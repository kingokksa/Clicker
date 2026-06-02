package com.clicker.app

import android.accessibilityservice.AccessibilityService
import android.accessibilityservice.GestureDescription
import android.annotation.TargetApi
import android.app.Activity
import android.app.Service
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
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
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

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        instance = this

        val metrics = resources.displayMetrics
        screenDensity = metrics.densityDpi
        screenWidth = metrics.widthPixels
        screenHeight = metrics.heightPixels

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
                dispatchGestureAction(x, y, action, result)
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
                result.success(emptyList<Map<String, Any>>())
            }
            "ocrRegion" -> {
                result.error("OCR_NOT_AVAILABLE", "OCR not available on Android", null)
            }
            "getForegroundWindowTitle" -> {
                result.success("")
            }
            "enumerateWindows" -> {
                result.success(emptyList<Map<String, Any>>())
            }
            "startFastClicker" -> result.success(true)
            "stopFastClicker" -> result.success(true)
            "initSystemTray" -> result.success(true)
            "destroySystemTray" -> result.success(true)
            "enableAutoStart" -> result.success(true)
            "disableAutoStart" -> result.success(true)
            "captureKey" -> result.success(true)
            else -> result.notImplemented()
        }
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

    private fun dispatchGestureAction(x: Float, y: Float, action: String, result: MethodChannel.Result) {
        val service = ClickerAccessibilityService.instance
        if (service == null) {
            result.error("NO_ACCESSIBILITY", "Accessibility service not running. Enable it in Settings > Accessibility", null)
            return
        }

        val path = Path()
        path.moveTo(x, y)

        when (action) {
            "click" -> {
                val stroke = GestureDescription.StrokeDescription(path, 0, 50)
                val gesture = GestureDescription.Builder().addStroke(stroke).build()
                service.dispatchGesture(gesture, null, null)
            }
            "down" -> {
                val stroke = GestureDescription.StrokeDescription(path, 0, 500)
                val gesture = GestureDescription.Builder().addStroke(stroke).build()
                service.dispatchGesture(gesture, null, null)
            }
            "up" -> {
                val stroke = GestureDescription.StrokeDescription(path, 0, 10)
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

        val overlayView = android.view.View(this)
        overlayView.setBackgroundColor(android.graphics.Color.TRANSPARENT)
        overlayView.setOnTouchListener { view, event ->
            when (event.action) {
                android.view.MotionEvent.ACTION_DOWN -> {
                    val channel = flutterEngine?.dartExecutor?.binaryMessenger?.let {
                        MethodChannel(it, PLATFORM_CHANNEL)
                    }
                    channel?.invokeMethod("onOverlayAreaSelected", mapOf(
                        "x1" to event.rawX.toInt(),
                        "y1" to event.rawY.toInt(),
                        "x2" to event.rawX.toInt(),
                        "y2" to event.rawY.toInt()
                    ))
                }
                android.view.MotionEvent.ACTION_UP -> {
                    val channel = flutterEngine?.dartExecutor?.binaryMessenger?.let {
                        MethodChannel(it, PLATFORM_CHANNEL)
                    }
                    channel?.invokeMethod("onOverlayAreaSelected", mapOf(
                        "x1" to 0,
                        "y1" to 0,
                        "x2" to event.rawX.toInt(),
                        "y2" to event.rawY.toInt()
                    ))
                    removeOverlay()
                }
            }
            true
        }

        windowManager.addView(overlayView, params)
        this.overlayView = overlayView
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

    @TargetApi(Build.VERSION_CODES.LOLLIPOP)
    private fun stopScreenCapture() {
        virtualDisplay?.release()
        virtualDisplay = null
        imageReader?.close()
        imageReader = null
        mediaProjection?.stop()
        mediaProjection = null
    }
}
