package ir.umbrella.vpn

import android.Manifest
import android.annotation.SuppressLint
import android.app.ActivityManager
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.ApplicationInfo
import android.content.pm.PackageManager
import android.net.Uri
import android.os.BatteryManager
import android.os.Build
import android.os.Environment
import android.os.StatFs
import android.os.SystemClock
import android.provider.Settings as AndroidSettings
import androidx.core.content.ContextCompat
import androidx.core.content.FileProvider
import com.hiddify.core.api.v2.hcommon.ResponseCode
import com.hiddify.core.api.v2.hcore.CoreClient
import com.hiddify.core.api.v2.hcore.FetchUrlError
import com.hiddify.core.api.v2.hcore.FetchUrlRequest
import com.hiddify.core.api.v2.hcore.ParseRequest
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import ir.umbrella.vpn.bg.BoxService
import ir.umbrella.vpn.constant.PerAppProxyMode
import ir.umbrella.vpn.constant.ServiceMode
import ir.umbrella.vpn.constant.Status
import ir.umbrella.vpn.utils.GrpcClientProvider
import ir.umbrella.vpn.utils.answer
import ir.umbrella.vpn.utils.answerNow
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import okhttp3.Headers.Companion.toHeaders
import okhttp3.MediaType.Companion.toMediaTypeOrNull
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import java.io.File
import java.net.Inet4Address
import java.net.InetSocketAddress
import java.net.NetworkInterface
import java.net.Proxy
import java.util.concurrent.TimeUnit

