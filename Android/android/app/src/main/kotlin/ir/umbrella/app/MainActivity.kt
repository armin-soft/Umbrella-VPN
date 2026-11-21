package ir.umbrella.app

import android.app.Activity
import android.content.Intent
import android.content.ComponentName
import android.content.Context
import android.content.ServiceConnection
import android.net.VpnService
import android.os.Build
import android.os.IBinder
import android.os.Handler
import android.os.Looper
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

/** Android platform bridge. A VPN grant is never treated as an active tunnel. */
class MainActivity : FlutterActivity() {
    private var pendingVpnPermission: MethodChannel.Result? = null
    private val vpnRequestCode = 4701
    private val handler = Handler(Looper.getMainLooper())
    private var service: UmbrellaVpnService? = null
    private var bound = false
    private var pendingStart: MethodChannel.Result? = null
    private var pendingPort = 0
    private val connection = object : ServiceConnection {
        override fun onServiceConnected(name: ComponentName, binder: IBinder) {
            val vpn = (binder as? UmbrellaVpnService.LocalBinder)?.service
            if (vpn == null) { failStart("Invalid service binder"); return }
            service = vpn
            val waiting = pendingStart ?: return
            if (vpn.isCoreReady) { pendingStart = null; waiting.error("CORE_ACTIVE", "VPN service already active", null); return }
            vpn.prepareCore(pendingPort) { outcome ->
                if (pendingStart !== waiting) return@prepareCore
                pendingStart = null
                outcome.fold({ waiting.success(true) }, { waiting.error("CORE_START_FAILED", it.message, null) })
            }
        }
        override fun onServiceDisconnected(name: ComponentName) {
            service = null
            failStart("VPN service disconnected")
        }
    }

    private fun releaseBinding() {
        if (bound) { unbindService(connection); bound = false }
        service = null
    }

    private fun failStart(message: String) {
        val pending = pendingStart
        pendingStart = null
        pending?.error("CORE_START_FAILED", message, null)
    }

    private fun startVpn(port: Int, result: MethodChannel.Result) {
        if (pendingStart != null || service?.isCoreReady == true) {
            result.error("CORE_ACTIVE", "VPN service is already starting or active", null); return
        }
        if (port !in 1..65535 || VpnService.prepare(this) != null || !File(filesDir, "grpc/client.crt").isFile) {
            result.error("CORE_NOT_READY", "VPN consent or client certificate missing", null); return
        }
        val intent = Intent(this, UmbrellaVpnService::class.java).setAction(UmbrellaVpnService.ACTION_PREPARE)
        pendingStart = result
        pendingPort = port
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) startForegroundService(intent) else startService(intent)
            if (bound) {
                val vpn = service ?: error("VPN service is not connected")
                vpn.prepareCore(port) { outcome ->
                    if (pendingStart !== result) return@prepareCore
                    pendingStart = null
                    outcome.fold({ result.success(true) }, { result.error("CORE_START_FAILED", it.message, null) })
                }
            } else {
                check(bindService(intent, connection, Context.BIND_AUTO_CREATE)) { "Cannot bind VPN service" }
                bound = true
            }
            handler.postDelayed({
                if (pendingStart === result) {
                    failStart("VPN setup timed out")
                    service?.stopCore { }
                    if (service == null) stopService(intent)
                }
            }, 30000)
        } catch (error: Exception) {
            failStart(error.message ?: "Cannot start VPN service")
            stopService(intent)
        }
    }

    private fun stopVpn(result: MethodChannel.Result) {
        if (pendingStart != null) { result.error("CORE_BUSY", "VPN setup in progress", null); return }
        val vpn = service
        if (vpn == null) {
            // Without a binder there is no acknowledgement that resources were closed.
            result.success(false)
            return
        }
        vpn.stopCore { ok ->
            releaseBinding()
            result.success(ok)
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "ir.umbrella.app/android")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "minimizeApp" -> result.success(moveTaskToBack(true))
                    "isVpnPrepared" -> result.success(VpnService.prepare(this) == null)
                    "requestVpnPermission" -> requestVpnPermission(result)
                    "coreDirectories" -> {
                        val working = File(filesDir, "core")
                        val temp = File(cacheDir, "core")
                        if ((!working.exists() && !working.mkdirs()) ||
                            (!temp.exists() && !temp.mkdirs())) {
                            result.error("DIRECTORY_ERROR", "Cannot create private core directories", null)
                        } else {
                            result.success(mapOf(
                                "baseDir" to filesDir.absolutePath,
                                "workingDir" to working.absolutePath,
                                "tempDir" to temp.absolutePath,
                            ))
                        }
                    }
                    "deviceInfo" -> result.success(mapOf(
                        "hostname" to listOf(Build.MANUFACTURER, Build.MODEL)
                            .filter { it.isNotBlank() }.joinToString(" "),
                        "os" to "Android ${Build.VERSION.RELEASE}",
                        "osDisplayVersion" to Build.VERSION.RELEASE,
                        "arch" to Build.SUPPORTED_ABIS.firstOrNull().orEmpty(),
                        "cpuCores" to Runtime.getRuntime().availableProcessors(),
                    ))
                    "coreAvailable" -> result.success(runCatching { com.hiddify.core.mobile.Mobile.test().isNotEmpty() }.getOrDefault(false))
                    "isServiceRunning" -> result.success(service?.isCoreReady == true)
                    "serverCertificate" -> result.success(service?.serverCertificate())
                    "startService" -> startVpn(call.argument<Int>("grpcPort") ?: 17078, result)
                    "stopService" -> stopVpn(result)
                    else -> result.notImplemented()
                }
            }
    }

    @Suppress("DEPRECATION")
    private fun requestVpnPermission(result: MethodChannel.Result) {
        if (pendingVpnPermission != null) {
            result.error("VPN_REQUEST_PENDING", "A VPN permission request is already open", null)
            return
        }
        try {
            val intent = VpnService.prepare(this)
            if (intent == null) {
                result.success(true)
                return
            }
            pendingVpnPermission = result
            startActivityForResult(intent, vpnRequestCode)
        } catch (error: Exception) {
            pendingVpnPermission = null
            result.error("VPN_PERMISSION_ERROR", error.message, null)
        }
    }

    @Deprecated("Used for VPN consent across supported Android versions")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != vpnRequestCode) return
        val pending = pendingVpnPermission
        pendingVpnPermission = null
        pending?.success(resultCode == Activity.RESULT_OK && VpnService.prepare(this) == null)
    }

    override fun onDestroy() {
        pendingVpnPermission?.success(false)
        pendingVpnPermission = null
        if (pendingStart != null) {
            failStart("Activity closed during VPN setup")
            val vpn = service
            if (vpn != null) vpn.stopCore { } else stopService(Intent(this, UmbrellaVpnService::class.java))
        }
        releaseBinding()
        super.onDestroy()
    }
}
