package main

import (
	"context"
	"crypto/tls"
	"encoding/json"
	"fmt"
	"net"
	nhttp "net/http"
	"net/url"
	"strconv"
	"time"

	"github.com/metacubex/mihomo/adapter"
	"github.com/metacubex/mihomo/adapter/outboundgroup"
	"github.com/metacubex/mihomo/common/observable"
	"github.com/metacubex/mihomo/common/utils"
	"github.com/metacubex/mihomo/component/updater"
	"github.com/metacubex/mihomo/config"
	"github.com/metacubex/mihomo/constant"
	cp "github.com/metacubex/mihomo/constant/provider"
	"github.com/metacubex/mihomo/hub/executor"
	"github.com/metacubex/mihomo/listener"
	"github.com/metacubex/mihomo/log"
	"github.com/metacubex/mihomo/tunnel/statistic"
	"runtime"
	"runtime/debug"
	"sort"
)

var (
	isInit            = false
	configParams      = ConfigExtendedParams{}
	externalProviders = map[string]cp.Provider{}
	logSubscriber     observable.Subscription[log.Event]
	currentConfig     *config.Config
)

func handleInitClash(homeDirStr string) bool {
	if !isInit {
		constant.SetHomeDir(homeDirStr)
		isInit = true
	}
	return isInit
}

func handleStartListener() bool {
	runLock.Lock()
	defer runLock.Unlock()
	isRunning = true
	updateListeners(true)
	return true
}

func handleStopListener() bool {
	runLock.Lock()
	defer runLock.Unlock()
	isRunning = false
	listener.StopListener()
	return true
}

func handleGetIsInit() bool {
	return isInit
}

func logMemoryStats(prefix string) {
	var m runtime.MemStats
	runtime.ReadMemStats(&m)
	log.Infoln("[MEM] %s | Alloc=%dKB | TotalAlloc=%dKB | Sys=%dKB | HeapAlloc=%dKB | HeapReleased=%dKB | NumGC=%d | NumForcedGC=%d",
		prefix,
		m.Alloc/1024,
		m.TotalAlloc/1024,
		m.Sys/1024,
		m.HeapAlloc/1024,
		m.HeapReleased/1024,
		m.NumGC,
		m.NumForcedGC,
	)
}

func handleForceGc() {
	go func() {
		log.Infoln("[APP] request force GC")
		logMemoryStats("before-GC")
		runtime.GC()
		debug.FreeOSMemory()
		logMemoryStats("after-FreeOSMemory")
	}()
}

func handleShutdown() bool {
	stopListeners()
	executor.Shutdown()
	runtime.GC()
	debug.FreeOSMemory()
	isInit = false
	return true
}

func handleValidateConfig(bytes []byte) string {
	_, err := config.UnmarshalRawConfig(bytes)
	if err != nil {
		return err.Error()
	}
	return ""
}

func handleUpdateConfig(bytes []byte) string {
	var params = &GenerateConfigParams{}
	err := json.Unmarshal(bytes, params)
	if err != nil {
		return err.Error()
	}

	configParams = params.Params
	prof := decorationConfig(params.ProfileId, params.Config)
	err = applyConfig(prof)
	if err != nil {
		return err.Error()
	}
	return ""
}

func handleGetProxies() string {
	runLock.Lock()
	defer runLock.Unlock()
	data, err := json.Marshal(proxiesWithProviders())
	if err != nil {
		return ""
	}
	return string(data)
}

func handleChangeProxy(data string, fn func(string string)) {
	runLock.Lock()
	go func() {
		defer runLock.Unlock()
		var params = &ChangeProxyParams{}
		err := json.Unmarshal([]byte(data), params)
		if err != nil {
			fn(err.Error())
			return
		}
		groupName := *params.GroupName
		proxyName := *params.ProxyName
		proxies := proxiesWithProviders()
		group, ok := proxies[groupName]
		if !ok {
			fn("Not found group")
			return
		}
		adapterProxy := group.(*adapter.Proxy)
		selector, ok := adapterProxy.ProxyAdapter.(outboundgroup.SelectAble)
		if !ok {
			fn("Group is not selectable")
			return
		}
		if proxyName == "" {
			selector.ForceSet(proxyName)
		} else {
			err = selector.Set(proxyName)
		}
		if err != nil {
			fn(err.Error())
			return
		}

		fn("")
	}()
}

