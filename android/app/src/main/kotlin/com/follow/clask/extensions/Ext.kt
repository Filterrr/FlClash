package com.follow.clask.extensions

import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.drawable.Drawable
import android.net.ConnectivityManager
import android.net.Network
import android.os.Build
import android.system.OsConstants.IPPROTO_TCP
import android.system.OsConstants.IPPROTO_UDP
import android.util.Base64
import androidx.core.graphics.drawable.toBitmap
import com.follow.clask.TempActivity
import com.follow.clask.models.CIDR
import com.follow.clask.models.Metadata
import com.follow.clask.models.VpnOptions
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeoutOrNull
import java.io.ByteArrayOutputStream
import java.net.Inet4Address
import java.net.Inet6Address
import java.net.InetAddress
import kotlin.coroutines.resume
import kotlin.coroutines.suspendCoroutine


suspend fun Drawable.getBase64(): String {
    val drawable = this
    return withContext(Dispatchers.IO) {
        val bitmap = drawable.toBitmap()
        val byteArrayOutputStream = ByteArrayOutputStream()
        bitmap.compress(Bitmap.CompressFormat.PNG, 100, byteArrayOutputStream)
        Base64.encodeToString(byteArrayOutputStream.toByteArray(), Base64.NO_WRAP)
    }
}

fun Metadata.getProtocol(): Int? {
    if (network.startsWith("tcp")) return IPPROTO_TCP
    if (network.startsWith("udp")) return IPPROTO_UDP
    return null
}

fun VpnOptions.getIpv4RouteAddress(): List<CIDR> {
    return routeAddress.filter {
        it.isIpv4()
    }.map {
        it.toCIDR()
    }
}

fun VpnOptions.getIpv6RouteAddress(): List<CIDR> {
    return routeAddress.filter {
        it.isIpv6()
    }.map {
        it.toCIDR()
    }
}

fun String.isIpv4(): Boolean {
    val parts = split("/")
    if (parts.size != 2) {
        throw IllegalArgumentException("Invalid CIDR format")
    }
    val address = InetAddress.getByName(parts[0])
    return address.address.size == 4
}

fun String.isIpv6(): Boolean {
    val parts = split("/")
    if (parts.size != 2) {
        throw IllegalArgumentException("Invalid CIDR format")
    }
    val address = InetAddress.getByName(parts[0])
    return address.address.size == 16
}

fun String.toCIDR(): CIDR {
    val parts = split("/")
    if (parts.size != 2) {
        throw IllegalArgumentException("Invalid CIDR format")
    }
    val ipAddress = parts[0]
    val prefixLength = parts[1].toIntOrNull()
        ?: throw IllegalArgumentException("Invalid prefix length")

    val address = InetAddress.getByName(ipAddress)

    val maxPrefix = if (address.address.size == 4) 32 else 128
    if (prefixLength < 0 || prefixLength > maxPrefix) {
        throw IllegalArgumentException("Invalid prefix length for IP version")
    }

    return CIDR(address, prefixLength)
}


fun ConnectivityManager.resolveDns(network: Network?): List<String> {
    val properties = getLinkProperties(network) ?: return listOf()
    return properties.dnsServers.map { it.asSocketAddressText(53) }
}

fun InetAddress.asSocketAddressText(port: Int): String {
    return when (this) {
        is Inet6Address ->
            "[${numericToTextFormat(this.address)}]:$port"

        is Inet4Address ->
            "${this.hostAddress}:$port"

        else -> throw IllegalArgumentException("Unsupported Inet type ${this.javaClass}")
    }
}

fun Context.wrapAction(action: String): String {
    return "${this.packageName}.action.$action"
}

fun Context.getActionIntent(action: String): Intent {
    val actionIntent = Intent(this, TempActivity::class.java)
    actionIntent.action = wrapAction(action)
    return actionIntent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_MULTIPLE_TASK)
}

fun Context.getActionPendingIntent(action: String): PendingIntent {
    return if (Build.VERSION.SDK_INT >= 31) {
        PendingIntent.getActivity(
            this,
            0,
            getActionIntent(action),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        )
    } else {
        PendingIntent.getActivity(
            this,
            0,
            getActionIntent(action),
            PendingIntent.FLAG_UPDATE_CURRENT
        )
    }
}


private fun numericToTextFormat(src: ByteArray): String {
    val sb = StringBuilder(39)
    for (i in 0 until 8) {
        sb.append(
            Integer.toHexString(
                src[i shl 1].toInt() shl 8 and 0xff00
                        or (src[(i shl 1) + 1].toInt() and 0xff)
            )
        )
        if (i < 7) {
            sb.append(":")
        }
    }
    return sb.toString()
}

private const val defaultAwaitTimeoutMillis = 1_500L

/**
 * 请求目标引擎的方法并等待结果。
 *
 * 必须有超时:目标引擎的 Dart handler 尚未注册(引擎刚创建)或引擎正在销毁时,
 * 结果回调永远不会触发,调用方(如用 runBlocking 取通知文案的
 * AppPlugin.getText)会永久阻塞,连带 startForeground 永远执行不到。
 */
suspend fun <T> MethodChannel.awaitResult(
    method: String,
    arguments: Any? = null,
    timeoutMillis: Long = defaultAwaitTimeoutMillis,
): T? = withTimeoutOrNull(timeoutMillis) {
    withContext(Dispatchers.Main) {
        // 用 suspendCancellableCoroutine + isActive 判断:超时后内层协程已被取消,
        // 此时若 Dart 侧的回包才到,直接 resume 会抛 IllegalStateException。
        suspendCancellableCoroutine { continuation ->
            invokeMethod(method, arguments, object : MethodChannel.Result {
                override fun success(result: Any?) {
                    if (!continuation.isActive) {
                        return
                    }
                    @Suppress("UNCHECKED_CAST")
                    continuation.resume(result as T)
                }

                override fun error(code: String, message: String?, details: Any?) {
                    if (continuation.isActive) {
                        continuation.resume(null)
                    }
                }

                override fun notImplemented() {
                    if (continuation.isActive) {
                        continuation.resume(null)
                    }
                }
            })
        }
    }
}