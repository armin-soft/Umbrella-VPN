package ir.umbrella.vpn

import android.annotation.SuppressLint
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.BroadcastReceiver
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager.NameNotFoundException
import android.content.pm.ServiceInfo
import android.net.ConnectivityManager
import android.net.DnsResolver
import android.net.IpPrefix
import android.net.Network
import android.net.NetworkCapabilities
import android.net.NetworkRequest
import android.net.ProxyInfo
import android.net.TrafficStats
import android.net.VpnService
import android.os.Build
import android.os.CancellationSignal
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.ParcelFileDescriptor
import android.os.PowerManager
import android.os.Process
import android.provider.Settings
import android.service.quicksettings.Tile
import android.service.quicksettings.TileService
import android.system.ErrnoException
import android.system.OsConstants
import android.util.Base64
import android.util.Log
import androidx.annotation.RequiresApi
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat
import com.hiddify.core.libbox.AutoRedirectHandler
import com.hiddify.core.libbox.AutoRedirectSession
import com.hiddify.core.libbox.BridgeOptions
import com.hiddify.core.libbox.BridgeSession
import com.hiddify.core.libbox.ConnectionOwner
import com.hiddify.core.libbox.ExchangeContext
import com.hiddify.core.libbox.InterfaceUpdateListener
import com.hiddify.core.libbox.Libbox
import com.hiddify.core.libbox.LocalDNSTransport
import com.hiddify.core.libbox.NeighborUpdateListener
import com.hiddify.core.libbox.NetworkInterfaceIterator
import com.hiddify.core.libbox.PlatformInterface
import com.hiddify.core.libbox.PlatformUser
import com.hiddify.core.libbox.RoutePrefix
import com.hiddify.core.libbox.ShellSession
import com.hiddify.core.libbox.StringIterator
import com.hiddify.core.libbox.TunOptions
import com.hiddify.core.libbox.WIFIState
import com.hiddify.core.mobile.CoreStoppedListener
import com.hiddify.core.mobile.Mobile
import com.hiddify.core.mobile.SetupOptions
import io.grpc.CallOptions
import io.grpc.MethodDescriptor
import io.grpc.okhttp.OkHttpChannelBuilder
import io.grpc.stub.ClientCalls
import kotlinx.coroutines.CancellableContinuation
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.asExecutor
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.job
import kotlinx.coroutines.launch
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.withContext
import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream
import java.io.File
import java.io.InputStream
import java.net.Inet6Address
import java.net.InetAddress
import java.net.InetSocketAddress
import java.net.InterfaceAddress
import java.net.NetworkInterface
import java.net.UnknownHostException
import java.security.KeyStore
import java.util.Locale
import java.util.concurrent.CopyOnWriteArraySet
import java.util.concurrent.TimeUnit
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException
import com.hiddify.core.libbox.NetworkInterface as BoxNetInterface
import com.hiddify.core.libbox.Notification as BoxNotification

/**
 * Minimal Flutter-to-Android VpnService host required by Android OS to create
 * a TUN interface, protect core sockets, and keep the Flutter tunnel alive in background.
 */
object VpnBridge {
    const val CHANNEL_VPN_STATUS = "umbrella_vpn_status"
    const val CHANNEL_ALERTS = "umbrella_alerts"
    const val ACTION_STOP = "ir.umbrella.vpn.ACTION_STOP"
    const val ACTION_RELOAD = "ir.umbrella.vpn.ACTION_RELOAD"
    const val NOTIF_ID_VPN = 1001

    private const val PREFS = "umbrella_core_prefs"
    private const val GRPC_MODE_INSECURE = 4L

    @Volatile
    var appContext: Context? = null

    @Volatile
    var state: String = "stopped"
        private set

    @Volatile
    var lastError: String = ""
        private set

    @Volatile
    var startedAtMs: Long = 0L
        private set

    @Volatile
    var baseRxBytes: Long = 0L
        private set

    @Volatile
    var baseTxBytes: Long = 0L
        private set

    private val mainHandler = Handler(Looper.getMainLooper())
    private val listeners = CopyOnWriteArraySet<(String) -> Unit>()

    fun ensureContext(ctx: Context): Context {
        val app = ctx.applicationContext
        if (appContext == null) {
            appContext = app
            ensureChannels(app)
        }
        return app
    }

    fun ensureChannels(ctx: Context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val nm = ctx.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        nm.createNotificationChannels(
            listOf(
                NotificationChannel(
                    CHANNEL_VPN_STATUS,
                    ctx.getString(R.string.channel_vpn_name),
                    NotificationManager.IMPORTANCE_LOW,
                ).apply {
                    description = ctx.getString(R.string.channel_vpn_desc)
                    setShowBadge(false)
                    enableVibration(false)
                    setSound(null, null)
                },
                NotificationChannel(
                    CHANNEL_ALERTS,
                    ctx.getString(R.string.channel_alerts_name),
                    NotificationManager.IMPORTANCE_DEFAULT,
                ).apply {
                    description = ctx.getString(R.string.channel_alerts_desc)
                },
            ),
        )
    }

