package com.meshcore.mcoadvanced

import android.content.Intent
import android.content.Context
import android.net.Uri
import android.os.Build
import android.os.PowerManager
import android.provider.Settings
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
                    "isIgnoringBatteryOptimizations" -> {
                        result.success(isIgnoringBatteryOptimizations())
                    }
                    "openAppBackgroundSettings" -> {
                        openAppBackgroundSettings()
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun isIgnoringBatteryOptimizations(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return true
        val powerManager =
            activity.getSystemService(Context.POWER_SERVICE) as PowerManager
        return powerManager.isIgnoringBatteryOptimizations(activity.packageName)
    }

    private fun openAppBackgroundSettings() {
        // App details is the most stable entry point for Background activity,
        // Battery usage, Notifications, and Location permissions across OEMs.
        val appSettingsIntent = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
            data = Uri.parse("package:${activity.packageName}")
        }
        try {
            activity.startActivity(appSettingsIntent)
            return
        } catch (_: Exception) {
            // Fall through to the generic battery optimization screen.
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            val batterySettingsIntent =
                Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS)
            activity.startActivity(batterySettingsIntent)
        }
    }
}
