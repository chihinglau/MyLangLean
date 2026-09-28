package com.mylanglean.app

import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.Intent
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.provider.OpenableColumns
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.PluginRegistry
import java.io.File

/**
 * MyLangLean - Android file/media picker plugin.
 * Channel: ml/media_picker. Storage Access Framework picker; the picked
 * document is copied into filesDir/imports so the path stays valid after
 * the SAF permission is released.
 *
 * Methods:
 *   pickAudio()       all audio MIME types plus common video containers
 *   pickFile({exts})  any file (Dart validates the extension allow-list)
 *   filesDir()        absolute app-private files directory
 */
class MlMediaPickerPlugin(
    private val activity: Activity,
    messenger: BinaryMessenger,
) : MethodCallHandler, PluginRegistry.ActivityResultListener {

    private val channel = MethodChannel(messenger, CHANNEL)
    private var pendingResult: MethodChannel.Result? = null
    private val mainHandler = Handler(Looper.getMainLooper())

    init {
        channel.setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "pickAudio", "pickFile" -> launchPicker(call, result)
            "filesDir" -> result.success(activity.filesDir.absolutePath)
            else -> result.notImplemented()
        }
    }

    private fun launchPicker(call: MethodCall, result: MethodChannel.Result) {
        if (pendingResult != null) {
            result.error("PICKER_BUSY", "another pick is in progress", null)
            return
        }
        pendingResult = result
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            if (call.method == "pickAudio") {
                type = "*/*"
                putExtra(
                    Intent.EXTRA_MIME_TYPES,
                    arrayOf(
                        "audio/*",
                        "video/mp4",
                        "video/quicktime",
                        "video/x-matroska",
                        "video/x-msvideo",
                        "video/webm"
                    )
                )
            } else {
                // Sidecar subtitles are often application/octet-stream on
                // devices, so do not constrain the MIME type; Dart checks
                // the extension allow-list after the copy.
                type = "*/*"
            }
        }
        try {
            activity.startActivityForResult(intent, REQ_PICK)
        } catch (e: ActivityNotFoundException) {
            pendingResult = null
            result.error(
                "NO_PICKER",
                "设备上没有可选择文件的应用，请先安装文件管理器",
                null,
            )
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode != REQ_PICK) return false
        val result = pendingResult
        pendingResult = null
        if (result == null) return true

        if (resultCode != Activity.RESULT_OK || data?.data == null) {
            result.success(null)
            return true
        }
        val uri = data.data!!
        // Videos can be hundreds of MB: copy off the UI thread to avoid ANR,
        // then deliver the result back on the main thread.
        Thread {
            var dest: File? = null
            try {
                val name = queryDisplayName(uri)
                val dir = File(activity.filesDir, "imports").apply { mkdirs() }
                val target = File(dir, uniqueName(dir, name))
                dest = target
                activity.contentResolver.openInputStream(uri).use { input ->
                    requireNotNull(input) { "cannot open picked file" }
                    target.outputStream().use { output -> input.copyTo(output) }
                }
                val payload = mapOf(
                    "path" to target.absolutePath,
                    "title" to name,
                    "durationMs" to 0,
                    "sizeBytes" to target.length()
                )
                mainHandler.post { result.success(payload) }
            } catch (e: Exception) {
                dest?.takeIf { it.exists() }?.delete()
                val message = "${e.javaClass.simpleName}: ${e.message}"
                mainHandler.post {
                    result.error("PICKER_ERROR", message, null)
                }
            }
        }.start()
        return true
    }

    /// Avoid silently overwriting a previously imported file with the same
    /// display name (e.g. two episodes both called "audio.mp3").
    private fun uniqueName(dir: File, name: String): String {
        if (!File(dir, name).exists()) return name
        val dot = name.lastIndexOf('.')
        val base = if (dot > 0) name.substring(0, dot) else name
        val ext = if (dot > 0) name.substring(dot) else ""
        var i = 1
        while (File(dir, "${base}_$i$ext").exists()) i++
        return "${base}_$i$ext"
    }

    private fun queryDisplayName(uri: Uri): String {
        activity.contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)
            ?.use { c ->
                if (c.moveToFirst() && !c.isNull(0)) {
                    val n = c.getString(0)
                    if (!n.isNullOrBlank()) return sanitize(n)
                }
            }
        return "file_${System.currentTimeMillis()}"
    }

    private fun sanitize(name: String): String =
        name.substringBefore('?').replace(Regex("[\\\\/:*?\"<>|]"), "_")

    companion object {
        private const val CHANNEL = "ml/media_picker"
        private const val REQ_PICK = 4102
    }
}
