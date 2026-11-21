//go:build android && cgo

package main

import "C"
import (
	"core/platform"
	"core/state"
	t "core/tun"
	"encoding/json"
	"errors"
	"fmt"
	"github.com/metacubex/mihomo/component/dialer"
	"github.com/metacubex/mihomo/component/process"
	"github.com/metacubex/mihomo/constant"
	"github.com/metacubex/mihomo/dns"
	"github.com/metacubex/mihomo/listener/sing_tun"
	"github.com/metacubex/mihomo/log"
	"strconv"
	"strings"
	"sync"
	"sync/atomic"
	"syscall"
	"time"
)

type ProcessMap struct {
	m sync.Map
}

type FdMap struct {
	m sync.Map
}

type Fd struct {
	Id    int64 `json:"id"`
	Value int64 `json:"value"`
}

var (
	tunListener *sing_tun.Listener
	fdMap       FdMap
	// fdWaiters 记录「已发出 protect 请求、正在等待 Dart 回包」的 fd:
	// key 是 fd 序号,value 是 chan struct{}。收到 setFdMap 后 close 该 channel,
	// 拨号 goroutine 立即返回,不再轮询忙等(见 initSocketHook)。
	fdWaiters  sync.Map
	fdCounter  int64 = 0
	counter    int64 = 0
	processMap ProcessMap
	tunLock    sync.Mutex
	runTime    *time.Time
	errBlocked = errors.New("blocked")
)

// socketProtectTimeout 是等待 Dart 侧回 protect(fd) 的最长时间。
const socketProtectTimeout = 500 * time.Millisecond

func (cm *ProcessMap) Store(key int64, value string) {
	cm.m.Store(key, value)
}

func (cm *ProcessMap) Load(key int64) (string, bool) {
	value, ok := cm.m.Load(key)
	if !ok || value == nil {
		return "", false
	}
	return value.(string), true
}

func (cm *FdMap) Store(key int64) {
	cm.m.Store(key, struct{}{})
}

func (cm *FdMap) Load(key int64) bool {
	_, ok := cm.m.Load(key)
	return ok
}

//export startTUN
func startTUN(fd C.int, port C.longlong) {
	i := int64(port)
	ServicePort = i
	if fd == 0 {
		tunLock.Lock()
		defer tunLock.Unlock()
		now := time.Now()
		runTime = &now
		SendMessage(Message{
			Type: StartedMessage,
			Data: strconv.FormatInt(runTime.UnixMilli(), 10),
		})
		return
	}
	initSocketHook()
	go func() {
		tunLock.Lock()
		defer tunLock.Unlock()
		f := int(fd)
		mtu := currentConfig.General.Tun.MTU
		if mtu == 0 {
			mtu = state.DefaultMtu
		}
		listener, err := t.Start(
			f,
			currentConfig.General.Tun.Device,
			currentConfig.General.Tun.Stack,
			currentConfig.General.Tun.CongestionController,
			mtu,
		)
		if err != nil {
			// 隧道没有建立起来:必须清掉旧 listener 与运行时间。
			// 旧实现丢弃错误并照样把 runTime 置位,getRunTime() 会让界面显示
			// 「已连接」而实际所有流量都在直连;fd 的所有权已交给 t.Start
			// (失败时由它自己关闭),这里不再处理。
			if tunListener != nil {
				_ = tunListener.Close()
			}
			tunListener = nil
			runTime = nil
			log.Errorln("startTUN failed, tunnel is not established: %v", err)
			return
		}
		// 覆盖前先关闭上一个 listener,避免重复启动时泄漏 sing-tun 资源。
		if tunListener != nil {
			_ = tunListener.Close()
		}
		tunListener = listener
		if tunListener != nil {
			log.Infoln("TUN address: %v", tunListener.Address())
		}
		now := time.Now()
		runTime = &now
	}()
}

//export getRunTime
func getRunTime() *C.char {
	if runTime == nil {
		return C.CString("")
	}
	return C.CString(strconv.FormatInt(runTime.UnixMilli(), 10))
}

//export stopTun
func stopTun() {
	removeSocketHook()
	go func() {
		tunLock.Lock()
		defer tunLock.Unlock()

		runTime = nil

		if tunListener != nil {
			_ = tunListener.Close()
		}
	}()
}

//export setFdMap
func setFdMap(fd C.long) {
	fdInt := int64(fd)
	go func() {
		fdMap.Store(fdInt)
		// 唤醒正在等待该 fd 被 protect 的拨号 goroutine(见 initSocketHook)。
		if waiter, ok := fdWaiters.LoadAndDelete(fdInt); ok {
			close(waiter.(chan struct{}))
		}
	}()
}

func markSocket(fd Fd) {
	SendMessage(Message{
		Type: ProtectMessage,
		Data: fd,
	})
}

