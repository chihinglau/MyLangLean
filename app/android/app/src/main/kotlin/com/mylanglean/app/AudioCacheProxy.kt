package com.mylanglean.app

import android.content.Context
import java.io.BufferedReader
import java.io.File
import java.io.InputStreamReader
import java.io.RandomAccessFile
import java.net.HttpURLConnection
import java.net.ServerSocket
import java.net.URL
import java.net.URLDecoder
import java.net.URLEncoder
import java.security.MessageDigest
import java.util.concurrent.ConcurrentHashMap

/**
 * Local "stream-and-cache" HTTP proxy for remote podcast audio.
 *
 * MediaPlayer loads `http://127.0.0.1:<port>/<encoded-url>`; the proxy serves
 * bytes from a per-URL cache file under filesDir/audio-cache. The first client
 * triggers a single background downloader that fills the file sequentially;
 * clients read cached bytes as they grow, so playback streams immediately
 * while the episode is persisted. Re-entering the player / replaying then
 * prepares instantly from disk instead of re-downloading from the CDN.
 *
 * Features: Range requests (seeks), resume across app restarts, direct
 * upstream passthrough for seeks past the downloaded prefix, LRU eviction.
 * No third-party dependencies.
 */
class AudioCacheProxy private constructor(context: Context) {

    private val cacheDir = File(context.filesDir, "audio-cache").apply { mkdirs() }
    private val activeKeys = ConcurrentHashMap.newKeySet<String>()
    private val entries = ConcurrentHashMap<String, Entry>()
    private val listeners = java.util.Collections.newSetFromMap(
        java.util.concurrent.ConcurrentHashMap<ProgressListener, Boolean>())
    @Volatile private var port = 0

    init {
        // Recover previously completed/partial caches.
        cacheDir.listFiles()?.filter { it.name.endsWith(SUFFIX_DONE) }?.forEach { f ->
            val key = f.name.removeSuffix(SUFFIX_DONE)
            val meta = File(cacheDir, "$key$SUFFIX_META")
            val total = meta.takeIf { it.exists() }?.readText()?.toLongOrNull() ?: -1L
            entries[key] = Entry(key, total = total, cached = f.length(), complete = true)
        }
        cacheDir.listFiles()?.filter { it.name.endsWith(SUFFIX_PART) }?.forEach { f ->
            val key = f.name.removeSuffix(SUFFIX_PART)
            entries.putIfAbsent(key, Entry(key, cached = f.length()))
        }

        val socket = ServerSocket(0, 32, java.net.InetAddress.getByName("127.0.0.1"))
        port = socket.localPort
        Thread({
            while (true) {
                val client = try {
                    socket.accept()
                } catch (_: Exception) {
                    break
                }
                Thread({
                    try {
                        handle(client)
                    } catch (_: Throwable) {
                        try { client.close() } catch (_: Exception) {}
                    }
                }, "audio-cache-conn").start()
            }
        }, "audio-cache-proxy").start()
    }

    /** Rewrites a remote http(s) URL to the local caching proxy URL. */
    fun proxyFor(url: String): String =
        "http://127.0.0.1:$port/${URLEncoder.encode(url, "UTF-8")}"

    // ------------------------------------------------------------------
    // Explicit download management (UI-driven)
    // ------------------------------------------------------------------

    /** Snapshot status: state none | downloading | downloaded | failed. */
    fun statusOf(url: String): Map<String, Any> {
        val entry = entries[keyOf(url)]
        val state = when {
            entry == null -> "none"
            entry.complete -> "downloaded"
            entry.failed -> "failed"
            entry.downloading -> "downloading"
            // A recovered .part with no active worker this session: offer
            // it as downloadable again (start resumes at the prefix).
            else -> "none"
        }
        return mapOf(
            "state" to state,
            "cached" to (entry?.cached ?: 0L),
            "total" to (entry?.total ?: -1L),
        )
    }

    /** Begin downloading [url] without playback. Idempotent. */
    fun startDownload(url: String) {
        val entry = entries.computeIfAbsent(keyOf(url)) { Entry(it) }
        if (entry.complete || entry.downloading) return
        entry.failed = false
        entry.cancelled = false
        ensureDownloading(entry, url)
    }

