package ir.umbrella.app

import android.content.pm.PackageManager
import android.net.InetAddresses
import android.net.IpPrefix
import android.net.VpnService
import android.os.Build
import android.os.ParcelFileDescriptor
import com.hiddify.core.libbox.Libbox
import com.hiddify.core.libbox.TunOptions

/** Owns the TUN descriptor until the service stops or VPN consent is revoked.
 * This class is not a service and does not start the engine on its own.
 */
internal class UmbrellaTun(private val service: VpnService) : AutoCloseable {
    private var descriptor: ParcelFileDescriptor? = null
    val isOpen: Boolean
        @Synchronized get() = descriptor != null

    /** Protect the core's outbound sockets against looping back into its TUN. */
    fun protectSocket(fd: Int) {
        check(service.protect(fd)) { "Cannot protect VPN outbound socket" }
    }

    @Synchronized
    fun open(options: TunOptions): Int {
        check(descriptor == null) { "A VPN tunnel is already open" }
        check(VpnService.prepare(service) == null) { "VPN permission missing or revoked" }
        val builder = service.Builder().setSession("Umbrella VPN").setMtu(options.mtu)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) builder.setMetered(false)

        val ipv4 = options.inet4Address
        while (ipv4.hasNext()) {
            val address = ipv4.next()
            builder.addAddress(address.address(), address.prefix())
        }
        val ipv6 = options.inet6Address
        while (ipv6.hasNext()) {
            val address = ipv6.next()
            builder.addAddress(address.address(), address.prefix())
        }

        if (options.autoRoute) {
            if (options.dnsMode.value != Libbox.DNSModeDisabled) {
                val dns = options.dnsServerAddress
                while (dns.hasNext()) builder.addDnsServer(dns.next())
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                val routes4 = options.inet4RouteAddress
                if (!routes4.hasNext()) builder.addRoute("0.0.0.0", 0)
                while (routes4.hasNext()) {
                    val route = routes4.next()
                    builder.addRoute(IpPrefix(InetAddresses.parseNumericAddress(route.address()), route.prefix()))
                }
                val routes6 = options.inet6RouteAddress
                if (!routes6.hasNext()) builder.addRoute("::", 0)
                while (routes6.hasNext()) {
                    val route = routes6.next()
                    builder.addRoute(IpPrefix(InetAddresses.parseNumericAddress(route.address()), route.prefix()))
                }
                val excluded4 = options.inet4RouteExcludeAddress
                while (excluded4.hasNext()) {
                    val route = excluded4.next()
                    builder.excludeRoute(IpPrefix(InetAddresses.parseNumericAddress(route.address()), route.prefix()))
                }
                val excluded6 = options.inet6RouteExcludeAddress
                while (excluded6.hasNext()) {
                    val route = excluded6.next()
                    builder.excludeRoute(IpPrefix(InetAddresses.parseNumericAddress(route.address()), route.prefix()))
                }
            } else {
                // The core supplies precomputed non-overlapping ranges on older Android.
                val routes4 = options.inet4RouteRange
                while (routes4.hasNext()) {
                    val route = routes4.next()
                    builder.addRoute(route.address(), route.prefix())
                }
                val routes6 = options.inet6RouteRange
                while (routes6.hasNext()) {
                    val route = routes6.next()
                    builder.addRoute(route.address(), route.prefix())
                }
            }
            val included = options.includePackage
            val excluded = options.excludePackage
            check(!(included.hasNext() && excluded.hasNext())) { "Conflicting app routing rules" }
            if (included.hasNext()) {
                while (included.hasNext()) {
                    val name = included.next()
                    require(name != service.packageName) { "Core app cannot route itself into its VPN" }
                    addApp(builder, name, allowed = true)
                }
            } else {
                while (excluded.hasNext()) {
                    val name = excluded.next()
                    if (name != service.packageName) addApp(builder, name, allowed = false)
                }
                // Keep this app in its own VPN so the traffic verifier can reach
                // the VPN network. Core outbound sockets use protectSocket(),
                // and core control remains on loopback with mutual TLS.
            }
        }
        val opened = builder.establish() ?: error("Android did not establish VPN tunnel")
        descriptor = opened
        return opened.fd
    }

    private fun addApp(builder: VpnService.Builder, name: String, allowed: Boolean) {
        try {
            if (allowed) builder.addAllowedApplication(name) else builder.addDisallowedApplication(name)
        } catch (error: PackageManager.NameNotFoundException) {
            // Silently skipping an app could route traffic contrary to user intent.
            throw IllegalArgumentException("VPN routing package unavailable: $name", error)
        }
    }

    @Synchronized
    override fun close() {
        val current = descriptor ?: return
        current.close()
        descriptor = null
    }
}
