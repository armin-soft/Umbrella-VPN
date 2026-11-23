package ir.umbrella.vpn

import android.Manifest
import android.annotation.SuppressLint
import android.content.Intent
import android.content.pm.PackageManager
import android.net.VpnService
import android.os.Build
import android.os.Bundle
import android.util.Log
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import ir.umbrella.vpn.bg.ServiceConnection
import ir.umbrella.vpn.constant.Alert
import ir.umbrella.vpn.constant.Status
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeoutOrNull

class MainActivity : FlutterFragmentActivity(), ServiceConnection.Callback {
    companion object {
        private const val TAG = "UmbrellaMainActivity"
        private const val METHOD_CHANNEL = "ir.umbrella.app/native"
        private const val EVENT_CHANNEL = "ir.umbrella.app/service_events"
        private const val REQ_VPN_PERMISSION = 2001
        private const val REQ_NOTIFICATION_PERMISSION = 2002
    }

    private val eventHandler = EventHandler()
    private val serviceConnection by lazy { ServiceConnection(this, this) }
    private var vpnPermissionDeferred: CompletableDeferred<Boolean>? = null
    private var notificationPermissionDeferred: CompletableDeferred<Boolean>? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        UmbrellaApplication.initialize(this)
        super.onCreate(savedInstanceState)
        serviceConnection.connect()
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, METHOD_CHANNEL)
            .setMethodCallHandler(MethodHandler(this))
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, EVENT_CHANNEL)
            .setStreamHandler(eventHandler)
    }

    override fun onDestroy() {
        runCatching { serviceConnection.disconnect() }
        super.onDestroy()
    }

    fun reconnectServiceObserver() {
        serviceConnection.reconnect()
    }

    suspend fun ensureNotificationPermissionOnly(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) return true
        val granted = ContextCompat.checkSelfPermission(
            this,
            Manifest.permission.POST_NOTIFICATIONS,
        ) == PackageManager.PERMISSION_GRANTED
        if (granted) return true

        val deferred = CompletableDeferred<Boolean>()
        notificationPermissionDeferred = deferred
        withContext(Dispatchers.Main) {
            ActivityCompat.requestPermissions(
                this@MainActivity,
                arrayOf(Manifest.permission.POST_NOTIFICATIONS),
                REQ_NOTIFICATION_PERMISSION,
            )
        }
        return withTimeoutOrNull(30_000L) { deferred.await() } ?: false
    }

    suspend fun ensureVpnAndNotificationPermissions(): Boolean {
        ensureNotificationPermissionOnly()
        val prepareIntent = VpnService.prepare(this) ?: return true

        val deferred = CompletableDeferred<Boolean>()
        vpnPermissionDeferred = deferred
        withContext(Dispatchers.Main) {
            @Suppress("DEPRECATION")
            startActivityForResult(prepareIntent, REQ_VPN_PERMISSION)
        }
        return withTimeoutOrNull(45_000L) { deferred.await() } ?: false
    }

    @Suppress("DEPRECATION")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == REQ_VPN_PERMISSION) {
            vpnPermissionDeferred?.complete(resultCode == RESULT_OK)
            vpnPermissionDeferred = null
        }
    }

    @SuppressLint("MissingSuperCall")
    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == REQ_NOTIFICATION_PERMISSION) {
            val granted = grantResults.firstOrNull() == PackageManager.PERMISSION_GRANTED
            notificationPermissionDeferred?.complete(granted)
            notificationPermissionDeferred = null
        }
    }

    override fun onServiceStatusChanged(status: Status) {
        eventHandler.onServiceStatusChanged(status)
    }

    override fun onServiceAlert(type: Alert, message: String?) {
        Log.w(TAG, "Service alert $type: $message")
        eventHandler.onServiceAlert(type, message)
    }

    override fun onServiceWriteLog(message: String?) {
        eventHandler.onServiceWriteLog(message)
    }

    override fun onServiceResetLogs(messages: MutableList<String>) {
        eventHandler.onServiceResetLogs(messages)
    }
}
