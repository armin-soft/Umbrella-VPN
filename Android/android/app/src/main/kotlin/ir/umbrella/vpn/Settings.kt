package ir.umbrella.vpn

import android.content.Context
import android.content.Intent
import ir.umbrella.vpn.bg.ProxyService
import ir.umbrella.vpn.bg.VPNService
import ir.umbrella.vpn.constant.PerAppProxyMode
import ir.umbrella.vpn.constant.ServiceMode
import java.io.File

object Settings {
    private const val PREFS_NAME = "umbrella_native_prefs"

    private val prefs by lazy {
        UmbrellaApplication.application.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
    }

    const val SERVICE_GRPC_MODE: Long = 4L // SetupMode_GRPC_BACKGROUND_INSECURE
    const val UTILITY_GRPC_MODE: Long = 3L // SetupMode_GRPC_NORMAL_INSECURE
    const val DEFAULT_SERVICE_GRPC_PORT = 17078
    const val DEFAULT_UTILITY_GRPC_PORT = 17079

    var baseDir: String
        get() = prefs.getString("base_dir", "")?.takeIf { it.isNotBlank() }
            ?: File(UmbrellaApplication.application.filesDir, "umbrella_core").apply { mkdirs() }.path
        set(value) = prefs.edit().putString("base_dir", value).apply()

    var workingDir: String
        get() = prefs.getString("working_dir", "")?.takeIf { it.isNotBlank() }
            ?: File(UmbrellaApplication.application.getExternalFilesDir(null) ?: UmbrellaApplication.application.filesDir, "umbrella_work").apply { mkdirs() }.path
        set(value) = prefs.edit().putString("working_dir", value).apply()

    var tempDir: String
        get() = prefs.getString("temp_dir", "")?.takeIf { it.isNotBlank() }
            ?: File(UmbrellaApplication.application.cacheDir, "umbrella_tmp").apply { mkdirs() }.path
        set(value) = prefs.edit().putString("temp_dir", value).apply()

    var activeConfigPath: String
        get() = prefs.getString("active_config_path", "") ?: ""
        set(value) = prefs.edit().putString("active_config_path", value).apply()

    var activeSettingsJson: String
        get() = prefs.getString("active_settings_json", "") ?: ""
        set(value) = prefs.edit().putString("active_settings_json", value).apply()

    var activeProfileName: String
        get() = prefs.getString("active_profile_name", "فیلترشکن آمبرلا") ?: "فیلترشکن آمبرلا"
        set(value) = prefs.edit().putString("active_profile_name", value).apply()

    var activeEnableRawConfig: Boolean
        get() = prefs.getBoolean("active_enable_raw_config", false)
        set(value) = prefs.edit().putBoolean("active_enable_raw_config", value).apply()

    var notificationsEnabled: Boolean
        get() = prefs.getBoolean("notifications_enabled", true)
        set(value) = prefs.edit().putBoolean("notifications_enabled", value).apply()

    var serviceMode: String
        get() = prefs.getString("service_mode", ServiceMode.VPN) ?: ServiceMode.VPN
        set(value) = prefs.edit().putString("service_mode", value).apply()

    var grpcServicePort: Int
        get() = prefs.getInt("grpc_service_port", DEFAULT_SERVICE_GRPC_PORT)
        set(value) = prefs.edit().putInt("grpc_service_port", value).apply()

    var grpcUtilityPort: Int
        get() = prefs.getInt("grpc_utility_port", DEFAULT_UTILITY_GRPC_PORT)
        set(value) = prefs.edit().putInt("grpc_utility_port", value).apply()

    var debugMode: Boolean
        get() = prefs.getBoolean("debug_mode", false)
        set(value) = prefs.edit().putBoolean("debug_mode", value).apply()

    var startedByUser: Boolean
        get() = prefs.getBoolean("started_by_user", false)
        set(value) = prefs.edit().putBoolean("started_by_user", value).apply()

    var startOnBoot: Boolean
        get() = prefs.getBoolean("start_on_boot", false)
        set(value) = prefs.edit().putBoolean("start_on_boot", value).apply()

    var dynamicNotification: Boolean
        get() = prefs.getBoolean("dynamic_notification", true)
        set(value) = prefs.edit().putBoolean("dynamic_notification", value).apply()

    var systemProxyEnabled: Boolean
        get() = prefs.getBoolean("system_proxy_enabled", false)
        set(value) = prefs.edit().putBoolean("system_proxy_enabled", value).apply()

    var perAppProxyMode: String
        get() = prefs.getString("per_app_proxy_mode", PerAppProxyMode.OFF) ?: PerAppProxyMode.OFF
        set(value) = prefs.edit().putString("per_app_proxy_mode", value).apply()

    val perAppProxyEnabled: Boolean
        get() = perAppProxyMode == PerAppProxyMode.INCLUDE || perAppProxyMode == PerAppProxyMode.EXCLUDE

    var perAppIncludePackages: List<String>
        get() = decodePackages(prefs.getString("per_app_include_packages", "") ?: "")
        set(value) = prefs.edit().putString("per_app_include_packages", encodePackages(value)).apply()

    var perAppExcludePackages: List<String>
        get() = decodePackages(prefs.getString("per_app_exclude_packages", "") ?: "")
        set(value) = prefs.edit().putString("per_app_exclude_packages", encodePackages(value)).apply()

    var bgGatewayBase: String
        get() = prefs.getString("bg_gateway_base", "") ?: ""
        set(value) = prefs.edit().putString("bg_gateway_base", value.trim()).apply()

    var bgAuthToken: String
        get() = prefs.getString("bg_auth_token", "") ?: ""
        set(value) = prefs.edit().putString("bg_auth_token", value.trim()).apply()

    var bgDeviceId: String
        get() = prefs.getString("bg_device_id", "") ?: ""
        set(value) = prefs.edit().putString("bg_device_id", value.trim()).apply()

    var bgAppVersion: String
        get() = prefs.getString("bg_app_version", "") ?: ""
        set(value) = prefs.edit().putString("bg_app_version", value.trim()).apply()

    var pendingBgSecurityEventsJson: String
        get() = prefs.getString("pending_bg_security_events_json", "") ?: ""
        set(value) = prefs.edit().putString("pending_bg_security_events_json", value).apply()

    val perAppProxyList: List<String>
        get() = if (perAppProxyMode == PerAppProxyMode.INCLUDE) {
            perAppIncludePackages
        } else {
            perAppExcludePackages
        }

    fun serviceClass(): Class<*> =
        if (serviceMode == ServiceMode.PROXY) ProxyService::class.java else VPNService::class.java

    fun serviceIntent(context: Context): Intent = Intent(context, serviceClass())

    private fun encodePackages(items: List<String>): String =
        items.map { it.trim() }.filter { it.isNotEmpty() }.distinct().joinToString("\n")

    private fun decodePackages(raw: String): List<String> =
        raw.split('\n').map { it.trim() }.filter { it.isNotEmpty() }.distinct()
}
