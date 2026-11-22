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

type Fd struct {
	Id    int64 `json:"id"`
	Value int64 `json:"value"`
}

var (
	tunListener *sing_tun.Listener
	// fdWaiters 记录「已发出 protect 请求、正在等待 Dart 回包」的 fd:
	// key 是 fd 序号,value 是 chan bool(容量 1)。true 表示 protect 成功,
	// false 表示 Dart 侧明确失败 —— 拨号 goroutine 收到 false 会直接拒绝
	// 这次连接,绝不能让未受保护的 socket 绕过 VPN 直连。
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

// LoadAndDelete 取走并删除:进程解析结果只用一次,旧实现只 Store 不 Delete,
// 每解析一次连接就永久留下一条(长会话下是确定性内存增长)。
func (cm *ProcessMap) LoadAndDelete(key int64) (string, bool) {
	value, ok := cm.m.LoadAndDelete(key)
	if !ok || value == nil {
		return "", false
	}
	return value.(string), true
}

func (cm *ProcessMap) Delete(key int64) {
	cm.m.Delete(key)
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

// notifyProtectResult 把 protect 结果交给等待中的拨号 goroutine。
// channel 是容量 1 的缓冲通道且发送用 default 兜底,所以即使对方已经
// 超时返回,这里也不会阻塞或泄漏 goroutine。
func notifyProtectResult(fd int64, protected bool) {
	if waiter, ok := fdWaiters.LoadAndDelete(fd); ok {
		select {
		case waiter.(chan bool) <- protected:
		default:
		}
	}
}

//export setFdMap
func setFdMap(fd C.long) {
	notifyProtectResult(int64(fd), true)
}

// setProtectFailed 由 Dart 在 VpnService.protect() 返回 false 时调用:
// 唤醒等待者并让它返回 errBlocked,宁可这次连接失败,也不能裸奔出隧道。
//
//export setProtectFailed
func setProtectFailed(fd C.long) {
	notifyProtectResult(int64(fd), false)
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
			// 先登记等待用的 channel,再发出 protect 请求:这样 setFdMap /
			// setProtectFailed 回来时一定能唤醒本 goroutine,不会出现
			// 「先回包后等待」的竞态。
			waiter := make(chan bool, 1)
			fdWaiters.Store(id, waiter)
			defer fdWaiters.Delete(id)

			markSocket(Fd{
				Id:    id,
				Value: fdInt,
			})

			timer := time.NewTimer(socketProtectTimeout)
			defer timer.Stop()
			select {
			case protected := <-waiter:
				if !protected {
					// Dart 侧 protect() 明确失败(服务在销毁 / fd 非法)。
					// 放行就是漏流量:这条连接会绕过 TUN 直连,界面却仍
					// 显示“已保护”。宁可让本次拨号失败。
					log.Warnln("protect socket failed, block socket %d", fdInt)
					return errBlocked
				}
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
				// 超时后 Dart 侧仍可能迟到回包。延迟清掉这个 id,否则那条
				// 迟到结果会永久留在 map 里,把「用完即删」又漏回去。
				go func(id int64) {
					time.Sleep(5 * time.Second)
					processMap.Delete(id)
				}(id)
				return "", errors.New("package resolver timeout")
			default:
				value, exists := processMap.LoadAndDelete(id)
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
