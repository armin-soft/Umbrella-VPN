package ir.umbrella.vpn

import android.app.Activity
import android.content.Intent
import android.content.pm.ShortcutManager
import android.net.VpnService
import android.os.Build
import android.os.Bundle
import androidx.core.content.getSystemService
import androidx.core.content.pm.ShortcutInfoCompat
import androidx.core.content.pm.ShortcutManagerCompat
import androidx.core.graphics.drawable.IconCompat
import ir.umbrella.vpn.bg.BoxService
import ir.umbrella.vpn.bg.ServiceConnection
import ir.umbrella.vpn.constant.ServiceMode
import ir.umbrella.vpn.constant.Status

class ShortcutActivity : Activity(), ServiceConnection.Callback {
    private val connection by lazy { ServiceConnection(this, this, register = false) }
    private var handled = false

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        if (intent.action == Intent.ACTION_CREATE_SHORTCUT) {
            val shortcut = ShortcutInfoCompat.Builder(this, "umbrella_toggle")
                .setShortLabel(getString(R.string.quick_toggle))
                .setIcon(IconCompat.createWithResource(this, R.mipmap.ic_launcher_round))
                .setIntent(Intent(this, ShortcutActivity::class.java).setAction(Intent.ACTION_MAIN))
                .build()
            setResult(RESULT_OK, ShortcutManagerCompat.createShortcutResultIntent(this, shortcut))
            finish()
        } else {
            connection.connect()
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N_MR1) {
                getSystemService<ShortcutManager>()?.reportShortcutUsed("umbrella_toggle")
            }
        }
    }

    override fun onServiceStatusChanged(status: Status) {
        if (handled) return
        handled = true
        when (status) {
            Status.Started -> BoxService.stop(this)
            Status.Stopped -> {
                if (Settings.activeConfigPath.isNotBlank() &&
                    (Settings.serviceMode != ServiceMode.VPN || VpnService.prepare(this) == null)
                ) {
                    BoxService.start(this, startCore = true)
                }
            }
            else -> Unit
        }
        finish()
    }

    override fun onDestroy() {
        runCatching { connection.disconnect() }
        super.onDestroy()
    }
}
