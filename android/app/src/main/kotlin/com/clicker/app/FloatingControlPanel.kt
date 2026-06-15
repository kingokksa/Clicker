package com.clicker.app

import android.annotation.SuppressLint
import android.content.Context
import android.content.SharedPreferences
import android.graphics.Color
import android.graphics.PixelFormat
import android.graphics.drawable.GradientDrawable
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.util.TypedValue
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.view.WindowManager
import android.widget.FrameLayout
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.TextView
import io.flutter.plugin.common.MethodChannel

/**
 * Expandable floating control panel for mobile.
 * Collapsed: small draggable FAB with play/stop.
 * Expanded: full control panel with action type, interval, repeat mode, etc.
 */
class FloatingControlPanel(private val context: Context) {

    companion object {
        private const val PLATFORM_CHANNEL = "com.clicker.pro/platform"
        private var instance: FloatingControlPanel? = null

        fun show(context: Context) {
            if (instance == null) {
                instance = FloatingControlPanel(context)
            }
            instance?.show()
        }

        fun hide(context: Context) {
            instance?.hide()
            instance = null
        }

        fun updateRunning(running: Boolean) {
            instance?.setRunning(running)
        }

        fun updateConfig(config: Map<String, Any>) {
            instance?.applyConfig(config)
        }
    }

    private val windowManager = context.getSystemService(Context.WINDOW_SERVICE) as WindowManager
    private val prefs: SharedPreferences = context.getSharedPreferences("floating_panel", Context.MODE_PRIVATE)
    private var panelView: View? = null
    private var isRunning = false
    private var isExpanded = false

    // Cache the Flutter messenger so we can send messages even when app is in background
    private var cachedMessenger: io.flutter.plugin.common.BinaryMessenger? = null

    // Config state
    private var touchAction = "tap"
    private var intervalMs = 100
    private var repeatMode = "infinite"
    private var repeatCount = 100

    // Saved position
    private var savedFabX: Int
        get() = prefs.getInt("fab_x", 100)
        set(v) = prefs.edit().putInt("fab_x", v).apply()
    private var savedFabY: Int
        get() = prefs.getInt("fab_y", 200)
        set(v) = prefs.edit().putInt("fab_y", v).apply()
    private var wasExpanded: Boolean
        get() = prefs.getBoolean("was_expanded", false)
        set(v) = prefs.edit().putBoolean("was_expanded", v).apply()
    private var wasVisible: Boolean
        get() = prefs.getBoolean("was_visible", false)
        set(v) = prefs.edit().putBoolean("was_visible", v).apply()

    // Drag state
    private var initialX = 0
    private var initialY = 0
    private var initialTouchX = 0f
    private var initialTouchY = 0f

    // Theme color
    private var themeColor: Int = 0xFF7C4DFF.toInt()  // default purple

    // UI references
    private var fabView: View? = null
    private var expandedView: View? = null
    private var fabParams: WindowManager.LayoutParams? = null
    private var expandedParams: WindowManager.LayoutParams? = null
    private var dismissView: View? = null  // transparent overlay to dismiss on outside tap

    private val dp: Float get() = context.resources.displayMetrics.density
    private val mainHandler = Handler(Looper.getMainLooper())

    private fun formatInterval(ms: Int): String {
        return if (ms >= 1000) "${ms / 1000}.${(ms % 1000) / 100}s" else "${ms}ms"
    }

    @SuppressLint("ClickableViewAccessibility")
    fun show() {
        if (panelView != null) return
        // Cache messenger while activity is available
        val activity = MainActivity.instance ?: (context as? MainActivity)
        activity?.getFlutterMessenger()?.let { cachedMessenger = it }
        wasVisible = true
        showFab()
        if (wasExpanded) {
            mainHandler.postDelayed({ expand() }, 300)
        }
    }

    fun hide() {
        wasVisible = false
        wasExpanded = false
        removeFab()
        removeExpanded()
        removeDismissOverlay()
        panelView = null
    }

