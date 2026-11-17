# HomeProxy 一体化部署包（luci + 打补丁内核）

本 ZIP 由 GitHub Actions 自动构建，内含：

- `luci-app-homeproxy_<版本>-all.apk` —— 本仓库用 OpenWrt 25.12 SDK 编译的 **all 架构** luci 包（含中文 lmo）
  （IPK / OpenWrt 24.10 及更早已不再提供：内核过低，启用不了 eBPF）
- `sing-box` —— **打过补丁的 reF1nd sing-box 1.14.4-reF1nd** 静态二进制（amd64/arm64 含 with_ebpf；mipsle 使用 softfloat 构建，不含 with_ebpf / with_gvisor）
- `install.sh` —— 一键部署脚本
- `README.md` —— 本说明

补丁让内核原生支持 `proxy_providers` 配置与 `/providers/proxies` API，
实现与 Mihomo / OpenClash 一样的「无损对接 Zashboard 面板」（含 WebSocket 实时页）。

---

## 一、怎么拿到这个 ZIP（在 GitHub 上自动编译）

1. 打开你的仓库 **Actions** 页面：
   `https://github.com/<你>/luci-app-homeproxy/actions`
2. 选择工作流 **Build & Release All-in-One** → **Run workflow**
3. 填写：
   - `tag`：版本号，例如 `0.1.01`（建议不带 `v` 前缀；它就是 Release 标签与包版本）
   - `description`：Release 描述（可选）
4. 等待所有 job 完成（luci 编译 + amd64/arm64/mipsle 三个架构内核 + 打包；耗时以 Actions 实际排队和编译时间为准）
5. 到 **Releases** 页面，该版本只有一个 Release（标签即你填的版本号），内含：
   - `homeproxy-deploy_<ver>-amd64.zip` / `-arm64.zip` / `-mipsle.zip`：各架构一体化部署包（命名与 luci 包一致：版本号在前、架构在后）
   - `luci-app-homeproxy_<ver>-all.apk`：独立 luci 包（不含内核，装后自动下载）
   - `sing-box-1.14.4-reF1nd_<版本>-linux-*-musl.tar.gz`：打补丁内核（供「更新内核」自动下载）

> 说明：luci 包是架构无关的（all），每个 zip 只是内核二进制不同。
> 一个版本 = 一个 Release 标签（如 `0.1.01`），所有产物都在里面。

---

## 二、安装（传到路由器 tmp，一条命令装好）

```bash
# 小米 R3G / MT7621 示例
scp homeproxy-deploy_0.1.01-mipsle.zip root@路由器IP:/tmp/
ssh root@路由器IP

# 保留 ZIP，只解压 APK 和脚本；sing-box 通过 unzip -p 流式安装，不产生第二份大文件
cd /tmp
mkdir -p homeproxy-deploy_0.1.01-mipsle
cd homeproxy-deploy_0.1.01-mipsle
unzip -o ../homeproxy-deploy_0.1.01-mipsle.zip 'luci-app-homeproxy_*.apk' install.sh README.md
sh install.sh
```

`install.sh` 会自动：预检内核架构 → 停服务 → 用 apk 升级 luci（自动解决依赖，需联网或已配源）→
从上级 ZIP 流式写入打补丁内核到 `/usr/bin/sing-box` → 校验版本 → 启动 homeproxy → 刷新 LuCI 缓存。amd64/arm64 也可完整解压后运行。

---

## 三、架构对照表

| ZIP 后缀   | 适用 `uname -m`        | 典型设备 |
|------------|------------------------|----------|
| `amd64`    | `x86_64`               | x86 软路由、虚拟机 |
| `arm64`    | `aarch64`              | ARM64 软路由、N1、R2S 等 |
| `mipsle`   | `mips`（小端）         | 小米 R3G / MT7621 等 MIPSLE 设备 |

> MIPSLE 使用 `GOARCH=mipsle` + `GOMIPS=softfloat`，不编入 `with_ebpf`（32 位 eBPF Go 库不受支持）和 `with_gvisor`（gVisor 当前仅支持 amd64/arm64）；保留其余 MIPSLE 可用的构建标签。面板只显示当前核心支持的代理模式。大端 MIPS、ARMv5/6/7 暂不构建。

`install.sh` 会在停止服务或修改软件包之前执行内核架构与版本预检；选错 ZIP 会直接退出，不覆盖当前核心。

---

## 四、重要注意事项

1. **面板「更新内核」可用且安全（已发布架构）**：`update_core.sh` 的 `REFIND_REPO` 在 CI 构建时改写为当前仓库
   （`${GITHUB_REPOSITORY}`），`REFIND_TAG` 在构建时被改写为该版本的 Release 标签
   （如 `0.4.10`），里面是**带补丁**的内核。点「更新内核」会从同一个 Release 拉补丁版，不会丢补丁；
   amd64 / arm64 / mipsle 已纳入自动下载；大端 mips 与 ARMv5/6/7 暂未构建。
   ⚠️ 不要删除已发布的 Release——旧版 luci 的自动下载仍指向它。
2. **版本钉死的意义**：二进制版本号被编译为 `1.14.4-reF1nd_<插件版本>`（如 `1.14.4-reF1nd_0.4.0`），
   `update_core.sh` 的 `ensure_core` 只比对 `_` 之前的基础版本 `1.14.4-reF1nd`，因此会判定
   「已是最新」并**跳过下载**，从而保留补丁。若用裸 `go build` 编译导致版本为 `unknown`，
   会被判定需更新而被覆盖。
3. **luci 依赖**：`apk add` 会自动拉 `firewall4 / dnsmasq-full / kmod-tun /
   kmod-nft-tproxy / curl / jsonfilter / ucode-*` 等；若你的镜像缺少源，安装会警告，
   需先配好软件源或手动补齐依赖，否则面板/分流不可用。
4. **仅支持 OpenWrt 25.12+（apk）**：每个 zip 内含 `.apk`，`install.sh` 直接安装，无需额外操作。
   同一 Release 也单独提供 `luci-app-homeproxy_<ver>-all.apk`，可直接
   `apk add --allow-untrusted` 安装后再走自动下载内核。**24.10 及更早（opkg/ipk）不再支持**：
   内核过低，启用不了 eBPF 透明代理，请升级系统。

---

## 五、验证

部署后：

```bash
sing-box version                                  # 应显示 1.14.4-reF1nd_<插件版本>
grep proxy_providers /var/run/homeproxy/sing-box-c.json   # 应有内容
curl -s -H "Authorization: Bearer homeproxy" http://127.0.0.1:9090/providers/proxies  # 返回供应商列表
```

面板上：「代理供应商」页出数据；「概览 / 连接 / 日志」实时页恢复。

---

## 六、内核构建参数（可复现）

```
CGO_ENABLED=0 GOOS=linux GOARCH=<arch> [GOMIPS=softfloat for mipsle] \
go build -trimpath -o sing-box \
  -tags "<matrix-specific build tags; omit with_ebpf on mipsle>" \
  -ldflags "-X 'github.com/sagernet/sing-box/constant.Version=1.14.4-reF1nd' -X runtime.godebugDefault=multipathtcp=0,tlssha1=1 -s -w -buildid=" \
  ./cmd/sing-box
```

（注：刻意去掉了 `with_naive_outbound`，因其依赖 cronet-go 的 musl 预编译 C 库，
无法纯静态编；naive 代理在 homeproxy 订阅中基本不会用到，去掉无影响。）
