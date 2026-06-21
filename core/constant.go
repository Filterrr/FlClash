package main

import (
	"github.com/metacubex/mihomo/adapter/provider"
	"github.com/metacubex/mihomo/config"
	"github.com/metacubex/mihomo/constant"
	"time"
)

type ConfigExtendedParams struct {
	IsPatch                     bool              `json:"is-patch"`
	IsCompatible                bool              `json:"is-compatible"`
	SelectedMap                 map[string]string `json:"selected-map"`
	TestURL                     *string           `json:"test-url"`
	OverrideDns                 bool              `json:"override-dns"`
	OverrideSniffer             bool              `json:"override-sniffer"`
	OverrideAutoRoute           bool              `json:"override-auto-route"`
	OverrideStrictRoute         bool              `json:"override-strict-route"`
	OverrideAutoDetectInterface bool              `json:"override-auto-detect-interface"`
	Udp                         bool              `json:"udp"`
}

type GenerateConfigParams struct {
	ProfileId string               `json:"profile-id"`
	Config    config.RawConfig     `json:"config" `
	Params    ConfigExtendedParams `json:"params"`
}

type ChangeProxyParams struct {
	GroupName *string `json:"group-name"`
	ProxyName *string `json:"proxy-name"`
}

type TestDelayParams struct {
	ProxyName string `json:"proxy-name"`
	Timeout   int64  `json:"timeout"`
}

type TestSpeedParams struct {
	ProxyName string `json:"proxy-name"`
	Url       string `json:"url"`
	Timeout   int64  `json:"timeout"`
}

type SpeedResult struct {
	Name  string   `json:"name"`
	Speed *float64 `json:"speed"`
}

type ProcessMapItem struct {
	Id    int64  `json:"id"`
	Value string `json:"value"`
}

type ExternalProvider struct {
	Name             string                     `json:"name"`
	Type             string                     `json:"type"`
	VehicleType      string                     `json:"vehicle-type"`
	Count            int                        `json:"count"`
	Path             string                     `json:"path"`
	UpdateAt         time.Time                  `json:"update-at"`
	SubscriptionInfo *provider.SubscriptionInfo `json:"subscription-info"`
}

const (
	messageMethod                  Method = "message"
	initClashMethod                Method = "initClash"
	getIsInitMethod                Method = "getIsInit"
	forceGcMethod                  Method = "forceGc"
	shutdownMethod                 Method = "shutdown"
	validateConfigMethod           Method = "validateConfig"
	updateConfigMethod             Method = "updateConfig"
	getProxiesMethod               Method = "getProxies"
	changeProxyMethod              Method = "changeProxy"
	getTrafficMethod               Method = "getTraffic"
	getTotalTrafficMethod          Method = "getTotalTraffic"
	resetTrafficMethod             Method = "resetTraffic"
	asyncTestDelayMethod           Method = "asyncTestDelay"
	asyncTestSpeedMethod           Method = "asyncTestSpeed"
	getConnectionsMethod           Method = "getConnections"
	closeConnectionsMethod         Method = "closeConnections"
	closeConnectionMethod          Method = "closeConnection"
	getExternalProvidersMethod     Method = "getExternalProviders"
	getExternalProviderMethod      Method = "getExternalProvider"
	updateGeoDataMethod            Method = "updateGeoData"
	updateExternalProviderMethod   Method = "updateExternalProvider"
	sideLoadExternalProviderMethod Method = "sideLoadExternalProvider"
	startLogMethod                 Method = "startLog"
	stopLogMethod                  Method = "stopLog"
	startListenerMethod            Method = "startListener"
	stopListenerMethod             Method = "stopListener"
	getMemoryStatsMethod           Method = "getMemoryStats"
)

type Method string

type Action struct {
	Id     string      `json:"id"`
	Method Method      `json:"method"`
	Data   interface{} `json:"data"`
}

type MessageType string

type Delay struct {
	Name  string `json:"name"`
	Value int32  `json:"value"`
}

type Message struct {
	Type MessageType `json:"type"`
	Data interface{} `json:"data"`
}

type Process struct {
	Id       int64              `json:"id"`
	Metadata *constant.Metadata `json:"metadata"`
}

const (
	LogMessage     MessageType = "log"
	ProtectMessage MessageType = "protect"
	DelayMessage   MessageType = "delay"
	ProcessMessage MessageType = "process"
	RequestMessage MessageType = "request"
	StartedMessage MessageType = "started"
	LoadedMessage  MessageType = "loaded"
)
