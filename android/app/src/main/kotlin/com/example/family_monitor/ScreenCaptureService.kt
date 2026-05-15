package com.example.family_monitor

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.media.projection.MediaProjection
import android.media.projection.MediaProjectionManager
import android.os.Binder
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.PowerManager
import android.util.Log
import androidx.core.app.NotificationCompat

/**
 * ScreenCaptureService — Production-hardened MediaProjection token holder.
 *
 * ROLE: This service's ONLY job is to:
 *   1. Hold a valid MediaProjection token (obtained from user consent).
 *   2. Keep a foreground service with MEDIA_PROJECTION type active, satisfying
 *      Android 14+'s requirement for any process calling getDisplayMedia.
 *   3. Survive aggressive OEM background killing via PARTIAL_WAKE_LOCK.
 *
 * CAPTURE: Actual screen capture is performed by flutter_webrtc's getDisplayMedia()
 * running inside the flutter_background_service isolate (BackgroundService). That
 * service has camera|microphone|dataSync in its foreground service type. The
 * MEDIA_PROJECTION type in THIS service satisfies the system-wide check on API 34+.
 *
 * ROOT CAUSES FIXED:
 *
 * RC-01 — No PARTIAL_WAKE_LOCK: CPU suspended on screen-off → capture froze.
 *          Fixed: PARTIAL_WAKE_LOCK acquired in onCreate(), released in onDestroy().
 *
 * RC-02 — Wrong startForeground() call order on Android 14+:
 *          startFg(MEDIA_PROJECTION) was called BEFORE getMediaProjection().
 *          Android 14+ requires the token to exist BEFORE startForeground with
 *          MEDIA_PROJECTION type. Fixed: use two-phase startForeground:
 *            Phase 1 → DATA_SYNC (immediate, satisfies 5s rule)
 *            Phase 2 → MEDIA_PROJECTION (after token is obtained)
 *
 * RC-03 — MediaProjection.Callback.onStop registered only on API 34+.
 *          On Android 12–13, token revocation was silent → black screen, no recovery.
 *          Fixed: Callback registered on API 29+ (Android Q+).
 *
 * RC-04 — NOTIFICATION_ID collision with WatchdogService (both used 1001).
 *          This service uses 1001; WatchdogService now uses 1002.
 *
 * RC-05 — onDestroy() did not release wake lock → battery drain on restart cycle.
 *          Fixed: releaseWakeLock() called in onDestroy() and ACTION_STOP path.
 *
 * RC-06 — onStartCommand(null) jumped straight to requestPermissionViaUi()
 *          without attempting a silent restart first. On START_STICKY restart
 *          with a valid saved token, a silent restart is preferred.
 *          Fixed: Try silent restart before showing UI.
 */
class ScreenCaptureService : Service() {

    companion object {
        private const val TAG                = "ScreenCaptureService"
        const val ACTION_START               = "START_SCREEN_CAPTURE"
        const val ACTION_STOP                = "STOP_SCREEN_CAPTURE"
        const val ACTION_START_SILENT        = "START_SCREEN_CAPTURE_SILENT"
        const val ACTION_PERMISSION_REQUIRED = "com.example.family_monitor.PROJECTION_PERMISSION_REQUIRED"
        const val EXTRA_RESULT_CODE          = "RESULT_CODE"
        const val EXTRA_RESULT_DATA          = "RESULT_DATA"
        const val CHANNEL_ID                 = "fm_screen_capture_v2"
        const val NOTIFICATION_ID            = 1001

        @Volatile var instance: ScreenCaptureService?  = null
        @Volatile var savedResultCode: Int              = 0
        @Volatile var savedResultData: Intent?          = null
        @Volatile var projectionToken: MediaProjection? = null

        // Prevents TOCTOU race where two concurrent onStartCommand deliveries
        // both pass the boolean check before either sets it, causing double-start.
        private val starting = java.util.concurrent.atomic.AtomicBoolean(false)

        private const val WAKE_LOCK_TAG = "FamilyMonitor:ScreenCapture"
    }

    inner class LocalBinder : Binder() { fun getService() = this@ScreenCaptureService }
    private val binder      = LocalBinder()
    private val mainHandler = Handler(Looper.getMainLooper())

    private var mediaProjection: MediaProjection? = null
    var resultCode: Int     = 0
    var resultData: Intent? = null

    // RC-01: PARTIAL_WAKE_LOCK keeps CPU running when screen is off.
    // Foreground service type alone does NOT prevent CPU sleep on aggressive OEMs.
    private var wakeLock: PowerManager.WakeLock? = null

    override fun onCreate() {
        super.onCreate()
        instance = this
        createChannel()
        acquireWakeLock()
        Log.d(TAG, "onCreate — wake lock acquired")
    }

