package com.clicker.app

import android.accessibilityservice.AccessibilityService
import android.accessibilityservice.GestureDescription
import android.annotation.TargetApi
import android.app.Activity
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.Path
import android.graphics.PixelFormat
import android.hardware.display.DisplayManager
import android.hardware.display.VirtualDisplay
import android.media.Image
import android.media.ImageReader
import android.media.projection.MediaProjection
import android.media.projection.MediaProjectionManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import android.util.DisplayMetrics
import android.view.Gravity
import android.view.WindowManager
import android.view.accessibility.AccessibilityEvent
import android.view.accessibility.AccessibilityNodeInfo
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.io.FileOutputStream
import java.nio.ByteBuffer

class MainActivity : FlutterActivity() {
    private val INPUT_CHANNEL = "clicker/input"
    private val PLATFORM_CHANNEL = "com.clicker.pro/platform"
    private val HOTKEY_CHANNEL = "clicker/hotkeys"
    private val RECORD_CHANNEL = "com.clicker.pro/record"

    private var mediaProjection: MediaProjection? = null
    private var virtualDisplay: VirtualDisplay? = null
    private var imageReader: ImageReader? = null
    private var screenDensity: Int = 0
    private var screenWidth: Int = 0
    private var screenHeight: Int = 0
    private var projectionResult: MethodChannel.Result? = null
    private var overlayView: android.view.View? = null
    private var isRecording = false
    private var recordStartTime = 0L

    companion object {
        const val REQUEST_MEDIA_PROJECTION = 1001
        var instance: MainActivity? = null
    }

