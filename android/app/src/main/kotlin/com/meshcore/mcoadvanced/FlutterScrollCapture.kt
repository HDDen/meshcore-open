package com.meshcore.mcoadvanced

import android.annotation.TargetApi
import android.graphics.Bitmap
import android.graphics.Color
import android.graphics.PorterDuff
import android.graphics.Rect
import android.os.Build
import android.os.CancellationSignal
import android.os.Handler
import android.os.Looper
import android.view.PixelCopy
import android.view.ScrollCaptureCallback
import android.view.ScrollCaptureSession
import android.view.View
import io.flutter.embedding.android.FlutterSurfaceView
import io.flutter.embedding.android.FlutterView
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.atomic.AtomicLong
import java.util.function.Consumer

/** Copies a visible strip of Flutter's surface into Android's screenshot session. */
@TargetApi(Build.VERSION_CODES.S)
internal class FlutterScrollCapture(
    private val view: FlutterView,
    messenger: BinaryMessenger,
) : ScrollCaptureCallback {
    private data class Target(val id: Long, val bounds: Rect, val surface: FlutterSurfaceView)
    private class Capture(val target: Target, val session: ScrollCaptureSession) {
        var ready = false
    }

    private val channel = MethodChannel(messenger, "mco_advanced/scroll_capture")
    private val handler = Handler(Looper.getMainLooper())
    private var searchId: Long? = null
    private var target: Target? = null
    private var capture: Capture? = null
    private var attached = false
    private var imagePending = false
    private var copyInFlight = false

    fun attach() {
        attached = true
        view.scrollCaptureHint = View.SCROLL_CAPTURE_HINT_INCLUDE
        view.setScrollCaptureCallback(this)
    }

    fun detach() {
        attached = false
        view.setScrollCaptureCallback(null)
        view.scrollCaptureHint = View.SCROLL_CAPTURE_HINT_AUTO
        finishSession {}
    }

    override fun onScrollCaptureSearch(signal: CancellationSignal, onReady: Consumer<Rect>) {
        // The Activity's standard Flutter renderer uses a SurfaceView. A
        // TextureView read would allocate a bitmap of the entire screen.
        val surface = (0 until view.childCount)
            .firstNotNullOfOrNull { view.getChildAt(it) as? FlutterSurfaceView }
        if (!attached || capture != null || surface == null || signal.isCanceled) {
            onReady.accept(Rect())
            return
        }
        target?.let { invoke("end", it.id) {} }
        target = null
        val id = ids.incrementAndGet()
        searchId = id
        invoke("search", id) { result ->
            val bounds = (result as? Map<*, *>)?.toBounds()
            val current = searchId == id
            if (current) searchId = null
            if (!current || !attached || signal.isCanceled || bounds == null ||
                bounds.isEmpty || !Rect(0, 0, view.width, view.height).contains(bounds)
            ) {
                invoke("end", id) {}
                onReady.accept(Rect())
                return@invoke
            }
            target = Target(id, bounds, surface)
            onReady.accept(Rect(bounds))
        }
    }

    override fun onScrollCaptureStart(
        session: ScrollCaptureSession,
        signal: CancellationSignal,
        onReady: Runnable,
    ) {
        val selected = target
        target = null
        if (!attached || selected == null || signal.isCanceled) {
            selected?.let { invoke("end", it.id) {} }
            onReady.run()
            return
        }
        val active = Capture(selected, session)
        capture = active
        signal.setOnCancelListener { handler.post { cancel(active) } }
        invoke("start", selected.id) { result ->
            signal.setOnCancelListener(null)
            if (capture === active && attached && !signal.isCanceled && result == true) {
                active.ready = true
            } else {
                cancel(active)
                if (capture === active) capture = null
            }
            onReady.run()
        }
    }

    override fun onScrollCaptureImageRequest(
        session: ScrollCaptureSession,
        signal: CancellationSignal,
        captureArea: Rect,
        onComplete: Consumer<Rect>,
    ) {
        val active = capture
        if (!attached || active == null || !active.ready || active.session !== session ||
            imagePending || copyInFlight || signal.isCanceled
        ) {
            onComplete.accept(Rect())
            return
        }
        val selected = active.target
        val left = captureArea.left.coerceAtLeast(0)
        val right = captureArea.right.coerceAtMost(selected.bounds.width())
        if (right <= left || right - left > MAX_PIXELS || captureArea.isEmpty) {
            onComplete.accept(Rect())
            return
        }
        val top = captureArea.top.toLong()
        val bottom = minOf(captureArea.bottom.toLong(), top + MAX_PIXELS / (right - left))
        imagePending = true
        var completed = false
        val timeout = Runnable {
            cancel(active)
            completed = true
            imagePending = false
            signal.setOnCancelListener(null)
            onComplete.accept(Rect())
        }
        fun finish(area: Rect) {
            if (completed) return
            completed = true
            handler.removeCallbacks(timeout)
            imagePending = false
            signal.setOnCancelListener(null)
            onComplete.accept(area)
        }
        fun valid() = !completed && attached && capture === active &&
            active.ready && !signal.isCanceled

        signal.setOnCancelListener {
            handler.post {
                if (!completed) {
                    cancel(active)
                    finish(Rect())
                }
            }
        }
        handler.postDelayed(timeout, IMAGE_TIMEOUT_MS)
        invoke("scroll", selected.id, mapOf("top" to top, "bottom" to bottom)) { result ->
            val moved = (result as? Number)?.toLong()
            if (!valid() || moved == null) {
                cancel(active)
                finish(Rect())
                return@invoke
            }
            val visibleTop = maxOf(top - moved, 0L)
            val visibleBottom = minOf(bottom - moved, selected.bounds.height().toLong())
            if (visibleBottom <= visibleTop) {
                finish(Rect())
                return@invoke
            }
            val source = Rect(
                selected.bounds.left + left,
                selected.bounds.top + visibleTop.toInt(),
                selected.bounds.left + right,
                selected.bounds.top + visibleBottom.toInt(),
            )
            val area = Rect(left, (visibleTop + moved).toInt(), right, (visibleBottom + moved).toInt())
            // Dart has submitted the new frame. Allow the raster surface to present it.
            handler.postDelayed({
                if (!valid()) {
                    finish(Rect())
                } else {
                    copyStrip(selected.surface, source) { bitmap ->
                        val drawn = bitmap != null && valid() && drawStrip(session, bitmap)
                        bitmap?.recycle()
                        finish(if (drawn) area else Rect())
                    }
                }
            }, FRAME_SETTLE_MS)
        }
    }

    override fun onScrollCaptureEnd(onReady: Runnable) = finishSession { onReady.run() }

    private fun cancel(active: Capture) {
        if (capture !== active) return
        active.ready = false
        invoke("end", active.target.id) {}
    }

    private fun finishSession(onReady: () -> Unit) {
        val id = capture?.target?.id ?: target?.id ?: searchId
        capture = null
        target = null
        searchId = null
        if (id == null) onReady() else invoke("end", id) { onReady() }
    }

    private fun copyStrip(surface: FlutterSurfaceView, area: Rect, done: (Bitmap?) -> Unit) {
        val viewLocation = IntArray(2).also(view::getLocationInWindow)
        val surfaceLocation = IntArray(2).also(surface::getLocationInWindow)
        area.offset(viewLocation[0] - surfaceLocation[0], viewLocation[1] - surfaceLocation[1])
        val frame = surface.holder.surfaceFrame
        if (copyInFlight || !surface.isAttachedToWindow || !surface.holder.surface.isValid ||
            !Rect(0, 0, frame.width(), frame.height()).contains(area)
        ) {
            done(null)
            return
        }
        val bitmap = try {
            Bitmap.createBitmap(area.width(), area.height(), Bitmap.Config.ARGB_8888)
        } catch (_: OutOfMemoryError) {
            done(null)
            return
        }
        copyInFlight = true
        try {
            PixelCopy.request(surface, area, bitmap, { status ->
                copyInFlight = false
                if (status == PixelCopy.SUCCESS) {
                    done(bitmap)
                } else {
                    bitmap.recycle()
                    done(null)
                }
            }, handler)
        } catch (_: RuntimeException) {
            copyInFlight = false
            bitmap.recycle()
            done(null)
        }
    }

    private fun drawStrip(session: ScrollCaptureSession, bitmap: Bitmap): Boolean = try {
        val surface = session.surface
        val canvas = surface.lockHardwareCanvas()
        try {
            canvas.drawColor(Color.TRANSPARENT, PorterDuff.Mode.CLEAR)
            canvas.drawBitmap(bitmap, 0f, 0f, null)
        } finally {
            surface.unlockCanvasAndPost(canvas)
        }
        true
    } catch (_: RuntimeException) {
        false
    }

    private fun invoke(
        method: String,
        id: Long,
        args: Map<String, Any> = emptyMap(),
        done: (Any?) -> Unit,
    ) {
        var finished = false
        val timeout = Runnable {
            finished = true
            done(null)
        }
        fun finish(value: Any?) {
            if (finished) return
            finished = true
            handler.removeCallbacks(timeout)
            done(value)
        }
        handler.postDelayed(timeout, CALL_TIMEOUT_MS)
        try {
            channel.invokeMethod(method, args + ("id" to id), object : MethodChannel.Result {
                override fun success(result: Any?) = finish(result)
                override fun error(code: String, message: String?, details: Any?) = finish(null)
                override fun notImplemented() = finish(null)
            })
        } catch (_: RuntimeException) {
            finish(null)
        }
    }

    private fun Map<*, *>.toBounds(): Rect? {
        val left = (get("left") as? Number)?.toInt() ?: return null
        val top = (get("top") as? Number)?.toInt() ?: return null
        val right = (get("right") as? Number)?.toInt() ?: return null
        val bottom = (get("bottom") as? Number)?.toInt() ?: return null
        return Rect(left, top, right, bottom)
    }

    private companion object {
        val ids = AtomicLong()
        const val MAX_PIXELS = 2_097_152 // At most 8 MiB of ARGB pixels.
        const val CALL_TIMEOUT_MS = 900L
        const val IMAGE_TIMEOUT_MS = 1_200L
        const val FRAME_SETTLE_MS = 32L
    }
}
