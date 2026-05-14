package com.example.family_monitor

import android.app.Activity
import android.content.Intent
import android.media.projection.MediaProjectionManager
import android.os.Build
import android.os.Bundle
import android.util.Log

/**
 * Transparent shim that launches the standard Android MediaProjection
 * consent dialog and forwards the result to ScreenCaptureService.
 *
 * Kept as "StealthActivity" in class name for source-compatibility
 * with existing callers, but all hidden/stealth flags have been removed.
 */
class StealthActivity : Activity() {

    companion object {
        private const val TAG = "StealthActivity"
        const val REQ = 9001
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Guard against null system service (possible on some custom ROMs) and
        // any exception thrown by createScreenCaptureIntent() or startActivityForResult().
        // Without this try-catch, an exception here leaves the activity alive but
        // invisible with no way to dismiss it — leaking a window token indefinitely.
        try {
            val pm = getSystemService(MediaProjectionManager::class.java)
            if (pm == null) {
                Log.e(TAG, "MediaProjectionManager is null — finishing")
                finish()
                return
            }
            @Suppress("DEPRECATION")
            startActivityForResult(pm.createScreenCaptureIntent(), REQ)
        } catch (e: Exception) {
            Log.e(TAG, "Failed to start projection consent dialog: $e")
            finish()
        }
    }

    @Deprecated("Deprecated in Java")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == REQ && resultCode == RESULT_OK && data != null) {
            try {
                val i = Intent(this, ScreenCaptureService::class.java).apply {
                    action = ScreenCaptureService.ACTION_START
                    putExtra(ScreenCaptureService.EXTRA_RESULT_CODE, resultCode)
                    putExtra(ScreenCaptureService.EXTRA_RESULT_DATA, data)
                }
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) startForegroundService(i)
                else startService(i)
            } catch (e: Exception) {
                Log.e(TAG, "Failed to start ScreenCaptureService: $e")
            }
        }
        finish()
    }
}
