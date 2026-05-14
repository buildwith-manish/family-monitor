package com.example.family_monitor

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.IBinder
import android.util.Log
import androidx.core.app.NotificationCompat
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.embedding.engine.loader.FlutterLoader
import io.flutter.plugin.common.MethodChannel

class WatchdogService : Service() {

    companion object {
        private const val TAG = "WatchdogService"
        const val ACTION_WATCHDOG_CHECK = "com.example.family_monitor.WATCHDOG_CHECK"
        const val EXTRA_TRIGGER_SOURCE = "trigger_source"
        private const val CHANNEL_ID = "watchdog_channel"
        private const val NOTIFICATION_ID = 1001
        private const val DART_ENTRYPOINT = "watchdogEntrypoint"
        private const val METHOD_CHANNEL = "com.example.family_monitor/watchdog"
    }

    private var flutterEngine: FlutterEngine? = null
    private var methodChannel: MethodChannel? = null

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
        startForeground(NOTIFICATION_ID, buildNotification())
        initFlutterEngine()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        Log.d(TAG, "onStartCommand action=${intent?.action}")
        when (intent?.action) {
            ACTION_WATCHDOG_CHECK -> performWatchdogCheck()
            else -> Log.w(TAG, "Unknown action: ${intent?.action}")
        }
        return START_REDELIVER_INTENT
    }

    override fun onDestroy() {
        methodChannel = null
        flutterEngine?.destroy()
        flutterEngine = null
        super.onDestroy()
    }

    private fun initFlutterEngine() {
        if (flutterEngine != null) return
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
    }

    private fun performWatchdogCheck() {
        val engine = flutterEngine
        if (engine == null) {
            Log.e(TAG, "FlutterEngine not ready — re-initialising")
            initFlutterEngine()
            return
        }
        methodChannel?.invokeMethod(
            "onWatchdogTriggered",
            mapOf("flavor" to BuildConfig.FLAVOR, "timestamp" to System.currentTimeMillis()),
            object : MethodChannel.Result {
                override fun success(result: Any?) {
                    Log.d(TAG, "Dart watchdog check completed: $result")
                    stopSelf()
                }
                override fun error(errorCode: String, errorMessage: String?, errorDetails: Any?) {
                    Log.e(TAG, "Dart watchdog error $errorCode: $errorMessage")
                    stopSelf()
                }
                override fun notImplemented() {
                    Log.w(TAG, "Dart watchdog method not implemented")
                    stopSelf()
                }
            }
        )
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
