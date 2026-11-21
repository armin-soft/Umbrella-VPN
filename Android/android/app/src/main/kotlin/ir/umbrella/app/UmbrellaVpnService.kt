package ir.umbrella.app

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.net.ConnectivityManager
import android.net.VpnService
import android.os.Binder
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import java.io.File
import java.util.concurrent.Executors

/** Owns the Android VPN lifecycle; setup alone is not a connected VPN. */
class UmbrellaVpnService : VpnService() {
    inner class LocalBinder : Binder() {
        val service: UmbrellaVpnService get() = this@UmbrellaVpnService
    }

    private val binder = LocalBinder()
    private val worker = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())
    private lateinit var tun: UmbrellaTun
    private lateinit var platform: UmbrellaPlatform
    @Volatile private var stopping = false
    @Volatile private var ready = false

    override fun onCreate() {
        super.onCreate()
        tun = UmbrellaTun(this)
        platform = UmbrellaPlatform(this, tun, getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager)
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        // Always-on is disabled until config restoration and reconnect are implemented.
        if (intent?.action != ACTION_PREPARE || VpnService.prepare(this) != null) {
            stopSelf(startId)
            return START_NOT_STICKY
        }
        try {
            startForeground(NOTIFICATION_ID, foregroundNotification())
        } catch (_: Exception) {
            stopSelf(startId)
        }
        return START_NOT_STICKY
    }

    override fun onBind(intent: Intent): IBinder? =
        if (intent.action == SERVICE_INTERFACE) super.onBind(intent) else binder

    /** Callback is delivered on the main thread; the certificate pins the gRPC server. */
    internal fun prepareCore(port: Int, callback: (Result<ByteArray>) -> Unit) {
        worker.execute {
            val result = runCatching {
                check(!stopping && !ready) { "VPN service is not available" }
                check(VpnService.prepare(this) == null) { "VPN permission was revoked" }
                val working = File(filesDir, "core").apply { check(isDirectory || mkdirs()) }
                val temp = File(cacheDir, "core").apply { check(isDirectory || mkdirs()) }
                val certificate = UmbrellaCoreRuntime.setup(filesDir, working, temp, port, platform)
                check(!stopping) { "VPN service is stopping" }
                ready = true
                certificate
            }
            if (result.isFailure) cleanup()
            main.post { callback(result) }
        }
    }

    internal fun stopCore(callback: (Boolean) -> Unit) {
        stopping = true
        worker.execute {
            val ok = cleanup()
            main.post {
                callback(ok)
                stopSelf()
            }
        }
    }

    private fun cleanup(): Boolean {
        ready = false
        // Attempt all cleanup even when an earlier step fails.
        val engine = runCatching { UmbrellaCoreRuntime.close() }.isSuccess
        val monitor = runCatching { platform.close() }.isSuccess
        val tunnel = runCatching { tun.close() }.isSuccess
        return engine && monitor && tunnel
    }

    override fun onRevoke() {
        stopping = true
        worker.execute { cleanup(); main.post { stopSelf() } }
        super.onRevoke()
    }

    override fun onDestroy() {
        stopping = true
        worker.execute { cleanup() }
        worker.shutdown()
        super.onDestroy()
    }

    private fun foregroundNotification(): Notification {
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            manager.createNotificationChannel(NotificationChannel(CHANNEL, "Umbrella VPN", NotificationManager.IMPORTANCE_LOW))
        }
        val open = PendingIntent.getActivity(this, 0, Intent(this, MainActivity::class.java),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) Notification.Builder(this, CHANNEL) else Notification.Builder(this)
        return builder.setSmallIcon(android.R.drawable.stat_sys_warning)
            .setContentTitle("Umbrella VPN")
            .setContentText("سرویس VPN در حال آماده‌سازی است")
            .setContentIntent(open).setOngoing(true).build()
    }

    companion object {
        internal const val ACTION_PREPARE = "ir.umbrella.app.PREPARE_VPN"
        private const val CHANNEL = "umbrella_vpn"
        private const val NOTIFICATION_ID = 17078
    }
}