    /** Delete a downloaded episode or abort an in-progress download. */
    fun deleteDownload(url: String) {
        val key = keyOf(url)
        val entry = entries.remove(key)
        if (entry != null) {
            entry.cancelled = true
            synchronized(entry.lock) { entry.lock.notifyAll() }
        }
        File(cacheDir, "$key$SUFFIX_PART").delete()
        File(cacheDir, "$key$SUFFIX_DONE").delete()
        File(cacheDir, "$key$SUFFIX_META").delete()
    }

    fun addListener(l: ProgressListener) { listeners.add(l) }
    fun removeListener(l: ProgressListener) { listeners.remove(l) }

    private fun emit(entry: Entry, state: String) {
        if (entry.srcUrl.isEmpty()) return
        listeners.forEach {
            it.onProgress(entry.srcUrl, entry.cached, entry.total, state)
        }
    }

    interface ProgressListener {
        fun onProgress(url: String, cached: Long, total: Long, state: String)
    }

    private class CancelledDownload : Exception()

    // ------------------------------------------------------------------
    // Request handling
    // ------------------------------------------------------------------

    private fun handle(client: java.net.Socket) {
        val reader = BufferedReader(InputStreamReader(client.getInputStream()))
        val requestLine = reader.readLine() ?: run { client.close(); return }
        val parts = requestLine.split(" ")
        if (parts.size < 3 || parts[0] !in listOf("GET", "HEAD")) {
            client.close(); return
        }
        val method = parts[0]
        val targetUrl = URLDecoder.decode(parts[1].removePrefix("/"), "UTF-8")
        if (!targetUrl.startsWith("http")) { client.close(); return }

        val headers = HashMap<String, String>()
        while (true) {
            val line = reader.readLine()
            if (line.isNullOrEmpty()) break
            val idx = line.indexOf(':')
            if (idx > 0) headers[line.substring(0, idx).trim().lowercase()] =
                line.substring(idx + 1).trim()
        }

        val key = keyOf(targetUrl)
        activeKeys.add(key)
        try {
            val entry = entries.computeIfAbsent(key) { Entry(key) }
            entry.srcUrl = targetUrl
            ensureDownloading(entry, targetUrl)

            val range = headers["range"]?.let { parseRange(it) }

            if (method == "HEAD") {
                writeHead(out = client.getOutputStream(), entry = entry, range = range)
                return
            }

            if (range != null && range.first >= entry.cached && !entry.complete) {
                // Seek far ahead of the sequential downloader: fetch that
                // window straight from upstream (responsive seeking).
                servePassthrough(client, targetUrl, range.first, range.second)
            } else {
                serveFromCache(client, entry, range)
            }
        } finally {
            activeKeys.remove(key)
        }
    }

    /** Streams bytes from the cache file, blocking until downloaded. */
    private fun serveFromCache(
        client: java.net.Socket, entry: Entry, range: Pair<Long, Long>?,
    ) {
        // Wait briefly for total length so the response carries Content-Length.
        if (entry.total < 0) {
            synchronized(entry.lock) {
                var waited = 0
                while (entry.total < 0 && !entry.failed && !entry.cancelled && waited < 5000) {
                    entry.lock.wait(100); waited += 100
                }
            }
        }
        val total = entry.total
        val start = range?.first ?: 0L
        val end = when {
            range?.second != null && range.second >= 0 -> range.second
            total >= 0 -> total - 1
            else -> Long.MAX_VALUE
        }
        if (total >= 0 && (start >= total || end < start)) {
            client.close(); return
        }

        val os = client.getOutputStream()
        val header = StringBuilder()
        if (range == null) {
            header.append("HTTP/1.1 200 OK\r\n")
            if (total >= 0) header.append("Content-Length: $total\r\n")
        } else {
            header.append("HTTP/1.1 206 Partial Content\r\n")
            if (total >= 0) {
                header.append("Content-Range: bytes $start-$end/$total\r\n")
                header.append("Content-Length: ${end - start + 1}\r\n")
            }
        }
        header.append("Content-Type: audio/mpeg\r\nAccept-Ranges: bytes\r\n\r\n")
        os.write(header.toString().toByteArray())

        val file = if (entry.complete) entry.doneFile() else entry.partFile()
        if (!file.exists()) { os.flush(); client.close(); return }
        RandomAccessFile(file, "r").use { raf ->
            var pos = start
            val buf = ByteArray(64 * 1024)
            while (pos <= end) {
                var available: Long
                synchronized(entry.lock) {
                    var waited = 0
                    while (entry.cached <= pos && !entry.complete && !entry.failed &&
                        !entry.cancelled && waited < 60_000) {
                        entry.lock.wait(1000); waited += 1000
                    }
                    available = minOf(entry.cached, end + 1) - pos
                }
                if (available <= 0) {
                    if (entry.complete || entry.failed || entry.cancelled) break
                    synchronized(entry.lock) { entry.lock.wait(5_000) }
                    continue
                }
                raf.seek(pos)
                var toRead = minOf(available, buf.size.toLong()).toInt()
                var read = 0
                while (read < toRead) {
                    val n = raf.read(buf, read, toRead - read)
                    if (n < 0) break
                    read += n
                }
                os.write(buf, 0, read)
                os.flush()
                pos += read
            }
        }
        os.flush()
        client.close()
    }

