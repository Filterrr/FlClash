package com.follow.clask.services

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.Build
import android.os.PowerManager

/**
 * 监听「灭屏 / Doze」状态。
 *
 * 前台服务通知的流量数字由 Dart 侧按固定节流刷新，但灭屏或设备进入
 * Doze 时这些更新无人可见，却仍会持续唤醒 NotificationManager。本类
 * 提供当前是否应延缓刷新的判断，服务在延缓期间冻结通知更新；一旦
 * 屏幕点亮或退出 Doze，通过 [consumeRefreshRequest] 请求立即刷新一次，
 * 避免数字停留在冻结时的旧值。
 *
 * 仅监听系统广播（ACTION_SCREEN_ON / ACTION_SCREEN_OFF /
 * ACTION_DEVICE_IDLE_MODE_CHANGED），因此不需要导出给其他应用。
 */
class ScreenStateWatcher(private val context: Context) {

    @Volatile
    private var interactive: Boolean = true

    @Volatile
    private var idle: Boolean = false

    @Volatile
    private var refreshRequested: Boolean = false

    private var registered = false

    /** 当前是否应延缓通知刷新（灭屏或处于 Doze）。 */
    val shouldDeferNotification: Boolean
        get() = !interactive || idle

    private val receiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            refresh()
        }
    }

    fun start() {
        refresh()
        if (registered) return
        val filter = IntentFilter().apply {
            addAction(Intent.ACTION_SCREEN_ON)
            addAction(Intent.ACTION_SCREEN_OFF)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                addAction(PowerManager.ACTION_DEVICE_IDLE_MODE_CHANGED)
            }
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            context.registerReceiver(receiver, filter, Context.RECEIVER_NOT_EXPORTED)
        } else {
            @Suppress("UnspecifiedRegisterReceiverFlag")
            context.registerReceiver(receiver, filter)
        }
        registered = true
    }

    fun stop() {
        if (!registered) return
        try {
            context.unregisterReceiver(receiver)
        } catch (_: IllegalArgumentException) {
            // 已注销或从未注册成功时忽略
        }
        registered = false
    }

    /**
     * 取出并清除「恢复可见后需要立即刷新一次」的标记。
     * 返回 true 表示调用方应忽略内容去重、强制刷新一次通知。
     */
    fun consumeRefreshRequest(): Boolean {
        if (!refreshRequested) return false
        refreshRequested = false
        return true
    }

    private fun refresh() {
        // 使用字符串键获取服务，兼容 minSdk 21（Class 版本需 API 23+）
        @Suppress("DEPRECATION")
        val powerManager =
            context.getSystemService(Context.POWER_SERVICE) as? PowerManager
        val newInteractive = powerManager?.isInteractive ?: true
        val newIdle = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            powerManager?.isDeviceIdleMode ?: false
        } else {
            false
        }
        val wasDeferred = shouldDeferNotification
        interactive = newInteractive
        idle = newIdle
        if (wasDeferred && !shouldDeferNotification) {
            refreshRequested = true
        }
    }
}
