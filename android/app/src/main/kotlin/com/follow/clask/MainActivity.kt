package com.follow.clask


import android.content.ComponentCallbacks2
import android.os.Build
import android.os.Bundle
import com.follow.clask.plugins.AppPlugin
import com.follow.clask.plugins.ServicePlugin
import com.follow.clask.plugins.TilePlugin
import com.follow.clask.plugins.VpnPlugin
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        requestHighRefreshRate()
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        flutterEngine.plugins.add(AppPlugin())
        flutterEngine.plugins.add(VpnPlugin())
        flutterEngine.plugins.add(ServicePlugin())
        flutterEngine.plugins.add(TilePlugin())
        GlobalState.flutterEngine = flutterEngine
    }

    private fun requestHighRefreshRate() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            val display = window.windowManager.defaultDisplay
            val supportedModes = display.supportedModes
            var preferredModeId = 0
            var maxRefreshRate = 0f
            for (mode in supportedModes) {
                if (mode.refreshRate > maxRefreshRate) {
                    maxRefreshRate = mode.refreshRate
                    preferredModeId = mode.modeId
                }
            }
            if (preferredModeId != 0) {
                val params = window.attributes
                params.preferredDisplayModeId = preferredModeId
                window.attributes = params
            }
        }
    }

    override fun onTrimMemory(level: Int) {
        super.onTrimMemory(level)
        when (level) {
            ComponentCallbacks2.TRIM_MEMORY_UI_HIDDEN,
            ComponentCallbacks2.TRIM_MEMORY_RUNNING_LOW,
            ComponentCallbacks2.TRIM_MEMORY_RUNNING_CRITICAL -> {
                GlobalState.getCurrentAppPlugin()?.clearCaches()
            }
            ComponentCallbacks2.TRIM_MEMORY_MODERATE,
            ComponentCallbacks2.TRIM_MEMORY_COMPLETE -> {
                GlobalState.getCurrentAppPlugin()?.clearCaches()
                GlobalState.destroyServiceEngine()
            }
        }
    }

    override fun onDestroy() {
        GlobalState.flutterEngine = null
        super.onDestroy()
    }
}