func handleGetTraffic(onlyProxy bool) string {
	up, down := statistic.DefaultManager.NowTraffic(onlyProxy)
	traffic := map[string]int64{
		"up":   up,
		"down": down,
	}
	data, err := json.Marshal(traffic)
	if err != nil {
		fmt.Println("Error:", err)
		return ""
	}
	return string(data)
}

func handleGetTotalTraffic(onlyProxy bool) string {
	up, down := statistic.DefaultManager.TotalTraffic(onlyProxy)
	traffic := map[string]int64{
		"up":   up,
		"down": down,
	}
	data, err := json.Marshal(traffic)
	if err != nil {
		fmt.Println("Error:", err)
		return ""
	}
	return string(data)
}

func handleResetTraffic() {
	statistic.DefaultManager.ResetStatistic()
}

func handleAsyncTestDelay(paramsString string, fn func(string)) {
	b.Go(paramsString, func() (bool, error) {
		var params = &TestDelayParams{}
		err := json.Unmarshal([]byte(paramsString), params)
		if err != nil {
			fn("")
			return false, nil
		}

		expectedStatus, err := utils.NewUnsignedRanges[uint16]("")
		if err != nil {
			fn("")
			return false, nil
		}

		ctx, cancel := context.WithTimeout(context.Background(), time.Millisecond*time.Duration(params.Timeout))
		defer cancel()

		proxies := proxiesWithProviders()
		proxy := proxies[params.ProxyName]

		delayData := &Delay{
			Name: params.ProxyName,
		}

		if proxy == nil {
			delayData.Value = -1
			data, _ := json.Marshal(delayData)
			fn(string(data))
			return false, nil
		}

		delay, err := proxy.URLTest(ctx, constant.DefaultTestURL, expectedStatus)
		if err != nil || delay == 0 {
			delayData.Value = -1
			data, _ := json.Marshal(delayData)
			fn(string(data))
			return false, nil
		}

		delayData.Value = int32(delay)
		data, _ := json.Marshal(delayData)
		fn(string(data))
		return false, nil
	})
}