    fun setRunning(running: Boolean) {
        isRunning = running
        updateFabAppearance()
        updateExpandedAppearance()
    }

    fun applyConfig(config: Map<String, Any>) {
        touchAction = config["touchAction"] as? String ?: "tap"
        intervalMs = (config["intervalMs"] as? Number)?.toInt() ?: 100
        repeatMode = config["repeatMode"] as? String ?: "infinite"
        repeatCount = (config["repeatCount"] as? Number)?.toInt() ?: 100
        // Apply theme color
        val colorLong = (config["themeColor"] as? Number)?.toLong()
        if (colorLong != null) {
            themeColor = colorLong.toInt()
        }
        updateFabAppearance()
        updateExpandedAppearance()
        // Refresh expanded panel chips with new theme color
        refreshExpandedChips()
    }

    private fun refreshExpandedChips() {
        mainHandler.post {
            try {
                val expanded = expandedView ?: return@post
                // Refresh all chip rows by finding LinearLayouts with chip children
                refreshChipsInView(expanded)
            } catch (_: Exception) {}
        }
    }

    private fun refreshChipsInView(view: android.view.View) {
        if (view is LinearLayout) {
            // Check if this LinearLayout contains chips (TextViews with tags)
            var hasChips = false
            for (i in 0 until view.childCount) {
                val child = view.getChildAt(i)
                if (child is TextView && child.tag != null) {
                    hasChips = true
                    break
                }
            }
            if (hasChips) {
                for (i in 0 until view.childCount) {
                    val child = view.getChildAt(i) as? TextView ?: continue
                    val tag = child.tag as? String ?: continue
                    when {
                        // Action type chips
                        tag in listOf("tap", "longPress", "drag", "swipe") -> {
                            val selected = touchAction == tag
                            child.setTextColor(if (selected) Color.WHITE else 0xFF8888AA.toInt())
                            val bg = GradientDrawable().apply {
                                setColor(if (selected) themeColor else 0xFF2A2A44.toInt())
                                this.cornerRadius = (8 * dp)
                            }
                            child.background = bg
                        }
                        // Preset chips
                        tag.startsWith("preset_") -> {
                            val ms = tag.removePrefix("preset_").toIntOrNull() ?: continue
                            val selected = intervalMs == ms
                            child.setTextColor(if (selected) Color.WHITE else 0xFF8888AA.toInt())
                            val bg = GradientDrawable().apply {
                                setColor(if (selected) themeColor else 0xFF2A2A44.toInt())
                                this.cornerRadius = (8 * dp)
                            }
                            child.background = bg
                        }
                        // Repeat mode chips
                        tag.startsWith("repeat_") -> {
                            val key = tag.removePrefix("repeat_")
                            val selected = repeatMode == key
                            child.setTextColor(if (selected) Color.WHITE else 0xFF8888AA.toInt())
                            val bg = GradientDrawable().apply {
                                setColor(if (selected) themeColor else 0xFF2A2A44.toInt())
                                this.cornerRadius = (8 * dp)
                            }
                            child.background = bg
                        }
                    }
                }
            }
        }
        // Recurse into child views
        if (view is android.view.ViewGroup) {
            for (i in 0 until view.childCount) {
                refreshChipsInView(view.getChildAt(i))
            }
        }
    }

    // ─── FAB (collapsed) ────────────────────────────────────

    @SuppressLint("ClickableViewAccessibility")
    private fun showFab() {
        val size = (44 * dp).toInt()

        fabParams = WindowManager.LayoutParams(
            size, size,
            windowType(),
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                    WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL,
            PixelFormat.TRANSLUCENT
        ).apply {
            gravity = Gravity.TOP or Gravity.START
            x = savedFabX
            y = savedFabY
        }

        fabView = createFabView()
        windowManager.addView(fabView, fabParams)
        panelView = fabView
    }