    fun prefs(ctx: Context) = ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    fun addListener(cb: (String) -> Unit) = listeners.add(cb)
    fun removeListener(cb: (String) -> Unit) = listeners.remove(cb)

    fun updateState(ctx: Context, next: String, error: String = "") {
        state = next
        if (next == "failed") {
            lastError = error
        } else if (next == "starting" || next == "started") {
            lastError = ""
        }
        if (next == "started") {
            if (startedAtMs == 0L) startedAtMs = System.currentTimeMillis()
            val uid = Process.myUid()
            baseRxBytes = TrafficStats.getUidRxBytes(uid).coerceAtLeast(0L)
            baseTxBytes = TrafficStats.getUidTxBytes(uid).coerceAtLeast(0L)
        } else if (next == "stopped" || next == "failed") {
            startedAtMs = 0L
        }
        val event = "state:$next"
        mainHandler.post {
            for (cb in listeners) runCatching { cb(event) }
        }
        runCatching {
            TileService.requestListeningState(
                ctx.applicationContext,
                ComponentName(ctx.applicationContext, UmbrellaTileService::class.java),
            )
        }
    }

    fun sessionTraffic(): Pair<Long, Long> {
        if (state != "started" && state != "starting") return 0L to 0L
        val uid = Process.myUid()
        val rx = (TrafficStats.getUidRxBytes(uid).coerceAtLeast(0L) - baseRxBytes).coerceAtLeast(0L)
        val tx = (TrafficStats.getUidTxBytes(uid).coerceAtLeast(0L) - baseTxBytes).coerceAtLeast(0L)
        return rx to tx
    }

    fun startService(ctx: Context) {
        val app = ensureContext(ctx)
        val p = prefs(app)
        val mode = p.getString("service_mode", "vpn") ?: "vpn"
        val target = if (mode == "proxy") UmbrellaProxyService::class.java else UmbrellaVpnService::class.java
        val intent = Intent(app, target)
        ContextCompat.startForegroundService(app, intent)
    }

    fun stopService(ctx: Context) {
        val app = ensureContext(ctx)
        app.sendBroadcast(Intent(ACTION_STOP).setPackage(app.packageName))
    }

    fun reloadService(ctx: Context) {
        val app = ensureContext(ctx)
        if (state == "started" || state == "starting") {
            app.sendBroadcast(Intent(ACTION_RELOAD).setPackage(app.packageName))
        } else {
            startService(app)
        }
    }

    fun applyCoreSettingsOverLoopback(port: Int, settingsJson: String) {
        if (settingsJson.isBlank()) return
        val payload = encodeProtoStringField1(settingsJson)
        val channel = OkHttpChannelBuilder.forAddress("127.0.0.1", port)
            .usePlaintext()
            .build()
        try {
            val marshaller = object : MethodDescriptor.Marshaller<ByteArray> {
                override fun stream(value: ByteArray): InputStream = ByteArrayInputStream(value)
                override fun parse(stream: InputStream): ByteArray = stream.readBytes()
            }
            val method = MethodDescriptor.newBuilder<ByteArray, ByteArray>()
                .setType(MethodDescriptor.MethodType.UNARY)
                .setFullMethodName("hcore.Core/ChangeHiddifySettings")
                .setRequestMarshaller(marshaller)
                .setResponseMarshaller(marshaller)
                .build()
            ClientCalls.blockingUnaryCall(
                channel,
                method,
                CallOptions.DEFAULT.withDeadlineAfter(8, TimeUnit.SECONDS),
                payload,
            )
        } finally {
            channel.shutdownNow()
        }
    }

    private fun encodeProtoStringField1(text: String): ByteArray {
        val utf8 = text.toByteArray(Charsets.UTF_8)
        val out = ByteArrayOutputStream(utf8.size + 10)
        out.write(0x0A) // field 1, wire type 2 (length-delimited)
        var len = utf8.size
        while ((len and 0x7F.inv()) != 0) {
            out.write((len and 0x7F) or 0x80)
            len = len ushr 7
        }
        out.write(len)
        out.write(utf8)
        return out.toByteArray()
    }

    fun setupAndStartCore(ctx: Context, platform: PlatformInterface) {
        val app = ensureContext(ctx)
        val p = prefs(app)
        val linksPath = p.getString("links_path", "") ?: ""
        val settingsJson = p.getString("settings_json", "") ?: ""
        val debug = p.getBoolean("debug_mode", false)
        val grpcPort = p.getInt("grpc_port", 17079)

        if (linksPath.isNotBlank() && !File(linksPath).exists()) {
            error("فایل پیکربندی اشتراک یافت نشد.")
        }

        val baseDir = File(app.filesDir, "umbrella_core_base").apply { mkdirs() }
        val workDir = File(app.filesDir, "umbrella_core_work").apply {
            mkdirs()
            File(this, "data").mkdirs()
        }
        val tempDir = File(app.cacheDir, "umbrella_core_tmp").apply { mkdirs() }

        val options = SetupOptions().apply {
            basePath = baseDir.absolutePath
            workingDir = workDir.absolutePath
            tempDir = tempDir.absolutePath
            listen = "127.0.0.1:$grpcPort"
            secret = ""
            this.debug = debug
            mode = GRPC_MODE_INSECURE
            fixAndroidStack = Build.VERSION.SDK_INT >= Build.VERSION_CODES.N
            memoryLimit = 0L
            lowMemory = false
        }
        Mobile.setup(options, platform)
        if (settingsJson.isNotBlank()) {
            applyCoreSettingsOverLoopback(grpcPort, settingsJson)
        }
        Mobile.start(linksPath, "")
    }

