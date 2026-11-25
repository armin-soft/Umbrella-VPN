package ir.umbrella.vpn.bg

import android.os.Build
import ir.umbrella.vpn.BuildConfig

object Bugs {
    // Workaround for Go Android runtime stack unwind issue (#68760)
    val fixAndroidStack: Boolean =
        BuildConfig.DEBUG ||
            (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N && Build.VERSION.SDK_INT <= Build.VERSION_CODES.N_MR1) ||
            Build.VERSION.SDK_INT >= Build.VERSION_CODES.P
}
