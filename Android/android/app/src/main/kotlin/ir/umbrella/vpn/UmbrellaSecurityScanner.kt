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
import android.os.FileObserver
import android.os.Handler
import android.os.Looper
import android.provider.Settings as AndroidSettings
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import ir.umbrella.vpn.bg.BoxService
import ir.umbrella.vpn.constant.Status
import java.io.File
import java.io.RandomAccessFile
import java.security.MessageDigest
import java.util.concurrent.ConcurrentHashMap

object UmbrellaSecurityScanner {
    data class SignatureMatch(
        val key: String,
        val name: String,
        val category: String,
        val severity: String,
        val detail: String,
    )

    private data class CleanFileStamp(
        val size: Long,
        val lastModified: Long,
    )

    private const val MAX_CLEAN_CACHE_ENTRIES = 20000
    private const val MAX_LABEL_CACHE_ENTRIES = 4096

    // In-memory clean-file and APK-label caches only store verified non-threat entries.
    private val cleanFileCache = ConcurrentHashMap<String, CleanFileStamp>()
    private val appLabelCache = ConcurrentHashMap<String, Pair<String, String>>()

    private fun isCleanFileCached(pathLower: String, size: Long, lastModified: Long): Boolean {
        val cached = cleanFileCache[pathLower] ?: return false
        return cached.size == size && cached.lastModified == lastModified
    }

    private fun recordCleanFileCache(pathLower: String, size: Long, lastModified: Long) {
        if (size <= 0L) return
        if (cleanFileCache.size >= MAX_CLEAN_CACHE_ENTRIES) {
            cleanFileCache.clear()
        }
        cleanFileCache[pathLower] = CleanFileStamp(size = size, lastModified = lastModified)
    }

    private fun invalidateCleanFileCache(path: String) {
        if (path.isBlank()) {
            cleanFileCache.clear()
            return
        }
        cleanFileCache.remove(path.lowercase())
    }

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

    fun hasActiveOtherVpnTransport(context: Context): Boolean {
        return isOtherVpnTransportActive(context)
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

    private fun collectThirdPartyVpnPackages(context: Context): List<String> {
        val pm = context.packageManager
        val selfPkg = context.packageName
        val results = linkedSetOf<String>()
        val vpnKeywords = listOf(
            "hiddify", "psiphon", "v2ray", "nekobox", "nekoray", "clash",
            "mihomo", "flclash", "openvpn", "wireguard", "amnezia",
            "onedotonedotonedotone", "protonvpn", "nordvpn", "expressvpn",
            "surfshark", "windscribe", "mullvad", "outline", "shadowsocks",
            "v2box", "karing", "happ", "mahsa", "lantern", "hotspotshield",
            "tunnelbear", "cyberghost", "adguard.android.vpn", "orbot",
            "singbox", "sing_box", "sing.box", "shadowrocket", "streisand",
            "napsternet", "httpcustom", "matsuri", "anonytun", "starkvpn",
            "thundervpn", "supervpn", "privado", "bitvpn", "betternet",
            "urbanvpn", "jumpjump",
        )

        val packagesWithServices = runCatching {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                pm.getInstalledPackages(
                    PackageManager.PackageInfoFlags.of(PackageManager.GET_SERVICES.toLong()),
                )
            } else {
                @Suppress("DEPRECATION")
                pm.getInstalledPackages(PackageManager.GET_SERVICES)
            }
        }.getOrDefault(emptyList())

        for (pkgInfo in packagesWithServices) {
            val pkg = pkgInfo.packageName ?: continue
            val pkgLower = pkg.lowercase()
            if (pkg == selfPkg ||
                pkgLower.startsWith("ir.umbrella.") ||
                pkgLower.startsWith("org.telegram.") ||
                pkgLower == "android" ||
                pkgLower.startsWith("com.android.")
            ) {
                continue
            }
            val declaresVpnService = pkgInfo.services?.any { svc ->
                svc.permission == Manifest.permission.BIND_VPN_SERVICE
            } == true
            val matchesKeyword = vpnKeywords.any { kw -> pkgLower.contains(kw) }
            if (declaresVpnService || matchesKeyword) {
                results.add(pkg)
            }
        }
        return results.toList()
    }