    fun closeGrpc() {
        runCatching { Mobile.close(GRPC_MODE_INSECURE) }
    }

    fun faDigits(text: String): String {
        val map = charArrayOf('۰', '۱', '۲', '۳', '۴', '۵', '۶', '۷', '۸', '۹')
        val out = StringBuilder(text.length)
        for (c in text) {
            when (c) {
                in '0'..'9' -> out.append(map[c - '0'])
                in '٠'..'٩' -> out.append(map[c - '٠'])
                else -> out.append(c)
            }
        }
        return out.toString()
    }

    fun formatSpeed(bytesPerSec: Long): String {
        val v = bytesPerSec.coerceAtLeast(0L)
        return when {
            v < 1024L -> faDigits("$v بایت/ث")
            v < 1024L * 1024L -> faDigits(String.format(Locale.US, "%.0f کیلوبایت/ث", v / 1024.0))
            else -> faDigits(
                String.format(Locale.US, "%.1f مگابایت/ث", v / (1024.0 * 1024.0)).replace('.', '٫'),
            )
        }
    }
}

object PhysicalNetworkTracker {
    private val handler = Handler(Looper.getMainLooper())

    @Volatile
    var current: Network? = null
        private set

    @Volatile
    private var listener: InterfaceUpdateListener? = null

    @Volatile
    private var registered = false

    private val request: NetworkRequest by lazy {
        NetworkRequest.Builder()
            .addCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)
            .addCapability(NetworkCapabilities.NET_CAPABILITY_NOT_RESTRICTED)
            .addCapability(NetworkCapabilities.NET_CAPABILITY_NOT_VPN)
            .build()
    }

    private val callback = object : ConnectivityManager.NetworkCallback() {
        override fun onAvailable(network: Network) {
            current = network
            dispatch(network)
        }

        override fun onCapabilitiesChanged(network: Network, caps: NetworkCapabilities) {
            if (caps.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET) &&
                caps.hasCapability(NetworkCapabilities.NET_CAPABILITY_NOT_VPN)
            ) {
                current = network
                dispatch(network)
            }
        }

        override fun onLost(network: Network) {
            if (current == network) {
                val next = VpnBridge.appContext?.let { probe(it) }
                current = next
                dispatch(next)
            }
        }
    }

    @Synchronized
    fun start(ctx: Context) {
        val app = VpnBridge.ensureContext(ctx)
        current = probe(app)
        if (registered) return
        val cm = app.getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
        runCatching {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                cm.registerBestMatchingNetworkCallback(request, callback, handler)
            } else {
                cm.registerNetworkCallback(request, callback, handler)
            }
            registered = true
        }
    }

    @Synchronized
    fun stop(ctx: Context) {
        if (!registered) return
        val cm = ctx.getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
        runCatching { cm.unregisterNetworkCallback(callback) }
        registered = false
    }

    fun setUpdateListener(l: InterfaceUpdateListener?) {
        listener = l
        if (l != null) {
            val net = current ?: VpnBridge.appContext?.let { probe(it) }.also { current = it }
            dispatch(net)
        }
    }

    fun activeOrProbe(ctx: Context? = VpnBridge.appContext): Network? {
        current?.let { return it }
        val c = ctx ?: return null
        return probe(c).also { current = it }
    }

    fun probe(ctx: Context): Network? {
        val cm = ctx.getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
        runCatching {
            cm.activeNetwork?.let { net ->
                val caps = cm.getNetworkCapabilities(net)
                if (caps != null &&
                    caps.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET) &&
                    caps.hasCapability(NetworkCapabilities.NET_CAPABILITY_NOT_VPN)
                ) return net
            }
            for (net in cm.allNetworks) {
                val caps = cm.getNetworkCapabilities(net) ?: continue
                if (caps.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET) &&
                    caps.hasCapability(NetworkCapabilities.NET_CAPABILITY_NOT_VPN)
                ) return net
            }
        }
        return null
    }

    private fun dispatch(network: Network?) {
        val target = listener ?: return
        val app = VpnBridge.appContext ?: return
        if (network == null) {
            runCatching { target.updateDefaultInterface("", -1, false, false) }
            return
        }
        val cm = app.getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
        val link = runCatching { cm.getLinkProperties(network) }.getOrNull() ?: return
        val caps = runCatching { cm.getNetworkCapabilities(network) }.getOrNull()
        val ifName = link.interfaceName ?: return
        val metered = caps != null && !caps.hasCapability(NetworkCapabilities.NET_CAPABILITY_NOT_METERED)
        val idx = runCatching { NetworkInterface.getByName(ifName)?.index ?: -1 }.getOrDefault(-1)
        if (idx >= 0) {
            runCatching { target.updateDefaultInterface(ifName, idx, metered, false) }
        }
    }
}

