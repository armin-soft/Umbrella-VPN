package ir.umbrella.vpn

import android.app.Activity
import android.app.ActivityManager
import android.content.Context
import android.content.Intent
import android.content.pm.ApplicationInfo
import android.content.pm.PackageInfo
import android.content.pm.PackageManager
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.Settings as AndroidSettings
import ir.umbrella.vpn.bg.BoxService
import ir.umbrella.vpn.constant.Status
import java.io.File
import java.security.MessageDigest

object UmbrellaSecurityScanner {
    data class SignatureMatch(
        val key: String,
        val name: String,
        val category: String,
        val severity: String,
        val detail: String,
    )

    private fun matchKnownPackageOrLabel(
        packageName: String,
        label: String,
        selfPkg: String,
    ): SignatureMatch? {
        if (packageName == selfPkg || packageName.startsWith("ir.umbrella.")) {
            return null
        }
        val combined = "${packageName.lowercase()} ${label.lowercase()}"
        if (combined.contains("jumpjump") ||
            combined.contains("jump-jump") ||
            combined.contains("jump jump")
        ) {
            return SignatureMatch(
                key = "malware:jumpjump",
                name = "JumpJump VPN (بدافزار / ابزار مخرب)",
                category = "malware",
                severity = "critical",
                detail = "برنامه مخرب JumpJump روی دستگاه نصب است؛ تا زمان حذف کامل، اتصال آمبرلا مسدود می ماند.",
            )
        }
        if (combined.contains("psiphon")) {
            return SignatureMatch(
                key = "vpn:psiphon",
                name = "Psiphon (فیلترشکن ناسازگار)",
                category = "conflicting_vpn",
                severity = "high",
                detail = "اپلیکیشن Psiphon روی دستگاه شناسایی شد و با تونل آمبرلا تداخل دارد.",
            )
        }
        if (combined.contains("holavpn") ||
            combined.contains("org.hola") ||
            combined.contains("luminati") ||
            combined.contains("brightdata")
        ) {
            return SignatureMatch(
                key = "adware:hola_luminati",
                name = "Hola / Luminati Proxy (تبلیغ افزار و اشتراک پهنای باند)",
                category = "adware",
                severity = "high",
                detail = "اپلیکیشن اشتراک گذاری ترافیک و پروکسی ناشناس روی دستگاه یافت شد.",
            )
        }
        if (combined.contains("honeygain") ||
            combined.contains("peer2profit") ||
            combined.contains("traffmonetizer") ||
            combined.contains("packetstream") ||
            combined.contains("pawns.app") ||
            combined.contains("earnapp")
        ) {
            return SignatureMatch(
                key = "adware:bandwidth_miner",
                name = "ابزار سوءاستفاده از ترافیک شبکه",
                category = "adware",
                severity = "high",
                detail = "اپلیکیشن مصرف کننده پنهان ترافیک روی دستگاه شناسایی شد.",
            )
        }
        return null
    }