    fun closeConflictingVpns(context: Context): Map<String, Any> {
        val am = context.getSystemService(Context.ACTIVITY_SERVICE) as? ActivityManager
        val vpnPackages = collectThirdPartyVpnPackages(context)
        val runningSet = runCatching {
            am?.runningAppProcesses
                ?.flatMap { it.pkgList?.toList().orEmpty() }
                ?.toSet()
                .orEmpty()
        }.getOrDefault(emptySet())

        val targeted = mutableListOf<String>()
        for (pkg in vpnPackages) {
            val isRunning = runningSet.isEmpty() || runningSet.contains(pkg)
            if (isRunning) {
                runCatching {
                    am?.killBackgroundProcesses(pkg)
                    targeted.add(pkg)
                }
            }
        }
        return mapOf(
            "closedCount" to targeted.size,
            "closedPackages" to targeted,
            "otherTunnelActive" to isOtherVpnTransportActive(context),
        )
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

    private fun readHeadAndTailBytes(
        file: File,
        headBytes: Int = 256 * 1024,
        tailBytes: Int = 512 * 1024,
    ): ByteArray {
        return runCatching {
            val totalSize = file.length()
            if (totalSize <= 0L) return@runCatching ByteArray(0)
            val maxCombined = headBytes.toLong() + tailBytes.toLong()
            if (totalSize <= maxCombined) {
                return@runCatching readSampleBytes(file, totalSize.toInt())
            }
            val head = ByteArray(headBytes)
            val tail = ByteArray(tailBytes)
            RandomAccessFile(file, "r").use { raf ->
                raf.readFully(head)
                raf.seek(totalSize - tailBytes.toLong())
                raf.readFully(tail)
            }
            val combined = ByteArray(head.size + tail.size)
            System.arraycopy(head, 0, combined, 0, head.size)
            System.arraycopy(tail, 0, combined, head.size, tail.size)
            combined
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
        val dangerExts = listOf(".apk", ".exe", ".scr", ".bat", ".sh", ".vbs", ".js", ".hta", ".ps1", ".cmd", ".msi", ".dll", ".pif")
        val decoyExts = listOf(".jpg.", ".jpeg.", ".png.", ".gif.", ".webp.", ".pdf.", ".mp4.", ".mp3.", ".wav.", ".doc.", ".docx.", ".zip.", ".rar.")
        return dangerExts.any { lower.endsWith(it) } && decoyExts.any { lower.contains(it) }
    }

    private fun isDangerousArchiveEntry(lowerEntry: String, isOfficeOpenXml: Boolean): Boolean {
        if (lowerEntry.isBlank() || lowerEntry.contains("umbrella")) return false
        if (hasRloOrDoubleExtension(lowerEntry)) return true
        if (matchKnownPackageOrLabel(lowerEntry, lowerEntry, "") != null) return true
        if (isOfficeOpenXml && lowerEntry.contains("vbaproject.bin")) return true
        val badExts = listOf(
            ".apk", ".exe", ".scr", ".pif", ".com", ".bat", ".cmd",
            ".vbs", ".vbe", ".js", ".jse", ".wsf", ".wsh", ".ps1", ".hta", ".msi", ".lnk", ".dll", ".sh",
        )
        return badExts.any { lowerEntry.endsWith(it) }
    }

    private fun inspectZipBufferForPayloads(buf: ByteArray, isOfficeOpenXml: Boolean): String? {
        var i = 0
        while (i + 46 < buf.size) {
            if (buf[i] == 'P'.code.toByte() && buf[i + 1] == 'K'.code.toByte()) {
                if (buf[i + 2] == 0x03.toByte() && buf[i + 3] == 0x04.toByte() && i + 30 < buf.size) {
                    val nameLen = (buf[i + 26].toInt() and 0xFF) or ((buf[i + 27].toInt() and 0xFF) shl 8)
                    if (nameLen in 1..512 && i + 30 + nameLen <= buf.size) {
                        val entryName = String(buf, i + 30, nameLen, Charsets.UTF_8)
                        if (isDangerousArchiveEntry(entryName.lowercase(), isOfficeOpenXml)) {
                            return entryName
                        }
                    }
                } else if (buf[i + 2] == 0x01.toByte() && buf[i + 3] == 0x02.toByte() && i + 46 < buf.size) {
                    val nameLen = (buf[i + 28].toInt() and 0xFF) or ((buf[i + 29].toInt() and 0xFF) shl 8)
                    if (nameLen in 1..512 && i + 46 + nameLen <= buf.size) {
                        val entryName = String(buf, i + 46, nameLen, Charsets.UTF_8)
                        if (isDangerousArchiveEntry(entryName.lowercase(), isOfficeOpenXml)) {
                            return entryName
                        }
                    }
                }
            }
            i++
        }
        return null
    }

    private fun candidateWatchDirectories(context: Context, quick: Boolean = false): List<File> {
        val publicDownloads = runCatching {
            Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS)
        }.getOrNull()
        val extStorage = runCatching { Environment.getExternalStorageDirectory() }.getOrNull()
        if (quick) {
            return listOfNotNull(
                context.getExternalFilesDir(Environment.DIRECTORY_DOWNLOADS),
                publicDownloads,
                publicDownloads?.let { File(it, "Telegram") },
                extStorage?.let { File(it, "Telegram/Telegram Documents") },
            )
        }
        return listOfNotNull(
            context.getExternalFilesDir(Environment.DIRECTORY_DOWNLOADS),
            publicDownloads,
            publicDownloads?.let { File(it, "Telegram") },
            extStorage?.let { File(it, "Telegram/Telegram Images") },
            extStorage?.let { File(it, "Telegram/Telegram Documents") },
            extStorage?.let { File(it, "Telegram/Telegram Audio") },
            extStorage?.let { File(it, "Telegram/Telegram Video") },
            runCatching { Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_PICTURES) }.getOrNull(),
            runCatching { Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_MOVIES) }.getOrNull(),
            runCatching { Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_MUSIC) }.getOrNull(),
            runCatching { Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOCUMENTS) }.getOrNull(),
            runCatching { Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DCIM) }.getOrNull(),
        )
    }

    private val activeObservers = mutableListOf<FileObserver>()
    private val observerHandler = Handler(Looper.getMainLooper())
    private var observerRunnable: Runnable? = null

    fun startFileObservers(onChanged: (String) -> Unit): Boolean {
        stopFileObservers()
        val publicDownloads = runCatching {
            Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS)
        }.getOrNull()
        val extStorage = runCatching { Environment.getExternalStorageDirectory() }.getOrNull()
        val dirs = listOfNotNull(
            publicDownloads,
            publicDownloads?.let { File(it, "Telegram") },
            extStorage?.let { File(it, "Telegram/Telegram Images") },
            extStorage?.let { File(it, "Telegram/Telegram Documents") },
            extStorage?.let { File(it, "Telegram/Telegram Audio") },
            extStorage?.let { File(it, "Telegram/Telegram Video") },
            runCatching { Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_PICTURES) }.getOrNull(),
            runCatching { Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_MOVIES) }.getOrNull(),
            runCatching { Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_MUSIC) }.getOrNull(),
            runCatching { Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOCUMENTS) }.getOrNull(),
        ).distinctBy { it.absolutePath.lowercase() }

        val mask = FileObserver.CREATE or FileObserver.MOVED_TO or FileObserver.CLOSE_WRITE
        for (dir in dirs) {
            if (!dir.exists() || !dir.isDirectory) continue
            runCatching {
                val handleEvent = { relativePath: String? ->
                    val name = relativePath.orEmpty()
                    val lower = name.lowercase()
                    if (name.isNotBlank() &&
                        !lower.contains("umbrella") &&
                        !lower.endsWith(".tmp") &&
                        !lower.endsWith(".crdownload") &&
                        !lower.endsWith(".part")
                    ) {
                        val full = File(dir, name).absolutePath
                        observerHandler.post {
                            observerRunnable?.let { observerHandler.removeCallbacks(it) }
                            val r = Runnable { onChanged(full) }
                            observerRunnable = r
                            observerHandler.postDelayed(r, 650L)
                        }
                    }
                }
                val obs: FileObserver = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                    object : FileObserver(dir, mask) {
                        override fun onEvent(event: Int, path: String?) = handleEvent(path)
                    }
                } else {
                    @Suppress("DEPRECATION")
                    object : FileObserver(dir.absolutePath, mask) {
                        override fun onEvent(event: Int, path: String?) = handleEvent(path)
                    }
                }
                obs.startWatching()
                activeObservers.add(obs)
            }
        }
        return activeObservers.isNotEmpty()
    }

    fun stopFileObservers() {
        observerRunnable?.let { observerHandler.removeCallbacks(it) }
        observerRunnable = null
        for (obs in activeObservers) {
            runCatching { obs.stopWatching() }
        }
        activeObservers.clear()
    }

    private fun collectFilesBounded(
        root: File,
        depth: Int,
        maxDepth: Int,
        maxFiles: Int,
        out: MutableList<File>,
    ) {
        if (out.size >= maxFiles || depth > maxDepth) return
        val children = runCatching { root.listFiles() }.getOrNull() ?: return
        val subdirs = mutableListOf<File>()
        for (child in children) {
            val lower = child.name.lowercase()
            if (child.isDirectory) {
                if (depth < maxDepth &&
                    lower != ".git" &&
                    lower != "node_modules" &&
                    !lower.startsWith(".trash") &&
                    !lower.contains("umbrella")
                ) {
                    subdirs.add(child)
                }
                continue
            }
            if (child.isFile) {
                out.add(child)
                if (out.size >= maxFiles) break
            }
        }
        for (sub in subdirs) {
            if (out.size >= maxFiles) break
            collectFilesBounded(sub, depth + 1, maxDepth, maxFiles, out)
        }
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
            lower.endsWith(".webp") || lower.endsWith(".bmp") ||
            lower.endsWith(".svg") || lower.endsWith(".ico")
        val isMedia = lower.endsWith(".mp4") || lower.endsWith(".mkv") ||
            lower.endsWith(".avi") || lower.endsWith(".mov") ||
            lower.endsWith(".webm") || lower.endsWith(".mp3") ||
            lower.endsWith(".wav") || lower.endsWith(".flac") ||
            lower.endsWith(".ogg") || lower.endsWith(".m4a") ||
            lower.endsWith(".aac") || lower.endsWith(".opus")
        val isArchive = lower.endsWith(".zip") || lower.endsWith(".rar") ||
            lower.endsWith(".7z") || lower.endsWith(".tar") ||
            lower.endsWith(".gz") || lower.endsWith(".iso")
        val isOffice = lower.endsWith(".doc") || lower.endsWith(".docx") ||
            lower.endsWith(".xls") || lower.endsWith(".xlsx") ||
            lower.endsWith(".ppt") || lower.endsWith(".pptx") ||
            lower.endsWith(".rtf")
        val isScriptOrWeb = lower.endsWith(".html") || lower.endsWith(".htm") ||
            lower.endsWith(".url") || lower.endsWith(".js") ||
            lower.endsWith(".sh") || lower.endsWith(".bat") ||
            lower.endsWith(".ps1") || lower.endsWith(".vbs") ||
            lower.endsWith(".hta")

        val header = readSampleBytes(file, 64 * 1024)
        if (header.isEmpty()) return null

        val elfSig = byteArrayOf(0x7F, 'E'.code.toByte(), 'L'.code.toByte(), 'F'.code.toByte())
        val dexSig = "dex\n03".encodeToByteArray()

        if (lower.endsWith(".svg")) {
            val sample = if (file.length() <= header.size.toLong()) header else readSampleBytes(file, 2 * 1024 * 1024)
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
                    header.size >= 3 && header[0] == 0xFF.toByte() && header[1] == 0xD8.toByte() && header[2] == 0xFF.toByte()
                lower.endsWith(".png") ->
                    header.size >= 8 && header[0] == 0x89.toByte() && header[1] == 0x50.toByte() &&
                        header[2] == 0x4E.toByte() && header[3] == 0x47.toByte()
                lower.endsWith(".gif") ->
                    header.size >= 6 && header[0] == 'G'.code.toByte() && header[1] == 'I'.code.toByte() &&
                        header[2] == 'F'.code.toByte() && header[3] == '8'.code.toByte()
                lower.endsWith(".webp") ->
                    header.size >= 12 && header[0] == 'R'.code.toByte() && header[1] == 'I'.code.toByte() &&
                        header[2] == 'F'.code.toByte() && header[3] == 'F'.code.toByte() &&
                        header[8] == 'W'.code.toByte() && header[9] == 'E'.code.toByte() &&
                        header[10] == 'B'.code.toByte() && header[11] == 'P'.code.toByte()
                lower.endsWith(".ico") ->
                    header.size >= 4 && header[0] == 0.toByte() && header[1] == 0.toByte() &&
                        header[2] == 1.toByte() && header[3] == 0.toByte()
                else -> header.size >= 2 && header[0] == 'B'.code.toByte() && header[1] == 'M'.code.toByte()
            }
            val sample = if (validMagic && file.length() > 768L * 1024L) {
                readHeadAndTailBytes(file, 256 * 1024, 512 * 1024)
            } else if (file.length() <= header.size.toLong()) {
                header
            } else {
                readSampleBytes(file, 2 * 1024 * 1024)
            }

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
                if ((sample[pos] == 0x4D.toByte() && sample[pos + 1] == 0x5A.toByte() &&
                        hasPeHeaderAt(sample, pos)) ||
                    (pos + 4 <= sample.size && sample[pos] == 0x7F.toByte() &&
                        sample[pos + 1] == 'E'.code.toByte() && sample[pos + 2] == 'L'.code.toByte() &&
                        sample[pos + 3] == 'F'.code.toByte())
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

        if (isMedia) {
            val binaryHeader = hasPeHeaderAt(header, 0) ||
                containsBytes(header, elfSig, 0) ||
                containsBytes(header, dexSig, 0)
            val sample = if (!binaryHeader && file.length() > 768L * 1024L) {
                readHeadAndTailBytes(file, 256 * 1024, 512 * 1024)
            } else if (file.length() <= header.size.toLong()) {
                header
            } else {
                readSampleBytes(file, 768 * 1024)
            }
            var hasEmbeddedBinary = binaryHeader
            if (!hasEmbeddedBinary) {
                for (pos in 16 until (sample.size - 0x40).coerceAtLeast(16)) {
                    if (sample[pos] == 0x4D.toByte() && sample[pos + 1] == 0x5A.toByte() &&
                        hasPeHeaderAt(sample, pos)
                    ) {
                        hasEmbeddedBinary = true
                        break
                    }
                }
            }
            if (hasEmbeddedBinary ||
                (containsAsciiCi(sample, "androidmanifest.xml") && containsAsciiCi(sample, "classes.dex")) ||
                containsAsciiCi(sample, "eicar-standard-antivirus-test-file") ||
                containsAsciiCi(sample, "<script") ||
                containsAsciiCi(sample, "wscript.shell") ||
                containsAsciiCi(sample, "urldownloadtofile") ||
                containsAsciiCi(sample, "eval(atob(")
            ) {
                return SignatureMatch(
                    key = "dl:media:${lower.hashCode()}",
                    name = "فایل رسانه ای حاوی بدافزار ($fname)",
                    category = "malicious_download",
                    severity = "critical",
                    detail = "این فایل صوتی یا ویدیویی حاوی کد اجرایی یا پی لود تروجانی است.",
                )
            }
            return null
        }

        val sample = if (file.length() <= header.size.toLong()) {
            header
        } else if (isArchive || isOffice || lower.endsWith(".pdf")) {
            readSampleBytes(file, 4 * 1024 * 1024)
        } else {
            readSampleBytes(file, 2 * 1024 * 1024)
        }

        if (isArchive || isOffice || lower.endsWith(".pdf")) {
            val badEntry = if (isArchive || isOffice) {
                inspectZipBufferForPayloads(sample, isOffice)
            } else {
                null
            }
            if (badEntry != null) {
                return SignatureMatch(
                    key = "dl:archive:${lower.hashCode()}",
                    name = "بسته یا سند حاوی فایل مخرب ($fname)",
                    category = "malicious_download",
                    severity = "critical",
                    detail = "درون آرشیو یا سند، فایل مشکوک و مخرب شناسایی شد: $badEntry",
                )
            }
            if (hasPeHeaderAt(sample, 0) ||
                containsBytes(sample, elfSig, 0) ||
                containsBytes(sample, dexSig, 0) ||
                containsAsciiCi(sample, "eicar-standard-antivirus-test-file") ||
                containsAsciiCi(sample, "wscript.shell") ||
                containsAsciiCi(sample, "urldownloadtofile") ||
                containsAsciiCi(sample, "powershell -enc")
            ) {
                return SignatureMatch(
                    key = "dl:doc:${lower.hashCode()}",
                    name = "سند یا بسته دانلودی آلوده ($fname)",
                    category = "malicious_download",
                    severity = "critical",
                    detail = "امضای بدافزار، کد اجرایی یا اسکریپت مخرب درون سند دانلود شده یافت شد.",
                )
            }
            return null
        }

        // Web/script downloads & dangerous executables/unknown extensionless files
        if (isScriptOrWeb) {
            if (hasPeHeaderAt(sample, 0) ||
                containsAsciiCi(sample, "eicar-standard-antivirus-test-file") ||
                containsAsciiCi(sample, "eval(atob(") ||
                containsAsciiCi(sample, "wscript.shell") ||
                containsAsciiCi(sample, "activexobject") ||
                containsAsciiCi(sample, "urldownloadtofile") ||
                containsAsciiCi(sample, "powershell -enc") ||
                containsAsciiCi(sample, "grabify.link") ||
                containsAsciiCi(sample, "iplogger.org") ||
                containsAsciiCi(sample, "iplogger.com") ||
                containsAsciiCi(sample, "2no.co") ||
                containsAsciiCi(sample, "blasze.com")
            ) {
                return SignatureMatch(
                    key = "dl:web:${lower.hashCode()}",
                    name = "فایل لینک / اسکریپت تروجانی ($fname)",
                    category = "malicious_download",
                    severity = "high",
                    detail = "فایل دانلود شده حاوی لینک یا اسکریپت تروجانی و فیشینگ است.",
                )
            }
            return null
        }

        // Remaining / unknown / extensionless files & standalone executables (.exe/.scr/.so)
        val execByExt = lower.endsWith(".exe") || lower.endsWith(".scr") ||
            lower.endsWith(".msi") || lower.endsWith(".bat")
        if (execByExt ||
            hasPeHeaderAt(sample, 0) ||
            containsBytes(sample, elfSig, 0) ||
            containsBytes(sample, dexSig, 0) ||
            containsAsciiCi(sample, "eicar-standard-antivirus-test-file") ||
            containsAsciiCi(sample, "wscript.shell") ||
            containsAsciiCi(sample, "powershell -enc")
        ) {
            val hit = matchKnownPackageOrLabel(lower, lower, selfPkg)
            if (hit != null) {
                return hit.copy(
                    key = "${hit.key}:bin:${lower.hashCode()}",
                    category = if (hit.category == "conflicting_vpn") "conflicting_vpn" else "malicious_download",
                )
            }
            if (execByExt || hasPeHeaderAt(sample, 0) ||
                containsAsciiCi(sample, "eicar-standard-antivirus-test-file") ||
                containsAsciiCi(sample, "wscript.shell") ||
                containsAsciiCi(sample, "powershell -enc")
            ) {
                return SignatureMatch(
                    key = "dl:bin:${lower.hashCode()}",
                    name = "فایل اجرایی یا پی لود مشکوک ($fname)",
                    category = "malicious_download",
                    severity = "critical",
                    detail = "فایل اجرایی ناشناس یا پی لود مشکوک در پوشه دانلودها شناسایی شد.",
                )
            }
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

    fun scan(context: Context, quick: Boolean = false): Map<String, Any> {
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

            val sourceKey = app.sourceDir ?: ""
            val cachedLabel = appLabelCache[app.packageName]
            val label = if (cachedLabel != null && cachedLabel.first == sourceKey) {
                cachedLabel.second
            } else {
                val loaded = runCatching { pm.getApplicationLabel(app).toString() }
                    .getOrDefault(app.packageName)
                if (appLabelCache.size >= MAX_LABEL_CACHE_ENTRIES) {
                    appLabelCache.clear()
                }
                appLabelCache[app.packageName] = sourceKey to loaded
                loaded
            }
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

        // Recursive bounded scan across accessible app-private, downloads, Telegram, media, and documents folders
        val candidateDirs = candidateWatchDirectories(context, quick = quick)
        val dirMaxDepth = if (quick) 1 else 3
        val dirMaxFiles = if (quick) 200 else 800
        val visited = hashSetOf<String>()
        for (dir in candidateDirs) {
            if (!dir.exists() || !dir.isDirectory) continue
            val files = mutableListOf<File>()
            collectFilesBounded(dir, 0, dirMaxDepth, dirMaxFiles, files)
            for (file in files) {
                if (!file.isFile) continue
                val abs = file.absolutePath
                val absLower = abs.lowercase()
                if (!visited.add(absLower)) continue
                val fname = file.name.lowercase()
                if (fname.contains("umbrella") ||
                    fname.endsWith(".tmp") ||
                    fname.endsWith(".crdownload") ||
                    fname.endsWith(".part")
                ) {
                    continue
                }

                scannedFiles++
                val fsize = file.length()
                val fmtime = file.lastModified()
                if (isCleanFileCached(absLower, fsize, fmtime)) {
                    continue
                }
                val hit = inspectDownloadedFile(file, selfPkg)
                if (hit == null) {
                    recordCleanFileCache(absLower, fsize, fmtime)
                    continue
                }
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
                    "detail" to "یک فیلترشکن دیگر هم اکنون در اندروید فعال است؛ هنگام اتصال تونل آمبرلا اتصال قبلی خودکار بسته می شود (مگر اینکه VPN همیشه روشن سیستم فعال باشد).",
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
        invalidateCleanFileCache(path)

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
            val closed = runCatching {
                (closeConflictingVpns(activity)["closedCount"] as? Int) ?: 0
            }.getOrDefault(0)
            if (closed > 0) {
                actionTaken = true
            }
            if (isOtherVpnTransportActive(activity)) {
                runCatching {
                    activity.startActivity(
                        Intent(AndroidSettings.ACTION_VPN_SETTINGS).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
                    )
                    actionTaken = true
                }
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