    /** Direct ranged fetch from upstream (seek beyond cached prefix). */
    private fun servePassthrough(
        client: java.net.Socket, url: String, start: Long, end: Long,
    ) {
        val conn = (URL(url).openConnection() as HttpURLConnection).apply {
            connectTimeout = 15_000
            readTimeout = 45_000
            setRequestProperty("User-Agent", UA)
            setRequestProperty(
                "Range",
                "bytes=$start-" + if (end >= 0) end.toString() else "",
            )
        }
        val code = conn.responseCode
        val os = client.getOutputStream()
        os.write(
            ("HTTP/1.1 ${if (code == 206) "206 Partial Content" else "200 OK"}\r\n" +
                "Content-Type: audio/mpeg\r\nAccept-Ranges: bytes\r\n\r\n")
                .toByteArray())
        conn.inputStream.use { input ->
            val buf = ByteArray(64 * 1024)
            while (true) {
                val n = input.read(buf)
                if (n < 0) break
                os.write(buf, 0, n); os.flush()
            }
        }
        os.flush()
        client.close()
    }

    private fun writeHead(
        out: java.io.OutputStream, entry: Entry, range: Pair<Long, Long>?,
    ) {
        val total = entry.total
        val sb = StringBuilder("HTTP/1.1 200 OK\r\nContent-Type: audio/mpeg\r\nAccept-Ranges: bytes\r\n")
        if (total >= 0) sb.append("Content-Length: $total\r\n")
        sb.append("\r\n")
        out.write(sb.toString().toByteArray()); out.flush()
    }

    // ------------------------------------------------------------------
    // Background sequential downloader
    // ------------------------------------------------------------------

    private fun ensureDownloading(entry: Entry, url: String) {
        if (entry.complete) return
        synchronized(entry) {
            if (entry.downloading) return
            entry.downloading = true
        }
        entry.srcUrl = url
        emit(entry, "downloading")
        Thread({
            var attempts = 0
            var gaveUp = false
            try {
                while (!entry.complete && !entry.cancelled) {
                    try {
                        downloadOnce(entry, url)
                    } catch (_: CancelledDownload) {
                        break
                    } catch (e: Throwable) {
                        if (entry.cancelled) break
                        android.util.Log.w(TAG, "download attempt ${attempts + 1} failed: $e")
                        attempts++
                        if (attempts >= 3) {
                            gaveUp = true
                            break
                        }
                        Thread.sleep(3_000)
                    }
                }
            } finally {
                entry.downloading = false
                when {
                    entry.cancelled -> {
                        // deleteDownload already removed files, but the
                        // still-running writer may have recreated the part
                        // file before noticing the flag; remove once more.
                        entry.partFile().delete()
                        entry.doneFile().delete()
                        File(cacheDir, "${entry.key}$SUFFIX_META").delete()
                        emit(entry, "none")
                    }
                    gaveUp -> {
                        entry.failed = true
                        synchronized(entry.lock) { entry.lock.notifyAll() }
                        emit(entry, "failed")
                    }
                    entry.complete -> {
                        emit(entry, "downloaded")
                        evictIfNeeded()
                    }
                }
            }
        }, "audio-cache-dl-${entry.key}").start()
    }

