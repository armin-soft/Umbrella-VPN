package ir.umbrella.vpn

import android.Manifest
import android.annotation.SuppressLint
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.net.Uri
import android.net.VpnService
import android.os.Build
import android.os.Bundle
import android.provider.DocumentsContract
import android.provider.Settings as AndroidSettings
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
        private const val REQ_STORAGE_TREE_ACCESS = 2004
        private const val REQ_ALL_FILES_ACCESS = 2005
        private const val REQ_LEGACY_STORAGE_ACCESS = 2006
        private const val REQ_MEDIA_ACCESS = 2007

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
    private var lastKnownStorageAccess: Boolean? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        UmbrellaApplication.initialize(this)
        super.onCreate(savedInstanceState)
        lastKnownStorageAccess = UmbrellaSecurityScanner.hasStorageScanAccess(this)
        ir.umbrella.vpn.bg.DefaultNetworkMonitor.onNetworkStateChanged = { online, fp ->
            eventHandler.onNetworkStateChanged(online, fp)
        }
        serviceConnection.connect()
    }

    override fun onResume() {
        super.onResume()
        val hasAccess = UmbrellaSecurityScanner.hasStorageScanAccess(this)
        val prev = lastKnownStorageAccess
        lastKnownStorageAccess = hasAccess
        if (prev != null && prev != hasAccess) {
            UmbrellaSecurityScanner.invalidateAllCleanCache()
            if (hasAccess) {
                startSecurityFileWatcher()
            }
            eventHandler.onSecurityFileEvent("storage_access:$hasAccess")
        }
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
        UmbrellaSecurityScanner.stopFileObservers()
        val appCtx = applicationContext
        runCatching {
            UmbrellaSecurityScanner.startFileObservers {
                ir.umbrella.vpn.bg.UmbrellaBackgroundMonitor.triggerDebouncedQuickScan(appCtx)
            }
        }
        unregisterSmsReceiver()
        runCatching { serviceConnection.disconnect() }
        super.onDestroy()
    }

    fun startSecurityFileWatcher(): Boolean {
        val appCtx = applicationContext
        return UmbrellaSecurityScanner.startFileObservers { path ->
            eventHandler.onSecurityFileEvent(path)
            ir.umbrella.vpn.bg.UmbrellaBackgroundMonitor.triggerDebouncedQuickScan(appCtx)
        }
    }

    fun stopSecurityFileWatcher(): Boolean {
        UmbrellaSecurityScanner.stopFileObservers()
        return true
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

    fun launchAllFilesAccessSettings(): Boolean {
        if (UmbrellaSecurityScanner.hasStorageScanAccess(this)) return true
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            !UmbrellaSecurityScanner.hasMediaScanAccess(this)
        ) {
            ActivityCompat.requestPermissions(
                this,
                arrayOf(
                    Manifest.permission.READ_MEDIA_IMAGES,
                    Manifest.permission.READ_MEDIA_VIDEO,
                    Manifest.permission.READ_MEDIA_AUDIO,
                ),
                REQ_MEDIA_ACCESS,
            )
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            val appIntent = Intent(
                AndroidSettings.ACTION_MANAGE_APP_ALL_FILES_ACCESS_PERMISSION,
                Uri.fromParts("package", packageName, null),
            )
            val openedApp = runCatching {
                @Suppress("DEPRECATION")
                startActivityForResult(appIntent, REQ_ALL_FILES_ACCESS)
                true
            }.getOrDefault(false)
            if (openedApp) return true

            val allIntent = Intent(AndroidSettings.ACTION_MANAGE_ALL_FILES_ACCESS_PERMISSION)
            val openedAll = runCatching {
                @Suppress("DEPRECATION")
                startActivityForResult(allIntent, REQ_ALL_FILES_ACCESS)
                true
            }.getOrDefault(false)
            if (openedAll) return true

            return launchStorageTreePicker()
        }
        ActivityCompat.requestPermissions(
            this,
            arrayOf(
                Manifest.permission.READ_EXTERNAL_STORAGE,
                Manifest.permission.WRITE_EXTERNAL_STORAGE,
            ),
            REQ_LEGACY_STORAGE_ACCESS,
        )
        return true
    }

    fun launchStorageTreePicker(): Boolean {
        return runCatching {
            val intent = Intent(Intent.ACTION_OPEN_DOCUMENT_TREE).apply {
                addFlags(
                    Intent.FLAG_GRANT_READ_URI_PERMISSION or
                        Intent.FLAG_GRANT_WRITE_URI_PERMISSION or
                        Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION or
                        Intent.FLAG_GRANT_PREFIX_URI_PERMISSION,
                )
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    putExtra(
                        DocumentsContract.EXTRA_INITIAL_URI,
                        Uri.parse("content://com.android.externalstorage.documents/document/primary%3ADownload"),
                    )
                }
            }
            @Suppress("DEPRECATION")
            startActivityForResult(intent, REQ_STORAGE_TREE_ACCESS)
            true
        }.getOrDefault(false)
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
            REQ_STORAGE_TREE_ACCESS -> {
                if (resultCode == RESULT_OK) {
                    val treeUri = data?.data
                    if (treeUri != null) {
                        UmbrellaSecurityScanner.persistSafTreeUri(
                            this,
                            treeUri,
                            data.flags,
                        )
                        eventHandler.onSecurityFileEvent(treeUri.toString())
                    }
                }
            }
            REQ_ALL_FILES_ACCESS -> {
                val hasAccess = UmbrellaSecurityScanner.hasStorageScanAccess(this)
                lastKnownStorageAccess = hasAccess
                UmbrellaSecurityScanner.invalidateAllCleanCache()
                if (hasAccess) {
                    startSecurityFileWatcher()
                    eventHandler.onSecurityFileEvent("all_files_access")
                }
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
        when (requestCode) {
            REQ_NOTIFICATION_PERMISSION -> {
                val granted = grantResults.firstOrNull() == PackageManager.PERMISSION_GRANTED
                notificationPermissionDeferred?.complete(granted)
                notificationPermissionDeferred = null
            }
            REQ_LEGACY_STORAGE_ACCESS,
            REQ_MEDIA_ACCESS, -> {
                val hasAccess = UmbrellaSecurityScanner.hasStorageScanAccess(this) ||
                    UmbrellaSecurityScanner.hasMediaScanAccess(this)
                lastKnownStorageAccess = UmbrellaSecurityScanner.hasStorageScanAccess(this)
                UmbrellaSecurityScanner.invalidateAllCleanCache()
                if (hasAccess) {
                    startSecurityFileWatcher()
                    eventHandler.onSecurityFileEvent("legacy_storage_access")
                }
            }
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