func initSocketHook() {
	dialer.DefaultSocketHook = func(network, address string, conn syscall.RawConn) error {
		if platform.ShouldBlockConnection() {
			return errBlocked
		}
		return conn.Control(func(fd uintptr) {
			fdInt := int64(fd)
			id := atomic.AddInt64(&fdCounter, 1)
			// 先登记等待用的 channel,再发出 protect 请求:这样 setFdMap
			// 回来时一定能唤醒本 goroutine,不会出现「先回包后等待」的竞态。
			waiter := make(chan struct{})
			fdWaiters.Store(id, waiter)
			defer fdWaiters.Delete(id)

			markSocket(Fd{
				Id:    id,
				Value: fdInt,
			})

			timer := time.NewTimer(socketProtectTimeout)
			defer timer.Stop()
			select {
			case <-waiter:
				return
			case <-timer.C:
				// 超时:不能一直卡在拨号路径上。放行该 socket,但留下日志,
				// 便于定位「Dart 侧 protect 往返过慢」导致的漏流量问题。
				log.Warnln("protect socket timeout, socket %d is not protected", fdInt)
				return
			}
		})
	}
}

func removeSocketHook() {
	dialer.DefaultSocketHook = nil
}

func init() {
	process.DefaultPackageNameResolver = func(metadata *constant.Metadata) (string, error) {
		if metadata == nil {
			return "", process.ErrInvalidNetwork
		}
		id := atomic.AddInt64(&counter, 1)

		timeout := time.After(200 * time.Millisecond)

		SendMessage(Message{
			Type: ProcessMessage,
			Data: Process{
				Id:       id,
				Metadata: metadata,
			},
		})

		for {
			select {
			case <-timeout:
				return "", errors.New("package resolver timeout")
			default:
				value, exists := processMap.Load(id)
				if exists {
					return value, nil
				}
				time.Sleep(20 * time.Millisecond)
			}
		}
	}
}

//export setProcessMap
func setProcessMap(s *C.char) {
	if s == nil {
		return
	}
	paramsString := C.GoString(s)
	go func() {
		var processMapItem = &ProcessMapItem{}
		err := json.Unmarshal([]byte(paramsString), processMapItem)
		if err == nil {
			processMap.Store(processMapItem.Id, processMapItem.Value)
		}
	}()
}

//export getCurrentProfileName
func getCurrentProfileName() *C.char {
	state.CurrentStateLock.RLock()
	defer state.CurrentStateLock.RUnlock()
	if state.CurrentState == nil {
		return C.CString("")
	}
	return C.CString(state.CurrentState.CurrentProfileName)
}

//export getAndroidVpnOptions
func getAndroidVpnOptions() *C.char {
	tunLock.Lock()
	defer tunLock.Unlock()
	mtu := currentConfig.General.Tun.MTU
	if mtu == 0 {
		mtu = state.DefaultMtu
	}
	// 与 setState 的写入互斥,避免读到「一半新一半旧」的配置。
	state.CurrentStateLock.RLock()
	defer state.CurrentStateLock.RUnlock()
	options := state.AndroidVpnOptions{
		Enable:           state.CurrentState.Enable,
		Port:             currentConfig.General.MixedPort,
		Ipv4Address:      state.DefaultIpv4Address,
		Ipv6Address:      state.GetIpv6Address(),
		AccessControl:    state.CurrentState.AccessControl,
		SystemProxy:      state.CurrentState.SystemProxy,
		AllowBypass:      state.CurrentState.AllowBypass,
		RouteAddress:     state.CurrentState.RouteAddress,
		BypassDomain:     state.CurrentState.BypassDomain,
		DnsServerAddress: state.GetDnsServerAddress(),
		FcmKeepAlive:     state.CurrentState.FcmKeepAlive,
		Mtu:              mtu,
	}
	data, err := json.Marshal(options)
	if err != nil {
		fmt.Println("Error:", err)
		return C.CString("")
	}
	return C.CString(string(data))
}

//export setState
func setState(s *C.char) {
	paramsString := C.GoString(s)
	// 先解析到临时结构体,成功后再整体替换:解析失败时不会留下「半更新」状态。
	// 写入必须与读侧(tun.Start / getAndroidVpnOptions)通过 CurrentStateLock 互斥。
	var nextState state.State
	if err := json.Unmarshal([]byte(paramsString), &nextState); err != nil {
		log.Errorln("setState error: %v", err)
		return
	}
	state.CurrentStateLock.Lock()
	*state.CurrentState = nextState
	state.CurrentStateLock.Unlock()
}

//export updateDns
func updateDns(s *C.char) {
	dnsList := C.GoString(s)
	// 首选网络未上报 DNS 服务器时 Android 侧会传空串。
	// strings.Split("", ",") 得到 [""]，mihomo 会把它构建成 "udp://:"，
	// 于是 system 解析器被当作已配置、永不回落到默认 nameserver，
	// 解析全部失败（上游 e55f6d10 修复的同一缺陷）。
	var addr []string
	if dnsList != "" {
		addr = strings.Split(dnsList, ",")
	}
	go func() {
		log.Infoln("[DNS] updateDns %s", dnsList)
		dns.UpdateSystemDNS(addr)
		dns.FlushCacheWithDefaultResolver()
	}()
}
