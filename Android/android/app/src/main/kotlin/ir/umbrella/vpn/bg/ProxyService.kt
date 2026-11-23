package ir.umbrella.vpn.bg

import android.app.Service
import android.content.Intent
import com.hiddify.core.libbox.Notification
import ir.umbrella.vpn.UmbrellaApplication

class ProxyService : Service(), PlatformInterfaceWrapper {
    private val service = BoxService(this, this)

    override fun onCreate() {
        UmbrellaApplication.initialize(this)
        super.onCreate()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int =
        service.onStartCommand(intent)

    override fun onBind(intent: Intent) = service.onBind(intent)

    override fun onDestroy() {
        service.onDestroy()
        super.onDestroy()
    }

    override fun sendNotification(notification: Notification) =
        service.sendNotification(notification)

    override fun cancelNotification(identifier: String, typeID: Int) =
        service.cancelNotification(identifier, typeID)
}
