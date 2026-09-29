# MIPS 拥塞控制（默认 BBR v3）改动说明

> 基于 FlClash（Filterrr 分支，核心 submodule `core/Clash.Meta` = Filterrr/Clash.Meta Alpha，同步自上游 mihomo@5019cc0），参考 Bettbox（appshubcc/Bettbox）的拥塞控制实现移植。

## 背景

"MIPS" 即 **mihomo IP stack（`github.com/metacubex/mipstack`）**——mihomo 内置的用户态 TCP/IP 栈，用于：

1. **TUN**（`tun.stack: mips`，sing-tun 的 mipstack 后端）；
2. **WG 类出站**（WireGuard / ZeroTier / OpenVPN / MASQUE 的 `ip-stack.mode: mips`）。

mipstack 内置 4 种 TCP 拥塞控制：`cubic` / `reno` / `bbr` / `bbr3`（BBR v3）。原版 FlClash：
- TUN 无 `congestion-controller` 配置项，mipstack 默认回落 **CUBIC**，默认栈还是 gVisor；
- WG 类出站虽有 `ip-stack.congestion-controller`，但 `auto` 模式在带 `with_gvisor` 构建时优先 gVisor。

## 本次改动

### 核心（core/Clash.Meta，6 文件）

| 文件 | 改动 |
|---|---|
| `listener/config/tun.go` | `Tun` 结构体新增 `CongestionController`（`congestion-controller`），加入相等性比较 |
| `config/config.go` | `RawTun` 新增字段；`parseTun` 透传；**默认 TUN 栈 `gVisor`→`mips`，默认拥塞控制 `bbr3`** |
| `hub/route/configs.go` | REST API `tunSchema` 新增 `congestion-controller`（支持 PATCH 热更） |
| `listener/sing_tun/server.go` | `StackOptions.TCPCongestionControl = options.CongestionController` 传入 sing-tun |
| `docs/config.yaml` | TUN 段补 `congestion-controller: bbr3` 说明 |
| `go.mod/go.sum` | `sing-tun v0.4.24→v0.4.26`（引入 `TCPCongestionControl` 校验）、`mipstack 20260910→20260926`、`sing v0.5.7→v0.5.8`、`gvisor 20260826→20260922`（均与 Bettbox 对齐） |

另将 `adapter/outbound/wireguard.go` 的 `ipStackAuto` 回退恢复为 Bettbox 语义（mips 优先，不再被 `with_gvisor` 构建劫持）。

### Flutter 层（10 文件）

| 文件 | 改动 |
|---|---|
| `lib/enum/enum.dart` | 新增 `enum CongestionController { cubic, reno, bbr, bbr3 }` |
| `lib/models/clash_config.dart` | `Tun` 新增 `congestionController`（默认 `bbr3`）；默认 `stack` 改 `TunStack.mips` |
| `lib/models/generated/clash_config.freezed.dart` | 手工同步 freezed 生成代码（getter/copyWith/==/hashCode/构造/toString） |
| `lib/models/generated/clash_config.g.dart` | 手工同步 JSON 编解码 + `_$CongestionControllerEnumMap` |
| `lib/fragments/config/network.dart` | 新增 `CongestionControllerItem` 选择器（cubic/reno/bbr/bbr3） |
| `lib/fragments/dashboard/status_button.dart` | TUN 按钮弹层加入该选择器 |
| `lib/l10n/arb/intl_en.arb` / `intl_zh_CN.arb` / `lib/l10n/l10n.dart` / `lib/l10n/intl/messages_en.dart` / `messages_zh_CN.dart` | 新增 `congestionController`（"Congestion Controller" / "拥塞控制"） |

## 生效链路

```
Flutter Tun(congestionController=bbr3)
  → toJson: "tun": {"stack": "mips", "congestion-controller": "bbr3", ...}
  → FFI updateConfig → json.Unmarshal(RawConfig)
  → overwriteConfig → executor.Parse → LC.Tun.CongestionController
  → sing-tun v0.4.26 StackOptions.TCPCongestionControl
  → mipstack 栈创建（校验 AvailableCongestionControls() = [bbr bbr3 cubic reno]）
```

WG 类出站（`ip-stack.mode: mips`）走 `mipstack.Config.TCP.CongestionControl`，字段两侧本已就绪。

## 配置示例

```yaml
tun:
  enable: true
  stack: mips                # mips 栈才生效
  congestion-controller: bbr3 # cubic / reno / bbr / bbr3，默认 bbr3
```

不写 `congestion-controller` 时默认即 `bbr3`；运行时可通过 REST API PATCH `{"tun":{"congestion-controller":"bbr"}}` 热更（重启 TUN 生效）。

## 已验证

- `go build -tags with_gvisor` 全量编译通过（go1.25.0 linux/arm64）；
- `sing-tun` 直连测试：`bbr3/bbr/cubic/reno` 全部接受，非法值报 `invalid TCP congestion control`；
- 核心冒烟：REST PATCH `congestion-controller: bbr3/bbr` 均返回 204；
- 全部 Dart 改动文件通过 Dart 3.9.4 解析器（`dart format --output=none`）校验，括号平衡。

## 构建

```bash
# 核心（FlClash 使用 cgo 桥接，Android 构建走 NDK；此处为普通二进制）
cd core/Clash.Meta
CGO_ENABLED=0 go build -tags "with_gvisor" -o clash .

# Flutter 应用（需 Flutter SDK ≥ 项目要求）
flutter pub get
flutter build apk        # 或 flutter run
```

补丁文件：`/var/minis/workspace/patches/flclash-core-bbr3.patch`（核心 submodule）、
`/var/minis/workspace/patches/flclash-flutter-bbr3.patch`（宿主仓库 + core 桥接层 common.go）。
