package com.example.family_monitor

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.media.projection.MediaProjectionConfig
import android.media.projection.MediaProjectionManager
import android.os.Build
import android.os.Bundle
import android.util.Log
import android.view.accessibility.AccessibilityEvent
import android.view.accessibility.AccessibilityNodeInfo

class TXScreenCaptureAssistantActivity : Activity() {

    companion object {
        private const val TAG = "TXCaptureAssistant"
        const val REQUEST_MEDIA_PROJECTION = 2001
        const val EXTRA_IS_APPLY_PROACTIVELY = "isApplyProactively"
    }

    private var isApplyProactively = false

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        isApplyProactively = intent?.getBooleanExtra(EXTRA_IS_APPLY_PROACTIVELY, false) ?: false

        val projectionManager = getSystemService(MEDIA_PROJECTION_SERVICE) as MediaProjectionManager

        // Check if we already have a cached projection we can reuse
        if (VirtualDisplayManager.instance?.hasActiveProjection() == true) {
            Log.d(TAG, "Active projection already exists — reusing")
            finish()
            return
        }

        // Check if we have cached token data that might still be valid
        val prefs = getSharedPreferences("fm_prefs", Context.MODE_PRIVATE)
        val savedCode = ScreenCaptureService.savedResultCode
        val savedData = ScreenCaptureService.savedResultData
        if (savedCode != 0 && savedData != null) {
            Log.d(TAG, "Cached projection data exists — attempting reuse")
            startScreenCaptureService(savedCode, savedData)
            finish()
            return
        }

        // Create the screen capture intent
        val captureIntent = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            // Android 14+: Use MediaProjectionConfig for default display
            val config = MediaProjectionConfig.createConfigForDefaultDisplay()
            projectionManager.createScreenCaptureIntent(config)
        } else {
            projectionManager.createScreenCaptureIntent()
        }

        startActivityForResult(captureIntent, REQUEST_MEDIA_PROJECTION)
    }

    @Suppress("DEPRECATION", "OVERRIDE_DEPRECATION")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)

        if (requestCode != REQUEST_MEDIA_PROJECTION) {
            finish()
            return
        }

        if (resultCode == RESULT_OK && data != null) {
            Log.d(TAG, "MediaProjection consent granted")
            startScreenCaptureService(resultCode, data)
        } else {
            Log.w(TAG, "MediaProjection consent denied")
            // Signal that consent was denied
            VirtualDisplayManager.instance?.notifyConsentDenied()
        }

        finish()
    }

    override fun onDestroy() {
        super.onDestroy()
        // Safety: ensure we finish even if onActivityResult is never called
    }

    private fun startScreenCaptureService(resultCode: Int, resultData: Intent) {
        // Cache the projection data
        ScreenCaptureService.savedResultCode = resultCode
        ScreenCaptureService.savedResultData = resultData

        // Start the ScreenCaptureService with the projection data
        val serviceIntent = Intent(this, ScreenCaptureService::class.java).apply {
            action = ScreenCaptureService.ACTION_START
            putExtra(ScreenCaptureService.EXTRA_RESULT_CODE, resultCode)
            putExtra(ScreenCaptureService.EXTRA_RESULT_DATA, resultData)
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            startForegroundService(serviceIntent)
        } else {
            startService(serviceIntent)
        }

        // Notify VirtualDisplayManager
        VirtualDisplayManager.instance?.notifyConsentGranted()

        // Persist consent
        getSharedPreferences("fm_prefs", Context.MODE_PRIVATE)
            .edit()
            .putBoolean("projection_consent_granted", true)
            .putInt("projection_result_code", resultCode)
            .apply()
    }
}
