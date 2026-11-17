#!/bin/sh
# =============================================================================
# HomeProxy 一体化部署脚本
#   本目录必须包含：
#     - luci-app-homeproxy_<版本>-all.apk         （本仓库 CI 编译的 all 架构包）
#       IPK（OpenWrt 24.10 及更早）已不再提供：那些版本内核过低，启用不了 eBPF，请升级到 25.12。
#     - sing-box                 （打补丁的 reF1nd 内核，版本为 1.14.4-reF1nd_<插件版本>）
#     - install.sh / README.md   （本脚本与说明）
#
# 用法（在路由器上，本脚本所在目录内执行）：
#   sh install.sh
#
# 它会：完成架构/版本/包文件预检 → 停服务 → 原位升级 luci → 铺设核心 → 启动。
# 反复执行等价于升级；apk 原位升级，不主动卸载旧包或删除配置。
# =============================================================================
set -e

self="$(cd "$(dirname "$0")" && pwd)"
cd "$self"

echo "===== HomeProxy 一体化部署 ====="
echo "工作目录: $self"

# ---- 0. 预检核心架构和版本（必须在停止服务/修改包之前完成） -------------------
case "$(uname -m)" in
  mipsel*) EXPECTED_GO_ARCH="linux/mipsle" ;;
  mips)
    # uname -m 在部分 MIPSLE OpenWrt 上只显示 mips，必须再判定大小端。
    pkg_arch="$(apk --print-arch 2>/dev/null || true)"
    case "$pkg_arch" in
      mipsel*) EXPECTED_GO_ARCH="linux/mipsle" ;;
      mips*)   EXPECTED_GO_ARCH="" ;;
      *)
        # apk 不可用/未返回架构时，读取当前 shell ELF 的 EI_DATA（偏移 5）：1=小端。
        mips_ei_data="$(dd if=/proc/self/exe bs=1 skip=5 count=1 2>/dev/null | od -An -tu1 2>/dev/null | tr -d '[:space:]')"
        [ "$mips_ei_data" = "1" ] && EXPECTED_GO_ARCH="linux/mipsle" || EXPECTED_GO_ARCH=""
        ;;
    esac
    ;;
  x86_64)  EXPECTED_GO_ARCH="linux/amd64" ;;
  aarch64) EXPECTED_GO_ARCH="linux/arm64" ;;
  *)       EXPECTED_GO_ARCH="" ;;
esac
if [ -z "$EXPECTED_GO_ARCH" ]; then
  echo ":: 错误：暂不支持当前设备架构/字节序：$(uname -m)（仅支持 x86_64、aarch64、MIPSLE）"
  exit 1
fi

CORE_FROM_ARCHIVE=0
CORE_ARCHIVE="$self.zip"
CORE_INFO=""
CORE_ARCHIVE_VERSION=""
if [ -x ./sing-box ]; then
  CORE_INFO="$(./sing-box version 2>&1)" || {
    echo ":: 错误：随包 sing-box 无法在当前路由器执行："
    echo "$CORE_INFO"
    echo "   请确认 ZIP 后缀与路由器 CPU 架构一致。"
    exit 1
  }
  if ! printf '%s\n' "$CORE_INFO" | grep -Fq "$EXPECTED_GO_ARCH"; then
    echo ":: 错误：内核架构与当前设备不匹配。"
    echo "   当前设备: $(uname -m)；需要: $EXPECTED_GO_ARCH"
    printf '%s\n' "$CORE_INFO" | sed -n '1,4p'
    echo "   未停止服务、未修改软件包、未覆盖现有内核。"
    exit 1
  fi
  if ! printf '%s\n' "$CORE_INFO" | head -n1 | grep -q '1.14.4-reF1nd'; then
    echo ":: 错误：内核版本不是本项目要求的 1.14.4-reF1nd。"
    printf '%s\n' "$CORE_INFO" | sed -n '1,3p'
    exit 1
  fi