    private fun downloadOnce(entry: Entry, url: String) {
        android.util.Log.i(TAG, "download start cached=${entry.cached} url=$url")
        val conn = (URL(url).openConnection() as HttpURLConnection).apply {
            connectTimeout = 15_000
            readTimeout = 20_000
            instanceFollowRedirects = true
            setRequestProperty("User-Agent", UA)
            setRequestProperty("Accept-Encoding", "identity")
            // Range requests (even bytes=0-) take the same 206 path that
            // desktop clients use reliably on this CDN.
            setRequestProperty("Range", "bytes=${entry.cached}-")
        }
        val code = conn.responseCode
        android.util.Log.i(TAG, "response code=$code")
        if (code !in 200..299) throw java.io.IOException("upstream $code")
        val part = entry.partFile()
        if (code == 200 && entry.cached > 0) {
            entry.cached = 0
            part.delete()
        }
        if (entry.total < 0) {
            entry.total = when {
                code == 206 -> conn.getHeaderField("Content-Range")
                    ?.substringAfterLast("/")?.toLongOrNull() ?: -1L
                else -> conn.contentLengthLong
            }
        }
        RandomAccessFile(part, "rw").use { raf ->
            conn.inputStream.use { input ->
                val buf = ByteArray(64 * 1024)
                while (true) {
                    val n = input.read(buf)
                    if (n < 0) break
                    if (entry.cancelled) throw CancelledDownload()
                    var shouldEmit = false
                    synchronized(entry.lock) {
                        if (entry.cancelled) throw CancelledDownload()
                        raf.seek(entry.cached)
                        raf.write(buf, 0, n)
                        entry.cached += n
                        entry.lock.notifyAll()
                        val now = System.currentTimeMillis()
                        if (now - entry.lastEmit >= PROGRESS_INTERVAL_MS) {
                            entry.lastEmit = now
                            shouldEmit = true
                        }
                    }
                    if (shouldEmit) emit(entry, "downloading")
                }
            }
        }
        if (entry.cancelled) throw CancelledDownload()
        val done = entry.doneFile()
        if (part.renameTo(done)) {
            entry.complete = true
            if (entry.total < 0) entry.total = done.length()
            File(cacheDir, "${entry.key}$SUFFIX_META").writeText(entry.total.toString())
            synchronized(entry.lock) { entry.lock.notifyAll() }
        } else {
            throw java.io.IOException("finalize cache failed")
        }
    }

    /** LRU cap: delete oldest non-active complete caches. */
    private fun evictIfNeeded() {
        val files = cacheDir.listFiles()?.filter { it.name.endsWith(SUFFIX_DONE) }
            ?.sortedBy { it.lastModified() } ?: return
        var total = files.sumOf { it.length() }
        for (f in files) {
            if (total <= MAX_CACHE_BYTES) break
            val key = f.name.removeSuffix(SUFFIX_DONE)
            if (activeKeys.contains(key)) continue
            val size = f.length()
            if (f.delete()) {
                File(cacheDir, "$key$SUFFIX_META").delete()
                total -= size
            }
        }
    }

    // ------------------------------------------------------------------

    private inner class Entry(
        val key: String,
        @Volatile var total: Long = -1,
        @Volatile var cached: Long = 0,
        @Volatile var complete: Boolean = false,
        @Volatile var failed: Boolean = false,
        @Volatile var downloading: Boolean = false,
        @Volatile var cancelled: Boolean = false,
        @Volatile var srcUrl: String = "",
        @Volatile var lastEmit: Long = 0,
    ) {
        val lock = Object()
        fun partFile() = File(cacheDir, "$key$SUFFIX_PART")
        fun doneFile() = File(cacheDir, "$key$SUFFIX_DONE")
    }

    companion object {
        private const val UA = "Mozilla/5.0"
        private const val SUFFIX_PART = ".part"
        private const val SUFFIX_DONE = ".cache"
        private const val SUFFIX_META = ".meta"
        private const val MAX_CACHE_BYTES = 512L * 1024 * 1024
        private const val PROGRESS_INTERVAL_MS = 500L
        private const val TAG = "AudioCacheProxy"

        @Volatile private var instance: AudioCacheProxy? = null

        fun get(context: Context): AudioCacheProxy =
            instance ?: synchronized(this) {
                instance ?: AudioCacheProxy(context.applicationContext).also { instance = it }
            }

        fun keyOf(url: String): String {
            val digest = MessageDigest.getInstance("SHA-256").digest(url.toByteArray())
            return digest.joinToString("") { "%02x".format(it) }
        }

        fun parseRange(header: String): Pair<Long, Long>? {
            val raw = header.removePrefix("bytes=").split("-")
            if (raw.size != 2) return null
            val start = raw[0].toLongOrNull() ?: return null
            val end = raw[1].takeIf { it.isNotEmpty() }?.toLongOrNull() ?: -1L
            return start to end
        }
    }
}
