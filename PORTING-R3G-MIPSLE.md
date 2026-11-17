# HomeProxy 0.4.9：小米 R3G / MT7621 MIPSLE 适配说明

## 基线

- 上游仓库：`weicaixian86/luci-app-homeproxy`
- 基线标签：`0.4.9`
- 基线提交：`be57aa61e2e97ba262ac427d276a0a1702e331f8`
- 目标设备：小米 R3G，MediaTek MT7621A
- 目标系统：OpenWrt 25.12.x，`ramips/mt7621`
- 目标 Go：`GOOS=linux GOARCH=mipsle GOMIPS=softfloat`

## 变更概要

1. `update_core.sh` 恢复 MIPSLE 运行时资产选择，并使用现有 `CORE_SHA256_MIPSLE` 常量校验下载文件。
2. GitHub Actions 增加 `mipsle` 构建矩阵，生成 MIPSLE-musl tarball、SHA256、离线部署 ZIP，并注入自动更新校验值。
3. MIPSLE 保留 QUIC、WireGuard、uTLS、Clash API、Tailscale 等常用 build tags，但不带 `with_ebpf` 和 `with_gvisor`。Cilium ebpf-go 不支持 32 位架构；gVisor 项目目前只支持 amd64/arm64。
4. LuCI 仅在核心 `Tags:` 声明 `with_ebpf` 时显示 eBPF 模式。生成器与两个防火墙脚本对从其他设备导入的 eBPF 配置统一回退到 `redirect_tproxy`。
5. 部署脚本在停止服务、改动 APK 或覆盖核心前，先执行随包 `sing-box version`，核对设备架构和 `1.14.4-reF1nd` 版本，减少错装 AMD64/ARM64 核心的风险。
6. 文档与静态测试增加 MIPSLE 构建目标、软浮点 ABI 和 eBPF 限制说明。

## MIPSLE 的功能边界

MIPSLE 构建不编入 `with_ebpf` 或 `with_gvisor`。Cilium ebpf-go 上游明确说明 32 位架构不在其支持范围内；gVisor 上游文档列出的 CPU 架构是 x86_64/AMD64 与 ARM64。因而本适配不向 MT7621 暴露 eBPF 模式，也不编入 gVisor Tun stack；使用 nftables Redirect/TProxy 等常规路径。

MIPSLE 保留 `with_tailscale`、`with_ccm`、`with_ocm`、`with_cloudflared`、`with_usbip`、`with_openvpn`、`with_openconnect` 等现有项目标签；官方 Tailscale 发行物也提供 `mipsle` 静态构建。省略 `with_ebpf` 和 `with_gvisor`。`with_naive_outbound` 仍沿用项目当前构建流程的做法，不编入静态发行包。

## 应用补丁

在已克隆并切换到 `0.4.9` 的仓库中执行：

```sh
git switch -c r3g-mipsle 0.4.9
git apply homeproxy-0.4.9-r3g-mipsle.patch
git diff --check
sh -n deploy/install.sh
sh -n luci-app-homeproxy/root/etc/homeproxy/scripts/update_core.sh
sh tools/tests/run.sh
```

## 用 GitHub Actions 构建

需要把修改推送到自己的 GitHub fork（不要尝试推送到上游仓库）：

```sh
git add .
git commit -m "Add MIPSLE softfloat build for Xiaomi R3G"

# 将 origin 改为你自己的 fork 地址后推送分支
# git remote set-url origin https://github.com/<你的 GitHub 用户名>/luci-app-homeproxy.git
git push -u origin r3g-mipsle
```

在自己 fork 的 GitHub 仓库中启用 Actions，然后打开 **Build & Release All-in-One**，使用 `workflow_dispatch`，版本标签填写一个尚不存在的新版本，例如 `0.4.10`。不要复用 `0.4.9`，工作流会拒绝覆盖已有 tag/Release。

若 MIPSLE 编译成功，Release 应包含：

- `luci-app-homeproxy_0.4.10-all.apk`
- `homeproxy-deploy_0.4.10-mipsle.zip`
- `sing-box-1.14.4-reF1nd_0.4.10-linux-mipsle-musl.tar.gz`
- `sha256sums-0.4.10.txt`

工作流将把 `REFIND_REPO` 设置为当前 fork，因此路由器的“更新内核”也会从这个 fork 的 Release 获取资产。

## 路由器安装前检查

小米 R3G 当前 `/overlay` 可用空间曾报告只有约 5.7 MB，而现有 `/usr/bin/sing-box` 的 `du` 显示约 97.5 MB。两项数据需要在实际设备上再次核实；空间不足时不要直接安装。建议先检查：

```sh
uname -m
apk --print-arch
sing-box version
df -h /overlay /tmp /usr/bin
ls -lh /usr/bin/sing-box
```

由于 MIPSLE 核心解压后可能接近 100 MB，而 R3G 的 `/tmp` 空间有限，ZIP 先传到 `/tmp`，只解压 APK 和脚本。`install.sh` 会先校验上级 ZIP 的完整性和 ELF32 小端 MIPS 头；然后通过 `unzip -p` 将 `sing-box` 流式写入 `/usr/bin/sing-box`，不在 `/tmp` 保存第二份解压内核。安装后应检查 `sing-box version` 的环境为 `linux/mipsle`，并确认 `Tags:` 不包含 `with_ebpf`。

## 验证状态

当前源码修改已通过本机 449 项静态测试、Shell 语法检查、JavaScript 语法检查和 GitHub Actions YAML 解析。另用本机 Go 1.23.2 对最小程序执行 `GOOS=linux GOARCH=mipsle GOMIPS=softfloat CGO_ENABLED=0` 交叉编译，产物被 `readelf` 确认为 ELF32、小端、MIPS。这个 smoke test 只验证 Go 工具链目标有效，不代表完整 sing-box 依赖已成功编译。此处尚未在 GitHub Actions 上实际执行 reF1nd sing-box 的完整 MIPSLE 交叉编译，也尚未在 Xiaomi R3G 实机验证；只有 Actions 成功并在设备上通过运行测试后，才能将构建标记为可用。