elif [ "$EXPECTED_GO_ARCH" = "linux/mipsle" ] && [ -f "$CORE_ARCHIVE" ] && command -v unzip >/dev/null 2>&1; then
  # R3G 的 /tmp 空间可能不足以同时保存压缩 ZIP 和约 100 MB 的解压核心。
  # 只把小文件解压到工作目录，核心从同级 ZIP 通过 unzip -p 流式写入目标文件。
  archive_name="${CORE_ARCHIVE##*/}"
  case "$archive_name" in
    homeproxy-deploy_*-mipsle.zip) ;;
    *) echo ":: 错误：用于流式安装的归档文件名必须以 -mipsle.zip 结尾。"; exit 1 ;;
  esac
  CORE_ARCHIVE_VERSION="${archive_name#homeproxy-deploy_}"
  CORE_ARCHIVE_VERSION="${CORE_ARCHIVE_VERSION%-mipsle.zip}"
  if [ -z "$CORE_ARCHIVE_VERSION" ] || [ "$CORE_ARCHIVE_VERSION" = "$archive_name" ]; then
    echo ":: 错误：无法从 MIPSLE 部署 ZIP 解析版本号。"
    exit 1
  fi
  if ! unzip -t "$CORE_ARCHIVE" >/dev/null 2>&1; then
    echo ":: 错误：MIPSLE 部署 ZIP 完整性校验失败。"
    exit 1
  fi
  header_file="/tmp/homeproxy-core-elfhdr.$$"
  if ! unzip -p "$CORE_ARCHIVE" sing-box 2>/dev/null | dd of="$header_file" bs=1 count=20 2>/dev/null; then
    rm -f "$header_file"
    echo ":: 错误：无法从部署 ZIP 读取 sing-box ELF 头。"
    exit 1
  fi
  set -- $(od -An -tu1 "$header_file" 2>/dev/null)
  rm -f "$header_file"
  if [ "$#" -ne 20 ] || [ "$1" != 127 ] || [ "$2" != 69 ] || [ "$3" != 76 ] || [ "$4" != 70 ] || \
     [ "$5" != 1 ] || [ "$6" != 1 ] || [ "$19" != 8 ] || [ "$20" != 0 ]; then
    echo ":: 错误：ZIP 内 sing-box 不是 ELF32 little-endian MIPS（MIPSLE）内核。"
    echo "   未停止服务、未修改软件包、未覆盖现有内核。"
    exit 1
  fi
  CORE_FROM_ARCHIVE=1
  echo "==> MIPSLE ZIP 预检通过：版本标签 $CORE_ARCHIVE_VERSION；核心将从 ZIP 流式安装。"
else
  echo ":: 错误：当前目录没有可执行的 ./sing-box，也没有可用的同名 MIPSLE 部署 ZIP。"
  echo "   若要节省 /tmp 空间，请保留 ${self##*/}.zip，并只解压 APK、install.sh 和 README.md。"
  exit 1
fi
if [ "$CORE_FROM_ARCHIVE" = "0" ]; then
  echo "==> 核心预检通过: $EXPECTED_GO_ARCH"
  printf '%s\n' "$CORE_INFO" | sed -n '1,3p'
fi

# ---- 1. 识别包管理器 --------------------------------------------------------
if command -v apk >/dev/null 2>&1; then
  PKG=apk
  PKG_INSTALL="apk add --allow-untrusted --upgrade"
elif command -v opkg >/dev/null 2>&1; then
  echo ":: 错误：检测到 opkg（旧版 OpenWrt）。本部署包仅提供 OpenWrt 25.12+ 使用的 .apk。"
  echo "   请使用与你当前固件匹配的旧版 IPK，或升级到 OpenWrt 25.12+。"
  exit 1
else
  echo ":: 错误：未找到 apk 包管理器，无法安装 luci。"
  echo "   本版本仅支持 OpenWrt 25.12（apk）。"
  exit 1
fi
echo "==> 包管理器: $PKG"

# ---- 2. 确认部署包文件及版本（在停止服务前完成） ----------------------------
case "$PKG" in
  apk)  PKG_EXT="apk" ;;
  *)    PKG_EXT="" ;;
esac
PKG_FILE=""
if [ -n "$PKG_EXT" ]; then
  PKG_FILE="$(ls ./luci-app-homeproxy*.${PKG_EXT} 2>/dev/null | head -n1)"
fi
if [ -z "$PKG_FILE" ]; then
  echo ":: 错误：当前目录缺少 luci-app-homeproxy*.${PKG_EXT}"
  echo "   本版本仅提供 .apk（OpenWrt 25.12）。"
  exit 1
fi
if [ "$CORE_FROM_ARCHIVE" = "1" ]; then
  apk_name="${PKG_FILE##*/}"
  apk_version="${apk_name#luci-app-homeproxy_}"
  apk_version="${apk_version%-all.apk}"
  if [ "$apk_version" != "$CORE_ARCHIVE_VERSION" ]; then
    echo ":: 错误：部署 ZIP 版本（$CORE_ARCHIVE_VERSION）与 LuCI APK 版本（$apk_version）不一致。"
    echo "   未停止服务、未修改软件包、未覆盖现有内核。"
    exit 1
  fi
