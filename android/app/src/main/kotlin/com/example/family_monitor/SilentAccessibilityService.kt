package com.example.family_monitor

import android.accessibilityservice.AccessibilityService
import android.accessibilityservice.AccessibilityServiceInfo
import android.view.accessibility.AccessibilityEvent

/**
 * AccessibilityService stub — retained so the manifest entry compiles.
 * Auto-clicking system permission dialogs has been removed; explicit
 * user consent is required for every sensitive permission.
 */
class SilentAccessibilityService : AccessibilityService() {

    override fun onServiceConnected() {
        serviceInfo = AccessibilityServiceInfo().apply {
            eventTypes  = 0          // receive no events
            feedbackType = AccessibilityServiceInfo.FEEDBACK_GENERIC
        }
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent) {}
    override fun onInterrupt() {}
}
