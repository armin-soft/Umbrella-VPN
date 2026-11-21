package ir.umbrella.app

import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.os.Build
import android.os.Process
import java.net.HttpURLConnection
import java.net.Proxy
import java.net.URL

/** Fail-closed verification bound to the VPN network, not the app's default
 * network (the app UID is excluded from its own tunnel). No redirect, captive
 * portal or successful TCP handshake alone is accepted as evidence.
 */
internal object UmbrellaTunVerifier {
    fun check(connectivity: ConnectivityManager, stillOpen: () -> Boolean): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q || !stillOpen()) return false
        val network = connectivity.allNetworks.firstOrNull { network ->
            val caps = connectivity.getNetworkCapabilities(network)
            caps != null && caps.hasTransport(NetworkCapabilities.TRANSPORT_VPN) &&
                caps.ownerUid == Process.myUid()
        } ?: return false
        val endpoints = listOf(
            "https://cp.cloudflare.com/generate_204",
            "https://www.gstatic.com/generate_204",
            "https://clients3.google.com/generate_204",
        )
        for (endpoint in endpoints) {
            if (!stillOpen()) return false
            var connection: HttpURLConnection? = null
            try {
                connection = network.openConnection(URL(endpoint), Proxy.NO_PROXY) as HttpURLConnection
                connection.instanceFollowRedirects = false
                connection.connectTimeout = 4000
                connection.readTimeout = 4000
                connection.setRequestProperty("Cache-Control", "no-store")
                if (connection.responseCode == 204 && connection.inputStream.use { it.read() == -1 } && stillOpen()) {
                    return true
                }
            } catch (_: Exception) {
                // Try the next independent endpoint. No insecure TLS fallback.
            } finally {
                connection?.disconnect()
            }
        }
        return false
    }
}
