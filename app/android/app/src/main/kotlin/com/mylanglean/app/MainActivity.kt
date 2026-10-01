package com.mylanglean.app

import android.content.Intent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {

    private var playerPlugin: MlAudioPlayerPlugin? = null
    private var recorderPlugin: MlAudioRecorderPlugin? = null
    private var pickerPlugin: MlMediaPickerPlugin? = null
    private var updaterPlugin: MlUpdaterPlugin? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger

        playerPlugin = MlAudioPlayerPlugin(applicationContext, messenger)
        recorderPlugin = MlAudioRecorderPlugin(this, messenger)
        pickerPlugin = MlMediaPickerPlugin(this, messenger)
        updaterPlugin = MlUpdaterPlugin(this, messenger)
    }

    @Deprecated("Deprecated in Java")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        pickerPlugin?.onActivityResult(requestCode, resultCode, data)
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        recorderPlugin?.onRequestPermissionsResult(requestCode, permissions, grantResults)
    }
}
