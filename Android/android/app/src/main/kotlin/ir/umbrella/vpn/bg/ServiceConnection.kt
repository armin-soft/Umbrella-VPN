package ir.umbrella.vpn.bg

import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.os.IBinder
import android.os.RemoteException
import android.util.Log
import ir.umbrella.vpn.IService
import ir.umbrella.vpn.IServiceCallback
import ir.umbrella.vpn.Settings
import ir.umbrella.vpn.constant.Action
import ir.umbrella.vpn.constant.Alert
import ir.umbrella.vpn.constant.Status
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.GlobalScope
import kotlinx.coroutines.launch
import android.content.ServiceConnection as AndroidServiceConnection

class ServiceConnection(
    private val context: Context,
    callback: Callback,
    private val register: Boolean = true,
) : AndroidServiceConnection {
    companion object {
        private const val TAG = "UmbrellaServiceConn"
    }

    private val serviceCallback = ServiceCallback(callback)
    private var service: IService? = null

    val isConnected: Boolean
        get() = service != null && service?.asBinder()?.isBinderAlive == true

    val status: Status
        get() = service?.let {
            runCatching { Status.entries[it.status] }.getOrNull()
        } ?: Status.Stopped

    fun connect() {
        val intent = Intent(context, Settings.serviceClass()).setAction(Action.SERVICE)
        context.bindService(intent, this, Context.BIND_AUTO_CREATE)
    }

    fun disconnect() {
        try {
            service?.unregisterCallback(serviceCallback)
        } catch (_: RemoteException) {
        }
        runCatching {
            context.unbindService(this)
        }
    }

    fun reconnect() {
        runCatching { context.unbindService(this) }
        val intent = Intent(context, Settings.serviceClass()).setAction(Action.SERVICE)
        context.bindService(intent, this, Context.BIND_AUTO_CREATE)
    }

    override fun onServiceConnected(name: ComponentName?, binder: IBinder?) {
        val service = IService.Stub.asInterface(binder)
        this.service = service
        try {
            if (register) {
                service.registerCallback(serviceCallback)
            }
            serviceCallback.onServiceStatusChanged(service.status)
        } catch (e: RemoteException) {
            Log.e(TAG, "onServiceConnected failed", e)
        }
    }

    override fun onServiceDisconnected(name: ComponentName?) {
        try {
            service?.unregisterCallback(serviceCallback)
        } catch (_: RemoteException) {
        }
        service = null
    }

    override fun onBindingDied(name: ComponentName?) {
        reconnect()
    }

    interface Callback {
        fun onServiceStatusChanged(status: Status)
        fun onServiceAlert(type: Alert, message: String?) {}
        fun onServiceWriteLog(message: String?) {}
        fun onServiceResetLogs(messages: MutableList<String>) {}
    }

    class ServiceCallback(private val callback: Callback) : IServiceCallback.Stub() {
        override fun onServiceStatusChanged(status: Int) {
            GlobalScope.launch(Dispatchers.Main) {
                callback.onServiceStatusChanged(Status.entries[status])
            }
        }

        override fun onServiceAlert(type: Int, message: String?) {
            GlobalScope.launch(Dispatchers.Main) {
                callback.onServiceAlert(Alert.entries[type], message)
            }
        }

        override fun onServiceWriteLog(message: String?) {
            GlobalScope.launch(Dispatchers.Main) {
                callback.onServiceWriteLog(message)
            }
        }

        override fun onServiceResetLogs(messages: MutableList<String>?) {
            GlobalScope.launch(Dispatchers.Main) {
                callback.onServiceResetLogs(messages ?: mutableListOf())
            }
        }
    }
}
