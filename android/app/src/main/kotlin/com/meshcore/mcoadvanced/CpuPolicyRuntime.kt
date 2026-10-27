package com.meshcore.mcoadvanced

import android.content.Context
import android.os.Handler
import android.os.Looper
import android.os.PowerManager
import android.os.SystemClock
import com.pravera.flutter_foreground_task.FlutterForegroundTaskLifecycleListener
import com.pravera.flutter_foreground_task.FlutterForegroundTaskPlugin
import com.pravera.flutter_foreground_task.FlutterForegroundTaskStarter
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodChannel

/** One app-owned lock; no reflection into plugin internals or wake-up alarm. */
object CpuPolicyRuntime : FlutterForegroundTaskLifecycleListener {
    private lateinit var context: Context
    private val handler = Handler(Looper.getMainLooper())
    private var lock: PowerManager.WakeLock? = null
    private var managed = false
    private var diagnostic = false
    private var unconditional = false
    private var taskActive = false
    private var policyHold = true
    private var workHold = false
    private var ready = false
    private var tickPending = false
    private var generation = 0
    private var readyGeneration = 0
    private var session = 0

    fun install(app: Context) {
        context = app.applicationContext
        val prefs = context.getSharedPreferences("mcoa_cpu_policy", Context.MODE_PRIVATE)
        managed = prefs.getBoolean("managed", false)
        unconditional = prefs.getBoolean("unconditional", false)
        FlutterForegroundTaskPlugin.addTaskLifecycleListener(this)
    }

    @Synchronized
    private fun applyLock() {
        val hold = managed && !diagnostic && !unconditional &&
            (workHold || (taskActive && (policyHold || !ready || tickPending)))
        if (hold) {
            if (lock == null) {
                val power = context.getSystemService(Context.POWER_SERVICE) as PowerManager
                lock = power.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "mcoa:cpu-policy")
                    .apply { setReferenceCounted(false) }
            }
            if (lock?.isHeld != true) lock?.acquire()
        } else if (lock?.isHeld == true) {
            lock?.release()
        }
    }

    @Synchronized
    fun handle(method: String, arguments: Any?, workerGeneration: Int?): Any? {
        if (workerGeneration != null && workerGeneration != generation) {
            throw IllegalStateException("Stale CPU worker generation")
        }
        val args = arguments as? Map<*, *>
        when (method) {
            "configure" -> {
                check(workerGeneration == null)
                val nextUnconditional = args?.get("unconditional") == true
                if (!managed || unconditional != nextUnconditional) {
                    // Restore the same choice even before the main engine is ready.
                    check(context.getSharedPreferences("mcoa_cpu_policy", Context.MODE_PRIVATE)
                        .edit().putBoolean("managed", true)
                        .putBoolean("unconditional", nextUnconditional).commit())
                    managed = true
                    unconditional = nextUnconditional
                }
                policyHold = args?.get("hold") != false
                workHold = args?.get("work") == true
                if (args?.get("migrate") == true) {
                    readyGeneration = generation + 1
                    ready = false
                }
                applyLock()
                return true
            }
            "diagnostic" -> {
                check(workerGeneration == null)
                diagnostic = args?.get("enabled") == true
                applyLock()
                return null
            }
            "mainSession" -> {
                check(workerGeneration == null)
                session++
                policyHold = true
                applyLock()
                return null
            }
            "workerReady" -> {
                check(workerGeneration != null)
                if (generation >= readyGeneration) ready = true
                applyLock()
            }
            "tickDone" -> {
                check(workerGeneration != null)
                tickPending = false
                applyLock()
                return null
            }
            "serviceStopped" -> {
                check(workerGeneration == null)
                taskActive = false
                ready = false
                tickPending = false
                applyLock()
                return null
            }
            "clock" -> Unit
            else -> throw IllegalArgumentException("Unknown CPU policy method")
        }
        return mapOf("schema" to 1, "uptimeMs" to SystemClock.uptimeMillis(),
            "generation" to generation, "managed" to (managed && !diagnostic),
            "session" to session, "unconditional" to unconditional,
            "supportsUnconditional" to true)
    }

    @Synchronized
    override fun onEngineCreate(flutterEngine: FlutterEngine?) {
        generation++
        taskActive = true
        ready = false
        tickPending = false
        applyLock()
        flutterEngine?.plugins?.add(CpuPolicyBridge(generation))
    }

    override fun onTaskStart(starter: FlutterForegroundTaskStarter) = Unit

    @Synchronized
    override fun onTaskRepeatEvent() {
        if (managed && !diagnostic && taskActive) {
            tickPending = true
            applyLock()
        }
    }

    @Synchronized
    override fun onTaskDestroy() {
        val endingGeneration = generation
        // API_RESTART replaces the worker, not the main engine or transports.
        handler.post {
            synchronized(this) {
                if (generation == endingGeneration) {
                    taskActive = false
                    ready = false
                    tickPending = false
                    applyLock()
                }
            }
        }
    }

    override fun onEngineWillDestroy() = Unit
}

class CpuPolicyBridge(private val workerGeneration: Int? = null) : FlutterPlugin {
    private var channel: MethodChannel? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel = MethodChannel(binding.binaryMessenger, "mco_advanced/cpu_policy").also {
            it.setMethodCallHandler { call, result ->
                try {
                    result.success(CpuPolicyRuntime.handle(call.method, call.arguments, workerGeneration))
                } catch (error: Exception) {
                    result.error("CPU_POLICY", error.message, null)
                }
            }
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel?.setMethodCallHandler(null)
        channel = null
    }
}
