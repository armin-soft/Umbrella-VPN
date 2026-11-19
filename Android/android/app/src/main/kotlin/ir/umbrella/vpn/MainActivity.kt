package ir.umbrella.vpn

import android.Manifest
import android.annotation.SuppressLint
import android.app.Activity
import android.app.ActivityManager
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.ApplicationInfo
import android.content.pm.PackageManager
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.net.Uri
import android.net.VpnService
import android.os.BatteryManager
import android.os.Build
import android.os.Bundle
import android.os.Environment
import android.os.PowerManager
import android.os.StatFs
import android.os.SystemClock
import android.provider.Settings
import android.telephony.TelephonyManager
import androidx.core.app.ActivityCompat
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat
import androidx.core.content.FileProvider
import androidx.core.view.WindowCompat
import androidx.core.view.WindowInsetsControllerCompat
import com.hiddify.core.mobile.Mobile
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.File
import java.net.HttpURLConnection
import java.net.Inet4Address
import java.net.InetSocketAddress
import java.net.NetworkInterface
import java.net.Proxy
import java.net.URL
import java.security.MessageDigest

/**
 * Standard Flutter Android MainActivity + `ir.umbrella.app/native` MethodChannel
 * (Android counterpart of `packages/umbrella_native` in the Windows Flutter app).
 */