fi

# ---- 3. 停止 homeproxy 服务 --------------------------------------------------
echo "==> [1/5] 停止 homeproxy 服务"
/etc/init.d/homeproxy stop 2>/dev/null || true
sleep 1

# ---- 4. 安装 / 升级 luci-app-homeproxy --------------------------------------
echo "==> [2/5] 安装 luci-app-homeproxy（自动解决依赖，需联网或已配置软件源）"
# 使用 apk upgrade 原位升级，避免先卸载现有 LuCI 后因依赖/源故障留下半套环境。
if ! $PKG_INSTALL "$PKG_FILE"; then
  echo ":: 错误：LuCI 安装失败（可能是软件源不可用或依赖缺失）。"
  echo "   已停止部署；当前 sing-box 核心尚未覆盖。请修复 APK 源后重试。"
  exit 1
fi

# ---- 5. 部署打补丁的 sing-box 内核 ------------------------------------------
echo "==> [3/5] 部署打补丁的 sing-box 内核（版本 1.14.4-reF1nd_<插件版本>）"
if [ "$CORE_FROM_ARCHIVE" = "1" ]; then
  # ZIP 已通过完整性检查，且 ELF 头已确认为 MIPSLE。直接重定向到现有文件，
  # 避免在 /tmp 或 overlay 临时保存第二份近 100 MB 的展开文件。
  if ! unzip -p "$CORE_ARCHIVE" sing-box > /usr/bin/sing-box; then
    echo ":: 错误：从部署 ZIP 写入 sing-box 失败。"
    exit 1
  fi
  chmod 0755 /usr/bin/sing-box
else
  install -m 0755 ./sing-box /usr/bin/sing-box
fi
chown root:root /usr/bin/sing-box
INSTALLED_CORE_INFO="$(/usr/bin/sing-box version 2>&1)" || {
  echo ":: 错误：安装后的 sing-box 无法执行："
  echo "$INSTALLED_CORE_INFO"
  exit 1
}
if ! printf '%s\n' "$INSTALLED_CORE_INFO" | grep -Fq "$EXPECTED_GO_ARCH" || \
   ! printf '%s\n' "$INSTALLED_CORE_INFO" | head -n1 | grep -q '1.14.4-reF1nd'; then
  echo ":: 错误：安装后的 sing-box 架构或版本校验失败："
  printf '%s\n' "$INSTALLED_CORE_INFO" | sed -n '1,4p'
  exit 1
fi

# ---- 6. 启用并启动，刷新 LuCI 缓存 ------------------------------------------
echo "==> [4/5] 启用并启动 homeproxy"
/etc/init.d/homeproxy enable 2>/dev/null || true
/etc/init.d/homeproxy start
sleep 2
# 让 LuCI 重新扫描到新装的 app
rm -rf /tmp/luci-indexcache /tmp/luci-modulecache 2>/dev/null || true
/etc/init.d/uhttpd restart 2>/dev/null || true
# rpcd 只在启动时加载 /usr/share/rpcd/ucode/*.uc，不重启就仍是旧方法表：
# 新版本新增的 RPC（如 dns_server_test 延迟测试）会一律报 Method not found。
/etc/init.d/rpcd restart 2>/dev/null || service rpcd restart 2>/dev/null || true

echo ""
echo "===== 部署完成，开始校验 ====="
echo "-- sing-box 版本（应为 1.14.4-reF1nd_<插件版本>，如 1.14.4-reF1nd_0.4.0；下载跳过条件只比对下划线前的基础版本）--"
/usr/bin/sing-box version 2>/dev/null || echo "(sing-box version 读取失败)"
echo ""
echo "-- 配置里是否生成 proxy_providers（内核补丁生效标志）--"
grep -A2 proxy_providers /var/run/homeproxy/sing-box-c.json 2>/dev/null \
  || echo "(配置尚未生成：请到面板『保存并应用』一次，再重启 homeproxy 后重试)"
echo ""
echo "提示："
echo "  1) 面板『更新内核』指向本次发布标签的 Release（如 0.1.01，含补丁内核）："
echo "     amd64/arm64/mipsle 会从你的仓库拉对应补丁版；MIPSLE 不含 eBPF。"
echo "  2) 要升级内核/面板时，重新跑本脚本即可（它会再次覆盖 /usr/bin/sing-box 并重装 luci）。"
echo "  3) 面板『代理供应商』页应列出每个订阅的节点/用量/到期；"
echo "     『概览/连接/日志』三个实时页（WebSocket）也应恢复正常。"
