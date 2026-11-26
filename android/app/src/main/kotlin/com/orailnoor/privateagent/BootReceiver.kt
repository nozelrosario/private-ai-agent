package com.orailnoor.privateagent

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log

class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val action = intent.action ?: return
        Log.d("BootReceiver", "Received boot/package intent: $action")

        if (action == Intent.ACTION_BOOT_COMPLETED || action == Intent.ACTION_MY_PACKAGE_REPLACED) {
            val prefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            val bgEnabled = prefs.getBoolean("flutter.background_service_enabled", true)
            val telegramEnabled = prefs.getBoolean("flutter.telegram_enabled", false)

            if (bgEnabled || telegramEnabled) {
                Log.d("BootReceiver", "Auto-starting MacroForegroundService on device boot")
                MacroForegroundService.startListener(context, "Listening for Telegram commands & scheduled routines")
            }
        }
    }
}
