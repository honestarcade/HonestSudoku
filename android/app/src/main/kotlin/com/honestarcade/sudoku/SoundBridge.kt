package com.honestarcade.sudoku

import android.content.res.AssetManager
import android.media.AudioAttributes
import android.media.SoundPool
import io.flutter.FlutterInjector
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * The game's four sounds through a SoundPool (#49). No plugin: the audio
 * plugins either pull in networking or a media player this does not need.
 *
 * `load` takes {clip name: Flutter asset key} and answers how many opened;
 * `play` takes a clip name and ignores one that has not finished loading;
 * `release` frees the pool. The usage is a game sonification, so the phone's
 * media volume and mute apply and the ringer switch does not.
 */
class SoundBridge(private val assets: AssetManager) : MethodChannel.MethodCallHandler {
    private var pool: SoundPool? = null
    private val ids = mutableMapOf<String, Int>()
    private val ready = mutableSetOf<Int>()

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "load" -> {
                val clips = call.arguments as? Map<*, *>
                if (clips == null) {
                    result.error("bad-args", "load takes {clip: asset}", null)
                    return
                }
                result.success(load(clips))
            }
            "play" -> {
                val id = ids[call.arguments as? String]
                if (id != null && id in ready) pool?.play(id, 1f, 1f, 1, 0, 1f)
                result.success(null)
            }
            "release" -> {
                release()
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    private fun load(clips: Map<*, *>): Int {
        release()
        val attributes = AudioAttributes.Builder()
            .setUsage(AudioAttributes.USAGE_GAME)
            .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
            .build()
        val next = SoundPool.Builder()
            .setMaxStreams(4)
            .setAudioAttributes(attributes)
            .build()
        next.setOnLoadCompleteListener { _, id, status ->
            if (status == 0) ready.add(id)
        }
        pool = next
        val loader = FlutterInjector.instance().flutterLoader()
        var opened = 0
        for ((name, asset) in clips) {
            if (name !is String || asset !is String) continue
            try {
                assets.openFd(loader.getLookupKeyForAsset(asset)).use { fd ->
                    ids[name] = next.load(fd, 1)
                }
                opened++
            } catch (e: java.io.IOException) {
                // Skipped; the count tells the Dart side.
            }
        }
        return opened
    }

    /** Frees the pool; safe to call twice. */
    fun release() {
        pool?.release()
        pool = null
        ids.clear()
        ready.clear()
    }

    companion object {
        const val CHANNEL = "com.honestarcade.sudoku/sound"
    }
}
