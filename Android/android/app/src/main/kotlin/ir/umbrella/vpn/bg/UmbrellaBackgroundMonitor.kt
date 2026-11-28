package ir.umbrella.vpn.bg

import android.Manifest
import android.app.job.JobInfo
import android.app.job.JobParameters
import android.app.job.JobScheduler
import android.app.job.JobService
import android.content.ComponentName
import android.content.Context
import android.content.pm.PackageManager
import android.database.ContentObserver
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.MediaStore
import android.util.Log
import androidx.core.content.ContextCompat
import ir.umbrella.vpn.Settings
import ir.umbrella.vpn.UmbrellaApplication
import ir.umbrella.vpn.UmbrellaSecurityScanner
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import org.json.JSONArray
import org.json.JSONObject
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.Executors
import java.util.concurrent.ScheduledFuture
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean

object UmbrellaBackgroundMonitor {
    private const val TAG = "UmbrellaBgSecurity"
    private const val JOB_ID = 4107
    private const val PERIODIC_INTERVAL_MS = 15L * 60L * 1000L
    private const val COOLDOWN_MS = 10L * 60L * 1000L
    private const val MAX_QUEUED_EVENTS = 30

    private val initialized = AtomicBoolean(false)
    private val scanningNow = AtomicBoolean(false)
    private val scheduler = Executors.newSingleThreadScheduledExecutor()
    private val recentNotifiedKeys = ConcurrentHashMap<String, Long>()
    private val httpClient by lazy {
        OkHttpClient.Builder()
            .connectTimeout(10, TimeUnit.SECONDS)
            .readTimeout(12, TimeUnit.SECONDS)
            .writeTimeout(10, TimeUnit.SECONDS)
            .build()
    }

    @Volatile
    private var debouncedFuture: ScheduledFuture<*>? = null

    @Volatile
    private var mediaObserverRegistered = false

    fun initialize(context: Context) {
        val appCtx = context.applicationContext
        schedulePeriodicJob(appCtx)
        if (!initialized.compareAndSet(false, true)) {
            return
        }
        registerMediaObservers(appCtx)
        runCatching {
            UmbrellaSecurityScanner.startFileObservers { _ ->
                triggerDebouncedQuickScan(appCtx)
            }
        }
        triggerDebouncedQuickScan(appCtx, delayMs = 2_000L)
    }

