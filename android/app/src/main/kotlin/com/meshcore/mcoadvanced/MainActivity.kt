package com.meshcore.mcoadvanced

import android.content.Context
import android.net.wifi.WifiManager
import android.os.Build
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.android.FlutterView
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterEngineCache
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    companion object {
        private const val ENGINE_CACHE_ID = "meshcore_main_engine"
        private const val ENGINE_LIFECYCLE_CHANNEL = "mco_advanced/engine_lifecycle"
        private const val TCP_WIFI_LOCK_CHANNEL = "mco_advanced/tcp_wifi_lock"
        private const val TCP_WIFI_LOCK_TAG = "mco_advanced:tcp"

        @Volatile
        private var retainEngine = false

        @Volatile
        private var tcpWifiLock: WifiManager.WifiLock? = null

        @Synchronized
        private fun setTcpWifiLock(context: Context, enabled: Boolean) {
            if (enabled) {
                if (tcpWifiLock?.isHeld == true) return
                val wifiManager = context.applicationContext
                    .getSystemService(Context.WIFI_SERVICE) as WifiManager
                tcpWifiLock = wifiManager.createWifiLock(
                    WifiManager.WIFI_MODE_FULL_HIGH_PERF,
                    TCP_WIFI_LOCK_TAG,
                ).apply {
                    setReferenceCounted(false)
                    acquire()
                }
                return
            }

            tcpWifiLock?.let { lock ->
                if (lock.isHeld) lock.release()
            }
            tcpWifiLock = null
        }
    }

    private val usbFunctions by lazy { MeshcoreUsbFunctions(this) }
    private val wardriveForegroundFunctions by lazy {
        WardriveForegroundFunctions(this)
    }
    private val notificationPermissionFunctions by lazy {
        NotificationPermissionFunctions(this)
    }
    private var scrollCapture: FlutterScrollCapture? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) return
        val engine = flutterEngine ?: return
        val view = findViewById<FlutterView>(FLUTTER_VIEW_ID) ?: return
        scrollCapture = FlutterScrollCapture(view, engine.dartExecutor.binaryMessenger)
            .also { it.attach() }
    }

    override fun provideFlutterEngine(context: Context): FlutterEngine? {
        return FlutterEngineCache.getInstance().get(ENGINE_CACHE_ID)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        if (!flutterEngine.plugins.has(CpuPolicyBridge::class.java)) {
            flutterEngine.plugins.add(CpuPolicyBridge())
        }
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
        val appContext = applicationContext
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            TCP_WIFI_LOCK_CHANNEL,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "setEnabled" -> {
                    setTcpWifiLock(
                        appContext,
                        call.argument<Boolean>("enabled") == true,
                    )
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

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            scrollCapture?.detach()
            scrollCapture = null
        }
        super.cleanUpFlutterEngine(flutterEngine)
    }

    override fun onDestroy() {
        if (!retainEngine) {
            setTcpWifiLock(applicationContext, false)
            FlutterEngineCache.getInstance().remove(ENGINE_CACHE_ID)
        }
        usbFunctions.dispose()
        super.onDestroy()
    }
}
