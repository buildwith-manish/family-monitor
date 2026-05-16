# Screen Mirroring Feature — Like FlashGet Kids
## Repo: https://github.com/buildwith-manish/family-monitor.git

---

## Context

I have already built a parental control Android app with two
APKs — child app and parent app — with a Node.js/MongoDB
backend. I have a basic live screen feature that is NOT working
properly. I want it to work exactly like FlashGet Kids screen
mirroring.

---

## How FlashGet Kids Screen Mirroring Works
> This is the exact behavior to replicate

1. During child app setup, parent grants MediaProjection
   permission **ONCE** on the child device
2. The token/result from MediaProjection is saved persistently
3. From that point, parent can tap "Live Screen" anytime in
   parent app and instantly see child's screen
4. A persistent foreground notification shows on child device:
   **"Screen sharing is active"** — required by Android, cannot be removed
5. Stream is low latency, updates in near real-time (~5fps)
6. Parent app shows the stream in a fullscreen view
7. Parent can stop the stream from their end
8. Child can also stop it by dismissing the notification

---

## What To Do

Look at the existing code in the repo carefully, then **fix and
complete** the screen mirroring to match the above behavior.

---

## CHILD APP CHANGES

### 1. One-Time MediaProjection Permission (Setup Flow)

Add to `PermissionsActivity.kt` or `SetupActivity.kt`:

```kotlin
private val mediaProjectionLauncher = registerForActivityResult(
    ActivityResultContracts.StartActivityForResult()
) { result ->
    if (result.resultCode == Activity.RESULT_OK) {
        MediaProjectionTokenManager.saveToken(
            this, result.resultCode, result.data)
    }
}

// Call this during setup permissions step
val mediaProjectionManager = getSystemService(
    Context.MEDIA_PROJECTION_SERVICE) as MediaProjectionManager
mediaProjectionLauncher.launch(
    mediaProjectionManager.createScreenCaptureIntent())
```

---

### 2. MediaProjectionTokenManager.kt (NEW FILE)

```kotlin
object MediaProjectionTokenManager {
    private const val PREFS = "screen_prefs"
    private const val KEY_RESULT_CODE = "mp_result_code"

    fun saveToken(context: Context, resultCode: Int, data: Intent?) {
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .edit()
            .putInt(KEY_RESULT_CODE, resultCode)
            .apply()
        savedResultCode = resultCode
        savedData = data
    }

    var savedResultCode: Int = -1
    var savedData: Intent? = null

    fun isAvailable() = savedResultCode != -1 && savedData != null

    fun clear() {
        savedResultCode = -1
        savedData = null
    }
}
```

---

### 3. ScreenMirrorService.kt (COMPLETE REWRITE)

