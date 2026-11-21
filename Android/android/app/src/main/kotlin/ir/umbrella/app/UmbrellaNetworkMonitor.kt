package ir.umbrella.app

import android.net.ConnectivityManager
import android.net.LinkProperties
import android.net.Network
import android.net.NetworkCapabilities
import android.net.NetworkRequest
import android.os.Build
import android.os.Handler
import android.os.Looper
import com.hiddify.core.libbox.InterfaceUpdateListener
import java.net.NetworkInterface

/** Reports the underlying default interface to the mobile engine.
 *
 * Adapted from the hiddify-app v5.9.11 default network listener; see
 * THIRD-PARTY-NOTICES.txt. A VPN must not report itself as its underlying
 * network, or core traffic can loop into the TUN.
 */
internal class UmbrellaNetworkMonitor(private val connectivity: ConnectivityManager) : AutoCloseable {
    private val lock = Any()
    private val mainHandler = Handler(Looper.getMainLooper())
    private var listener: InterfaceUpdateListener? = null
    private var registered = false
    private var current: Network? = null
    private val request = NetworkRequest.Builder()
        .addCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)
        .addCapability(NetworkCapabilities.NET_CAPABILITY_NOT_RESTRICTED)
        .addCapability(NetworkCapabilities.NET_CAPABILITY_NOT_VPN)
        .build()

    private val callback = object : ConnectivityManager.NetworkCallback() {
        override fun onAvailable(network: Network) = update(network)
        override fun onLinkPropertiesChanged(network: Network, properties: LinkProperties) {
            synchronized(lock) { if (current == network) publishLocked(network) }
        }
        override fun onCapabilitiesChanged(network: Network, capabilities: NetworkCapabilities) {
            synchronized(lock) { if (current == network) publishLocked(network) }
        }
        override fun onLost(network: Network) {
            synchronized(lock) {
                if (registered && current == network) {
                    current = null
                    listener?.updateDefaultInterface("", -1, false, false)
                }
            }
        }
    }

    private fun update(network: Network) {
        synchronized(lock) {
            if (!registered) return
            val capabilities = connectivity.getNetworkCapabilities(network) ?: return
            if (!capabilities.hasCapability(NetworkCapabilities.NET_CAPABILITY_NOT_VPN)) return
            current = network
            publishLocked(network)
        }
    }

    private fun publishLocked(network: Network) {
        if (!registered) return
        val capabilities = connectivity.getNetworkCapabilities(network) ?: return
        if (!capabilities.hasCapability(NetworkCapabilities.NET_CAPABILITY_NOT_VPN)) return
        val name = connectivity.getLinkProperties(network)?.interfaceName ?: return
        val index = try { NetworkInterface.getByName(name)?.index ?: return } catch (_: Exception) { return }
        listener?.updateDefaultInterface(
            name, index,
            !capabilities.hasCapability(NetworkCapabilities.NET_CAPABILITY_NOT_METERED), false,
        )
    }

    /** Registration fails closed if Android denies the required network request. */
    fun start(target: InterfaceUpdateListener) {
        synchronized(lock) {
            check(!registered) { "Network monitor already started" }
            listener = target
            registered = true
            try {
                when {
                    Build.VERSION.SDK_INT >= 31 -> connectivity.registerBestMatchingNetworkCallback(request, callback, mainHandler)
                    Build.VERSION.SDK_INT >= 28 -> connectivity.requestNetwork(request, callback, mainHandler)
                    Build.VERSION.SDK_INT >= 26 -> connectivity.registerDefaultNetworkCallback(callback, mainHandler)
                    else -> connectivity.registerDefaultNetworkCallback(callback)
                }
            } catch (error: Exception) {
                registered = false
                listener = null
                throw error
            }
        }
    }

    override fun close() {
        synchronized(lock) {
            if (!registered) return
            // Mark closed first so queued callbacks cannot publish a stale network.
            registered = false
            current = null
            listener = null
            connectivity.unregisterNetworkCallback(callback)
        }
    }
}
