package ir.umbrella.vpn

import android.Manifest
import android.annotation.SuppressLint
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.net.VpnService
import android.os.Build
import android.os.Bundle
import android.util.Log
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import com.google.android.gms.auth.api.phone.SmsRetriever
import com.google.android.gms.common.api.CommonStatusCodes
import com.google.android.gms.common.api.Status as GmsStatus
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
        private const val REQ_SMS_USER_CONSENT = 2003

        fun extractVerificationCode(message: String?): String {
            if (message.isNullOrBlank()) return ""
            val normalized = buildString(message.length) {
                for (ch in message) {
                    when (ch) {
                        in '۰'..'۹' -> append(('0'.code + (ch.code - '۰'.code)).toChar())
                        in '٠'..'٩' -> append(('0'.code + (ch.code - '٠'.code)).toChar())
                        else -> append(ch)
                    }
                }
            }
            val sixDigit = Regex("""(?<!\d)\d{6}(?!\d)""").find(normalized)?.value
            if (!sixDigit.isNullOrEmpty()) return sixDigit
            return Regex("""(?<!\d)\d{4,8}(?!\d)""").find(normalized)?.value ?: ""
        }
    }

    private val eventHandler = EventHandler()
    private val serviceConnection by lazy { ServiceConnection(this, this) }
    private var vpnPermissionDeferred: CompletableDeferred<Boolean>? = null
    private var notificationPermissionDeferred: CompletableDeferred<Boolean>? = null
    private var smsReceiver: BroadcastReceiver? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        UmbrellaApplication.initialize(this)
        super.onCreate(savedInstanceState)
        ir.umbrella.vpn.bg.DefaultNetworkMonitor.onNetworkStateChanged = { online, fp ->
            eventHandler.onNetworkStateChanged(online, fp)
        }
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
        ir.umbrella.vpn.bg.DefaultNetworkMonitor.onNetworkStateChanged = null
        unregisterSmsReceiver()
        runCatching { serviceConnection.disconnect() }
        super.onDestroy()
    }

    fun reconnectServiceObserver(force: Boolean = true) {
        if (force || !serviceConnection.isConnected) {
            serviceConnection.reconnect()
        }
    }

    suspend fun startSmsUserConsent(): Boolean {
        val deferred = CompletableDeferred<Boolean>()
        withContext(Dispatchers.Main) {
            runCatching {
                registerSmsReceiver()
                SmsRetriever.getClient(this@MainActivity)
                    .startSmsUserConsent(null)
                    .addOnSuccessListener {
                        if (!deferred.isCompleted) deferred.complete(true)
                    }
                    .addOnFailureListener { e ->
                        Log.w(TAG, "SMS User Consent unavailable: ${e.message}")
                        unregisterSmsReceiver()
                        if (!deferred.isCompleted) deferred.complete(false)
                    }
            }.onFailure { e ->
                Log.w(TAG, "Failed to start SMS User Consent: ${e.message}")
                unregisterSmsReceiver()
                if (!deferred.isCompleted) deferred.complete(false)
            }
        }
        return withTimeoutOrNull(5_000L) { deferred.await() } ?: false
    }

    fun stopSmsUserConsent() {
        runOnUiThread {
            unregisterSmsReceiver()
        }
    }

    private fun registerSmsReceiver() {
        unregisterSmsReceiver()
        val receiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context?, intent: Intent?) {
                if (intent?.action != SmsRetriever.SMS_RETRIEVED_ACTION) return
                val extras = intent.extras ?: return
                val status: GmsStatus? = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                    extras.getParcelable(SmsRetriever.EXTRA_STATUS, GmsStatus::class.java)
                } else {
                    @Suppress("DEPRECATION")
                    extras.getParcelable(SmsRetriever.EXTRA_STATUS)
                }
                if (status?.statusCode == CommonStatusCodes.TIMEOUT) {
                    unregisterSmsReceiver()
                    return
                }
                if (status?.statusCode != CommonStatusCodes.SUCCESS) return

                val directMessage = extras.getString(SmsRetriever.EXTRA_SMS_MESSAGE)
                if (!directMessage.isNullOrBlank()) {
                    val code = extractVerificationCode(directMessage)
                    if (code.isNotEmpty()) {
                        eventHandler.onSmsCodeReceived(code, directMessage)
                    }
                    unregisterSmsReceiver()
                    return
                }

                val consentIntent: Intent? = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                    extras.getParcelable(SmsRetriever.EXTRA_CONSENT_INTENT, Intent::class.java)
                } else {
                    @Suppress("DEPRECATION")
                    extras.getParcelable(SmsRetriever.EXTRA_CONSENT_INTENT)
                }
                if (consentIntent != null) {
                    runCatching {
                        @Suppress("DEPRECATION")
                        startActivityForResult(consentIntent, REQ_SMS_USER_CONSENT)
                    }.onFailure { e ->
                        Log.w(TAG, "Unable to launch SMS consent prompt: ${e.message}")
                    }
                }
            }
        }
        ContextCompat.registerReceiver(
            this,
            receiver,
            IntentFilter(SmsRetriever.SMS_RETRIEVED_ACTION),
            SmsRetriever.SEND_PERMISSION,
            null,
            ContextCompat.RECEIVER_EXPORTED,
        )
        smsReceiver = receiver
    }

    private fun unregisterSmsReceiver() {
        val current = smsReceiver ?: return
        smsReceiver = null
        runCatching { unregisterReceiver(current) }
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
        when (requestCode) {
            REQ_VPN_PERMISSION -> {
                vpnPermissionDeferred?.complete(resultCode == RESULT_OK)
                vpnPermissionDeferred = null
            }
            REQ_SMS_USER_CONSENT -> {
                if (resultCode == RESULT_OK && data != null) {
                    val message = data.getStringExtra(SmsRetriever.EXTRA_SMS_MESSAGE) ?: ""
                    val code = extractVerificationCode(message)
                    if (code.isNotEmpty()) {
                        eventHandler.onSmsCodeReceived(code, message)
                    }
                }
                unregisterSmsReceiver()
            }
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