    fun getFlutterMessenger(): io.flutter.plugin.common.BinaryMessenger? {
        return flutterEngine?.dartExecutor?.binaryMessenger
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        instance = this

        val metrics = resources.displayMetrics
        screenDensity = metrics.densityDpi
        // Use real physical pixels for gesture coordinates
        val realMetrics = android.util.DisplayMetrics()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.JELLY_BEAN_MR1) {
            windowManager.defaultDisplay.getRealMetrics(realMetrics)
            screenWidth = realMetrics.widthPixels
            screenHeight = realMetrics.heightPixels
        } else {
            screenWidth = metrics.widthPixels
            screenHeight = metrics.heightPixels
        }

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            INPUT_CHANNEL
        ).setMethodCallHandler { call, result ->
            handleInputCall(call.method, call.arguments as? Map<String, Any>, result)
        }

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            PLATFORM_CHANNEL
        ).setMethodCallHandler { call, result ->
            handlePlatformCall(call.method, call.arguments, result)
        }

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            HOTKEY_CHANNEL
        ).setMethodCallHandler { call, result ->
            handleHotkeyCall(call.method, call.arguments, result)
        }

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            RECORD_CHANNEL
        ).setMethodCallHandler { call, result ->
            handleRecordCall(call.method, call.arguments, result)
        }
    }

    override fun onDestroy() {
        super.onDestroy()
        stopScreenCapture()
        instance = null
    }

    @TargetApi(Build.VERSION_CODES.LOLLIPOP)
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (requestCode == REQUEST_MEDIA_PROJECTION) {
            if (resultCode == Activity.RESULT_OK && data != null) {
                val mgr = getSystemService(Context.MEDIA_PROJECTION_SERVICE) as MediaProjectionManager
                mediaProjection = mgr.getMediaProjection(resultCode, data)
                setupVirtualDisplay()
                projectionResult?.success(true)
            } else {
                projectionResult?.error("PROJECTION_DENIED", "User denied screen capture permission", null)
            }
            projectionResult = null
        } else {
            super.onActivityResult(requestCode, resultCode, data)
        }
    }

    private fun handleInputCall(method: String, args: Map<String, Any>?, result: MethodChannel.Result) {
        when (method) {
            "dispatchGesture" -> {
                val x = (args?.get("x") as? Number)?.toFloat() ?: 0f
                val y = (args?.get("y") as? Number)?.toFloat() ?: 0f
                val action = args?.get("action") as? String ?: "click"
                val durationMs = (args?.get("durationMs") as? Number)?.toInt() ?: 300
                val startX = (args?.get("startX") as? Number)?.toFloat() ?: x
                val startY = (args?.get("startY") as? Number)?.toFloat() ?: y
                val endX = (args?.get("endX") as? Number)?.toFloat() ?: x
                val endY = (args?.get("endY") as? Number)?.toFloat() ?: y
                dispatchGestureAction(x, y, action, result, durationMs, startX, startY, endX, endY)
            }
            "mouseClick" -> {
                val x = (args?.get("x") as? Number)?.toFloat() ?: 0f
                val y = (args?.get("y") as? Number)?.toFloat() ?: 0f
                val doubleClick = args?.get("doubleClick") as? Boolean ?: false
                val count = if (doubleClick) 2 else 1
                for (i in 0 until count) {
                    dispatchGestureAction(x, y, "click", result)
                }
            }
            "mouseMove" -> result.success(true)
            "mouseDown" -> {
                val x = (args?.get("x") as? Number)?.toFloat() ?: 0f
                val y = (args?.get("y") as? Number)?.toFloat() ?: 0f
                dispatchGestureAction(x, y, "down", result)
            }
            "mouseUp" -> {
                val x = (args?.get("x") as? Number)?.toFloat() ?: 0f
                val y = (args?.get("y") as? Number)?.toFloat() ?: 0f
                dispatchGestureAction(x, y, "up", result)
            }
            "mouseScroll" -> result.success(true)
            "keyPress" -> {
                val key = args?.get("key") as? String ?: ""
                performKeyPress(key, result)
            }
            "keyRelease" -> result.success(true)
            "keyType" -> result.success(true)
            "getScreenSize" -> {
                val map = mapOf("width" to screenWidth, "height" to screenHeight)
                result.success(map)
            }
            else -> result.notImplemented()
        }
    }

    private fun handlePlatformCall(method: String, args: Any?, result: MethodChannel.Result) {
        when (method) {
            "captureScreenRect" -> {
                captureScreenRect(args, result)
            }
            "getScreenSize" -> {
                val map = mapOf("width" to screenWidth, "height" to screenHeight)
                result.success(map)
            }
            "getCursorPosition" -> {
                result.success(mapOf("x" to 0, "y" to 0))
            }
            "getPixelColor" -> {
                result.success(mapOf("r" to 0, "g" to 0, "b" to 0))
            }
            "startAreaSelectOverlay" -> {
                showOverlay("area", result)
            }
            "startPickOverlay" -> {
                showOverlay("pick", result)
            }
            "startWindowPickOverlay" -> {
                showOverlay("pick", result)
            }
            "stopOverlay" -> {
                removeOverlay()
                result.success(true)
            }
            "showDetectionBoxes" -> {
                showOverlay("detection", result)
            }
            "updateDetectionBoxes" -> {
                result.success(true)
            }
            "saveScreenshot" -> {
                saveScreenshot(args, result)
            }
            "findImage" -> {
                findImage(args, result)
            }
            "ocrRegion" -> {
                ocrRegion(args, result)
            }
            "checkOcrAvailable" -> {
                result.success(mapOf("available" to true))
            }
            "getForegroundWindowTitle" -> {
                result.success("")
            }
            "enumerateWindows" -> {
                result.success(emptyList<Map<String, Any>>())
            }
            "startFastClicker" -> {
                // Clear emergency stop when starting a new click session
                ClickerAccessibilityService.emergencyStopped = false
                ClickerAccessibilityService.gesturePaused = false
                result.success(true)
            }
            "stopFastClicker" -> result.success(true)
            "initSystemTray" -> result.success(true)
            "destroySystemTray" -> result.success(true)
            "enableAutoStart" -> result.success(true)
            "disableAutoStart" -> result.success(true)
            "captureKey" -> result.success(true)
            "showFloatingPanel" -> {
                FloatingControlPanel.show(this)
                result.success(true)
            }
            "hideFloatingPanel" -> {
                FloatingControlPanel.hide(this)
                result.success(true)
            }
            "updateFloatingPanel" -> {
                val running = (args as? Map<*, *>)?.get("running") as? Boolean ?: false
                FloatingControlPanel.updateRunning(running)
                result.success(true)
            }
            "updateFloatingPanelConfig" -> {
                val config = (args as? Map<*, *>)?.mapKeys { it.key.toString() }
                    ?.mapValues { it.value } as? Map<String, Any>
                if (config != null) {
                    FloatingControlPanel.updateConfig(config)
                }
                result.success(true)
            }
            "isAccessibilityEnabled" -> {
                val enabled = isAccessibilityServiceEnabled()
                result.success(enabled)
            }
            "openAccessibilitySettings" -> {
                val intent = Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS)
                intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                startActivity(intent)
                result.success(true)
            }
            "checkOverlayPermission" -> {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                    result.success(Settings.canDrawOverlays(this))
                } else {
                    result.success(true)
                }
            }
            "requestOverlayPermission" -> {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                    if (!Settings.canDrawOverlays(this)) {
                        val intent = Intent(
                            Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                            Uri.parse("package:$packageName")
                        )
                        startActivity(intent)
                    }
                }
                result.success(true)
            }
            else -> result.notImplemented()
        }
    }

    private fun isAccessibilityServiceEnabled(): Boolean {
        // Check if ClickerAccessibilityService is running
        if (ClickerAccessibilityService.instance != null) return true
        // Fallback: check system settings
        val serviceName = "$packageName/.ClickerAccessibilityService"
        val enabledServices = Settings.Secure.getString(
            contentResolver,
            Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES
        ) ?: return false
        return enabledServices.contains(serviceName)
    }

    private fun handleHotkeyCall(method: String, args: Any?, result: MethodChannel.Result) {
        when (method) {
            "registerHotkey" -> result.success(true)
            "unregisterHotkey" -> result.success(true)
            "unregisterAll" -> result.success(true)
            else -> result.notImplemented()
        }
    }

    private fun handleRecordCall(method: String, args: Any?, result: MethodChannel.Result) {
        when (method) {
            "startRecording" -> {
                isRecording = true
                recordStartTime = System.currentTimeMillis()
                result.success(true)
            }
            "stopRecording" -> {
                isRecording = false
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    private fun dispatchGestureAction(
        x: Float, y: Float, action: String, result: MethodChannel.Result,
        durationMs: Int = 300,
        startX: Float = x, startY: Float = y,
        endX: Float = x, endY: Float = y
    ) {
        // Native-level pause check — blocks gestures when floating panel is being used
        if (ClickerAccessibilityService.gesturePaused) {
            android.util.Log.d("Clicker", "dispatchGesture BLOCKED (panel paused)")
            result.success(false)
            return
        }
        if (ClickerAccessibilityService.emergencyStopped) {
            android.util.Log.d("Clicker", "dispatchGesture BLOCKED (emergency stop)")
            result.success(false)
            return
        }

        val service = ClickerAccessibilityService.instance
        if (service == null) {
            android.util.Log.e("Clicker", "dispatchGesture: Accessibility service not running!")
            result.error("NO_ACCESSIBILITY", "Accessibility service not running. Enable it in Settings > Accessibility", null)
            return
        }

        when (action) {
            "click" -> {
                android.util.Log.d("Clicker", "dispatchGesture click at ($x, $y)")
                val path = Path()
                path.moveTo(x, y)
                // 50ms is sufficient for a click and won't block user input
                // Longer durations (200ms+) block touch when interval < duration
                val stroke = GestureDescription.StrokeDescription(path, 0, 50)
                val gesture = GestureDescription.Builder().addStroke(stroke).build()
                val dispatched = service.dispatchGesture(gesture, object : AccessibilityService.GestureResultCallback() {
                    override fun onCompleted(gestureDescription: GestureDescription?) {
                        android.util.Log.d("Clicker", "click gesture completed at ($x, $y)")
                    }
                    override fun onCancelled(gestureDescription: GestureDescription?) {
                        android.util.Log.e("Clicker", "click gesture CANCELLED at ($x, $y)")
                    }
                }, null)
                android.util.Log.d("Clicker", "dispatchGesture call returned: $dispatched")
            }
            "down" -> {
                val path = Path()
                path.moveTo(x, y)
                val stroke = GestureDescription.StrokeDescription(path, 0, 500)
                val gesture = GestureDescription.Builder().addStroke(stroke).build()
                service.dispatchGesture(gesture, null, null)
            }
            "up" -> {
                val path = Path()
                path.moveTo(x, y)
                val stroke = GestureDescription.StrokeDescription(path, 0, 10)
                val gesture = GestureDescription.Builder().addStroke(stroke).build()
                service.dispatchGesture(gesture, null, null)
            }
            "longPress" -> {
                val path = Path()
                path.moveTo(x, y)
                val stroke = GestureDescription.StrokeDescription(path, 0, durationMs.toLong())
                val gesture = GestureDescription.Builder().addStroke(stroke).build()
                service.dispatchGesture(gesture, null, null)
            }
            "drag", "swipe" -> {
                val path = Path()
                path.moveTo(startX, startY)
                // Create intermediate points for smooth gesture
                val steps = (durationMs / 16f).coerceIn(2f, 60f).toInt()
                for (i in 1..steps) {
                    val t = i.toFloat() / steps
                    val cx = startX + (endX - startX) * t
                    val cy = startY + (endY - startY) * t
                    path.lineTo(cx, cy)
                }
                val stroke = GestureDescription.StrokeDescription(path, 0, durationMs.toLong())
                val gesture = GestureDescription.Builder().addStroke(stroke).build()
                service.dispatchGesture(gesture, null, null)
            }
        }
        result.success(true)
    }

    private fun performKeyPress(key: String, result: MethodChannel.Result) {
        val service = ClickerAccessibilityService.instance
        if (service == null) {
            result.error("NO_ACCESSIBILITY", "Accessibility service not running", null)
            return
        }

        when (key.lowercase()) {
            "home" -> service.performGlobalAction(AccessibilityService.GLOBAL_ACTION_HOME)
            "back" -> service.performGlobalAction(AccessibilityService.GLOBAL_ACTION_BACK)
            "recents" -> service.performGlobalAction(AccessibilityService.GLOBAL_ACTION_RECENTS)
            "notifications" -> service.performGlobalAction(AccessibilityService.GLOBAL_ACTION_NOTIFICATIONS)
            "quick_settings" -> service.performGlobalAction(AccessibilityService.GLOBAL_ACTION_QUICK_SETTINGS)
            "power_dialog" -> {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
                    service.performGlobalAction(AccessibilityService.GLOBAL_ACTION_POWER_DIALOG)
                }
            }
            "lock_screen" -> {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                    service.performGlobalAction(AccessibilityService.GLOBAL_ACTION_LOCK_SCREEN)
                }
            }
            "take_screenshot" -> {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                    service.performGlobalAction(AccessibilityService.GLOBAL_ACTION_TAKE_SCREENSHOT)
                }
            }
        }
        result.success(true)
    }

    @TargetApi(Build.VERSION_CODES.LOLLIPOP)
    private fun captureScreenRect(args: Any?, result: MethodChannel.Result) {
        if (mediaProjection == null) {
            requestScreenCapture(result)
            return
        }

        val argList = args as? List<Any>
        if (argList == null || argList.size < 4) {
            result.error("INVALID_ARGS", "Expected [x, y, w, h]", null)
            return
        }

        val x = (argList[0] as? Number)?.toInt() ?: 0
        val y = (argList[1] as? Number)?.toInt() ?: 0
        val w = (argList[2] as? Number)?.toInt() ?: screenWidth
        val h = (argList[3] as? Number)?.toInt() ?: screenHeight

        captureAndReturn(x, y, w, h, result)
    }

    @TargetApi(Build.VERSION_CODES.LOLLIPOP)
    private fun requestScreenCapture(result: MethodChannel.Result) {
        projectionResult = result
        try {
            val mgr = getSystemService(Context.MEDIA_PROJECTION_SERVICE) as MediaProjectionManager
            startActivityForResult(mgr.createScreenCaptureIntent(), REQUEST_MEDIA_PROJECTION)
        } catch (e: Exception) {
            projectionResult = null
            result.error("PROJECTION_ERROR", e.message, null)
        }
    }

    @TargetApi(Build.VERSION_CODES.LOLLIPOP)
    private fun setupVirtualDisplay() {
        if (imageReader == null) {
            imageReader = ImageReader.newInstance(screenWidth, screenHeight, PixelFormat.RGBA_8888, 2)
        }

        virtualDisplay = mediaProjection?.createVirtualDisplay(
            "ClickerScreenCapture",
            screenWidth, screenHeight, screenDensity,
            DisplayManager.VIRTUAL_DISPLAY_FLAG_AUTO_MIRROR,
            imageReader?.surface, null, null
        )
    }

    @TargetApi(Build.VERSION_CODES.LOLLIPOP)
    private fun captureAndReturn(x: Int, y: Int, w: Int, h: Int, result: MethodChannel.Result) {
        try {
            val image: Image? = imageReader?.acquireLatestImage()
            if (image == null) {
                result.error("CAPTURE_FAILED", "No image available from VirtualDisplay", null)
                return
            }

            val planes = image.planes
            val buffer: ByteBuffer = planes[0].buffer
            val pixelStride = planes[0].pixelStride
            val rowStride = planes[0].rowStride
            val rowPadding = rowStride - pixelStride * screenWidth

            val bitmap = Bitmap.createBitmap(
                screenWidth + rowPadding / pixelStride, screenHeight,
                Bitmap.Config.ARGB_8888
            )
            bitmap.copyPixelsFromBuffer(buffer)
            image.close()

            val clampedX = x.coerceAtLeast(0).coerceAtMost(screenWidth - 1)
            val clampedY = y.coerceAtLeast(0).coerceAtMost(screenHeight - 1)
            val clampedW = w.coerceAtMost(screenWidth - clampedX)
            val clampedH = h.coerceAtMost(screenHeight - clampedY)

            if (clampedW <= 0 || clampedH <= 0) {
                result.error("CAPTURE_FAILED", "Invalid capture region", null)
                return
            }

            val cropped = Bitmap.createBitmap(bitmap, clampedX, clampedY, clampedW, clampedH)

            val pixels = IntArray(clampedW * clampedH)
            cropped.getPixels(pixels, 0, clampedW, 0, 0, clampedW, clampedH)

            val bytes = ByteArray(clampedW * clampedH * 4)
            for (i in pixels.indices) {
                val pixel = pixels[i]
                val idx = i * 4
                bytes[idx] = (pixel and 0xFF).toByte()
                bytes[idx + 1] = ((pixel shr 8) and 0xFF).toByte()
                bytes[idx + 2] = ((pixel shr 16) and 0xFF).toByte()
                bytes[idx + 3] = 0xFF.toByte()
            }

            result.success(bytes)
        } catch (e: Exception) {
            result.error("CAPTURE_FAILED", e.message, null)
        }
    }

    @TargetApi(Build.VERSION_CODES.LOLLIPOP)
    private fun saveScreenshot(args: Any?, result: MethodChannel.Result) {
        val argList = args as? List<Any>
        if (argList == null || argList.size < 5) {
            result.error("INVALID_ARGS", "Expected [x, y, w, h, path]", null)
            return
        }

        val x = (argList[0] as? Number)?.toInt() ?: 0
        val y = (argList[1] as? Number)?.toInt() ?: 0
        val w = (argList[2] as? Number)?.toInt() ?: screenWidth
        val h = (argList[3] as? Number)?.toInt() ?: screenHeight
        val path = argList[4] as? String ?: ""

        if (mediaProjection == null) {
            result.error("NO_PROJECTION", "Screen capture not initialized", null)
            return
        }

        try {
            val image: Image? = imageReader?.acquireLatestImage()
            if (image == null) {
                result.error("CAPTURE_FAILED", "No image available", null)
                return
            }

            val planes = image.planes
            val buffer: ByteBuffer = planes[0].buffer
            val pixelStride = planes[0].pixelStride
            val rowStride = planes[0].rowStride
            val rowPadding = rowStride - pixelStride * screenWidth

            val bitmap = Bitmap.createBitmap(
                screenWidth + rowPadding / pixelStride, screenHeight,
                Bitmap.Config.ARGB_8888
            )
            bitmap.copyPixelsFromBuffer(buffer)
            image.close()

            val cropped = Bitmap.createBitmap(bitmap,
                x.coerceAtLeast(0).coerceAtMost(screenWidth - 1),
                y.coerceAtLeast(0).coerceAtMost(screenHeight - 1),
                w.coerceAtMost(screenWidth - x), h.coerceAtMost(screenHeight - y)
            )

            val fos = FileOutputStream(path)
            cropped.compress(Bitmap.CompressFormat.PNG, 100, fos)
            fos.close()
            result.success(true)
        } catch (e: Exception) {
            result.error("SAVE_FAILED", e.message, null)
        }
    }

    private fun showOverlay(mode: String, result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            if (!android.provider.Settings.canDrawOverlays(this)) {
                val intent = Intent(
                    android.provider.Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                    android.net.Uri.parse("package:$packageName")
                )
                startActivity(intent)
                result.error("OVERLAY_PERMISSION", "Overlay permission required. Enable in Settings > Display over other apps", null)
                return
            }
        }

        removeOverlay()

        val windowManager = getSystemService(Context.WINDOW_SERVICE) as WindowManager
        val params = WindowManager.LayoutParams(
            WindowManager.LayoutParams.MATCH_PARENT,
            WindowManager.LayoutParams.MATCH_PARENT,
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O)
                WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
            else
                @Suppress("DEPRECATION")
                WindowManager.LayoutParams.TYPE_SYSTEM_ALERT,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                    WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL or
                    WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN,
            PixelFormat.TRANSLUCENT
        )
        params.gravity = Gravity.TOP or Gravity.START

        // Create a frame layout with hint text
        val container = android.widget.FrameLayout(this)

        // Semi-transparent background
        val bgView = android.view.View(this)
        bgView.setBackgroundColor(0x40000000.toInt())
        container.addView(bgView, android.widget.FrameLayout.LayoutParams(
            android.widget.FrameLayout.LayoutParams.MATCH_PARENT,
            android.widget.FrameLayout.LayoutParams.MATCH_PARENT
        ))

        // Hint text
        val hintText = android.widget.TextView(this).apply {
            text = if (mode == "pick") "点击屏幕选取坐标" else "拖拽选取区域"
            setTextColor(android.graphics.Color.WHITE)
            setTextSize(android.util.TypedValue.COMPLEX_UNIT_SP, 18f)
            setTypeface(null, android.graphics.Typeface.BOLD)
            gravity = android.view.Gravity.CENTER
            setShadowLayer(4f, 1f, 1f, android.graphics.Color.BLACK)
        }
        val hintParams = android.widget.FrameLayout.LayoutParams(
            android.widget.FrameLayout.LayoutParams.WRAP_CONTENT,
            android.widget.FrameLayout.LayoutParams.WRAP_CONTENT
        ).apply {
            gravity = android.view.Gravity.CENTER
        }
        container.addView(hintText, hintParams)

        // Cancel button at top-right
        val cancelBtn = android.widget.TextView(this).apply {
            text = "✕"
            setTextColor(android.graphics.Color.WHITE)
            setTextSize(android.util.TypedValue.COMPLEX_UNIT_SP, 22f)
            setPadding((16 * resources.displayMetrics.density).toInt(),
                       (8 * resources.displayMetrics.density).toInt(),
                       (16 * resources.displayMetrics.density).toInt(),
                       (8 * resources.displayMetrics.density).toInt())
            setShadowLayer(4f, 1f, 1f, android.graphics.Color.BLACK)
        }
        val cancelParams = android.widget.FrameLayout.LayoutParams(
            android.widget.FrameLayout.LayoutParams.WRAP_CONTENT,
            android.widget.FrameLayout.LayoutParams.WRAP_CONTENT
        ).apply {
            gravity = android.view.Gravity.TOP or android.view.Gravity.END
            topMargin = (32 * resources.displayMetrics.density).toInt()
            rightMargin = (16 * resources.displayMetrics.density).toInt()
        }
        container.addView(cancelBtn, cancelParams)

        cancelBtn.setOnClickListener {
            val channel = flutterEngine?.dartExecutor?.binaryMessenger?.let {
                MethodChannel(it, PLATFORM_CHANNEL)
            }
            channel?.invokeMethod("onOverlayCancelled", null)
            removeOverlay()
        }

        val channel = flutterEngine?.dartExecutor?.binaryMessenger?.let {
            MethodChannel(it, PLATFORM_CHANNEL)
        }

        if (mode == "pick") {
            // Pick mode: single click to get coordinates
            container.setOnTouchListener { view, event ->
                when (event.action) {
                    android.view.MotionEvent.ACTION_DOWN -> true
                    android.view.MotionEvent.ACTION_UP -> {
                        channel?.invokeMethod("onOverlayClick", mapOf(
                            "x" to event.rawX.toInt(),
                            "y" to event.rawY.toInt()
                        ))
                        removeOverlay()
                    }
                }
                true
            }
        } else {
            // Area select mode: drag to select area
            var startX = 0
            var startY = 0
            container.setOnTouchListener { view, event ->
                when (event.action) {
                    android.view.MotionEvent.ACTION_DOWN -> {
                        startX = event.rawX.toInt()
                        startY = event.rawY.toInt()
                    }
                    android.view.MotionEvent.ACTION_UP -> {
                        val endX = event.rawX.toInt()
                        val endY = event.rawY.toInt()
                        channel?.invokeMethod("onOverlayAreaSelected", mapOf(
                            "x1" to minOf(startX, endX),
                            "y1" to minOf(startY, endY),
                            "x2" to maxOf(startX, endX),
                            "y2" to maxOf(startY, endY)
                        ))
                        removeOverlay()
                    }
                }
                true
            }
        }

        windowManager.addView(container, params)
        this.overlayView = container
        result.success(true)
    }

    private fun removeOverlay() {
        overlayView?.let {
            val windowManager = getSystemService(Context.WINDOW_SERVICE) as WindowManager
            try {
                windowManager.removeView(it)
            } catch (_: Exception) {}
            overlayView = null
        }
    }

    // ─── Floating Panel Coordinate Pick ──────────────────────

    fun startPickOverlayFromFloating(callback: (Int, Int) -> Unit) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            if (!android.provider.Settings.canDrawOverlays(this)) return
        }
        removeOverlay()

        val windowManager = getSystemService(Context.WINDOW_SERVICE) as WindowManager
        val params = WindowManager.LayoutParams(
            WindowManager.LayoutParams.MATCH_PARENT,
            WindowManager.LayoutParams.MATCH_PARENT,
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O)
                WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
            else @Suppress("DEPRECATION") WindowManager.LayoutParams.TYPE_SYSTEM_ALERT,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                    WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL or
                    WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN,
            PixelFormat.TRANSLUCENT
        )
        params.gravity = Gravity.TOP or Gravity.START

        val container = android.widget.FrameLayout(this)

        val bgView = android.view.View(this)
        bgView.setBackgroundColor(0x40000000.toInt())
        container.addView(bgView, android.widget.FrameLayout.LayoutParams(
            android.widget.FrameLayout.LayoutParams.MATCH_PARENT,
            android.widget.FrameLayout.LayoutParams.MATCH_PARENT
        ))

        val hintText = android.widget.TextView(this).apply {
            text = "点击屏幕选取坐标"
            setTextColor(android.graphics.Color.WHITE)
            setTextSize(android.util.TypedValue.COMPLEX_UNIT_SP, 18f)
            setTypeface(null, android.graphics.Typeface.BOLD)
            gravity = android.view.Gravity.CENTER
            setShadowLayer(4f, 1f, 1f, android.graphics.Color.BLACK)
        }
        container.addView(hintText, android.widget.FrameLayout.LayoutParams(
            android.widget.FrameLayout.LayoutParams.WRAP_CONTENT,
            android.widget.FrameLayout.LayoutParams.WRAP_CONTENT
        ).apply { gravity = android.view.Gravity.CENTER })

        val cancelBtn = android.widget.TextView(this).apply {
            text = "✕"
            setTextColor(android.graphics.Color.WHITE)
            setTextSize(android.util.TypedValue.COMPLEX_UNIT_SP, 22f)
            setPadding((16 * resources.displayMetrics.density).toInt(),
                       (8 * resources.displayMetrics.density).toInt(),
                       (16 * resources.displayMetrics.density).toInt(),
                       (8 * resources.displayMetrics.density).toInt())
            setShadowLayer(4f, 1f, 1f, android.graphics.Color.BLACK)
        }
        container.addView(cancelBtn, android.widget.FrameLayout.LayoutParams(
            android.widget.FrameLayout.LayoutParams.WRAP_CONTENT,
            android.widget.FrameLayout.LayoutParams.WRAP_CONTENT
        ).apply {
            gravity = android.view.Gravity.TOP or android.view.Gravity.END
            topMargin = (32 * resources.displayMetrics.density).toInt()
            rightMargin = (16 * resources.displayMetrics.density).toInt()
        })

        cancelBtn.setOnClickListener { removeOverlay() }

        container.setOnTouchListener { _, event ->
            when (event.action) {
                android.view.MotionEvent.ACTION_DOWN -> true
                android.view.MotionEvent.ACTION_UP -> {
                    callback(event.rawX.toInt(), event.rawY.toInt())
                    removeOverlay()
                }
            }
            true
        }

        windowManager.addView(container, params)
        this.overlayView = container
    }

    fun startAreaOverlayFromFloating(callback: (Int, Int, Int, Int) -> Unit) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            if (!android.provider.Settings.canDrawOverlays(this)) return
        }
        removeOverlay()

        val windowManager = getSystemService(Context.WINDOW_SERVICE) as WindowManager
        val params = WindowManager.LayoutParams(
            WindowManager.LayoutParams.MATCH_PARENT,
            WindowManager.LayoutParams.MATCH_PARENT,
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O)
                WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
            else @Suppress("DEPRECATION") WindowManager.LayoutParams.TYPE_SYSTEM_ALERT,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                    WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL or
                    WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN,
            PixelFormat.TRANSLUCENT
        )
        params.gravity = Gravity.TOP or Gravity.START

        val container = android.widget.FrameLayout(this)

        val bgView = android.view.View(this)
        bgView.setBackgroundColor(0x40000000.toInt())
        container.addView(bgView, android.widget.FrameLayout.LayoutParams(
            android.widget.FrameLayout.LayoutParams.MATCH_PARENT,
            android.widget.FrameLayout.LayoutParams.MATCH_PARENT
        ))

        val hintText = android.widget.TextView(this).apply {
            text = "拖拽选取区域"
            setTextColor(android.graphics.Color.WHITE)
            setTextSize(android.util.TypedValue.COMPLEX_UNIT_SP, 18f)
            setTypeface(null, android.graphics.Typeface.BOLD)
            gravity = android.view.Gravity.CENTER
            setShadowLayer(4f, 1f, 1f, android.graphics.Color.BLACK)
        }
        container.addView(hintText, android.widget.FrameLayout.LayoutParams(
            android.widget.FrameLayout.LayoutParams.WRAP_CONTENT,
            android.widget.FrameLayout.LayoutParams.WRAP_CONTENT
        ).apply { gravity = android.view.Gravity.CENTER })

        val cancelBtn = android.widget.TextView(this).apply {
            text = "✕"
            setTextColor(android.graphics.Color.WHITE)
            setTextSize(android.util.TypedValue.COMPLEX_UNIT_SP, 22f)
            setPadding((16 * resources.displayMetrics.density).toInt(),
                       (8 * resources.displayMetrics.density).toInt(),
                       (16 * resources.displayMetrics.density).toInt(),
                       (8 * resources.displayMetrics.density).toInt())
            setShadowLayer(4f, 1f, 1f, android.graphics.Color.BLACK)
        }
        container.addView(cancelBtn, android.widget.FrameLayout.LayoutParams(
            android.widget.FrameLayout.LayoutParams.WRAP_CONTENT,
            android.widget.FrameLayout.LayoutParams.WRAP_CONTENT
        ).apply {
            gravity = android.view.Gravity.TOP or android.view.Gravity.END
            topMargin = (32 * resources.displayMetrics.density).toInt()
            rightMargin = (16 * resources.displayMetrics.density).toInt()
        })

        cancelBtn.setOnClickListener { removeOverlay() }

        var startX = 0
        var startY = 0
        container.setOnTouchListener { _, event ->
            when (event.action) {
                android.view.MotionEvent.ACTION_DOWN -> {
                    startX = event.rawX.toInt()
                    startY = event.rawY.toInt()
                }
                android.view.MotionEvent.ACTION_UP -> {
                    val endX = event.rawX.toInt()
                    val endY = event.rawY.toInt()
                    callback(minOf(startX, endX), minOf(startY, endY),
                             maxOf(startX, endX), maxOf(startY, endY))
                    removeOverlay()
                }
            }
            true
        }

        windowManager.addView(container, params)
        this.overlayView = container
    }

    @TargetApi(Build.VERSION_CODES.LOLLIPOP)
    private fun stopScreenCapture() {
        virtualDisplay?.release()
        virtualDisplay = null
        imageReader?.close()
        imageReader = null
        mediaProjection?.stop()
        mediaProjection = null
    }

    @TargetApi(Build.VERSION_CODES.LOLLIPOP)
    private fun captureRegionBitmap(x: Int, y: Int, w: Int, h: Int): Bitmap? {
        val image = imageReader?.acquireLatestImage() ?: return null
        try {
            val planes = image.planes
            val buffer: ByteBuffer = planes[0].buffer
            val pixelStride = planes[0].pixelStride
            val rowStride = planes[0].rowStride
            val rowPadding = rowStride - pixelStride * screenWidth

            val fullBitmap = Bitmap.createBitmap(
                screenWidth + rowPadding / pixelStride, screenHeight,
                Bitmap.Config.ARGB_8888
            )
            fullBitmap.copyPixelsFromBuffer(buffer)
            image.close()

            val cx = x.coerceAtLeast(0).coerceAtMost(screenWidth - 1)
            val cy = y.coerceAtLeast(0).coerceAtMost(screenHeight - 1)
            val cw = w.coerceAtMost(screenWidth - cx)
            val ch = h.coerceAtMost(screenHeight - cy)
            if (cw <= 0 || ch <= 0) return null

            return Bitmap.createBitmap(fullBitmap, cx, cy, cw, ch)
        } catch (e: Exception) {
            image.close()
            return null
        }
    }

    @TargetApi(Build.VERSION_CODES.LOLLIPOP)
    private fun findImage(args: Any?, result: MethodChannel.Result) {
        if (mediaProjection == null) {
            result.error("NO_PROJECTION", "Screen capture not initialized", null)
            return
        }

        val argList = args as? List<Any>
        if (argList == null || argList.size < 8) {
            result.error("INVALID_ARGS", "Expected [regionX, regionY, regionW, regionH, tplBytes, tplW, tplH, threshold]", null)
            return
        }

        val regionX = (argList[0] as? Number)?.toInt() ?: 0
        val regionY = (argList[1] as? Number)?.toInt() ?: 0
        val regionW = (argList[2] as? Number)?.toInt() ?: screenWidth
        val regionH = (argList[3] as? Number)?.toInt() ?: screenHeight
        val tplBytes = argList[4] as? ByteArray ?: byteArrayOf()
        val tplW = (argList[5] as? Number)?.toInt() ?: 0
        val tplH = (argList[6] as? Number)?.toInt() ?: 0
        val threshold = (argList[7] as? Number)?.toDouble() ?: 0.8

        if (tplW <= 0 || tplH <= 0 || tplBytes.size < tplW * tplH * 4) {
            result.success(emptyList<Map<String, Any>>())
            return
        }

        val regionBitmap = captureRegionBitmap(regionX, regionY, regionW, regionH)
        if (regionBitmap == null) {
            result.error("CAPTURE_FAILED", "Failed to capture screen region", null)
            return
        }

        Thread {
            try {
                val regionPixels = IntArray(regionW * regionH)
                regionBitmap.getPixels(regionPixels, 0, regionW, 0, 0, regionW, regionH)

                val tplPixels = IntArray(tplW * tplH)
                for (i in 0 until tplW * tplH) {
                    val idx = i * 4
                    val b = tplBytes[idx].toInt() and 0xFF
                    val g = tplBytes[idx + 1].toInt() and 0xFF
                    val r = tplBytes[idx + 2].toInt() and 0xFF
                    tplPixels[i] = (0xFF shl 24) or (r shl 16) or (g shl 8) or b
                }

                var tplMeanR = 0.0
                var tplMeanG = 0.0
                var tplMeanB = 0.0
                for (i in tplPixels.indices) {
                    val px = tplPixels[i]
                    tplMeanR += (px shr 16 and 0xFF)
                    tplMeanG += (px shr 8 and 0xFF)
                    tplMeanB += (px and 0xFF)
                }
                val tplN = tplPixels.size.toDouble()
                tplMeanR /= tplN
                tplMeanG /= tplN
                tplMeanB /= tplN

                var tplVarSum = 0.0
                for (i in tplPixels.indices) {
                    val px = tplPixels[i]
                    val dr = (px shr 16 and 0xFF) - tplMeanR
                    val dg = (px shr 8 and 0xFF) - tplMeanG
                    val db = (px and 0xFF) - tplMeanB
                    tplVarSum += dr * dr + dg * dg + db * db
                }
                val tplStdDev = Math.sqrt(tplVarSum / (tplN * 3))
                if (tplStdDev < 1.0) {
                    runOnUiThread { result.success(emptyList<Map<String, Any>>()) }
                    return@Thread
                }

                val coarseStep = maxOf(2, minOf(tplW, tplH) / 8)
                val searchW = regionW - tplW
                val searchH = regionH - tplH

                data class Candidate(val sx: Int, val sy: Int, val score: Double)

                val candidates = mutableListOf<Candidate>()
                for (sy in 0..searchH step coarseStep) {
                    for (sx in 0..searchW step coarseStep) {
                        var nccNum = 0.0
                        var regVarSum = 0.0
                        var regMeanR = 0.0
                        var regMeanG = 0.0
                        var regMeanB = 0.0

                        for (ty in 0 until tplH step 2) {
                            for (tx in 0 until tplW step 2) {
                                val rIdx = (sy + ty) * regionW + (sx + tx)
                                val rpx = regionPixels[rIdx]
                                regMeanR += (rpx shr 16 and 0xFF)
                                regMeanG += (rpx shr 8 and 0xFF)
                                regMeanB += (rpx and 0xFF)
                            }
                        }
                        val sampleN = ((tplH + 1) / 2) * ((tplW + 1) / 2).toDouble()
                        regMeanR /= sampleN
                        regMeanG /= sampleN
                        regMeanB /= sampleN

                        for (ty in 0 until tplH step 2) {
                            for (tx in 0 until tplW step 2) {
                                val rIdx = (sy + ty) * regionW + (sx + tx)
                                val rpx = regionPixels[rIdx]
                                val tpx = tplPixels[ty * tplW + tx]

                                val rdR = (rpx shr 16 and 0xFF) - regMeanR
                                val rdG = (rpx shr 8 and 0xFF) - regMeanG
                                val rdB = (rpx and 0xFF) - regMeanB
                                val tdR = (tpx shr 16 and 0xFF) - tplMeanR
                                val tdG = (tpx shr 8 and 0xFF) - tplMeanG
                                val tdB = (tpx and 0xFF) - tplMeanB
                                nccNum += rdR * tdR + rdG * tdG + rdB * tdB
                                regVarSum += rdR * rdR + rdG * rdG + rdB * rdB
                            }
                        }

                        val regStdDev = Math.sqrt(regVarSum / (sampleN * 3))
                        val ncc = if (regStdDev > 0.5) nccNum / (sampleN * 3 * tplStdDev * regStdDev) else 0.0
                        val clampedNcc = ncc.coerceIn(0.0, 1.0)

                        if (clampedNcc >= threshold - 0.15) {
                            candidates.add(Candidate(sx, sy, clampedNcc))
                        }
                    }
                }

                candidates.sortByDescending { it.score }
                val topCandidates = candidates.take(20)

                var bestScore = -1.0
                var bestX = -1
                var bestY = -1

                val fineRadius = coarseStep
                for (cand in topCandidates) {
                    for (dy in -fineRadius..fineRadius) {
                        for (dx in -fineRadius..fineRadius) {
                            val sx = cand.sx + dx
                            val sy = cand.sy + dy
                            if (sx < 0 || sy < 0 || sx > searchW || sy > searchH) continue

                            var nccNum = 0.0
                            var regVarSum = 0.0
                            var regMeanR = 0.0
                            var regMeanG = 0.0
                            var regMeanB = 0.0

                            for (ty in 0 until tplH) {
                                for (tx in 0 until tplW) {
                                    val rIdx = (sy + ty) * regionW + (sx + tx)
                                    val rpx = regionPixels[rIdx]
                                    regMeanR += (rpx shr 16 and 0xFF)
                                    regMeanG += (rpx shr 8 and 0xFF)
                                    regMeanB += (rpx and 0xFF)
                                }
                            }
                            regMeanR /= tplN
                            regMeanG /= tplN
                            regMeanB /= tplN

                            for (ty in 0 until tplH) {
                                for (tx in 0 until tplW) {
                                    val rIdx = (sy + ty) * regionW + (sx + tx)
                                    val rpx = regionPixels[rIdx]
                                    val tpx = tplPixels[ty * tplW + tx]

                                    val rdR = (rpx shr 16 and 0xFF) - regMeanR
                                    val rdG = (rpx shr 8 and 0xFF) - regMeanG
                                    val rdB = (rpx and 0xFF) - regMeanB
                                    val tdR = (tpx shr 16 and 0xFF) - tplMeanR
                                    val tdG = (tpx shr 8 and 0xFF) - tplMeanG
                                    val tdB = (tpx and 0xFF) - tplMeanB
                                    nccNum += rdR * tdR + rdG * tdG + rdB * tdB
                                    regVarSum += rdR * rdR + rdG * rdG + rdB * rdB
                                }
                            }

                            val regStdDev = Math.sqrt(regVarSum / (tplN * 3))
                            val ncc = if (regStdDev > 0.5) nccNum / (tplN * 3 * tplStdDev * regStdDev) else 0.0
                            val clampedNcc = ncc.coerceIn(0.0, 1.0)

                            if (clampedNcc >= threshold && clampedNcc > bestScore) {
                                bestScore = clampedNcc
                                bestX = regionX + sx
                                bestY = regionY + sy
                            }
                        }
                    }
                }

                val matches = mutableListOf<Map<String, Any>>()
                if (bestX >= 0 && bestY >= 0) {
                    matches.add(mapOf(
                        "x" to bestX,
                        "y" to bestY,
                        "width" to tplW,
                        "height" to tplH,
                        "score" to bestScore
                    ))
                }

                runOnUiThread { result.success(matches) }
            } catch (e: Exception) {
                runOnUiThread { result.error("FIND_FAILED", e.message, null) }
            }
        }.start()
    }

    @TargetApi(Build.VERSION_CODES.LOLLIPOP)
    private fun ocrRegion(args: Any?, result: MethodChannel.Result) {
        if (mediaProjection == null) {
            result.error("NO_PROJECTION", "Screen capture not initialized", null)
            return
        }

        val argList = args as? List<Any>
        if (argList == null || argList.size < 4) {
            result.error("INVALID_ARGS", "Expected [x, y, w, h, language?]", null)
            return
        }

        val x = (argList[0] as? Number)?.toInt() ?: 0
        val y = (argList[1] as? Number)?.toInt() ?: 0
        val w = (argList[2] as? Number)?.toInt() ?: screenWidth
        val h = (argList[3] as? Number)?.toInt() ?: screenHeight

        val bitmap = captureRegionBitmap(x, y, w, h)
        if (bitmap == null) {
            result.error("CAPTURE_FAILED", "Failed to capture screen region for OCR", null)
            return
        }

        // ML Kit is only available in the "full" flavor.
        // In the "lite" flavor, the dependency is not included.
        try {
            val inputImageClass = Class.forName("com.google.mlkit.vision.common.InputImage")
            val fromBitmap = inputImageClass.getMethod("fromBitmap", Bitmap::class.java, Int::class.javaPrimitiveType)
            val image = fromBitmap.invoke(null, bitmap, 0)

            val optionsClass = Class.forName("com.google.mlkit.vision.text.chinese.ChineseTextRecognizerOptions")
            val optionsCtor = optionsClass.getConstructor()
            val optionsBuilder = optionsCtor.newInstance()
            val buildMethod = optionsClass.getMethod("build")
            val options = buildMethod.invoke(optionsBuilder)

            val textRecognitionClass = Class.forName("com.google.mlkit.vision.text.TextRecognition")
            val getClientMethod = textRecognitionClass.getMethod("getClient", optionsClass)
            val recognizer = getClientMethod.invoke(null, options)

            val processMethod = recognizer.javaClass.getMethod("process", inputImageClass)
            val task = processMethod.invoke(recognizer, image)

            // Use reflection to call addOnSuccessListener / addOnFailureListener
            // since com.google.android.gms.tasks.Task may not be on classpath in lite flavor
            val onSuccessListenerClass = Class.forName("com.google.android.gms.tasks.OnSuccessListener")
            val onFailureListenerClass = Class.forName("com.google.android.gms.tasks.OnFailureListener")

            val onSuccessProxy = java.lang.reflect.Proxy.newProxyInstance(
                onSuccessListenerClass.classLoader,
                arrayOf(onSuccessListenerClass)
            ) { _, method, args ->
                if (method.name == "onSuccess" && args != null && args.isNotEmpty()) {
                    try {
                        val textMethod = args[0]!!.javaClass.getMethod("getText")
                        val text = textMethod.invoke(args[0]) as? String ?: ""
                        result.success(mapOf(
                            "text" to text,
                            "x" to x,
                            "y" to y,
                            "width" to w,
                            "height" to h
                        ))
                    } catch (e: Exception) {
                        result.success(mapOf("text" to "", "x" to x, "y" to y, "width" to w, "height" to h))
                    }
                }
                null
            }

            val onFailureProxy = java.lang.reflect.Proxy.newProxyInstance(
                onFailureListenerClass.classLoader,
                arrayOf(onFailureListenerClass)
            ) { _, method, args ->
                if (method.name == "onFailure" && args != null && args.isNotEmpty()) {
                    val exception = args[0] as? Exception
                    result.error("OCR_FAILED", exception?.message, null)
                }
                null
            }

            val addOnSuccessListener = task.javaClass.getMethod("addOnSuccessListener", onSuccessListenerClass)
            val addOnFailureListener = task.javaClass.getMethod("addOnFailureListener", onFailureListenerClass)

            addOnSuccessListener.invoke(task, onSuccessProxy)
            addOnFailureListener.invoke(task, onFailureProxy)
        } catch (e: ClassNotFoundException) {
            result.error("OCR_NOT_AVAILABLE",
                "ML Kit not available. Install the full version or download the OCR module in Settings.", null)
        } catch (e: Exception) {
            result.error("OCR_FAILED", e.message, null)
        }
    }
}