private object AndroidDnsTransport : LocalDNSTransport {
    override fun raw(): Boolean = Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q

    @RequiresApi(Build.VERSION_CODES.Q)
    override fun exchange(ctx: ExchangeContext, message: ByteArray) = runCancelable(ctx) {
        val net = PhysicalNetworkTracker.activeOrProbe() ?: run {
            ctx.errorCode(2)
            return@runCancelable
        }
        awaitQuery { signal, cont ->
            DnsResolver.getInstance().rawQuery(
                net,
                message,
                DnsResolver.FLAG_NO_RETRY,
                Dispatchers.IO.asExecutor(),
                signal,
                resolverCb(ctx, cont) { ctx.rawSuccess(it) },
            )
        }
    }

    override fun lookup(ctx: ExchangeContext, network: String, domain: String) = runCancelable(ctx) {
        val net = PhysicalNetworkTracker.activeOrProbe() ?: run {
            ctx.errorCode(2)
            return@runCancelable
        }
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
            try {
                val all = net.getAllByName(domain)
                ctx.success(all.mapNotNull { it.hostAddress }.joinToString("\n"))
            } catch (_: UnknownHostException) {
                ctx.errorCode(3)
            }
            return@runCancelable
        }
        val qType = when {
            network.endsWith("4") -> DnsResolver.TYPE_A
            network.endsWith("6") -> DnsResolver.TYPE_AAAA
            else -> null
        }
        awaitQuery { signal, cont ->
            val cb = resolverCb<Collection<InetAddress>>(ctx, cont) { ans ->
                ctx.success(ans.mapNotNull { it.hostAddress }.joinToString("\n"))
            }
            if (qType != null) {
                DnsResolver.getInstance().query(
                    net, domain, qType, DnsResolver.FLAG_NO_RETRY,
                    Dispatchers.IO.asExecutor(), signal, cb,
                )
            } else {
                DnsResolver.getInstance().query(
                    net, domain, DnsResolver.FLAG_NO_RETRY,
                    Dispatchers.IO.asExecutor(), signal, cb,
                )
            }
        }
    }

    private fun runCancelable(ctx: ExchangeContext, block: suspend CoroutineScope.() -> Unit) =
        runBlocking {
            val j = coroutineContext.job
            ctx.onCancel { j.cancel() }
            block()
        }

    @RequiresApi(Build.VERSION_CODES.Q)
    private suspend fun awaitQuery(fn: (CancellationSignal, CancellableContinuation<Unit>) -> Unit) =
        suspendCancellableCoroutine { cont ->
            val sig = CancellationSignal()
            cont.invokeOnCancellation { sig.cancel() }
            fn(sig, cont)
        }

    @RequiresApi(Build.VERSION_CODES.Q)
    private fun <T : Any> resolverCb(
        ctx: ExchangeContext,
        cont: CancellableContinuation<Unit>,
        ok: (T) -> Unit,
    ) = object : DnsResolver.Callback<T> {
        override fun onAnswer(answer: T, rcode: Int) {
            if (rcode == 0) ok(answer) else ctx.errorCode(rcode)
            if (cont.isActive) cont.resume(Unit)
        }

        override fun onError(error: DnsResolver.DnsException) {
            val cause = error.cause
            if (cause is ErrnoException) {
                ctx.errnoCode(cause.errno)
                if (cont.isActive) cont.resume(Unit)
            } else if (cont.isActive) {
                cont.resumeWithException(error)
            }
        }
    }
}

private interface AndroidCorePlatform : PlatformInterface {
    val hostContext: Context

    override fun localDNSTransport(): LocalDNSTransport = AndroidDnsTransport
    override fun usePlatformAutoDetectInterfaceControl(): Boolean = true
    override fun autoDetectInterfaceControl(fd: Int) {}
    override fun openTun(options: TunOptions): Int = error("TUN not supported in proxy-only mode")