    override fun onBind(intent: Intent?): IBinder = binder

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        Log.d(TAG, "onStartCommand action=${intent?.action}")
        when (intent?.action) {
            ACTION_START -> {
                resultCode = intent.getIntExtra(EXTRA_RESULT_CODE, 0)
                @Suppress("DEPRECATION")
                resultData = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU)
                    intent.getParcelableExtra(EXTRA_RESULT_DATA, Intent::class.java)
                else intent.getParcelableExtra(EXTRA_RESULT_DATA)
                savedResultCode = resultCode
                savedResultData = resultData
                startCaptureSafe()
            }
            ACTION_START_SILENT -> {
                resultCode = savedResultCode
                resultData = savedResultData
                if (resultCode != 0 && resultData != null) startCaptureSafe()
                else requestPermissionViaUi()
            }
            ACTION_STOP -> {
                releaseWakeLock()
                stopSelf()
                return START_NOT_STICKY
            }
            null -> {
                // RC-06: START_STICKY restart after process death delivers null intent.
                // Try silent restart first; only show UI if no saved token exists.
                if (savedResultCode != 0 && savedResultData != null) {
                    resultCode = savedResultCode
                    resultData = savedResultData
                    startCaptureSafe()
                } else {
                    requestPermissionViaUi()
                }
            }
        }
        return START_STICKY
    }

    private fun requestPermissionViaUi() {
        // Use DATA_SYNC type — safe to call without a MediaProjection token.
        startFgDataSync()
        sendBroadcast(Intent(ACTION_PERMISSION_REQUIRED).apply { setPackage(packageName) })
        try {
            startActivity(
                packageManager.getLaunchIntentForPackage(packageName)?.apply {
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
                } ?: return
            )
        } catch (_: Exception) {}
    }

    private fun startCaptureSafe() {
        if (!starting.compareAndSet(false, true)) return
        try {
            // ── RC-02: TWO-PHASE startForeground for Android 14+ compatibility ──
            //
            // Phase 1: Start foreground with DATA_SYNC type IMMEDIATELY.
            //          This satisfies Android's 5-second startForeground rule
            //          and prevents the ForegroundServiceDidNotStartInTimeException.
            //          DATA_SYNC does NOT require a MediaProjection token.
            startFgDataSync()

            val pm   = getSystemService(MEDIA_PROJECTION_SERVICE) as MediaProjectionManager
            val data = resultData ?: run { starting.set(false); return }

            teardownProjection()

            // Phase 2: Get the MediaProjection token.
            mediaProjection = pm.getMediaProjection(resultCode, data)

            // Phase 3: Now that we have the token, upgrade to MEDIA_PROJECTION type.
            // On Android 14+, this satisfies the system-wide check that allows
            // flutter_webrtc's getDisplayMedia() to run successfully in BackgroundService.
            // On older APIs, upgrading is safe (idempotent second call to startForeground).
            startFgMediaProjection()

            // RC-03: Register MediaProjection.Callback on API 29+.
            // On Android 12–13, token revocation was silent. This callback fires
            // when the system invalidates the token (config change, user revoke, etc.).
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
                mediaProjection?.registerCallback(object : MediaProjection.Callback() {
                    override fun onStop() {
                        Log.w(TAG, "MediaProjection stopped by system (API34+)")
                        mainHandler.post { onProjectionStopped() }
                    }
                }, mainHandler)
            } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                @Suppress("DEPRECATION")
                mediaProjection?.registerCallback(object : MediaProjection.Callback() {
                    override fun onStop() {
                        Log.w(TAG, "MediaProjection stopped by system (API29-33)")
                        mainHandler.post { onProjectionStopped() }
                    }
                }, mainHandler)
            }

            projectionToken = mediaProjection

            // Persist consent so boot receiver / watchdog know to attempt silent restart.
            applicationContext
                .getSharedPreferences("fm_prefs", Context.MODE_PRIVATE)
                .edit()
                .putBoolean("projection_consent_granted", true)
                .apply()
            Log.d(TAG, "MediaProjection created — token active")
        } catch (e: Exception) {
            Log.e(TAG, "startCaptureSafe failed: $e")
            requestPermissionViaUi()
        } finally {
            starting.set(false)
        }
    }

    /** Called when the system revokes the MediaProjection token. */
    private fun onProjectionStopped() {
        teardownProjection()
        projectionToken = null
        if (savedResultCode != 0 && savedResultData != null) {
            Log.d(TAG, "Token revoked — attempting silent re-establish")
            startCaptureSafe()
        } else {
            requestPermissionViaUi()
        }
    }

    // ── startForeground helpers ──────────────────────────────────────────────

    /**
     * Phase 1 startForeground — DATA_SYNC type. Safe to call without a token.
     * Satisfies the 5-second rule. Used immediately on service start and as
     * fallback when no token is available.
     */
    private fun startFgDataSync() {
        createChannel()
        val n = buildNotification()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            try {
                startForeground(
                    NOTIFICATION_ID, n,
                    android.content.pm.ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC
                )
            } catch (e: Exception) {
                Log.w(TAG, "startFgDataSync failed, untyped fallback: $e")
                try { startForeground(NOTIFICATION_ID, n) } catch (_: Exception) {}
            }
        } else {
            try { startForeground(NOTIFICATION_ID, n) } catch (_: Exception) {}
        }
    }

    /**
     * Phase 2 startForeground — MEDIA_PROJECTION type. Call ONLY after getMediaProjection()
     * succeeds. Satisfies Android 14+'s requirement that a foreground service with
     * MEDIA_PROJECTION type is active when getDisplayMedia() / createVirtualDisplay() runs.
     */
    private fun startFgMediaProjection() {
        createChannel()
        val n = buildNotification()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            try {
                startForeground(
                    NOTIFICATION_ID, n,
                    android.content.pm.ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PROJECTION
                )
                Log.d(TAG, "Foreground upgraded to MEDIA_PROJECTION type")
            } catch (e: Exception) {
                // On some OEMs (MIUI) the typed call fails even with a valid token.
                // Fall back to untyped — still better than crashing.
                Log.w(TAG, "startFgMediaProjection failed, falling back to DATA_SYNC: $e")
                startFgDataSync()
            }
        }
        // Pre-Q: no typed startForeground, DATA_SYNC is already set.
    }

    private fun teardownProjection() {
        try { mediaProjection?.stop() } catch (_: Exception) {}
        projectionToken = null
        mediaProjection = null
    }

    fun reinitAfterReconnect() {
        if (resultCode != 0 && resultData != null) {
            teardownProjection()
            startCaptureSafe()
        } else {
            requestPermissionViaUi()
        }
    }

    fun getProjectionParams(): Pair<Int, Intent>? {
        val d = resultData ?: return null
        return Pair(resultCode, d)
    }

    // ── Wake lock ────────────────────────────────────────────────────────────

    private fun acquireWakeLock() {
        if (wakeLock?.isHeld == true) return
        try {
            val pm = getSystemService(POWER_SERVICE) as PowerManager
            wakeLock = pm.newWakeLock(
                PowerManager.PARTIAL_WAKE_LOCK,
                WAKE_LOCK_TAG
            ).also {
                it.setReferenceCounted(false)
                // 10-hour max. Service is restarted by watchdog well before this.
                // PARTIAL_WAKE_LOCK only keeps CPU awake — does NOT keep screen on.
                it.acquire(10 * 60 * 60 * 1000L)
            }
            Log.d(TAG, "PARTIAL_WAKE_LOCK acquired")
        } catch (e: Exception) {
            Log.e(TAG, "Failed to acquire wake lock: $e")
        }
    }

    private fun releaseWakeLock() {
        try {
            if (wakeLock?.isHeld == true) {
                wakeLock?.release()
                Log.d(TAG, "PARTIAL_WAKE_LOCK released")
            }
        } catch (e: Exception) {
            Log.e(TAG, "Failed to release wake lock: $e")
        }
        wakeLock = null
    }

    // ── Lifecycle ────────────────────────────────────────────────────────────

    override fun onTaskRemoved(rootIntent: Intent?) {
        super.onTaskRemoved(rootIntent)
        WatchdogReceiver.schedule(applicationContext)
    }

    override fun onDestroy() {
        teardownProjection()
        releaseWakeLock()   // RC-05: always release to prevent battery drain
        instance = null
        WatchdogReceiver.schedule(applicationContext)
        Log.d(TAG, "onDestroy — released, watchdog rescheduled")
        super.onDestroy()
    }

    // ── Notification ─────────────────────────────────────────────────────────

    private fun createChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val nm = getSystemService(NotificationManager::class.java)
            if (nm.getNotificationChannel("fm_bg_sync") != null) {
                nm.deleteNotificationChannel("fm_bg_sync")
            }
            val existing = nm.getNotificationChannel(CHANNEL_ID)
            if (existing != null && existing.importance >= NotificationManager.IMPORTANCE_LOW) return
            if (existing != null) nm.deleteNotificationChannel(CHANNEL_ID)
            val ch = NotificationChannel(
                CHANNEL_ID,
                "Family Monitor Service",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description    = "Required for screen monitoring service"
                setShowBadge(false)
                enableLights(false)
                enableVibration(false)
                setSound(null, null)
            }
            nm.createNotificationChannel(ch)
        }
    }

    private fun buildNotification(): Notification {
        val launchIntent: Intent = try {
            packageManager.getLaunchIntentForPackage(packageName)
        } catch (_: Exception) { null }
            ?: Intent(this, MainActivity::class.java).apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
            }

        val openIntent = PendingIntent.getActivity(
            this, 0, launchIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("Family Monitor — Active")
            .setContentText("Screen monitoring is running.")
            .setSmallIcon(android.R.drawable.ic_menu_camera)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setOngoing(true)
            .setSilent(true)
            .setContentIntent(openIntent)
            .build()
    }
}
