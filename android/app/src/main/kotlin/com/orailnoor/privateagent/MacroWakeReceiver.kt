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

                // Start Foreground Service to display ongoing notification
                MacroForegroundService.start(context, "Running Autonomous Routine...")

                // Notify Flutter
                onRoutineTriggerCallback?.invoke(routineId)
                MainActivity.channelSink?.invokeMethod("onRoutineTriggered", mapOf("routine_id" to routineId))
            }

            action.endsWith(".STOP_ROUTINE") -> {
                Log.d(TAG, "Stop routine requested by user")
                MacroForegroundService.stop(context)
                releaseWakeLock()
                onRoutineStopCallback?.invoke()
                MainActivity.channelSink?.invokeMethod("onRoutineStopped", null)
            }
        }
    }
}
