package ir.umbrella.vpn.bg

import android.net.NetworkCapabilities
import android.os.Build
import android.os.Process
import android.provider.Settings as AndroidSettings
import android.system.OsConstants
import android.util.Log
import androidx.annotation.RequiresApi
import com.hiddify.core.libbox.AutoRedirectHandler
import com.hiddify.core.libbox.AutoRedirectSession
import com.hiddify.core.libbox.BridgeOptions
import com.hiddify.core.libbox.BridgeSession
import com.hiddify.core.libbox.ConnectionOwner
import com.hiddify.core.libbox.InterfaceUpdateListener
import com.hiddify.core.libbox.Libbox
import com.hiddify.core.libbox.LocalDNSTransport
import com.hiddify.core.libbox.NeighborUpdateListener
import com.hiddify.core.libbox.NetworkInterface as LibboxNetworkInterface
import com.hiddify.core.libbox.NetworkInterfaceIterator
import com.hiddify.core.libbox.Notification
import com.hiddify.core.libbox.PlatformInterface
import com.hiddify.core.libbox.PlatformUser
import com.hiddify.core.libbox.ShellSession
import com.hiddify.core.libbox.StringIterator
import com.hiddify.core.libbox.TunOptions
import com.hiddify.core.libbox.WIFIState
import ir.umbrella.vpn.UmbrellaApplication
import java.net.Inet6Address
import java.net.InetSocketAddress
import java.net.InterfaceAddress
import java.net.NetworkInterface
import java.security.KeyStore
import kotlin.io.encoding.Base64
import kotlin.io.encoding.ExperimentalEncodingApi

interface PlatformInterfaceWrapper : PlatformInterface {
    override fun usePlatformAutoDetectInterfaceControl(): Boolean = true

    override fun autoDetectInterfaceControl(fd: Int) {
    }

    override fun openTun(options: TunOptions): Int {
        error("openTun requires VPNService")
    }

    @RequiresApi(Build.VERSION_CODES.Q)
    override fun findConnectionOwner(
        ipProtocol: Int,
        sourceAddress: String,
        sourcePort: Int,
        destinationAddress: String,
        destinationPort: Int,
    ): ConnectionOwner {
        val uid = UmbrellaApplication.connectivity.getConnectionOwnerUid(
            ipProtocol,
            InetSocketAddress(sourceAddress, sourcePort),
            InetSocketAddress(destinationAddress, destinationPort),
        )
        val owner = ConnectionOwner()
        owner.userId = uid
        if (uid != Process.INVALID_UID) {
            val packages = UmbrellaApplication.packageManager.getPackagesForUid(uid)
            owner.userName = packages?.firstOrNull() ?: ""
            owner.setAndroidPackageNames(StringArray(packages.orEmpty().iterator()))
        }
        return owner
    }

    override fun startDefaultInterfaceMonitor(listener: InterfaceUpdateListener) {
        DefaultNetworkMonitor.setListener(listener)
    }

    override fun closeDefaultInterfaceMonitor(listener: InterfaceUpdateListener) {
        DefaultNetworkMonitor.setListener(null)
    }

    override fun getInterfaces(): NetworkInterfaceIterator {
        val networks = UmbrellaApplication.connectivity.allNetworks
        val networkInterfaces = runCatching {
            NetworkInterface.getNetworkInterfaces()?.toList().orEmpty()
        }.getOrDefault(emptyList())
        val interfaces = mutableListOf<LibboxNetworkInterface>()
        for (network in networks) {
            val linkProperties = UmbrellaApplication.connectivity.getLinkProperties(network) ?: continue
            val networkCapabilities =
                UmbrellaApplication.connectivity.getNetworkCapabilities(network) ?: continue
            val ifName = linkProperties.interfaceName ?: continue
            val networkInterface = networkInterfaces.find { it.name == ifName } ?: continue

            val boxInterface = LibboxNetworkInterface()
            boxInterface.name = ifName
            boxInterface.dnsServer =
                StringArray(linkProperties.dnsServers.mapNotNull { it.hostAddress }.iterator())
            boxInterface.type = when {
                networkCapabilities.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) -> Libbox.InterfaceTypeWIFI
                networkCapabilities.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR) -> Libbox.InterfaceTypeCellular
                networkCapabilities.hasTransport(NetworkCapabilities.TRANSPORT_ETHERNET) -> Libbox.InterfaceTypeEthernet
                else -> Libbox.InterfaceTypeOther
            }
            boxInterface.index = networkInterface.index
            runCatching {
                boxInterface.mtu = networkInterface.mtu
            }.onFailure {
                Log.w("PlatformInterface", "failed to get mtu for ${boxInterface.name}", it)
            }
            boxInterface.addresses = StringArray(
                networkInterface.interfaceAddresses.mapTo(mutableListOf()) { it.toPrefix() }.iterator(),
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

    override fun readWIFIState(): WIFIState? = null

    override fun localDNSTransport(): LocalDNSTransport? = LocalResolver

    @OptIn(ExperimentalEncodingApi::class)
    override fun systemCertificates(): StringIterator {
        val certificates = mutableListOf<String>()
        try {
            val keyStore = KeyStore.getInstance("AndroidCAStore")
            if (keyStore != null) {
                keyStore.load(null, null)
                val aliases = keyStore.aliases()
                while (aliases.hasMoreElements()) {
                    val cert = keyStore.getCertificate(aliases.nextElement()) ?: continue
                    certificates.add(
                        "-----BEGIN CERTIFICATE-----\n" +
                            Base64.encode(cert.encoded) +
                            "\n-----END CERTIFICATE-----",
                    )
                }
            }
        } catch (e: Exception) {
            Log.w("PlatformInterface", "systemCertificates", e)
        }
        return StringArray(certificates.iterator())
    }

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

    override fun tailscaleHostname(): String = AndroidSettings.Global.getString(
        UmbrellaApplication.application.contentResolver,
        AndroidSettings.Global.DEVICE_NAME,
    )?.takeIf { it.isNotBlank() }
        ?: "${Build.MANUFACTURER} ${Build.MODEL}"

    override fun usePlatformBridge(): Boolean = false

    override fun createBridge(options: BridgeOptions?): BridgeSession {
        error("platform bridge not supported")
    }

    override fun usePlatformAutoRedirect(): Boolean = false

    override fun createAutoRedirect(
        options: ByteArray?,
        handler: AutoRedirectHandler?,
    ): AutoRedirectSession {
        error("platform auto redirect not supported")
    }

    override fun sendNotification(notification: Notification) {
    }

    override fun cancelNotification(identifier: String, typeID: Int) {
    }

    private class InterfaceArray(
        private val iterator: Iterator<LibboxNetworkInterface>,
    ) : NetworkInterfaceIterator {
        override fun hasNext(): Boolean = iterator.hasNext()

        override fun next(): LibboxNetworkInterface = iterator.next()
    }

    class StringArray(private val iterator: Iterator<String>) : StringIterator {
        override fun len(): Int = 0

        override fun hasNext(): Boolean = iterator.hasNext()

        override fun next(): String = iterator.next()
    }

    private fun InterfaceAddress.toPrefix(): String = if (address is Inet6Address) {
        "${Inet6Address.getByAddress(address.address).hostAddress}/$networkPrefixLength"
    } else {
        "${address.hostAddress}/$networkPrefixLength"
    }
}
