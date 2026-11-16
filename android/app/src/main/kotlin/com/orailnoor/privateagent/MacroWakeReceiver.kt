package com.orailnoor.privateagent

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.PowerManager
import android.util.Log

class MacroWakeReceiver : BroadcastReceiver() {
    companion object {
        private const val TAG = "MacroWakeReceiver"
        var wakeLock: PowerManager.WakeLock? = null
        var onRoutineTriggerCallback: ((String) -> Unit)? = null
        var onRoutineStopCallback: (() -> Unit)? = null

        fun acquireWakeLock(context: Context, timeoutMs: Long = 180_000L) {
            try {
                if (wakeLock == null || wakeLock?.isHeld == false) {
                    val pm = context.getSystemService(Context.POWER_SERVICE) as? PowerManager
                    wakeLock = pm?.newWakeLock(
                        PowerManager.PARTIAL_WAKE_LOCK or PowerManager.ACQUIRE_CAUSES_WAKEUP,
                        "PrivateAgent:RoutineExecutionLock"
                    )
                    wakeLock?.setReferenceCounted(false)
                }
                wakeLock?.acquire(timeoutMs)
                Log.d(TAG, "WakeLock acquired for routine execution (${timeoutMs}ms)")
            } catch (e: Exception) {
                Log.e(TAG, "Error acquiring wake lock: ${e.message}")
            }
        }

        fun releaseWakeLock() {
            try {
                if (wakeLock?.isHeld == true) {
                    wakeLock?.release()
                    Log.d(TAG, "WakeLock released")
                }
            } catch (e: Exception) {
                Log.e(TAG, "Error releasing wake lock: ${e.message}")
            }
        }
    }

    override fun onReceive(context: Context, intent: Intent) {
        val action = intent.action ?: return
        Log.d(TAG, "Received action: $action")

        when {
            action.endsWith(".TRIGGER_ROUTINE") -> {
                val routineId = intent.getStringExtra("routine_id") ?: ""
                Log.d(TAG, "Triggering routine: $routineId")

                // Check if user is actively interacting with the phone
                if (AgentAccessibilityService.isUserActivelyInteracting(30_000L)) {
                    Log.d(TAG, "User actively using phone. Postponing routine $routineId by 5 minutes")
                    MacroAlarmScheduler.scheduleRoutineAlarm(context, routineId, 300L)
                    return
                }

                // Acquire WakeLock
                acquireWakeLock(context)

                // Wake screen
                MacroForegroundService.wakeScreenTemporarily(context, 10000L)

                // Start Foreground Service in execution mode
                MacroForegroundService.startExecution(context, "Executing scheduled routine...")

                // Always bring MainActivity to front so it shows over keyguard and holds screen on
                val launchIntent = Intent(context, MainActivity::class.java).apply {
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_REORDER_TO_FRONT)
                    putExtra("trigger_routine_id", routineId)
                }
                context.startActivity(launchIntent)

                // Notify Flutter
                onRoutineTriggerCallback?.invoke(routineId)
                MainActivity.channelSink?.invokeMethod("onRoutineTriggered", mapOf("routine_id" to routineId))
            }

            action.endsWith(".STOP_ROUTINE") -> {
                Log.d(TAG, "Stop routine requested by user")
                releaseWakeLock()
                onRoutineStopCallback?.invoke()
                MainActivity.channelSink?.invokeMethod("onRoutineStopped", null)
                MacroForegroundService.startListener(context)
            }

            action.endsWith(".STOP_BACKGROUND_SERVICE") -> {
                Log.d(TAG, "Stop background listener requested by user")
                releaseWakeLock()
                MacroForegroundService.stop(context)
                MainActivity.channelSink?.invokeMethod("onBackgroundServiceStopped", null)
            }
        }
    }
}
