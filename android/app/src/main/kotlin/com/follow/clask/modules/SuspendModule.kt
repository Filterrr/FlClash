package com.follow.clask.modules

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.Build
import android.os.PowerManager
import io.flutter.plugin.common.MethodChannel

class SuspendModule(
    private val context: Context,
    private val methodChannel: MethodChannel,
) {
    private var isRegistered = false
    private var isDeviceIdle = false
    private var isScreenOff = false

    private val receiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            when (intent.action) {
                Intent.ACTION_SCREEN_OFF -> {
                    isScreenOff = true
                    checkSuspend()
                }

                Intent.ACTION_SCREEN_ON -> {
                    isScreenOff = false
                    checkResume()
                }

                PowerManager.ACTION_DEVICE_IDLE_MODE_CHANGED -> {
                    val pm = context.getSystemService(Context.POWER_SERVICE) as PowerManager
                    isDeviceIdle = pm.isDeviceIdleMode
                    if (isDeviceIdle) {
                        checkSuspend()
                    } else {
                        checkResume()
                    }
                }
            }
        }
    }

    fun install() {
        if (isRegistered) return
        val filter = IntentFilter().apply {
            addAction(Intent.ACTION_SCREEN_OFF)
            addAction(Intent.ACTION_SCREEN_ON)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                addAction(PowerManager.ACTION_DEVICE_IDLE_MODE_CHANGED)
            }
        }
        context.registerReceiver(receiver, filter)
        isRegistered = true

        val pm = context.getSystemService(Context.POWER_SERVICE) as PowerManager
        isDeviceIdle = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            pm.isDeviceIdleMode
        } else {
            false
        }
        isScreenOff = !pm.isInteractive
    }

    fun uninstall() {
        if (!isRegistered) return
        try {
            context.unregisterReceiver(receiver)
        } catch (_: Exception) {
        }
        isRegistered = false
    }

    private fun checkSuspend() {
        if (isScreenOff || isDeviceIdle) {
            methodChannel.invokeMethod("suspended", true)
        }
    }

    private fun checkResume() {
        if (!isScreenOff && !isDeviceIdle) {
            methodChannel.invokeMethod("suspended", false)
        }
    }
}
