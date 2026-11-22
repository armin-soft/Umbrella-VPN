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
import kotlinx.coroutines.CancellableContinuation
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException

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
    private val networkWaiters = mutableSetOf<CancellableContinuation<Network>>()
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
            // Capabilities and link properties may arrive after onAvailable.
            // Remember the candidate so later callbacks can publish it.
            if (current != network) listener?.updateDefaultInterface("", -1, false, false)
            current = network
            publishLocked(network)
        }
    }

    private fun publishLocked(network: Network) {
        if (!registered) return
        val capabilities = connectivity.getNetworkCapabilities(network) ?: return
        if (!capabilities.hasCapability(NetworkCapabilities.NET_CAPABILITY_NOT_VPN)) {
            listener?.updateDefaultInterface("", -1, false, false)
            return
        }
        // Local DNS can be requested while Android is still delivering its
        // first network callback. Wake those requests as soon as the physical
        // network is usable, rather than failing them during startup.
        val waiting = networkWaiters.toList()
        networkWaiters.clear()
        waiting.forEach { if (it.isActive) it.resume(network) }
        val name = connectivity.getLinkProperties(network)?.interfaceName ?: return
        val index = try { NetworkInterface.getByName(name)?.index ?: return } catch (_: Exception) { return }
        listener?.updateDefaultInterface(
            name, index,
            !capabilities.hasCapability(NetworkCapabilities.NET_CAPABILITY_NOT_METERED), false,
        )
    }

    /** Wait for Android's physical-network callback, cancellably, as upstream does.
     * The core's DNS context bounds this wait; never fall back to the VPN. */
    suspend fun awaitNetwork(): Network = suspendCancellableCoroutine { continuation ->
        synchronized(lock) {
            if (!registered) {
                continuation.resumeWithException(IllegalStateException("Network monitor is not active"))
            } else {
                val network = current
                val caps = network?.let { connectivity.getNetworkCapabilities(it) }
                if (network != null && caps?.hasCapability(NetworkCapabilities.NET_CAPABILITY_NOT_VPN) == true) {
                    continuation.resume(network)
                } else {
                    networkWaiters.add(continuation)
                    continuation.invokeOnCancellation { synchronized(lock) { networkWaiters.remove(continuation) } }
                }
            }
        }
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
            val waiting = networkWaiters.toList()
            networkWaiters.clear()
            waiting.forEach { if (it.isActive) it.resumeWithException(IllegalStateException("Network monitor closed")) }
            connectivity.unregisterNetworkCallback(callback)
        }
    }
}
