package ir.umbrella.vpn.bg

import android.os.RemoteCallbackList
import androidx.lifecycle.MutableLiveData
import androidx.lifecycle.Observer
import ir.umbrella.vpn.IService
import ir.umbrella.vpn.IServiceCallback
import ir.umbrella.vpn.constant.Status
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch

class ServiceBinder(private val status: MutableLiveData<Status>) : IService.Stub() {
    private val callbacks = RemoteCallbackList<IServiceCallback>()
    private val scope = CoroutineScope(Dispatchers.Main + SupervisorJob())
    private val logLines = ArrayDeque<String>()
    private val statusObserver = Observer<Status> { next ->
        broadcast { callback ->
            callback.onServiceStatusChanged(next.ordinal)
        }
    }

    init {
        status.observeForever(statusObserver)
    }

    fun broadcast(work: (IServiceCallback) -> Unit) {
        scope.launch {
            val count = callbacks.beginBroadcast()
            try {
                for (i in 0 until count) {
                    runCatching {
                        work(callbacks.getBroadcastItem(i))
                    }
                }
            } finally {
                callbacks.finishBroadcast()
            }
        }
    }

    fun appendLog(line: String) {
        synchronized(logLines) {
            if (logLines.size >= 400) logLines.removeFirst()
            logLines.addLast(line)
        }
        broadcast { it.onServiceWriteLog(line) }
    }

    override fun getStatus(): Int = (status.value ?: Status.Stopped).ordinal

    override fun registerCallback(callback: IServiceCallback) {
        callbacks.register(callback)
        val snapshot = synchronized(logLines) { logLines.toList() }
        runCatching {
            callback.onServiceResetLogs(snapshot)
            callback.onServiceStatusChanged((status.value ?: Status.Stopped).ordinal)
        }
    }

    override fun unregisterCallback(callback: IServiceCallback?) {
        if (callback != null) {
            callbacks.unregister(callback)
        }
    }

    fun close() {
        status.removeObserver(statusObserver)
        callbacks.kill()
    }
}