class MethodHandler(
    private val activity: MainActivity,
) : MethodChannel.MethodCallHandler {
    private val scope = CoroutineScope(Dispatchers.IO + SupervisorJob())

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "getPlatformInfo" -> result.answerNow(call.method) { buildPlatformInfo() }
            "setupDirectories" -> result.answerNow(call.method) { handleSetupDirectories(call) }
            "ensureVpnPermission" -> scope.launch {
                result.answer(call.method) { activity.ensureVpnAndNotificationPermissions() }
            }
            "startCore" -> scope.launch {
                result.answer(call.method) { handleStartCore(call) }
            }
            "stopCore" -> scope.launch {
                result.answer(call.method) { handleStopCore() }
            }
            "getCoreStatus" -> result.answerNow(call.method) { buildCoreStatus() }
            "parseConfig" -> scope.launch {
                result.answer(call.method) { handleParseConfig(call) }
            }
            "fetchUrlWithCore" -> scope.launch {
                result.answer(call.method) { handleFetchUrlWithCore(call) }
            }
            "getInstalledApps" -> scope.launch {
                result.answer(call.method) { handleGetInstalledApps() }
            }
            "setPerAppProxy" -> result.answerNow(call.method) { handleSetPerAppProxy(call) }
            "setStartOnBoot" -> result.answerNow(call.method) {
                Settings.startOnBoot = call.argument<Boolean>("enabled") ?: false
                true
            }
            "getBatteryOptimizationStatus" -> result.answerNow(call.method) {
                isIgnoringBatteryOptimizations()
            }
            "requestIgnoreBatteryOptimization" -> result.answerNow(call.method) {
                requestIgnoreBatteryOptimization()
            }
            "installApk" -> result.answerNow(call.method) {
                handleInstallApk(call.argument<String>("path") ?: "")
            }
            "openVpnSystemSettings" -> result.answerNow(call.method) {
                activity.startActivity(
                    Intent(AndroidSettings.ACTION_VPN_SETTINGS).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
                )
                true
            }
            "consumeRecentCrashes" -> result.answerNow(call.method) {
                AppCrashRecorder.consumeRecent(activity)
            }
            "getLanIps" -> result.answerNow(call.method) { getLanIpv4Addresses() }
            "httpRequest" -> scope.launch {
                result.answer(call.method) { handleHttpRequest(call) }
            }
            else -> result.notImplemented()
        }
    }

    private fun buildPlatformInfo(): Map<String, Any> {
        val canInstall = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            activity.packageManager.canRequestPackageInstalls()
        } else {
            true
        }
        val notifGranted = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            ContextCompat.checkSelfPermission(
                activity,
                Manifest.permission.POST_NOTIFICATIONS,
            ) == PackageManager.PERMISSION_GRANTED
        } else {
            true
        }
        val deviceName = runCatching {
            AndroidSettings.Global.getString(
                activity.contentResolver,
                AndroidSettings.Global.DEVICE_NAME,
            )?.takeIf { it.isNotBlank() }
        }.getOrNull() ?: "${Build.MANUFACTURER} ${Build.MODEL}"

        val memInfo = ActivityManager.MemoryInfo()
        val am = activity.getSystemService(Context.ACTIVITY_SERVICE) as? ActivityManager
        am?.getMemoryInfo(memInfo)
        val ramTotalMb = (memInfo.totalMem / (1024L * 1024L)).toInt().coerceAtLeast(0)
        val ramUsedMb = ((memInfo.totalMem - memInfo.availMem).coerceAtLeast(0L) / (1024L * 1024L)).toInt()
        val ramLoadPercent = if (ramTotalMb > 0) ((ramUsedMb * 100) / ramTotalMb).coerceIn(0, 100) else 0

        val stat = StatFs(Environment.getDataDirectory().path)
        val diskTotalMb = (stat.totalBytes / (1024L * 1024L)).toInt().coerceAtLeast(0)
        val diskFreeMb = (stat.availableBytes / (1024L * 1024L)).toInt().coerceAtLeast(0)

        val batteryIntent = activity.registerReceiver(null, IntentFilter(Intent.ACTION_BATTERY_CHANGED))
        val level = batteryIntent?.getIntExtra(BatteryManager.EXTRA_LEVEL, -1) ?: -1
        val scale = batteryIntent?.getIntExtra(BatteryManager.EXTRA_SCALE, -1) ?: -1
        val batteryPercent = if (level >= 0 && scale > 0) ((level * 100) / scale).coerceIn(0, 100) else -1
        val plugged = batteryIntent?.getIntExtra(BatteryManager.EXTRA_PLUGGED, 0) ?: 0
        val powerPlugged = plugged != 0
        val uptimeSeconds = (SystemClock.elapsedRealtime() / 1000L).toInt().coerceAtLeast(0)

        return mapOf(
            "platform" to "Android",
            "deviceName" to deviceName,
            "manufacturer" to Build.MANUFACTURER,
            "model" to Build.MODEL,
            "osVersion" to Build.VERSION.RELEASE,
            "sdkInt" to Build.VERSION.SDK_INT,
            "abi" to (Build.SUPPORTED_ABIS.firstOrNull() ?: "arm64-v8a"),
            "ramTotalMb" to ramTotalMb,
            "ramUsedMb" to ramUsedMb,
            "ramLoadPercent" to ramLoadPercent,
            "diskTotalMb" to diskTotalMb,
            "diskFreeMb" to diskFreeMb,
            "batteryPercent" to batteryPercent,
            "powerPlugged" to powerPlugged,
            "uptimeSeconds" to uptimeSeconds,
            "batteryOptimized" to !isIgnoringBatteryOptimizations(),
            "canRequestInstallPackages" to canInstall,
            "notificationGranted" to notifGranted,
            "startOnBoot" to Settings.startOnBoot,
            "perAppProxyMode" to Settings.perAppProxyMode,
            "perAppIncludePackages" to Settings.perAppIncludePackages,
            "perAppExcludePackages" to Settings.perAppExcludePackages,
            "baseDir" to Settings.baseDir,
            "workingDir" to Settings.workingDir,
            "tempDir" to Settings.tempDir,
        )
    }

    private fun handleSetupDirectories(call: MethodCall): Map<String, Any> {
        call.argument<String>("baseDir")?.takeIf { it.isNotBlank() }?.let {
            File(it).mkdirs()
            Settings.baseDir = it
        }
        call.argument<String>("workingDir")?.takeIf { it.isNotBlank() }?.let {
            File(it).mkdirs()
            Settings.workingDir = it
        }
        call.argument<String>("tempDir")?.takeIf { it.isNotBlank() }?.let {
            File(it).mkdirs()
            Settings.tempDir = it
        }
        call.argument<Int>("grpcServicePort")?.takeIf { it in 1024..65535 }?.let {
            Settings.grpcServicePort = it
        }
        call.argument<Int>("grpcUtilityPort")?.takeIf { it in 1024..65535 }?.let {
            Settings.grpcUtilityPort = it
        }
        call.argument<Boolean>("debug")?.let {
            Settings.debugMode = it
        }
        return mapOf(
            "baseDir" to Settings.baseDir,
            "workingDir" to Settings.workingDir,
            "tempDir" to Settings.tempDir,
            "grpcServicePort" to Settings.grpcServicePort,
            "grpcUtilityPort" to Settings.grpcUtilityPort,
        )
    }

    private suspend fun handleStartCore(call: MethodCall): Map<String, Any> {
        val configPath = call.argument<String>("configPath") ?: error("missing configPath")
        val settingsJson = call.argument<String>("settingsJson") ?: ""
        val profileName = call.argument<String>("profileName") ?: "آمبرلا"
        val mode = call.argument<String>("serviceMode") ?: ServiceMode.VPN
        val normalizedMode = if (mode == ServiceMode.PROXY) ServiceMode.PROXY else ServiceMode.VPN

        if (normalizedMode == ServiceMode.VPN) {
            val granted = activity.ensureVpnAndNotificationPermissions()
            if (!granted) {
                return mapOf("ok" to false, "error" to "vpn_permission_denied")
            }
        } else {
            activity.ensureNotificationPermissionOnly()
        }

        val currentStatus = BoxService.status.value ?: Status.Stopped
        if (currentStatus == Status.Started || currentStatus == Status.Starting) {
            handleStopCore()
        }

        Settings.serviceMode = normalizedMode
        Settings.activeConfigPath = configPath
        Settings.activeSettingsJson = settingsJson
        Settings.activeProfileName = profileName

        withContext(Dispatchers.Main) {
            activity.reconnectServiceObserver()
            BoxService.start(activity, startCore = true)
        }

        return mapOf(
            "ok" to true,
            "grpcPort" to Settings.grpcServicePort,
            "serviceMode" to normalizedMode,
        )
    }

    private suspend fun handleStopCore(): Boolean {
        val current = BoxService.status.value ?: Status.Stopped
        if (current == Status.Stopped) return true

        withContext(Dispatchers.Main) {
            BoxService.stop(activity)
        }
        for (i in 0 until 40) {
            if ((BoxService.status.value ?: Status.Stopped) == Status.Stopped) {
                return true
            }
            delay(100)
        }
        return (BoxService.status.value ?: Status.Stopped) == Status.Stopped
    }

    private fun buildCoreStatus(): Map<String, Any> {
        val status = BoxService.status.value ?: Status.Stopped
        return mapOf(
            "status" to status.name,
            "active" to (status == Status.Started),
            "starting" to (status == Status.Starting),
            "stopping" to (status == Status.Stopping),
            "serviceMode" to Settings.serviceMode,
            "grpcServicePort" to Settings.grpcServicePort,
            "grpcUtilityPort" to Settings.grpcUtilityPort,
        )
    }

    private suspend fun handleParseConfig(call: MethodCall): Map<String, Any> {
        val content = call.argument<String>("content") ?: ""
        val configPath = call.argument<String>("configPath") ?: ""
        val tempPath = call.argument<String>("tempPath") ?: Settings.tempDir
        val debug = call.argument<Boolean>("debug") ?: Settings.debugMode

        val port = BoxService.ensureUtilityCore()
        val client = GrpcClientProvider.coreGrpcClient(port, callTimeoutSeconds = 30L)
            .create(CoreClient::class)
        val resp = client.Parse().execute(
            ParseRequest(
                content = content,
                config_path = configPath,
                temp_path = tempPath,
                debug = debug,
            ),
        )
        return mapOf(
            "ok" to (resp.response_code == ResponseCode.OK),
            "responseCode" to resp.response_code.name,
            "content" to resp.content,
            "message" to resp.message,
        )
    }

    private suspend fun handleFetchUrlWithCore(call: MethodCall): Map<String, Any> {
        val url = call.argument<String>("url") ?: error("missing url")
        val userAgent = call.argument<String>("userAgent") ?: ""
        val timeoutMs = call.argument<Int>("timeoutMs") ?: 15000

        val port = BoxService.ensureUtilityCore()
        val timeoutSeconds = ((timeoutMs / 1000L) + 10L).coerceAtLeast(20L)
        val client = GrpcClientProvider.coreGrpcClient(port, callTimeoutSeconds = timeoutSeconds)
            .create(CoreClient::class)
        val resp = client.FetchUrl().execute(
            FetchUrlRequest(
                url = url,
                user_agent = userAgent,
                timeout_ms = timeoutMs,
            ),
        )

        val headersMap = linkedMapOf<String, String>()
        for (h in resp.headers) {
            val k = h.name.lowercase()
            headersMap[k] = headersMap[k]?.let { "$it, ${h.value}" } ?: h.value
        }
        return mapOf(
            "ok" to (resp.error == FetchUrlError.FETCH_URL_ERROR_NONE && resp.status_code > 0),
            "statusCode" to resp.status_code,
            "headers" to headersMap,
            "bodyBytes" to resp.body.toByteArray(),
            "error" to resp.error.name,
            "errorDetail" to resp.error_detail,
        )
    }

    @SuppressLint("QueryPermissionsNeeded")
    private fun handleGetInstalledApps(): List<Map<String, Any>> {
        val pm = activity.packageManager
        val selfPkg = activity.packageName
        val apps = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            pm.getInstalledApplications(PackageManager.ApplicationInfoFlags.of(0L))
        } else {
            @Suppress("DEPRECATION")
            pm.getInstalledApplications(PackageManager.GET_META_DATA)
        }
        return apps
            .asSequence()
            .filter { it.packageName != selfPkg }
            .filter { pm.getLaunchIntentForPackage(it.packageName) != null || (it.flags and ApplicationInfo.FLAG_SYSTEM) == 0 }
            .map { info ->
                val label = runCatching { pm.getApplicationLabel(info).toString() }.getOrDefault(info.packageName)
                mapOf(
                    "packageName" to info.packageName,
                    "name" to label,
                    "isSystem" to ((info.flags and ApplicationInfo.FLAG_SYSTEM) != 0),
                )
            }
            .sortedWith(compareBy<Map<String, Any>> { it["isSystem"] as Boolean }.thenBy { (it["name"] as String).lowercase() })
            .toList()
    }

    private fun handleSetPerAppProxy(call: MethodCall): Boolean {
        val mode = call.argument<String>("mode") ?: PerAppProxyMode.OFF
        val normalized = when (mode) {
            PerAppProxyMode.INCLUDE -> PerAppProxyMode.INCLUDE
            PerAppProxyMode.EXCLUDE -> PerAppProxyMode.EXCLUDE
            else -> PerAppProxyMode.OFF
        }
        Settings.perAppProxyMode = normalized
        call.argument<List<String>>("includePackages")?.let { Settings.perAppIncludePackages = it }
        call.argument<List<String>>("excludePackages")?.let { Settings.perAppExcludePackages = it }
        return true
    }

    private fun isIgnoringBatteryOptimizations(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return true
        return UmbrellaApplication.powerManager.isIgnoringBatteryOptimizations(activity.packageName)
    }

    @SuppressLint("BatteryLife")
    private fun requestIgnoreBatteryOptimization(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return true
        if (UmbrellaApplication.powerManager.isIgnoringBatteryOptimizations(activity.packageName)) {
            return true
        }
        val intent = Intent(AndroidSettings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS).apply {
            data = Uri.parse("package:${activity.packageName}")
        }
        return runCatching {
            activity.startActivity(intent)
            true
        }.getOrDefault(false)
    }

    private fun handleInstallApk(path: String): Map<String, Any> {
        val file = File(path)
        if (!file.exists()) {
            return mapOf("ok" to false, "reason" to "file_not_found")
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
            !activity.packageManager.canRequestPackageInstalls()
        ) {
            val permIntent = Intent(AndroidSettings.ACTION_MANAGE_UNKNOWN_APP_SOURCES).apply {
                data = Uri.parse("package:${activity.packageName}")
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            runCatching { activity.startActivity(permIntent) }
            return mapOf("ok" to false, "reason" to "install_permission_required")
        }

        val uri = FileProvider.getUriForFile(
            activity,
            "${activity.packageName}.updates",
            file,
        )
        val installIntent = Intent(Intent.ACTION_VIEW).apply {
            setDataAndType(uri, "application/vnd.android.package-archive")
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
        activity.startActivity(installIntent)
        return mapOf("ok" to true)
    }

    private fun getLanIpv4Addresses(): List<String> {
        val out = mutableListOf<String>()
        runCatching {
            val ifaces = NetworkInterface.getNetworkInterfaces() ?: return@runCatching
            for (iface in ifaces) {
                if (!iface.isUp || iface.isLoopback) continue
                for (addr in iface.inetAddresses) {
                    if (!addr.isLoopbackAddress && addr is Inet4Address) {
                        addr.hostAddress?.let { out.add(it) }
                    }
                }
            }
        }
        return out.distinct()
    }

    private fun handleHttpRequest(call: MethodCall): Map<String, Any> {
        val method = (call.argument<String>("method") ?: "GET").uppercase()
        val url = call.argument<String>("url") ?: error("missing url")
        val headers = call.argument<Map<String, String>>("headers").orEmpty()
        val bodyBytes = call.argument<ByteArray>("bodyBytes")
        val timeoutMs = (call.argument<Int>("timeoutMs") ?: 15000).toLong()
        val proxyHost = call.argument<String>("proxyHost")
        val proxyPort = call.argument<Int>("proxyPort") ?: 0
        val followRedirects = call.argument<Boolean>("followRedirects") ?: true

        val builder = OkHttpClient.Builder()
            .connectTimeout(timeoutMs, TimeUnit.MILLISECONDS)
            .readTimeout(timeoutMs, TimeUnit.MILLISECONDS)
            .writeTimeout(timeoutMs, TimeUnit.MILLISECONDS)
            .followRedirects(followRedirects)
            .followSslRedirects(followRedirects)

        if (!proxyHost.isNullOrBlank() && proxyPort in 1..65535) {
            builder.proxy(Proxy(Proxy.Type.HTTP, InetSocketAddress(proxyHost, proxyPort)))
        }

        val reqBody = when (method) {
            "GET", "HEAD", "DELETE" -> null
            else -> (bodyBytes ?: ByteArray(0)).toRequestBody(
                headers.entries.firstOrNull { it.key.equals("content-type", ignoreCase = true) }
                    ?.value
                    ?.toMediaTypeOrNull(),
            )
        }

        val req = Request.Builder()
            .url(url)
            .headers(headers.toHeaders())
            .method(method, reqBody)
            .build()

        val resp = builder.build().newCall(req).execute()
        val respHeaders = linkedMapOf<String, String>()
        for (i in 0 until resp.headers.size) {
            val name = resp.headers.name(i).lowercase()
            val value = resp.headers.value(i)
            respHeaders[name] = respHeaders[name]?.let { "$it, $value" } ?: value
        }
        val respBytes = resp.body?.bytes() ?: ByteArray(0)
        resp.close()

        return mapOf(
            "statusCode" to resp.code,
            "headers" to respHeaders,
            "bodyBytes" to respBytes,
        )
    }
}
