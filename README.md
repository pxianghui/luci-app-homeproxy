# HomeProxy for OpenWrt
适用于 OpenWrt 的 HomeProxy LuCI 管理界面，完美适配Clash API面板（基于 immortalwrt/homeproxy 修改）。

## 版本说明
支持架构：amd64 / arm64 / mipsle

> OpenWrt **24.10 及更早不再提供安装包**：本项目发布 APK，适用于 OpenWrt 25.12 系。MIPSLE 核心不编入 `with_ebpf` / `with_gvisor`，使用 Redirect/TProxy/Tun 等常规模式。

luci-app-homeproxy_<版本>-all.apk OpenWrt 25.12 版本 LUCI 安装包  
sing-box-1.14.4-reF1nd_<版本>-linux-amd64-musl.tar.gz AMD64 带补丁内核（含 with_ebpf）
sing-box-1.14.4-reF1nd_<版本>-linux-mipsle-musl.tar.gz MIPSLE softfloat 内核（不含 with_ebpf）
homeproxy-deploy_<版本>-mipsle.zip 小米 R3G / MT7621 离线安装包（含 LUCI 与匹配内核）

## 界面截图
| 客户端设置 | 节点设置 |
| --- | --- |
| ![服务状态](png/1.png) | ![节点设置](png/2.png) |
| 配置文件 | 服务状态 |
| ![配置文件](png/3.png) | ![客户端设置](png/4.png) |
| 运行日志 | 控制面板 |
| ![节点列表](png/5.png) | ![运行日志](png/6.png) |

> 截图中的地址、节点与订阅信息均为示例环境。

## 一、安装
### 方式一：安装 APK，内核自动下载（推荐，在线）
适合能联网、已配置软件源的路由器。装好面板后，打补丁的 reF1nd 内核会按设备架构自动下载并安装。
1. 到 Releases 下载 **OpenWrt 25.12** 的包（`<版本>` 替换成实际发布号，如 `0.4.6`）：
   - OpenWrt **25.12** → `luci-app-homeproxy_<版本>-all.apk`
2. 上传到路由器 `/tmp` 后安装：
   ```sh
   apk --update-cache add --allow-untrusted /tmp/luci-app-homeproxy_<版本>-all.apk
   ```
3. 首次启动服务时，插件会按架构自动下载并安装 reF1nd sing-box 内核（`1.14.4-reF1nd`，含 Clash API/proxy-providers 补丁；amd64/arm64 含 eBPF，MIPSLE 不含 eBPF / gVisor）；也可以在 LuCI 状态页「sing-box 内核管理」中手动点「下载 / 更新内核」。
### 方式二：下载 ZIP 离线安装（含内核，无需额外下载）
适合无法联网拉取内核、或希望一次性铺好「面板 + 内核」的路由器。每个架构一个 zip，内含 luci 包（`.apk`）、打补丁内核 `sing-box`、`install.sh` 与说明。
1. 到 Releases 下载对应架构的 zip（按 `uname -m` 选择；`<版本>` 为实际发布号）：
   - `x86_64`  → `homeproxy-deploy_<版本>-amd64.zip`
   - `aarch64` → `homeproxy-deploy_<版本>-arm64.zip`
   - `mips`（小端、如 MT7621）→ `homeproxy-deploy_<版本>-mipsle.zip`（Go `linux/mipsle`，softfloat；不含 `with_ebpf`）
2. 小米 R3G / MT7621 建议采用流式安装：ZIP 保留在 `/tmp`，只解压 APK 和脚本，避免把约 97 MB 的内核再复制一份到 tmpfs：
   ```sh
   cd /tmp
   mkdir -p homeproxy-deploy_<版本>-mipsle
   cd homeproxy-deploy_<版本>-mipsle
   unzip -o ../homeproxy-deploy_<版本>-mipsle.zip 'luci-app-homeproxy_*.apk' install.sh README.md
   sh install.sh
   ```
   安装脚本会从同目录名对应的上级 ZIP 中流式读取 `sing-box`，写入 `/usr/bin/sing-box`。其他架构也可以完整解压后执行 `sh install.sh`。
3. `install.sh` 会自动执行：停服务 → 安装 luci（apk 自动解决依赖，需联网或已配源）→ 铺设 `/usr/bin/sing-box` 内核 → 启动服务 → 刷新 LuCI。升级时重新跑本脚本即可（会再次覆盖内核并重装 luci）。
> 两种方式下内核版本都钉死为 `1.14.4-reF1nd_<插件版本>`（打过补丁），因此 `ensure_core` 会判定「已是最新」并跳过下载，从而保留补丁。