func handleAsyncTestSpeed(paramsString string, fn func(string)) {
	b.Go(paramsString, func() (bool, error) {
		var params = &TestSpeedParams{}
		err := json.Unmarshal([]byte(paramsString), params)
		if err != nil {
			fn("")
			return false, nil
		}

		ctx, cancel := context.WithTimeout(context.Background(), time.Millisecond*time.Duration(params.Timeout))
		defer cancel()

		proxies := proxiesWithProviders()
		proxy := proxies[params.ProxyName]

		speedResult := &SpeedResult{
			Name: params.ProxyName,
		}

		if proxy == nil {
			data, _ := json.Marshal(speedResult)
			fn(string(data))
			return false, nil
		}

		adapterProxy, ok := proxy.(*adapter.Proxy)
		if !ok {
			data, _ := json.Marshal(speedResult)
			fn(string(data))
			return false, nil
		}

		// Parse URL to get host and port for metadata
		parsedUrl, err := url.Parse(params.Url)
		if err != nil {
			data, _ := json.Marshal(speedResult)
			fn(string(data))
			return false, nil
		}

		port := parsedUrl.Port()
		dstPort := uint16(80)
		if port != "" {
			p, _ := strconv.Atoi(port)
			dstPort = uint16(p)
		} else if parsedUrl.Scheme == "https" {
			dstPort = 443
		}

		addr := constant.Metadata{
			NetWork: constant.TCP,
			Type:    constant.HTTPCONNECT,
			Host:    parsedUrl.Hostname(),
			DstPort: dstPort,
		}

		// Dial directly through the proxy (no changeProxy needed)
		proxyConn, err := adapterProxy.DialContext(ctx, &addr)
		if err != nil {
			data, _ := json.Marshal(speedResult)
			fn(string(data))
			return false, nil
		}

		// Build HTTP request through the dialed connection
		req, err := nhttp.NewRequest(nhttp.MethodGet, params.Url, nil)
		if err != nil {
			proxyConn.Close()
			data, _ := json.Marshal(speedResult)
			fn(string(data))
			return false, nil
		}
		req = req.WithContext(ctx)

		// Use custom transport that routes through the dialed connection
		transport := &nhttp.Transport{
			DialContext: func(context.Context, string, string) (net.Conn, error) {
				return proxyConn, nil
			},
			MaxIdleConns:          100,
			IdleConnTimeout:       90 * time.Second,
			TLSHandshakeTimeout:   10 * time.Second,
			ExpectContinueTimeout: 1 * time.Second,
		}

		if parsedUrl.Scheme == "https" {
			transport.TLSClientConfig = &tls.Config{
				MinVersion: tls.VersionTLS12,
			}
		}

		client := nhttp.Client{
			Timeout:   time.Duration(params.Timeout) * time.Millisecond,
			Transport: transport,
		}
		defer client.CloseIdleConnections()

		resp, err := client.Do(req)
		if err != nil {
			data, _ := json.Marshal(speedResult)
			fn(string(data))
			return false, nil
		}
		defer resp.Body.Close()

		// Measure download speed
		start := time.Now()
		var totalBytes int64
		buf := make([]byte, 32*1024)
		for {
			n, err := resp.Body.Read(buf)
			totalBytes += int64(n)
			if err != nil {
				break
			}
		}

		elapsed := time.Since(start).Seconds()
		if elapsed > 0 && totalBytes > 0 {
			speed := float64(totalBytes) / elapsed
			speedResult.Speed = &speed
		}

		data, _ := json.Marshal(speedResult)
		fn(string(data))
		return false, nil
	})
}

func handleGetConnections() string {
	runLock.Lock()
	defer runLock.Unlock()
	snapshot := statistic.DefaultManager.Snapshot()
	data, err := json.Marshal(snapshot)
	if err != nil {
		fmt.Println("Error:", err)
		return ""
	}
	return string(data)
}

func handleCloseConnectionsUnLock() bool {
	statistic.DefaultManager.Range(func(c statistic.Tracker) bool {
		err := c.Close()
		if err != nil {
			return false
		}
		return true
	})
	return true
}

func handleCloseConnections() bool {
	runLock.Lock()
	defer runLock.Unlock()
	statistic.DefaultManager.Range(func(c statistic.Tracker) bool {
		err := c.Close()
		if err != nil {
			return false
		}
		return true
	})
	return true
}

func handleCloseConnection(connectionId string) bool {
	runLock.Lock()
	defer runLock.Unlock()
	c := statistic.DefaultManager.Get(connectionId)
	if c == nil {
		return false
	}
	_ = c.Close()
	return true
}

func handleGetExternalProviders() string {
	runLock.Lock()
	defer runLock.Unlock()
	externalProviders = getExternalProvidersRaw()
	eps := make([]ExternalProvider, 0)
	for _, p := range externalProviders {
		externalProvider, err := toExternalProvider(p)
		if err != nil {
			continue
		}
		eps = append(eps, *externalProvider)
	}
	sort.Sort(ExternalProviders(eps))
	data, err := json.Marshal(eps)
	if err != nil {
		return ""
	}
	return string(data)
}

