package ir.umbrella.vpn.bg

import android.content.Intent
import android.content.pm.PackageManager.NameNotFoundException
import android.net.ProxyInfo
import android.net.VpnService
import android.os.Build
import android.os.IBinder
import android.util.Log
import com.hiddify.core.libbox.Notification
import com.hiddify.core.libbox.TunOptions
import ir.umbrella.vpn.Settings
import ir.umbrella.vpn.UmbrellaApplication
import ir.umbrella.vpn.constant.PerAppProxyMode
import ir.umbrella.vpn.ktx.toIpPrefix
import ir.umbrella.vpn.ktx.toList
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withContext

class VPNService : VpnService(), PlatformInterfaceWrapper {
    companion object {
        private const val TAG = "UmbrellaVPNService"
    }

    private val service = BoxService(this, this)
    var systemProxyAvailable = false
    var systemProxyEnabled = false

    override fun onCreate() {
        UmbrellaApplication.initialize(this)
        super.onCreate()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int =
        service.onStartCommand(intent)

    override fun onBind(intent: Intent): IBinder {
        val binder = super.onBind(intent)
        if (binder != null && intent.action == SERVICE_INTERFACE) {
            return binder
        }
        return service.onBind(intent)
    }

    override fun onDestroy() {
        service.onDestroy()
        super.onDestroy()
    }

    override fun onRevoke() {
        runBlocking {
            withContext(Dispatchers.Main) {
                service.onRevoke()
            }
        }
    }

    override fun autoDetectInterfaceControl(fd: Int) {
        protect(fd)
    }

    override fun openTun(options: TunOptions): Int {
        var hasPermission = false
        for (i in 0 until 20) {
            if (prepare(this) == null) {
                hasPermission = true
                break
            }
            Thread.sleep(100)
        }
        if (!hasPermission) error("missing vpn permission")

        val builder = Builder()
            .setSession("Umbrella VPN")
            .setMtu(options.mtu)

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            builder.setMetered(false)
        }

        var hasInet4 = false
        val inet4Address = options.inet4Address
        while (inet4Address.hasNext()) {
            hasInet4 = true
            val address = inet4Address.next()
            builder.addAddress(address.address(), address.prefix())
        }

        var hasInet6 = false
        val inet6Address = options.inet6Address
        while (inet6Address.hasNext()) {
            hasInet6 = true
            val address = inet6Address.next()
            builder.addAddress(address.address(), address.prefix())
        }

        if (options.autoRoute) {
            val dnsServerAddress = options.dnsServerAddress
            while (dnsServerAddress.hasNext()) {
                builder.addDnsServer(dnsServerAddress.next())
            }

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                val inet4RouteAddress = options.inet4RouteAddress
                if (inet4RouteAddress.hasNext()) {
                    while (inet4RouteAddress.hasNext()) {
                        builder.addRoute(inet4RouteAddress.next().toIpPrefix())
                    }
                } else if (hasInet4) {
                    builder.addRoute("0.0.0.0", 0)
                }

                val inet6RouteAddress = options.inet6RouteAddress
                if (inet6RouteAddress.hasNext()) {
                    while (inet6RouteAddress.hasNext()) {
                        builder.addRoute(inet6RouteAddress.next().toIpPrefix())
                    }
                } else if (hasInet6) {
                    builder.addRoute("::", 0)
                }

                val inet4RouteExcludeAddress = options.inet4RouteExcludeAddress
                while (inet4RouteExcludeAddress.hasNext()) {
                    builder.excludeRoute(inet4RouteExcludeAddress.next().toIpPrefix())
                }

                val inet6RouteExcludeAddress = options.inet6RouteExcludeAddress
                while (inet6RouteExcludeAddress.hasNext()) {
                    builder.excludeRoute(inet6RouteExcludeAddress.next().toIpPrefix())
                }
            } else {
                val inet4RouteAddress = options.inet4RouteRange
                if (inet4RouteAddress.hasNext()) {
                    while (inet4RouteAddress.hasNext()) {
                        val address = inet4RouteAddress.next()
                        builder.addRoute(address.address(), address.prefix())
                    }
                }

                val inet6RouteAddress = options.inet6RouteRange
                if (inet6RouteAddress.hasNext()) {
                    while (inet6RouteAddress.hasNext()) {
                        val address = inet6RouteAddress.next()
                        builder.addRoute(address.address(), address.prefix())
                    }
                }
            }

            if (Settings.perAppProxyEnabled) {
                val appList = Settings.perAppProxyList
                if (Settings.perAppProxyMode == PerAppProxyMode.INCLUDE) {
                    appList.forEach {
                        if (it != packageName) {
                            runCatching { builder.addAllowedApplication(it) }
                                .onFailure { err -> Log.w(TAG, "addAllowedApplication $it", err) }
                        }
                    }
                } else {
                    appList.forEach {
                        runCatching { builder.addDisallowedApplication(it) }
                            .onFailure { err -> Log.w(TAG, "addDisallowedApplication $it", err) }
                    }
                    excludeSelfPackage(builder)
                }
            } else {
                val includePackage = options.includePackage
                if (includePackage.hasNext()) {
                    while (includePackage.hasNext()) {
                        val pkg = includePackage.next()
                        if (pkg != packageName) {
                            runCatching { builder.addAllowedApplication(pkg) }
                        }
                    }
                } else {
                    val excludePackage = options.excludePackage
                    while (excludePackage.hasNext()) {
                        runCatching { builder.addDisallowedApplication(excludePackage.next()) }
                    }
                    excludeSelfPackage(builder)
                }
            }
        }

        if (options.isHTTPProxyEnabled && Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            systemProxyAvailable = true
            systemProxyEnabled = Settings.systemProxyEnabled
            if (systemProxyEnabled) {
                builder.setHttpProxy(
                    ProxyInfo.buildDirectProxy(
                        options.httpProxyServer,
                        options.httpProxyServerPort,
                        options.httpProxyBypassDomain.toList(),
                    ),
                )
            }
        } else {
            systemProxyAvailable = false
            systemProxyEnabled = false
        }

        service.fileDescriptor?.let {
            runCatching { it.close() }
            service.fileDescriptor = null
        }
        val pfd = builder.establish() ?: error("application has no permission to establish VPN")
        service.fileDescriptor = pfd
        return pfd.fd
    }

    private fun excludeSelfPackage(builder: Builder) {
        try {
            builder.addDisallowedApplication(packageName)
        } catch (_: NameNotFoundException) {
        }
    }

    override fun sendNotification(notification: Notification) =
        service.sendNotification(notification)

    override fun cancelNotification(identifier: String, typeID: Int) =
        service.cancelNotification(identifier, typeID)
}
