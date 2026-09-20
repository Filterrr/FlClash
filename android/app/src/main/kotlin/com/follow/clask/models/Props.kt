package com.follow.clask.models

import java.net.InetAddress

enum class AccessControlMode {
    acceptSelected, rejectSelected,
}

data class AccessControl(
    val mode: AccessControlMode,
    val acceptList: List<String>,
    val rejectList: List<String>,
)

data class CIDR(val address: InetAddress, val prefixLength: Int)

/**
 * Package names that can carry the FCM (Google push) connection. The framework
 * rejects unknown package names with
 * [android.content.pm.PackageManager.NameNotFoundException], so consumers must
 * filter this list against the installed packages before handing it to
 * [android.net.VpnService.Builder].
 */
val FCM_CANDIDATE_PACKAGES = listOf(
    "com.google.android.gms",
    "com.google.android.gsf",
)

data class VpnOptions(
    val enable: Boolean,
    val port: Int,
    val accessControl: AccessControl?,
    val allowBypass: Boolean,
    val systemProxy: Boolean,
    val bypassDomain: List<String>,
    val routeAddress: List<String>,
    val ipv4Address: String,
    val ipv6Address: String,
    val dnsServerAddress: String,
    val fcmKeepAlive: Boolean = false,
) {
    /**
     * Package names to pin into the tunnel when [fcmKeepAlive] is on. Still a
     * candidate list: [com.google.android.gms.persistent] is a process name, not
     * a package name, so the caller must intersect with the actually installed
     * packages (see FlClashVpnService).
     */
    val fcmKeepAlivePackages: List<String>
        get() = if (fcmKeepAlive) FCM_CANDIDATE_PACKAGES else emptyList()
}
