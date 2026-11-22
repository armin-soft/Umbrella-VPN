package ir.umbrella.app

import android.net.ConnectivityManager
import android.net.DnsResolver
import android.net.Network
import android.net.NetworkCapabilities
import android.os.Build
import android.os.CancellationSignal
import android.os.Process
import java.net.InetAddress
import java.net.InetSocketAddress
import java.net.SocketTimeoutException
import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executor
import java.util.concurrent.TimeUnit
import javax.net.ssl.SSLException
import javax.net.ssl.SSLSocket
import javax.net.ssl.SSLSocketFactory

/** Verification is always DNS + HTTPS over the app-owned VPN network.
 * A timeout, a redirect or a TLS certificate error can never report success.
 */
internal object UmbrellaTunVerifier {
    private val callbackExecutor = Executor { it.run() }

    private fun resolve(network: Network, host: String): InetAddress? {
        val signal = CancellationSignal()
        val done = CountDownLatch(1)
        var answer: InetAddress? = null
        try {
            DnsResolver.getInstance().query(
                network, host, DnsResolver.TYPE_A, DnsResolver.FLAG_NO_RETRY,
                callbackExecutor, signal,
                object : DnsResolver.Callback<Collection<InetAddress>> {
                    override fun onAnswer(addresses: Collection<InetAddress>, rcode: Int) {
                        if (rcode == 0) answer = addresses.firstOrNull()
                        done.countDown()
                    }
                    override fun onError(error: DnsResolver.DnsException) { done.countDown() }
                },
            )
            if (!done.await(3, TimeUnit.SECONDS)) return null
            return answer
        } finally {
            signal.cancel()
        }
    }

    private fun checkEndpoint(network: Network, host: String): String {
        val address = try { resolve(network, host) } catch (_: Exception) { null }
            ?: return "DNS_FAILED"
        return try {
            // No default-network DNS or sockets: both are explicitly bound to
            // the VPN. TLS still authenticates the hostname and uses SNI.
            network.socketFactory.createSocket().use { plain ->
                plain.connect(InetSocketAddress(address, 443), 3000)
                plain.soTimeout = 3000
                val factory = SSLSocketFactory.getDefault() as SSLSocketFactory
                (factory.createSocket(plain, host, 443, false) as SSLSocket).use { tls ->
                    tls.soTimeout = 3000
                    val params = tls.sslParameters
                    params.endpointIdentificationAlgorithm = "HTTPS"
                    tls.sslParameters = params
                    tls.startHandshake()
                    tls.outputStream.write("GET /generate_204 HTTP/1.1\r\nHost: $host\r\nConnection: close\r\nCache-Control: no-store\r\n\r\n".toByteArray(Charsets.US_ASCII))
                    tls.outputStream.flush()
                    // Read only the bounded status line, not a potentially large body.
                    val line = StringBuilder()
                    while (line.length < 256) {
                        val c = tls.inputStream.read()
                        if (c < 0 || c == 10) break
                        if (c != 13) line.append(c.toChar())
                    }
                    if (Regex("^HTTP/1\\.[01] 204(?: |$)").containsMatchIn(line)) "OK" else "HTTP_UNEXPECTED"
                }
            }
        } catch (_: SocketTimeoutException) {
            "TIMEOUT"
        } catch (_: SSLException) {
            "TLS_FAILED"
        } catch (_: Exception) {
            "CONNECT_FAILED"
        }
    }

    fun check(connectivity: ConnectivityManager, stillOpen: () -> Boolean): String {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) return "UNSUPPORTED_ANDROID"
        if (!stillOpen()) return "TUN_NOT_OPEN"
        val network = connectivity.allNetworks.firstOrNull { candidate ->
            val caps = connectivity.getNetworkCapabilities(candidate)
            caps != null && caps.hasTransport(NetworkCapabilities.TRANSPORT_VPN) &&
                caps.ownerUid == Process.myUid()
        } ?: return "VPN_NETWORK_NOT_VISIBLE"
        val outcomes = mutableListOf<String>()
        for (host in listOf("cp.cloudflare.com", "www.gstatic.com")) {
            if (!stillOpen()) return "TUN_NOT_OPEN"
            val result = checkEndpoint(network, host)
            if (result == "OK" && stillOpen()) return "OK"
            outcomes.add(result)
        }
        // Preserve the most informative failure instead of letting a later DNS
        // failure hide a successful lookup followed by a TCP/TLS failure.
        return outcomes.firstOrNull { it != "DNS_FAILED" } ?: "DNS_FAILED"
    }
}
