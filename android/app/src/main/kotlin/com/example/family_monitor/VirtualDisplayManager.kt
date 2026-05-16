package com.example.family_monitor

import android.content.Context
import android.hardware.display.DisplayManager
import android.hardware.display.VirtualDisplay
import android.media.projection.MediaProjection
import android.media.projection.MediaProjectionManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.util.Log
import android.view.Surface
import java.util.concurrent.CopyOnWriteArrayList
import java.util.concurrent.TimeUnit

/**
 * VirtualDisplayManager — Centralized owner of MediaProjection + VirtualDisplay.
 *
 * Based on the FlashGet Kids reference architecture, this singleton:
 * - Owns the MediaProjection token lifecycle
 * - Manages VirtualDisplay creation/teardown
 * - Supports multiple surfaces (WebRTC + native capture)
 * - Provides delayed cleanup (1s) on projection stop to allow re-acquisition
 * - Notifies listeners on capture errors and projection state changes
 */
class VirtualDisplayManager private constructor(private val context: Context) {

    companion object {
        private const val TAG = "VirtualDisplayManager"

        @Volatile
        private var _instance: VirtualDisplayManager? = null

        fun initialize(context: Context): VirtualDisplayManager {
            if (_instance == null) {
                synchronized(this) {
                    if (_instance == null) {
                        _instance = VirtualDisplayManager(context.applicationContext)
                    }
                }
            }
            return _instance!!
        }

        val instance: VirtualDisplayManager?
            get() = _instance

        private const val CLEANUP_DELAY_MS = 1000L // 1 second delayed cleanup
    }

    private val mainHandler = Handler(Looper.getMainLooper())
    private var mediaProjection: MediaProjection? = null
    private var virtualDisplay: VirtualDisplay? = null
    private var currentSurface: Surface? = null
    private var currentWidth: Int = 480
    private var currentHeight: Int = 854
    private var currentDpi: Int = 1

    private val listeners = CopyOnWriteArrayList<VirtualDisplayListener>()

    private val projectionCallback = object : MediaProjection.Callback() {
        override fun onStop() {
            Log.w(TAG, "MediaProjection stopped by system")
            // Delayed cleanup — allows re-acquisition within 1s
            mainHandler.postDelayed({
                notifyCaptureError(CaptureError.PROJECTION_STOPPED)
                cleanupInternal()
            }, CLEANUP_DELAY_MS)
        }
    }

    interface VirtualDisplayListener {
        fun onCaptureError(error: CaptureError) {}
        fun onVirtualDisplayCreated(display: VirtualDisplay) {}
        fun onVirtualDisplayStopped() {}
        fun onConsentGranted() {}
        fun onConsentDenied() {}
    }

    enum class CaptureError(val code: Int, val description: String) {
        PROJECTION_STOPPED(1, "MediaProjection was stopped"),
        PROJECTION_NULL(2, "getMediaProjection returned null"),
        VIRTUAL_DISPLAY_FAILED(3, "VirtualDisplay creation failed"),
        SURFACE_INVALID(4, "Surface is invalid or null"),
        NOT_INITIALIZED(5, "MediaProjection not initialized"),
    }

    fun addListener(listener: VirtualDisplayListener) {
        listeners.addIfAbsent(listener)
    }

    fun removeListener(listener: VirtualDisplayListener) {
        listeners.remove(listener)
    }

    fun hasActiveProjection(): Boolean = mediaProjection != null

    fun setMediaProjection(projection: MediaProjection) {
        // Unregister callback from old projection
        try { mediaProjection?.unregisterCallback(projectionCallback) } catch (_: Exception) {}

        mediaProjection = projection

        // Register callback on new projection
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            mediaProjection?.registerCallback(projectionCallback, mainHandler)
        }

        Log.d(TAG, "MediaProjection set and callback registered")
    }

    /**
     * Create a VirtualDisplay bound to a surface.
     * This is used by the native capture pipeline (ImageReader surface)
     * and can also be used by Tencent SDK (native Surface).
     */
    fun createVirtualDisplay(
        surface: Surface,
        width: Int = 480,
        height: Int = 854,
        dpi: Int = 1
    ): VirtualDisplay? {
        val projection = mediaProjection
        if (projection == null) {
            Log.e(TAG, "Cannot create VirtualDisplay — no MediaProjection")
            notifyCaptureError(CaptureError.NOT_INITIALIZED)
            return null
        }

        // Release existing VirtualDisplay
        releaseVirtualDisplay()

        currentSurface = surface
        currentWidth = width
        currentHeight = height
        currentDpi = dpi

        try {
            virtualDisplay = projection.createVirtualDisplay(
                "FamilyMonitorScreenCapture",
                width, height, dpi,
                DisplayManager.VIRTUAL_DISPLAY_FLAG_AUTO_MIRROR,
                surface,
                object : VirtualDisplay.Callback() {
                    override fun onStopped() {
                        Log.w(TAG, "VirtualDisplay stopped")
                        listeners.forEach { it.onVirtualDisplayStopped() }
                    }
                },
                mainHandler
            )

            Log.d(TAG, "VirtualDisplay created: ${width}x${height} @ ${dpi}dpi")
            virtualDisplay?.let { listeners.forEach { l -> l.onVirtualDisplayCreated(it) } }
            return virtualDisplay
        } catch (e: Exception) {
            Log.e(TAG, "Failed to create VirtualDisplay: $e")
            notifyCaptureError(CaptureError.VIRTUAL_DISPLAY_FAILED)
            return null
        }
    }

    /**
     * Recreate VirtualDisplay with new dimensions (e.g., on rotation).
     */
    fun recreateVirtualDisplay(width: Int, height: Int): VirtualDisplay? {
        val surface = currentSurface ?: run {
            Log.e(TAG, "Cannot recreate VirtualDisplay — no surface")
            return null
        }
        return createVirtualDisplay(surface, width, height, currentDpi)
    }

    fun releaseVirtualDisplay() {
        try {
            virtualDisplay?.release()
        } catch (_: Exception) {}
        virtualDisplay = null
    }

    fun notifyConsentGranted() {
        listeners.forEach { it.onConsentGranted() }
    }

    fun notifyConsentDenied() {
        listeners.forEach { it.onConsentDenied() }
    }

    private fun notifyCaptureError(error: CaptureError) {
        Log.w(TAG, "Capture error: ${error.description}")
        listeners.forEach { it.onCaptureError(error) }
    }

    private fun cleanupInternal() {
        releaseVirtualDisplay()
        try { mediaProjection?.unregisterCallback(projectionCallback) } catch (_: Exception) {}
        try { mediaProjection?.stop() } catch (_: Exception) {}
        mediaProjection = null
    }

    /**
     * Full teardown — call when the service is being destroyed.
     */
    fun destroy() {
        cleanupInternal()
        currentSurface = null
        listeners.clear()
    }
}
