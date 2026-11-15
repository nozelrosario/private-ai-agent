package com.orailnoor.privateagent

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.IBinder
import androidx.core.app.NotificationCompat

class MacroForegroundService : Service() {
    companion object {
        const val CHANNEL_ID = "privateagent_routine_fgs_channel"
        const val NOTIFICATION_ID = 2001

        const val ACTION_START_LISTENER = "START_LISTENER"
        const val ACTION_START_EXECUTION = "START_EXECUTION"
        const val ACTION_STOP_SERVICE = "STOP_SERVICE"

        var isRunning = false
            private set
        var isExecutingRoutine = false
            private set

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

        // Backward compatibility for existing callers
        fun start(context: Context, routineTitle: String) {
            startExecution(context, routineTitle)
        }

        fun stop(context: Context) {
            val intent = Intent(context, MacroForegroundService::class.java).apply {
                action = ACTION_STOP_SERVICE
            }
            context.stopService(intent)
        }

        private fun startServiceCompat(context: Context, intent: Intent) {
            try {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    context.startForegroundService(intent)
                } else {
                    context.startService(intent)
                }
            } catch (e: Exception) {
                android.util.Log.e("MacroForegroundService", "Failed to start service: ${e.message}")
            }
        }
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val action = intent?.action ?: ACTION_START_LISTENER
        createNotificationChannel()

        when (action) {
            ACTION_STOP_SERVICE -> {
                isRunning = false
                isExecutingRoutine = false
                stopForeground(true)
                stopSelf()
                return START_NOT_STICKY
            }

            ACTION_START_EXECUTION -> {
                isRunning = true
                isExecutingRoutine = true
                val title = intent?.getStringExtra("routine_title") ?: "Running Autonomous Routine..."
                val notification = buildExecutionNotification(title)
                startForeground(NOTIFICATION_ID, notification)
            }

            else -> { // ACTION_START_LISTENER
                isRunning = true
                isExecutingRoutine = false
                val statusText = intent?.getStringExtra("status_text") ?: "Listening for Telegram commands & scheduled routines"
                val notification = buildListenerNotification(statusText)
                startForeground(NOTIFICATION_ID, notification)
            }
        }

        return START_STICKY
    }

    override fun onDestroy() {
        isRunning = false
        isExecutingRoutine = false
        super.onDestroy()
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