```kotlin
@AndroidEntryPoint
class ScreenMirrorService : Service() {

    companion object {
        const val ACTION_START = "START_MIRROR"
        const val ACTION_STOP = "STOP_MIRROR"
        const val NOTIFICATION_ID = 1001
        var isRunning = false
    }

    private var mediaProjection: MediaProjection? = null
    private var virtualDisplay: VirtualDisplay? = null
    private var imageReader: ImageReader? = null
    private var webSocket: WebSocket? = null
    private val handler = Handler(Looper.getMainLooper())
    private var isStreaming = false

    // Stream config — balance quality vs latency
    private val STREAM_WIDTH = 720
    private val STREAM_HEIGHT = 1280
    private val STREAM_DPI = 320
    private val JPEG_QUALITY = 40     // Lower = faster, less data
    private val FRAME_INTERVAL_MS = 200L  // 5fps — same as FlashGet

    override fun onStartCommand(intent: Intent?, flags: Int,
                                startId: Int): Int {
        when (intent?.action) {
            ACTION_START -> startMirroring()
            ACTION_STOP  -> stopMirroring()
        }
        return START_STICKY
    }

    private fun startMirroring() {
        if (isStreaming) return
        startForeground(NOTIFICATION_ID, buildNotification())
        isRunning = true

        if (!MediaProjectionTokenManager.isAvailable()) {
            stopSelf()
            return
        }

        val mpManager = getSystemService(
            Context.MEDIA_PROJECTION_SERVICE) as MediaProjectionManager

        mediaProjection = mpManager.getMediaProjection(
            MediaProjectionTokenManager.savedResultCode,
            MediaProjectionTokenManager.savedData!!
        )

        mediaProjection?.registerCallback(object :
            MediaProjection.Callback() {
            override fun onStop() { stopMirroring() }
        }, handler)

        imageReader = ImageReader.newInstance(
            STREAM_WIDTH, STREAM_HEIGHT,
            PixelFormat.RGBA_8888, 2
        )

        virtualDisplay = mediaProjection?.createVirtualDisplay(
            "ScreenMirror",
            STREAM_WIDTH, STREAM_HEIGHT, STREAM_DPI,
            DisplayManager.VIRTUAL_DISPLAY_FLAG_AUTO_MIRROR,
            imageReader?.surface, null, handler
        )

        connectWebSocket()
        isStreaming = true
        startFrameCapture()
    }

    private fun connectWebSocket() {
        val serverUrl = BuildConfig.BASE_URL
            .replace("https://", "wss://")
            .replace("http://", "ws://")

        val token = getSharedPreferences("auth_prefs",
            Context.MODE_PRIVATE).getString("token", "") ?: ""
        val deviceId = getSharedPreferences("device_prefs",
            Context.MODE_PRIVATE).getString("device_id", "") ?: ""

        val request = Request.Builder()
            .url("$serverUrl/ws/screen?deviceId=$deviceId&token=$token")
            .build()

        webSocket = OkHttpClient.Builder()
            .pingInterval(10, TimeUnit.SECONDS)
            .build()
            .newWebSocket(request, object : WebSocketListener() {
                override fun onOpen(ws: WebSocket, response: Response) {
                    ws.send(JSONObject().apply {
                        put("type", "screen_register")
                        put("deviceId", deviceId)
                    }.toString())
                }
                override fun onMessage(ws: WebSocket, text: String) {
                    val msg = JSONObject(text)
                    if (msg.getString("type") == "stop_stream") {
                        stopMirroring()
                    }
                }
                override fun onFailure(ws: WebSocket, t: Throwable,
                                       response: Response?) {
                    handler.postDelayed({ connectWebSocket() }, 3000)
                }
            })
    }

    private fun startFrameCapture() {
        handler.post(object : Runnable {
            override fun run() {
                if (!isStreaming) return
                captureAndSendFrame()
                handler.postDelayed(this, FRAME_INTERVAL_MS)
            }
        })
    }

    private fun captureAndSendFrame() {
        val image = imageReader?.acquireLatestImage() ?: return
        try {
            val planes     = image.planes
            val buffer     = planes[0].buffer
            val pixelStride = planes[0].pixelStride
            val rowStride  = planes[0].rowStride
            val rowPadding = rowStride - pixelStride * STREAM_WIDTH

            val bitmap = Bitmap.createBitmap(
                STREAM_WIDTH + rowPadding / pixelStride,
                STREAM_HEIGHT, Bitmap.Config.ARGB_8888
            )
            bitmap.copyPixelsFromBuffer(buffer)

            val cropped = Bitmap.createBitmap(
                bitmap, 0, 0, STREAM_WIDTH, STREAM_HEIGHT)
            bitmap.recycle()

            val outputStream = ByteArrayOutputStream()
            cropped.compress(Bitmap.CompressFormat.JPEG,
                JPEG_QUALITY, outputStream)
            cropped.recycle()

            val base64Frame = Base64.encodeToString(
                outputStream.toByteArray(), Base64.NO_WRAP)

            webSocket?.send(JSONObject().apply {
                put("type", "screen_frame")
                put("frame", base64Frame)
                put("timestamp", System.currentTimeMillis())
            }.toString())

        } catch (e: Exception) {
            // Skip frame on error
        } finally {
            image.close()
        }
    }

    private fun stopMirroring() {
        isStreaming = false
        isRunning   = false
        virtualDisplay?.release()
        mediaProjection?.stop()
        imageReader?.close()
        webSocket?.close(1000, "Stopped")
        stopForeground(true)
        stopSelf()
    }

    private fun buildNotification(): Notification {
        val channelId = "screen_mirror_channel"
        val channel = NotificationChannel(
            channelId, "Screen Sharing",
            NotificationManager.IMPORTANCE_LOW
        ).apply {
            description = "Active screen sharing with parent"
        }
        (getSystemService(Context.NOTIFICATION_SERVICE) as
            NotificationManager).createNotificationChannel(channel)

        val stopIntent = PendingIntent.getService(
            this, 0,
            Intent(this, ScreenMirrorService::class.java).apply {
                action = ACTION_STOP
            },
            PendingIntent.FLAG_IMMUTABLE
        )

        return NotificationCompat.Builder(this, channelId)
            .setContentTitle("Screen sharing active")
            .setContentText(
                "Parent is viewing your screen. Tap to stop.")
            .setSmallIcon(R.drawable.ic_screen_share)
            .addAction(R.drawable.ic_stop, "Stop", stopIntent)
            .setOngoing(true)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .build()
    }

    override fun onBind(intent: Intent?) = null

    override fun onDestroy() {
        stopMirroring()
        super.onDestroy()
    }
}
```