    @RequiresApi(Build.VERSION_CODES.Q)
    override fun findConnectionOwner(
        ipProtocol: Int,
        sourceAddress: String,
        sourcePort: Int,
        destinationAddress: String,
        destinationPort: Int,
    ): ConnectionOwner {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
            error("Connection owner lookup requires Android 10+")
        }
        val cm = hostContext.getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
        val uid = cm.getConnectionOwnerUid(
            ipProtocol,
            InetSocketAddress(sourceAddress, sourcePort),
            InetSocketAddress(destinationAddress, destinationPort),
        )
        return ConnectionOwner().apply {
            userId = uid
            if (uid != Process.INVALID_UID) {
                val pkgs = hostContext.packageManager.getPackagesForUid(uid).orEmpty().toList()
                userName = pkgs.firstOrNull() ?: ""
                setAndroidPackageNames(StrIter(pkgs))
            }
        }
    }

    override fun startDefaultInterfaceMonitor(listener: InterfaceUpdateListener) =
        PhysicalNetworkTracker.setUpdateListener(listener)

    override fun closeDefaultInterfaceMonitor(listener: InterfaceUpdateListener) =
        PhysicalNetworkTracker.setUpdateListener(null)

    override fun getInterfaces(): NetworkInterfaceIterator {
        val cm = hostContext.getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
        val sysIfs = runCatching { NetworkInterface.getNetworkInterfaces()?.toList().orEmpty() }
            .getOrDefault(emptyList())
        val out = mutableListOf<BoxNetInterface>()
        for (net in runCatching { cm.allNetworks }.getOrDefault(emptyArray())) {
            val lp = runCatching { cm.getLinkProperties(net) }.getOrNull() ?: continue
            val caps = runCatching { cm.getNetworkCapabilities(net) }.getOrNull() ?: continue
            val name = lp.interfaceName ?: continue
            val ni = sysIfs.firstOrNull { it.name == name } ?: continue
            val item = BoxNetInterface().apply {
                this.name = name
                index = ni.index
                runCatching { mtu = ni.mtu }
                dnsServer = StrIter(lp.dnsServers.mapNotNull { it.hostAddress }.iterator())
                type = when {
                    caps.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) -> Libbox.InterfaceTypeWIFI
                    caps.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR) -> Libbox.InterfaceTypeCellular
                    caps.hasTransport(NetworkCapabilities.TRANSPORT_ETHERNET) -> Libbox.InterfaceTypeEthernet
                    else -> Libbox.InterfaceTypeOther
                }
                addresses = StrIter(ni.interfaceAddresses.map { it.asCidr() }.iterator())
                var f = 0
                if (caps.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)) {
                    f = OsConstants.IFF_UP or OsConstants.IFF_RUNNING
                }
                if (ni.isLoopback) f = f or OsConstants.IFF_LOOPBACK
                if (ni.isPointToPoint) f = f or OsConstants.IFF_POINTOPOINT
                if (ni.supportsMulticast()) f = f or OsConstants.IFF_MULTICAST
                flags = f
                metered = !caps.hasCapability(NetworkCapabilities.NET_CAPABILITY_NOT_METERED)
            }
            out.add(item)
        }
        return NetIfIter(out.iterator())
    }

    override fun underNetworkExtension(): Boolean = false
    override fun includeAllNetworks(): Boolean = false
    override fun readWIFIState(): WIFIState? = null
    override fun clearDNSCache() {}
    override fun sendNotification(notification: BoxNotification?) {}
    override fun cancelNotification(identifier: String?, typeID: Int) {}
    override fun startNeighborMonitor(listener: NeighborUpdateListener?) {}
    override fun closeNeighborMonitor(listener: NeighborUpdateListener?) {}
    override fun registerMyInterface(name: String?) {}
    override fun usePlatformShell(): Boolean = false
    override fun checkPlatformShell() = error("unsupported")
    override fun openShellSession(
        user: PlatformUser?,
        command: String?,
        environ: StringIterator?,
        term: String?,
        rows: Int,
        cols: Int,
    ): ShellSession = error("unsupported")
    override fun lookupUser(username: String?): PlatformUser = error("unsupported")
    override fun lookupSFTPServer(): String = error("unsupported")
    override fun readSystemSSHHostKey(): String = error("unsupported")
    override fun tailscaleHostname(): String =
        runCatching { Settings.Global.getString(hostContext.contentResolver, Settings.Global.DEVICE_NAME) }
            .getOrNull()?.takeIf { it.isNotBlank() } ?: "${Build.MANUFACTURER} ${Build.MODEL}"
    override fun usePlatformBridge(): Boolean = false
    override fun createBridge(options: BridgeOptions?): BridgeSession = error("unsupported")
    override fun usePlatformAutoRedirect(): Boolean = false
    override fun createAutoRedirect(options: ByteArray?, handler: AutoRedirectHandler?): AutoRedirectSession =
        error("unsupported")

    override fun systemCertificates(): StringIterator {
        val list = mutableListOf<String>()
        runCatching {
            val ks = KeyStore.getInstance("AndroidCAStore")
            ks.load(null, null)
            val aliases = ks.aliases()
            while (aliases.hasMoreElements()) {
                val cert = ks.getCertificate(aliases.nextElement()) ?: continue
                val b64 = Base64.encodeToString(cert.encoded, Base64.NO_WRAP)
                list.add("-----BEGIN CERTIFICATE-----\n$b64\n-----END CERTIFICATE-----")
            }
        }
        return StrIter(list.iterator())
    }
}

private class StrIter(private val items: List<String>) : StringIterator {
    private val it = items.iterator()
    constructor(iter: Iterator<String>) : this(iter.asSequence().toList())
    override fun len(): Int = items.size
    override fun hasNext(): Boolean = it.hasNext()
    override fun next(): String = it.next()
}

