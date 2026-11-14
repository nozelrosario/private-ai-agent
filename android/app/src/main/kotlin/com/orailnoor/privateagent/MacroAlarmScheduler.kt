package com.orailnoor.privateagent

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import android.util.Log

object MacroAlarmScheduler {
    private const val TAG = "MacroAlarmScheduler"

    fun scheduleRoutineAlarm(context: Context, routineId: String, delaySeconds: Long) {
        val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as? AlarmManager ?: return
        val intent = Intent(context, MacroWakeReceiver::class.java).apply {
            action = "${context.packageName}.TRIGGER_ROUTINE"
            putExtra("routine_id", routineId)
        }

        val requestCode = routineId.hashCode()
        val flags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        } else {
            PendingIntent.FLAG_UPDATE_CURRENT
        }

        val pendingIntent = PendingIntent.getBroadcast(context, requestCode, intent, flags)
        val triggerAtMillis = System.currentTimeMillis() + (delaySeconds * 1000L)

        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                alarmManager.setExactAndAllowWhileIdle(
                    AlarmManager.RTC_WAKEUP,
                    triggerAtMillis,
                    pendingIntent
                )
            } else {
                alarmManager.setExact(
                    AlarmManager.RTC_WAKEUP,
                    triggerAtMillis,
                    pendingIntent
                )
            }
            Log.d(TAG, "Scheduled alarm for routine $routineId in $delaySeconds seconds ($triggerAtMillis)")
        } catch (e: Exception) {
            Log.e(TAG, "Error scheduling exact alarm: ${e.message}", e)
        }
    }

    fun cancelRoutineAlarm(context: Context, routineId: String) {
        val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as? AlarmManager ?: return
        val intent = Intent(context, MacroWakeReceiver::class.java).apply {
            action = "${context.packageName}.TRIGGER_ROUTINE"
            putExtra("routine_id", routineId)
        }

        val requestCode = routineId.hashCode()
        val flags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            PendingIntent.FLAG_NO_CREATE or PendingIntent.FLAG_IMMUTABLE
        } else {
            PendingIntent.FLAG_NO_CREATE
        }

        val pendingIntent = PendingIntent.getBroadcast(context, requestCode, intent, flags)
        if (pendingIntent != null) {
            alarmManager.cancel(pendingIntent)
            pendingIntent.cancel()
            Log.d(TAG, "Cancelled alarm for routine $routineId")
        }
    }
}
