//go:build android && cgo

package platform

import "syscall"

// LowerProcessPriority 把当前进程的 nice 值调到指定值。
//
// 只降不升,失败静默:非特权进程在部分内核 / 容器里不允许调 nice,
// 那种情况下继续用默认优先级就行,不该让 core 起不来。
func LowerProcessPriority(nice int) {
	_ = syscall.Setpriority(syscall.PRIO_PROCESS, 0, nice)
}
