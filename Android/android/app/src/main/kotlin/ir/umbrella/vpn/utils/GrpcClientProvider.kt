package ir.umbrella.vpn.utils

import com.squareup.wire.GrpcClient
import ir.umbrella.vpn.Settings
import okhttp3.OkHttpClient
import okhttp3.Protocol
import java.util.concurrent.TimeUnit

object GrpcClientProvider {
    fun coreGrpcClient(
        port: Int = Settings.grpcServicePort,
        callTimeoutSeconds: Long = 30L,
    ): GrpcClient {
        val httpClient = OkHttpClient.Builder()
            .protocols(listOf(Protocol.H2_PRIOR_KNOWLEDGE))
            .connectTimeout(10, TimeUnit.SECONDS)
            .readTimeout(callTimeoutSeconds, TimeUnit.SECONDS)
            .writeTimeout(callTimeoutSeconds.coerceAtLeast(15L), TimeUnit.SECONDS)
            .callTimeout(callTimeoutSeconds, TimeUnit.SECONDS)
            .build()
        return GrpcClient.Builder()
            .client(httpClient)
            .baseUrl("http://127.0.0.1:$port")
            .build()
    }
}