## 二、卸载
### OpenWrt 24.10（`opkg`）
```sh
# 1) 停用并移除软件包（会卸载 menu/acl/rpcd/脚本等已登记文件）
/etc/init.d/homeproxy stop 2>/dev/null || true
/etc/init.d/homeproxy disable 2>/dev/null || true
opkg remove luci-app-homeproxy 2>/dev/null || true
# 2) 清理 opkg 不会删的残留（保留规则集 /etc/homeproxy/ruleset 与面板 /etc/homeproxy/run/ui）
rm -rf /etc/config/homeproxy
# 只删程序文件，保留 ruleset/(规则集) 与 run/ui/(面板)：
rm -rf /etc/homeproxy/scripts
rm -rf /etc/homeproxy/resources
rm -f  /etc/capabilities/homeproxy.json
rm -f  /etc/uci-defaults/luci-homeproxy
rm -f  /etc/uci-defaults/luci-homeproxy-migration
rm -f  /www/luci-static/resources/homeproxy.js
rm -rf /www/luci-static/resources/view/homeproxy
rm -f  /usr/share/luci/menu.d/luci-app-homeproxy.json
rm -f  /usr/share/rpcd/acl.d/luci-app-homeproxy.json
rm -f  /usr/share/rpcd/ucode/luci.homeproxy
rm -f  /usr/lib/lua/luci/i18n/homeproxy.zh-cn.lmo
rm -f  /usr/bin/sing-box
# 3) 删除 homeproxy 下发的定时任务行，并移除 sing-box 专用用户/组
sed -i '/homeproxy/d' /etc/crontabs/root 2>/dev/null
/etc/init.d/cron restart 2>/dev/null || true
deluser sing-box 2>/dev/null || true
delgroup sing-box 2>/dev/null || true
# 4) 清 LuCI 缓存并重启 Web 服务
rm -f  /tmp/luci-indexcache
rm -rf /tmp/luci-modulecache/* 2>/dev/null
/etc/init.d/rpcd restart
/etc/init.d/uhttpd restart
```

### OpenWrt 25.12（`apk`）
```sh
# 1) 停用并移除软件包
/etc/init.d/homeproxy stop 2>/dev/null || true
/etc/init.d/homeproxy disable 2>/dev/null || true
apk del luci-app-homeproxy 2>/dev/null || true
# 2) 清理 apk 不会删的残留（保留规则集 /etc/homeproxy/ruleset 与面板 /etc/homeproxy/run/ui）
rm -rf /etc/config/homeproxy
# 只删程序文件，保留 ruleset/(规则集) 与 run/ui/(面板)：
rm -rf /etc/homeproxy/scripts
rm -rf /etc/homeproxy/resources
rm -f  /etc/capabilities/homeproxy.json
rm -f  /etc/uci-defaults/luci-homeproxy
rm -f  /etc/uci-defaults/luci-homeproxy-migration
rm -f  /www/luci-static/resources/homeproxy.js
rm -rf /www/luci-static/resources/view/homeproxy
rm -f  /usr/share/luci/menu.d/luci-app-homeproxy.json
rm -f  /usr/share/rpcd/acl.d/luci-app-homeproxy.json
rm -f  /usr/share/rpcd/ucode/luci.homeproxy
rm -f  /usr/lib/lua/luci/i18n/homeproxy.zh-cn.lmo
rm -f  /usr/bin/sing-box
# 3) 删除定时任务行，并移除 sing-box 专用用户/组
sed -i '/homeproxy/d' /etc/crontabs/root 2>/dev/null
/etc/init.d/cron restart 2>/dev/null || true
deluser sing-box 2>/dev/null || true
delgroup sing-box 2>/dev/null || true
# 4) 清 LuCI 缓存并重启 Web 服务
rm -f  /tmp/luci-indexcache
rm -rf /tmp/luci-modulecache/* 2>/dev/null
/etc/init.d/rpcd restart
/etc/init.d/uhttpd restart
```
> 说明：
> - 卸载时忽略面板、规则集、配置文件。


## 三 、常见问题
1. **面板下载失败**
   - 客户端设置 → 点「更新面板」手动触发；
   - 或手动下载 ZIP 上传：`https://github.com/Zephyruso/zashboard/releases/latest/download/dist.zip`，客户端设置 → 点「上传面板ZIP」。
2. **远程规则集是否下载成功**
   面板查看，有即成功或者SSH 查看 `/etc/homeproxy/ruleset/`，否则检查规则集远程连接。
3. **sing-box 内核未安装或下载失败**
   服务状态 → 「sing-box 内核管理」查看架构与目标版本；显示"未安装"则点「下载 / 更新内核」。日志：`/var/run/homeproxy/core_download.log`。若当前架构 reF1nd 暂未发布，请等作者更新。
4. **装新包后页面仍是旧文字**
   清浏览器缓存，或执行：
   ```sh
   rm -f /tmp/luci-indexcache
   rm -rf /tmp/luci-modulecache/*
   /etc/init.d/rpcd restart
   /etc/init.d/uhttpd restart
   ```

## 四、感谢作者
- immortalwrt：https://github.com/immortalwrt/homeproxy
- reF1nd（sing-box 内核基础源码）：https://github.com/reF1nd/sing-box （v1.14.4-reF1nd）
- MIPSLE：Go `GOARCH=mipsle` + `GOMIPS=softfloat`；因 32 位 eBPF Go 库限制不编 `with_ebpf`，UI 会按核心 build tags 隐藏 eBPF 模式并对旧配置回退到 Redirect/TProxy。