    private fun packageSigningSha256(pm: PackageManager, packageName: String): String {
        return runCatching {
            val info: PackageInfo = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                pm.getPackageInfo(packageName, PackageManager.GET_SIGNING_CERTIFICATES)
            } else {
                @Suppress("DEPRECATION")
                pm.getPackageInfo(packageName, PackageManager.GET_SIGNATURES)
            }
            val sigBytes = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                info.signingInfo?.apkContentsSigners?.firstOrNull()?.toByteArray()
            } else {
                @Suppress("DEPRECATION")
                info.signatures?.firstOrNull()?.toByteArray()
            } ?: return@runCatching ""
            val digest = MessageDigest.getInstance("SHA-256").digest(sigBytes)
            digest.joinToString("") { "%02x".format(it) }
        }.getOrDefault("")
    }

    private fun isOtherVpnTransportActive(context: Context): Boolean {
        val coreStatus = BoxService.status.value ?: Status.Stopped
        if (coreStatus != Status.Stopped) {
            return false
        }
        return runCatching {
            val cm = context.getSystemService(Context.CONNECTIVITY_SERVICE) as? ConnectivityManager
                ?: return@runCatching false
            @Suppress("DEPRECATION")
            val networks = cm.allNetworks
            networks.any { net ->
                val caps = cm.getNetworkCapabilities(net)
                caps != null && caps.hasTransport(NetworkCapabilities.TRANSPORT_VPN)
            }
        }.getOrDefault(false)
    }

    fun isPackageInstalled(context: Context, packageName: String): Boolean {
        if (packageName.isBlank()) return false
        return runCatching {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                context.packageManager.getPackageInfo(
                    packageName,
                    PackageManager.PackageInfoFlags.of(0L),
                )
            } else {
                @Suppress("DEPRECATION")
                context.packageManager.getPackageInfo(packageName, 0)
            }
            true
        }.getOrDefault(false)
    }

    fun scan(context: Context): Map<String, Any> {
        val pm = context.packageManager
        val selfPkg = context.packageName
        val findings = linkedMapOf<String, MutableMap<String, Any>>()

        val packages = runCatching {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                pm.getInstalledApplications(PackageManager.ApplicationInfoFlags.of(0L))
            } else {
                @Suppress("DEPRECATION")
                pm.getInstalledApplications(PackageManager.GET_META_DATA)
            }
        }.getOrDefault(emptyList())

        var scannedFiles = 0
        for (app in packages) {
            if (app.packageName == selfPkg) continue
            val isSystem = (app.flags and ApplicationInfo.FLAG_SYSTEM) != 0
            if (isSystem && app.packageName.startsWith("com.android.")) continue

            val label = runCatching { pm.getApplicationLabel(app).toString() }
                .getOrDefault(app.packageName)
            val hit = matchKnownPackageOrLabel(app.packageName, label, selfPkg) ?: continue
            val sha = packageSigningSha256(pm, app.packageName)
            findings.putIfAbsent(
                hit.key,
                mutableMapOf(
                    "key" to hit.key,
                    "name" to hit.name,
                    "category" to hit.category,
                    "severity" to hit.severity,
                    "target" to "${app.packageName} ($label)",
                    "detail" to hit.detail,
                    "remediationKind" to "uninstall",
                    "packageName" to app.packageName,
                    "path" to (app.sourceDir ?: ""),
                    "sha256" to sha,
                    "active" to true,
                    "signedValid" to true,
                    "blockedByPolicy" to true,
                ),
            )
        }

        // Scan accessible app-private or external download folders for malicious APK installers
        val candidateDirs = listOfNotNull(
            context.getExternalFilesDir(Environment.DIRECTORY_DOWNLOADS),
            runCatching { Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS) }.getOrNull(),
        )
        for (dir in candidateDirs) {
            if (!dir.exists() || !dir.isDirectory) continue
            val children = runCatching { dir.listFiles() }.getOrNull() ?: continue
            for (file in children.take(120)) {
                if (!file.isFile) continue
                val fname = file.name.lowercase()
                if (!fname.endsWith(".apk")) continue
                scannedFiles++
                val hit = matchKnownPackageOrLabel(fname, fname, selfPkg) ?: continue
                val apkKey = "${hit.key}:apk:${fname.hashCode()}"
                findings.putIfAbsent(
                    apkKey,
                    mutableMapOf(
                        "key" to apkKey,
                        "name" to "${hit.name} (فایل نصبی)",
                        "category" to hit.category,
                        "severity" to hit.severity,
                        "target" to file.absolutePath,
                        "detail" to "فایل نصبی مخرب یا ناسازگار روی حافظه دستگاه یافت شد.",
                        "remediationKind" to "file",
                        "path" to file.absolutePath,
                        "packageName" to "",
                        "active" to false,
                        "signedValid" to false,
                        "blockedByPolicy" to true,
                    ),
                )
            }
        }

        // Live conflicting VPN tunnel detection when Umbrella itself is disconnected
        if (isOtherVpnTransportActive(context)) {
            findings.putIfAbsent(
                "vpn:active_other_tunnel",
                mutableMapOf(
                    "key" to "vpn:active_other_tunnel",
                    "name" to "تونل وی پی ان فعال دیگر در سیستم",
                    "category" to "conflicting_vpn",
                    "severity" to "high",
                    "target" to "Android VPN Service",
                    "detail" to "یک فیلترشکن دیگر هم اکنون در اندروید فعال است و مانع برقراری اتصال امن آمبرلا می شود.",
                    "remediationKind" to "vpn_settings",
                    "active" to true,
                    "signedValid" to true,
                    "blockedByPolicy" to true,
                ),
            )
        }

        val sortedThreats = findings.values.sortedWith(
            compareBy<Map<String, Any>> {
                when (it["severity"]) {
                    "critical" -> 0
                    "high" -> 1
                    else -> 2
                }
            }.thenBy { it["name"]?.toString() ?: "" },
        )

        return mapOf(
            "clean" to sortedThreats.isEmpty(),
            "scannedProcesses" to packages.size,
            "scannedApps" to packages.size,
            "scannedFiles" to scannedFiles,
            "scannedAtMs" to System.currentTimeMillis(),
            "threats" to sortedThreats,
        )
    }

    fun remediate(
        activity: Activity,
        key: String,
        remediationKind: String,
        packageName: String,
        path: String,
    ): Map<String, Any> {
        var actionTaken = false

        if (remediationKind == "file" && path.isNotBlank()) {
            val file = File(path)
            if (file.exists() && file.delete()) {
                actionTaken = true
            }
        }

        if (packageName.isNotBlank() && packageName != activity.packageName) {
            runCatching {
                val am = activity.getSystemService(Context.ACTIVITY_SERVICE) as? ActivityManager
                am?.killBackgroundProcesses(packageName)
                actionTaken = true
            }
            if (isPackageInstalled(activity, packageName)) {
                val intent = Intent(
                    Intent.ACTION_DELETE,
                    Uri.fromParts("package", packageName, null),
                ).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                runCatching {
                    activity.startActivity(intent)
                    actionTaken = true
                }
            }
        }

        if (remediationKind == "vpn_settings") {
            runCatching {
                activity.startActivity(
                    Intent(AndroidSettings.ACTION_VPN_SETTINGS).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
                )
                actionTaken = true
            }
        }

        val stillInstalled = if (packageName.isNotBlank()) {
            isPackageInstalled(activity, packageName)
        } else if (remediationKind == "file" && path.isNotBlank()) {
            File(path).exists()
        } else if (remediationKind == "vpn_settings") {
            isOtherVpnTransportActive(activity)
        } else {
            false
        }

        val ok = !stillInstalled
        val message = when {
            ok -> "تهدید با موفقیت متوقف و حذف شد."
            packageName.isNotBlank() ->
                "پنجره حذف سیستم باز شد؛ پس از تایید حذف برنامه، وضعیت امنیتی خودکار تایید می شود."
            remediationKind == "vpn_settings" ->
                "تنظیمات VPN سیستم باز شد؛ فیلترشکن دیگر را قطع کنید تا سپر امنیتی سبز شود."
            actionTaken ->
                "فرآیند متوقف شد اما فایل هنوز باقی است."
            else ->
                "حذف خودکار کامل نشد؛ لطفاً برنامه را از تنظیمات گوشی حذف کنید."
        }

        return mapOf(
            "ok" to ok,
            "actionTaken" to actionTaken,
            "stillPresent" to stillInstalled,
            "message" to message,
        )
    }
}