func handleGetExternalProvider(externalProviderName string) string {
	runLock.Lock()
	defer runLock.Unlock()
	externalProvider, exist := externalProviders[externalProviderName]
	if !exist {
		return ""
	}
	e, err := toExternalProvider(externalProvider)
	if err != nil {
		return ""
	}
	data, err := json.Marshal(e)
	if err != nil {
		return ""
	}
	return string(data)
}

func handleUpdateGeoData(geoType string, geoName string, fn func(value string)) {
	go func() {
		path := constant.Path.Resolve(geoName)
		switch geoType {
		case "MMDB":
			err := updater.UpdateMMDBWithPath(path)
			if err != nil {
				fn(err.Error())
				return
			}
		case "ASN":
			err := updater.UpdateASNWithPath(path)
			if err != nil {
				fn(err.Error())
				return
			}
		case "GeoIp":
			err := updater.UpdateGeoIpWithPath(path)
			if err != nil {
				fn(err.Error())
				return
			}
		case "GeoSite":
			err := updater.UpdateGeoSiteWithPath(path)
			if err != nil {
				fn(err.Error())
				return
			}
		}
		fn("")
	}()
}

func handleUpdateExternalProvider(providerName string, fn func(value string)) {
	go func() {
		externalProvider, exist := externalProviders[providerName]
		if !exist {
			fn("external provider is not exist")
			return
		}
		err := externalProvider.Update()
		if err != nil {
			fn(err.Error())
			return
		}
		fn("")
	}()
}

func handleSideLoadExternalProvider(providerName string, data []byte, fn func(value string)) {
	go func() {
		runLock.Lock()
		defer runLock.Unlock()
		externalProvider, exist := externalProviders[providerName]
		if !exist {
			fn("external provider is not exist")
			return
		}
		err := sideUpdateExternalProvider(externalProvider, data)
		if err != nil {
			fn(err.Error())
			return
		}
		fn("")
	}()
}

func handleStartLog() {
	if logSubscriber != nil {
		log.UnSubscribe(logSubscriber)
		logSubscriber = nil
	}
	logSubscriber = log.Subscribe()
	go func() {
		for logData := range logSubscriber {
			if logData.LogLevel < log.Level() {
				continue
			}
			message := &Message{
				Type: LogMessage,
				Data: logData,
			}
			SendMessage(*message)
		}
	}()
}

func handleStopLog() {
	if logSubscriber != nil {
		log.UnSubscribe(logSubscriber)
		logSubscriber = nil
	}
}

func handleGetMemoryStats() string {
	var m runtime.MemStats
	runtime.ReadMemStats(&m)
	stats := map[string]uint64{
		"alloc":        m.Alloc,
		"totalAlloc":   m.TotalAlloc,
		"sys":          m.Sys,
		"heapAlloc":    m.HeapAlloc,
		"heapSys":      m.HeapSys,
		"heapReleased": m.HeapReleased,
		"heapIdle":     m.HeapIdle,
		"heapInUse":    m.HeapInuse,
		"stackInUse":   m.StackInuse,
		"stackSys":     m.StackSys,
		"numGC":        uint64(m.NumGC),
		"numForcedGC":  uint64(m.NumForcedGC),
		"gcCPUFraction": uint64(m.GCCPUFraction * 1e6),
	}
	data, err := json.Marshal(stats)
	if err != nil {
		return "{}"
	}
	return string(data)
}

func init() {
	adapter.UrlTestHook = func(url string, name string, delay uint16) {
		delayData := &Delay{
			Name: name,
		}
		if delay == 0 {
			delayData.Value = -1
		} else {
			delayData.Value = int32(delay)
		}
		SendMessage(Message{
			Type: DelayMessage,
			Data: delayData,
		})
	}
	statistic.DefaultRequestNotify = func(c statistic.Tracker) {
		SendMessage(Message{
			Type: RequestMessage,
			Data: c,
		})
	}
	executor.DefaultProviderLoadedHook = func(providerName string) {
		SendMessage(Message{
			Type: LoadedMessage,
			Data: providerName,
		})
	}
}
