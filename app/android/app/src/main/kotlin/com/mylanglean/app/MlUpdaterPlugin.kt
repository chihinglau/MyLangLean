package com.mylanglean.app

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.RandomAccessFile
import java.net.HttpURLConnection
import java.net.URL
import java.security.MessageDigest

/**
 * MyLangLean - Android OTA updater plugin.
 *
 * Channels:
 *   MethodChannel `ml/updater`         - `cancel` aborts the active download
 *   EventChannel  `ml/updater/events`  - listen with either the APK URL
 *                                        (String) or a map
 *                                        `{url, sha256?, id?}`; emits
 *                                        progress / installing /
 *                                        needPermission / error.
 *
 * Robustness:
 *   * every download runs under an independent monotonic session token, so a
 *     restart/cancel can never corrupt or interleave with a previous worker;
 *   * interrupted downloads resume with `Range` into a per-release `.part`
 *     file (`mll-update-<releaseId>.part`);
 *   * the finished file is SHA-256 verified before it replaces
 *     [APK_NAME] (which [MlUpdateFileProvider] serves to the installer).
 */
class MlUpdaterPlugin(
    private val activity: Activity,
    messenger: BinaryMessenger,
) {

    private val mainHandler = Handler(Looper.getMainLooper())

    /** Token of the currently active session; 0 means "no session". */
    @Volatile
    private var sessionId: Long = 0L

    @Volatile
    private var activeConn: HttpURLConnection? = null

    private var worker: Thread? = null
    private val lock = Any()

    init {
        MethodChannel(messenger, METHOD_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "cancel" -> {
                    cancelActive()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }

        EventChannel(messenger, EVENT_CHANNEL).setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    val sink = events ?: return
                    val spec = parseArguments(arguments)
                    if (spec == null) {
                        sink.error("BAD_URL", "下载地址为空", null)
                        return
                    }
                    start(spec, sink)
                }

                override fun onCancel(arguments: Any?) {
                    cancelActive()
                }
            }
        )
    }

    private data class DownloadSpec(
        val url: String,
        val expectedSha256: String?,
        val releaseKey: String?,
    )

    private fun parseArguments(arguments: Any?): DownloadSpec? = when (arguments) {
        is String -> arguments.takeIf { it.isNotBlank() }?.let {
            DownloadSpec(it, null, null)
        }
        is Map<*, *> -> {
            val url = arguments["url"]?.toString()?.takeIf { it.isNotBlank() }
                ?: return null
            val sha = arguments["sha256"]?.toString()
                ?.trim()?.lowercase()?.takeIf { it.length == 64 }
            val key = arguments["id"]?.toString()
                ?.filter { it.isLetterOrDigit() || it == '_' || it == '-' }
                ?.takeIf { it.isNotEmpty() }
            DownloadSpec(url, sha, key)
        }
        else -> null
    }

    private fun start(spec: DownloadSpec, sink: EventChannel.EventSink) {
        val old: Thread?
        val token: Long
        synchronized(lock) {
            // Detach the previous session before starting a new one.
            val prevId = sessionId
            sessionId = prevId + 1
            token = sessionId
            activeConn?.disconnect()
            old = worker
            worker = null

            val thread = Thread {
                runSession(token, spec, sink)
            }.apply { name = "mll-updater-$token" }
            worker = thread
            thread.start()
        }
        if (old != null && old !== Thread.currentThread()) {
            try {
                old.interrupt()
                old.join(1_500)
            } catch (_: InterruptedException) {
                Thread.currentThread().interrupt()
            }
        }
    }

    private fun cancelActive() {
        synchronized(lock) {
            if (sessionId != 0L) sessionId += 1
            activeConn?.disconnect()
            activeConn = null
            worker?.interrupt()
        }
    }

    private fun isActive(token: Long): Boolean = sessionId == token

    private fun runSession(
        token: Long,
        spec: DownloadSpec,
        sink: EventChannel.EventSink,
    ) {
        try {
            if (!ensureInstallPermission(token, sink)) return
            download(token, spec, sink)
            if (!isActive(token)) return
            launchInstaller(token, sink)
        } catch (e: InterruptedException) {
            postIfActive(token, sink) { it.error("CANCELLED", "已取消下载", null) }
        } catch (e: Exception) {
            if (isActive(token)) {
                postIfActive(token, sink) {
                    it.error("DOWNLOAD_FAILED", e.message ?: "下载失败", null)
                }
            }
        } finally {
            synchronized(lock) {
                if (sessionId == token) {
                    activeConn = null
                }
            }
        }
    }

    /** Returns false (and opens the OS settings once) when installation from
     *  unknown sources is not allowed yet. */
    private fun ensureInstallPermission(token: Long, sink: EventChannel.EventSink): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return true
        if (activity.packageManager.canRequestPackageInstalls()) return true
        postIfActive(token, sink) {
            try {
                val intent = Intent(
                    Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                    Uri.parse("package:${activity.packageName}"),
                ).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                activity.startActivity(intent)
            } catch (_: Exception) {
                // Some devices lack this settings screen; fall through and let
                // the installer raise its own prompt.
            }
            it.success(mapOf("status" to "needPermission"))
        }
        return false
    }

    private fun download(
        token: Long,
        spec: DownloadSpec,
        sink: EventChannel.EventSink,
    ) {
        val partName = "mll-update-${spec.releaseKey ?: token}.part"
        val partFile = File(activity.cacheDir, partName)
        val finalFile = File(activity.cacheDir, APK_NAME)
        partFile.parentFile?.mkdirs()

        var conn: HttpURLConnection? = null
        try {
            val existing = if (partFile.exists()) partFile.length() else 0L
            conn = openConnection(spec.url, existing)
            synchronized(lock) {
                if (isActive(token)) activeConn = conn
            }
            val code = conn.responseCode
            val append: Boolean
            when (code) {
                HttpURLConnection.HTTP_OK -> {
                    // Server/restart ignored the Range request: start fresh.
                    partFile.delete()
                    append = false
                }
                HttpURLConnection.HTTP_PARTIAL -> {
                    if (existing <= 0L) {
                        // 206 without anything to resume makes no sense.
                        partFile.delete()
                        throw IllegalStateException("服务器异常返回 206")
                    }
                    val start = parseRangeStart(conn.getHeaderField("Content-Range"))
                    if (start != null && start != existing) {
                        partFile.delete()
                        throw IllegalStateException("续传区间不匹配，请重试")
                    }
                    append = true
                }
                in 200..299 -> throw IllegalStateException("服务器返回 HTTP $code")
                else -> throw IllegalStateException("服务器返回 HTTP $code")
            }

            val bodyLength = conn.contentLengthLong.coerceAtLeast(0L)
            val total = if (append && bodyLength > 0L) existing + bodyLength else bodyLength

            var received = if (append) existing else 0L
            var lastEmit = 0L
            conn.inputStream.use { input ->
                RandomAccessFile(partFile, "rw").use { raf ->
                    raf.seek(if (append) existing else 0L)
                    val buffer = ByteArray(64 * 1024)
                    while (true) {
                        if (!isActive(token) || Thread.currentThread().isInterrupted) {
                            throw InterruptedException("cancelled")
                        }
                        val n = input.read(buffer)
                        if (n <= 0) break
                        raf.write(buffer, 0, n)
                        received += n
                        val now = System.currentTimeMillis()
                        if (now - lastEmit > 250 || (total > 0 && received == total)) {
                            lastEmit = now
                            val snapshotReceived = received
                            val snapshotTotal = total
                            postIfActive(token, sink) {
                                it.success(
                                    mapOf(
                                        "status" to "progress",
                                        "received" to snapshotReceived,
                                        "total" to snapshotTotal,
                                    )
                                )
                            }
                        }
                    }
                    raf.fd.sync()
                }
            }

            if (total > 0 && partFile.length() != total) {
                partFile.delete()
                throw IllegalStateException("下载文件不完整（${partFile.length()}/$total 字节）")
            }

            // Integrity gate: never hand a corrupt/truncated APK to installer.
            spec.expectedSha256?.let { expected ->
                val actual = sha256Hex(partFile)
                if (!actual.equals(expected, ignoreCase = true)) {
                    partFile.delete()
                    throw IllegalStateException("安装包校验失败（SHA-256 不一致），请重新下载")
                }
            }

            if (finalFile.exists()) finalFile.delete()
            if (!partFile.renameTo(finalFile)) {
                partFile.copyTo(finalFile, overwrite = true)
                partFile.delete()
            }
        } finally {
            conn?.disconnect()
            synchronized(lock) {
                if (activeConn === conn) activeConn = null
            }
        }
    }

    private fun openConnection(rawUrl: String, resumeFrom: Long): HttpURLConnection {
        val conn = URL(rawUrl).openConnection() as HttpURLConnection
        conn.connectTimeout = 15_000
        conn.readTimeout = 30_000
        conn.instanceFollowRedirects = true
        conn.setRequestProperty("Accept", "application/vnd.android.package-archive,*/*")
        if (resumeFrom > 0L) {
            conn.setRequestProperty("Range", "bytes=$resumeFrom-")
        }
        return conn
    }

    /** Parses `bytes <start>-<end>/<total>`; tolerant of missing fields. */
    private fun parseRangeStart(header: String?): Long? {
        if (header == null) return null
        val marker = "bytes "
        val idx = header.indexOf(marker)
        if (idx < 0) return null
        val rest = header.substring(idx + marker.length)
        val startPart = rest.substringBefore('-', "").trim()
        return startPart.toLongOrNull()
    }

    private fun sha256Hex(file: File): String {
        val digest = MessageDigest.getInstance("SHA-256")
        file.inputStream().use { input ->
            val buffer = ByteArray(256 * 1024)
            while (true) {
                val n = input.read(buffer)
                if (n <= 0) break
                digest.update(buffer, 0, n)
            }
        }
        return digest.digest().joinToString("") { "%02x".format(it) }
    }

    private fun launchInstaller(token: Long, sink: EventChannel.EventSink) {
        val file = File(activity.cacheDir, APK_NAME)
        if (!file.exists()) throw IllegalStateException("安装包下载后丢失")
        postIfActive(token, sink) {
            val uri = Uri.parse("content://${activity.packageName}.updatefile/apk")
            val intent = Intent(Intent.ACTION_VIEW).apply {
                setDataAndType(uri, MlUpdateFileProvider.APK_MIME)
                addFlags(
                    Intent.FLAG_ACTIVITY_NEW_TASK or
                        Intent.FLAG_GRANT_READ_URI_PERMISSION
                )
            }
            it.success(mapOf("status" to "installing"))
            try {
                activity.startActivity(intent)
                it.endOfStream()
            } catch (e: Exception) {
                it.error("NO_INSTALLER", "未找到可安装 APK 的应用", null)
            }
        }
    }

    private fun postIfActive(
        token: Long,
        sink: EventChannel.EventSink,
        block: (EventChannel.EventSink) -> Unit,
    ) {
        mainHandler.post {
            if (isActive(token)) block(sink)
        }
    }

    companion object {
        const val METHOD_CHANNEL = "ml/updater"
        const val EVENT_CHANNEL = "ml/updater/events"
        const val APK_NAME = "mll-update.apk"
    }
}
