package ir.umbrella.vpn

import android.Manifest
import android.app.Activity
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
import android.provider.DocumentsContract
import android.provider.Settings as AndroidSettings
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import ir.umbrella.vpn.bg.BoxService
import ir.umbrella.vpn.constant.Status
import java.io.ByteArrayOutputStream
import java.io.File
import java.io.FileInputStream
import java.io.RandomAccessFile
import java.security.MessageDigest
import java.util.concurrent.ConcurrentHashMap
import java.util.zip.ZipInputStream
import kotlin.math.log2

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
    private val apkDropperCache = ConcurrentHashMap<String, Pair<Long, Boolean>>()

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
        if (packageName == selfPkg || packageName.startsWith("ir.umbrella.")) {
            return null
        }
        val combined = "${packageName.lowercase()} ${label.lowercase()}"
        if (combined.contains("spynote") ||
            combined.contains("spymax") ||
            combined.contains("craxsrat") ||
            combined.contains("ahmyth") ||
            combined.contains("cypherrat") ||
            combined.contains("droidjack") ||
            combined.contains("androrat") ||
            combined.contains("eaglespy") ||
            combined.contains("ermac") ||
            combined.contains("hookbot")
        ) {
            return SignatureMatch(
                key = "malware:android_rat",
                name = "بدافزار کنترل از راه دور اندروید (RAT)",
                category = "malware",
                severity = "critical",
                detail = "امضای یک تروجان یا ابزار کنترل مخفی دستگاه اندرویدی (RAT) شناسایی شد.",
            )
        }
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
        // Android automatically hands over and revokes any active third-party
        // VpnService tunnel when Umbrella calls VpnService.prepare + Builder.establish.
        val vpnPackages = collectThirdPartyVpnPackages(context)
        val otherTunnelActive = isOtherVpnTransportActive(context)
        return mapOf(
            "closedCount" to if (otherTunnelActive) 1 else 0,
            "closedPackages" to vpnPackages,
            "otherTunnelActive" to otherTunnelActive,
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

    private fun shannonEntropy(bytes: ByteArray, offset: Int = 0, length: Int = bytes.size - offset): Double {
        if (length <= 0 || offset < 0 || offset + length > bytes.size) return 0.0
        val freq = IntArray(256)
        for (i in offset until (offset + length)) {
            freq[bytes[i].toInt() and 0xFF]++
        }
        var ent = 0.0
        val lenD = length.toDouble()
        for (c in freq) {
            if (c == 0) continue
            val p = c.toDouble() / lenD
            ent -= p * log2(p)
        }
        return ent
    }

    private fun containsBinderOrPayloadBytes(buf: ByteArray, startOffset: Int = 0): Boolean {
        if (startOffset < 0 || startOffset >= buf.size) return false
        val elfSig = byteArrayOf(0x7F, 'E'.code.toByte(), 'L'.code.toByte(), 'F'.code.toByte())
        val dexSig = "dex\n03".encodeToByteArray()
        for (pos in startOffset until (buf.size - 4)) {
            if (pos + 0x40 <= buf.size && buf[pos] == 0x4D.toByte() && buf[pos + 1] == 0x5A.toByte() &&
                hasPeHeaderAt(buf, pos)
            ) {
                return true
            }
            if (pos + 4 <= buf.size && buf[pos] == elfSig[0] && buf[pos + 1] == elfSig[1] &&
                buf[pos + 2] == elfSig[2] && buf[pos + 3] == elfSig[3]
            ) {
                return true
            }
            if (buf[pos] == 'P'.code.toByte() && buf[pos + 1] == 'K'.code.toByte() &&
                buf[pos + 2] == 0x03.toByte() && buf[pos + 3] == 0x04.toByte()
            ) {
                return true
            }
            if (pos + 7 <= buf.size && buf[pos] == 'R'.code.toByte() && buf[pos + 1] == 'a'.code.toByte() &&
                buf[pos + 2] == 'r'.code.toByte() && buf[pos + 3] == '!'.code.toByte() &&
                buf[pos + 4] == 0x1A.toByte() && buf[pos + 5] == 0x07.toByte()
            ) {
                return true
            }
            if (pos + 6 <= buf.size && buf[pos] == '7'.code.toByte() && buf[pos + 1] == 'z'.code.toByte() &&
                buf[pos + 2] == 0xBC.toByte() && buf[pos + 3] == 0xAF.toByte() &&
                buf[pos + 4] == 0x27.toByte() && buf[pos + 5] == 0x1C.toByte()
            ) {
                return true
            }
        }
        val slice = if (startOffset == 0) buf else buf.copyOfRange(startOffset, buf.size)
        return containsBytes(slice, dexSig, 0) ||
            (containsAsciiCi(slice, "androidmanifest.xml") && containsAsciiCi(slice, "classes.dex")) ||
            containsAsciiCi(slice, "eicar-standard-antivirus-test-file") ||
            containsAsciiCi(slice, "<script") ||
            containsAsciiCi(slice, "wscript.shell") ||
            containsAsciiCi(slice, "urldownloadtofile") ||
            containsAsciiCi(slice, "frombase64string") ||
            containsAsciiCi(slice, "invoke-expression") ||
            containsAsciiCi(slice, "powershell -enc") ||
            containsAsciiCi(slice, "basestart-") ||
            containsAsciiCi(slice, "-baseend") ||
            containsAsciiCi(slice, "tvqqaam") ||
            containsAsciiCi(slice, "uesdb") ||
            containsAsciiCi(slice, "dexclassloader")
    }

    private fun isOfficialPngChunkType(t: String): Boolean {
        val official = setOf(
            "IHDR", "PLTE", "IDAT", "IEND", "tRNS", "cHRM", "gAMA", "iCCP",
            "sBIT", "sRGB", "tEXt", "zTXt", "iTXt", "bKGD", "hIST", "pHYs",
            "sPLT", "tIME", "eXIf", "acTL", "fcTL", "fdAT", "oFFs", "pCAL",
            "sCAL", "sTER", "dSIG",
        )
        if (official.contains(t)) return true
        return t.length == 4 && t[1] !in 'a'..'z'
    }

    private fun isSafeMotionPhotoTrailer(tail: ByteArray): Boolean {
        if (containsBinderOrPayloadBytes(tail, 0)) return false
        return containsAsciiCi(tail, "ftypmp4") ||
            containsAsciiCi(tail, "ftypisom") ||
            containsAsciiCi(tail, "seft")
    }

    private fun inspectImagePolyglotFile(file: File, fname: String, lower: String): SignatureMatch? {
        val totalLen = file.length()
        if (totalLen < 12L) return null
        return runCatching {
            RandomAccessFile(file, "r").use { raf ->
                val hdr = ByteArray(12)
                val hRead = raf.read(hdr)
                if (hRead < 4) return@use null

                // 1. PNG Chunk Traversal + Post-IEND Binder Detection
                if (lower.endsWith(".png") && hRead >= 8 &&
                    hdr[0] == 0x89.toByte() && hdr[1] == 0x50.toByte() &&
                    hdr[2] == 0x4E.toByte() && hdr[3] == 0x47.toByte() &&
                    hdr[4] == 0x0D.toByte() && hdr[5] == 0x0A.toByte() &&
                    hdr[6] == 0x1A.toByte() && hdr[7] == 0x0A.toByte()
                ) {
                    var offset = 8L
                    var iendEof = 0L
                    val chdr = ByteArray(8)
                    while (offset + 12L <= totalLen) {
                        raf.seek(offset)
                        if (raf.read(chdr) < 8) break
                        val clen = ((chdr[0].toLong() and 0xFFL) shl 24) or
                            ((chdr[1].toLong() and 0xFFL) shl 16) or
                            ((chdr[2].toLong() and 0xFFL) shl 8) or
                            (chdr[3].toLong() and 0xFFL)
                        val ctype = String(chdr, 4, 4, Charsets.US_ASCII)
                        if (clen < 0L || clen > 64L * 1024L * 1024L || offset + 12L + clen > totalLen) break

                        val inspectChunk = ctype == "tEXt" || ctype == "zTXt" ||
                            ctype == "iTXt" || !isOfficialPngChunkType(ctype)
                        if (inspectChunk && clen > 0L) {
                            val cap = minOf(clen, 512L * 1024L).toInt()
                            val cbuf = ByteArray(cap)
                            val cRead = raf.read(cbuf)
                            if (cRead > 0) {
                                val slice = if (cRead == cap) cbuf else cbuf.copyOf(cRead)
                                if (containsBinderOrPayloadBytes(slice, 0) ||
                                    (!isOfficialPngChunkType(ctype) && cRead >= 8192 &&
                                        shannonEntropy(slice) >= 7.65)
                                ) {
                                    return@use SignatureMatch(
                                        key = "dl:png_chunk:${lower.hashCode()}",
                                        name = "تصویر PNG حاوی پی لود مخفی ($fname)",
                                        category = "malicious_download",
                                        severity = "critical",
                                        detail = "کد اجرایی یا داده مخرب درون چانک متادیتا/خصوصی تصویر PNG شناسایی شد.",
                                    )
                                }
                            }
                        }
                        offset += 12L + clen
                        if (ctype == "IEND") {
                            iendEof = offset
                            break
                        }
                    }
                    if (iendEof > 0L && totalLen > iendEof) {
                        val cap = minOf(totalLen - iendEof, 2L * 1024L * 1024L).toInt()
                        val trailer = ByteArray(cap)
                        raf.seek(iendEof)
                        val tRead = raf.read(trailer)
                        if (tRead > 0) {
                            var firstNz = 0
                            while (firstNz < tRead && trailer[firstNz] == 0.toByte()) firstNz++
                            val meaningful = tRead - firstNz
                            if (meaningful >= 16) {
                                val sub = trailer.copyOfRange(firstNz, tRead)
                                if (containsBinderOrPayloadBytes(sub, 0) ||
                                    (meaningful >= 512 && shannonEntropy(sub) >= 7.35)
                                ) {
                                    return@use SignatureMatch(
                                        key = "dl:png_eof:${lower.hashCode()}",
                                        name = "تصویر PNG با فایل بایندشده ($fname)",
                                        category = "malicious_download",
                                        severity = "critical",
                                        detail = "فایل اجرایی، آرشیو یا پی لود مخرب چسبیده به انتهای تصویر PNG (بعد از IEND) شناسایی شد.",
                                    )
                                }
                            }
                        }
                    }
                    return@use null
                }

                // 2. JPEG Marker Traversal (skips EXIF thumbnails) + Post-EOI Binder Detection
                if ((lower.endsWith(".jpg") || lower.endsWith(".jpeg")) && hRead >= 3 &&
                    hdr[0] == 0xFF.toByte() && hdr[1] == 0xD8.toByte() && hdr[2] == 0xFF.toByte()
                ) {
                    var pos = 2L
                    var hitSos = false
                    val m = ByteArray(4)
                    while (pos + 4L <= totalLen) {
                        raf.seek(pos)
                        val mRead = raf.read(m)
                        if (mRead < 2 || m[0] != 0xFF.toByte()) break
                        var marker = m[1].toInt() and 0xFF
                        while (marker == 0xFF && pos + 2L < totalLen) {
                            pos++
                            raf.seek(pos)
                            if (raf.read(m) < 2) break
                            marker = m[1].toInt() and 0xFF
                        }
                        if (marker == 0xD9 || marker == 0x00) break
                        if (marker == 0xD8 || marker in 0xD0..0xD7 || marker == 0x01) {
                            pos += 2L
                            continue
                        }
                        if (mRead < 4) break
                        val segLen = ((m[2].toInt() and 0xFF) shl 8) or (m[3].toInt() and 0xFF)
                        if (segLen < 2 || pos + 2L + segLen > totalLen) break
                        if (marker == 0xDA) {
                            hitSos = true
                            pos += 2L + segLen
                            break
                        }
                        if (marker in 0xE0..0xEF || marker == 0xFE) {
                            val segCap = minOf(segLen - 2, 131072)
                            if (segCap >= 8) {
                                val seg = ByteArray(segCap)
                                val sRead = raf.read(seg)
                                if (sRead > 0) {
                                    val sSlice = if (sRead == segCap) seg else seg.copyOf(sRead)
                                    if (containsAsciiCi(sSlice, "<script") ||
                                        containsAsciiCi(sSlice, "basestart-") ||
                                        containsAsciiCi(sSlice, "tvqqaam") ||
                                        containsAsciiCi(sSlice, "frombase64string") ||
                                        containsAsciiCi(sSlice, "powershell -enc") ||
                                        containsAsciiCi(sSlice, "dexclassloader")
                                    ) {
                                        return@use SignatureMatch(
                                            key = "dl:jpg_meta:${lower.hashCode()}",
                                            name = "کد مخرب در متادیتای تصویر JPEG ($fname)",
                                            category = "malicious_download",
                                            severity = "critical",
                                            detail = "پی لود یا اسکریپت تروجانی درون متادیتای تصویر JPEG تزریق شده است.",
                                        )
                                    }
                                }
                            }
                        }
                        pos += 2L + segLen
                    }
                    if (hitSos && pos < totalLen) {
                        val tailWin = minOf(totalLen - pos, 2L * 1024L * 1024L).toInt()
                        val scanStart = totalLen - tailWin
                        val tail = ByteArray(tailWin)
                        raf.seek(scanStart)
                        val tRead = raf.read(tail)
                        if (tRead > 4) {
                            var lastEoi = -1
                            for (i in (tRead - 2) downTo 1) {
                                if (tail[i] == 0xFF.toByte() && tail[i + 1] == 0xD9.toByte()) {
                                    lastEoi = i + 2
                                    break
                                }
                            }
                            if (lastEoi in 1 until tRead) {
                                var firstNz = lastEoi
                                while (firstNz < tRead && tail[firstNz] == 0.toByte()) firstNz++
                                val extra = tRead - firstNz
                                if (extra >= 64) {
                                    val appended = tail.copyOfRange(firstNz, tRead)
                                    if (!isSafeMotionPhotoTrailer(appended) &&
                                        (containsBinderOrPayloadBytes(appended, 0) ||
                                            (extra >= 1024 && shannonEntropy(appended) >= 7.45))
                                    ) {
                                        return@use SignatureMatch(
                                            key = "dl:jpg_eoi:${lower.hashCode()}",
                                            name = "تصویر JPEG با فایل بایندشده ($fname)",
                                            category = "malicious_download",
                                            severity = "critical",
                                            detail = "فایل اجرایی، آرشیو یا بدافزار چسبیده به انتهای تصویر JPEG (بعد از FFD9) شناسایی شد.",
                                        )
                                    }
                                }
                            }
                        }
                    }
                    return@use null
                }

                // 3. BMP Declared Size Mismatch & GIF Post-Trailer Check
                if (lower.endsWith(".bmp") && hRead >= 6 &&
                    hdr[0] == 'B'.code.toByte() && hdr[1] == 'M'.code.toByte()
                ) {
                    val declared = (hdr[2].toLong() and 0xFFL) or
                        ((hdr[3].toLong() and 0xFFL) shl 8) or
                        ((hdr[4].toLong() and 0xFFL) shl 16) or
                        ((hdr[5].toLong() and 0xFFL) shl 24)
                    if (declared >= 54L && totalLen > declared + 64L) {
                        val cap = minOf(totalLen - declared, 2L * 1024L * 1024L).toInt()
                        val extra = ByteArray(cap)
                        raf.seek(declared)
                        val tRead = raf.read(extra)
                        if (tRead >= 64) {
                            val slice = if (tRead == cap) extra else extra.copyOf(tRead)
                            if (containsBinderOrPayloadBytes(slice, 0) || shannonEntropy(slice) >= 7.35) {
                                return@use SignatureMatch(
                                    key = "dl:bmp_eof:${lower.hashCode()}",
                                    name = "تصویر BMP با فایل بایندشده ($fname)",
                                    category = "malicious_download",
                                    severity = "critical",
                                    detail = "داده یا بدافزار بایندشده در انتهای تصویر BMP شناسایی شد.",
                                )
                            }
                        }
                    }
                }
                if (lower.endsWith(".gif") && hRead >= 6 &&
                    hdr[0] == 'G'.code.toByte() && hdr[1] == 'I'.code.toByte() &&
                    hdr[2] == 'F'.code.toByte() && hdr[3] == '8'.code.toByte()
                ) {
                    val win = minOf(totalLen, 1024L * 1024L).toInt()
                    val tail = ByteArray(win)
                    raf.seek(totalLen - win)
                    val tRead = raf.read(tail)
                    if (tRead > 8) {
                        var trailerPos = -1
                        for (i in (tRead - 1) downTo 0) {
                            if (tail[i] == 0x3B.toByte()) {
                                trailerPos = i + 1
                                break
                            }
                        }
                        if (trailerPos > 0 && trailerPos + 64 <= tRead) {
                            var firstNz = trailerPos
                            while (firstNz < tRead && tail[firstNz] == 0.toByte()) firstNz++
                            if (tRead - firstNz >= 64) {
                                val appended = tail.copyOfRange(firstNz, tRead)
                                if (containsBinderOrPayloadBytes(appended, 0) ||
                                    (appended.size >= 1024 && shannonEntropy(appended) >= 7.45)
                                ) {
                                    return@use SignatureMatch(
                                        key = "dl:gif_eof:${lower.hashCode()}",
                                        name = "تصویر GIF با فایل بایندشده ($fname)",
                                        category = "malicious_download",
                                        severity = "critical",
                                        detail = "داده یا بدافزار بایندشده پس از پایان تصویر GIF شناسایی شد.",
                                    )
                                }
                            }
                        }
                    }
                }
                null
            }
        }.getOrNull()
    }

    private fun inspectPdfPayload(sample: ByteArray, fname: String, lower: String): SignatureMatch? {
        val hasJsOrLaunch = containsAsciiCi(sample, "/js") ||
            containsAsciiCi(sample, "/javascript") ||
            containsAsciiCi(sample, "/launch")
        val hasAutoOrEmbed = containsAsciiCi(sample, "/openaction") ||
            containsAsciiCi(sample, "/aa ") ||
            containsAsciiCi(sample, "/aa<<") ||
            containsAsciiCi(sample, "/embeddedfile") ||
            containsAsciiCi(sample, "/richmedia")
        if (hasJsOrLaunch && hasAutoOrEmbed) {
            return SignatureMatch(
                key = "dl:pdf_act:${lower.hashCode()}",
                name = "سند PDF حاوی اسکریپت یا فرمان مخرب ($fname)",
                category = "malicious_download",
                severity = "critical",
                detail = "فایل PDF حاوی اسکریپت یا فایل اجرایی با اجرای خودکار است.",
            )
        }
        val text = String(sample, Charsets.ISO_8859_1).lowercase()
        val lastEof = text.lastIndexOf("%%eof")
        if (lastEof >= 0 && lastEof + 64 < sample.size &&
            containsBinderOrPayloadBytes(sample, lastEof + 5)
        ) {
            return SignatureMatch(
                key = "dl:pdf_eof:${lower.hashCode()}",
                name = "فایل بایندشده در انتهای سند PDF ($fname)",
                category = "malicious_download",
                severity = "critical",
                detail = "پی لود مخفی شده پس از پایان رسمی سند PDF شناسایی شد.",
            )
        }
        return null
    }

    private fun hasHiddenPayloadEntriesInApk(apkFile: File): Boolean {
        return runCatching {
            var count = 0
            ZipInputStream(FileInputStream(apkFile)).use { zis ->
                while (count < 1500) {
                    val entry = zis.nextEntry ?: break
                    count++
                    val eLower = entry.name.lowercase()
                    if (!entry.isDirectory) {
                        val inHiddenAssetDir = eLower.startsWith("assets/") || eLower.startsWith("res/raw/")
                        if (inHiddenAssetDir && (eLower.endsWith(".apk") ||
                                eLower.endsWith(".dex") ||
                                eLower.endsWith(".jar") ||
                                eLower.endsWith(".exe"))
                        ) {
                            return@use true
                        }
                        if (eLower.contains("craxsrat") ||
                            eLower.contains("spynote") ||
                            eLower.contains("spymax") ||
                            eLower.contains("ahmyth") ||
                            eLower.contains("cypherrat") ||
                            eLower.contains("eaglespy")
                        ) {
                            return@use true
                        }
                    }
                    zis.closeEntry()
                }
                false
            }
        }.getOrDefault(false)
    }

    private fun inspectDownloadedApk(
        context: Context,
        file: File,
        selfPkg: String,
    ): SignatureMatch? {
        val fname = file.name
        val lower = fname.lowercase()
        val pm = context.packageManager
        val flags = PackageManager.GET_PERMISSIONS or PackageManager.GET_SERVICES or PackageManager.GET_RECEIVERS
        val pkgInfo = runCatching {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                pm.getPackageArchiveInfo(
                    file.absolutePath,
                    PackageManager.PackageInfoFlags.of(flags.toLong()),
                )
            } else {
                @Suppress("DEPRECATION")
                pm.getPackageArchiveInfo(file.absolutePath, flags)
            }
        }.getOrNull()

        if (pkgInfo != null) {
            val pkgName = pkgInfo.packageName ?: ""
            val appInfo = pkgInfo.applicationInfo
            val label = if (appInfo != null) {
                appInfo.sourceDir = file.absolutePath
                appInfo.publicSourceDir = file.absolutePath
                runCatching { pm.getApplicationLabel(appInfo).toString() }.getOrDefault(pkgName)
            } else {
                pkgName
            }
            val knownHit = matchKnownPackageOrLabel(pkgName, "$label $lower", selfPkg)
            if (knownHit != null) {
                return knownHit.copy(
                    key = "${knownHit.key}:apk:${lower.hashCode()}",
                    name = "${knownHit.name} (فایل نصبی)",
                    detail = "فایل نصبی مخرب یا ناسازگار روی حافظه دستگاه یافت شد.",
                )
            }
            if (pkgName == selfPkg || pkgName.startsWith("ir.umbrella.")) {
                return null
            }

            val perms = pkgInfo.requestedPermissions?.toSet() ?: emptySet()
            val hasA11yService = pkgInfo.services?.any {
                it.permission == Manifest.permission.BIND_ACCESSIBILITY_SERVICE
            } == true
            val hasDeviceAdmin = pkgInfo.receivers?.any {
                it.permission == Manifest.permission.BIND_DEVICE_ADMIN
            } == true
            val hasSms = perms.contains(Manifest.permission.READ_SMS) ||
                perms.contains(Manifest.permission.RECEIVE_SMS) ||
                perms.contains(Manifest.permission.SEND_SMS)
            val hasOverlay = perms.contains(Manifest.permission.SYSTEM_ALERT_WINDOW)
            val hasMicOrCam = perms.contains(Manifest.permission.RECORD_AUDIO) ||
                perms.contains(Manifest.permission.CAMERA)
            val hasInstallPerm = perms.contains(Manifest.permission.REQUEST_INSTALL_PACKAGES)

            if (hasA11yService && (hasDeviceAdmin || (hasOverlay && (hasSms || hasMicOrCam || hasInstallPerm)))) {
                return SignatureMatch(
                    key = "dl:apk_rat:${lower.hashCode()}",
                    name = "فایل نصبی تروجانی با دسترسی کنترل کامل ($fname)",
                    category = "malicious_download",
                    severity = "critical",
                    detail = "این فایل نصبی ترکیبی بسیار پرخطر از سرویس دسترسی پذیری، مدیر دستگاه، پیامک یا روکش صفحه (الگوی RAT) را درخواست می کند.",
                )
            }
        } else {
            val nameHit = matchKnownPackageOrLabel(lower, lower, selfPkg)
            if (nameHit != null) {
                return nameHit.copy(
                    key = "${nameHit.key}:apk:${lower.hashCode()}",
                    name = "${nameHit.name} (فایل نصبی)",
                    detail = "فایل نصبی مخرب یا ناسازگار روی حافظه دستگاه یافت شد.",
                )
            }
        }

        if (hasHiddenPayloadEntriesInApk(file)) {
            return SignatureMatch(
                key = "dl:apk_dropper:${lower.hashCode()}",
                name = "فایل نصبی حاوی پی لود یا کد مخفی ($fname)",
                category = "malicious_download",
                severity = "critical",
                detail = "درون منابع این APK فایل اجرایی .dex/.apk/.jar پنهان شده (الگوی Dropper/SpyNote) یافت شد.",
            )
        }
        return null
    }

    private fun inspectInstalledAppBehavioralRisk(
        context: Context,
        pm: PackageManager,
        app: ApplicationInfo,
        label: String,
        enabledA11y: String,
    ): SignatureMatch? {
        val pkg = app.packageName ?: return null
        val pkgLower = pkg.lowercase()
        if (pkg == context.packageName ||
            pkgLower.startsWith("ir.umbrella.") ||
            pkgLower.startsWith("com.android.") ||
            pkgLower.startsWith("com.google.android.") ||
            pkgLower.startsWith("com.samsung.") ||
            pkgLower.startsWith("com.sec.") ||
            pkgLower.startsWith("com.miui.") ||
            pkgLower.startsWith("com.xiaomi.") ||
            pkgLower.startsWith("com.huawei.") ||
            pkgLower.startsWith("com.oppo.") ||
            pkgLower.startsWith("com.vivo.") ||
            pkgLower.startsWith("org.telegram.")
        ) {
            return null
        }
        if ((app.flags and (ApplicationInfo.FLAG_SYSTEM or ApplicationInfo.FLAG_UPDATED_SYSTEM_APP)) != 0) {
            return null
        }

        val flags = PackageManager.GET_PERMISSIONS or PackageManager.GET_SERVICES or PackageManager.GET_RECEIVERS
        val pkgInfo = runCatching {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                pm.getPackageInfo(pkg, PackageManager.PackageInfoFlags.of(flags.toLong()))
            } else {
                @Suppress("DEPRECATION")
                pm.getPackageInfo(pkg, flags)
            }
        }.getOrNull() ?: return null

        val perms = pkgInfo.requestedPermissions?.toSet() ?: emptySet()
        val hasA11y = pkgInfo.services?.any {
            it.permission == Manifest.permission.BIND_ACCESSIBILITY_SERVICE
        } == true
        val hasDeviceAdmin = pkgInfo.receivers?.any {
            it.permission == Manifest.permission.BIND_DEVICE_ADMIN
        } == true
        val hasSms = perms.contains(Manifest.permission.READ_SMS) ||
            perms.contains(Manifest.permission.RECEIVE_SMS) ||
            perms.contains(Manifest.permission.SEND_SMS)
        val hasOverlay = perms.contains(Manifest.permission.SYSTEM_ALERT_WINDOW)
        val hasMicOrCam = perms.contains(Manifest.permission.RECORD_AUDIO) ||
            perms.contains(Manifest.permission.CAMERA)
        val hasInstallPerm = perms.contains(Manifest.permission.REQUEST_INSTALL_PACKAGES)

        if (!hasA11y && !(hasInstallPerm && hasSms)) {
            return null
        }

        val installer = runCatching {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                pm.getInstallSourceInfo(pkg).installingPackageName ?: ""
            } else {
                @Suppress("DEPRECATION")
                pm.getInstallerPackageName(pkg) ?: ""
            }
        }.getOrDefault("").lowercase()
        val trustedStore = installer == "com.android.vending" ||
            installer == "com.sec.android.app.samsungapps" ||
            installer == "com.farsitel.bazaar" ||
            installer == "ir.mservices.market" ||
            installer == "com.xiaomi.market"

        if (!trustedStore && hasA11y && hasDeviceAdmin && (hasSms || hasOverlay || hasMicOrCam)) {
            return SignatureMatch(
                key = "malware:rat_behav:${pkgLower.hashCode()}",
                name = "$label (تروجان با دسترسی کامل)",
                category = "malware",
                severity = "critical",
                detail = "اپلیکیشن خارج از فروشگاه رسمی با ترکیب خطرناک دسترسی پذیری، مدیر دستگاه و پیامک/روکش صفحه (الگوی SpyNote/CraxsRAT) شناسایی شد.",
            )
        }

        val isA11yActive = enabledA11y.contains(pkgLower)
        if (!trustedStore && (isA11yActive || hasInstallPerm) && (hasSms || hasOverlay)) {
            val srcPath = app.sourceDir
            if (!srcPath.isNullOrBlank()) {
                val srcFile = File(srcPath)
                if (srcFile.exists() && srcFile.isFile) {
                    val lastUpd = pkgInfo.lastUpdateTime
                    val cached = apkDropperCache[pkg]
                    val hiddenDropper = if (cached != null && cached.first == lastUpd) {
                        cached.second
                    } else {
                        val detected = hasHiddenPayloadEntriesInApk(srcFile)
                        if (apkDropperCache.size >= MAX_LABEL_CACHE_ENTRIES) {
                            apkDropperCache.clear()
                        }
                        apkDropperCache[pkg] = lastUpd to detected
                        detected
                    }
                    if (hiddenDropper) {
                        return SignatureMatch(
                            key = "malware:apk_dropper:${pkgLower.hashCode()}",
                            name = "$label (دراپر بدافزار)",
                            category = "malware",
                            severity = "critical",
                            detail = "درون فایل نصبی این برنامه، پی لود مخفی .dex/.apk/.jar به همراه مجوزهای حساس شناسایی شد.",
                        )
                    }
                }
            }
        }
        return null
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
        if (lowerEntry.isBlank()) return false
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
                extStorage?.let { File(it, "Telegram/Telegram Images") },
                extStorage?.let { File(it, "Telegram/Telegram Video") },
                runCatching { Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_PICTURES) }.getOrNull(),
                runCatching { Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_MOVIES) }.getOrNull(),
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
                    !lower.startsWith(".trash")
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

    private data class SafDocumentEntry(
        val docUri: Uri,
        val name: String,
        val size: Long,
        val lastModified: Long,
    )

    private fun readSafSampleBytes(context: Context, docUri: Uri, limitBytes: Int = 2 * 1024 * 1024): ByteArray {
        return runCatching {
            context.contentResolver.openInputStream(docUri)?.use { input ->
                val out = ByteArrayOutputStream()
                val buf = ByteArray(16384)
                var remaining = limitBytes
                while (remaining > 0) {
                    val toRead = remaining.coerceAtMost(buf.size)
                    val r = input.read(buf, 0, toRead)
                    if (r <= 0) break
                    out.write(buf, 0, r)
                    remaining -= r
                }
                out.toByteArray()
            } ?: ByteArray(0)
        }.getOrDefault(ByteArray(0))
    }

    private fun readSafHeadAndTailBytes(
        context: Context,
        docUri: Uri,
        totalSize: Long,
        headBytes: Int = 256 * 1024,
        tailBytes: Int = 512 * 1024,
    ): ByteArray {
        if (totalSize <= 0L) return ByteArray(0)
        val maxCombined = headBytes.toLong() + tailBytes.toLong()
        if (totalSize <= maxCombined) {
            return readSafSampleBytes(context, docUri, totalSize.toInt())
        }
        return runCatching {
            context.contentResolver.openFileDescriptor(docUri, "r")?.use { pfd ->
                FileInputStream(pfd.fileDescriptor).use { fis ->
                    val channel = fis.channel
                    val head = ByteArray(headBytes)
                    val headLen = fis.read(head).coerceAtLeast(0)
                    channel.position(totalSize - tailBytes.toLong())
                    val tail = ByteArray(tailBytes)
                    var tailLen = 0
                    while (tailLen < tailBytes) {
                        val r = fis.read(tail, tailLen, tailBytes - tailLen)
                        if (r <= 0) break
                        tailLen += r
                    }
                    val combined = ByteArray(headLen + tailLen)
                    System.arraycopy(head, 0, combined, 0, headLen)
                    System.arraycopy(tail, 0, combined, headLen, tailLen)
                    combined
                }
            } ?: readSafSampleBytes(context, docUri, headBytes + tailBytes)
        }.getOrDefault(readSafSampleBytes(context, docUri, headBytes + tailBytes))
    }

    private fun safFileSha256(context: Context, docUri: Uri): String {
        return runCatching {
            val md = MessageDigest.getInstance("SHA-256")
            context.contentResolver.openInputStream(docUri)?.use { input ->
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

    private fun safDocumentExists(context: Context, docUri: Uri): Boolean {
        return runCatching {
            context.contentResolver.query(
                docUri,
                arrayOf(DocumentsContract.Document.COLUMN_DOCUMENT_ID),
                null,
                null,
                null,
            )?.use { it.moveToFirst() } == true
        }.getOrDefault(false)
    }

    private fun collectSafDocumentsBounded(
        context: Context,
        treeUri: Uri,
        docId: String,
        depth: Int,
        maxDepth: Int,
        maxFiles: Int,
        out: MutableList<SafDocumentEntry>,
    ) {
        if (out.size >= maxFiles || depth > maxDepth) return
        val childrenUri = DocumentsContract.buildChildDocumentsUriUsingTree(treeUri, docId)
        val projection = arrayOf(
            DocumentsContract.Document.COLUMN_DOCUMENT_ID,
            DocumentsContract.Document.COLUMN_DISPLAY_NAME,
            DocumentsContract.Document.COLUMN_MIME_TYPE,
            DocumentsContract.Document.COLUMN_SIZE,
            DocumentsContract.Document.COLUMN_LAST_MODIFIED,
        )
        val subdirs = mutableListOf<String>()
        runCatching {
            context.contentResolver.query(childrenUri, projection, null, null, null)?.use { cursor ->
                val idIdx = cursor.getColumnIndex(DocumentsContract.Document.COLUMN_DOCUMENT_ID)
                val nameIdx = cursor.getColumnIndex(DocumentsContract.Document.COLUMN_DISPLAY_NAME)
                val mimeIdx = cursor.getColumnIndex(DocumentsContract.Document.COLUMN_MIME_TYPE)
                val sizeIdx = cursor.getColumnIndex(DocumentsContract.Document.COLUMN_SIZE)
                val modIdx = cursor.getColumnIndex(DocumentsContract.Document.COLUMN_LAST_MODIFIED)
                while (cursor.moveToNext()) {
                    if (idIdx < 0) continue
                    val childId = cursor.getString(idIdx) ?: continue
                    val childName = if (nameIdx >= 0) cursor.getString(nameIdx) ?: "" else ""
                    val childMime = if (mimeIdx >= 0) cursor.getString(mimeIdx) ?: "" else ""
                    val childSize = if (sizeIdx >= 0 && !cursor.isNull(sizeIdx)) cursor.getLong(sizeIdx) else 0L
                    val childMod = if (modIdx >= 0 && !cursor.isNull(modIdx)) cursor.getLong(modIdx) else 0L
                    val lower = childName.lowercase()
                    if (childMime == DocumentsContract.Document.MIME_TYPE_DIR) {
                        if (depth < maxDepth &&
                            lower != ".git" &&
                            lower != "node_modules" &&
                            !lower.startsWith(".trash")
                        ) {
                            subdirs.add(childId)
                        }
                        continue
                    }
                    if (childName.isBlank()) continue
                    val childUri = DocumentsContract.buildDocumentUriUsingTree(treeUri, childId)
                    out.add(
                        SafDocumentEntry(
                            docUri = childUri,
                            name = childName,
                            size = childSize,
                            lastModified = childMod,
                        ),
                    )
                    if (out.size >= maxFiles) break
                }
            }
        }
        for (subId in subdirs) {
            if (out.size >= maxFiles) break
            collectSafDocumentsBounded(context, treeUri, subId, depth + 1, maxDepth, maxFiles, out)
        }
    }

    private fun inspectImageTailBuffer(sample: ByteArray, fname: String, lower: String): SignatureMatch? {
        if (lower.endsWith(".png")) {
            val iendSig = byteArrayOf(
                'I'.code.toByte(), 'E'.code.toByte(), 'N'.code.toByte(), 'D'.code.toByte(),
            )
            for (pos in (sample.size - 8) downTo 8) {
                if (sample[pos] == iendSig[0] && sample[pos + 1] == iendSig[1] &&
                    sample[pos + 2] == iendSig[2] && sample[pos + 3] == iendSig[3]
                ) {
                    val afterEof = pos + 8
                    if (afterEof < sample.size) {
                        var firstNz = afterEof
                        while (firstNz < sample.size && sample[firstNz] == 0.toByte()) firstNz++
                        if (sample.size - firstNz >= 16) {
                            val sub = sample.copyOfRange(firstNz, sample.size)
                            if (containsBinderOrPayloadBytes(sub, 0) ||
                                (sub.size >= 512 && shannonEntropy(sub) >= 7.35)
                            ) {
                                return SignatureMatch(
                                    key = "dl:png_eof:${lower.hashCode()}",
                                    name = "تصویر PNG با فایل بایندشده ($fname)",
                                    category = "malicious_download",
                                    severity = "critical",
                                    detail = "فایل اجرایی، آرشیو یا پی لود مخرب پس از IEND در تصویر PNG شناسایی شد.",
                                )
                            }
                        }
                    }
                    break
                }
            }
        } else if (lower.endsWith(".jpg") || lower.endsWith(".jpeg")) {
            for (pos in (sample.size - 2) downTo 12) {
                if (sample[pos] == 0xFF.toByte() && sample[pos + 1] == 0xD9.toByte()) {
                    var firstNz = pos + 2
                    while (firstNz < sample.size && sample[firstNz] == 0.toByte()) firstNz++
                    if (sample.size - firstNz >= 64) {
                        val sub = sample.copyOfRange(firstNz, sample.size)
                        if (!isSafeMotionPhotoTrailer(sub) &&
                            (containsBinderOrPayloadBytes(sub, 0) ||
                                (sub.size >= 1024 && shannonEntropy(sub) >= 7.45))
                        ) {
                            return SignatureMatch(
                                key = "dl:jpg_eoi:${lower.hashCode()}",
                                name = "تصویر JPEG با فایل بایندشده ($fname)",
                                category = "malicious_download",
                                severity = "critical",
                                detail = "فایل اجرایی، آرشیو یا بدافزار چسبیده به انتهای تصویر JPEG شناسایی شد.",
                            )
                        }
                    }
                    break
                }
            }
        }
        return null
    }

    private fun inspectDownloadedFile(context: Context, file: File, selfPkg: String): SignatureMatch? {
        val fname = file.name
        val lower = fname.lowercase()
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
            return inspectDownloadedApk(context, file, selfPkg)
        }
        if (lower.endsWith(".png") || lower.endsWith(".jpg") || lower.endsWith(".jpeg") ||
            lower.endsWith(".bmp") || lower.endsWith(".gif")
        ) {
            inspectImagePolyglotFile(file, fname, lower)?.let { return it }
        }
        return inspectDownloadedPayload(
            fname = fname,
            totalLength = file.length(),
            selfPkg = selfPkg,
            readHead = { readSampleBytes(file, 64 * 1024) },
            readSample = { limit -> readSampleBytes(file, limit) },
            readHeadAndTail = { head, tail -> readHeadAndTailBytes(file, head, tail) },
        )
    }

    private fun inspectSafDocument(context: Context, doc: SafDocumentEntry, selfPkg: String): SignatureMatch? {
        return inspectDownloadedPayload(
            fname = doc.name,
            totalLength = doc.size,
            selfPkg = selfPkg,
            readHead = { readSafSampleBytes(context, doc.docUri, 64 * 1024) },
            readSample = { limit -> readSafSampleBytes(context, doc.docUri, limit) },
            readHeadAndTail = { head, tail -> readSafHeadAndTailBytes(context, doc.docUri, doc.size, head, tail) },
        )
    }

    private fun inspectDownloadedPayload(
        fname: String,
        totalLength: Long,
        selfPkg: String,
        readHead: () -> ByteArray,
        readSample: (Int) -> ByteArray,
        readHeadAndTail: (Int, Int) -> ByteArray,
    ): SignatureMatch? {
        val lower = fname.lowercase()

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
            lower.endsWith(".sh") || lower.endsWith(".hta")

        val header = readHead()
        if (header.isEmpty()) return null

        val elfSig = byteArrayOf(0x7F, 'E'.code.toByte(), 'L'.code.toByte(), 'F'.code.toByte())
        val dexSig = "dex\n03".encodeToByteArray()

        if (lower.endsWith(".svg")) {
            val sample = if (totalLength in 1L..header.size.toLong()) header else readSample(2 * 1024 * 1024)
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
            val sample = if (validMagic && totalLength > 768L * 1024L) {
                readHeadAndTail(256 * 1024, 512 * 1024)
            } else if (totalLength in 1L..header.size.toLong()) {
                header
            } else {
                readSample(2 * 1024 * 1024)
            }

            if (!validMagic &&
                (hasPeHeaderAt(sample, 0) ||
                    containsBytes(sample, elfSig, 0) ||
                    containsBytes(sample, dexSig, 0) ||
                    containsAsciiCi(sample, "androidmanifest.xml") ||
                    containsAsciiCi(sample, "<script") ||
                    containsAsciiCi(sample, "frombase64string") ||
                    containsAsciiCi(sample, "basestart-") ||
                    containsAsciiCi(sample, "tvqqaam") ||
                    containsAsciiCi(sample, "dexclassloader") ||
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
                containsAsciiCi(sample, "wscript.shell") ||
                containsAsciiCi(sample, "frombase64string") ||
                containsAsciiCi(sample, "basestart-") ||
                containsAsciiCi(sample, "tvqqaam") ||
                containsAsciiCi(sample, "powershell -enc") ||
                containsAsciiCi(sample, "dexclassloader")
            ) {
                return SignatureMatch(
                    key = "dl:poly_img:${lower.hashCode()}",
                    name = "تصویر آلوده به پی لود تروجانی ($fname)",
                    category = "malicious_download",
                    severity = "critical",
                    detail = "کد اجرایی یا اسکریپت تروجانی پنهان شده داخل تصویر شناسایی شد.",
                )
            }
            if (validMagic) {
                inspectImageTailBuffer(sample, fname, lower)?.let { return it }
            }
            return null
        }

        if (isMedia) {
            val binaryHeader = hasPeHeaderAt(header, 0) ||
                containsBytes(header, elfSig, 0) ||
                containsBytes(header, dexSig, 0)
            val sample = if (!binaryHeader && totalLength > 768L * 1024L) {
                readHeadAndTail(256 * 1024, 512 * 1024)
            } else if (totalLength in 1L..header.size.toLong()) {
                header
            } else {
                readSample(768 * 1024)
            }
            var hasEmbeddedBinary = binaryHeader
            if (!hasEmbeddedBinary) {
                for (pos in 16 until (sample.size - 0x40).coerceAtLeast(16)) {
                    if ((sample[pos] == 0x4D.toByte() && sample[pos + 1] == 0x5A.toByte() &&
                            hasPeHeaderAt(sample, pos)) ||
                        (pos + 4 <= sample.size && sample[pos] == 0x7F.toByte() &&
                            sample[pos + 1] == 'E'.code.toByte() && sample[pos + 2] == 'L'.code.toByte() &&
                            sample[pos + 3] == 'F'.code.toByte()) ||
                        (pos + 7 <= sample.size && sample[pos] == 'R'.code.toByte() &&
                            sample[pos + 1] == 'a'.code.toByte() && sample[pos + 2] == 'r'.code.toByte() &&
                            sample[pos + 3] == '!'.code.toByte() && sample[pos + 4] == 0x1A.toByte() &&
                            sample[pos + 5] == 0x07.toByte())
                    ) {
                        hasEmbeddedBinary = true
                        break
                    }
                }
            }
            if (hasEmbeddedBinary ||
                containsBytes(sample, dexSig, 16) ||
                (containsAsciiCi(sample, "androidmanifest.xml") && containsAsciiCi(sample, "classes.dex")) ||
                containsAsciiCi(sample, "eicar-standard-antivirus-test-file") ||
                containsAsciiCi(sample, "<script") ||
                containsAsciiCi(sample, "frombase64string") ||
                containsAsciiCi(sample, "basestart-") ||
                containsAsciiCi(sample, "tvqqaam") ||
                containsAsciiCi(sample, "dexclassloader") ||
                containsAsciiCi(sample, "powershell -enc")
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

        val sample = if (totalLength in 1L..header.size.toLong()) {
            header
        } else if (isArchive || isOffice || lower.endsWith(".pdf")) {
            readSample(4 * 1024 * 1024)
        } else {
            readSample(2 * 1024 * 1024)
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
            if (lower.endsWith(".pdf")) {
                inspectPdfPayload(sample, fname, lower)?.let { return it }
            }
            if (hasPeHeaderAt(sample, 0) ||
                containsBytes(sample, elfSig, 0) ||
                containsBytes(sample, dexSig, 0) ||
                containsAsciiCi(sample, "eicar-standard-antivirus-test-file") ||
                containsAsciiCi(sample, "frombase64string") ||
                containsAsciiCi(sample, "basestart-")
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

        // Web/script downloads & phishing link payloads
        if (isScriptOrWeb) {
            if (hasPeHeaderAt(sample, 0) ||
                containsAsciiCi(sample, "eicar-standard-antivirus-test-file") ||
                containsAsciiCi(sample, "grabify.link") ||
                containsAsciiCi(sample, "iplogger.org") ||
                containsAsciiCi(sample, "iplogger.com") ||
                containsAsciiCi(sample, "2no.co") ||
                containsAsciiCi(sample, "blasze.com") ||
                (containsAsciiCi(sample, "frombase64string") &&
                    (containsAsciiCi(sample, "invoke-expression") || containsAsciiCi(sample, "iex("))) ||
                containsAsciiCi(sample, "eval(atob(") ||
                containsAsciiCi(sample, "wscript.shell") ||
                containsAsciiCi(sample, "urldownloadtofile") ||
                containsAsciiCi(sample, "basestart-") ||
                containsAsciiCi(sample, "tvqqaam")
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

        // Remaining / unknown / extensionless files & standalone executables
        val execByExt = lower.endsWith(".exe") || lower.endsWith(".scr") ||
            lower.endsWith(".msi") || lower.endsWith(".bat")
        if (execByExt ||
            hasPeHeaderAt(sample, 0) ||
            containsBytes(sample, elfSig, 0) ||
            containsBytes(sample, dexSig, 0) ||
            containsAsciiCi(sample, "eicar-standard-antivirus-test-file")
        ) {
            val hit = matchKnownPackageOrLabel(lower, lower, selfPkg)
            if (hit != null) {
                return hit.copy(
                    key = "${hit.key}:bin:${lower.hashCode()}",
                    category = if (hit.category == "conflicting_vpn") "conflicting_vpn" else "malicious_download",
                )
            }
            if (execByExt ||
                hasPeHeaderAt(sample, 0) ||
                containsAsciiCi(sample, "eicar-standard-antivirus-test-file")
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

    fun persistSafTreeUri(context: Context, treeUri: Uri, intentFlags: Int = 0) {
        val takeFlags = Intent.FLAG_GRANT_READ_URI_PERMISSION or
            (intentFlags and Intent.FLAG_GRANT_WRITE_URI_PERMISSION)
        runCatching {
            context.contentResolver.takePersistableUriPermission(
                treeUri,
                takeFlags or Intent.FLAG_GRANT_WRITE_URI_PERMISSION,
            )
        }.recoverCatching {
            context.contentResolver.takePersistableUriPermission(
                treeUri,
                Intent.FLAG_GRANT_READ_URI_PERMISSION,
            )
        }
    }

    fun invalidateAllCleanCache() {
        cleanFileCache.clear()
    }

    private fun hasSafTreeAccess(context: Context): Boolean {
        return runCatching {
            context.contentResolver.persistedUriPermissions.any { it.isReadPermission }
        }.getOrDefault(false)
    }

    private fun canOpenAllFilesSettings(context: Context): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) return false
        val appIntent = Intent(
            AndroidSettings.ACTION_MANAGE_APP_ALL_FILES_ACCESS_PERMISSION,
            Uri.fromParts("package", context.packageName, null),
        )
        if (appIntent.resolveActivity(context.packageManager) != null) return true
        val allIntent = Intent(AndroidSettings.ACTION_MANAGE_ALL_FILES_ACCESS_PERMISSION)
        return allIntent.resolveActivity(context.packageManager) != null
    }

    fun hasMediaScanAccess(context: Context): Boolean {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R && Environment.isExternalStorageManager()) {
            return true
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            return ContextCompat.checkSelfPermission(
                context,
                Manifest.permission.READ_MEDIA_IMAGES,
            ) == PackageManager.PERMISSION_GRANTED ||
                ContextCompat.checkSelfPermission(
                    context,
                    Manifest.permission.READ_MEDIA_VIDEO,
                ) == PackageManager.PERMISSION_GRANTED
        }
        return ContextCompat.checkSelfPermission(
            context,
            Manifest.permission.READ_EXTERNAL_STORAGE,
        ) == PackageManager.PERMISSION_GRANTED
    }

    fun hasStorageScanAccess(context: Context): Boolean {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            if (Environment.isExternalStorageManager()) {
                return true
            }
            return !canOpenAllFilesSettings(context) && hasSafTreeAccess(context)
        }
        val readGranted = ContextCompat.checkSelfPermission(
            context,
            Manifest.permission.READ_EXTERNAL_STORAGE,
        ) == PackageManager.PERMISSION_GRANTED
        val writeGranted = ContextCompat.checkSelfPermission(
            context,
            Manifest.permission.WRITE_EXTERNAL_STORAGE,
        ) == PackageManager.PERMISSION_GRANTED
        return readGranted && writeGranted
    }

    fun requestStorageScanAccess(activity: Activity): Boolean {
        if (hasStorageScanAccess(activity)) return true
        if (activity is MainActivity) {
            return activity.launchAllFilesAccessSettings()
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            val opened = runCatching {
                activity.startActivity(
                    Intent(
                        AndroidSettings.ACTION_MANAGE_APP_ALL_FILES_ACCESS_PERMISSION,
                        Uri.fromParts("package", activity.packageName, null),
                    ),
                )
                true
            }.recoverCatching {
                activity.startActivity(
                    Intent(AndroidSettings.ACTION_MANAGE_ALL_FILES_ACCESS_PERMISSION),
                )
                true
            }.getOrDefault(false)
            if (opened) return true
        } else {
            ActivityCompat.requestPermissions(
                activity,
                arrayOf(
                    Manifest.permission.READ_EXTERNAL_STORAGE,
                    Manifest.permission.WRITE_EXTERNAL_STORAGE,
                ),
                2006,
            )
            return true
        }
        return runCatching {
            val intent = Intent(Intent.ACTION_OPEN_DOCUMENT_TREE).addFlags(
                Intent.FLAG_GRANT_READ_URI_PERMISSION or
                    Intent.FLAG_GRANT_WRITE_URI_PERMISSION or
                    Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION,
            )
            activity.startActivity(intent)
            true
        }.getOrDefault(false)
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

        val enabledA11y = runCatching {
            AndroidSettings.Secure.getString(
                context.contentResolver,
                AndroidSettings.Secure.ENABLED_ACCESSIBILITY_SERVICES,
            ) ?: ""
        }.getOrDefault("").lowercase()

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
            val hit = matchKnownPackageOrLabel(app.packageName, label, selfPkg)
                ?: inspectInstalledAppBehavioralRisk(context, pm, app, label, enabledA11y)
                ?: continue
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
                if (fname.endsWith(".tmp") ||
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
                val hit = inspectDownloadedFile(context, file, selfPkg)
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

        // Scan user-approved Storage Access Framework (SAF) folders via DocumentsContract
        val safEntries = mutableListOf<SafDocumentEntry>()
        val safTrees = runCatching { context.contentResolver.persistedUriPermissions }.getOrDefault(emptyList())
        for (perm in safTrees) {
            if (!perm.isReadPermission) continue
            val rootDocId = runCatching { DocumentsContract.getTreeDocumentId(perm.uri) }.getOrNull() ?: continue
            collectSafDocumentsBounded(context, perm.uri, rootDocId, 0, dirMaxDepth, dirMaxFiles, safEntries)
            if (safEntries.size >= dirMaxFiles) break
        }
        for (doc in safEntries) {
            val uriStr = doc.docUri.toString()
            val uriLower = uriStr.lowercase()
            if (!visited.add(uriLower)) continue
            val fname = doc.name.lowercase()
            if (fname.endsWith(".tmp") ||
                fname.endsWith(".crdownload") ||
                fname.endsWith(".part")
            ) {
                continue
            }
            scannedFiles++
            if (isCleanFileCached(uriLower, doc.size, doc.lastModified)) {
                continue
            }
            val hit = inspectSafDocument(context, doc, selfPkg)
            if (hit == null) {
                recordCleanFileCache(uriLower, doc.size, doc.lastModified)
                continue
            }
            val sha = safFileSha256(context, doc.docUri)
            val findingKey = if (sha.isNotEmpty()) "${hit.key}:${sha.take(12)}" else hit.key
            val isAppPkg = hit.category == "conflicting_vpn"
            findings.putIfAbsent(
                findingKey,
                mutableMapOf(
                    "key" to findingKey,
                    "name" to hit.name,
                    "category" to hit.category,
                    "severity" to hit.severity,
                    "target" to doc.name,
                    "detail" to hit.detail,
                    "remediationKind" to "file",
                    "path" to uriStr,
                    "packageName" to "",
                    "sha256" to sha,
                    "active" to isAppPkg,
                    "signedValid" to false,
                    "blockedByPolicy" to true,
                ),
            )
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
            "mediaAccessGranted" to hasMediaScanAccess(context),
            "threats" to sortedThreats,
        )
    }

    fun deleteTargetInBackground(context: Context, path: String): Boolean {
        if (path.isBlank()) return false
        val deleted = if (path.startsWith("content://")) {
            val docUri = Uri.parse(path)
            runCatching {
                DocumentsContract.deleteDocument(context.contentResolver, docUri)
            }.getOrDefault(false)
        } else {
            val file = File(path)
            !file.exists() || runCatching { file.delete() }.getOrDefault(false)
        }
        invalidateCleanFileCache(path)
        return deleted
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
            if (path.startsWith("content://")) {
                val docUri = Uri.parse(path)
                val deleted = runCatching {
                    DocumentsContract.deleteDocument(activity.contentResolver, docUri)
                }.getOrDefault(false)
                if (deleted) {
                    actionTaken = true
                }
            } else {
                val file = File(path)
                if (file.exists() && file.delete()) {
                    actionTaken = true
                }
            }
        }
        invalidateCleanFileCache(path)

        if (packageName.isNotBlank() && packageName != activity.packageName) {
            if (isPackageInstalled(activity, packageName)) {
                val intent = Intent(
                    AndroidSettings.ACTION_APPLICATION_DETAILS_SETTINGS,
                    Uri.fromParts("package", packageName, null),
                ).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                runCatching {
                    activity.startActivity(intent)
                    actionTaken = true
                }
            }
        }

        if (remediationKind == "vpn_settings") {
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
            if (path.startsWith("content://")) {
                safDocumentExists(activity, Uri.parse(path))
            } else {
                File(path).exists()
            }
        } else if (remediationKind == "vpn_settings") {
            isOtherVpnTransportActive(activity)
        } else {
            false
        }

        val ok = !stillInstalled
        val message = when {
            ok -> "تهدید با موفقیت متوقف و حذف شد."
            packageName.isNotBlank() ->
                "صفحه تنظیمات برنامه باز شد؛ پس از تایید حذف برنامه، وضعیت امنیتی خودکار تایید می شود."
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
