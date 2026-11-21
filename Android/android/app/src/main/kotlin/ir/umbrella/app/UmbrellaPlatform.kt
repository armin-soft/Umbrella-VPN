package ir.umbrella.app

import android.net.NetworkCapabilities
import android.os.Build
import android.os.Process
import android.util.Log
import androidx.annotation.RequiresApi
import android.net.ConnectivityManager
import android.net.VpnService
import com.hiddify.core.libbox.InterfaceUpdateListener
import com.hiddify.core.libbox.Libbox
import com.hiddify.core.libbox.NetworkInterfaceIterator
import com.hiddify.core.libbox.PlatformInterface
import com.hiddify.core.libbox.StringIterator
import com.hiddify.core.libbox.TunOptions
import com.hiddify.core.libbox.WIFIState
import java.net.Inet6Address
import java.net.InetSocketAddress
import java.net.InterfaceAddress
import java.net.NetworkInterface
import com.hiddify.core.libbox.NetworkInterface as LibboxNetworkInterface



import android.system.OsConstants
import com.hiddify.core.libbox.ConnectionOwner
import com.hiddify.core.libbox.AutoRedirectHandler
import com.hiddify.core.libbox.AutoRedirectSession
import com.hiddify.core.libbox.BridgeOptions
import com.hiddify.core.libbox.BridgeSession
import com.hiddify.core.libbox.NeighborUpdateListener
import com.hiddify.core.libbox.PlatformUser
import com.hiddify.core.libbox.ShellSession
import com.hiddify.core.libbox.LocalDNSTransport
import java.security.KeyStore
import android.util.Base64
import com.hiddify.core.libbox.Notification

