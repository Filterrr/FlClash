//go:build android && cgo

package main

import "core/platform"

// coreProcessNice 是 core 进程使用的 nice 值。
//
// 取 5 而不是 19:代理转发是 I/O 密集活,略微降优先级就能让 UI 顺畅,
// 又不会因为让得太狠(19)在高负载时把转发延迟拖上去。
const coreProcessNice = 5

// applyPlatformTuning 是 android 平台的进程级调优。
//
// 把 core 进程的 nice 值调低一点,让 UI 线程和前台应用在争抢 CPU 时优先。
// 代理转发本身是 I/O 密集而非 CPU 密集,略微降优先级对吞吐影响很小,
// 但能让后台运行时少跟系统抢调度。
//
// 只降不升,失败静默 —— 某些内核 / 容器不允许非特权进程调 nice,
// 那不该让 core 起不来。
func applyPlatformTuning() {
	platform.LowerProcessPriority(coreProcessNice)
}
