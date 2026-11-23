package ir.umbrella.vpn.utils

import android.util.Log
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.NonCancellable
import kotlinx.coroutines.withContext

private const val TAG = "UmbrellaMethod"

suspend fun MethodChannel.Result.answer(method: String, block: suspend () -> Any?) {
    val value = try {
        block()
    } catch (e: CancellationException) {
        withContext(NonCancellable + Dispatchers.Main.immediate) {
            error(method, "cancelled", null)
        }
        throw e
    } catch (e: Throwable) {
        Log.w(TAG, "$method failed", e)
        withContext(Dispatchers.Main.immediate) {
            error(method, e.message ?: e.toString(), null)
        }
        return
    }
    withContext(Dispatchers.Main.immediate) {
        success(value)
    }
}

fun MethodChannel.Result.answerNow(method: String, block: () -> Any?) {
    val value = try {
        block()
    } catch (e: Throwable) {
        Log.w(TAG, "$method failed", e)
        error(method, e.message ?: e.toString(), null)
        return
    }
    success(value)
}
