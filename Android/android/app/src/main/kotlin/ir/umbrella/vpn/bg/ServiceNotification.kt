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
import android.os.Build
import android.util.Log
import androidx.core.app.NotificationCompat
import androidx.core.app.ServiceCompat
import androidx.core.content.ContextCompat
import com.hiddify.core.api.v2.hcommon.Empty
import com.hiddify.core.api.v2.hcore.CoreClient
import com.hiddify.core.api.v2.hcore.SystemInfo
import com.hiddify.core.libbox.Libbox
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
        private const val CHANNEL_ID = "umbrella_service"

        val pendingFlags: Int = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        } else {
            PendingIntent.FLAG_UPDATE_CURRENT
        }
    }

    private val scope = CoroutineScope(Dispatchers.IO)
    private var pollJob: Job? = null
    private var receiverRegistered = false
    private var lastTitle: String = ""
    private var lastText: String = ""

    private val modeLabel: String
        get() = if (service is VPNService) {
            service.getString(R.string.mode_vpn)
        } else {
            service.getString(R.string.mode_proxy)
        }

    fun show(profileName: String, statusTextRes: Int) {
        show(profileName, service.getString(statusTextRes))
    }

    fun show(profileName: String, contentText: String) {
        if (!receiverRegistered) {
            ContextCompat.registerReceiver(
                service,
                this,
                IntentFilter(Action.SERVICE_CLOSE),
                ContextCompat.RECEIVER_NOT_EXPORTED,
            )
            receiverRegistered = true
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            UmbrellaApplication.notification.createNotificationChannel(
                NotificationChannel(
                    CHANNEL_ID,
                    service.getString(R.string.service_channel_name),
                    NotificationManager.IMPORTANCE_LOW,
                ),
            )
        }
        val title = profileName.ifBlank { service.getString(R.string.app_name) }
        render(title, contentText, modeLabel)
    }

    private fun render(title: String, contentText: String, subText: String) {
        if (title == lastTitle && contentText == lastText) return
        lastTitle = title
        lastText = contentText

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

        val notification = NotificationCompat.Builder(service, CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_stat_umbrella)
            .setContentTitle(title)
            .setContentText(contentText)
            .setSubText(subText)
            .setOngoing(true)
            .setShowWhen(false)
            .setOnlyAlertOnce(true)
            .setCategory(NotificationCompat.CATEGORY_SERVICE)
            .setContentIntent(openIntent)
            .addAction(0, service.getString(R.string.stop), stopIntent)
            .build()

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
        val showSpeed = Settings.dynamicNotification
        val intervalMs = if (showSpeed) 1500L else 4000L
        pollJob = scope.launch {
            var coreClient: CoreClient? = null
            var previous: SystemInfo? = null
            while (isActive) {
                try {
                    val client = coreClient
                        ?: GrpcClientProvider.coreGrpcClient(Settings.grpcServicePort)
                            .create(CoreClient::class)
                            .also { coreClient = it }
                    val info = client.GetSystemInfo().execute(Empty())
                    if (!isActive) break
                    val profile = info.current_profile.ifBlank { Settings.activeProfileName }
                    val outbound = info.current_outbound.ifBlank {
                        service.getString(R.string.status_started)
                    }
                    val text = if (showSpeed && previous != null) {
                        val up = Libbox.formatBytes((info.uplink_total - previous.uplink_total).coerceAtLeast(0))
                        val down = Libbox.formatBytes((info.downlink_total - previous.downlink_total).coerceAtLeast(0))
                        "$outbound  ·  ↑ $up/s  ↓ $down/s"
                    } else {
                        outbound
                    }
                    previous = info
                    render(profile, text, modeLabel)
                } catch (e: CancellationException) {
                    throw e
                } catch (e: Exception) {
                    Log.d(TAG, "SystemInfo polling waiting: ${e.message}")
                    previous = null
                    coreClient = null
                }
                delay(intervalMs)
            }
        }
    }

    fun close() {
        pollJob?.cancel()
        pollJob = null
        lastTitle = ""
        lastText = ""
        runCatching {
            ServiceCompat.stopForeground(service, ServiceCompat.STOP_FOREGROUND_REMOVE)
        }
        runCatching {
            UmbrellaApplication.notification.cancel(NOTIFICATION_ID)
        }
        if (receiverRegistered) {
            runCatching { service.unregisterReceiver(this) }
            receiverRegistered = false
        }
    }

    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action == Action.SERVICE_CLOSE) {
            context.sendBroadcast(Intent(Action.SERVICE_CLOSE).setPackage(context.packageName))
        }
    }
}
