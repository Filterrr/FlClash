package com.follow.clask.plugins

import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.ServiceConnection
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.net.NetworkRequest
import android.os.Build
import android.os.IBinder
import android.util.Log
import androidx.core.content.getSystemService
import com.follow.clask.BaseServiceInterface
import com.follow.clask.GlobalState
import com.follow.clask.RunState
import com.follow.clask.extensions.getProtocol
import com.follow.clask.extensions.resolveDns
import com.follow.clask.models.Process
import com.follow.clask.models.VpnOptions
import com.follow.clask.services.FlClashService
import com.follow.clask.services.FlClashVpnService
import com.google.gson.Gson
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.net.InetSocketAddress
import kotlin.concurrent.withLock


class VpnPlugin : FlutterPlugin, MethodChannel.MethodCallHandler {
    private lateinit var flutterMethodChannel: MethodChannel
    private lateinit var context: Context
    private var flClashService: BaseServiceInterface? = null

    // 是否已成功建立绑定。用于保证 unbindService 与 bindService 严格配对：
    // 对未绑定的连接调用 unbindService 会抛 IllegalArgumentException。
    private var isBound = false
    private lateinit var options: VpnOptions
    private lateinit var scope: CoroutineScope

    private val connectivity by lazy {
        context.getSystemService<ConnectivityManager>()
    }

    private val connection = object : ServiceConnection {
        override fun onServiceConnected(className: ComponentName, service: IBinder) {
            flClashService = when (service) {
                is FlClashVpnService.LocalBinder -> service.getService()
                is FlClashService.LocalBinder -> service.getService()
                else -> throw Exception("invalid binder")
            }
            updateUnderlyingNetworks()
            start()
        }

        override fun onServiceDisconnected(arg: ComponentName) {
            flClashService = null
        }
    }

    override fun onAttachedToEngine(flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
        scope = CoroutineScope(Dispatchers.Default)
        context = flutterPluginBinding.applicationContext
        scope.launch {
            registerNetworkCallback()
        }
        flutterMethodChannel = MethodChannel(flutterPluginBinding.binaryMessenger, "vpn")
        flutterMethodChannel.setMethodCallHandler(this)
    }

    override fun onDetachedFromEngine(flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
        unRegisterNetworkCallback()
        // 注意：这里只释放本实例持有的绑定，绝不能顺带 stopService。
        // 主 UI 引擎被销毁（用户划掉应用）时本方法同样会被调用，
        // 而 VPN 服务应当继续在后台运行。
        unbindServiceSafely()
        flutterMethodChannel.setMethodCallHandler(null)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "start" -> {
                val data = call.argument<String>("data")
                options = Gson().fromJson(data, VpnOptions::class.java)
                when (options.enable) {
                    true -> handleStartVpn()
                    false -> start()
                }
                result.success(true)
            }

            "stop" -> {
                stop()
                result.success(true)
            }

            "setProtect" -> {
                val fd = call.argument<Int>("fd")
                if (fd != null) {
                    if (flClashService is FlClashVpnService) {
                        (flClashService as FlClashVpnService).protect(fd)
                    }
                    result.success(true)
                } else {
                    result.success(false)
                }
            }

            "startForeground" -> {
                val title = call.argument<String>("title") as String
                val content = call.argument<String>("content") as String
                startForeground(title, content)
                result.success(true)
            }

            "resolverProcess" -> {
                val data = call.argument<String>("data")
                val process = if (data != null) Gson().fromJson(
                    data, Process::class.java
                ) else null
                val metadata = process?.metadata
                if (metadata == null) {
                    result.success(null)
                    return
                }
                val protocol = metadata.getProtocol()
                if (protocol == null) {
                    result.success(null)
                    return
                }
                scope.launch {
                    withContext(Dispatchers.Default) {
                        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
                            result.success(null)
                            return@withContext
                        }
                        val src = InetSocketAddress(metadata.sourceIP, metadata.sourcePort)
                        val dst = InetSocketAddress(
                            metadata.destinationIP.ifEmpty { metadata.host },
                            metadata.destinationPort
                        )
                        val uid = try {
                            connectivity?.getConnectionOwnerUid(protocol, src, dst)
                        } catch (_: Exception) {
                            null
                        }
                        if (uid == null || uid == -1) {
                            result.success(null)
                            return@withContext
                        }
                        val packages = context.packageManager?.getPackagesForUid(uid)
                        result.success(packages?.first())
                    }
                }
            }

