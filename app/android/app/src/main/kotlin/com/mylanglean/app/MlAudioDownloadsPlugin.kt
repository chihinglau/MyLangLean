package com.mylanglean.app

import android.content.Context
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler

/**
 * Bridges the Flutter UI to [AudioCacheProxy] explicit download management.
 * Channel: ml/audio_downloads
 *
 * Methods:
 *  - statuses(urls: List<String>) -> List<Map> snapshots
 *  - start(url)                  -> begin/ensure download
 *  - delete(url)                 -> remove cache / abort download
 *
 * Pushed calls:
 *  - onProgress {url, state, cached, total} while downloads run.
 */
class MlAudioDownloadsPlugin(
    context: Context,
    messenger: BinaryMessenger,
) : MethodCallHandler {

    private val proxy = AudioCacheProxy.get(context)
    private val channel = MethodChannel(messenger, CHANNEL)

    private val mainHandler = Handler(Looper.getMainLooper())

    private val progressListener = object : AudioCacheProxy.ProgressListener {
        override fun onProgress(url: String, cached: Long, total: Long, state: String) {
            // MethodChannel.invokeMethod is @UiThread; downloads run on
            // background threads, so hop to the platform thread.
            mainHandler.post {
                channel.invokeMethod(
                    "onProgress",
                    mapOf(
                        "url" to url,
                        "state" to state,
                        "cached" to cached,
                        "total" to total,
                    ),
                )
            }
        }
    }

    init {
        channel.setMethodCallHandler(this)
        proxy.addListener(progressListener)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        try {
            when (call.method) {
                "statuses" -> {
                    val urls = call.argument<List<String>>("urls") ?: emptyList()
                    result.success(urls.map { proxy.statusOf(it) })
                }
                "start" -> {
                    proxy.startDownload(call.argument("url") ?: "")
                    result.success(null)
                }
                "delete" -> {
                    proxy.deleteDownload(call.argument("url") ?: "")
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        } catch (e: Exception) {
            result.error("AUDIO_DOWNLOAD_ERROR", "${call.method} failed", e.message)
        }
    }

    companion object {
        private const val CHANNEL = "ml/audio_downloads"
    }
}
