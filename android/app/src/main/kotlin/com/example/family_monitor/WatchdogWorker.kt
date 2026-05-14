package com.example.family_monitor

import android.content.Context
import android.content.Intent
import android.os.Build
import android.util.Log
import androidx.work.CoroutineWorker
import androidx.work.WorkerParameters
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

    private fun performNativeChecks() {
        Log.d(TAG, "performNativeChecks() on API ${Build.VERSION.SDK_INT}")
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
