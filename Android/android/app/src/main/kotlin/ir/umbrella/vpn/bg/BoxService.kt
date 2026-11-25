package ir.umbrella.vpn.bg

import android.app.Service
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.Build
import android.os.IBinder
import android.os.ParcelFileDescriptor
import android.os.PowerManager
import android.util.Log
import androidx.annotation.RequiresApi
import androidx.core.content.ContextCompat
import androidx.lifecycle.MutableLiveData
import com.hiddify.core.api.v2.hcore.ChangeHiddifySettingsRequest
import com.hiddify.core.api.v2.hcore.CoreClient
import com.hiddify.core.api.v2.hcore.CoreStates
import com.hiddify.core.api.v2.hcore.MessageType
import com.hiddify.core.api.v2.hcore.StartRequest
import com.hiddify.core.libbox.Notification
import com.hiddify.core.libbox.PlatformInterface
import com.hiddify.core.mobile.CoreStoppedListener
import com.hiddify.core.mobile.Mobile
import com.hiddify.core.mobile.SetupOptions
import ir.umbrella.vpn.R
import ir.umbrella.vpn.Settings
import ir.umbrella.vpn.UmbrellaApplication
import ir.umbrella.vpn.constant.Action
import ir.umbrella.vpn.constant.Alert
import ir.umbrella.vpn.constant.Status
import ir.umbrella.vpn.utils.DeviceMemory
import ir.umbrella.vpn.utils.GrpcClientProvider
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.DelicateCoroutinesApi
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.GlobalScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.NonCancellable
import kotlinx.coroutines.cancelAndJoin
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.delay
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withContext

