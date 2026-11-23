package ir.umbrella.vpn

import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.EventChannel
import ir.umbrella.vpn.bg.ServiceConnection
import ir.umbrella.vpn.constant.Alert
import ir.umbrella.vpn.constant.Status

class EventHandler : EventChannel.StreamHandler, ServiceConnection.Callback {
    private val mainHandler = Handler(Looper.getMainLooper())
    private var sink: EventChannel.EventSink? = null

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        sink = events
    }

    override fun onCancel(arguments: Any?) {
        sink = null
    }

    override fun onServiceStatusChanged(status: Status) {
        emit(
            mapOf(
                "type" to "status",
                "status" to status.name,
            ),
        )
    }

    override fun onServiceAlert(type: Alert, message: String?) {
        emit(
            mapOf(
                "type" to "alert",
                "alert" to type.name,
                "message" to (message ?: ""),
            ),
        )
    }

    override fun onServiceWriteLog(message: String?) {
        if (message.isNullOrBlank()) return
        emit(
            mapOf(
                "type" to "log",
                "message" to message,
            ),
        )
    }

    override fun onServiceResetLogs(messages: MutableList<String>) {
        if (messages.isEmpty()) return
        emit(
            mapOf(
                "type" to "logs_reset",
                "messages" to messages,
            ),
        )
    }

    private fun emit(payload: Map<String, Any>) {
        mainHandler.post {
            sink?.success(payload)
        }
    }
}