    fun schedulePeriodicJob(context: Context) {
        runCatching {
            val js = context.getSystemService(Context.JOB_SCHEDULER_SERVICE) as? JobScheduler
                ?: return
            val existing = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                js.getPendingJob(JOB_ID)
            } else {
                js.allPendingJobs.firstOrNull { it.id == JOB_ID }
            }
            if (existing != null) return

            val builder = JobInfo.Builder(
                JOB_ID,
                ComponentName(context, UmbrellaSecurityJobService::class.java),
            )
                .setPeriodic(PERIODIC_INTERVAL_MS)
                .setRequiresBatteryNotLow(false)
                .setRequiresDeviceIdle(false)

            val hasBootPerm = ContextCompat.checkSelfPermission(
                context,
                Manifest.permission.RECEIVE_BOOT_COMPLETED,
            ) == PackageManager.PERMISSION_GRANTED
            if (hasBootPerm) {
                builder.setPersisted(true)
            }
            js.schedule(builder.build())
        }.onFailure { err ->
            Log.w(TAG, "schedulePeriodicJob failed: ${err.message}")
        }
    }

    private fun registerMediaObservers(context: Context) {
        if (mediaObserverRegistered) return
        val handler = Handler(Looper.getMainLooper())
        val observer = object : ContentObserver(handler) {
            override fun onChange(selfChange: Boolean, uri: Uri?) {
                triggerDebouncedQuickScan(context, delayMs = 600L)
            }
        }
        val uris = buildList<Uri> {
            add(MediaStore.Images.Media.EXTERNAL_CONTENT_URI)
            add(MediaStore.Video.Media.EXTERNAL_CONTENT_URI)
            add(MediaStore.Audio.Media.EXTERNAL_CONTENT_URI)
            add(MediaStore.Files.getContentUri("external"))
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                add(MediaStore.Downloads.EXTERNAL_CONTENT_URI)
            }
        }
        var registeredCount = 0
        for (uri in uris) {
            val ok = runCatching {
                context.contentResolver.registerContentObserver(uri, true, observer)
                true
            }.getOrDefault(false)
            if (ok) registeredCount++
        }
        mediaObserverRegistered = registeredCount > 0
    }

    fun triggerDebouncedQuickScan(context: Context, delayMs: Long = 500L) {
        val appCtx = context.applicationContext
        synchronized(this) {
            debouncedFuture?.cancel(false)
            debouncedFuture = scheduler.schedule(
                { runCatching { runBackgroundPass(appCtx, quick = true) } },
                delayMs.coerceAtLeast(100L),
                TimeUnit.MILLISECONDS,
            )
        }
    }

    fun runBackgroundPass(context: Context, quick: Boolean = true) {
        if (!scanningNow.compareAndSet(false, true)) return
        try {
            val result = UmbrellaSecurityScanner.scan(context, quick = quick)
            @Suppress("UNCHECKED_CAST")
            val rawThreats = (result["threats"] as? List<Map<String, Any>>) ?: emptyList()
            val remainingThreats = mutableListOf<Map<String, Any>>()
            val neutralizedBatch = mutableListOf<Map<String, Any>>()
            val now = System.currentTimeMillis()

            for (threat in rawThreats) {
                val key = threat["key"]?.toString() ?: continue
                val name = threat["name"]?.toString() ?: key
                val category = threat["category"]?.toString() ?: "suspicious"
                val severity = threat["severity"]?.toString() ?: "high"
                val target = threat["target"]?.toString() ?: ""
                val detail = threat["detail"]?.toString() ?: ""
                val kind = threat["remediationKind"]?.toString() ?: ""
                val path = threat["path"]?.toString() ?: ""

                val autoRemediable = kind == "file" &&
                    path.isNotBlank() &&
                    (category == "malicious_download" || category == "malware")
                if (autoRemediable && UmbrellaSecurityScanner.deleteTargetInBackground(context, path)) {
                    val event = linkedMapOf<String, Any>(
                        "key" to key,
                        "name" to name,
                        "category" to category,
                        "severity" to severity,
                        "target" to target.ifBlank { path },
                        "detail" to detail.ifBlank {
                            "فایل دانلودی مخرب پیش از باز شدن شناسایی و به صورت خودکار حذف شد."
                        },
                        "action" to "deleted",
                        "timestampMs" to now,
                    )
                    neutralizedBatch.add(event)
                    ServiceNotification.showSecurityThreatBalloon(
                        context = context,
                        title = "سپر امنیتی آمبرلا: فایل مخرب حذف شد",
                        body = "$name بلافاصله شناسایی و پاکسازی شد.",
                    )
                    continue
                }
                remainingThreats.add(threat)
            }

            val scannedFiles = (result["scannedFiles"] as? Number)?.toInt() ?: 0
            val scannedApps = (result["scannedApps"] as? Number)?.toInt() ?: 0
            val scannedProcesses = (result["scannedProcesses"] as? Number)?.toInt() ?: 0
            val scannedAtMs = (result["scannedAtMs"] as? Number)?.toLong() ?: now
            val securityStatus = if (remainingThreats.isEmpty()) "safe" else "warning"

            var shouldSync = neutralizedBatch.isNotEmpty()
            for (threat in remainingThreats) {
                val key = threat["key"]?.toString() ?: continue
                val lastAt = recentNotifiedKeys[key] ?: 0L
                if (now - lastAt >= COOLDOWN_MS) {
                    recentNotifiedKeys[key] = now
                    shouldSync = true
                }
            }

            val synced = if (shouldSync) {
                postBackgroundSecurityAlert(
                    threats = remainingThreats,
                    neutralized = neutralizedBatch,
                    securityStatus = securityStatus,
                    scannedAtMs = scannedAtMs,
                    scannedFiles = scannedFiles,
                    scannedApps = scannedApps,
                    scannedProcesses = scannedProcesses,
                )
            } else {
                false
            }

            if (neutralizedBatch.isNotEmpty()) {
                enqueuePendingEvents(neutralizedBatch, synced = synced)
            }
        } catch (err: Exception) {
            Log.w(TAG, "runBackgroundPass failed: ${err.message}")
        } finally {
            scanningNow.set(false)
        }
    }

    private fun postBackgroundSecurityAlert(
        threats: List<Map<String, Any>>,
        neutralized: List<Map<String, Any>>,
        securityStatus: String,
        scannedAtMs: Long,
        scannedFiles: Int,
        scannedApps: Int,
        scannedProcesses: Int,
    ): Boolean {
        val base = Settings.bgGatewayBase.trimEnd('/')
        val token = Settings.bgAuthToken
        if (base.isBlank() || token.isBlank()) return false

        return runCatching {
            val payload = JSONObject().apply {
                put("token", token)
                put("device_id", Settings.bgDeviceId)
                put("platform", "Android")
                put("app_version", Settings.bgAppVersion.ifBlank { "1.0.0" })
                put("sync_all", true)
                put("security_status", securityStatus)
                put("scanned_at_ms", scannedAtMs)
                put("scanned_files", scannedFiles)
                put("scanned_apps", scannedApps)
                put("scanned_processes", scannedProcesses)

                val threatsArr = JSONArray()
                for (t in threats) {
                    threatsArr.put(
                        JSONObject().apply {
                            put("key", t["key"] ?: "")
                            put("name", t["name"] ?: "")
                            put("category", t["category"] ?: "suspicious")
                            put("severity", t["severity"] ?: "high")
                            put("target", t["target"] ?: "")
                        },
                    )
                }
                put("threats", threatsArr)

                if (neutralized.isNotEmpty()) {
                    val neutArr = JSONArray()
                    for (n in neutralized) {
                        neutArr.put(
                            JSONObject().apply {
                                put("key", n["key"] ?: "")
                                put("name", n["name"] ?: "")
                                put("category", n["category"] ?: "malicious_download")
                                put("severity", n["severity"] ?: "critical")
                                put("action", n["action"] ?: "deleted")
                                put("target", n["target"] ?: "")
                                put("detail", n["detail"] ?: "")
                            },
                        )
                    }
                    put("neutralized", neutArr)
                }
            }

            val route = "app/security-alert"
            val parsed = Uri.parse(base)
            val url = if (base.contains("?")) {
                val builder = parsed.buildUpon().clearQuery()
                for (name in parsed.queryParameterNames) {
                    if (name == "AppApi") continue
                    for (value in parsed.getQueryParameters(name)) {
                        builder.appendQueryParameter(name, value)
                    }
                }
                builder.appendQueryParameter("AppApi", route).build().toString()
            } else {
                "$base/$route"
            }
            val appVer = Settings.bgAppVersion.ifBlank { "1.0.2" }
            val req = Request.Builder()
                .url(url)
                .header("Accept", "application/json, text/plain, */*")
                .header("Cache-Control", "no-cache")
                .header("User-Agent", "Mozilla/5.0 (Linux; Android 14) UmbrellaVPN/$appVer")
                .header("X-Umbrella-Client", "Android/$appVer")
                .post(payload.toString().toRequestBody("application/json; charset=utf-8".toMediaType()))
                .build()
            httpClient.newCall(req).execute().use { resp ->
                resp.isSuccessful
            }
        }.getOrDefault(false)
    }

    @Synchronized
    private fun enqueuePendingEvents(events: List<Map<String, Any>>, synced: Boolean) {
        val current = runCatching {
            val raw = Settings.pendingBgSecurityEventsJson
            if (raw.isBlank()) JSONArray() else JSONArray(raw)
        }.getOrElse { JSONArray() }

        for (ev in events) {
            current.put(
                JSONObject().apply {
                    put("key", ev["key"] ?: "")
                    put("name", ev["name"] ?: "")
                    put("category", ev["category"] ?: "malicious_download")
                    put("severity", ev["severity"] ?: "critical")
                    put("target", ev["target"] ?: "")
                    put("detail", ev["detail"] ?: "")
                    put("action", ev["action"] ?: "deleted")
                    put("timestampMs", ev["timestampMs"] ?: System.currentTimeMillis())
                    put("synced", synced)
                },
            )
        }
        val trimmed = JSONArray()
        val startIdx = (current.length() - MAX_QUEUED_EVENTS).coerceAtLeast(0)
        for (i in startIdx until current.length()) {
            trimmed.put(current.get(i))
        }
        Settings.pendingBgSecurityEventsJson = trimmed.toString()
    }

    @Synchronized
    fun consumePendingEvents(): List<Map<String, Any>> {
        val raw = Settings.pendingBgSecurityEventsJson
        if (raw.isBlank()) return emptyList()
        Settings.pendingBgSecurityEventsJson = ""
        return runCatching {
            val arr = JSONArray(raw)
            val out = mutableListOf<Map<String, Any>>()
            for (i in 0 until arr.length()) {
                val obj = arr.optJSONObject(i) ?: continue
                out.add(
                    mapOf(
                        "key" to obj.optString("key"),
                        "name" to obj.optString("name"),
                        "category" to obj.optString("category", "malicious_download"),
                        "severity" to obj.optString("severity", "critical"),
                        "target" to obj.optString("target"),
                        "detail" to obj.optString("detail"),
                        "action" to obj.optString("action", "deleted"),
                        "timestampMs" to obj.optLong("timestampMs", 0L),
                        "synced" to obj.optBoolean("synced", false),
                    ),
                )
            }
            out
        }.getOrDefault(emptyList())
    }
}

class UmbrellaSecurityJobService : JobService() {
    override fun onStartJob(params: JobParameters?): Boolean {
        val ctx = applicationContext
        UmbrellaApplication.initialize(ctx)
        Thread {
            try {
                UmbrellaBackgroundMonitor.runBackgroundPass(ctx, quick = false)
            } finally {
                jobFinished(params, false)
            }
        }.start()
        return true
    }

    override fun onStopJob(params: JobParameters?): Boolean = true
}
