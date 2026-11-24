package ir.umbrella.vpn

import android.Manifest
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
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import ir.umbrella.vpn.bg.BoxService
import ir.umbrella.vpn.constant.Status
import java.io.File
import java.io.RandomAccessFile
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
        if (packageName == selfPkg ||
            packageName.startsWith("ir.umbrella.") ||
            label.lowercase().contains("umbrella")
        ) {
            return null
        }
        val combined = "${packageName.lowercase()} ${label.lowercase()}"
        if (combined.contains("hiddify")) {
            return SignatureMatch(
                key = "vpn:hiddify",
                name = "Hiddify (فیلترشکن ناسازگار)",
                category = "conflicting_vpn",
                severity = "high",
                detail = "اپلیکیشن Hiddify روی دستگاه نصب است؛ پیش از اتصال به آمبرلا باید آن را حذف کنید.",
            )
        }
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

    private fun fileSha256(file: File): String {
        return runCatching {
            val md = MessageDigest.getInstance("SHA-256")
            file.inputStream().use { input ->
                val buf = ByteArray(16384)
                var total = 0L
                while (total < 16L * 1024L * 1024L) {
                    val r = input.read(buf)
                    if (r <= 0) break
                    md.update(buf, 0, r)
                    total += r
                }
            }
            md.digest().joinToString("") { "%02x".format(it) }
        }.getOrDefault("")
    }

    private fun readSampleBytes(file: File, limitBytes: Int = 2 * 1024 * 1024): ByteArray {
        return runCatching {
            val size = file.length().coerceAtMost(limitBytes.toLong()).toInt()
            if (size <= 0) return@runCatching ByteArray(0)
            val out = ByteArray(size)
            RandomAccessFile(file, "r").use { raf ->
                raf.readFully(out)
            }
            out
        }.getOrDefault(ByteArray(0))
    }

    private fun containsAsciiCi(bytes: ByteArray, needle: String): Boolean {
        val target = needle.lowercase().encodeToByteArray()
        if (target.isEmpty() || bytes.size < target.size) return false
        outer@ for (i in 0..(bytes.size - target.size)) {
            for (j in target.indices) {
                var b = bytes[i + j].toInt() and 0xFF
                if (b in 65..90) b += 32
                if (b != (target[j].toInt() and 0xFF)) continue@outer
            }
            return true
        }
        return false
    }

    private fun containsBytes(bytes: ByteArray, seq: ByteArray, startOffset: Int = 0): Boolean {
        if (seq.isEmpty() || bytes.size - startOffset < seq.size) return false
        outer@ for (i in startOffset..(bytes.size - seq.size)) {
            for (j in seq.indices) {
                if (bytes[i + j] != seq[j]) continue@outer
            }
            return true
        }
        return false
    }

    private fun hasPeHeaderAt(buf: ByteArray, offset: Int): Boolean {
        if (offset + 0x40 > buf.size) return false
        if (buf[offset] != 0x4D.toByte() || buf[offset + 1] != 0x5A.toByte()) return false
        val peRel = (buf[offset + 0x3C].toInt() and 0xFF) or
            ((buf[offset + 0x3D].toInt() and 0xFF) shl 8) or
            ((buf[offset + 0x3E].toInt() and 0xFF) shl 16) or
            ((buf[offset + 0x3F].toInt() and 0xFF) shl 24)
        if (peRel < 0x20 || peRel > 0x2000) return false
        val pe = offset + peRel
        if (pe + 6 > buf.size) return false
        return buf[pe] == 'P'.code.toByte() &&
            buf[pe + 1] == 'E'.code.toByte() &&
            buf[pe + 2] == 0.toByte() &&
            buf[pe + 3] == 0.toByte()
    }

    private fun hasRloOrDoubleExtension(fname: String): Boolean {
        if (fname.any { it == '\u202E' || it == '\u202D' || it in '\u2066'..'\u2069' }) {
            return true
        }
        val lower = fname.lowercase()
        val dangerExts = listOf(".apk", ".exe", ".scr", ".bat", ".sh", ".vbs", ".js", ".hta")
        val decoyExts = listOf(".jpg.", ".jpeg.", ".png.", ".gif.", ".webp.", ".pdf.", ".mp4.", ".zip.")
        return dangerExts.any { lower.endsWith(it) } && decoyExts.any { lower.contains(it) }
    }

    private fun inspectDownloadedFile(file: File, selfPkg: String): SignatureMatch? {
        val fname = file.name
        val lower = fname.lowercase()
        if (lower.contains("umbrella")) return null

        if (hasRloOrDoubleExtension(fname)) {
            return SignatureMatch(
                key = "dl:masq:${lower.hashCode()}",
                name = "فایل تروجانی با نام فریبنده ($fname)",
                category = "malicious_download",
                severity = "critical",
                detail = "این فایل با پسوند دوگانه یا کاراکتر تغییر جهت سعی در پنهان کردن فایل اجرایی یا نصبی به جای تصویر/سند دارد.",
            )
        }

        if (lower.endsWith(".apk")) {
            val hit = matchKnownPackageOrLabel(lower, lower, selfPkg)
            if (hit != null) {
                return hit.copy(
                    key = "${hit.key}:apk:${lower.hashCode()}",
                    name = "${hit.name} (فایل نصبی)",
                    detail = "فایل نصبی مخرب یا ناسازگار روی حافظه دستگاه یافت شد.",
                )
            }
            return null
        }

        val isImage = lower.endsWith(".jpg") || lower.endsWith(".jpeg") ||
            lower.endsWith(".png") || lower.endsWith(".gif") ||
            lower.endsWith(".webp") || lower.endsWith(".bmp") || lower.endsWith(".svg")
        val isScriptOrWeb = lower.endsWith(".html") || lower.endsWith(".htm") ||
            lower.endsWith(".url") || lower.endsWith(".js") || lower.endsWith(".sh")
        if (!isImage && !isScriptOrWeb) return null

        val sample = readSampleBytes(file)
        if (sample.isEmpty()) return null

        if (lower.endsWith(".svg")) {
            if (containsAsciiCi(sample, "<script") ||
                containsAsciiCi(sample, "onload=") ||
                containsAsciiCi(sample, "onerror=") ||
                containsAsciiCi(sample, "javascript:") ||
                containsAsciiCi(sample, "eicar-standard-antivirus-test-file")
            ) {
                return SignatureMatch(
                    key = "dl:svg:${lower.hashCode()}",
                    name = "تصویر SVG حاوی کد تروجانی ($fname)",
                    category = "malicious_download",
                    severity = "critical",
                    detail = "فایل تصویر SVG حاوی اسکریپت یا کد مخرب است.",
                )
            }
            return null
        }

        if (isImage) {
            val validMagic = when {
                lower.endsWith(".jpg") || lower.endsWith(".jpeg") ->
                    sample.size >= 3 && sample[0] == 0xFF.toByte() && sample[1] == 0xD8.toByte() && sample[2] == 0xFF.toByte()
                lower.endsWith(".png") ->
                    sample.size >= 8 && sample[0] == 0x89.toByte() && sample[1] == 0x50.toByte() &&
                        sample[2] == 0x4E.toByte() && sample[3] == 0x47.toByte()
                lower.endsWith(".gif") ->
                    sample.size >= 6 && sample[0] == 'G'.code.toByte() && sample[1] == 'I'.code.toByte() &&
                        sample[2] == 'F'.code.toByte() && sample[3] == '8'.code.toByte()
                lower.endsWith(".webp") ->
                    sample.size >= 12 && sample[0] == 'R'.code.toByte() && sample[1] == 'I'.code.toByte() &&
                        sample[2] == 'F'.code.toByte() && sample[3] == 'F'.code.toByte() &&
                        sample[8] == 'W'.code.toByte() && sample[9] == 'E'.code.toByte() &&
                        sample[10] == 'B'.code.toByte() && sample[11] == 'P'.code.toByte()
                else -> sample.size >= 2 && sample[0] == 'B'.code.toByte() && sample[1] == 'M'.code.toByte()
            }

            val elfSig = byteArrayOf(0x7F, 'E'.code.toByte(), 'L'.code.toByte(), 'F'.code.toByte())
            val dexSig = "dex\n03".encodeToByteArray()

            if (!validMagic &&
                (hasPeHeaderAt(sample, 0) ||
                    containsBytes(sample, elfSig, 0) ||
                    containsBytes(sample, dexSig, 0) ||
                    containsAsciiCi(sample, "androidmanifest.xml") ||
                    containsAsciiCi(sample, "<script") ||
                    containsAsciiCi(sample, "wscript.shell") ||
                    containsAsciiCi(sample, "eicar-standard-antivirus-test-file"))
            ) {
                return SignatureMatch(
                    key = "dl:fake_img:${lower.hashCode()}",
                    name = "بدافزار در پوشش تصویر ($fname)",
                    category = "malicious_download",
                    severity = "critical",
                    detail = "فایل با نام تصویر ذخیره شده اما در واقع حاوی کد اجرایی یا نصبی مخرب است.",
                )
            }

            var hasEmbeddedPe = false
            for (pos in 16 until (sample.size - 0x40).coerceAtLeast(16)) {
                if (sample[pos] == 0x4D.toByte() && sample[pos + 1] == 0x5A.toByte() &&
                    hasPeHeaderAt(sample, pos)
                ) {
                    hasEmbeddedPe = true
                    break
                }
            }
            if (hasEmbeddedPe ||
                containsBytes(sample, dexSig, 16) ||
                (containsAsciiCi(sample, "androidmanifest.xml") && containsAsciiCi(sample, "classes.dex")) ||
                containsAsciiCi(sample, "eicar-standard-antivirus-test-file") ||
                containsAsciiCi(sample, "<script") ||
                containsAsciiCi(sample, "eval(atob(") ||
                containsAsciiCi(sample, "urldownloadtofile")
            ) {
                return SignatureMatch(
                    key = "dl:poly_img:${lower.hashCode()}",
                    name = "تصویر آلوده به پی لود تروجانی ($fname)",
                    category = "malicious_download",
                    severity = "critical",
                    detail = "کد اجرایی یا اسکریپت تروجانی پنهان شده داخل تصویر شناسایی شد.",
                )
            }
            return null
        }

        // Web/script download checks
        if (containsAsciiCi(sample, "eicar-standard-antivirus-test-file") ||
            containsAsciiCi(sample, "eval(atob(") ||
            containsAsciiCi(sample, "wscript.shell") ||
            containsAsciiCi(sample, "activexobject") ||
            containsAsciiCi(sample, "grabify.link") ||
            containsAsciiCi(sample, "iplogger.org") ||
            containsAsciiCi(sample, "iplogger.com") ||
            containsAsciiCi(sample, "2no.co") ||
            containsAsciiCi(sample, "blasze.com")
        ) {
            return SignatureMatch(
                key = "dl:web:${lower.hashCode()}",
                name = "فایل لینک / صفحه تروجانی ($fname)",
                category = "malicious_download",
                severity = "high",
                detail = "فایل دانلود شده حاوی لینک یا اسکریپت تروجانی و فیشینگ است.",
            )
        }
        return null
    }

    fun hasStorageScanAccess(context: Context): Boolean {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            Environment.isExternalStorageManager()
        } else {
            ContextCompat.checkSelfPermission(
                context,
                Manifest.permission.READ_EXTERNAL_STORAGE,
            ) == PackageManager.PERMISSION_GRANTED
        }
    }

    fun requestStorageScanAccess(activity: Activity): Boolean {
        if (hasStorageScanAccess(activity)) return true
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            runCatching {
                val intent = Intent(
                    AndroidSettings.ACTION_MANAGE_APP_ALL_FILES_ACCESS_PERMISSION,
                    Uri.fromParts("package", activity.packageName, null),
                ).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                activity.startActivity(intent)
                true
            }.recoverCatching {
                val fallback = Intent(AndroidSettings.ACTION_MANAGE_ALL_FILES_ACCESS_PERMISSION)
                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                activity.startActivity(fallback)
                true
            }.getOrDefault(false)
        } else {
            ActivityCompat.requestPermissions(
                activity,
                arrayOf(
                    Manifest.permission.READ_EXTERNAL_STORAGE,
                    Manifest.permission.WRITE_EXTERNAL_STORAGE,
                ),
                9412,
            )
            true
        }
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

        // Scan accessible app-private and external download/media folders for malicious APKs, scripts, and disguised images
        val publicDownloads = runCatching { Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS) }.getOrNull()
        val extStorage = runCatching { Environment.getExternalStorageDirectory() }.getOrNull()
        val candidateDirs = listOfNotNull(
            context.getExternalFilesDir(Environment.DIRECTORY_DOWNLOADS),
            publicDownloads,
            publicDownloads?.let { File(it, "Telegram") },
            extStorage?.let { File(it, "Telegram/Telegram Images") },
            extStorage?.let { File(it, "Telegram/Telegram Documents") },
            runCatching { Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_PICTURES) }.getOrNull(),
            runCatching { Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOCUMENTS) }.getOrNull(),
        )
        val visited = hashSetOf<String>()
        for (dir in candidateDirs) {
            if (!dir.exists() || !dir.isDirectory) continue
            val children = runCatching { dir.listFiles() }.getOrNull() ?: continue
            for (file in children.take(160)) {
                if (!file.isFile) continue
                val abs = file.absolutePath
                if (!visited.add(abs.lowercase())) continue
                val fname = file.name.lowercase()
                if (fname.contains("umbrella")) continue
                val watchExt = fname.endsWith(".apk") || fname.endsWith(".jpg") ||
                    fname.endsWith(".jpeg") || fname.endsWith(".png") ||
                    fname.endsWith(".gif") || fname.endsWith(".webp") ||
                    fname.endsWith(".bmp") || fname.endsWith(".svg") ||
                    fname.endsWith(".html") || fname.endsWith(".htm") ||
                    fname.endsWith(".url") || fname.endsWith(".js") || fname.endsWith(".sh")
                if (!watchExt && !hasRloOrDoubleExtension(file.name)) continue

                scannedFiles++
                val hit = inspectDownloadedFile(file, selfPkg) ?: continue
                val sha = fileSha256(file)
                val findingKey = if (sha.isNotEmpty()) "${hit.key}:${sha.take(12)}" else hit.key
                val isAppPkg = hit.category == "conflicting_vpn"
                findings.putIfAbsent(
                    findingKey,
                    mutableMapOf(
                        "key" to findingKey,
                        "name" to hit.name,
                        "category" to hit.category,
                        "severity" to hit.severity,
                        "target" to abs,
                        "detail" to hit.detail,
                        "remediationKind" to "file",
                        "path" to abs,
                        "packageName" to "",
                        "sha256" to sha,
                        "active" to isAppPkg,
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
            "storageAccessGranted" to hasStorageScanAccess(context),
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
                "تنظیمات وی پی ان سیستم باز شد؛ فیلترشکن دیگر را قطع کنید تا سپر امنیتی سبز شود."
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