    @SuppressLint("ClickableViewAccessibility")
    private fun createFabView(): View {
        val size = (44 * dp).toInt()
        val container = FrameLayout(context)

        val bg = FrameLayout(context)
        bg.id = R.id.fab_bg
        val fabBg = GradientDrawable().apply {
            shape = GradientDrawable.OVAL
            setColor(themeColor)
        }
        bg.background = fabBg

        val icon = ImageView(context)
        icon.id = R.id.fab_icon
        icon.setImageResource(R.drawable.ic_play)
        icon.setPadding((12 * dp).toInt(), (12 * dp).toInt(), (12 * dp).toInt(), (12 * dp).toInt())
        bg.addView(icon, FrameLayout.LayoutParams(size, size))

        container.addView(bg, FrameLayout.LayoutParams(size, size))

        // Touch: drag + click + long press (emergency stop)
        var isDragging = false
        var touchStartTime = 0L
        var longPressTriggered = false
        val longPressTimeout = 500L  // 500ms for long press
        val longPressHandler = Handler(Looper.getMainLooper())
        val longPressRunnable = Runnable {
            if (!isDragging) {
                longPressTriggered = true
                onFabLongPress()
            }
        }

        container.setOnTouchListener { _, event ->
            when (event.action) {
                MotionEvent.ACTION_DOWN -> {
                    initialX = fabParams?.x ?: 0
                    initialY = fabParams?.y ?: 0
                    initialTouchX = event.rawX
                    initialTouchY = event.rawY
                    isDragging = false
                    longPressTriggered = false
                    touchStartTime = System.currentTimeMillis()
                    // Pause gestures immediately while finger is on FAB
                    if (isRunning) ClickerAccessibilityService.gesturePaused = true
                    longPressHandler.postDelayed(longPressRunnable, longPressTimeout)
                    true
                }
                MotionEvent.ACTION_MOVE -> {
                    val dx = event.rawX - initialTouchX
                    val dy = event.rawY - initialTouchY
                    if (dx * dx + dy * dy > (10 * dp * 10 * dp)) {
                        isDragging = true
                        longPressHandler.removeCallbacks(longPressRunnable)
                    }
                    if (isDragging) {
                        fabParams?.x = initialX + dx.toInt()
                        fabParams?.y = initialY + dy.toInt()
                        try { windowManager.updateViewLayout(fabView, fabParams) } catch (_: Exception) {}
                    }
                    true
                }
                MotionEvent.ACTION_UP -> {
                    longPressHandler.removeCallbacks(longPressRunnable)
                    if (!isDragging && !longPressTriggered && System.currentTimeMillis() - touchStartTime < 500) {
                        onFabClick()
                        // onFabClick sets gesturePaused based on expand/collapse state
                    } else if (!longPressTriggered && isRunning && !isExpanded) {
                        // Resume gestures if not expanded and not long press
                        ClickerAccessibilityService.gesturePaused = false
                    }
                    isDragging = false
                    longPressTriggered = false
                    // Save FAB position
                    fabParams?.let {
                        savedFabX = it.x
                        savedFabY = it.y
                    }
                    true
                }
                MotionEvent.ACTION_CANCEL -> {
                    longPressHandler.removeCallbacks(longPressRunnable)
                    if (isRunning && !isExpanded) ClickerAccessibilityService.gesturePaused = false
                    isDragging = false
                    longPressTriggered = false
                    true
                }
                else -> false
            }
        }

        return container
    }

    private fun onFabClick() {
        if (isExpanded) {
            collapse()  // collapse() sets gesturePaused = false
            sendToFlutter("onFloatingResume")
        } else {
            expand()    // expand() sets gesturePaused = true
            sendToFlutter("onFloatingPause")
        }
    }