---

### 4. AndroidManifest.xml — Child App Addition

```xml
<service
    android:name=".services.ScreenMirrorService"
    android:foregroundServiceType="mediaProjection"
    android:exported="false" />
```

---

### 5. WebSocketService.kt — Add Command Handling

In your existing command receiver, add:

```kotlin
when (command.type) {
    "start_screen_mirror" -> {
        if (MediaProjectionTokenManager.isAvailable()) {
            val intent = Intent(context,
                ScreenMirrorService::class.java).apply {
                action = ScreenMirrorService.ACTION_START
            }
            context.startForegroundService(intent)
        } else {
            sendToBackend(JSONObject().apply {
                put("type", "screen_mirror_error")
                put("reason", "permission_not_granted")
            })
        }
    }
    "stop_screen_mirror" -> {
        val intent = Intent(context,
            ScreenMirrorService::class.java).apply {
            action = ScreenMirrorService.ACTION_STOP
        }
        context.startService(intent)
    }
}
```

---

## BACKEND CHANGES

### server.js — Add `/ws/screen` WebSocket Endpoint

```javascript
// Separate maps for screen streaming connections
const screenSenders = new Map()  // deviceId -> ws (child)
const screenViewers = new Map()  // deviceId -> ws (parent)

wss.on('connection', (ws, req) => {
    const url      = new URL(req.url, 'http://localhost')
    const isScreen = url.pathname === '/ws/screen'
    const deviceId = url.searchParams.get('deviceId')

    if (!isScreen) return  // handled by existing ws logic

    ws.on('message', (msg) => {
        try {
            const data = JSON.parse(msg)

            switch (data.type) {

                case 'screen_register':
                    // Child device registers as frame sender
                    screenSenders.set(data.deviceId, ws)
                    break

                case 'screen_frame':
                    // Forward frame directly to parent viewer
                    const viewer = screenViewers.get(data.deviceId)
                    if (viewer?.readyState === WebSocket.OPEN) {
                        viewer.send(msg)
                    }
                    break

                case 'parent_watching':
                    // Parent registers to receive frames
                    screenViewers.set(data.deviceId, ws)
                    break

                case 'stop_stream':
                    // Parent stopped — notify child
                    const sender = screenSenders.get(data.deviceId)
                    if (sender?.readyState === WebSocket.OPEN) {
                        sender.send(JSON.stringify({
                            type: 'stop_stream'
                        }))
                    }
                    screenViewers.delete(data.deviceId)
                    break
            }
        } catch (e) {
            console.error('Screen WS error:', e)
        }
    })

    ws.on('close', () => {
        for (const [id, conn] of screenSenders) {
            if (conn === ws) screenSenders.delete(id)
        }
        for (const [id, conn] of screenViewers) {
            if (conn === ws) screenViewers.delete(id)
        }
    })
})
```

---

## PARENT APP CHANGES

### LiveScreenActivity.kt (COMPLETE REWRITE)

```kotlin
@AndroidEntryPoint
class LiveScreenActivity : AppCompatActivity() {

    private lateinit var binding: ActivityLiveScreenBinding
    private var webSocket: WebSocket? = null
    private val deviceId by lazy {
        intent.getStringExtra("device_id") ?: ""
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        binding = ActivityLiveScreenBinding.inflate(layoutInflater)
        setContentView(binding.root)

        window.addFlags(
            WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)

        binding.btnStop.setOnClickListener {
            stopWatching()
            finish()
        }

        binding.tvStatus.text = "Connecting..."
        connectAndWatch()
    }

    private fun connectAndWatch() {
        val serverUrl = BuildConfig.BASE_URL
            .replace("https://", "wss://")
            .replace("http://", "ws://")
        val token = getSharedPreferences("auth_prefs",
            Context.MODE_PRIVATE).getString("token", "")

        val request = Request.Builder()
            .url("$serverUrl/ws/screen?token=$token")
            .build()

        webSocket = OkHttpClient.Builder()
            .pingInterval(10, TimeUnit.SECONDS)
            .build()
            .newWebSocket(request, object : WebSocketListener() {

                override fun onOpen(ws: WebSocket, response: Response) {
                    // Register as viewer for this child device
                    ws.send(JSONObject().apply {
                        put("type", "parent_watching")
                        put("deviceId", deviceId)
                    }.toString())

                    // Tell child to start streaming
                    sendCommandToChild("start_screen_mirror")

                    runOnUiThread {
                        binding.tvStatus.text = "Waiting for stream..."
                    }
                }

                override fun onMessage(ws: WebSocket, text: String) {
                    val data = JSONObject(text)

                    when (data.getString("type")) {
                        "screen_frame" -> {
                            val bytes = Base64.decode(
                                data.getString("frame"), Base64.NO_WRAP)
                            val bitmap = BitmapFactory
                                .decodeByteArray(bytes, 0, bytes.size)
                            runOnUiThread {
                                binding.ivScreen.setImageBitmap(bitmap)
                                binding.tvStatus.visibility = View.GONE
                            }
                        }
                        "screen_mirror_error" -> {
                            runOnUiThread {
                                binding.tvStatus.text =
                                    "Screen permission not set up.\n" +
                                    "Ask child to re-run setup."
                            }
                        }
                    }
                }

                override fun onFailure(ws: WebSocket, t: Throwable,
                                       response: Response?) {
                    runOnUiThread {
                        binding.tvStatus.text = "Connection failed. Retrying..."
                    }
                    Handler(Looper.getMainLooper())
                        .postDelayed({ connectAndWatch() }, 3000)
                }
            })
    }

    private fun sendCommandToChild(type: String) {
        CoroutineScope(Dispatchers.IO).launch {
            CommandRepository.sendCommand(deviceId, type, "{}")
        }
    }

    private fun stopWatching() {
        webSocket?.send(JSONObject().apply {
            put("type", "stop_stream")
            put("deviceId", deviceId)
        }.toString())
        webSocket?.close(1000, "Parent stopped")
        sendCommandToChild("stop_screen_mirror")
    }

    override fun onDestroy() {
        stopWatching()
        super.onDestroy()
    }
}
```

