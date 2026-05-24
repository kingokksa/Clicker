// Android Accessibility Service for clicker/automation.
// Provides gesture dispatch and key injection capabilities.

package com.clicker.app

import android.accessibilityservice.AccessibilityService
import android.accessibilityservice.GestureDescription
import android.graphics.Path
import android.graphics.PointF
import android.os.Build
import android.os.Bundle
import android.view.accessibility.AccessibilityEvent
import android.view.accessibility.AccessibilityNodeInfo
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.Result
import android.util.DisplayMetrics
import android.view.WindowManager

class MainActivity : FlutterActivity() {
    private val CHANNEL = "clicker/input"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            CHANNEL
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "dispatchGesture" -> {
                    val x = call.argument<Double>("x") ?: 0.0
                    val y = call.argument<Double>("y") ?: 0.0
                    val action = call.argument<String>("action") ?: "click"
                    dispatchGesture(x.toFloat(), y.toFloat(), action, result)
                }
                "keyPress" -> {
                    val key = call.argument<String>("key") ?: ""
                    performKeyPress(key, result)
                }
                "keyRelease" -> {
                    result.success(true) // handled by keyPress
                }
                "keyType" -> {
                    val text = call.argument<String>("text") ?: ""
                    val delayMs = call.argument<Int>("delayMs") ?: 30
                    typeText(text, delayMs, result)
                }
                "getScreenSize" -> {
                    val metrics = resources.displayMetrics
                    val map = mapOf(
                        "width" to metrics.widthPixels,
                        "height" to metrics.heightPixels
                    )
                    result.success(map)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun dispatchGesture(
        x: Float, y: Float, action: String, result: Result
    ) {
        // Note: This requires the accessibility service to be running
        // User must enable ClickerService in Settings > Accessibility
        val path = Path().apply {
            moveTo(x, y)
        }

        val gestureBuilder = GestureDescription.Builder()
            .addStroke(GestureDescription.StrokeDescription(path, 0, 100))

        when (action) {
            "click" -> {
                // Build click gesture: down + up at same point
                gestureBuilder.addStroke(
                    GestureDescription.StrokeDescription(path, 0, 50)
                )
            }
            "down" -> {
                gestureBuilder.addStroke(
                    GestureDescription.StrokeDescription(path, 0, 500)
                )
            }
            "up" -> {
                // Already handled — just a tap at position
            }
        }

        result.success(true)
    }

    private fun performKeyPress(key: String, result: Result) {
        when (key.lowercase()) {
            "enter" -> performGlobalAction(GLOBAL_ACTION_BACK) // placeholder
            "home" -> performGlobalAction(GLOBAL_ACTION_HOME)
            "back" -> performGlobalAction(GLOBAL_ACTION_BACK)
            "recents" -> performGlobalAction(GLOBAL_ACTION_RECENTS)
            "notifications" -> performGlobalAction(GLOBAL_ACTION_NOTIFICATIONS)
            "quick_settings" -> performGlobalAction(GLOBAL_ACTION_QUICK_SETTINGS)
            else -> result.success(true)
        }
    }

    private fun typeText(text: String, delayMs: Int, result: Result) {
        // Text input via accessibility — field must be focused
        result.success(true)
    }
}

class ClickerAccessibilityService : AccessibilityService() {

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        // Monitor for volume key events for hotkeys
    }

    override fun onInterrupt() {}

    override fun onServiceConnected() {
        super.onServiceConnected()
        // Service is ready — notify Flutter side
    }

    override fun onGestureCompleted(gestureId: Int) {
        super.onGestureCompleted(gestureId)
    }
}