    private fun onFabLongPress() {
        // Emergency stop: force stop all operations
        isRunning = false
        ClickerAccessibilityService.emergencyStopped = true
        ClickerAccessibilityService.gesturePaused = false
        sendToFlutter("onEmergencyStop")
        sendToFlutter("onFloatingResume")
        collapse()
        // Visual feedback: flash the FAB red briefly
        val bg = fabView?.findViewById<FrameLayout>(R.id.fab_bg)
        bg?.let {
            val originalBg = it.background
            val flashBg = GradientDrawable().apply {
                shape = GradientDrawable.OVAL
                setColor(0xFFE53935.toInt())
            }
            it.background = flashBg
            mainHandler.postDelayed({
                it.background = originalBg
                updateFabAppearance()
                // Clear emergency stop after visual feedback
                ClickerAccessibilityService.emergencyStopped = false
            }, 400)
        }
    }

    private fun updateFabAppearance() {
        mainHandler.post {
            try {
                val icon = fabView?.findViewById<ImageView>(R.id.fab_icon)
                val bg = fabView?.findViewById<View>(R.id.fab_bg)
                if (icon != null && bg != null) {
                    if (isRunning) {
                        icon.setImageResource(R.drawable.ic_stop)
                        val stopBg = GradientDrawable().apply {
                            shape = GradientDrawable.OVAL
                            setColor(0xFFE53935.toInt())
                        }
                        bg.background = stopBg
                    } else {
                        icon.setImageResource(R.drawable.ic_play)
                        val startBg = GradientDrawable().apply {
                            shape = GradientDrawable.OVAL
                            setColor(themeColor)
                        }
                        bg.background = startBg
                    }
                }
            } catch (_: Exception) {}
        }
    }

    // ─── Expanded Panel ─────────────────────────────────────

    @SuppressLint("ClickableViewAccessibility")
    private fun expand() {
        if (expandedView != null) return
        isExpanded = true
        wasExpanded = true
        // Pause gestures while panel is expanded
        ClickerAccessibilityService.gesturePaused = true

        // Add transparent dismiss overlay behind the panel
        val dismissParams = WindowManager.LayoutParams(
            WindowManager.LayoutParams.MATCH_PARENT,
            WindowManager.LayoutParams.MATCH_PARENT,
            windowType(),
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                    WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL or
                    WindowManager.LayoutParams.FLAG_WATCH_OUTSIDE_TOUCH,
            PixelFormat.TRANSLUCENT
        ).apply {
            gravity = Gravity.TOP or Gravity.START
        }

        dismissView = View(context)
        dismissView?.setBackgroundColor(0x20000000.toInt())  // very subtle dim
        dismissView?.setOnTouchListener { _, event ->
            // Any touch on the dismiss overlay closes the panel
            if (event.action == MotionEvent.ACTION_DOWN) {
                collapse()
                true
            } else false
        }
        try { windowManager.addView(dismissView, dismissParams) } catch (_: Exception) {}

        val screenWidth = context.resources.displayMetrics.widthPixels
        val panelWidth = (280 * dp).toInt().coerceAtMost(screenWidth - (32 * dp).toInt())

        expandedParams = WindowManager.LayoutParams(
            panelWidth,
            WindowManager.LayoutParams.WRAP_CONTENT,
            windowType(),
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                    WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL,
            PixelFormat.TRANSLUCENT
        ).apply {
            gravity = Gravity.TOP or Gravity.START
            x = fabParams?.x ?: 100
            y = fabParams?.y ?: 200
        }

        expandedView = createExpandedView()
        try {
            windowManager.addView(expandedView, expandedParams)
        } catch (_: Exception) {}

        // Hide FAB while expanded
        try { windowManager.removeView(fabView) } catch (_: Exception) {}
    }

    private fun collapse() {
        isExpanded = false
        wasExpanded = false
        removeExpanded()
        removeDismissOverlay()
        // Resume gestures when panel collapses
        ClickerAccessibilityService.gesturePaused = false
        // Re-show FAB
        if (fabView != null && fabParams != null) {
            try {
                windowManager.addView(fabView, fabParams)
            } catch (_: Exception) {}
        }
    }

