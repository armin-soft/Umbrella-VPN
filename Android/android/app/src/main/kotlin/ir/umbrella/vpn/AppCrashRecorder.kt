package ir.umbrella.vpn

import android.content.Context
import android.os.Build
import java.io.File
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

object AppCrashRecorder {
    private var installed = false

    @Synchronized
    fun install(context: Context) {
        if (installed) return
        val previous = Thread.getDefaultUncaughtExceptionHandler()
        val crashDir = File(context.filesDir, "native_crashes")
        Thread.setDefaultUncaughtExceptionHandler { thread, throwable ->
            runCatching {
                crashDir.mkdirs()
                val stamp = SimpleDateFormat("yyyyMMdd-HHmmss", Locale.US).format(Date())
                val file = File(crashDir, "crash-$stamp.txt")
                file.writeText(
                    buildString {
                        appendLine("Umbrella Android Crash Report")
                        appendLine("Device: ${Build.MANUFACTURER} ${Build.MODEL} (SDK ${Build.VERSION.SDK_INT})")
                        appendLine("Thread: ${thread.name}")
                        appendLine(throwable.stackTraceToString())
                    },
                )
            }
            previous?.uncaughtException(thread, throwable)
        }
        installed = true
    }

    fun consumeRecent(context: Context): List<String> {
        val crashDir = File(context.filesDir, "native_crashes")
        if (!crashDir.isDirectory) return emptyList()
        val files = crashDir.listFiles()?.sortedBy { it.name } ?: return emptyList()
        val results = mutableListOf<String>()
        for (file in files.takeLast(5)) {
            runCatching { results.add(file.readText()) }
            runCatching { file.delete() }
        }
        return results
    }
}
