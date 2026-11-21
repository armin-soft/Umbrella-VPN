package ir.umbrella.app

import android.app.Activity
import android.content.Intent
import android.net.VpnService
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

/** Android platform bridge. A VPN grant is never treated as an active tunnel. */
class MainActivity : FlutterActivity() {
    private var pendingVpnPermission: MethodChannel.Result? = null
    private val vpnRequestCode = 4701

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "ir.umbrella.app/android")
            .setMethodCallHandler { call, result ->
                when (call.method) {
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
                    // Fail closed until the native core and VPN service exist.
                    "coreAvailable", "isServiceRunning" -> result.success(false)
                    "startService", "stopService" -> result.error(
                        "CORE_NOT_READY", "VPN core service is not installed", null,
                    )
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
        super.onDestroy()
    }
}
