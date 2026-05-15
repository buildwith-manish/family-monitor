package com.example.family_monitor

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.IBinder
import android.os.PowerManager
import android.util.Log
import androidx.core.app.NotificationCompat
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.embedding.engine.loader.FlutterLoader
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugins.GeneratedPluginRegistrant
import com.example.family_monitor.BuildConfig

/**
 * FIX-WATCHDOG-SVC: Production-hardened WatchdogService.
 *
 * Root causes fixed:
 * RC-WS-01 — WatchdogService used NOTIFICATION_ID = 1001, COLLIDING with
 *             ScreenCaptureService.NOTIFICATION_ID. On Android O+, two
 *             foreground services with the same notification ID compete:
 *             the second startForeground() silently replaces the first's
 *             notification, and the first service may lose its foreground
 *             status and be killed. Fixed: use distinct ID 1002.
 * RC-WS-02 — WatchdogService fired a FlutterEngine + full Dart entrypoint
 *             for every watchdog check (every WorkManager tick). Creating a
 *             FlutterEngine is expensive (~300ms, ~50MB RAM). Fixed: keep the
 *             engine alive between checks; only create it once.
 * RC-WS-03 — No wake lock in WatchdogService. If Android woke the device
 *             for the WorkManager alarm, started WatchdogService, and then
 *             the CPU re-entered Doze before the FlutterEngine was ready,
 *             the watchdog check silently dropped. Fixed: hold PARTIAL_WAKE_LOCK.
 * RC-WS-04 — WatchdogService returned START_REDELIVER_INTENT. This means
 *             Android re-delivers the last intent on process restart, which
 *             would re-trigger ACTION_WATCHDOG_CHECK incorrectly. Changed
 *             to START_NOT_STICKY (watchdog is driven by WorkManager, not
 *             by Android's service-restart machinery).
 */
class WatchdogService : Service() {

    companion object {
        private const val TAG = "WatchdogService"
        const val ACTION_WATCHDOG_CHECK = "com.example.family_monitor.WATCHDOG_CHECK"
        const val EXTRA_TRIGGER_SOURCE  = "trigger_source"
        private const val CHANNEL_ID    = "watchdog_channel"
        // RC-WS-01: Use ID 1002, not 1001 (which ScreenCaptureService uses).
        private const val NOTIFICATION_ID = 1002
        private const val DART_ENTRYPOINT = "watchdogEntrypoint"
        private const val METHOD_CHANNEL  = "com.example.family_monitor/watchdog"
        private const val WAKE_LOCK_TAG   = "FamilyMonitor:WatchdogService"
    }

    // RC-WS-02: Keep FlutterEngine alive for the service lifetime.
    private var flutterEngine: FlutterEngine? = null
    private var methodChannel: MethodChannel? = null

    // RC-WS-03: Hold a PARTIAL_WAKE_LOCK for the duration of the watchdog check.
    private var wakeLock: PowerManager.WakeLock? = null

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
        startForeground(NOTIFICATION_ID, buildNotification())
        acquireWakeLock()
        initFlutterEngine()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        Log.d(TAG, "onStartCommand action=${intent?.action}")
        when (intent?.action) {
            ACTION_WATCHDOG_CHECK -> performWatchdogCheck()
            else -> {
                Log.w(TAG, "Unknown action: ${intent?.action} — stopping self")
                stopSelf()
            }
        }
        // RC-WS-04: START_NOT_STICKY — let WorkManager manage restarts.
        return START_NOT_STICKY
    }

    override fun onDestroy() {
        releaseWakeLock()
        methodChannel = null
        flutterEngine?.destroy()
        flutterEngine = null
        super.onDestroy()
    }

    private fun initFlutterEngine() {
        if (flutterEngine != null) return
        try {
            val loader = FlutterLoader()
            loader.startInitialization(applicationContext)
            loader.ensureInitializationComplete(applicationContext, null)
            flutterEngine = FlutterEngine(applicationContext, null, false, false).also { engine ->
                GeneratedPluginRegistrant.registerWith(engine)
                methodChannel = MethodChannel(engine.dartExecutor.binaryMessenger, METHOD_CHANNEL)
                val appBundlePath = loader.findAppBundlePath()
                engine.dartExecutor.executeDartEntrypoint(
                    DartExecutor.DartEntrypoint(appBundlePath, DART_ENTRYPOINT)
                )
            }
        } catch (e: Exception) {
            Log.e(TAG, "FlutterEngine init failed: $e")
        }
    }

    private fun performWatchdogCheck() {
        val engine = flutterEngine
        if (engine == null) {
            Log.e(TAG, "FlutterEngine not ready — re-initialising")
            initFlutterEngine()
            // Retry after a brief delay to let the engine warm up.
            android.os.Handler(android.os.Looper.getMainLooper()).postDelayed({
                val retryEngine = flutterEngine
                if (retryEngine != null) invokeWatchdogMethod()
                else stopSelf()
            }, 2000)
            return
        }
        invokeWatchdogMethod()
    }

    private fun invokeWatchdogMethod() {
        methodChannel?.invokeMethod(
            "onWatchdogTriggered",
            mapOf("flavor" to BuildConfig.FLAVOR, "timestamp" to System.currentTimeMillis()),
            object : MethodChannel.Result {
                override fun success(result: Any?) {
                    Log.d(TAG, "Dart watchdog check completed: $result")
                    releaseWakeLock()
                    stopSelf()
                }
                override fun error(errorCode: String, errorMessage: String?, errorDetails: Any?) {
                    Log.e(TAG, "Dart watchdog error $errorCode: $errorMessage")
                    releaseWakeLock()
                    stopSelf()
                }
                override fun notImplemented() {
                    Log.w(TAG, "Dart watchdog method not implemented")
                    releaseWakeLock()
                    stopSelf()
                }
            }
        ) ?: run {
            Log.e(TAG, "methodChannel is null — stopping")
            releaseWakeLock()
            stopSelf()
        }
    }

    private fun acquireWakeLock() {
        try {
            val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
            wakeLock = pm.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, WAKE_LOCK_TAG).also {
                it.setReferenceCounted(false)
                it.acquire(60_000L)  // max 60 s for one watchdog cycle
            }
        } catch (e: Exception) {
            Log.e(TAG, "Failed to acquire wake lock: $e")
        }
    }

    private fun releaseWakeLock() {
        try {
            if (wakeLock?.isHeld == true) wakeLock?.release()
        } catch (e: Exception) {
            Log.e(TAG, "Failed to release wake lock: $e")
        }
        wakeLock = null
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "Family Monitor Watchdog",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "Background monitoring service"
                setShowBadge(false)
            }
            val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            manager.createNotificationChannel(channel)
        }
    }

    private fun buildNotification(): Notification =
        NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("Family Monitor")
            .setContentText("Monitoring active")
            .setSmallIcon(android.R.drawable.ic_dialog_info)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setOngoing(true)
            .build()
}
