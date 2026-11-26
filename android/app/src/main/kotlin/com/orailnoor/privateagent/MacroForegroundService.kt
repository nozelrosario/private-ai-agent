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
        const val EXECUTION_CHANNEL_ID = "privateagent_execution_channel"
        const val NOTIFICATION_ID = 2001

        const val ACTION_START_LISTENER = "START_LISTENER"
        const val ACTION_START_EXECUTION = "START_EXECUTION"
        const val ACTION_STOP_SERVICE = "STOP_SERVICE"

        var isRunning = false
            private set
        var isExecutingRoutine = false
            private set

        private var instance: MacroForegroundService? = null

        fun startListener(
            context: Context,
            statusText: String = "Listening for Telegram commands & scheduled routines",
            botToken: String? = null,
            telegramEnabled: Boolean = false
        ) {
            val intent = Intent(context, MacroForegroundService::class.java).apply {
                action = ACTION_START_LISTENER
                putExtra("status_text", statusText)
                if (botToken != null) putExtra("telegram_bot_token", botToken)
                putExtra("telegram_enabled", telegramEnabled)
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

        fun reloadTelegramPoller(botToken: String? = null, telegramEnabled: Boolean? = null) {
            instance?.let { service ->
                if (botToken != null || telegramEnabled != null) {
                    val prefs = service.getSharedPreferences("PrivateAgentPrefs", Context.MODE_PRIVATE).edit()
                    botToken?.let { prefs.putString("telegram_bot_token", it) }
                    telegramEnabled?.let { prefs.putBoolean("telegram_enabled", it) }
                    prefs.apply()
                }
                service.stopTelegramPoller()
                service.startTelegramPoller()
            }
        }

        fun wakeScreenTemporarily(context: Context, durationMs: Long = 10000L) {
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
    private var screenBrightWakeLock: PowerManager.WakeLock? = null

    private var isPollingTelegram = false
    private var pollingThread: Thread? = null
    private var lastUpdateId: Long = 0
    private var lastDispatchedUpdateId: Long = 0

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        instance = this
        lastDispatchedUpdateId = getSharedPreferences("PrivateAgentPrefs", Context.MODE_PRIVATE)
            .getLong("last_dispatched_update_id", 0L)
        if (lastDispatchedUpdateId > lastUpdateId) {
            lastUpdateId = lastDispatchedUpdateId
        }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val action = intent?.action ?: ACTION_START_LISTENER
        createNotificationChannel()

        when (action) {
            ACTION_STOP_SERVICE -> {
                Log.d(TAG, "Stopping service via ACTION_STOP_SERVICE")
                isRunning = false
                isExecutingRoutine = false
                MainActivity.currentActivity?.applyKeepScreenOn(false)
                releaseScreenBrightLock()
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
                acquireScreenBrightLock()
                MainActivity.currentActivity?.applyKeepScreenOn(true)
                val title = intent?.getStringExtra("routine_title") ?: "Running Autonomous Routine..."
                val notification = buildExecutionNotification(title)
                startForeground(NOTIFICATION_ID, notification)
            }

            else -> { // ACTION_START_LISTENER
                Log.d(TAG, "Starting listener mode")
                isRunning = true
                isExecutingRoutine = false
                MainActivity.currentActivity?.applyKeepScreenOn(false)
                releaseScreenBrightLock()
                acquireLocks()

                // Save credentials passed in intent if present
                val tokenExtra = intent?.getStringExtra("telegram_bot_token")
                val enabledExtra = intent?.getBooleanExtra("telegram_enabled", false) ?: false
                if (!tokenExtra.isNullOrEmpty()) {
                    getSharedPreferences("PrivateAgentPrefs", Context.MODE_PRIVATE)
                        .edit()
                        .putString("telegram_bot_token", tokenExtra)
                        .putBoolean("telegram_enabled", enabledExtra)
                        .apply()
                }

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
        releaseScreenBrightLock()
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

    private fun acquireScreenBrightLock() {
        try {
            if (screenBrightWakeLock == null) {
                val pm = getSystemService(Context.POWER_SERVICE) as? PowerManager
                @Suppress("DEPRECATION")
                screenBrightWakeLock = pm?.newWakeLock(
                    PowerManager.SCREEN_BRIGHT_WAKE_LOCK or PowerManager.ACQUIRE_CAUSES_WAKEUP,
                    "PrivateAgent:ExecutionScreenBrightLock"
                )
                screenBrightWakeLock?.setReferenceCounted(false)
            }
            if (screenBrightWakeLock?.isHeld == false) {
                // Keep screen bright for up to 10 minutes during execution
                screenBrightWakeLock?.acquire(600_000L)
                Log.d(TAG, "Acquired SCREEN_BRIGHT_WAKE_LOCK for routine execution")
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error acquiring screen bright lock: ${e.message}")
        }
    }

    private fun releaseScreenBrightLock() {
        try {
            if (screenBrightWakeLock?.isHeld == true) {
                screenBrightWakeLock?.release()
                Log.d(TAG, "Released SCREEN_BRIGHT_WAKE_LOCK")
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error releasing screen bright lock: ${e.message}")
        }
    }

    @Synchronized
    private fun startTelegramPoller() {
        val ownPrefs = getSharedPreferences("PrivateAgentPrefs", Context.MODE_PRIVATE)
        val flutterPrefs = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)

        val enabled = ownPrefs.getBoolean(
            "telegram_enabled",
            flutterPrefs.getBoolean("flutter.telegram_enabled", false)
        )
        val token = ownPrefs.getString("telegram_bot_token", null)
            ?: flutterPrefs.getString("flutter.telegram_bot_token", "") ?: ""

        if (!enabled || token.isEmpty()) {
            Log.d(TAG, "Telegram poller not started: enabled=$enabled, tokenEmpty=${token.isEmpty()}")
            stopTelegramPoller()
            return
        }

        val lastToken = ownPrefs.getString("last_poller_token", null)
        if (lastToken != null && lastToken != token) {
            lastUpdateId = 0L
            lastDispatchedUpdateId = 0L
            ownPrefs.edit().putLong("last_dispatched_update_id", 0L).apply()
        }
        if (lastToken != token) {
            ownPrefs.edit().putString("last_poller_token", token).apply()
        }

        if (isPollingTelegram) return
        isPollingTelegram = true

        pollingThread = Thread({
            Log.d(TAG, "Native Telegram background poller thread started")
            while (isPollingTelegram) {
                try {
                    val currentPrefs = getSharedPreferences("PrivateAgentPrefs", Context.MODE_PRIVATE)
                    val flPrefs = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)

                    val currentToken = currentPrefs.getString("telegram_bot_token", null)
                        ?: flPrefs.getString("flutter.telegram_bot_token", "") ?: token
                    val isStillEnabled = currentPrefs.getBoolean(
                        "telegram_enabled",
                        flPrefs.getBoolean("flutter.telegram_enabled", false)
                    )

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
                                    onIncomingTelegramMessage(chatId, text, token, updateId)
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

    private fun onIncomingTelegramMessage(chatId: String, text: String, token: String, updateId: Long) {
        if (updateId > 0 && updateId <= lastDispatchedUpdateId) {
            Log.d(TAG, "Skipping duplicate updateId=$updateId")
            return
        }
        if (updateId > lastDispatchedUpdateId) {
            lastDispatchedUpdateId = updateId
            getSharedPreferences("PrivateAgentPrefs", Context.MODE_PRIVATE)
                .edit()
                .putLong("last_dispatched_update_id", lastDispatchedUpdateId)
                .apply()
        }

        Log.d(TAG, "Incoming Telegram message (updateId=$updateId): '$text' from chat $chatId")

        // Save last active chat ID in preferences
        getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            .edit()
            .putString("flutter.telegram_last_chat_id", chatId)
            .apply()
        getSharedPreferences("PrivateAgentPrefs", Context.MODE_PRIVATE)
            .edit()
            .putString("telegram_last_chat_id", chatId)
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

        // Immediately transition into high-priority Execution Mode so screen, CPU, and Wi-Fi stay
        // awake across lockscreen transitions and Android 10-16 honors full-screen wakeups.
        isRunning = true
        isExecutingRoutine = true
        acquireLocks()
        acquireScreenBrightLock()
        val preview = if (text.length > 40) "${text.take(40)}..." else text
        val execNotification = buildExecutionNotification("Telegram: $preview")
        startForeground(NOTIFICATION_ID, execNotification)

        // Dispatch via persistent queue/channel bridge with ACK guarantee
        val msgId = if (updateId > 0) "${updateId}_${chatId}" else "${System.currentTimeMillis()}_${chatId}"
        MainActivity.dispatchTelegramMessage(this, chatId, text, msgId)
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
        val openIntent = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        val openPendingIntent = PendingIntent.getActivity(
            this,
            1003,
            openIntent,
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE else PendingIntent.FLAG_UPDATE_CURRENT
        )

        val stopIntent = Intent(this, MacroWakeReceiver::class.java).apply {
            action = "${packageName}.STOP_ROUTINE"
        }
        val stopPendingIntent = PendingIntent.getBroadcast(
            this,
            NOTIFICATION_ID,
            stopIntent,
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE else PendingIntent.FLAG_UPDATE_CURRENT
        )

        return NotificationCompat.Builder(this, EXECUTION_CHANNEL_ID)
            .setContentTitle("PrivateAgent Loop Active")
            .setContentText(routineTitle)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setOngoing(true)
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setCategory(NotificationCompat.CATEGORY_ALARM)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setContentIntent(openPendingIntent)
            .setFullScreenIntent(openPendingIntent, true)
            .addAction(android.R.drawable.ic_media_pause, "Emergency Stop", stopPendingIntent)
            .build()
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val listenerChannel = NotificationChannel(
                CHANNEL_ID,
                "PrivateAgent Background Service",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "Keeps PrivateAgent active in the background for Telegram remote control and autonomous routines."
                setShowBadge(false)
            }

            // Dedicated HIGH-importance channel required on Android 8-16 for setFullScreenIntent wakeups
            val executionChannel = NotificationChannel(
                EXECUTION_CHANNEL_ID,
                "PrivateAgent Task Wakeup & Execution",
                NotificationManager.IMPORTANCE_HIGH
            ).apply {
                description = "Wakes the screen over the lockscreen when an autonomous routine or remote Telegram task starts."
                lockscreenVisibility = Notification.VISIBILITY_PUBLIC
                setSound(null, null)
                enableVibration(false)
                setShowBadge(true)
            }

            val manager = getSystemService(Context.NOTIFICATION_SERVICE) as? NotificationManager
            manager?.createNotificationChannel(listenerChannel)
            manager?.createNotificationChannel(executionChannel)
        }
    }
}
