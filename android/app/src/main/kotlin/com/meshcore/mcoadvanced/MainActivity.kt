package com.meshcore.mcoadvanced

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    private val usbFunctions by lazy { MeshcoreUsbFunctions(this) }
    private val wardriveForegroundFunctions by lazy {
        WardriveForegroundFunctions(this)
    }
    private val notificationPermissionFunctions by lazy {
        NotificationPermissionFunctions(this)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        usbFunctions.configureFlutterEngine(flutterEngine)
        wardriveForegroundFunctions.configureFlutterEngine(flutterEngine)
        notificationPermissionFunctions.configureFlutterEngine(flutterEngine)
    }

    override fun onDestroy() {
        usbFunctions.dispose()
        super.onDestroy()
    }
}