            else -> {
                result.notImplemented()
            }
        }
    }

    private fun handleStartVpn() {
        GlobalState.getCurrentAppPlugin()?.requestVpnPermission(context) {
            start()
        }
    }

    fun requestGc() {
        flutterMethodChannel.invokeMethod("gc", null)
    }

    private val networks = mutableSetOf<Network>()

    private val networksLock = Any()

    fun onUpdateNetwork() {
        updateUnderlyingNetworks()
        val dns = synchronized(networksLock) {
            networks.flatMap { network ->
                connectivity?.resolveDns(network) ?: emptyList()
            }
        }.toSet().joinToString(",")
        scope.launch {
            withContext(Dispatchers.Main) {
                flutterMethodChannel.invokeMethod("dnsChanged", dns)
            }
        }
    }

    /**
     * Keeps the VpnService's underlying networks in sync with connectivity
     * changes. Passing an empty array would tell the system the VPN has no
     * usable underlying network (a startup race or full connectivity loss
     * would then blackhole traffic), so an empty snapshot keeps the system's
     * default tracking by passing null instead.
     */
    private fun updateUnderlyingNetworks() {
        val service = flClashService
        if (service is FlClashVpnService) {
            val snapshot = synchronized(networksLock) { networks.toTypedArray() }
            service.updateUnderlyingNetworks(snapshot.ifEmpty { null })
        }
    }

    private val callback = object : ConnectivityManager.NetworkCallback() {
        override fun onAvailable(network: Network) {
            synchronized(networksLock) {
                networks.add(network)
            }
            onUpdateNetwork()
        }

        override fun onLost(network: Network) {
            synchronized(networksLock) {
                networks.remove(network)
            }
            onUpdateNetwork()
        }
    }

    private val request = NetworkRequest.Builder().apply {
        addCapability(NetworkCapabilities.NET_CAPABILITY_NOT_VPN)
        addCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)
        addCapability(NetworkCapabilities.NET_CAPABILITY_NOT_RESTRICTED)
    }.build()

    private fun registerNetworkCallback() {
        synchronized(networksLock) {
            networks.clear()
        }
        connectivity?.registerNetworkCallback(request, callback)
    }

    private fun unRegisterNetworkCallback() {
        connectivity?.unregisterNetworkCallback(callback)
        synchronized(networksLock) {
            networks.clear()
        }
        onUpdateNetwork()
    }

    private fun startForeground(title: String, content: String) {
        GlobalState.runLock.withLock {
            if (GlobalState.runState.value != RunState.START) return
            flClashService?.startForeground(title, content)
        }
    }

    private fun start() {
        if (flClashService == null) {
            bindService()
            return
        }
        var startFailed = false
        GlobalState.runLock.withLock {
            if (GlobalState.runState.value == RunState.START) return
            GlobalState.runState.value = RunState.START
            val fd = try {
                flClashService?.start(options)
            } catch (e: Exception) {
                // VPN 建立失败：绝不能停留在 START。残留的 START 会让
                // 快速设置磁贴显示“已连接”，而实际没有任何隧道在保护
                // 流量——用户以为代理生效时，全部流量都在直连。
                Log.w("VpnPlugin", "VPN start failed", e)
                null
            }
            if (fd == null) {
                startFailed = true
            } else {
                flutterMethodChannel.invokeMethod(
                    "started", fd
                )
            }
        }
        if (startFailed) {
            abortStart()
        }
    }

    /**
     * 启动未完成（隧道建立失败、系统授权被拒等）时的兜底清理：
     * 复位运行状态、释放绑定、停掉服务实例，并通知界面复位。
     * 让用户随后可以重新发起启动。
     *
     * 引擎销毁投递到主线程，避免在方法通道回调栈内销毁引擎自身；
     * 执行前复查状态：若用户已重新发起启动（状态离开 STOP），
     * 则保留引擎供重试复用，不做销毁。
     */
    fun abortStart() {
        GlobalState.runLock.withLock {
            GlobalState.runState.value = RunState.STOP
        }
        unbindServiceSafely()
        stopBackgroundServices()
        // 仅在存在前台 UI 引擎时通知界面复位（走与「用户主动停止」相同的
        // 链路，复位按钮与流量统计）。无 UI 引擎时不发：该通道的接收者
        // 是服务引擎自己，其 onStop 会执行 exit(0) 强杀进程——那是
        // 用户主动停止的语义，不适用于一次失败的启动。
        if (GlobalState.flutterEngine != null) {
            GlobalState.getCurrentTilePlugin()?.handleStop()
        }
        CoroutineScope(Dispatchers.Main).launch {
            GlobalState.runLock.withLock {
                if (GlobalState.runState.value == RunState.STOP) {
                    GlobalState.destroyServiceEngine()
                }
            }
        }
        Log.w("VpnPlugin", "aborted an incomplete VPN start")
    }

    fun stop() {
        GlobalState.runLock.withLock {
            if (GlobalState.runState.value == RunState.STOP) return
            GlobalState.runState.value = RunState.STOP
            flClashService?.stop()
        }
        unbindServiceSafely()
        // 显式停止：连同系统（always-on / 粘性重启）自行拉起的实例一并结束。
        // 仅在此路径执行，避免误停后台仍在工作的服务。
        stopBackgroundServices()
        GlobalState.destroyServiceEngine()
    }

    /**
     * 供系统撤销 VPN 时（FlClashVpnService.onRevoke）回调，仅释放绑定。
     *
     * 与 [stop] 的区别：此时隧道已由系统拆除、Flutter 引擎可能已不可用，
     * 因此不再下发 stop 指令，只清掉本地连接与缓存引用。
     */
    fun releaseBinding() {
        unbindServiceSafely()
    }

    /**
     * 释放本实例持有的 ServiceConnection。
     *
     * 旧实现只 bindService 从不 unbindService：Service 因绑定而存活，即使
     * 销毁了 Flutter engine，系统仍会因未释放的连接而重建服务，出现
     * “App 显示已停止、服务却仍在运行”的幽灵服务，并持续持有资源。
     */
    private fun unbindServiceSafely() {
        if (!isBound) return
        try {
            context.unbindService(connection)
        } catch (_: IllegalArgumentException) {
            // 已被系统解绑时忽略
        }
        isBound = false
        flClashService = null
    }

    /**
     * 停止可能由系统（always-on / 粘性重启）自行拉起、不受本进程绑定
     * 生命周期约束的服务实例。仅在用户显式停止时调用。
     */
    private fun stopBackgroundServices() {
        listOf(
            FlClashVpnService::class.java,
            FlClashService::class.java,
        ).forEach { serviceClass ->
            try {
                context.stopService(Intent(context, serviceClass))
            } catch (_: Exception) {
                // 服务未运行时忽略
            }
        }
    }

    private fun bindService() {
        val intent = when (options.enable) {
            true -> Intent(context, FlClashVpnService::class.java)
            false -> Intent(context, FlClashService::class.java)
        }
        isBound = context.bindService(intent, connection, Context.BIND_AUTO_CREATE)
    }

}
