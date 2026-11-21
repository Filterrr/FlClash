package com.follow.clask.plugins

import android.content.Context
import com.follow.clask.GlobalState
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch


class ServicePlugin : FlutterPlugin, MethodChannel.MethodCallHandler {

    private lateinit var flutterMethodChannel: MethodChannel

    private lateinit var context: Context

    override fun onAttachedToEngine(flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
        context = flutterPluginBinding.applicationContext
        flutterMethodChannel = MethodChannel(flutterPluginBinding.binaryMessenger, "service")
        flutterMethodChannel.setMethodCallHandler(this)
    }

    override fun onDetachedFromEngine(flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
        flutterMethodChannel.setMethodCallHandler(null)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) = when (call.method) {
        "init" -> {
            GlobalState.getCurrentAppPlugin()?.requestNotificationsPermission(context)
            GlobalState.initServiceEngine(context)
            result.success(true)
        }

        "destroy" -> {
            // 先回复结果,再销毁引擎:引擎一旦销毁,方法通道的回复就再也投递
            // 不出去,Dart 侧 await service.destroy() 会永久挂起。
            result.success(true)
            // 销毁必须离开本回调栈 —— 本方法是由"被销毁的那个引擎"自己调用的。
            CoroutineScope(Dispatchers.Main).launch {
                handleDestroy()
            }
        }

        else -> {
            result.notImplemented()
        }
    }

    private fun handleDestroy() {
        GlobalState.getCurrentVPNPlugin()?.stop()
        GlobalState.destroyServiceEngine()
    }
}