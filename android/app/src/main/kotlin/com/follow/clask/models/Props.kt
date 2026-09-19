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
     * Google push (FCM) is carried by Google Play services. When the VPN runs in
     * per-app mode those packages must stay inside the tunnel, otherwise the
     * long-lived MCS connection is dropped and notifications stop arriving.
     * [FCM_PACKAGES] is what gets pinned into the tunnel when [fcmKeepAlive] is on.
     */
    val fcmKeepAlivePackages: List<String>
        get() = if (fcmKeepAlive) FCM_PACKAGES else emptyList()

    companion object {
        /**
         * Packets for FCM flow through these; they are the packages the system
         * attributes the MCS connection to.
         */
        val FCM_PACKAGES = listOf(
            "com.google.android.gms",
            "com.google.android.gsf",
            "com.google.android.gms.persistent",
        )
    }
}