class MainActivity : FlutterActivity() {
    companion object {
        private const val REQ_VPN_PERMISSION = 4101
        private const val REQ_NOTIF_PERMISSION = 4102
    }

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)
    private var pendingVpnResult: ((Boolean) -> Unit)? = null
    private var eventSink: EventChannel.EventSink? = null
    private var alertSeq = 2000

    private val stateListener: (String) -> Unit = { event ->
        eventSink?.success(event)
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        VpnBridge.ensureContext(this)
        PhysicalNetworkTracker.start(this)
        WindowCompat.setDecorFitsSystemWindows(window, false)
    }

    override fun onDestroy() {
        VpnBridge.removeListener(stateListener)
        scope.cancel()
        super.onDestroy()
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        VpnBridge.ensureContext(this)

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, "ir.umbrella.app/tray")
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    eventSink = events
                    VpnBridge.addListener(stateListener)
                }

                override fun onCancel(arguments: Any?) {
                    VpnBridge.removeListener(stateListener)
                    eventSink = null
                }
            })

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "ir.umbrella.app/native")
            .setMethodCallHandler { call, result -> handleCall(call, result) }
    }

    private fun handleCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "isElevated", "hasVpnPermission" -> {
                result.success(VpnService.prepare(this) == null)
            }
            "relaunchElevated", "requestVpnPermission" -> {
                requestVpnConsent { granted -> result.success(granted) }
            }
            "requestNotificationPermission" -> {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
                    ContextCompat.checkSelfPermission(this, Manifest.permission.POST_NOTIFICATIONS) !=
                    PackageManager.PERMISSION_GRANTED
                ) {
                    ActivityCompat.requestPermissions(
                        this,
                        arrayOf(Manifest.permission.POST_NOTIFICATIONS),
                        REQ_NOTIF_PERMISSION,
                    )
                }
                result.success(true)
            }
            "coreInstalled" -> {
                val ok = runCatching { Mobile.test().isNotEmpty() }.getOrDefault(false)
                result.success(ok)
            }
            "startCore" -> {
                val linksPath = call.argument<String>("linksPath") ?: ""
                val settingsJson = call.argument<String>("settingsJson") ?: ""
                val serviceMode = call.argument<String>("serviceMode") ?: "vpn"
                val perAppMode = call.argument<String>("perAppMode") ?: "off"
                val perAppList = call.argument<List<String>>("perAppPackages")?.toSet().orEmpty()
                val showSpeed = call.argument<Boolean>("showSpeed") ?: true
                val debugMode = call.argument<Boolean>("debugMode") ?: false
                val autoConnect = call.argument<Boolean>("autoConnect") ?: false
                val proxyPort = call.argument<Int>("proxyPort") ?: 12334
                val clashPort = call.argument<Int>("clashPort") ?: 16756

                val prefs = VpnBridge.prefs(this)
                val previousMode = prefs.getString("service_mode", "vpn") ?: "vpn"
                prefs.edit()
                    .putString("links_path", linksPath)
                    .putString("settings_json", settingsJson)
                    .putString("service_mode", serviceMode)
                    .putString("per_app_mode", perAppMode)
                    .putStringSet("per_app_list", perAppList)
                    .putBoolean("show_speed", showSpeed)
                    .putBoolean("debug_mode", debugMode)
                    .putBoolean("autoconnect_boot", autoConnect)
                    .putInt("proxy_port", proxyPort)
                    .putInt("clash_port", clashPort)
                    .apply()

                val launch: () -> Unit = {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
                        ContextCompat.checkSelfPermission(
                            this,
                            Manifest.permission.POST_NOTIFICATIONS,
                        ) != PackageManager.PERMISSION_GRANTED
                    ) {
                        ActivityCompat.requestPermissions(
                            this,
                            arrayOf(Manifest.permission.POST_NOTIFICATIONS),
                            REQ_NOTIF_PERMISSION,
                        )
                    }
                    scope.launch {
                        try {
                            val wasProxy = previousMode == "proxy"
                            val nowProxy = serviceMode == "proxy"
                            if (VpnBridge.state == "started" || VpnBridge.state == "starting") {
                                if (wasProxy != nowProxy) {
                                    VpnBridge.stopService(this@MainActivity)
                                    var w = 0L
                                    while (w < 3000L && VpnBridge.state != "stopped") {
                                        delay(100L)
                                        w += 100L
                                    }
                                    VpnBridge.startService(this@MainActivity)
                                } else {
                                    VpnBridge.reloadService(this@MainActivity)
                                }
                            } else {
                                VpnBridge.startService(this@MainActivity)
                            }
                            var elapsed = 0L
                            while (elapsed < 18000L) {
                                delay(120L)
                                elapsed += 120L
                                when (VpnBridge.state) {
                                    "started" -> {
                                        result.success(mapOf("ok" to true, "state" to "started"))
                                        return@launch
                                    }
                                    "failed" -> {
                                        result.success(
                                            mapOf(
                                                "ok" to false,
                                                "state" to "failed",
                                                "error" to VpnBridge.lastError,
                                            ),
                                        )
                                        return@launch
                                    }
                                }
                            }
                            result.success(
                                mapOf(
                                    "ok" to (VpnBridge.state == "started"),
                                    "state" to VpnBridge.state,
                                    "error" to VpnBridge.lastError.ifBlank {
                                        "زمان راه اندازی سرویس تونل به پایان رسید."
                                    },
                                ),
                            )
                        } catch (e: Exception) {
                            result.success(
                                mapOf("ok" to false, "state" to "failed", "error" to (e.message ?: "")),
                            )
                        }
                    }
                }

                if (serviceMode != "proxy") {
                    requestVpnConsent { granted ->
                        if (!granted) {
                            result.success(
                                mapOf(
                                    "ok" to false,
                                    "permissionDenied" to true,
                                    "error" to "مجوز اتصال VPN در اندروید تایید نشد.",
                                ),
                            )
                        } else {
                            launch()
                        }
                    }
                } else {
                    launch()
                }
            }
            "stopCore", "shutdownCores" -> {
                scope.launch {
                    if (VpnBridge.state != "stopped" && VpnBridge.state != "failed") {
                        VpnBridge.stopService(this@MainActivity)
                        var waited = 0L
                        while (waited < 4000L &&
                            VpnBridge.state != "stopped" &&
                            VpnBridge.state != "failed"
                        ) {
                            delay(80L)
                            waited += 80L
                        }
                    }
                    result.success(1)
                }
            }
            "coreStatus" -> {
                val (rx, tx) = VpnBridge.sessionTraffic()
                result.success(
                    mapOf(
                        "state" to VpnBridge.state,
                        "active" to (VpnBridge.state == "started" || VpnBridge.state == "starting"),
                        "error" to VpnBridge.lastError,
                        "startedAtMs" to VpnBridge.startedAtMs,
                        "rx" to rx,
                        "tx" to tx,
                    ),
                )
            }
            "tunnelStats" -> {
                val (rx, tx) = VpnBridge.sessionTraffic()
                val active = VpnBridge.state == "started"
                result.success(
                    mapOf(
                        "rx" to rx,
                        "tx" to tx,
                        "available" to active,
                        "adapter" to if (active) "tun0" else "",
                    ),
                )
            }
            "isRunning" -> result.success(VpnBridge.state == "started")
            "runningCores" -> {
                result.success(if (VpnBridge.state == "started") listOf("umbrella-core") else emptyList<String>())
            }
            "deviceInfo" -> scope.launch {
                val info = withContext(Dispatchers.IO) { collectDeviceInfo() }
                result.success(info)
            }
            "localIp" -> scope.launch {
                val ip = withContext(Dispatchers.IO) { readLocalIpv4() }
                result.success(ip)
            }
            "adapterName" -> result.success(readActiveTransportLabel())
            "installedApps" -> scope.launch {
                val apps = withContext(Dispatchers.IO) { queryInstalledApps() }
                result.success(apps)
            }
            "httpRequest" -> {
                val method = call.argument<String>("method") ?: "GET"
                val url = call.argument<String>("url") ?: ""
                val headers = call.argument<Map<String, String>>("headers").orEmpty()
                val body = call.argument<String>("body") ?: ""
                val timeoutMs = (call.argument<Int>("timeoutMs") ?: 15000).coerceIn(2000, 45000)
                val useProxy = call.argument<Boolean>("useProxy") ?: false
                scope.launch {
                    val resp = withContext(Dispatchers.IO) {
                        executeHttp(method, url, headers, body, timeoutMs, useProxy)
                    }
                    result.success(resp)
                }
            }
            "autostart" -> {
                val enabled = call.argument<Boolean>("enabled") ?: false
                VpnBridge.prefs(this).edit().putBoolean("autostart_boot", enabled).apply()
                result.success(true)
            }
            "autostartEnabled" -> {
                result.success(VpnBridge.prefs(this).getBoolean("autostart_boot", false))
            }
            "setShowSpeed" -> {
                val enabled = call.argument<Boolean>("enabled") ?: true
                VpnBridge.prefs(this).edit().putBoolean("show_speed", enabled).apply()
                result.success(true)
            }
            "isIgnoringBatteryOptimizations" -> {
                val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
                result.success(pm.isIgnoringBatteryOptimizations(packageName))
            }
            "requestIgnoreBatteryOptimizations" -> {
                @SuppressLint("BatteryLife")
                val ok = runCatching {
                    val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
                    if (!pm.isIgnoringBatteryOptimizations(packageName)) {
                        startActivity(
                            Intent(
                                Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS,
                                Uri.parse("package:$packageName"),
                            ),
                        )
                    }
                    true
                }.getOrDefault(false)
                result.success(ok)
            }
            "openVpnSettings" -> {
                val ok = runCatching {
                    startActivity(Intent(Settings.ACTION_VPN_SETTINGS))
                    true
                }.getOrDefault(false)
                result.success(ok)
            }
            "installApk" -> {
                val path = call.argument<String>("path") ?: ""
                result.success(launchApkInstaller(path))
            }
            "shareText" -> {
                val text = call.argument<String>("text") ?: ""
                val title = call.argument<String>("title") ?: getString(R.string.app_name)
                val ok = runCatching {
                    val send = Intent(Intent.ACTION_SEND).apply {
                        type = "text/plain"
                        putExtra(Intent.EXTRA_SUBJECT, title)
                        putExtra(Intent.EXTRA_TEXT, text)
                    }
                    startActivity(Intent.createChooser(send, title))
                    true
                }.getOrDefault(false)
                result.success(ok)
            }
            "openPath" -> {
                val path = call.argument<String>("path") ?: ""
                result.success(openOrShareFile(path))
            }
            "syncSystemBars" -> {
                val dark = call.argument<Boolean>("dark") ?: true
                runCatching {
                    val controller = WindowInsetsControllerCompat(window, window.decorView)
                    controller.isAppearanceLightStatusBars = !dark
                    controller.isAppearanceLightNavigationBars = !dark
                }
                result.success(true)
            }
            "minimizeApp" -> {
                result.success(moveTaskToBack(true))
            }
            "dataDir" -> result.success(filesDir.absolutePath)
            "exePath" -> result.success(applicationInfo.sourceDir ?: "")
            "trayInit", "trayIcon", "trayTooltip", "trayMenu", "trayDestroy",
            "setSystemProxy", "disableSystemProxy", "flushDns" -> result.success(true)
            "systemProxyEnabled" -> {
                val p = VpnBridge.prefs(this)
                result.success(VpnBridge.state == "started" && p.getString("service_mode", "vpn") == "systemProxy")
            }
            "trayBalloon" -> {
                val title = call.argument<String>("title") ?: getString(R.string.app_name)
                val body = call.argument<String>("body") ?: ""
                postAlertNotification(title, body)
                result.success(true)
            }
            else -> result.notImplemented()
        }
    }

    private fun requestVpnConsent(callback: (Boolean) -> Unit) {
        val intent = VpnService.prepare(this)
        if (intent == null) {
            callback(true)
            return
        }
        pendingVpnResult = callback
        @Suppress("DEPRECATION")
        startActivityForResult(intent, REQ_VPN_PERMISSION)
    }

    @Deprecated("Deprecated in Java")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (requestCode == REQ_VPN_PERMISSION) {
            val cb = pendingVpnResult
            pendingVpnResult = null
            cb?.invoke(resultCode == Activity.RESULT_OK || VpnService.prepare(this) == null)
            return
        }
        @Suppress("DEPRECATION")
        super.onActivityResult(requestCode, resultCode, data)
    }

    private fun postAlertNotification(title: String, body: String) {
        if (body.isBlank()) return
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            ContextCompat.checkSelfPermission(this, Manifest.permission.POST_NOTIFICATIONS) !=
            PackageManager.PERMISSION_GRANTED
        ) return
        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as android.app.NotificationManager
        val openIntent = PendingIntentHelper.mainActivity(this)
        val notif = NotificationCompat.Builder(this, VpnBridge.CHANNEL_ALERTS)
            .setSmallIcon(R.drawable.ic_stat_umbrella)
            .setContentTitle(title)
            .setContentText(body)
            .setStyle(NotificationCompat.BigTextStyle().bigText(body))
            .setAutoCancel(true)
            .setContentIntent(openIntent)
            .build()
        runCatching { nm.notify(alertSeq++, notif) }
    }

    private fun launchApkInstaller(path: String): Boolean {
        val file = File(path)
        if (!file.exists()) return false
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
            !packageManager.canRequestPackageInstalls()
        ) {
            return runCatching {
                startActivity(
                    Intent(
                        Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                        Uri.parse("package:$packageName"),
                    ).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
                )
                false
            }.getOrDefault(false)
        }
        return runCatching {
            val uri = FileProvider.getUriForFile(this, "$packageName.fileprovider", file)
            val install = Intent(Intent.ACTION_VIEW).apply {
                setDataAndType(uri, "application/vnd.android.package-archive")
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_GRANT_READ_URI_PERMISSION)
            }
            startActivity(install)
            true
        }.getOrDefault(false)
    }

    private fun openOrShareFile(path: String): Boolean {
        val file = File(path)
        if (!file.exists()) return false
        if (file.extension.equals("apk", ignoreCase = true)) {
            return launchApkInstaller(path)
        }
        return runCatching {
            val uri = FileProvider.getUriForFile(this, "$packageName.fileprovider", file)
            val share = Intent(Intent.ACTION_SEND).apply {
                type = "text/plain"
                putExtra(Intent.EXTRA_STREAM, uri)
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            }
            startActivity(Intent.createChooser(share, getString(R.string.app_name)))
            true
        }.getOrDefault(false)
    }

    @SuppressLint("HardwareIds")
    private fun collectDeviceInfo(): Map<String, Any> {
        val am = getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
        val mem = ActivityManager.MemoryInfo().also { am.getMemoryInfo(it) }
        val stat = StatFs(Environment.getDataDirectory().path)
        val mb = 1024L * 1024L
        val ramTotalMb = (mem.totalMem / mb).coerceAtLeast(0L)
        val ramFreeMb = (mem.availMem / mb).coerceAtLeast(0L)
        val ramUsedMb = (ramTotalMb - ramFreeMb).coerceAtLeast(0L)
        val ramLoadPercent = if (ramTotalMb > 0L) {
            ((ramUsedMb * 100L) / ramTotalMb).toInt().coerceIn(0, 100)
        } else 0
        val diskTotalMb = (stat.totalBytes / mb).coerceAtLeast(0L)
        val diskFreeMb = (stat.availableBytes / mb).coerceAtLeast(0L)
        val dm = resources.displayMetrics

        val bm = getSystemService(Context.BATTERY_SERVICE) as BatteryManager
        val batteryPct = bm.getIntProperty(BatteryManager.BATTERY_PROPERTY_CAPACITY).coerceIn(0, 100)
        val bStatus = registerReceiver(null, IntentFilter(Intent.ACTION_BATTERY_CHANGED))
            ?.getIntExtra(BatteryManager.EXTRA_STATUS, -1) ?: -1
        val charging = bStatus == BatteryManager.BATTERY_STATUS_CHARGING ||
            bStatus == BatteryManager.BATTERY_STATUS_FULL

        val rawAndroidId = runCatching {
            Settings.Secure.getString(contentResolver, Settings.Secure.ANDROID_ID)
        }.getOrNull().orEmpty()
        val digest = MessageDigest.getInstance("SHA-256")
            .digest("umbrella-android:$rawAndroidId:${Build.BOARD}:${Build.BRAND}".toByteArray())
            .joinToString("") { "%02x".format(it) }
            .take(32)

        val abi = Build.SUPPORTED_ABIS.firstOrNull() ?: "arm64-v8a"
        val brand = Build.MANUFACTURER.trim().replaceFirstChar { it.uppercase() }
        val model = Build.MODEL.trim()
        val fullModel = if (model.startsWith(brand, ignoreCase = true)) model else "$brand $model"
        val soc = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            "${Build.SOC_MANUFACTURER} ${Build.SOC_MODEL}".trim().ifBlank { Build.HARDWARE }
        } else {
            Build.HARDWARE
        }
        val carrier = runCatching {
            (getSystemService(Context.TELEPHONY_SERVICE) as TelephonyManager)
                .networkOperatorName?.trim().orEmpty()
        }.getOrDefault("")
        val securityPatch = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            Build.VERSION.SECURITY_PATCH ?: ""
        } else ""
        val pm = getSystemService(Context.POWER_SERVICE) as PowerManager

        return mapOf(
            "hostname" to fullModel,
            "username" to brand,
            "os" to "Android ${Build.VERSION.RELEASE} (SDK ${Build.VERSION.SDK_INT})",
            "osBuild" to Build.VERSION.SDK_INT,
            "osDisplayVersion" to Build.VERSION.RELEASE,
            "osEdition" to securityPatch,
            "manufacturer" to brand,
            "model" to fullModel,
            "arch" to abi,
            "cpu" to soc,
            "cpuCores" to Runtime.getRuntime().availableProcessors(),
            "ramTotalMb" to ramTotalMb,
            "ramUsedMb" to ramUsedMb,
            "ramLoadPercent" to ramLoadPercent,
            "diskTotalMb" to diskTotalMb,
            "diskFreeMb" to diskFreeMb,
            "screenWidth" to dm.widthPixels,
            "screenHeight" to dm.heightPixels,
            "uptimeSeconds" to (SystemClock.elapsedRealtime() / 1000L),
            "localIp" to readLocalIpv4(),
            "adapterName" to readActiveTransportLabel(),
            "carrier" to carrier,
            "machineId" to digest,
            "elevated" to (VpnService.prepare(this) == null),
            "batteryOptimized" to !pm.isIgnoringBatteryOptimizations(packageName),
            "hasBattery" to true,
            "batteryPercent" to batteryPct,
            "powerPlugged" to charging,
        )
    }

    private fun readLocalIpv4(): String {
        runCatching {
            val interfaces = NetworkInterface.getNetworkInterfaces()?.toList().orEmpty()
            for (ni in interfaces) {
                if (!ni.isUp || ni.isLoopback) continue
                val name = ni.name.lowercase()
                if (name.startsWith("tun") || name.startsWith("ppp")) continue
                for (addr in ni.inetAddresses) {
                    if (addr is Inet4Address && !addr.isLoopbackAddress) {
                        return addr.hostAddress ?: continue
                    }
                }
            }
        }
        return ""
    }

    private fun readActiveTransportLabel(): String {
        val cm = getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
        val net = PhysicalNetworkTracker.activeOrProbe(this) ?: cm.activeNetwork ?: return ""
        val caps = runCatching { cm.getNetworkCapabilities(net) }.getOrNull() ?: return ""
        return when {
            caps.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) -> "شبکه وای فای"
            caps.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR) -> "اینترنت همراه"
            caps.hasTransport(NetworkCapabilities.TRANSPORT_ETHERNET) -> "شبکه کابلی"
            else -> "شبکه اندروید"
        }
    }

    private fun queryInstalledApps(): List<Map<String, Any>> {
        val pm = packageManager
        val apps = runCatching { pm.getInstalledApplications(PackageManager.GET_META_DATA) }
            .getOrDefault(emptyList())
        return apps
            .asSequence()
            .filter { it.packageName != packageName }
            .filter {
                val isSystem = (it.flags and ApplicationInfo.FLAG_SYSTEM) != 0 &&
                    (it.flags and ApplicationInfo.FLAG_UPDATED_SYSTEM_APP) == 0
                !isSystem || pm.getLaunchIntentForPackage(it.packageName) != null
            }
            .map { info ->
                val label = runCatching { pm.getApplicationLabel(info).toString().trim() }
                    .getOrDefault(info.packageName)
                val isSystem = (info.flags and ApplicationInfo.FLAG_SYSTEM) != 0 &&
                    (info.flags and ApplicationInfo.FLAG_UPDATED_SYSTEM_APP) == 0
                mapOf(
                    "packageName" to info.packageName,
                    "appName" to label.ifBlank { info.packageName },
                    "isSystem" to isSystem,
                )
            }
            .sortedWith(compareBy({ it["isSystem"] as Boolean }, { (it["appName"] as String).lowercase() }))
            .toList()
    }

    private fun executeHttp(
        method: String,
        urlStr: String,
        headers: Map<String, String>,
        body: String,
        timeoutMs: Int,
        useProxy: Boolean,
    ): Map<String, Any> {
        var conn: HttpURLConnection? = null
        return try {
            val url = URL(urlStr)
            conn = when {
                useProxy && VpnBridge.state == "started" -> {
                    val port = VpnBridge.prefs(this).getInt("proxy_port", 12334)
                    val proxy = Proxy(Proxy.Type.HTTP, InetSocketAddress("127.0.0.1", port))
                    url.openConnection(proxy) as HttpURLConnection
                }
                else -> {
                    val net = PhysicalNetworkTracker.activeOrProbe(this)
                    ((net?.openConnection(url) ?: url.openConnection()) as HttpURLConnection)
                }
            }
            conn.requestMethod = method.uppercase()
            conn.connectTimeout = timeoutMs
            conn.readTimeout = timeoutMs
            conn.instanceFollowRedirects = true
            conn.useCaches = false
            for ((k, v) in headers) {
                conn.setRequestProperty(k, v)
            }
            if (body.isNotEmpty() && method.uppercase() in setOf("POST", "PUT", "PATCH")) {
                conn.doOutput = true
                val bytes = body.toByteArray(Charsets.UTF_8)
                conn.setFixedLengthStreamingMode(bytes.size)
                conn.outputStream.use { it.write(bytes) }
            }
            val code = conn.responseCode
            val stream = if (code in 200..399) conn.inputStream else (conn.errorStream ?: conn.inputStream)
            val respBytes = stream?.use { it.readBytes() } ?: ByteArray(0)
            val contentType = conn.contentType ?: ""
            mapOf(
                "ok" to true,
                "statusCode" to code,
                "bodyBytes" to respBytes,
                "contentType" to contentType,
                "winError" to 0,
                "error" to "",
            )
        } catch (e: Exception) {
            mapOf(
                "ok" to false,
                "statusCode" to 0,
                "bodyBytes" to ByteArray(0),
                "contentType" to "",
                "winError" to -1,
                "error" to "${e.javaClass.simpleName}: ${e.message ?: ""}",
            )
        } finally {
            runCatching { conn?.disconnect() }
        }
    }
}

private object PendingIntentHelper {
    fun mainActivity(ctx: Context): android.app.PendingIntent =
        android.app.PendingIntent.getActivity(
            ctx,
            0,
            Intent(ctx, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
            },
            android.app.PendingIntent.FLAG_UPDATE_CURRENT or android.app.PendingIntent.FLAG_IMMUTABLE,
        )
}
