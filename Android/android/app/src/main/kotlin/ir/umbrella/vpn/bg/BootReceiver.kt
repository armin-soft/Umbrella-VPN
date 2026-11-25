package ir.umbrella.vpn.bg

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.net.VpnService
import ir.umbrella.vpn.Settings
import ir.umbrella.vpn.constant.ServiceMode

class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        when (intent.action) {
            Intent.ACTION_BOOT_COMPLETED,
            Intent.ACTION_MY_PACKAGE_REPLACED,
            -> Unit
            else -> return
        }
        if (!Settings.startOnBoot) return
        if (Settings.activeConfigPath.isBlank()) return
        if (Settings.serviceMode == ServiceMode.VPN && VpnService.prepare(context) != null) {
            return
        }
        BoxService.start(context, startCore = true)
    }
}
