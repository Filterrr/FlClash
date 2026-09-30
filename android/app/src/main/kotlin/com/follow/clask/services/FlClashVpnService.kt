package com.follow.clask.services

import android.annotation.SuppressLint
import android.app.Notification.FOREGROUND_SERVICE_IMMEDIATE
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Intent
import android.content.pm.ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE
import android.net.Network
import android.net.ProxyInfo
import android.net.VpnService
import android.os.Binder
import android.os.Build
import android.os.IBinder
import android.os.Parcel
import android.util.Log
import androidx.core.app.NotificationCompat
import com.follow.clask.BaseServiceInterface
import com.follow.clask.GlobalState
import com.follow.clask.MainActivity
import com.follow.clask.R
import com.follow.clask.RunState
import com.follow.clask.extensions.getActionPendingIntent
import com.follow.clask.extensions.getIpv4RouteAddress
import com.follow.clask.extensions.getIpv6RouteAddress
import com.follow.clask.extensions.toCIDR
import com.follow.clask.models.AccessControlMode
import com.follow.clask.models.VpnOptions
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch


class FlClashVpnService : VpnService(), BaseServiceInterface {
    override fun onCreate() {
        super.onCreate()
        screenStateWatcher.start()
        GlobalState.initServiceEngine(applicationContext)
    }

