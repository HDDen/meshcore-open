package com.meshcore.mcoadvanced

import android.content.Context
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterEngineCache
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    companion object {
        private const val ENGINE_CACHE_ID = "meshcore_main_engine"
        private const val ENGINE_LIFECYCLE_CHANNEL = "mco_advanced/engine_lifecycle"

        @Volatile
        private var retainEngine = false
    }

    private val usbFunctions by lazy { MeshcoreUsbFunctions(this) }
    private val wardriveForegroundFunctions by lazy {
        WardriveForegroundFunctions(this)
    }
    private val notificationPermissionFunctions by lazy {
        NotificationPermissionFunctions(this)
    }

    override fun provideFlutterEngine(context: Context): FlutterEngine? {
        return FlutterEngineCache.getInstance().get(ENGINE_CACHE_ID)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        FlutterEngineCache.getInstance().put(ENGINE_CACHE_ID, flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            ENGINE_LIFECYCLE_CHANNEL,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "setRetainEngine" -> {
                    retainEngine = call.argument<Boolean>("retain") == true
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
        usbFunctions.configureFlutterEngine(flutterEngine)
        wardriveForegroundFunctions.configureFlutterEngine(flutterEngine)
        notificationPermissionFunctions.configureFlutterEngine(flutterEngine)
    }

    override fun shouldDestroyEngineWithHost(): Boolean = !retainEngine

    override fun onDestroy() {
        if (!retainEngine) {
            FlutterEngineCache.getInstance().remove(ENGINE_CACHE_ID)
        }
        usbFunctions.dispose()
        super.onDestroy()
    }
}
