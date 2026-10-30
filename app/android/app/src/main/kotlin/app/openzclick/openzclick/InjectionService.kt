package app.openzclick.openzclick

import android.accessibilityservice.AccessibilityService
import android.accessibilityservice.GestureDescription
import android.graphics.Path
import android.util.DisplayMetrics
import android.util.Log
import android.view.WindowManager
import android.view.accessibility.AccessibilityEvent
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Injects taps into whatever application is in the foreground.
 *
 * Android refuses synthetic pointer events to ordinary applications, but a
 * running accessibility service may dispatch gestures. This service therefore
 * exposes a single capability, [tap], reached from the Dart side through
 * [channel]: the bridge stays portable, only this host knows how to touch a
 * screen.
 */
class InjectionService : AccessibilityService() {

    override fun onServiceConnected() {
        super.onServiceConnected()
        instance = this
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        // The service only injects; it never reads the screen.
    }

    override fun onInterrupt() = Unit

    override fun onUnbind(intent: android.content.Intent?): Boolean {
        if (instance === this) instance = null
        return super.onUnbind(intent)
    }

    override fun onDestroy() {
        if (instance === this) instance = null
        super.onDestroy()
    }

    /** Converts relative coordinates to pixels and dispatches a tap. */
    fun tap(xPercent: Double, yPercent: Double, onDone: (Boolean) -> Unit) {
        val metrics = displayMetrics()
        val x = (xPercent.coerceIn(0.0, 1.0) * metrics.widthPixels).toFloat()
        val y = (yPercent.coerceIn(0.0, 1.0) * metrics.heightPixels).toFloat()

        val path = Path().apply { moveTo(x, y) }
        val gesture = GestureDescription.Builder()
            .addStroke(GestureDescription.StrokeDescription(path, 0, 40))
            .build()
        val accepted = dispatchGesture(gesture, null, null)
        Log.i(TAG, "tap at ${x.toInt()},${y.toInt()} accepted=$accepted")
        onDone(accepted)
    }

    private fun displayMetrics(): DisplayMetrics {
        val manager = getSystemService(WINDOW_SERVICE) as WindowManager
        val metrics = DisplayMetrics()
        @Suppress("DEPRECATION")
        manager.defaultDisplay.getRealMetrics(metrics)
        return metrics
    }

    companion object {
        /** Running service, null when the user has not enabled it. */
        @Volatile
        var instance: InjectionService? = null

        /** Log tag used by the diagnostic screen and by `adb logcat`. */
        const val TAG = "openzclick-injection"

        /** Channel name shared with the Dart side. */
        const val CHANNEL = "openzclick/injection"

        /** True when the accessibility service is enabled and connected. */
        fun isReady(): Boolean = instance != null

        /** Handles a call coming from the application. */
        fun handle(call: MethodCall, result: MethodChannel.Result) {
            when (call.method) {
                "ready" -> result.success(isReady())
                "tap" -> {
                    val x = call.argument<Double>("x") ?: 0.0
                    val y = call.argument<Double>("y") ?: 0.0
                    val service = instance
                    Log.i(TAG, "tap request x=$x y=$y service=${service != null}")
                    if (service == null) {
                        result.error("disabled", "injection service is not enabled", null)
                        return
                    }
                    service.tap(x, y) { accepted -> result.success(accepted) }
                }
                else -> result.notImplemented()
            }
        }
    }
}
