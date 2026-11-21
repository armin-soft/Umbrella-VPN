package ir.umbrella.app

import com.hiddify.core.libbox.PlatformInterface
import com.hiddify.core.mobile.Mobile
import com.hiddify.core.mobile.SetupOptions
import java.io.File

/** Native entry point for the Android build of the Windows engine.
 *
 * Not a VPN service: a caller must supply a real VpnService platform interface,
 * create the app-private client identity before setup, and own teardown.
 */
internal object UmbrellaCoreRuntime {
    private const val MTLS_BACKGROUND_MODE = 2L
    private var setupAttempted = false

    @Synchronized
    fun setup(base: File, working: File, temp: File, port: Int, platform: PlatformInterface): ByteArray {
        check(!setupAttempted) { "Core setup already attempted; close before retrying" }
        require(port in 1..65535)
        require(base.isDirectory && working.isDirectory && temp.isDirectory)
        require(File(base, "grpc/client.crt").isFile) { "Missing app-private client certificate" }
        setupAttempted = true
        val options = SetupOptions().apply {
            basePath = base.absolutePath
            workingDir = working.absolutePath
            tempDir = temp.absolutePath
            listen = "127.0.0.1:$port"
            secret = ""
            mode = MTLS_BACKGROUND_MODE
            debug = false
        }
        Mobile.setup(options, platform)
        val certificate = Mobile.getServerPublicKey()
        check(certificate != null && certificate.isNotEmpty()) { "Core server certificate unavailable" }
        return certificate
    }

    /** Call even after a failed setup: setup may have partially initialized. */
    @Synchronized
    fun close() {
        if (!setupAttempted) return
        Mobile.close(MTLS_BACKGROUND_MODE)
        setupAttempted = false
    }
}