class BoxService(
    private val service: Service,
    private val platformInterface: PlatformInterface,
) {
    companion object {
        private const val TAG = "UmbrellaBoxService"
        const val EXTRA_START_CORE = "startCore"

        val status = MutableLiveData(Status.Stopped)

        @Volatile
        var activePlatformInterface: PlatformInterface? = null
            private set

        @Volatile
        var lastStartError: String? = null

        private val mobileLock = Any()

        @Volatile
        private var activeUtilityMode = false

        @Volatile
        private var utilitySetupDone = false

        private object IdlePlatformInterface : PlatformInterfaceWrapper

        fun ensureUtilityCore(): Int {
            synchronized(mobileLock) {
                when (status.value ?: Status.Stopped) {
                    Status.Started, Status.Starting -> return Settings.grpcServicePort
                    Status.Stopping -> error("VPN service is stopping")
                    Status.Stopped -> {}
                }
                if (!utilitySetupDone) {
                    val options = SetupOptions().apply {
                        basePath = Settings.baseDir
                        workingDir = Settings.workingDir
                        tempDir = Settings.tempDir
                        listen = "127.0.0.1:${Settings.grpcUtilityPort}"
                        secret = ""
                        debug = Settings.debugMode
                        mode = Settings.UTILITY_GRPC_MODE
                        fixAndroidStack = Bugs.fixAndroidStack
                        DeviceMemory.applyTo(this)
                    }
                    Mobile.setup(options, IdlePlatformInterface)
                    utilitySetupDone = true
                    activeUtilityMode = true
                }
                return Settings.grpcUtilityPort
            }
        }

        fun shutdownUtilityCore() {
            synchronized(mobileLock) {
                if (!utilitySetupDone && !activeUtilityMode) return
                runCatching { Mobile.close(Settings.UTILITY_GRPC_MODE) }
                    .onFailure { Log.w(TAG, "shutdownUtilityCore close(3)", it) }
                utilitySetupDone = false
                activeUtilityMode = false
            }
        }

        fun start(context: Context, startCore: Boolean = true) {
            val intent = Settings.serviceIntent(context).apply {
                putExtra(EXTRA_START_CORE, startCore)
            }
            ContextCompat.startForegroundService(context, intent)
        }

        fun stop(context: Context) {
            context.sendBroadcast(Intent(Action.SERVICE_CLOSE).setPackage(context.packageName))
        }
    }

    private data class StartFailure(val alert: Alert, val message: String?)

    var fileDescriptor: ParcelFileDescriptor? = null
    private val notification = ServiceNotification(service)
    private val binder = ServiceBinder(status)
    private var receiverRegistered = false
    private var startJob: Job? = null
    private var startedCore = true

    private val receiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            when (intent.action) {
                Action.SERVICE_CLOSE -> stopService()
                PowerManager.ACTION_DEVICE_IDLE_MODE_CHANGED -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                        serviceUpdateIdleMode()
                    }
                }
            }
        }
    }

    private val coreStoppedListener = object : CoreStoppedListener {
        @OptIn(DelicateCoroutinesApi::class)
        override fun onCoreStopped(messageType: Int, message: String?) {
            GlobalScope.launch(Dispatchers.Main) {
                coreStopped(message)
            }
        }
    }

    private suspend fun startService(startCore: Boolean): StartFailure? = coroutineScope {
        try {
            lastStartError = null
            withContext(Dispatchers.Main) {
                notification.showStarting()
            }

            DefaultNetworkMonitor.start()
            coroutineContext.ensureActive()

            try {
                synchronized(mobileLock) {
                    shutdownUtilityCore()
                    activePlatformInterface = platformInterface
                    val options = SetupOptions().apply {
                        basePath = Settings.baseDir
                        workingDir = Settings.workingDir
                        tempDir = Settings.tempDir
                        listen = "127.0.0.1:${Settings.grpcServicePort}"
                        secret = ""
                        debug = Settings.debugMode
                        mode = Settings.SERVICE_GRPC_MODE
                        fixAndroidStack = Bugs.fixAndroidStack
                        DeviceMemory.applyTo(this)
                    }
                    Mobile.setup(options, platformInterface)
                    Mobile.setCoreStoppedListener(coreStoppedListener)
                }
            } catch (e: Exception) {
                if (e is CancellationException) throw e
                Log.e(TAG, "Mobile.setup failed", e)
                return@coroutineScope StartFailure(Alert.CreateService, e.message ?: e.toString())
            }

            coroutineContext.ensureActive()

            if (startCore) {
                val settingsJson = Settings.activeSettingsJson
                val configPath = Settings.activeConfigPath
                if (configPath.isNotBlank()) {
                    val client = GrpcClientProvider.coreGrpcClient(
                        port = Settings.grpcServicePort,
                        callTimeoutSeconds = 45L,
                    ).create(CoreClient::class)
                    if (settingsJson.isNotBlank()) {
                        val settingsResp = client.ChangeHiddifySettings().execute(
                            ChangeHiddifySettingsRequest(hiddify_settings_json = settingsJson),
                        )
                        if (settingsResp.message_type != MessageType.EMPTY &&
                            settingsResp.message.isNotBlank()
                        ) {
                            return@coroutineScope StartFailure(
                                Alert.StartService,
                                settingsResp.message,
                            )
                        }
                    }
                    coroutineContext.ensureActive()
                    val startResp = client.StartService().execute(
                        StartRequest(
                            config_path = configPath,
                            config_name = Settings.activeProfileName,
                            enable_raw_config = false,
                        ),
                    )
                    if (startResp.core_state == CoreStates.STOPPED ||
                        (startResp.message_type != MessageType.EMPTY &&
                            startResp.message_type != MessageType.ALREADY_STARTED)
                    ) {
                        val reason = startResp.message.ifBlank { startResp.message_type.name }
                        return@coroutineScope StartFailure(Alert.StartService, reason)
                    }
                } else {
                    Mobile.start("", "")
                }
                coroutineContext.ensureActive()
            }

            withContext(Dispatchers.Main) {
                coroutineContext.ensureActive()
                status.value = Status.Started
            }
            notification.startPolling()
            null
        } catch (e: Exception) {
            if (e is CancellationException) throw e
            Log.e(TAG, "startService failed", e)
            StartFailure(Alert.StartService, e.message ?: e.toString())
        }
    }

    fun serviceReload() {
        runBlocking {
            notification.close()
            status.postValue(Status.Starting)
            fileDescriptor?.let {
                runCatching { it.close() }
                fileDescriptor = null
            }
            runCatching { Mobile.stop() }
            startService(startedCore)?.let { teardown(it) }
        }
    }

    @RequiresApi(Build.VERSION_CODES.M)
    private fun serviceUpdateIdleMode() {
        if (!UmbrellaApplication.powerManager.isDeviceIdleMode) {
            runCatching { Mobile.wake() }
        }
    }

    @OptIn(DelicateCoroutinesApi::class)
    private fun coreStopped(message: String?) {
        // An in-flight startService() handles its own failure and teardown via StartService().
        // Only tear down asynchronously when the core drops after startup has already succeeded.
        if (status.value != Status.Started) return
        Log.w(TAG, "Core stopped unexpectedly: $message")
        status.value = Status.Stopping
        notification.close()
        GlobalScope.launch(Dispatchers.IO) {
            teardown(StartFailure(Alert.StartService, message))
        }
    }

    @OptIn(DelicateCoroutinesApi::class)
    private fun stopService() {
        if (status.value == Status.Stopped || status.value == Status.Stopping) return
        status.value = Status.Stopping
        notification.close()
        val runningStart = startJob
        GlobalScope.launch(Dispatchers.IO) {
            // Interrupt an in-progress StartService() call inside Go before joining startJob.
            runCatching { Mobile.stop() }
            runningStart?.cancelAndJoin()
            teardown(null)
        }
    }

    private suspend fun teardown(failure: StartFailure?) = withContext(NonCancellable) {
        if (failure != null) {
            lastStartError = failure.message ?: failure.alert.name
        }
        Settings.startedByUser = false
        withContext(Dispatchers.Main) {
            if (status.value == Status.Starting || status.value == Status.Started) {
                status.value = Status.Stopping
            }
            if (receiverRegistered) {
                runCatching { service.unregisterReceiver(receiver) }
                receiverRegistered = false
            }
            notification.close()
        }
        fileDescriptor?.let {
            runCatching { it.close() }
            fileDescriptor = null
        }
        synchronized(mobileLock) {
            if (activePlatformInterface === platformInterface) {
                activePlatformInterface = null
            }
            Mobile.setCoreStoppedListener(null)
            for (mode in linkedSetOf(Settings.SERVICE_GRPC_MODE, 2L, 4L)) {
                runCatching { Mobile.close(mode) }
                    .onFailure { Log.w(TAG, "closing core mode $mode", it) }
            }
        }
        DefaultNetworkMonitor.stop()
        withContext(Dispatchers.Main) {
            if (failure != null) {
                binder.broadcast { callback ->
                    callback.onServiceAlert(failure.alert.ordinal, failure.message)
                }
            }
            status.value = Status.Stopped
            notification.close()
            service.stopSelf()
        }
    }

    @OptIn(DelicateCoroutinesApi::class)
    internal fun onStartCommand(intent: Intent?): Int {
        val startCore = intent?.getBooleanExtra(EXTRA_START_CORE, true) ?: true
        if (status.value == Status.Started) {
            return Service.START_NOT_STICKY
        }
        try {
            notification.showStarting()
        } catch (e: Exception) {
            Log.e(TAG, "cannot go to foreground", e)
        }
        if (status.value == Status.Starting) {
            return Service.START_NOT_STICKY
        }
        if (status.value == Status.Stopping) {
            GlobalScope.launch(Dispatchers.IO) {
                var i = 0
                while (status.value == Status.Stopping && i < 50) {
                    delay(200)
                    i++
                }
                if (status.value == Status.Stopped) {
                    withContext(Dispatchers.Main) {
                        start(service, startCore)
                    }
                }
            }
            return Service.START_NOT_STICKY
        }

        lastStartError = null
        status.value = Status.Starting
        if (!receiverRegistered) {
            ContextCompat.registerReceiver(
                service,
                receiver,
                IntentFilter().apply {
                    addAction(Action.SERVICE_CLOSE)
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                        addAction(PowerManager.ACTION_DEVICE_IDLE_MODE_CHANGED)
                    }
                },
                ContextCompat.RECEIVER_NOT_EXPORTED,
            )
            receiverRegistered = true
        }

        startJob = GlobalScope.launch(Dispatchers.IO) {
            Settings.startedByUser = true
            startedCore = startCore
            startService(startCore)?.let { teardown(it) }
        }
        return Service.START_NOT_STICKY
    }

    fun onBind(intent: Intent): IBinder = binder

    fun onDestroy() {
        binder.close()
    }

    fun onRevoke() {
        stopService()
    }

    fun sendNotification(notification: Notification) {
    }

    fun cancelNotification(identifier: String, typeID: Int) {
    }

    fun writeDebugMessage(message: String?) {
        if (message.isNullOrBlank()) return
        Log.d(TAG, message)
        binder.appendLog(message)
    }
}
