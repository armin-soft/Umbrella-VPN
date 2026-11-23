package ir.umbrella.vpn.bg

import android.net.DnsResolver
import android.os.Build
import android.os.CancellationSignal
import android.system.ErrnoException
import androidx.annotation.RequiresApi
import com.hiddify.core.libbox.ExchangeContext
import com.hiddify.core.libbox.LocalDNSTransport
import kotlinx.coroutines.CancellableContinuation
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.asExecutor
import kotlinx.coroutines.job
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.suspendCancellableCoroutine
import java.net.InetAddress
import java.net.UnknownHostException
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException

object LocalResolver : LocalDNSTransport {
    private const val RCODE_NXDOMAIN = 3

    override fun raw(): Boolean = Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q

    @RequiresApi(Build.VERSION_CODES.Q)
    override fun exchange(ctx: ExchangeContext, message: ByteArray) = untilCancelled(ctx) {
        val defaultNetwork = DefaultNetworkMonitor.require()
        query { signal, continuation ->
            DnsResolver.getInstance().rawQuery(
                defaultNetwork,
                message,
                DnsResolver.FLAG_NO_RETRY,
                Dispatchers.IO.asExecutor(),
                signal,
                callback(ctx, continuation) { answer -> ctx.rawSuccess(answer) },
            )
        }
    }

    override fun lookup(ctx: ExchangeContext, network: String, domain: String) = untilCancelled(ctx) {
        val defaultNetwork = DefaultNetworkMonitor.require()
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
            val answer = try {
                defaultNetwork.getAllByName(domain)
            } catch (_: UnknownHostException) {
                ctx.errorCode(RCODE_NXDOMAIN)
                return@untilCancelled
            }
            ctx.success(answer.mapNotNull { it.hostAddress }.joinToString("\n"))
            return@untilCancelled
        }
        val type = when {
            network.endsWith("4") -> DnsResolver.TYPE_A
            network.endsWith("6") -> DnsResolver.TYPE_AAAA
            else -> null
        }
        query { signal, continuation ->
            val cb = callback<Collection<InetAddress>>(ctx, continuation) { answer ->
                ctx.success(answer.mapNotNull { it.hostAddress }.joinToString("\n"))
            }
            if (type != null) {
                DnsResolver.getInstance().query(
                    defaultNetwork,
                    domain,
                    type,
                    DnsResolver.FLAG_NO_RETRY,
                    Dispatchers.IO.asExecutor(),
                    signal,
                    cb,
                )
            } else {
                DnsResolver.getInstance().query(
                    defaultNetwork,
                    domain,
                    DnsResolver.FLAG_NO_RETRY,
                    Dispatchers.IO.asExecutor(),
                    signal,
                    cb,
                )
            }
        }
    }

    private fun untilCancelled(ctx: ExchangeContext, block: suspend CoroutineScope.() -> Unit) =
        runBlocking {
            val job = coroutineContext.job
            ctx.onCancel { job.cancel() }
            block()
        }

    @RequiresApi(Build.VERSION_CODES.Q)
    private suspend fun query(start: (CancellationSignal, CancellableContinuation<Unit>) -> Unit) =
        suspendCancellableCoroutine { continuation ->
            val signal = CancellationSignal()
            continuation.invokeOnCancellation { signal.cancel() }
            start(signal, continuation)
        }

    @RequiresApi(Build.VERSION_CODES.Q)
    private fun <T : Any> callback(
        ctx: ExchangeContext,
        continuation: CancellableContinuation<Unit>,
        onSuccess: (T) -> Unit,
    ) = object : DnsResolver.Callback<T> {
        override fun onAnswer(answer: T, rcode: Int) {
            if (rcode == 0) {
                onSuccess(answer)
            } else {
                ctx.errorCode(rcode)
            }
            continuation.resume(Unit)
        }

        override fun onError(error: DnsResolver.DnsException) {
            val cause = error.cause
            if (cause is ErrnoException) {
                ctx.errnoCode(cause.errno)
                continuation.resume(Unit)
            } else {
                continuation.resumeWithException(error)
            }
        }
    }
}
