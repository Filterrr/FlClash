//go:build android && cgo

package tun

import "C"
import (
	"core/state"
	"github.com/metacubex/mihomo/constant"
	"syscall"
	LC "github.com/metacubex/mihomo/listener/config"
	"github.com/metacubex/mihomo/listener/sing_tun"
	"github.com/metacubex/mihomo/log"
	"github.com/metacubex/mihomo/tunnel"
	"net"
	"net/netip"
)

type Props struct {
	Fd       int    `json:"fd"`
	Gateway  string `json:"gateway"`
	Gateway6 string `json:"gateway6"`
	Portal   string `json:"portal"`
	Portal6  string `json:"portal6"`
	Dns      string `json:"dns"`
	Dns6     string `json:"dns6"`
}

func Start(fd int, device string, stack constant.TUNStack, congestionController string, mtu uint32) (*sing_tun.Listener, error) {
	// Start 接管 fd 的所有权:调用方(Android VpnService 已 detachFd)不再关闭它,
	// 因此每个失败分支都必须自己关闭,否则每次启动失败都会泄漏一个隧道 fd。
	fail := func(err error) (*sing_tun.Listener, error) {
		_ = syscall.Close(fd)
		log.Errorln("startTUN error:", err)
		return nil, err
	}

	state.CurrentStateLock.RLock()
	ipv6 := state.CurrentState.Ipv6
	disableICMPForwarding := state.CurrentState.DisableICMPForwarding
	icmpTimeout := state.CurrentState.IcmpTimeout
	dnsServerAddress := state.GetDnsServerAddress()
	state.CurrentStateLock.RUnlock()

	var prefix4 []netip.Prefix
	tempPrefix4, err := netip.ParsePrefix(state.DefaultIpv4Address)
	if err != nil {
		return fail(err)
	}
	prefix4 = append(prefix4, tempPrefix4)
	var prefix6 []netip.Prefix
	if ipv6 {
		tempPrefix6, err := netip.ParsePrefix(state.DefaultIpv6Address)
		if err != nil {
			return fail(err)
		}
		prefix6 = append(prefix6, tempPrefix6)
	}

	var dnsHijack []string
	dnsHijack = append(dnsHijack, net.JoinHostPort(dnsServerAddress, "53"))

	// dup 一份交给 sing_tun.New(它只在自己内部成功接管后才持有该 fd),
	// 原始 fd 由本函数始终关闭 —— 与上游对同一问题的处理方式一致:
	// 只看 New 的返回错误无法判断它是否已经接管 fd。
	dupFd, err := syscall.Dup(fd)
	if err != nil {
		return fail(err)
	}
	defer func() { _ = syscall.Close(fd) }()

	options := LC.Tun{
		Enable:                true,
		Device:                device,
		Stack:                 stack,
		DNSHijack:             dnsHijack,
		AutoRoute:             false,
		AutoDetectInterface:   false,
		Inet4Address:          prefix4,
		Inet6Address:          prefix6,
		MTU:                   mtu,
		FileDescriptor:        dupFd,
		DisableICMPForwarding: disableICMPForwarding,
		ICMPTimeout:           icmpTimeout,
		CongestionController:  congestionController,
	}

	listener, err := sing_tun.New(options, tunnel.Tunnel)

	if err != nil {
		log.Errorln("startTUN error:", err)
		return nil, err
	}

	return listener, nil
}
