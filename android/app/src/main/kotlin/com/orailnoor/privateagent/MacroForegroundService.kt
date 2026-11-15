package com.orailnoor.privateagent

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.net.wifi.WifiManager
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.PowerManager
import android.util.Log
import androidx.core.app.NotificationCompat
import org.json.JSONArray
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL

class MacroForegroundService : Service() {
    companion object {
        private const val TAG = "MacroForegroundService"
        const val CHANNEL_ID = "privateagent_routine_fgs_channel"
        const val NOTIFICATION_ID = 2001

        const val ACTION_START_LISTENER = "START_LISTENER"
        const val ACTION_START_EXECUTION = "START_EXECUTION"
        const val ACTION_STOP_SERVICE = "STOP_SERVICE"

        var isRunning = false
            private set
        var isExecutingRoutine = false
            private set

        private var instance: MacroForegroundService? = null

        fun startListener(context: Context, statusText: String = "Listening for Telegram commands & scheduled routines") {
            val intent = Intent(context, MacroForegroundService::class.java).apply {
                action = ACTION_START_LISTENER
                putExtra("status_text", statusText)
            }
            startServiceCompat(context, intent)
        }

        fun startExecution(context: Context, routineTitle: String) {
            val intent = Intent(context, MacroForegroundService::class.java).apply {
                action = ACTION_START_EXECUTION
                putExtra("routine_title", routineTitle)
            }
            startServiceCompat(context, intent)
        }

        fun start(context: Context, routineTitle: String) {
            startExecution(context, routineTitle)
        }

        fun stop(context: Context) {
            val intent = Intent(context, MacroForegroundService::class.java).apply {
                action = ACTION_STOP_SERVICE
            }
            context.stopService(intent)
        }

        fun reloadTelegramPoller() {
            instance?.let { service ->
                service.stopTelegramPoller()
                service.startTelegramPoller()
            }
        }

        fun wakeScreenTemporarily(context: Context, durationMs: Long = 5000L) {
            try {
                val pm = context.getSystemService(Context.POWER_SERVICE) as? PowerManager
                @Suppress("DEPRECATION")
                val screenLock = pm?.newWakeLock(
                    PowerManager.SCREEN_BRIGHT_WAKE_LOCK or PowerManager.ACQUIRE_CAUSES_WAKEUP,
                    "PrivateAgent:ScreenWakeTelegram"
                )
                screenLock?.acquire(durationMs)
                Log.d(TAG, "Screen temporarily woken for $durationMs ms")
            } catch (e: Exception) {
                Log.e(TAG, "Error waking screen: ${e.message}")
            }
        }

        private fun startServiceCompat(context: Context, intent: Intent) {
            try {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    context.startForegroundService(intent)
                } else {
                    context.startService(intent)
                }
            } catch (e: Exception) {
                Log.e(TAG, "Failed to start service: ${e.message}")
            }
        }
    }

    private var partialWakeLock: PowerManager.WakeLock? = null
    private var wifiLock: WifiManager.WifiLock? = null

    private var isPollingTelegram = false
    private var pollingThread: Thread? = null
    private var lastUpdateId: Long = 0

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        instance = this
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val action = intent?.action ?: ACTION_START_LISTENER
        createNotificationChannel()

        when (action) {
            ACTION_STOP_SERVICE -> {
                Log.d(TAG, "Stopping service via ACTION_STOP_SERVICE")
                isRunning = false
                isExecutingRoutine = false
                stopTelegramPoller()
                releaseLocks()
                stopForeground(true)
                stopSelf()
                return START_NOT_STICKY
            }

            ACTION_START_EXECUTION -> {
                Log.d(TAG, "Starting execution mode")
                isRunning = true
                isExecutingRoutine = true
                acquireLocks()
                val title = intent?.getStringExtra("routine_title") ?: "Running Autonomous Routine..."
                val notification = buildExecutionNotification(title)
                startForeground(NOTIFICATION_ID, notification)
            }

            else -> { // ACTION_START_LISTENER
                Log.d(TAG, "Starting listener mode")
                isRunning = true
                isExecutingRoutine = false
                acquireLocks()
                startTelegramPoller()
                val statusText = intent?.getStringExtra("status_text") ?: "Listening for Telegram commands & scheduled routines"
                val notification = buildListenerNotification(statusText)
                startForeground(NOTIFICATION_ID, notification)
            }
        }

        return START_STICKY
    }

    override fun onDestroy() {
        Log.d(TAG, "MacroForegroundService onDestroy")
        isRunning = false
        isExecutingRoutine = false
        stopTelegramPoller()
        releaseLocks()
        if (instance == this) {
            instance = null
        }
        super.onDestroy()
    }

    private fun acquireLocks() {
        try {
            if (partialWakeLock == null) {
                val pm = getSystemService(Context.POWER_SERVICE) as? PowerManager
                partialWakeLock = pm?.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "PrivateAgent:BackgroundListenerWakeLock")
                partialWakeLock?.setReferenceCounted(false)
            }
            if (partialWakeLock?.isHeld == false) {
                partialWakeLock?.acquire()
                Log.d(TAG, "Acquired PARTIAL_WAKE_LOCK for background listener")
            }

            if (wifiLock == null) {
                val wm = applicationContext.getSystemService(Context.WIFI_SERVICE) as? WifiManager
                @Suppress("DEPRECATION")
                wifiLock = wm?.createWifiLock(WifiManager.WIFI_MODE_FULL_HIGH_PERF, "PrivateAgent:BackgroundWifiLock")
                wifiLock?.setReferenceCounted(false)
            }
            if (wifiLock?.isHeld == false) {
                wifiLock?.acquire()
                Log.d(TAG, "Acquired WifiLock for background listener")
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error acquiring locks: ${e.message}")
        }
    }

    private fun releaseLocks() {
        try {
            if (partialWakeLock?.isHeld == true) {
                partialWakeLock?.release()
                Log.d(TAG, "Released PARTIAL_WAKE_LOCK")
            }
            if (wifiLock?.isHeld == true) {
                wifiLock?.release()
                Log.d(TAG, "Released WifiLock")
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error releasing locks: ${e.message}")
        }
    }

    @Synchronized
    private fun startTelegramPoller() {
        val prefs = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
        val enabled = prefs.getBoolean("flutter.telegram_enabled", false)
        val token = prefs.getString("flutter.telegram_bot_token", "") ?: ""

        if (!enabled || token.isEmpty()) {
            Log.d(TAG, "Telegram poller not started: enabled=$enabled, tokenEmpty=${token.isEmpty()}")
            stopTelegramPoller()
            return
        }

        if (isPollingTelegram) return
        isPollingTelegram = true

        pollingThread = Thread({
            Log.d(TAG, "Native Telegram background poller thread started")
            while (isPollingTelegram) {
                try {
                    val currentToken = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
                        .getString("flutter.telegram_bot_token", "") ?: token
                    val isStillEnabled = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
                        .getBoolean("flutter.telegram_enabled", false)

                    if (!isStillEnabled || currentToken.isEmpty()) {
                        Log.d(TAG, "Telegram polling disabled or token removed. Stopping.")
                        break
                    }

                    pollTelegramUpdates(currentToken)
                } catch (e: Exception) {
                    Log.e(TAG, "Telegram polling cycle error: ${e.message}")
                    try { Thread.sleep(3000) } catch (_: InterruptedException) { break }
                }
            }
            isPollingTelegram = false
            Log.d(TAG, "Native Telegram background poller thread stopped")
        }, "TelegramPollerThread").apply {
            isDaemon = true
            start()
        }
    }

    @Synchronized
    private fun stopTelegramPoller() {
        isPollingTelegram = false
        pollingThread?.interrupt()
        pollingThread = null
    }

    private fun pollTelegramUpdates(token: String) {
        var connection: HttpURLConnection? = null
        try {
            val url = URL("https://api.telegram.org/bot$token/getUpdates")
            connection = (url.openConnection() as HttpURLConnection).apply {
                requestMethod = "POST"
                connectTimeout = 30000
                readTimeout = 35000
                doOutput = true
                setRequestProperty("Content-Type", "application/json")
            }

            val body = JSONObject().apply {
                if (lastUpdateId > 0) {
                    put("offset", lastUpdateId + 1)
                }
                put("timeout", 20)
                put("allowed_updates", JSONArray().put("message"))
            }.toString()

            connection.outputStream.use { os ->
                os.write(body.toByteArray(Charsets.UTF_8))
            }

            val responseCode = connection.responseCode
            if (responseCode == 200) {
                val responseText = connection.inputStream.bufferedReader().use { it.readText() }
                val json = JSONObject(responseText)
                if (json.optBoolean("ok", false)) {
                    val results = json.optJSONArray("result")
                    if (results != null && results.length() > 0) {
                        for (i in 0 until results.length()) {
                            val update = results.getJSONObject(i)
                            val updateId = update.optLong("update_id", 0)
                            if (updateId > lastUpdateId) {
                                lastUpdateId = updateId
                            }
                            val message = update.optJSONObject("message")
                            if (message != null) {
                                val text = message.optString("text", "")
                                val chat = message.optJSONObject("chat")
                                val chatId = chat?.optLong("id", 0)?.toString() ?: ""
                                if (text.isNotEmpty() && chatId.isNotEmpty()) {
                                    onIncomingTelegramMessage(chatId, text, token)
                                }
                            }
                        }
                    }
                }
            } else if (responseCode == 409) {
                Log.w(TAG, "Telegram 409 Conflict: waiting before retry...")
                Thread.sleep(5000)
            } else {
                Log.w(TAG, "Telegram getUpdates HTTP $responseCode")
                Thread.sleep(2000)
            }
        } catch (e: Exception) {
            if (isPollingTelegram) {
                Log.w(TAG, "Network issue during Telegram polling: ${e.message}")
                Thread.sleep(2000)
            }
        } finally {
            connection?.disconnect()
        }
    }

    private fun onIncomingTelegramMessage(chatId: String, text: String, token: String) {
        Log.d(TAG, "Incoming Telegram message: '$text' from chat $chatId")

        // Wake screen immediately so UI can be automated if necessary
        wakeScreenTemporarily(this)

        // Save last active chat ID in preferences
        getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            .edit()
            .putString("flutter.telegram_last_chat_id", chatId)
            .apply()

        // Handle emergency stop directly
        if (text.trim() == "/stop") {
            Log.d(TAG, "Telegram emergency stop requested")
            MacroWakeReceiver.releaseWakeLock()
            MacroWakeReceiver.onRoutineStopCallback?.invoke()
            Handler(Looper.getMainLooper()).post {
                MainActivity.channelSink?.invokeMethod("onRoutineStopped", null)
            }
            sendTelegramMessageDirectly(token, chatId, "🛑 Emergency stop signal received.")
            return
        }

        if (MainActivity.channelSink != null) {
            Log.d(TAG, "MainActivity channel is active. Forwarding to Flutter.")
            Handler(Looper.getMainLooper()).post {
                MainActivity.channelSink?.invokeMethod(
                    "onTelegramMessageReceived",
                    mapOf("chatId" to chatId, "text" to text)
                )
            }
        } else {
            Log.d(TAG, "MainActivity channel is null! Waking and launching MainActivity...")
            MainActivity.pendingTelegramMessage = mapOf("chatId" to chatId, "text" to text)
            val launchIntent = Intent(this, MainActivity::class.java).apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_REORDER_TO_FRONT)
                putExtra("telegram_chat_id", chatId)
                putExtra("telegram_text", text)
            }
            startActivity(launchIntent)
        }
    }

    private fun sendTelegramMessageDirectly(token: String, chatId: String, text: String) {
        Thread({
            var conn: HttpURLConnection? = null
            try {
                val url = URL("https://api.telegram.org/bot$token/sendMessage")
                conn = (url.openConnection() as HttpURLConnection).apply {
                    requestMethod = "POST"
                    connectTimeout = 15000
                    readTimeout = 15000
                    doOutput = true
                    setRequestProperty("Content-Type", "application/json")
                }
                val body = JSONObject().apply {
                    put("chat_id", chatId)
                    put("text", text)
                }.toString()
                conn.outputStream.use { it.write(body.toByteArray(Charsets.UTF_8)) }
                conn.responseCode
            } catch (e: Exception) {
                Log.e(TAG, "Failed to send direct telegram reply: ${e.message}")
            } finally {
                conn?.disconnect()
            }
        }, "TelegramSendDirectThread").start()
    }

    private fun buildListenerNotification(statusText: String): Notification {
        val openIntent = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        val openPendingIntent = PendingIntent.getActivity(
            this,
            1001,
            openIntent,
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE else PendingIntent.FLAG_UPDATE_CURRENT
        )

        val stopIntent = Intent(this, MacroWakeReceiver::class.java).apply {
            action = "${packageName}.STOP_BACKGROUND_SERVICE"
        }
        val stopPendingIntent = PendingIntent.getBroadcast(
            this,
            1002,
            stopIntent,
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE else PendingIntent.FLAG_UPDATE_CURRENT
        )

        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("PrivateAgent Active")
            .setContentText(statusText)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setOngoing(true)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setCategory(NotificationCompat.CATEGORY_SERVICE)
            .setContentIntent(openPendingIntent)
            .addAction(android.R.drawable.ic_menu_close_clear_cancel, "Stop Service", stopPendingIntent)
            .build()
    }

    private fun buildExecutionNotification(routineTitle: String): Notification {
        val stopIntent = Intent(this, MacroWakeReceiver::class.java).apply {
            action = "${packageName}.STOP_ROUTINE"
        }
        val stopPendingIntent = PendingIntent.getBroadcast(
            this,
            NOTIFICATION_ID,
            stopIntent,
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE else PendingIntent.FLAG_UPDATE_CURRENT
        )

        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("PrivateAgent Loop Active")
            .setContentText(routineTitle)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setOngoing(true)
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setCategory(NotificationCompat.CATEGORY_SERVICE)
            .addAction(android.R.drawable.ic_media_pause, "Emergency Stop", stopPendingIntent)
            .build()
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "PrivateAgent Background Service",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "Keeps PrivateAgent active in the background for Telegram remote control and autonomous routines."
                setShowBadge(false)
            }
            val manager = getSystemService(Context.NOTIFICATION_SERVICE) as? NotificationManager
            manager?.createNotificationChannel(channel)
        }
    }
}
