# TUN 拥塞控制（cubic / reno / bbr / bbr3）改动说明

> 目标仓库：Filterrr/FlClash（分支 `feat/mips-congestion-control`）
> 核心子模块：`core/Clash.Meta` = Filterrr/Clash.Meta `Alpha` 分支

## 背景

MIPS 是 **mihomo IP stack**（`github.com/metacubex/mipstack`）——mihomo 内置的用户态 TCP/IP 栈，
用于 TUN（`tun.stack: mips`）以及 WG 类出站的 `ip-stack.mode: mips`。

mipstack 内置 4 种 TCP 拥塞控制：`cubic` / `reno` / `bbr` / `bbr3`（BBR v3）。

上游 mihomo 在提交 `63bd52e`（"chore: change default IP stack mode to mips and support
`congestion-controller` option for tun"）中已把该能力打通到 TUN 配置，本项目使用该**上游原生实现**，
核心侧无需任何自研补丁：

| 核心侧位置 | 作用 |
|---|---|
| `config/config.go` (`RawTun`) | 新增 `congestion-controller` 字段并透传 |
| `listener/config/tun.go` | `Tun` 结构体新增字段并入相等性比较 |
| `hub/route/configs.go` | REST `tunSchema` 新增字段（支持 PATCH） |
| `listener/sing_tun/server.go` | 传入 `StackOptions.TCPCongestionControl` |
| `adapter/outbound/wireguard.go` | default `ip-stack.mode` 回落为 mips；校验 4 种取值 |

本分支的实际改动集中在 **Flutter 应用层**（把能力暴露给用户），以及把子模块指针切到包含该能力的 Alpha 提交。

## 本次改动（Flutter 层）

| 文件 | 改动 |
|---|---|
| `lib/enum/enum.dart` | 新增 `enum CongestionController { cubic, reno, bbr, bbr3 }` |
| `lib/models/clash_config.dart` | `Tun` 新增 `congestionController`（JSON 键 `congestion-controller`，默认 `bbr3`） |
| `lib/models/generated/clash_config.freezed.dart` | freezed 生成代码同步（getter / copyWith / == / hashCode / 构造 / toString） |
| `lib/models/generated/clash_config.g.dart` | json_serializable 生成代码同步（fromJson / toJson / `_$CongestionControllerEnumMap`） |
| `lib/fragments/config/network.dart` | 新增 `CongestionControllerItem` 选择器（仅 mips 栈时显示）；加入「网络」设置页 |
| `lib/fragments/dashboard/status_button.dart` | 仪表盘 TUN 弹层加入该选择器 |
| `lib/l10n/arb/intl_en.arb`、`intl_zh_CN.arb` | 新增 `congestionController`（"Congestion Controller" / "拥塞控制"） |
| `lib/l10n/l10n.dart`、`lib/l10n/intl/messages_en.dart`、`messages_zh_CN.dart` | 同步 l10n 生成代码 |
| `core/common.go` | FFI 配置覆盖时透传 `Tun.CongestionController` |
| `core/Clash.Meta`（子模块指针） | 指向 `Alpha`（含 `63bd52e` 原生支持） |
| `core/go.mod` / `core/go.sum` | `go mod tidy` 对齐到 Alpha 的依赖（mipstack 20260926 / sing-tun v0.4.26 等） |

> 生成代码由与仓库同版本的生成器产出并逐段比对确认：
> freezed 2.5.2 / json_serializable 6.8.0 / freezed_annotation 2.4.4 / json_annotation 4.9.0。

## 生效链路

```
Flutter Tun(congestionController = bbr3)
  → toJson: "tun": { ..., "congestion-controller": "bbr3" }
  → FFI updateConfig → json.Unmarshal(RawConfig)
  → overwriteConfig → executor.Parse → LC.Tun.CongestionController
  → sing-tun v0.4.26 StackOptions.TCPCongestionControl
  → mipstack 栈创建（校验 AvailableCongestionControls() = [bbr bbr3 cubic reno]）
```

运行时可通过 REST API PATCH `{"tun":{"congestion-controller":"bbr"}}` 热更（重启 TUN 后生效）。

## 配置示例

```yaml
tun:
  enable: true
  stack: mips                 # 仅 mips 栈生效
  congestion-controller: bbr3  # cubic / reno / bbr / bbr3，默认 bbr3
```

## 已验证

- 核心（`go build -tags with_gvisor`，go1.25.0 linux/arm64）：全量编译通过；`-buildmode=c-shared`（FlClash FFI 构建形态）亦通过；
- 栈级验收（sing-tun v0.4.26 + mipstack 20260926）：`bbr3 / bbr / cubic / reno` 全部接受，非法值报 `invalid TCP congestion control`；
- Dart 改动文件通过 Dart 3.9.4 解析器校验；ARB 文件 JSON 合法；
- 生成代码与同版本生成器输出逐段比对无差异；
- 端到端：`core/go.mod` 用 Alpha 依赖 `go mod tidy` 无报错。

## 构建

```bash
# 核心（Android 走 NDK）
cd core/Clash.Meta
CGO_ENABLED=0 go build -tags "with_gvisor" -o clash .

# Flutter 应用
flutter pub get
dart run build_runner build -d   # 可选：重建生成代码
flutter build apk
```
