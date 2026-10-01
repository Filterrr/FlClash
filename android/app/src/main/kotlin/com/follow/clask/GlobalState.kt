package com.follow.clask

import android.content.Context
import androidx.lifecycle.MutableLiveData
import com.follow.clask.plugins.AppPlugin
import com.follow.clask.plugins.ServicePlugin
import com.follow.clask.plugins.TilePlugin
import com.follow.clask.plugins.VpnPlugin
import io.flutter.FlutterInjector
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.dart.DartExecutor
import java.util.concurrent.locks.ReentrantLock
import kotlin.concurrent.withLock

enum class RunState {
    START,
    PENDING,
    STOP
}


object GlobalState {
    val runLock = ReentrantLock()

    val runState: MutableLiveData<RunState> = MutableLiveData<RunState>(RunState.STOP)
    var flutterEngine: FlutterEngine? = null
    private var serviceEngine: FlutterEngine? = null

    fun getCurrentAppPlugin(): AppPlugin? {
        val currentEngine = if (flutterEngine != null) flutterEngine else serviceEngine
        return currentEngine?.plugins?.get(AppPlugin::class.java) as AppPlugin?
    }

    fun getText(text: String): String {
        return getCurrentAppPlugin()?.getText(text) ?: ""
    }

    fun getCurrentTilePlugin(): TilePlugin? {
        val currentEngine = if (flutterEngine != null) flutterEngine else serviceEngine
        return currentEngine?.plugins?.get(TilePlugin::class.java) as TilePlugin?
    }

    fun getCurrentVPNPlugin(): VpnPlugin? {
        return serviceEngine?.plugins?.get(VpnPlugin::class.java) as VpnPlugin?
    }

    fun handleToggle(context: Context) {
        val starting = handleStart(context)
        if (!starting) {
            handleStop()
        }
    }

    /**
     * 进入 START 流程：状态置为 PENDING 后交给 Tile 插件或启动服务引擎。
     *
     * 注意：这里必须使用 withLock（配对释放），不能裸 lock()。
     * 旧实现 lock() 后从不 unlock，导致 runLock 被永久持有，
     * 其他线程后续的 runLock.withLock 调用（VpnPlugin.start / stop /
     * startForeground / destroyServiceEngine）会全部阻塞。
     */
    fun handleStart(context: Context): Boolean {
        return runLock.withLock {
            if (runState.value != RunState.STOP) {
                return@withLock false
            }
            runState.value = RunState.PENDING
            val tilePlugin = getCurrentTilePlugin()
            if (tilePlugin != null) {
                tilePlugin.handleStart()
            } else {
                initServiceEngine(context)
            }
            true
        }
    }

    /**
     * 进入 STOP 流程：状态置为 PENDING 后交给 Tile 插件处理。
     * 同上，必须使用 withLock（配对释放）。
     */
    fun handleStop() {
        runLock.withLock {
            if (runState.value != RunState.START) {
                return@withLock
            }
            runState.value = RunState.PENDING
            getCurrentTilePlugin()?.handleStop()
        }
    }

    fun destroyServiceEngine() {
        runLock.withLock {
            serviceEngine?.destroy()
            serviceEngine = null
        }
    }

    fun initServiceEngine(context: Context) {
        if (serviceEngine != null) return
        destroyServiceEngine()
        runLock.withLock {
            serviceEngine = FlutterEngine(context)
            serviceEngine?.plugins?.add(VpnPlugin())
            serviceEngine?.plugins?.add(AppPlugin())
            serviceEngine?.plugins?.add(TilePlugin())
            serviceEngine?.plugins?.add(ServicePlugin())
            val vpnService = DartExecutor.DartEntrypoint(
                FlutterInjector.instance().flutterLoader().findAppBundlePath(),
                "vpnService"
            )
            serviceEngine?.dartExecutor?.executeDartEntrypoint(
                vpnService,
            )
        }
    }
}


