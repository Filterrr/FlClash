//go:build android && cgo

package state

import "sync"

var DefaultIpv4Address = "172.19.0.1/30"
var DefaultDnsAddress = "172.19.0.2"
var DefaultIpv6Address = "fdfe:dcba:9876::1/126"

// DefaultMtu mirrors mihomo's TUN default and is applied when the user has
// not chosen a custom TUN MTU.
const DefaultMtu = 9000

type AndroidVpnOptions struct {
	Enable           bool           `json:"enable"`
	Port             int            `json:"port"`
	AccessControl    *AccessControl `json:"accessControl"`
	AllowBypass      bool           `json:"allowBypass"`
	SystemProxy      bool           `json:"systemProxy"`
	BypassDomain     []string       `json:"bypassDomain"`
	RouteAddress     []string       `json:"routeAddress"`
	Ipv4Address      string         `json:"ipv4Address"`
	Ipv6Address      string         `json:"ipv6Address"`
	DnsServerAddress string         `json:"dnsServerAddress"`
	FcmKeepAlive     bool           `json:"fcmKeepAlive"`
	Mtu              uint32         `json:"mtu"`
}

type AccessControl struct {
	Mode              string   `json:"mode"`
	AcceptList        []string `json:"acceptList"`
	RejectList        []string `json:"rejectList"`
	IsFilterSystemApp bool     `json:"isFilterSystemApp"`
}

type AndroidVpnRawOptions struct {
	Enable                  bool           `json:"enable"`
	AccessControl           *AccessControl `json:"accessControl"`
	AllowBypass             bool           `json:"allowBypass"`
	SystemProxy             bool           `json:"systemProxy"`
	RouteAddress            []string       `json:"routeAddress"`
	Ipv6                    bool           `json:"ipv6"`
	BypassDomain            []string       `json:"bypassDomain"`
	DisableICMPForwarding   bool           `json:"disableIcmpForwarding"`
	IcmpTimeout             int64          `json:"icmpTimeout"`
	FcmKeepAlive            bool           `json:"fcmKeepAlive"`
}

type State struct {
	AndroidVpnRawOptions
	CurrentProfileName string `json:"currentProfileName"`
}

var CurrentState = &State{}

// CurrentStateLock 保护 CurrentState。
//
// setState 由 Dart 的 FFI 调用线程整体覆盖 CurrentState,而 TUN 启动
// (startTUN -> tun.Start)与 getAndroidVpnOptions 会在其它 goroutine 读同一
// 结构体;没有同步时可能读到「一半新一半旧」的配置。
// 约定:读侧持 RLock 批量读完后立即释放,不要在持锁期间做耗时操作。
var CurrentStateLock sync.RWMutex

func GetIpv6Address() string {
	if CurrentState.Ipv6 {
		return DefaultIpv6Address
	} else {
		return ""
	}
}

func GetDnsServerAddress() string {
	return DefaultDnsAddress
}
