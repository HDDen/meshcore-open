package com.meshcore.mcoadvanced

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class WardriveForegroundFunctions(
    private val activity: FlutterActivity,
) {
    private val methodChannelName = "mco_advanced/wardrive_foreground"

    fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, methodChannelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "start" -> {
                        WardriveForegroundService.start(activity)
                        result.success(null)
                    }
                    "stop" -> {
                        WardriveForegroundService.stop(activity)
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }
}
