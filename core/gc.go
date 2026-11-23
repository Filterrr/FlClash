package main

import (
	"bufio"
	"os"
	"runtime/debug"
	"strconv"
	"strings"
)

// 后台内存开销的两条腿:
//
//  1. SetMemoryLimit 设一个「软上限」—— Go 只在堆接近上限时才加压 GC。
//     这是唯一「降内存但不增耗电」的姿势:平时该干嘛干嘛,真涨到危险水位
//     才把 CPU 花在回收上。
//  2. 前后台切 GC 百分比 —— 前台 100(默认,少 GC、省 CPU),后台 50
//     (多回收一点,后台没人看 UI,CPU 富余)。
//
// 反面教材:无脑把 GOGC 调到 20 —— 那是拿 CPU 换内存,常驻进程会变成
// GC 风暴,后台耗电反而上升。
const (
	gcPercentForeground = 100
	gcPercentBackground = 50

	// 软上限的夹逼区间:小内存机器别设得比 96MB 还紧(会 GC 风暴),
	// 大内存机器也不必让一个代理进程吃到 512MB 以上。
	minMemoryLimitBytes = 96 << 20
	maxMemoryLimitBytes = 512 << 20

	// 取设备物理内存的 1/8 作为软上限。
	memoryLimitDenominator = 8
)

var memLimitInitialized bool

// initMemoryLimit 读取设备物理内存并设置 Go 堆软上限。
// 幂等,失败(读不到 /proc/meminfo)时直接放弃,不影响启动。
func initMemoryLimit() {
	if memLimitInitialized {
		return
	}
	memLimitInitialized = true

	totalKB := readMemTotalKB()
	if totalKB <= 0 {
		return
	}

	limit := totalKB * 1024 / memoryLimitDenominator
	if limit < minMemoryLimitBytes {
		limit = minMemoryLimitBytes
	}
	if limit > maxMemoryLimitBytes {
		limit = maxMemoryLimitBytes
	}

	// SetMemoryLimit 需要 Go 1.19+;旧工具链下这里会编译失败而非静默降级,
	// 所以构建脚本必须锁 >= 1.19(CI 固定 1.25.x)。
	debug.SetMemoryLimit(limit)
}

// readMemTotalKB 从 /proc/meminfo 读 MemTotal,单位 KB。
// 读不到返回 0,调用方据此跳过软上限设置。
func readMemTotalKB() int64 {
	f, err := os.Open("/proc/meminfo")
	if err != nil {
		return 0
	}
	defer func() {
		_ = f.Close()
	}()

	scanner := bufio.NewScanner(f)
	for scanner.Scan() {
		line := scanner.Text()
		if !strings.HasPrefix(line, "MemTotal:") {
			continue
		}
		fields := strings.Fields(line)
		if len(fields) < 2 {
			return 0
		}
		value, err := strconv.ParseInt(fields[1], 10, 64)
		if err != nil {
			return 0
		}
		return value
	}
	return 0
}

// handleSetBackgroundMode 在前后台切换时调整 GC 百分比。
//
// 参数是 bool 而不是枚举:只有「前台 / 后台」两种稳态,中间的 reduced /
// low 档由 Dart 侧的后台管理器决定何时切,core 不需要知道细节。
func handleSetBackgroundMode(isBackground bool) {
	if isBackground {
		debug.SetGCPercent(gcPercentBackground)
		return
	}
	debug.SetGCPercent(gcPercentForeground)
}
