package com.clicker.app

import android.content.Context
import android.view.MotionEvent
import android.view.View

/**
 * A full-screen transparent overlay used during macro recording.
 *
 * It captures every touch gesture and reports it to the Dart side via [Listener].
 * Gestures are classified into:
 *  - click:   a tap with little movement and short duration
 *  - longPress: a press held without moving for > 600ms
 *  - drag:    a press followed by significant movement before release
 */
class RecordingTouchView(context: Context, private val listener: Listener) : View(context) {

    fun interface Listener {
        fun onEvent(event: Map<String, Any>)
    }

    private var downX = 0f
    private var downY = 0f
    private var downTime = 0L
    private var moved = false
    private var _touchable = true

    private val moveThreshold = 20f

    /** Make the overlay touchable (capture) or pass-through (ignore touches). */
    fun setTouchable(touchable: Boolean) {
        _touchable = touchable
    }

    override fun onTouchEvent(event: MotionEvent): Boolean {
        // In pass-through mode, don't capture any touches — they fall through
        // to the app below so the user can interact with the target app.
        if (!_touchable) return false

        when (event.actionMasked) {
            MotionEvent.ACTION_DOWN -> {
                downX = event.rawX
                downY = event.rawY
                downTime = event.eventTime
                moved = false
                return true
            }
            MotionEvent.ACTION_MOVE -> {
                if (Math.abs(event.rawX - downX) > moveThreshold ||
                    Math.abs(event.rawY - downY) > moveThreshold) {
                    moved = true
                }
                return true
            }
            MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL -> {
                val durationMs = (event.eventTime - downTime).toInt()
                val upX = event.rawX
                val upY = event.rawY

                if (!moved) {
                    if (durationMs > 600) {
                        listener.onEvent(mapOf(
                            "type" to "longPress",
                            "x" to downX.toInt(),
                            "y" to downY.toInt(),
                            "durationMs" to durationMs.coerceAtLeast(1000),
                        ))
                    } else {
                        listener.onEvent(mapOf(
                            "type" to "click",
                            "x" to downX.toInt(),
                            "y" to downY.toInt(),
                        ))
                    }
                } else {
                    listener.onEvent(mapOf(
                        "type" to "drag",
                        "startX" to downX.toInt(),
                        "startY" to downY.toInt(),
                        "endX" to upX.toInt(),
                        "endY" to upY.toInt(),
                        "durationMs" to durationMs.coerceAtLeast(100),
                    ))
                }
                return true
            }
        }
        return super.onTouchEvent(event)
    }
}
