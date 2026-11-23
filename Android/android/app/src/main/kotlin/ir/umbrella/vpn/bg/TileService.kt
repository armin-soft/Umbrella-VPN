package ir.umbrella.vpn.bg

import android.content.Intent
import android.net.VpnService
import android.os.Build
import android.service.quicksettings.Tile
import android.service.quicksettings.TileService as AndroidTileService
import androidx.annotation.RequiresApi
import ir.umbrella.vpn.MainActivity
import ir.umbrella.vpn.Settings
import ir.umbrella.vpn.constant.Alert
import ir.umbrella.vpn.constant.ServiceMode
import ir.umbrella.vpn.constant.Status

@RequiresApi(Build.VERSION_CODES.N)
class TileService : AndroidTileService(), ServiceConnection.Callback {
    private val connection = ServiceConnection(this, this)

    override fun onStartListening() {
        super.onStartListening()
        connection.connect()
        onServiceStatusChanged(connection.status)
    }

    override fun onStopListening() {
        connection.disconnect()
        super.onStopListening()
    }

    override fun onClick() {
        super.onClick()
        when (connection.status) {
            Status.Stopped -> {
                if (Settings.activeConfigPath.isBlank()) {
                    openMainActivity()
                    return
                }
                if (Settings.serviceMode == ServiceMode.VPN && VpnService.prepare(this) != null) {
                    openMainActivity()
                    return
                }
                BoxService.start(this, startCore = true)
            }
            Status.Started -> BoxService.stop(this)
            else -> Unit
        }
    }

    override fun onServiceStatusChanged(status: Status) {
        val tile = qsTile ?: return
        tile.state = when (status) {
            Status.Started -> Tile.STATE_ACTIVE
            Status.Starting, Status.Stopping -> Tile.STATE_UNAVAILABLE
            Status.Stopped -> Tile.STATE_INACTIVE
        }
        tile.updateTile()
    }

    override fun onServiceAlert(type: Alert, message: String?) {
    }

    private fun openMainActivity() {
        val intent = Intent(this, MainActivity::class.java).apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            startActivityAndCollapse(
                android.app.PendingIntent.getActivity(
                    this,
                    0,
                    intent,
                    ServiceNotification.pendingFlags,
                ),
            )
        } else {
            @Suppress("DEPRECATION")
            startActivityAndCollapse(intent)
        }
    }
}