private class NetIfIter(private val it: Iterator<BoxNetInterface>) : NetworkInterfaceIterator {
    override fun hasNext(): Boolean = it.hasNext()
    override fun next(): BoxNetInterface = it.next()
}

private fun InterfaceAddress.asCidr(): String =
    if (address is Inet6Address) {
        "${Inet6Address.getByAddress(address.address).hostAddress}/$networkPrefixLength"
    } else {
        "${address.hostAddress}/$networkPrefixLength"
    }

@RequiresApi(Build.VERSION_CODES.TIRAMISU)
private fun RoutePrefix.asIpPrefix(): IpPrefix =
    IpPrefix(InetAddress.getByName(address()), prefix())

private class ForegroundCoreRunner(
    private val service: Service,
    private val platform: PlatformInterface,
) {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private var worker: Job? = null
    private var speedTicker: Job? = null
    private var receiverRegistered = false
    var tunFd: ParcelFileDescriptor? = null

    private val receiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            when (intent.action) {
                VpnBridge.ACTION_STOP -> stop(failedMessage = null)
                VpnBridge.ACTION_RELOAD -> reload()
                PowerManager.ACTION_DEVICE_IDLE_MODE_CHANGED -> {
                    val pm = service.getSystemService(Context.POWER_SERVICE) as PowerManager
                    if (!pm.isDeviceIdleMode) {
                        scope.launch { runCatching { Mobile.wake() } }
                    }
                }
            }
        }
    }

    private val stoppedListener = CoreStoppedListener { _, message ->
        if (VpnBridge.state == "started" || VpnBridge.state == "starting") {
            stop(failedMessage = message?.takeIf { it.isNotBlank() })
        }
    }

    fun onStart(): Int {
        VpnBridge.ensureContext(service)
        postForeground(service.getString(R.string.status_starting))
        registerReceivers()
        worker?.cancel()
        VpnBridge.updateState(service, "starting")
        worker = scope.launch {
            try {
                PhysicalNetworkTracker.start(service)
                VpnBridge.setupAndStartCore(service, platform)
                Mobile.setCoreStoppedListener(stoppedListener)
                VpnBridge.updateState(service, "started")
                withContext(Dispatchers.Main) {
                    updateNotification(service.getString(R.string.status_connected))
                }
                startSpeedTicker()
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                Log.e("UmbrellaVpn", "Core start failed", e)
                stop(failedMessage = e.message ?: "خطا در راه اندازی هسته اتصال")
            }
        }
        return Service.START_STICKY
    }

    private fun reload() {
        worker?.cancel()
        speedTicker?.cancel()
        VpnBridge.updateState(service, "starting")
        updateNotification(service.getString(R.string.status_starting))
        worker = scope.launch {
            try {
                runCatching { tunFd?.close() }
                tunFd = null
                runCatching { Mobile.stop() }
                VpnBridge.setupAndStartCore(service, platform)
                Mobile.setCoreStoppedListener(stoppedListener)
                VpnBridge.updateState(service, "started")
                withContext(Dispatchers.Main) {
                    updateNotification(service.getString(R.string.status_connected))
                }
                startSpeedTicker()
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                Log.e("UmbrellaVpn", "Core reload failed", e)
                stop(failedMessage = e.message ?: "خطا در بازخوانی هسته اتصال")
            }
        }
    }

    private fun startSpeedTicker() {
        speedTicker?.cancel()
        speedTicker = scope.launch {
            val uid = Process.myUid()
            var lastRx = TrafficStats.getUidRxBytes(uid).coerceAtLeast(0L)
            var lastTx = TrafficStats.getUidTxBytes(uid).coerceAtLeast(0L)
            while (isActive && VpnBridge.state == "started") {
                delay(2000L)
                if (VpnBridge.state != "started") break
                val show = VpnBridge.prefs(service).getBoolean("show_speed", true)
                val nowRx = TrafficStats.getUidRxBytes(uid).coerceAtLeast(0L)
                val nowTx = TrafficStats.getUidTxBytes(uid).coerceAtLeast(0L)
                val rxRate = ((nowRx - lastRx).coerceAtLeast(0L)) / 2L
                val txRate = ((nowTx - lastTx).coerceAtLeast(0L)) / 2L
                lastRx = nowRx
                lastTx = nowTx
                val text = if (show) {
                    "متصل  •  ↓ ${VpnBridge.formatSpeed(rxRate)}   ↑ ${VpnBridge.formatSpeed(txRate)}"
                } else {
                    service.getString(R.string.status_connected)
                }
                withContext(Dispatchers.Main) { updateNotification(text) }
            }
        }
    }

    fun stop(failedMessage: String?) {
        speedTicker?.cancel()
        worker?.cancel()
        VpnBridge.updateState(service, "stopping")
        scope.launch {
            runCatching { Mobile.setCoreStoppedListener(null) }
            runCatching { tunFd?.close() }
            tunFd = null
            runCatching { Mobile.stop() }
            VpnBridge.closeGrpc()
            PhysicalNetworkTracker.stop(service)
            if (failedMessage != null) {
                VpnBridge.updateState(service, "failed", failedMessage)
            } else {
                VpnBridge.updateState(service, "stopped")
            }
            withContext(Dispatchers.Main) {
                unregisterReceivers()
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                    service.stopForeground(Service.STOP_FOREGROUND_REMOVE)
                } else {
                    @Suppress("DEPRECATION")
                    service.stopForeground(true)
                }
                service.stopSelf()
            }
        }
    }

    fun onDestroy() {
        unregisterReceivers()
        speedTicker?.cancel()
        worker?.cancel()
        runCatching { tunFd?.close() }
        tunFd = null
        if (VpnBridge.state != "stopped" && VpnBridge.state != "failed") {
            VpnBridge.updateState(service, "stopped")
        }
    }

    private fun registerReceivers() {
        if (receiverRegistered) return
        val filter = IntentFilter().apply {
            addAction(VpnBridge.ACTION_STOP)
            addAction(VpnBridge.ACTION_RELOAD)
            addAction(PowerManager.ACTION_DEVICE_IDLE_MODE_CHANGED)
        }
        ContextCompat.registerReceiver(service, receiver, filter, ContextCompat.RECEIVER_NOT_EXPORTED)
        receiverRegistered = true
    }

    private fun unregisterReceivers() {
        if (!receiverRegistered) return
        runCatching { service.unregisterReceiver(receiver) }
        receiverRegistered = false
    }

    private fun buildNotification(content: String): Notification {
        val openIntent = PendingIntent.getActivity(
            service,
            0,
            Intent(service, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
            },
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val stopIntent = PendingIntent.getBroadcast(
            service,
            1,
            Intent(VpnBridge.ACTION_STOP).setPackage(service.packageName),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        return NotificationCompat.Builder(service, VpnBridge.CHANNEL_VPN_STATUS)
            .setSmallIcon(R.drawable.ic_stat_umbrella)
            .setContentTitle(service.getString(R.string.app_name))
            .setContentText(content)
            .setContentIntent(openIntent)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setSilent(true)
            .setCategory(NotificationCompat.CATEGORY_SERVICE)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .addAction(0, service.getString(R.string.action_disconnect), stopIntent)
            .build()
    }

    private fun postForeground(content: String) {
        val notif = buildNotification(content)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            service.startForeground(
                VpnBridge.NOTIF_ID_VPN,
                notif,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE,
            )
        } else {
            service.startForeground(VpnBridge.NOTIF_ID_VPN, notif)
        }
    }

    private fun updateNotification(content: String) {
        val nm = service.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        runCatching { nm.notify(VpnBridge.NOTIF_ID_VPN, buildNotification(content)) }
    }
}

