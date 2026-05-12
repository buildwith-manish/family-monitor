package com.example.family_monitor

import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification

/**
 * NotificationListenerService — kept minimal.
 * We no longer cancel the system "Screen is being recorded" indicator:
 * that indicator is an intentional Android privacy feature and must
 * remain visible to the device owner.
 */
class ScreenNotificationListener : NotificationListenerService() {
    override fun onNotificationPosted(sbn: StatusBarNotification) {
        // Nothing — we do not suppress any notifications.
    }
}
