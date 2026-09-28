package com.mylanglean.app

import android.content.Context
import android.content.res.AssetFileDescriptor
import android.media.MediaPlayer
import android.os.Handler
import android.os.Looper
import android.os.PowerManager
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler

/**
 * MyLangLean - Android audio playback plugin.
 * Channel: ml/audio_player  (mirrors the HarmonyOS AVPlayer implementation).
 *
 * Lifecycle notes:
 *  - [ticker] is scheduled exactly once and always re-posts itself, even when
 *    no MediaPlayer exists yet. Releasing/loading a player must never cancel it
 *    (an early `return` used to kill position callbacks for the whole session).
 *  - `play` arriving before prepare completes is remembered and honoured in
 *    onPrepared, so quick load+play never silently no-ops.
 */
class MlAudioPlayerPlugin(
    private val context: Context,
    messenger: BinaryMessenger,
) : MethodCallHandler {

    private val channel = MethodChannel(messenger, CHANNEL)
    private val handler = Handler(Looper.getMainLooper())

    private var player: MediaPlayer? = null
    private var assetFd: AssetFileDescriptor? = null
    private var prepared = false
    private var playWhenPrepared = false
    private var loopA = -1
    private var loopB = -1
    private var pendingRate = 1.0f
    private var pendingSeek = -1

    private val ticker = object : Runnable {
        override fun run() {
            val mp = player
            if (mp != null && prepared) {
                try {
                    if (mp.isPlaying) {
                        val pos = mp.currentPosition
                        if (loopA >= 0 && loopB > loopA && pos >= loopB) {
                            mp.seekTo(loopA)
                        }
                        // Always emit (including right after a loop jump): the
                        // next currentPosition already reflects the new head.
                        val posNow = mp.currentPosition
                        channel.invokeMethod("onPosition", posNow)
                    }
                } catch (_: IllegalStateException) {
                    // Player released mid-tick; just reschedule.
                }
            }
            handler.postDelayed(this, TICK_MS.toLong())
        }
    }

    init {
        channel.setMethodCallHandler(this)
        handler.postDelayed(ticker, TICK_MS.toLong())
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        try {
            when (call.method) {
                "load" -> {
                    load(call.argument("source") ?: "", call.argument("isLocal") ?: false)
                    result.success(null)
                }
                "play" -> {
                    play()
                    result.success(null)
                }
                "pause" -> {
                    val mp = player
                    if (prepared && mp != null) {
                        mp.pause()
                        channel.invokeMethod("onState", "paused")
                    }
                    result.success(null)
                }
                "seek" -> {
                    val ms = call.argument<Int>("ms") ?: 0
                    if (prepared) {
                        player?.seekTo(ms)
                        channel.invokeMethod("onPosition", ms)
                    } else {
                        // Seeking before prepare throws; remember it and apply
                        // from onPrepared.
                        pendingSeek = ms
                    }
                    result.success(null)
                }
                "setRate" -> {
                    pendingRate = (call.argument<Double>("rate") ?: 1.0).toFloat()
                    applyRate()
                    result.success(null)
                }
                "setLoop" -> {
                    val a = call.argument<Int?>("a")
                    val b = call.argument<Int?>("b")
                    loopA = a ?: -1
                    loopB = b ?: -1
                    result.success(null)
                }
                "dispose" -> {
                    releasePlayer()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        } catch (e: Exception) {
            result.error("AUDIO_ERROR", "${call.method} failed", e.message)
        }
    }

    private fun play() {
        val mp = player ?: return
        if (!prepared) {
            playWhenPrepared = true
            return
        }
        mp.start()
        channel.invokeMethod("onState", "playing")
    }

    private fun load(source: String, @Suppress("UNUSED_PARAMETER") isLocal: Boolean) {
        releasePlayer()
        playWhenPrepared = false
        // A new episode must not inherit the previous one's loop window.
        loopA = -1
        loopB = -1
        pendingSeek = -1
        val mp = MediaPlayer()
        mp.setWakeMode(context, PowerManager.PARTIAL_WAKE_LOCK)
        if (source.startsWith(ASSET_PREFIX)) {
            // Flutter bundles assets under flutter_assets/ inside the APK.
            // mp3 is stored uncompressed (noCompress), so openFd + offset works.
            val key = "flutter_assets/" + source.removePrefix(ASSET_PREFIX)
            val afd = context.assets.openFd(key)
            assetFd = afd
            mp.setDataSource(afd.fileDescriptor, afd.startOffset, afd.length)
        } else {
            mp.setDataSource(source)
        }
        mp.setOnPreparedListener { p ->
            prepared = true
            channel.invokeMethod("onDuration", p.duration)
            applyRate()
            if (pendingSeek >= 0) {
                p.seekTo(pendingSeek)
                channel.invokeMethod("onPosition", pendingSeek)
                pendingSeek = -1
            }
            if (playWhenPrepared) {
                playWhenPrepared = false
                p.start()
                channel.invokeMethod("onState", "playing")
            }
        }
        mp.setOnCompletionListener {
            channel.invokeMethod("onState", "completed")
        }
        mp.setOnErrorListener { _, what, extra ->
            channel.invokeMethod(
                "onState",
                "error: MediaPlayer what=$what extra=$extra source=${source.take(80)}"
            )
            true
        }
        player = mp
        mp.prepareAsync()
    }

    private fun applyRate() {
        val mp = player ?: return
        if (!prepared) return
        try {
            mp.playbackParams = mp.playbackParams.setSpeed(pendingRate)
        } catch (_: IllegalStateException) {
            // Speed can only be applied once the player is prepared; pendingRate
            // is re-applied from onPrepared.
        }
    }

    private fun releasePlayer() {
        player?.let {
            try {
                it.reset()
                it.release()
            } catch (_: Exception) {
            }
        }
        player = null
        prepared = false
        playWhenPrepared = false
        pendingSeek = -1
        loopA = -1
        loopB = -1
        assetFd?.let {
            try {
                it.close()
            } catch (_: Exception) {
            }
        }
        assetFd = null
    }

    companion object {
        private const val CHANNEL = "ml/audio_player"
        private const val ASSET_PREFIX = "asset://"
        private const val TICK_MS = 33
    }
}