class UmbrellaVpnService : VpnService(), AndroidCorePlatform {
    override val hostContext: Context get() = this
    private val runner = ForegroundCoreRunner(this, this)

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int = runner.onStart()

    override fun onRevoke() {
        runner.stop(failedMessage = null)
        super.onRevoke()
    }

    override fun onDestroy() {
        runner.onDestroy()
        super.onDestroy()
    }

    override fun autoDetectInterfaceControl(fd: Int) {
        protect(fd)
    }

    @SuppressLint("NewApi")
    override fun openTun(options: TunOptions): Int {
        if (prepare(this) != null) {
            error("مجوز ساخت تونل VPN در اندروید تایید نشده است.")
        }
        val prefs = VpnBridge.prefs(this)
        val builder = Builder()
            .setSession(getString(R.string.app_name))
            .setMtu(options.mtu.coerceIn(1280, 9000))

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            builder.setMetered(false)
        }

        val v4 = options.inet4Address
        while (v4.hasNext()) {
            val a = v4.next()
            builder.addAddress(a.address(), a.prefix())
        }
        val v6 = options.inet6Address
        while (v6.hasNext()) {
            val a = v6.next()
            builder.addAddress(a.address(), a.prefix())
        }

        if (options.autoRoute) {
            if (options.dnsMode?.value != Libbox.DNSModeDisabled) {
                val dns = options.dnsServerAddress
                while (dns.hasNext()) {
                    runCatching { builder.addDnsServer(dns.next()) }
                }
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                val r4 = options.inet4RouteAddress
                if (r4.hasNext()) {
                    while (r4.hasNext()) builder.addRoute(r4.next().asIpPrefix())
                } else {
                    builder.addRoute("0.0.0.0", 0)
                }
                val r6 = options.inet6RouteAddress
                if (r6.hasNext()) {
                    while (r6.hasNext()) builder.addRoute(r6.next().asIpPrefix())
                } else {
                    builder.addRoute("::", 0)
                }
                val ex4 = options.inet4RouteExcludeAddress
                while (ex4.hasNext()) builder.excludeRoute(ex4.next().asIpPrefix())
                val ex6 = options.inet6RouteExcludeAddress
                while (ex6.hasNext()) builder.excludeRoute(ex6.next().asIpPrefix())
            } else {
                val r4 = options.inet4RouteRange
                while (r4.hasNext()) {
                    val r = r4.next()
                    builder.addRoute(r.address(), r.prefix())
                }
                val r6 = options.inet6RouteRange
                while (r6.hasNext()) {
                    val r = r6.next()
                    builder.addRoute(r.address(), r.prefix())
                }
            }

            val perAppMode = prefs.getString("per_app_mode", "off") ?: "off"
            val perAppPkgs = prefs.getStringSet("per_app_list", emptySet()).orEmpty()
            when {
                perAppMode == "include" && perAppPkgs.isNotEmpty() -> {
                    for (pkg in perAppPkgs) {
                        if (pkg != packageName) {
                            try { builder.addAllowedApplication(pkg) } catch (_: NameNotFoundException) {}
                        }
                    }
                }
                perAppMode == "exclude" && perAppPkgs.isNotEmpty() -> {
                    for (pkg in perAppPkgs) {
                        try { builder.addDisallowedApplication(pkg) } catch (_: NameNotFoundException) {}
                    }
                    runCatching { builder.addDisallowedApplication(packageName) }
                }
                else -> {
                    val inc = options.includePackage
                    if (inc.hasNext()) {
                        while (inc.hasNext()) {
                            val pkg = inc.next()
                            if (pkg != packageName) {
                                try { builder.addAllowedApplication(pkg) } catch (_: NameNotFoundException) {}
                            }
                        }
                    } else {
                        val exc = options.excludePackage
                        while (exc.hasNext()) {
                            try { builder.addDisallowedApplication(exc.next()) } catch (_: NameNotFoundException) {}
                        }
                        runCatching { builder.addDisallowedApplication(packageName) }
                    }
                }
            }
        }

