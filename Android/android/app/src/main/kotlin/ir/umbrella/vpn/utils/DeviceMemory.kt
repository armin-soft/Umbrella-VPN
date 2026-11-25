package ir.umbrella.vpn.utils

import android.app.ActivityManager
import android.content.Context
import com.hiddify.core.mobile.SetupOptions
import ir.umbrella.vpn.UmbrellaApplication

object DeviceMemory {
    private const val LOW_MEMORY_TOTAL = 2560L shl 20

    private val activityManager: ActivityManager?
        get() = UmbrellaApplication.application.getSystemService(Context.ACTIVITY_SERVICE) as? ActivityManager

    val limit: Long
        get() {
            val manager = activityManager ?: return 0
            val info = ActivityManager.MemoryInfo().also(manager::getMemoryInfo)
            return info.totalMem / 4
        }

    val isLow: Boolean
        get() {
            val manager = activityManager ?: return false
            if (manager.isLowRamDevice) return true
            val info = ActivityManager.MemoryInfo().also(manager::getMemoryInfo)
            return info.totalMem in 1 until LOW_MEMORY_TOTAL
        }

    fun applyTo(options: SetupOptions) {
        options.memoryLimit = limit
        options.lowMemory = isLow
    }
}
