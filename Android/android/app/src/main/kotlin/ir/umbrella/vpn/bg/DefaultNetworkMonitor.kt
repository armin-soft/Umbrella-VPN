package ir.umbrella.vpn.bg

import android.net.Network
import android.os.Build
import com.hiddify.core.libbox.InterfaceUpdateListener
import ir.umbrella.vpn.UmbrellaApplication
import java.net.NetworkInterface

object DefaultNetworkMonitor {
    @Volatile
    var defaultNetwork: Network? = null

    @Volatile
    private var listener: InterfaceUpdateListener? = null

    suspend fun start() {
        DefaultNetworkListener.start(this) { network ->
            defaultNetwork = network
            checkDefaultInterfaceUpdate(network)
        }
        defaultNetwork = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            UmbrellaApplication.connectivity.activeNetwork
        } else {
            DefaultNetworkListener.get()
        }
    }

    suspend fun stop() {
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
