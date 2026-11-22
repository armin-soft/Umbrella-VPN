package ir.umbrella.app

import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.os.Build
import android.os.Process
import java.net.HttpURLConnection
import java.net.Proxy
import java.net.URL

/** Fail-closed verification explicitly bound to this app's VPN network.
 * No redirect, captive portal or successful TCP handshake alone is accepted as evidence.
 */
internal object UmbrellaTunVerifier {
    fun check(connectivity: ConnectivityManager, stillOpen: () -> Boolean): String {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) return "UNSUPPORTED_ANDROID"
        if (!stillOpen()) return "TUN_NOT_OPEN"
        val network = connectivity.allNetworks.firstOrNull { network ->
            val caps = connectivity.getNetworkCapabilities(network)
            caps != null && caps.hasTransport(NetworkCapabilities.TRANSPORT_VPN) &&
                caps.ownerUid == Process.myUid()
        } ?: return "VPN_NETWORK_NOT_VISIBLE"
        val endpoints = listOf(
            "https://cp.cloudflare.com/generate_204",
            "https://www.gstatic.com/generate_204",
            "https://clients3.google.com/generate_204",
        )
        var failure = "PROBE_FAILED"
        for (endpoint in endpoints) {
            if (!stillOpen()) return "TUN_NOT_OPEN"
            var connection: HttpURLConnection? = null
            try {
                connection = network.openConnection(URL(endpoint), Proxy.NO_PROXY) as HttpURLConnection
                connection.instanceFollowRedirects = false
                connection.connectTimeout = 4000
                connection.readTimeout = 4000
                connection.setRequestProperty("Cache-Control", "no-store")
                if (connection.responseCode == 204 && connection.inputStream.use { it.read() == -1 } && stillOpen()) {
                    return "OK"
                }
                failure = "HTTP_UNEXPECTED"
            } catch (_: java.net.SocketTimeoutException) {
                failure = "TIMEOUT"
            } catch (_: javax.net.ssl.SSLException) {
                failure = "TLS_FAILED"
            } catch (_: java.net.UnknownHostException) {
                failure = "DNS_FAILED"
            } catch (_: Exception) {
                // Try the next independent endpoint. No insecure TLS fallback.
            } finally {
                connection?.disconnect()
            }
        }
        return failure
    }
}
