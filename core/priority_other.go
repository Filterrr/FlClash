//go:build !android || !cgo

package main

// applyPlatformTuning 在非 android 平台(以及 android 的非 cgo 构建)是空实现。
//
// 桌面端没有「和手机 UI 抢 CPU」这回事,进程优先级交给系统的调度策略即可,
// 不必在这里插手 —— 少一处平台相关的行为差异,少一处能出问题的地方。
//
// 覆盖条件用 !android || !cgo 而不是 !android:后者在 GOOS=android 且
// CGO_ENABLED=0 时两边都不满足(priority_android.go 要求 cgo),会让
// applyPlatformTuning 变成未定义符号。虽然 android 实际上必须开 cgo,
// 但一个字符的代价换掉一类构建组合的编译失败,值得。
func applyPlatformTuning() {}
