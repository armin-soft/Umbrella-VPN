package ir.umbrella.vpn.bg

import android.net.Network
import android.net.NetworkCapabilities
import android.os.Build
import com.hiddify.core.libbox.InterfaceUpdateListener
import ir.umbrella.vpn.UmbrellaApplication
import java.net.NetworkInterface

object DefaultNetworkMonitor {
    @Volatile
    var defaultNetwork: Network? = null

    @Volatile
    var onNetworkStateChanged: ((Boolean, String) -> Unit)? = null

    @Volatile
    private var listener: InterfaceUpdateListener? = null

    @Volatile
    private var lastReportedFingerprint: String = ""

    fun describeNetwork(network: Network?): Pair<Boolean, String> {
        if (network == null) {
            return false to "offline"
        }
        val caps = runCatching {
            UmbrellaApplication.connectivity.getNetworkCapabilities(network)
        }.getOrNull()
        if (caps == null ||
            caps.hasTransport(NetworkCapabilities.TRANSPORT_VPN) ||
            !caps.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)
        ) {
            return false to "offline"
        }
        val lp = runCatching {
            UmbrellaApplication.connectivity.getLinkProperties(network)
        }.getOrNull()
        val ifName = lp?.interfaceName?.trim().orEmpty()
        val transport = when {
            caps.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) -> "wifi"
            caps.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR) -> "cell"
            caps.hasTransport(NetworkCapabilities.TRANSPORT_ETHERNET) -> "eth"
            else -> "other"
        }
        val addrs = lp?.linkAddresses
            ?.mapNotNull { it.address?.hostAddress }
            ?.sorted()
            ?.joinToString(",")
            .orEmpty()
        return true to "$transport|$ifName|$addrs"
    }

    private fun notifyAppNetwork(network: Network?) {
        val (online, fp) = describeNetwork(network)
        if (fp == lastReportedFingerprint) return
        lastReportedFingerprint = fp
        onNetworkStateChanged?.invoke(online, fp)
    }

    suspend fun start() {
        lastReportedFingerprint = ""
        DefaultNetworkListener.start(this) { network ->
            defaultNetwork = network
            checkDefaultInterfaceUpdate(network)
            notifyAppNetwork(network)
        }
        defaultNetwork = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            UmbrellaApplication.connectivity.activeNetwork
        } else {
            DefaultNetworkListener.get()
        }
        notifyAppNetwork(defaultNetwork)
    }

    suspend fun stop() {
        lastReportedFingerprint = ""
        DefaultNetworkListener.stop(this)
    }

    suspend fun require(): Network {
        defaultNetwork?.let { return it }
        return DefaultNetworkListener.get()
    }

    fun setListener(listener: InterfaceUpdateListener?) {
        this.listener = listener
        checkDefaultInterfaceUpdate(defaultNetwork)
    }

    private fun checkDefaultInterfaceUpdate(newNetwork: Network?) {
        val current = listener ?: return
        if (newNetwork != null) {
            val interfaceName =
                (UmbrellaApplication.connectivity.getLinkProperties(newNetwork) ?: return).interfaceName
                    ?: return
            for (attempt in 0 until 10) {
                val interfaceIndex = try {
                    NetworkInterface.getByName(interfaceName)?.index ?: -1
                } catch (_: Exception) {
                    -1
                }
                if (interfaceIndex >= 0) {
                    current.updateDefaultInterface(interfaceName, interfaceIndex, false, false)
                    return
                }
                Thread.sleep(100)
            }
        } else {
            current.updateDefaultInterface("", -1, false, false)
        }
    }
}
