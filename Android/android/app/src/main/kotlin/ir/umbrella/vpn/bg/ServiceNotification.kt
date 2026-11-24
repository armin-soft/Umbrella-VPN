package ir.umbrella.vpn.bg

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.ServiceInfo
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.os.Build
import android.util.Log
import androidx.core.app.NotificationCompat
import androidx.core.app.ServiceCompat
import androidx.core.content.ContextCompat
import com.hiddify.core.api.v2.hcommon.Empty
import com.hiddify.core.api.v2.hcore.CoreClient
import ir.umbrella.vpn.MainActivity
import ir.umbrella.vpn.R
import ir.umbrella.vpn.Settings
import ir.umbrella.vpn.UmbrellaApplication
import ir.umbrella.vpn.constant.Action
import ir.umbrella.vpn.utils.GrpcClientProvider
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch

class ServiceNotification(
    private val service: Service,
) : BroadcastReceiver() {
    companion object {
        private const val TAG = "UmbrellaNotification"
        private const val NOTIFICATION_ID = 1
        private const val BALLOON_NOTIFICATION_ID = 2
        private const val CHANNEL_ID = "umbrella_service_v2"
        private const val BALLOON_CHANNEL_ID = "umbrella_alerts_v2"
        private const val BRAND_COLOR = 0xFFE11D48.toInt()
        private const val PERSIAN_DIGITS = "۰۱۲۳۴۵۶۷۸۹"

        val pendingFlags: Int = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        } else {
            PendingIntent.FLAG_UPDATE_CURRENT
        }

        @Volatile
        private var activeInstance: ServiceNotification? = null

        @Volatile
        private var desiredConnectedTitle: String = ""

        @Volatile
        private var desiredConnectedText: String = ""

        @Volatile
        private var hasAlertedThisSession: Boolean = false

        fun sanitizePersian(raw: String): String {
            if (raw.isEmpty()) return ""
            val sb = StringBuilder(raw.length)
            for (ch in raw) {
                when (ch) {
                    in '0'..'9' -> sb.append(PERSIAN_DIGITS[ch - '0'])
                    in '\u0660'..'\u0669' -> sb.append(PERSIAN_DIGITS[ch - '\u0660'])
                    '\u200C' -> sb.append(' ')
                    else -> sb.append(ch)
                }
            }
            return sb.toString().trim()
        }

        fun resetSessionState() {
            desiredConnectedTitle = ""
            desiredConnectedText = ""
            hasAlertedThisSession = false
        }

        fun updateConnectedNotification(
            title: String,
            body: String,
            alert: Boolean,
        ) {
            val cleanTitle = sanitizePersian(title)
            val cleanBody = sanitizePersian(body)
            if (cleanTitle.isNotEmpty()) {
                desiredConnectedTitle = cleanTitle
            }
            if (cleanBody.isNotEmpty()) {
                desiredConnectedText = cleanBody
            }
            val instance = activeInstance ?: return
            instance.renderConnected(alert = alert)
        }

        fun showStandaloneBalloon(
            context: Context,
            title: String,
            body: String,
            warning: Boolean,
        ) {
            if (!Settings.notificationsEnabled) return
            ensureAlertChannel(context)
            val cleanTitle = sanitizePersian(title)
            val cleanBody = sanitizePersian(body)
            if (cleanTitle.isEmpty()) return

            val openIntent = PendingIntent.getActivity(
                context,
                2,
                Intent(context, MainActivity::class.java).apply {
                    flags = Intent.FLAG_ACTIVITY_REORDER_TO_FRONT or Intent.FLAG_ACTIVITY_NEW_TASK
                },
                pendingFlags,
            )
            val iconRes = if (warning) R.drawable.ic_notif_failed else R.drawable.ic_notif_connected
            val largeIcon = BitmapFactory.decodeResource(context.resources, iconRes)

            val builder = NotificationCompat.Builder(context, BALLOON_CHANNEL_ID)
                .setSmallIcon(R.drawable.ic_stat_umbrella)
                .setColor(BRAND_COLOR)
                .setContentTitle(cleanTitle)
                .setContentText(cleanBody)
                .setAutoCancel(true)
                .setOnlyAlertOnce(false)
                .setSilent(true)
                .setTimeoutAfter(7000L)
                .setPriority(NotificationCompat.PRIORITY_HIGH)
                .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
                .setContentIntent(openIntent)
            if (largeIcon != null) {
                builder.setLargeIcon(largeIcon)
            }
            UmbrellaApplication.notification.notify(BALLOON_NOTIFICATION_ID, builder.build())
        }

        fun showBlockedUrlBalloon(
            context: Context,
            url: String,
            title: String,
            body: String,
        ) {
            ensureAlertChannel(context)
            val cleanTitle = sanitizePersian(title).ifEmpty { "سپر کنترل محتوای آمبرلا" }
            val cleanBody = sanitizePersian(body).ifEmpty { "دسترسی به این صفحه مسدود شد." }
            val browserIntent = Intent(Intent.ACTION_VIEW, android.net.Uri.parse(url)).apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            val openPending = PendingIntent.getActivity(
                context,
                3,
                browserIntent,
                pendingFlags,
            )
            val largeIcon = BitmapFactory.decodeResource(context.resources, R.drawable.ic_notif_failed)
            val builder = NotificationCompat.Builder(context, BALLOON_CHANNEL_ID)
                .setSmallIcon(R.drawable.ic_stat_umbrella)
                .setColor(BRAND_COLOR)
                .setContentTitle(cleanTitle)
                .setContentText(cleanBody)
                .setStyle(NotificationCompat.BigTextStyle().bigText(cleanBody))
                .setAutoCancel(true)
                .setOnlyAlertOnce(false)
                .setSilent(true)
                .setTimeoutAfter(12000L)
                .setPriority(NotificationCompat.PRIORITY_HIGH)
                .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
                .setContentIntent(openPending)
            if (largeIcon != null) {
                builder.setLargeIcon(largeIcon)
            }
            UmbrellaApplication.notification.notify(BALLOON_NOTIFICATION_ID, builder.build())
        }

        fun cancelStandaloneBalloon() {
            runCatching {
                UmbrellaApplication.notification.cancel(BALLOON_NOTIFICATION_ID)
            }
        }

        private fun ensureServiceChannel(context: Context) {
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
            val channel = NotificationChannel(
                CHANNEL_ID,
                context.getString(R.string.service_channel_name),
                NotificationManager.IMPORTANCE_HIGH,
            ).apply {
                setSound(null, null)
                enableVibration(false)
                setShowBadge(false)
            }
            UmbrellaApplication.notification.createNotificationChannel(channel)
        }

        private fun ensureAlertChannel(context: Context) {
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
            val channel = NotificationChannel(
                BALLOON_CHANNEL_ID,
                context.getString(R.string.alerts_channel_name),
                NotificationManager.IMPORTANCE_HIGH,
            ).apply {
                setSound(null, null)
                enableVibration(false)
                setShowBadge(false)
            }
            UmbrellaApplication.notification.createNotificationChannel(channel)
        }
    }

    private val scope = CoroutineScope(Dispatchers.IO)
    private var pollJob: Job? = null
    private var receiverRegistered = false
    private var lastTitle: String = ""
    private var lastText: String = ""
    private var lastLogoRes: Int = 0
    private var isConnectedState: Boolean = false
    private val bitmapCache = HashMap<Int, Bitmap?>()

    @Synchronized
    private fun logoBitmap(resId: Int): Bitmap? {
        return bitmapCache.getOrPut(resId) {
            runCatching { BitmapFactory.decodeResource(service.resources, resId) }.getOrNull()
        }
    }

    private fun registerCloseReceiverIfNeeded() {
        if (receiverRegistered) return
        ContextCompat.registerReceiver(
            service,
            this,
            IntentFilter(Action.SERVICE_CLOSE),
            ContextCompat.RECEIVER_NOT_EXPORTED,
        )
        receiverRegistered = true
    }

    fun showStarting() {
        activeInstance = this
        isConnectedState = false
        cancelStandaloneBalloon()
        registerCloseReceiverIfNeeded()
        ensureServiceChannel(service)
        render(
            title = service.getString(R.string.app_name),
            contentText = service.getString(R.string.status_starting),
            logoRes = R.drawable.ic_notif_connecting,
            alert = false,
        )
    }

    fun showConnected(alert: Boolean = false) {
        activeInstance = this
        isConnectedState = true
        cancelStandaloneBalloon()
        registerCloseReceiverIfNeeded()
        ensureServiceChannel(service)
        renderConnected(alert = alert)
    }

    fun renderConnected(alert: Boolean = false) {
        if (!isConnectedState) return
        val title = desiredConnectedTitle.ifBlank {
            service.getString(R.string.status_connected_title)
        }
        val text = desiredConnectedText.ifBlank {
            service.getString(R.string.status_started)
        }
        val shouldHeadsUp = alert && Settings.notificationsEnabled && !hasAlertedThisSession
        if (shouldHeadsUp) {
            hasAlertedThisSession = true
        }
        render(
            title = title,
            contentText = text,
            logoRes = R.drawable.ic_notif_connected,
            alert = shouldHeadsUp,
        )
    }

    @Synchronized
    private fun render(
        title: String,
        contentText: String,
        logoRes: Int,
        alert: Boolean,
    ) {
        val cleanTitle = sanitizePersian(title)
        val cleanText = sanitizePersian(contentText)
        if (!alert && cleanTitle == lastTitle && cleanText == lastText && logoRes == lastLogoRes) {
            return
        }
        lastTitle = cleanTitle
        lastText = cleanText
        lastLogoRes = logoRes

        val openIntent = PendingIntent.getActivity(
            service,
            0,
            Intent(service, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_REORDER_TO_FRONT
            },
            pendingFlags,
        )
        val stopIntent = PendingIntent.getBroadcast(
            service,
            1,
            Intent(Action.SERVICE_CLOSE).setPackage(service.packageName),
            pendingFlags,
        )

        val builder = NotificationCompat.Builder(service, CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_stat_umbrella)
            .setColor(BRAND_COLOR)
            .setContentTitle(cleanTitle)
            .setContentText(cleanText)
            .setOngoing(true)
            .setShowWhen(false)
            .setOnlyAlertOnce(!alert)
            .setSilent(!alert)
            .setPriority(if (alert) NotificationCompat.PRIORITY_HIGH else NotificationCompat.PRIORITY_DEFAULT)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setCategory(NotificationCompat.CATEGORY_SERVICE)
            .setContentIntent(openIntent)
            .addAction(0, service.getString(R.string.stop), stopIntent)

        logoBitmap(logoRes)?.let { bitmap ->
            builder.setLargeIcon(bitmap)
        }

        val notification = builder.build()

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            ServiceCompat.startForeground(
                service,
                NOTIFICATION_ID,
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE,
            )
        } else {
            ServiceCompat.startForeground(service, NOTIFICATION_ID, notification, 0)
        }
    }

    fun startPolling() {
        pollJob?.cancel()
        pollJob = scope.launch {
            var coreClient: CoreClient? = null
            while (isActive) {
                try {
                    val client = coreClient
                        ?: GrpcClientProvider.coreGrpcClient(Settings.grpcServicePort)
                            .create(CoreClient::class)
                            .also { coreClient = it }
                    client.GetSystemInfo().execute(Empty())
                    if (!isActive) break
                    renderConnected(alert = false)
                } catch (e: CancellationException) {
                    throw e
                } catch (e: Exception) {
                    Log.d(TAG, "SystemInfo polling waiting: ${e.message}")
                    coreClient = null
                }
                delay(4000L)
            }
        }
    }

    fun close() {
        if (activeInstance === this) {
            activeInstance = null
        }
        isConnectedState = false
        pollJob?.cancel()
        pollJob = null
        lastTitle = ""
        lastText = ""
        lastLogoRes = 0
        resetSessionState()
        runCatching {
            if (receiverRegistered) {
                service.unregisterReceiver(this)
                receiverRegistered = false
            }
        }
        ServiceCompat.stopForeground(service, ServiceCompat.STOP_FOREGROUND_REMOVE)
        runCatching {
            UmbrellaApplication.notification.cancel(NOTIFICATION_ID)
        }
    }

    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action == Action.SERVICE_CLOSE) {
            BoxService.stop(context)
        }
    }
}