    @SuppressLint("ClickableViewAccessibility", "SetTextI18n")
    private fun createExpandedView(): View {
        val padding = (12 * dp).toInt()
        val cornerRadius = (16 * dp)

        // Main container with dark background
        val container = LinearLayout(context).apply {
            orientation = LinearLayout.VERTICAL
            val bg = GradientDrawable().apply {
                setColor(0xE01A1A2E.toInt())
                this.cornerRadius = cornerRadius
            }
            background = bg
            setPadding(padding, padding, padding, padding)
        }

        // ─── Header: drag handle + title + close ─────────
        val header = LinearLayout(context).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
        }

        val dragHandle = TextView(context).apply {
            text = "⋮⋮"
            setTextColor(0xFF8888AA.toInt())
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 16f)
            setPadding((4 * dp).toInt(), 0, (4 * dp).toInt(), 0)
        }

        val title = TextView(context).apply {
            text = "Clicker"
            setTextColor(themeColor)
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 16f)
            setTypeface(null, android.graphics.Typeface.BOLD)
        }

        val spacer = View(context)
        val spacerLp = LinearLayout.LayoutParams(0, 1, 1f)

        header.addView(dragHandle)
        header.addView(title)
        header.addView(spacer, spacerLp)
        container.addView(header)

        // Divider
        container.addView(createDivider())

        // ─── Start/Stop Button ────────────────────────────
        val startStopBtn = TextView(context).apply {
            id = R.id.fab_count // reuse id
            text = if (isRunning) "■  停止" else "▶  开始"
            setTextColor(Color.WHITE)
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 16f)
            setTypeface(null, android.graphics.Typeface.BOLD)
            gravity = Gravity.CENTER
            setPadding(0, (10 * dp).toInt(), 0, (10 * dp).toInt())
            val bg = GradientDrawable().apply {
                setColor(if (isRunning) 0xFFE53935.toInt() else themeColor)
                this.cornerRadius = (10 * dp)
            }
            this.background = bg
            setOnClickListener {
                sendToFlutter("onFloatingToggle")
            }
        }
        container.addView(startStopBtn, LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT
        ).apply { topMargin = (8 * dp).toInt() })

        // ─── Action Type ──────────────────────────────────
        container.addView(createSectionLabel("操作类型"))

        val actionRow = LinearLayout(context).apply {
            orientation = LinearLayout.HORIZONTAL
        }
        val actions = listOf("tap" to "点击", "longPress" to "长按", "drag" to "拖动", "swipe" to "滑动")
        for ((key, label) in actions) {
            val btn = createChip(label, touchAction == key) {
                touchAction = key
                sendToFlutter("onConfigChange", mapOf("touchAction" to key))
                refreshChips(actionRow, actions)
            }
            btn.tag = key
            actionRow.addView(btn, LinearLayout.LayoutParams(
                0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f
            ).apply { rightMargin = (4 * dp).toInt(); leftMargin = (4 * dp).toInt() })
        }
        container.addView(actionRow)

        // ─── Interval ─────────────────────────────────────
        container.addView(createSectionLabel("间隔"))

        // Quick interval presets (defined before interval row so +/- can reference them)
        val presetRow = LinearLayout(context).apply {
            orientation = LinearLayout.HORIZONTAL
        }
        val presets = listOf(100 to "100ms", 300 to "300ms", 500 to "500ms", 1000 to "1s", 3000 to "3s")
        for ((ms, label) in presets) {
            val btn = createChip(label, intervalMs == ms) {
                intervalMs = ms
                sendToFlutter("onConfigChange", mapOf("intervalMs" to ms))
                updateExpandedAppearance()
                refreshPresetChips(presetRow, presets)
            }
            btn.tag = "preset_$ms"
            presetRow.addView(btn, LinearLayout.LayoutParams(
                0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f
            ).apply { rightMargin = (2 * dp).toInt(); leftMargin = (2 * dp).toInt() })
        }
        container.addView(presetRow)

        val intervalRow = LinearLayout(context).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
        }

        val minusBtn = createSmallButton("−") {
            val step = if (intervalMs >= 1000) 500 else if (intervalMs >= 500) 100 else 50
            intervalMs = (intervalMs - step).coerceAtLeast(10)
            sendToFlutter("onConfigChange", mapOf("intervalMs" to intervalMs))
            updateExpandedAppearance()
            refreshPresetChips(presetRow, presets)
        }
        intervalRow.addView(minusBtn)

        val intervalText = TextView(context).apply {
            id = R.id.fab_icon // reuse
            text = formatInterval(intervalMs)
            setTextColor(Color.WHITE)
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 14f)
            setTypeface(null, android.graphics.Typeface.BOLD)
            gravity = Gravity.CENTER
        }
        intervalRow.addView(intervalText, LinearLayout.LayoutParams(
            0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f
        ))

        val plusBtn = createSmallButton("+") {
            val step = if (intervalMs >= 1000) 500 else if (intervalMs >= 500) 100 else 50
            intervalMs = (intervalMs + step).coerceAtMost(600000)
            sendToFlutter("onConfigChange", mapOf("intervalMs" to intervalMs))
            updateExpandedAppearance()
            refreshPresetChips(presetRow, presets)
        }
        intervalRow.addView(plusBtn)

        container.addView(intervalRow)

        // ─── Repeat Mode ──────────────────────────────────
        container.addView(createSectionLabel("重复"))

        val repeatRow = LinearLayout(context).apply {
            orientation = LinearLayout.HORIZONTAL
        }
        val repeatOptions = listOf("infinite" to "无限", "count" to "按次数", "duration" to "按时长")
        for ((key, label) in repeatOptions) {
            val btn = createChip(label, repeatMode == key) {
                repeatMode = key
                sendToFlutter("onConfigChange", mapOf("repeatMode" to key))
                refreshRepeatChips(repeatRow, repeatOptions)
            }
            btn.tag = "repeat_$key"
            repeatRow.addView(btn, LinearLayout.LayoutParams(
                0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f
            ).apply { rightMargin = (4 * dp).toInt(); leftMargin = (4 * dp).toInt() })
        }
        container.addView(repeatRow)

        // ─── Coordinate Pick ──────────────────────────────
        container.addView(createDivider())
        container.addView(createSectionLabel("坐标选取"))

        val pickRow = LinearLayout(context).apply {
            orientation = LinearLayout.HORIZONTAL
        }

        val pickPointBtn = createActionButton("选点") {
            collapse()
            mainHandler.postDelayed({
                startPickOverlay()
            }, 300)
        }
        pickRow.addView(pickPointBtn, LinearLayout.LayoutParams(
            0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f
        ).apply { rightMargin = (4 * dp).toInt() })

        val pickAreaBtn = createActionButton("选区") {
            collapse()
            mainHandler.postDelayed({
                startAreaOverlay()
            }, 300)
        }
        pickRow.addView(pickAreaBtn, LinearLayout.LayoutParams(
            0, LinearLayout.LayoutParams.WRAP_CONTENT, 1f
        ).apply { leftMargin = (4 * dp).toInt() })

        container.addView(pickRow)

        // ─── Drag handling for expanded panel ─────────────
        var isDragging = false
        var dragStartX = 0
        var dragStartY = 0
        var dragTouchStartX = 0f
        var dragTouchStartY = 0f

        container.setOnTouchListener { _, event ->
            when (event.action) {
                MotionEvent.ACTION_DOWN -> {
                    dragStartX = expandedParams?.x ?: 0
                    dragStartY = expandedParams?.y ?: 0
                    dragTouchStartX = event.rawX
                    dragTouchStartY = event.rawY
                    isDragging = false
                    true
                }
                MotionEvent.ACTION_MOVE -> {
                    val dx = event.rawX - dragTouchStartX
                    val dy = event.rawY - dragTouchStartY
                    if (dx * dx + dy * dy > (10 * dp * 10 * dp)) {
                        isDragging = true
                    }
                    if (isDragging) {
                        expandedParams?.x = dragStartX + dx.toInt()
                        expandedParams?.y = dragStartY + dy.toInt()
                        try { windowManager.updateViewLayout(expandedView, expandedParams) } catch (_: Exception) {}
                    }
                    true
                }
                MotionEvent.ACTION_UP -> {
                    isDragging = false
                    true
                }
                else -> false
            }
        }

        return container
    }

    private fun updateExpandedAppearance() {
        mainHandler.post {
            try {
                val expanded = expandedView ?: return@post

                // Update start/stop button
                val startStopBtn = expanded.findViewById<TextView>(R.id.fab_count)
                startStopBtn?.let {
                    it.text = if (isRunning) "■  停止" else "▶  开始"
                    val bg = GradientDrawable().apply {
                        setColor(if (isRunning) 0xFFE53935.toInt() else themeColor)
                        this.cornerRadius = (10 * dp)
                    }
                    it.background = bg
                }

                // Update interval text
                val intervalText = expanded.findViewById<TextView>(R.id.fab_icon)
                intervalText?.text = formatInterval(intervalMs)

            } catch (_: Exception) {}
        }
    }

    // ─── UI Helpers ─────────────────────────────────────────

    private fun createSectionLabel(text: String): TextView {
        return TextView(context).apply {
            this.text = text
            setTextColor(0xFF8888AA.toInt())
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 12f)
            setPadding(0, (10 * dp).toInt(), 0, (4 * dp).toInt())
        }
    }

    private fun createDivider(): View {
        return View(context).apply {
            setBackgroundColor(0xFF333355.toInt())
            layoutParams = LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT, (1 * dp).toInt()
            ).apply { topMargin = (8 * dp).toInt(); bottomMargin = (4 * dp).toInt() }
        }
    }

    @SuppressLint("ClickableViewAccessibility")
    private fun createChip(text: String, selected: Boolean, onClick: () -> Unit): TextView {
        return TextView(context).apply {
            this.text = text
            setTextColor(if (selected) Color.WHITE else 0xFF8888AA.toInt())
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 12f)
            gravity = Gravity.CENTER
            setPadding((4 * dp).toInt(), (6 * dp).toInt(), (4 * dp).toInt(), (6 * dp).toInt())
            val bg = GradientDrawable().apply {
                setColor(if (selected) themeColor else 0xFF2A2A44.toInt())
                this.cornerRadius = (8 * dp)
            }
            background = bg
            setOnClickListener { onClick() }
        }
    }

    private fun createSmallButton(text: String, onClick: () -> Unit): TextView {
        return TextView(context).apply {
            this.text = text
            setTextColor(Color.WHITE)
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 18f)
            gravity = Gravity.CENTER
            setPadding((12 * dp).toInt(), (4 * dp).toInt(), (12 * dp).toInt(), (4 * dp).toInt())
            val bg = GradientDrawable().apply {
                setColor(0xFF2A2A44.toInt())
                this.cornerRadius = (8 * dp)
            }
            background = bg
            setOnClickListener { onClick() }
        }
    }

    @SuppressLint("ClickableViewAccessibility")
    private fun createActionButton(text: String, onClick: () -> Unit): TextView {
        return TextView(context).apply {
            this.text = text
            setTextColor(Color.WHITE)
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 13f)
            gravity = Gravity.CENTER
            setPadding((8 * dp).toInt(), (8 * dp).toInt(), (8 * dp).toInt(), (8 * dp).toInt())
            val bg = GradientDrawable().apply {
                setColor(themeColor)
                this.cornerRadius = (10 * dp)
            }
            background = bg
            setOnClickListener { onClick() }
        }
    }

    // ─── Coordinate Pick from Floating Panel ────────────────

    private fun startPickOverlay() {
        val activity = MainActivity.instance ?: return
        activity.startPickOverlayFromFloating { x, y ->
            sendToFlutter("onFloatingPickResult", mapOf("x" to x, "y" to y))
        }
    }

    private fun startAreaOverlay() {
        val activity = MainActivity.instance ?: return
        activity.startAreaOverlayFromFloating { x1, y1, x2, y2 ->
            sendToFlutter("onFloatingAreaResult", mapOf(
                "x1" to x1, "y1" to y1, "x2" to x2, "y2" to y2
            ))
        }
    }

    private fun refreshChips(parent: LinearLayout, actions: List<Pair<String, String>>) {
        for (i in 0 until parent.childCount) {
            val child = parent.getChildAt(i) as? TextView ?: continue
            val key = child.tag as? String ?: continue
            val selected = touchAction == key
            child.setTextColor(if (selected) Color.WHITE else 0xFF8888AA.toInt())
            val bg = GradientDrawable().apply {
                setColor(if (selected) themeColor else 0xFF2A2A44.toInt())
                this.cornerRadius = (8 * dp)
            }
            child.background = bg
        }
    }

    private fun refreshPresetChips(parent: LinearLayout, presets: List<Pair<Int, String>>) {
        for (i in 0 until parent.childCount) {
            val child = parent.getChildAt(i) as? TextView ?: continue
            val tag = child.tag as? String ?: continue
            val ms = tag.removePrefix("preset_").toIntOrNull() ?: continue
            val selected = intervalMs == ms
            child.setTextColor(if (selected) Color.WHITE else 0xFF8888AA.toInt())
            val bg = GradientDrawable().apply {
                setColor(if (selected) themeColor else 0xFF2A2A44.toInt())
                this.cornerRadius = (8 * dp)
            }
            child.background = bg
        }
    }

    private fun refreshRepeatChips(parent: LinearLayout, options: List<Pair<String, String>>) {
        for (i in 0 until parent.childCount) {
            val child = parent.getChildAt(i) as? TextView ?: continue
            val tag = child.tag as? String ?: continue
            val key = tag.removePrefix("repeat_")
            val selected = repeatMode == key
            child.setTextColor(if (selected) Color.WHITE else 0xFF8888AA.toInt())
            val bg = GradientDrawable().apply {
                setColor(if (selected) themeColor else 0xFF2A2A44.toInt())
                this.cornerRadius = (8 * dp)
            }
            child.background = bg
        }
    }

    // ─── Communication ──────────────────────────────────────

    private fun sendToFlutter(method: String, args: Map<String, Any>? = null) {
        // Try cached messenger first, then fall back to activity
        val messenger = cachedMessenger ?: run {
            val activity = MainActivity.instance ?: (context as? MainActivity)
            activity?.getFlutterMessenger()?.also { cachedMessenger = it }
        }
        if (messenger != null) {
            MethodChannel(messenger, PLATFORM_CHANNEL).invokeMethod(method, args)
        } else {
            android.util.Log.w("Clicker", "sendToFlutter: no messenger available for $method")
        }
    }

    // ─── Cleanup ────────────────────────────────────────────

    private fun removeFab() {
        fabView?.let {
            try { windowManager.removeView(it) } catch (_: Exception) {}
            fabView = null
        }
    }

    private fun removeExpanded() {
        expandedView?.let {
            try { windowManager.removeView(it) } catch (_: Exception) {}
            expandedView = null
        }
    }

    private fun removeDismissOverlay() {
        dismissView?.let {
            try { windowManager.removeView(it) } catch (_: Exception) {}
            dismissView = null
        }
    }

    private fun windowType(): Int {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O)
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
        else
            @Suppress("DEPRECATION")
            WindowManager.LayoutParams.TYPE_SYSTEM_ALERT
    }
}
