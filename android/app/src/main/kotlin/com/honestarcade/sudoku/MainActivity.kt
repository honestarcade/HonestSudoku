package com.honestarcade.sudoku

import android.media.AudioManager
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var sound: SoundBridge? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // The volume keys set the media volume the game's sounds play at.
        volumeControlStream = AudioManager.STREAM_MUSIC
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val bridge = SoundBridge(context.assets)
        sound = bridge
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, SoundBridge.CHANNEL)
            .setMethodCallHandler(bridge)
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        sound?.release()
        super.cleanUpFlutterEngine(flutterEngine)
    }

    override fun onDestroy() {
        sound?.release()
        sound = null
        super.onDestroy()
    }
}
