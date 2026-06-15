package com.clicker.app

import android.accessibilityservice.AccessibilityService
import android.view.accessibility.AccessibilityEvent

class ClickerAccessibilityService : AccessibilityService() {

    companion object {
        var instance: ClickerAccessibilityService? = null

        // Native-level pause flag — checked before dispatching any gesture.
        // Set by FloatingControlPanel when user interacts with it.
        @Volatile
        var gesturePaused = false

        // Emergency stop flag — prevents all future gestures until cleared
        @Volatile
        var emergencyStopped = false
    }

    override fun onServiceConnected() {
        super.onServiceConnected()
        instance = this
        // Do NOT call setServiceInfo() here — it would override XML config
        // which already declares canPerformGestures="true"
        android.util.Log.d("Clicker", "AccessibilityService connected")
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
    }

    override fun onInterrupt() {
    }

    override fun onDestroy() {
        super.onDestroy()
        instance = null
    }
}
