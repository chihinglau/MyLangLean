package com.mylanglean.app

import android.Manifest
import android.app.Activity
import android.content.pm.PackageManager
import android.media.MediaRecorder
import android.os.Build
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.PluginRegistry
import java.io.File

/**
 * MyLangLean - Android microphone recorder plugin.
 * Channel: ml/audio_recorder. MediaRecorder AAC into filesDir "recordings" as m4a.
 */
class MlAudioRecorderPlugin(
    private val activity: Activity,
    messenger: BinaryMessenger,
) : MethodCallHandler, PluginRegistry.RequestPermissionsResultListener {

    private val channel = MethodChannel(messenger, CHANNEL)
    private var recorder: MediaRecorder? = null
    private var outputPath: String = ""
    private var permissionResult: MethodChannel.Result? = null

    init {
        channel.setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        try {
            when (call.method) {
                "requestPermission" -> {
                    if (hasMicPermission()) {
                        result.success(true)
                    } else {
                        permissionResult = result
                        activity.requestPermissions(arrayOf(Manifest.permission.RECORD_AUDIO), REQ_MIC)
                    }
                }
                "start" -> {
                    start()
                    result.success(null)
                }
                "stop" -> result.success(stop())
                else -> result.notImplemented()
            }
        } catch (e: Exception) {
            result.error("RECORDER_ERROR", "${call.method} failed", e.message)
        }
    }

    override fun onRequestPermissionsResult(
        requestCode: Int, permissions: Array<out String>, grantResults: IntArray
    ): Boolean {
        if (requestCode != REQ_MIC) return false
        val granted = grantResults?.isNotEmpty() == true &&
                grantResults[0] == PackageManager.PERMISSION_GRANTED
        permissionResult?.success(granted)
        permissionResult = null
        return true
    }

    private fun hasMicPermission(): Boolean =
        activity.checkSelfPermission(Manifest.permission.RECORD_AUDIO) ==
                PackageManager.PERMISSION_GRANTED

    private fun start() {
        check(hasMicPermission()) { "RECORD_AUDIO permission not granted" }
        val dir = File(activity.filesDir, "recordings").apply { mkdirs() }
        outputPath = File(dir, "rec_${System.currentTimeMillis()}.m4a").absolutePath

        @Suppress("DEPRECATION")
        val mr = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            MediaRecorder(activity)
        } else {
            MediaRecorder()
        }
        mr.setAudioSource(MediaRecorder.AudioSource.MIC)
        mr.setOutputFormat(MediaRecorder.OutputFormat.MPEG_4)
        mr.setAudioEncoder(MediaRecorder.AudioEncoder.AAC)
        mr.setAudioEncodingBitRate(96000)
        mr.setAudioSamplingRate(44100)
        mr.setAudioChannels(1)
        mr.setOutputFile(outputPath)
        mr.prepare()
        mr.start()
        recorder = mr
    }

    private fun stop(): String {
        recorder?.let {
            try {
                it.stop()
                it.release()
            } catch (_: Exception) {
            }
        }
        recorder = null
        return outputPath
    }

    companion object {
        private const val CHANNEL = "ml/audio_recorder"
        private const val REQ_MIC = 4101
    }
}