        val serviceMode = prefs.getString("service_mode", "vpn") ?: "vpn"
        if (serviceMode == "systemProxy" &&
            options.isHTTPProxyEnabled &&
            Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q
        ) {
            runCatching {
                builder.setHttpProxy(
                    ProxyInfo.buildDirectProxy(options.httpProxyServer, options.httpProxyServerPort),
                )
            }
        }

        runCatching { runner.tunFd?.close() }
        val pfd = builder.establish() ?: error("ساخت رابط تونل VPN در اندروید ناموفق بود.")
        runner.tunFd = pfd
        return pfd.fd
    }
}

class UmbrellaProxyService : Service(), AndroidCorePlatform {
    override val hostContext: Context get() = this
    private val runner = ForegroundCoreRunner(this, this)

    override fun onBind(intent: Intent?): IBinder? = null
    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int = runner.onStart()
    override fun onDestroy() {
        runner.onDestroy()
        super.onDestroy()
    }
}

class UmbrellaTileService : TileService() {
    override fun onStartListening() {
        super.onStartListening()
        syncTile()
    }

    override fun onClick() {
        super.onClick()
        VpnBridge.ensureContext(this)
        when (VpnBridge.state) {
            "started", "starting" -> VpnBridge.stopService(this)
            else -> {
                val p = VpnBridge.prefs(this)
                val links = p.getString("links_path", "") ?: ""
                val mode = p.getString("service_mode", "vpn") ?: "vpn"
                val needsPerm = mode != "proxy" && VpnService.prepare(this) != null
                if (links.isBlank() || needsPerm) {
                    val intent = Intent(this, MainActivity::class.java).apply {
                        addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    }
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
                        startActivityAndCollapse(
                            PendingIntent.getActivity(
                                this, 2, intent,
                                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
                            ),
                        )
                    } else {
                        @Suppress("DEPRECATION")
                        startActivityAndCollapse(intent)
                    }
                } else {
                    VpnBridge.startService(this)
                }
            }
        }
        syncTile()
    }

    private fun syncTile() {
        val tile = qsTile ?: return
        tile.label = getString(R.string.tile_label)
        when (VpnBridge.state) {
            "started" -> {
                tile.state = Tile.STATE_ACTIVE
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) tile.subtitle = "متصل"
            }
            "starting", "stopping" -> {
                tile.state = Tile.STATE_ACTIVE
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) tile.subtitle = "در حال اتصال"
            }
            else -> {
                tile.state = Tile.STATE_INACTIVE
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) tile.subtitle = "قطع"
            }
        }
        tile.updateTile()
    }
}

class UmbrellaBootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent?) {
        val action = intent?.action ?: return
        if (action != Intent.ACTION_BOOT_COMPLETED &&
            action != Intent.ACTION_MY_PACKAGE_REPLACED &&
            action != "android.intent.action.QUICKBOOT_POWERON"
        ) return
        val app = VpnBridge.ensureContext(context)
        val p = VpnBridge.prefs(app)
        if (!p.getBoolean("autostart_boot", false) || !p.getBoolean("autoconnect_boot", false)) return
        val links = p.getString("links_path", "") ?: ""
        if (links.isBlank() || !File(links).exists()) return
        val mode = p.getString("service_mode", "vpn") ?: "vpn"
        if (mode != "proxy" && VpnService.prepare(app) != null) return
        runCatching { VpnBridge.startService(app) }
    }
}
