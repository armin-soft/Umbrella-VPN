package ir.umbrella.vpn

import android.app.Application
import android.app.NotificationManager
import android.content.Context
import android.net.ConnectivityManager
import android.os.PowerManager
import androidx.core.content.getSystemService
import go.Seq

class UmbrellaApplication : Application() {
    override fun attachBaseContext(base: Context?) {
        super.attachBaseContext(base)
        application = this
    }

    override fun onCreate() {
        super.onCreate()
        initialize(this)
    }

    companion object {
        lateinit var application: Application
            private set

        @Volatile
        private var initialized = false

        @Synchronized
        fun initialize(context: Context) {
            if (initialized) return
            val app = context.applicationContext as Application
            application = app
            AppCrashRecorder.install(app)
            Seq.setContext(app)
            initialized = true
            runCatching { ir.umbrella.vpn.bg.UmbrellaBackgroundMonitor.initialize(app) }
        }

        val notification: NotificationManager
            get() = application.getSystemService<NotificationManager>()!!

        val connectivity: ConnectivityManager
            get() = application.getSystemService<ConnectivityManager>()!!

        val packageManager
            get() = application.packageManager

        val powerManager: PowerManager
            get() = application.getSystemService<PowerManager>()!!
    }
}
