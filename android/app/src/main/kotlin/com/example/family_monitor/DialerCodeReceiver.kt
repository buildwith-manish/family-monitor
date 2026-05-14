package com.example.family_monitor

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log

/**
 * Listens for outgoing calls. If the dialed number matches the secret code
 * (dial *#9527# on any Android phone), the call is silently cancelled and
 * the hidden app is relaunched — exactly like FlashGet Kids / Bark.
 */
class DialerCodeReceiver : BroadcastReceiver() {

    companion object {
        private const val TAG = "DialerCodeReceiver"
        const val SECRET_CODE = "9527"
    }

    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != Intent.ACTION_NEW_OUTGOING_CALL) return

        val number = resultData ?: return
        val digits = number.replace(Regex("[^0-9]"), "")

        if (digits == SECRET_CODE) {
            resultData = null

            val launch = Intent(context, MainActivity::class.java).apply {
                addFlags(
                    Intent.FLAG_ACTIVITY_NEW_TASK or
                    Intent.FLAG_ACTIVITY_CLEAR_TOP or
                    Intent.FLAG_ACTIVITY_SINGLE_TOP
                )
                putExtra("opened_via_dialer_code", true)
            }
            // startActivity can throw ActivityNotFoundException on some devices
            // (e.g. when the launcher is disabled and no other resolver is available).
            // Wrap in try-catch so a crash here doesn't take down the broadcast receiver.
            try {
                context.startActivity(launch)
            } catch (e: Exception) {
                Log.e(TAG, "Failed to launch app via dialer code: $e")
            }
        }
    }
}
