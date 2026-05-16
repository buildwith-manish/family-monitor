package com.example.family_monitor

import android.content.Context
import android.content.Intent
import android.os.Build
import android.util.Log
import androidx.work.CoroutineWorker
import androidx.work.WorkerParameters
import com.example.family_monitor.BuildConfig
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

class WatchdogWorker(
    private val appContext: Context,
    workerParams: WorkerParameters
) : CoroutineWorker(appContext, workerParams) {

    companion object {
        private const val TAG = "WatchdogWorker"
        const val WORK_NAME = "family_monitor_watchdog"
    }

    override suspend fun doWork(): Result = withContext(Dispatchers.IO) {
        Log.d(TAG, "WatchdogWorker triggered — flavor: ${BuildConfig.FLAVOR}")
        return@withContext try {
            performNativeChecks()
            dispatchToFlutterService()
            Result.success()
        } catch (e: Exception) {
            Log.e(TAG, "WatchdogWorker failed", e)
            Result.retry()
        }
    }

    /**
     * BUG-3-FIX: Perform native-side health checks before dispatching to the
     * WatchdogService.
     *
     * Checks the Flutter background service health via the SharedPreferences
     * heartbeat timestamp. If the service is unhealthy AND an active screen
     * capture session is detected (ScreenCaptureService still alive), sets the
     * `watchdog_triggered_restart` flag so the Flutter isolate will attempt to
     * reconnect to the active session after restart.
     */
    private fun performNativeChecks() {
        Log.d(TAG, "performNativeChecks() on API ${Build.VERSION.SDK_INT}")

        try {
            val flutterPrefs = appContext.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            val lastHealthy = flutterPrefs.getLong("flutter.bg_service_last_healthy", 0L)
            val now = System.currentTimeMillis()
            val isHealthy = (now - lastHealthy) < 120_000L  // 2 minutes

            if (!isHealthy) {
                Log.w(TAG, "Background service unhealthy (last heartbeat ${now - lastHealthy}ms ago) — flagging for reconnect")

                // Check if there's an active screen session that needs reconnection.
                // If ScreenCaptureService is alive but the Flutter isolate is dead,
                // the WebRTC stream has died even though the projection token is held.
                val hasScreenSession = try {
                    ScreenCaptureService.instance != null ||
                        ScreenCaptureService.projectionToken != null
                } catch (_: Exception) { false }

                if (hasScreenSession) {
                    Log.w(TAG, "Active screen capture detected but bg service unhealthy — setting reconnect flag")
                    flutterPrefs.edit()
                        .putBoolean("flutter.watchdog_triggered_restart", true)
                        .apply()
                }
            } else {
                Log.d(TAG, "Background service healthy (last heartbeat ${now - lastHealthy}ms ago)")
            }
        } catch (e: Exception) {
            Log.e(TAG, "performNativeChecks error: $e")
        }
    }

    private fun dispatchToFlutterService() {
        val intent = Intent(appContext, WatchdogService::class.java).apply {
            action = WatchdogService.ACTION_WATCHDOG_CHECK
            putExtra(WatchdogService.EXTRA_TRIGGER_SOURCE, "WorkManager")
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            appContext.startForegroundService(intent)
        } else {
            appContext.startService(intent)
        }
    }
}