    /**
     * 处理系统直接启动服务的情形：
     *
     * 1. 常驻 VPN（always-on）：系统通过 startService 拉起本服务，
     *    不经过 App 的绑定路径。onCreate 中的 initServiceEngine 会启动
     *    服务引擎，Dart 侧随后沿正常的 handleStart 流程重建隧道。
     * 2. 进程被系统回收后重启：返回 START_STICKY 让系统在资源允许时
     *    重新拉起服务，避免 VPN 静默失效（隧道随进程一起消失）。
     *
     * 用户主动停止（stopSelf / stopService）不会被 STICKY 重新拉起。
     */
    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        return START_STICKY
    }

    override fun start(options: VpnOptions): Int {
        return with(Builder()) {
            if (options.ipv4Address.isNotEmpty()) {
                val cidr = options.ipv4Address.toCIDR()
                addAddress(cidr.address, cidr.prefixLength)
                val routeAddress = options.getIpv4RouteAddress()
                if (routeAddress.isNotEmpty()) {
                    routeAddress.forEach { i ->
                        Log.d("addRoute4", "address: ${i.address} prefixLength:${i.prefixLength}")
                        addRoute(i.address, i.prefixLength)
                    }
                } else {
                    addRoute("0.0.0.0", 0)
                }
            }
            if (options.ipv6Address.isNotEmpty()) {
                val cidr = options.ipv6Address.toCIDR()
                addAddress(cidr.address, cidr.prefixLength)
                val routeAddress = options.getIpv6RouteAddress()
                if (routeAddress.isNotEmpty()) {
                    routeAddress.forEach { i ->
                        Log.d("addRoute6", "address: ${i.address} prefixLength:${i.prefixLength}")
                        addRoute(i.address, i.prefixLength)
                    }
                } else {
                    addRoute("::", 0)
                }
            }
            addDnsServer(options.dnsServerAddress)
            setMtu(options.mtu)
            options.accessControl?.let { accessControl ->
                // Builder 对未安装的包名会抛 NameNotFoundException，
                // 因此仅对候选包做（少量）存在性检查，避免整表扫描。
                val fcmPackages = if (options.fcmKeepAlive) {
                    options.fcmKeepAlivePackages.filter { isPackageInstalled(it) }
                } else {
                    emptyList()
                }
                when (accessControl.mode) {
                    AccessControlMode.acceptSelected -> {
                        val allowed = accessControl.acceptList + packageName + fcmPackages
                        allowed.distinct().forEach {
                            addAllowedApplication(it)
                        }
                    }

                    AccessControlMode.rejectSelected -> {
                        val disallowed = accessControl.rejectList - packageName - fcmPackages.toSet()
                        disallowed.forEach {
                            addDisallowedApplication(it)
                        }
                    }
                }
            }
            setSession("FlClash")
            setBlocking(false)
            if (Build.VERSION.SDK_INT >= 29) {
                setMetered(false)
            }
            if (options.allowBypass) {
                allowBypass()
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q && options.systemProxy) {
                setHttpProxy(
                    ProxyInfo.buildDirectProxy(
                        "127.0.0.1",
                        options.port,
                        options.bypassDomain
                    )
                )
            }
            establish()?.detachFd()
                ?: throw NullPointerException("Establish VPN rejected by system")
        }
    }

    fun updateUnderlyingNetworks(networks: Array<Network>?) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP_MR1) {
            this.setUnderlyingNetworks(networks)
        }
    }

    /**
     * 判断候选包是否已安装。
     *
     * 候选包只有两个（见 [com.follow.clask.models.FCM_CANDIDATE_PACKAGES]），
     * 逐包查询即可；相比 getInstalledPackages 全量列举（数百个包、
     * 建立 PackageInfo 列表），在 VPN 启动这段同步路径上开销可忽略。
     */
    private fun isPackageInstalled(packageName: String): Boolean {
        return try {
            packageManager.getPackageInfo(packageName, 0)
            true
        } catch (_: Exception) {
            false
        }
    }

    override fun stop() {
        stopSelf()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            stopForeground(STOP_FOREGROUND_REMOVE)
        }
    }

    private val CHANNEL = "FlClash"

    private val notificationId: Int = 1

    private val notificationBuilder: NotificationCompat.Builder by lazy {
        val intent = Intent(this, MainActivity::class.java)

        val pendingIntent = if (Build.VERSION.SDK_INT >= 31) {
            PendingIntent.getActivity(
                this,
                0,
                intent,
                PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
            )
        } else {
            PendingIntent.getActivity(
                this,
                0,
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT
            )
        }

        with(NotificationCompat.Builder(this, CHANNEL)) {
            setSmallIcon(R.drawable.ic_stat_name)
            setContentTitle("FlClash")
            setContentIntent(pendingIntent)
            setCategory(NotificationCompat.CATEGORY_SERVICE)
            priority = NotificationCompat.PRIORITY_MIN
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                foregroundServiceBehavior = FOREGROUND_SERVICE_IMMEDIATE
            }
            setOngoing(true)
            addAction(
                0,
                GlobalState.getText("stop"),
                getActionPendingIntent("STOP")
            )
            setShowWhen(false)
            setOnlyAlertOnce(true)
            setAutoCancel(true)
            // 省电优化：减少通知声音和震动
            setSilent(true)
        }
    }

    // 缓存上次通知内容，避免相同内容重复更新
    private var lastNotificationTitle: String = ""
    private var lastNotificationContent: String = ""

    private val screenStateWatcher by lazy { ScreenStateWatcher(this) }

    // 是否已经成功进入过前台。首个 startForeground 调用必须放行，
    // 否则 Android 12+ 会因服务未在时限内进入前台而崩溃。
    @Volatile
    private var enteredForeground = false

    @SuppressLint("ForegroundServiceType", "WrongConstant")
    override fun startForeground(title: String, content: String) {
        val forceRefresh = screenStateWatcher.consumeRefreshRequest()
        // 屏幕熄灭期间冻结通知刷新：此时内容无人查看，
        // 每次更新都会唤醒 NotificationManager；亮屏后强制刷新一次。
        if (!forceRefresh && enteredForeground && screenStateWatcher.shouldDeferNotification) {
            return
        }
        // 跳过内容完全相同的通知更新，减少系统通知管理器的 CPU 唤醒
        if (!forceRefresh &&
            enteredForeground &&
            title == lastNotificationTitle &&
            content == lastNotificationContent
        ) {
            return
        }
        lastNotificationTitle = title
        lastNotificationContent = content
        CoroutineScope(Dispatchers.Default).launch {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                val manager = getSystemService(NotificationManager::class.java)
                var channel = manager?.getNotificationChannel(CHANNEL)
                if (channel == null) {
                    channel =
                        NotificationChannel(CHANNEL, "FlClash", NotificationManager.IMPORTANCE_LOW)
                    manager?.createNotificationChannel(channel)
                }
            }
            val notification =
                notificationBuilder
                    .setContentTitle(title)
                    .setContentText(content)
                    .build()
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
                startForeground(notificationId, notification, FOREGROUND_SERVICE_TYPE_SPECIAL_USE)
            } else {
                startForeground(notificationId, notification)
            }
            enteredForeground = true
        }
    }

    override fun onTrimMemory(level: Int) {
        super.onTrimMemory(level)
        // 仅在中高内存压力时触发 GC，低级别时跳过以减少 CPU 唤醒
        if (level >= TRIM_MEMORY_RUNNING_LOW) {
            GlobalState.getCurrentVPNPlugin()?.requestGc()
        }
    }

    /**
     * 系统撤销 VPN（用户切换/关闭其他 VPN、撤销授权等）时回调。
     *
     * 此时隧道已被系统拆除，但本应用仍可能显示“已连接”、快速设置磁贴
     * 停留在激活态，且自身持有的绑定会让服务无法真正销毁。因此这里要：
     * 1) 通知 App 侧停止（复用磁贴停止链路）；
     * 2) 释放本应用自己的 ServiceConnection；
     * 3) 关闭服务与前台通知。
     */
    override fun onRevoke() {
        CoroutineScope(Dispatchers.Main).launch {
            notifyVpnRevoked()
        }
        stop()
        super.onRevoke()
    }

    private fun notifyVpnRevoked() {
        if (GlobalState.getCurrentTilePlugin() != null) {
            GlobalState.handleStop()
        } else {
            // 没有可通知的 Flutter 引擎：直接复位运行状态，
            // 避免 runState 停留在 PENDING 导致后续开关失效。
            GlobalState.runState.value = RunState.STOP
        }
        GlobalState.getCurrentVPNPlugin()?.releaseBinding()
    }

    private val binder = LocalBinder()

    inner class LocalBinder : Binder() {
        fun getService(): FlClashVpnService = this@FlClashVpnService

        override fun onTransact(code: Int, data: Parcel, reply: Parcel?, flags: Int): Boolean {
            if (code == IBinder.LAST_CALL_TRANSACTION) {
                // 系统通过该事务告知 VPN 权限被撤销，语义与框架
                // VpnService.Callback 一致。本服务覆写了 onBind，
                // 系统事务会直接送达此 Binder，需在此显式处理。
                onRevoke()
                return true
            }
            return super.onTransact(code, data, reply, flags)
        }
    }

    override fun onBind(intent: Intent): IBinder {
        return binder
    }

    override fun onUnbind(intent: Intent?): Boolean {
        return super.onUnbind(intent)
    }

    override fun onDestroy() {
        screenStateWatcher.stop()
        stop()
        super.onDestroy()
    }
}