// Adapted from hiddify-app v5.9.11; attribution and license in THIRD-PARTY-NOTICES.
// This object is owned by the service and must be closed after Mobile.close.
internal class UmbrellaPlatform(
    private val service: VpnService,
    private val tun: UmbrellaTun,
    private val connectivity: ConnectivityManager,
) : PlatformInterface, AutoCloseable {
    private val networkMonitor = UmbrellaNetworkMonitor(connectivity)
    override fun usePlatformAutoDetectInterfaceControl(): Boolean = true

    override fun autoDetectInterfaceControl(fd: Int) = tun.protectSocket(fd)
    override fun openTun(options: TunOptions): Int = tun.open(options)

    @RequiresApi(Build.VERSION_CODES.Q)
    override fun findConnectionOwner(
        ipProtocol: Int,
        sourceAddress: String,
        sourcePort: Int,
        destinationAddress: String,
        destinationPort: Int,
    ): ConnectionOwner {
        try {
            val uid =
                connectivity.getConnectionOwnerUid(
                    ipProtocol,
                    InetSocketAddress(sourceAddress, sourcePort),
                    InetSocketAddress(destinationAddress, destinationPort),
                )
//            if (uid == Process.INVALID_UID)error("android: connection owner not found")

            val owner = ConnectionOwner()
            owner.userId = uid
            if (uid!=Process.INVALID_UID) {
                val packages = service.packageManager.getPackagesForUid(uid)
                owner.userName = packages?.firstOrNull() ?: ""
                owner.setAndroidPackageNames(StringArray(packages.orEmpty().iterator()))
            }
            return owner
        } catch (e: Exception) {
            Log.e("PlatformInterface", "getConnectionOwnerUid", e)
            e.printStackTrace(System.err)
            throw e
        }
    }

    override fun startDefaultInterfaceMonitor(listener: InterfaceUpdateListener) {
        networkMonitor.start(listener)
    }

    override fun closeDefaultInterfaceMonitor(listener: InterfaceUpdateListener) {
        networkMonitor.close()
    }

    override fun getInterfaces(): NetworkInterfaceIterator {
        val networks = connectivity.allNetworks
        val networkInterfaces = NetworkInterface.getNetworkInterfaces().toList()
        val interfaces = mutableListOf<LibboxNetworkInterface>()
        for (network in networks) {
            val boxInterface = LibboxNetworkInterface()
            val linkProperties = connectivity.getLinkProperties(network) ?: continue
            val networkCapabilities =
                connectivity.getNetworkCapabilities(network) ?: continue
            boxInterface.name = linkProperties.interfaceName
            val networkInterface =
                networkInterfaces.find { it.name == boxInterface.name } ?: continue
            boxInterface.dnsServer =
                StringArray(linkProperties.dnsServers.mapNotNull { it.hostAddress }.iterator())
            boxInterface.type =
                when {
                    networkCapabilities.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) -> Libbox.InterfaceTypeWIFI
                    networkCapabilities.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR) -> Libbox.InterfaceTypeCellular
                    networkCapabilities.hasTransport(NetworkCapabilities.TRANSPORT_ETHERNET) -> Libbox.InterfaceTypeEthernet
                    else -> Libbox.InterfaceTypeOther
                }
            boxInterface.index = networkInterface.index
            runCatching {
                boxInterface.mtu = networkInterface.mtu
            }.onFailure {
                Log.e(
                    "PlatformInterface",
                    "failed to get mtu for interface ${boxInterface.name}",
                    it,
                )
            }
            boxInterface.addresses =
                StringArray(
                    networkInterface.interfaceAddresses.mapTo(mutableListOf()) { it.toPrefix() }
                        .iterator(),
                )
            var dumpFlags = 0
            if (networkCapabilities.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)) {
                dumpFlags = OsConstants.IFF_UP or OsConstants.IFF_RUNNING
            }
            if (networkInterface.isLoopback) {
                dumpFlags = dumpFlags or OsConstants.IFF_LOOPBACK
            }
            if (networkInterface.isPointToPoint) {
                dumpFlags = dumpFlags or OsConstants.IFF_POINTOPOINT
            }
            if (networkInterface.supportsMulticast()) {
                dumpFlags = dumpFlags or OsConstants.IFF_MULTICAST
            }
            boxInterface.flags = dumpFlags
            boxInterface.metered =
                !networkCapabilities.hasCapability(NetworkCapabilities.NET_CAPABILITY_NOT_METERED)
            interfaces.add(boxInterface)
        }
        return InterfaceArray(interfaces.iterator())
    }

    override fun underNetworkExtension(): Boolean = false

    override fun includeAllNetworks(): Boolean = false

    override fun clearDNSCache() {
    }

    // WiFi state (SSID/BSSID for wifi_ssid rules) is not read: it needs ACCESS_WIFI_STATE and, on newer
    // Android, location permission; a SecurityException here would abort the process from the Go core.
    override fun readWIFIState(): WIFIState? = null

    private val resolver = UmbrellaLocalResolver(networkMonitor)
    override fun localDNSTransport(): LocalDNSTransport = resolver

    override fun sendNotification(notification: Notification) { }
    override fun cancelNotification(identifier: String, typeID: Int) { }
    override fun close() = networkMonitor.close()

    override fun systemCertificates(): StringIterator {
        val certificates = mutableListOf<String>()
        // Called from the Go core without an error return: must not throw.
        try {
            val keyStore = KeyStore.getInstance("AndroidCAStore")
            if (keyStore != null) {
                keyStore.load(null, null)
                val aliases = keyStore.aliases()
                while (aliases.hasMoreElements()) {
                    val cert = keyStore.getCertificate(aliases.nextElement()) ?: continue
                    certificates.add(
                        "-----BEGIN CERTIFICATE-----\n" + Base64.encodeToString(cert.encoded, Base64.NO_WRAP) + "\n-----END CERTIFICATE-----",
                    )
                }
            }
        } catch (e: Exception) {
            Log.w("PlatformInterface", "systemCertificates", e)
        }
        return StringArray(certificates.iterator())
    }

    // Neighbor monitor, platform shell, bridge and auto-redirect need root helpers
    // (RootClient in sing-box-for-android) which Hiddify does not ship; keep them disabled.
    override fun startNeighborMonitor(listener: NeighborUpdateListener?) {
    }

    override fun closeNeighborMonitor(listener: NeighborUpdateListener?) {
    }

    override fun registerMyInterface(name: String?) {
    }

    override fun usePlatformShell(): Boolean = false

    override fun checkPlatformShell() {
        error("platform shell not supported")
    }

    override fun openShellSession(
        user: PlatformUser?,
        command: String?,
        environ: StringIterator?,
        term: String?,
        rows: Int,
        cols: Int,
    ): ShellSession {
        error("platform shell not supported")
    }

    override fun lookupUser(username: String?): PlatformUser {
        error("platform shell not supported")
    }

    override fun lookupSFTPServer(): String {
        error("not supported")
    }

    override fun readSystemSSHHostKey(): String {
        error("not supported")
    }

    override fun tailscaleHostname(): String = android.provider.Settings.Global.getString(
        service.contentResolver,
        android.provider.Settings.Global.DEVICE_NAME,
    )?.takeIf { it.isNotBlank() }
        ?: "${Build.MANUFACTURER} ${Build.MODEL}"

    override fun usePlatformBridge(): Boolean = false

    override fun createBridge(options: BridgeOptions?): BridgeSession {
        error("platform bridge not supported")
    }

    override fun usePlatformAutoRedirect(): Boolean = false

    override fun createAutoRedirect(options: ByteArray?, handler: AutoRedirectHandler?): AutoRedirectSession {
        error("platform auto redirect not supported")
    }

    private class InterfaceArray(private val iterator: Iterator<LibboxNetworkInterface>) : NetworkInterfaceIterator {
        override fun hasNext(): Boolean = iterator.hasNext()

        override fun next(): LibboxNetworkInterface = iterator.next()
    }

    class StringArray(private val iterator: Iterator<String>) : StringIterator {
        override fun len(): Int {
            // not used by core
            return 0
        }

        override fun hasNext(): Boolean = iterator.hasNext()

        override fun next(): String = iterator.next()
    }

    private fun InterfaceAddress.toPrefix(): String = if (address is Inet6Address) {
        "${Inet6Address.getByAddress(address.address).hostAddress}/$networkPrefixLength"
    } else {
        "${address.hostAddress}/$networkPrefixLength"
    }

}