---

### activity_live_screen.xml

```xml
<?xml version="1.0" encoding="utf-8"?>
<FrameLayout
    xmlns:android="http://schemas.android.com/apk/res/android"
    android:layout_width="match_parent"
    android:layout_height="match_parent"
    android:background="#000000">

    <ImageView
        android:id="@+id/ivScreen"
        android:layout_width="match_parent"
        android:layout_height="match_parent"
        android:scaleType="fitCenter"
        android:contentDescription="Child screen" />

    <TextView
        android:id="@+id/tvStatus"
        android:layout_width="wrap_content"
        android:layout_height="wrap_content"
        android:layout_gravity="center"
        android:textColor="#FFFFFF"
        android:textSize="16sp"
        android:gravity="center"
        android:text="Connecting..." />

    <Button
        android:id="@+id/btnStop"
        android:layout_width="wrap_content"
        android:layout_height="wrap_content"
        android:layout_gravity="bottom|center_horizontal"
        android:layout_marginBottom="32dp"
        android:text="Stop Viewing"
        android:backgroundTint="#FF4444" />

</FrameLayout>
```

---

## Important Notes for AI Agent

| Rule | Detail |
|---|---|
| Do NOT replace existing features | Only modify screen mirroring files |
| Two separate WebSockets | `/ws` = commands (unchanged), `/ws/screen` = frames (new) |
| Frame rate | 5fps (200ms interval) — same as FlashGet Kids |
| JPEG quality | 40 — keeps latency low on mobile data |
| Token expiry | After device reboot, MediaProjection token is lost. Show message: "Ask child to re-grant screen permission" |
| Notification | Cannot be removed — required by Android OS |

---

## Files to Modify

### Child App
- `PermissionsActivity.kt` or `SetupActivity.kt` — add MediaProjection request
- `MediaProjectionTokenManager.kt` — create new file
- `ScreenMirrorService.kt` — complete rewrite
- `WebSocketService.kt` — add start/stop command handling
- `AndroidManifest.xml` — add service declaration

### Backend
- `server.js` — add `/ws/screen` WebSocket handler

### Parent App
- `LiveScreenActivity.kt` — complete rewrite
- `activity_live_screen.xml` — replace layout

---

## How It Flows End to End

```
SETUP (one time):
Parent opens child app → taps through permissions →
MediaProjection dialog appears → child/parent taps Allow →
Token saved in MediaProjectionTokenManager

LIVE VIEW:
Parent taps "Live Screen" in parent app
→ Parent app connects to /ws/screen
→ Parent app sends {type:"parent_watching", deviceId}
→ Parent app sends command "start_screen_mirror" via /ws
→ Child receives command → starts ScreenMirrorService
→ Child connects to /ws/screen
→ Child sends {type:"screen_register", deviceId}
→ Child captures frames every 200ms → sends to /ws/screen
→ Backend forwards frames to parent viewer
→ Parent app decodes JPEG → displays in ImageView

STOP:
Parent taps Stop
→ Parent sends {type:"stop_stream"} to /ws/screen
→ Backend forwards stop signal to child
→ Child stops ScreenMirrorService
→ Foreground notification dismissed
→ All connections closed
```
