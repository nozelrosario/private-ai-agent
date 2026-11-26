package com.orailnoor.privateagent

import android.content.Context
import android.content.Intent
import android.app.KeyguardManager
import android.os.PowerManager
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.EventChannel
import android.graphics.PixelFormat
import android.graphics.Color
import android.view.Gravity
import android.view.WindowManager
import android.view.View
import android.widget.Button
import android.net.Uri

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.privateagent/accessibility"
    private val EVENT_CHANNEL = "com.privateagent/accessibility_events"
    private var eventSink: EventChannel.EventSink? = null
    private var overlayView: View? = null

    override fun onCreate(savedInstanceState: android.os.Bundle?) {
        handleLockscreenFlags(keepAwake = hasPendingTriggers(this, intent))
        super.onCreate(savedInstanceState)
        currentActivity = this
        handleIntent(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        currentActivity = this
        setIntent(intent)
        handleLockscreenFlags(keepAwake = hasPendingTriggers(this, intent))
        handleIntent(intent)
    }

    override fun onResume() {
        super.onResume()
        currentActivity = this
        if (hasPendingTriggers(this, intent)) {
            handleLockscreenFlags(keepAwake = true)
        }
    }

    private fun handleLockscreenFlags(keepAwake: Boolean = false) {
        if (keepAwake) {
            window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        }
        if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.O_MR1) {
            setShowWhenLocked(true)
            setTurnScreenOn(true)
        } else {
            @Suppress("DEPRECATION")
            window.addFlags(
                WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
                WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON
            )
        }
    }

    fun applyShowWhenLocked(enabled: Boolean) {
        runOnUiThread {
            if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.O_MR1) {
                setShowWhenLocked(enabled)
            } else if (enabled) {
                @Suppress("DEPRECATION")
                window.addFlags(WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED)
            } else {
                @Suppress("DEPRECATION")
                window.clearFlags(WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED)
            }
        }
    }

    fun applyKeepScreenOn(enabled: Boolean) {
        runOnUiThread {
            if (enabled) {
                window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
            } else {
                window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
            }
        }
    }

    fun dismissKeyguardWithCallback(onComplete: (Boolean) -> Unit) {
        runOnUiThread {
            if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.O) {
                val km = getSystemService(Context.KEYGUARD_SERVICE) as? KeyguardManager
                if (km == null || !km.isKeyguardLocked) {
                    onComplete(true)
                    return@runOnUiThread
                }
                var finished = false
                val handler = android.os.Handler(android.os.Looper.getMainLooper())
                val finishOnce = { success: Boolean ->
                    if (!finished) {
                        finished = true
                        handler.removeCallbacksAndMessages(null)
                        onComplete(success)
                    }
                }
                handler.postDelayed({ finishOnce(!km.isKeyguardLocked) }, 2500L)
                try {
                    km.requestDismissKeyguard(this, object : KeyguardManager.KeyguardDismissCallback() {
                        override fun onDismissSucceeded() {
                            android.util.Log.d("MainActivity", "Keyguard dismiss succeeded")
                            finishOnce(true)
                        }
                        override fun onDismissError() {
                            android.util.Log.e("MainActivity", "Keyguard dismiss error")
                            finishOnce(false)
                        }
                        override fun onDismissCancelled() {
                            android.util.Log.d("MainActivity", "Keyguard dismiss cancelled")
                            finishOnce(false)
                        }
                    })
                } catch (e: Exception) {
                    android.util.Log.e("MainActivity", "requestDismissKeyguard failed: ${e.message}")
                    finishOnce(false)
                }
            } else {
                onComplete(true)
            }
        }
    }

    @Suppress("DEPRECATION")
    override fun onBackPressed() {
        moveTaskToBack(true)
    }

    private fun handleIntent(intent: Intent?) {
        val routineId = intent?.getStringExtra("trigger_routine_id")
        if (!routineId.isNullOrEmpty()) {
            deliverOrQueueRoutine(routineId)
        }

        val tgText = intent?.getStringExtra("telegram_text")
        val tgChatId = intent?.getStringExtra("telegram_chat_id")
        val tgMsgId = intent?.getStringExtra("telegram_msg_id") ?: ""
        if (!tgText.isNullOrEmpty() && !tgChatId.isNullOrEmpty()) {
            deliverOrQueueTelegram(tgChatId, tgText, tgMsgId)
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        currentActivity = this

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, EVENT_CHANNEL).setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    eventSink = events
                    AgentAccessibilityService.eventListener = { eventMap ->
                        runOnUiThread {
                            eventSink?.success(eventMap)
                        }
                    }
                }

                override fun onCancel(arguments: Any?) {
                    eventSink = null
                    AgentAccessibilityService.eventListener = null
                }
            }
        )

        registerAccessibilityChannel(flutterEngine, this)
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        if (activeEngine == flutterEngine) {
            isDartReady = false
            channelSink = null
            activeEngine = null
        }
        super.cleanUpFlutterEngine(flutterEngine)
    }

    override fun onDestroy() {
        if (currentActivity == this) {
            currentActivity = null
            isDartReady = false
            channelSink = null
        }
        super.onDestroy()
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == FILE_PICKER_REQUEST_CODE) {
            val pickerResult = pendingFilePickerResult
            pendingFilePickerResult = null
            if (resultCode == RESULT_OK && data?.data != null) {
                try {
                    contentResolver.openInputStream(data.data!!)?.use { inputStream ->
                        val content = inputStream.bufferedReader().use { it.readText() }
                        pickerResult?.success(content)
                    } ?: run {
                        pickerResult?.error("READ_ERROR", "Could not open selected file", null)
                    }
                } catch (e: Exception) {
                    pickerResult?.error("READ_ERROR", e.message, null)
                }
            } else {
                pickerResult?.success(null)
            }
        }
    }

    companion object {
        var channelSink: MethodChannel? = null
        var currentActivity: MainActivity? = null
        var pendingFilePickerResult: MethodChannel.Result? = null
        @Volatile
        var isDartReady: Boolean = false
        private var activeEngine: FlutterEngine? = null
        private val pendingRoutineIds = java.util.Collections.synchronizedList(mutableListOf<String>())
        private val pendingTelegramMessages = java.util.Collections.synchronizedList(mutableListOf<Map<String, String>>())
        private val seenTelegramMsgIds = java.util.Collections.synchronizedSet(mutableSetOf<String>())
        private const val PREFS_NAME = "PrivateAgentPrefs"
        private const val KEY_TELEGRAM_QUEUE = "pending_telegram_queue"
        private const val KEY_ROUTINE_QUEUE = "pending_routine_queue"
        const val FILE_PICKER_REQUEST_CODE = 4123

        fun hasPendingTriggers(context: android.content.Context, intent: Intent?): Boolean {
            loadPersistedQueues(context)
            val hasIntentTrigger = !(intent?.getStringExtra("telegram_text").isNullOrEmpty()) ||
                !(intent?.getStringExtra("trigger_routine_id").isNullOrEmpty())
            return hasIntentTrigger ||
                synchronized(pendingTelegramMessages) { pendingTelegramMessages.isNotEmpty() } ||
                synchronized(pendingRoutineIds) { pendingRoutineIds.isNotEmpty() }
        }

        private fun persistTelegramQueue(context: android.content.Context) {
            try {
                val arr = org.json.JSONArray()
                synchronized(pendingTelegramMessages) {
                    for (m in pendingTelegramMessages) {
                        val obj = org.json.JSONObject().apply {
                            put("chatId", m["chatId"] ?: "")
                            put("text", m["text"] ?: "")
                            put("messageId", m["messageId"] ?: "")
                        }
                        arr.put(obj)
                    }
                }
                context.applicationContext.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
                    .edit()
                    .putString(KEY_TELEGRAM_QUEUE, arr.toString())
                    .commit()
            } catch (e: Exception) {
                android.util.Log.e("MainActivity", "Failed to persist telegram queue: ${e.message}")
            }
        }

        private fun persistRoutineQueue(context: android.content.Context) {
            try {
                val arr = org.json.JSONArray()
                synchronized(pendingRoutineIds) {
                    for (id in pendingRoutineIds) {
                        arr.put(id)
                    }
                }
                context.applicationContext.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
                    .edit()
                    .putString(KEY_ROUTINE_QUEUE, arr.toString())
                    .commit()
            } catch (e: Exception) {
                android.util.Log.e("MainActivity", "Failed to persist routine queue: ${e.message}")
            }
        }

        private fun loadPersistedQueues(context: android.content.Context) {
            try {
                val prefs = context.applicationContext.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
                val tgJson = prefs.getString(KEY_TELEGRAM_QUEUE, null)
                if (!tgJson.isNullOrEmpty()) {
                    val arr = org.json.JSONArray(tgJson)
                    synchronized(pendingTelegramMessages) {
                        for (i in 0 until arr.length()) {
                            val obj = arr.optJSONObject(i) ?: continue
                            val cId = obj.optString("chatId", "")
                            val txt = obj.optString("text", "")
                            val mId = obj.optString("messageId", "")
                            if (cId.isNotEmpty() && txt.isNotEmpty()) {
                                val exists = pendingTelegramMessages.any { it["messageId"] == mId && mId.isNotEmpty() }
                                if (!exists && (mId.isEmpty() || !seenTelegramMsgIds.contains(mId))) {
                                    pendingTelegramMessages.add(mapOf("chatId" to cId, "text" to txt, "messageId" to mId))
                                }
                            }
                        }
                    }
                }
                val rJson = prefs.getString(KEY_ROUTINE_QUEUE, null)
                if (!rJson.isNullOrEmpty()) {
                    val arr = org.json.JSONArray(rJson)
                    synchronized(pendingRoutineIds) {
                        for (i in 0 until arr.length()) {
                            val id = arr.optString(i, "")
                            if (id.isNotEmpty() && !pendingRoutineIds.contains(id)) {
                                pendingRoutineIds.add(id)
                            }
                        }
                    }
                }
            } catch (e: Exception) {
                android.util.Log.e("MainActivity", "Failed to load persisted queues: ${e.message}")
            }
        }

        private fun removePendingTelegramMessage(context: android.content.Context, messageId: String) {
            synchronized(pendingTelegramMessages) {
                if (messageId.isNotEmpty()) {
                    pendingTelegramMessages.removeAll { it["messageId"] == messageId }
                } else if (pendingTelegramMessages.isNotEmpty()) {
                    pendingTelegramMessages.removeAt(0)
                }
            }
            persistTelegramQueue(context)
        }

        private fun removePendingRoutineId(context: android.content.Context, routineId: String) {
            synchronized(pendingRoutineIds) {
                pendingRoutineIds.removeAll { it == routineId }
            }
            persistRoutineQueue(context)
        }

        fun dispatchTelegramMessage(context: android.content.Context, chatId: String, text: String, messageId: String) {
            val appCtx = context.applicationContext
            val msgMap = mapOf("chatId" to chatId, "text" to text, "messageId" to messageId)
            val alreadySeen = if (messageId.isNotEmpty()) !seenTelegramMsgIds.add(messageId) else false
            if (alreadySeen) {
                android.util.Log.d("MainActivity", "Skipping duplicate Telegram messageId=$messageId")
                return
            }

            // Always persist BEFORE attempting live push so freeze/kill can never lose the trigger
            synchronized(pendingTelegramMessages) {
                pendingTelegramMessages.add(msgMap)
            }
            persistTelegramQueue(appCtx)

            val launchIntent = Intent(appCtx, MainActivity::class.java).apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_REORDER_TO_FRONT)
                putExtra("telegram_chat_id", chatId)
                putExtra("telegram_text", text)
                putExtra("telegram_msg_id", messageId)
            }
            try {
                appCtx.startActivity(launchIntent)
            } catch (e: Exception) {
                android.util.Log.e("MainActivity", "startActivity for Telegram failed: ${e.message}")
            }

            if (isDartReady && channelSink != null && currentActivity != null) {
                android.util.Log.d("MainActivity", "Dart ready; pushing onTelegramMessageReceived with ACK")
                currentActivity?.applyKeepScreenOn(true)
                android.os.Handler(android.os.Looper.getMainLooper()).post {
                    if (isDartReady && channelSink != null) {
                        channelSink?.invokeMethod("onTelegramMessageReceived", msgMap, object : MethodChannel.Result {
                            override fun success(res: Any?) {
                                removePendingTelegramMessage(appCtx, messageId)
                            }
                            override fun error(code: String, msg: String?, details: Any?) {
                                android.util.Log.w("MainActivity", "Dart ACK error for telegram $messageId: $msg")
                            }
                            override fun notImplemented() {
                                android.util.Log.w("MainActivity", "Dart handler notImplemented for telegram $messageId")
                            }
                        })
                    }
                }
            } else {
                android.util.Log.d("MainActivity", "Dart not ready (isDartReady=$isDartReady); persisted in queue for startup drain")
            }
        }

        fun dispatchRoutineTrigger(context: android.content.Context, routineId: String) {
            val appCtx = context.applicationContext
            synchronized(pendingRoutineIds) {
                if (!pendingRoutineIds.contains(routineId)) {
                    pendingRoutineIds.add(routineId)
                }
            }
            persistRoutineQueue(appCtx)

            val launchIntent = Intent(appCtx, MainActivity::class.java).apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_REORDER_TO_FRONT)
                putExtra("trigger_routine_id", routineId)
            }
            try {
                appCtx.startActivity(launchIntent)
            } catch (e: Exception) {
                android.util.Log.e("MainActivity", "startActivity for routine failed: ${e.message}")
            }

            if (isDartReady && channelSink != null && currentActivity != null) {
                android.util.Log.d("MainActivity", "Dart ready; pushing onRoutineTriggered with ACK")
                currentActivity?.applyKeepScreenOn(true)
                android.os.Handler(android.os.Looper.getMainLooper()).post {
                    if (isDartReady && channelSink != null) {
                        channelSink?.invokeMethod("onRoutineTriggered", mapOf("routine_id" to routineId), object : MethodChannel.Result {
                            override fun success(res: Any?) {
                                removePendingRoutineId(appCtx, routineId)
                            }
                            override fun error(code: String, msg: String?, details: Any?) {
                                android.util.Log.w("MainActivity", "Dart ACK error for routine $routineId: $msg")
                            }
                            override fun notImplemented() {
                                android.util.Log.w("MainActivity", "Dart handler notImplemented for routine $routineId")
                            }
                        })
                    }
                }
            } else {
                android.util.Log.d("MainActivity", "Dart not ready; persisted routine $routineId for startup drain")
            }
        }

        private fun deliverOrQueueRoutine(routineId: String) {
            val appCtx = currentActivity?.applicationContext
            if (appCtx != null) {
                synchronized(pendingRoutineIds) {
                    if (!pendingRoutineIds.contains(routineId)) {
                        pendingRoutineIds.add(routineId)
                    }
                }
                persistRoutineQueue(appCtx)
            }
            if (isDartReady && channelSink != null && appCtx != null) {
                channelSink?.invokeMethod("onRoutineTriggered", mapOf("routine_id" to routineId), object : MethodChannel.Result {
                    override fun success(res: Any?) {
                        removePendingRoutineId(appCtx, routineId)
                    }
                    override fun error(code: String, msg: String?, details: Any?) {}
                    override fun notImplemented() {}
                })
            }
        }

        private fun deliverOrQueueTelegram(chatId: String, text: String, messageId: String) {
            if (messageId.isNotEmpty() && !seenTelegramMsgIds.add(messageId)) {
                return
            }
            val msgMap = mapOf("chatId" to chatId, "text" to text, "messageId" to messageId)
            val appCtx = currentActivity?.applicationContext
            if (appCtx != null) {
                synchronized(pendingTelegramMessages) {
                    pendingTelegramMessages.add(msgMap)
                }
                persistTelegramQueue(appCtx)
            }
            if (isDartReady && channelSink != null && appCtx != null) {
                channelSink?.invokeMethod("onTelegramMessageReceived", msgMap, object : MethodChannel.Result {
                    override fun success(res: Any?) {
                        removePendingTelegramMessage(appCtx, messageId)
                    }
                    override fun error(code: String, msg: String?, details: Any?) {}
                    override fun notImplemented() {}
                })
            }
        }

        fun registerAccessibilityChannel(flutterEngine: FlutterEngine, context: android.content.Context) {
            val channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.privateagent/accessibility")
            channelSink = channel
            activeEngine = flutterEngine
            isDartReady = false

            channel.setMethodCallHandler { call, result ->
                    android.util.Log.d("PrivateAgentKotlin", "Received method call: ${call.method}")
                    when (call.method) {
                        "ping" -> result.success(true)

                        "logToNative" -> {
                            val msg = call.argument<String>("message") ?: ""
                            android.util.Log.d("PrivateAgentDart", msg)
                            result.success(true)
                        }

                        "isServiceRunning" -> {
                            result.success(AgentAccessibilityService.isRunning())
                        }

                        "checkOverlayPermission" -> {
                            result.success(Settings.canDrawOverlays(context))
                        }

                        "requestOverlayPermission" -> {
                            val intent = Intent(Settings.ACTION_MANAGE_OVERLAY_PERMISSION, Uri.parse("package:${context.packageName}"))
                            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            context.startActivity(intent)
                            result.success(true)
                        }

                        "showMacroOverlay" -> {
                            // Macro overlay requires an Activity context, so we just ignore or return error if called from background
                            result.error("NOT_SUPPORTED", "Macro overlay not supported from background", null)
                        }

                        "hideMacroOverlay" -> {
                            result.success(true)
                        }

                        "openAccessibilitySettings" -> {
                            val intent = Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS)
                            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            context.startActivity(intent)
                            result.success(true)
                        }

                        "dumpScreen" -> {
                            val service = AgentAccessibilityService.instance
                            if (service == null) {
                                result.error("SERVICE_NOT_RUNNING", "Accessibility service is not running", null)
                            } else {
                                val nodes = service.dumpScreen()
                                result.success(nodes)
                            }
                        }

                        "takeScreenshot" -> {
                            val service = AgentAccessibilityService.instance
                            if (service == null) {
                                result.error("SERVICE_NOT_RUNNING", "Accessibility service is not running", null)
                            } else {
                                if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.R) {
                                    service.takeScreenshot { base64 ->
                                        if (base64 != null) {
                                            result.success(base64)
                                        } else {
                                            result.error("SCREENSHOT_FAILED", "Failed to capture screenshot", null)
                                        }
                                    }
                                } else {
                                    result.error("UNSUPPORTED_VERSION", "Screenshot requires Android 11 (API 30) or higher", null)
                                }
                            }
                        }

                        "clickByText" -> {
                            val text = call.argument<String>("text") ?: ""
                            val service = AgentAccessibilityService.instance
                            if (service == null) {
                                result.error("SERVICE_NOT_RUNNING", "Accessibility service is not running", null)
                            } else {
                                result.success(service.clickByText(text))
                            }
                        }

                        "clickAt" -> {
                            val x = call.argument<Double>("x")?.toFloat() ?: 0f
                            val y = call.argument<Double>("y")?.toFloat() ?: 0f
                            val service = AgentAccessibilityService.instance
                            if (service == null) {
                                result.error("SERVICE_NOT_RUNNING", "Accessibility service is not running", null)
                            } else {
                                result.success(service.clickAtCoordinates(x, y))
                            }
                        }

                        "typeText" -> {
                            val text = call.argument<String>("text") ?: ""
                            val hint = call.argument<String>("fieldHint")
                            val service = AgentAccessibilityService.instance
                            if (service == null) {
                                result.error("SERVICE_NOT_RUNNING", "Accessibility service is not running", null)
                            } else {
                                result.success(service.typeText(text, hint))
                            }
                        }

                        "pressEnter" -> {
                            val service = AgentAccessibilityService.instance
                            if (service == null) {
                                result.error("SERVICE_NOT_RUNNING", "Accessibility service is not running", null)
                            } else {
                                result.success(service.pressEnter())
                            }
                        }

                        "scroll" -> {
                            val direction = call.argument<String>("direction") ?: "down"
                            val target = call.argument<String>("target")
                            val service = AgentAccessibilityService.instance
                            if (service == null) {
                                result.error("SERVICE_NOT_RUNNING", "Accessibility service is not running", null)
                            } else {
                                result.success(service.scroll(direction, target))
                            }
                        }

                        "showToast" -> {
                            val message = call.argument<String>("message") ?: ""
                            android.widget.Toast.makeText(context, message, android.widget.Toast.LENGTH_SHORT).show()
                            result.success(true)
                        }

                        "swipe" -> {
                            val startX = call.argument<Double>("startX")?.toFloat() ?: 0f
                            val startY = call.argument<Double>("startY")?.toFloat() ?: 0f
                            val endX = call.argument<Double>("endX")?.toFloat() ?: 0f
                            val endY = call.argument<Double>("endY")?.toFloat() ?: 0f
                            val service = AgentAccessibilityService.instance
                            if (service == null) {
                                result.error("SERVICE_NOT_RUNNING", "Accessibility service is not running", null)
                            } else {
                                result.success(service.swipe(startX, startY, endX, endY))
                            }
                        }

                        "pressBack" -> {
                            val service = AgentAccessibilityService.instance
                            if (service == null) {
                                result.error("SERVICE_NOT_RUNNING", "Accessibility service is not running", null)
                            } else {
                                result.success(service.pressBack())
                            }
                        }

                        "pressHome" -> {
                            val service = AgentAccessibilityService.instance
                            if (service == null) {
                                result.error("SERVICE_NOT_RUNNING", "Accessibility service is not running", null)
                            } else {
                                result.success(service.pressHome())
                            }
                        }

                        "openNotifications" -> {
                            val service = AgentAccessibilityService.instance
                            if (service == null) {
                                result.error("SERVICE_NOT_RUNNING", "Accessibility service is not running", null)
                            } else {
                                result.success(service.openNotifications())
                            }
                        }

                        "getCurrentPackage" -> {
                            val service = AgentAccessibilityService.instance
                            if (service == null) {
                                result.error("SERVICE_NOT_RUNNING", "Accessibility service is not running", null)
                            } else {
                                result.success(service.getCurrentPackage())
                            }
                        }

                        "scheduleRoutineAlarm" -> {
                            val routineId = call.argument<String>("routineId") ?: ""
                            val delaySeconds = (call.argument<Number>("delaySeconds")?.toLong()) ?: 1800L
                            MacroAlarmScheduler.scheduleRoutineAlarm(context, routineId, delaySeconds)
                            result.success(true)
                        }

                        "cancelRoutineAlarm" -> {
                            val routineId = call.argument<String>("routineId") ?: ""
                            MacroAlarmScheduler.cancelRoutineAlarm(context, routineId)
                            result.success(true)
                        }

                        "startRoutineForegroundService" -> {
                            val title = call.argument<String>("title") ?: "Running Routine"
                            MacroForegroundService.start(context, title)
                            result.success(true)
                        }

                        "stopRoutineForegroundService" -> {
                            val returnToListener = call.argument<Boolean>("returnToListener") ?: true
                            if (returnToListener) {
                                MacroForegroundService.startListener(context)
                            } else {
                                MacroForegroundService.stop(context)
                            }
                            MacroWakeReceiver.releaseWakeLock()
                            result.success(true)
                        }

                        "startBackgroundService" -> {
                            val status = call.argument<String>("status") ?: "Listening for Telegram commands & scheduled routines"
                            val botToken = call.argument<String>("botToken")
                            val telegramEnabled = call.argument<Boolean>("telegramEnabled") ?: false
                            MacroForegroundService.startListener(context, status, botToken, telegramEnabled)
                            result.success(true)
                        }

                        "stopBackgroundService" -> {
                            MacroForegroundService.stop(context)
                            MacroWakeReceiver.releaseWakeLock()
                            result.success(true)
                        }

                        "isBackgroundServiceRunning" -> {
                            result.success(MacroForegroundService.isRunning)
                        }

                        "requestIgnoreBatteryOptimizations" -> {
                            if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.M) {
                                try {
                                    val intent = Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS).apply {
                                        data = Uri.parse("package:${context.packageName}")
                                        addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                                    }
                                    context.startActivity(intent)
                                    result.success(true)
                                } catch (e: Exception) {
                                    android.util.Log.e("MainActivity", "Failed to open battery optimization settings: ${e.message}")
                                    result.error("BATTERY_OPTI_ERROR", e.message, null)
                                }
                            } else {
                                result.success(true)
                            }
                        }

                        "isIgnoringBatteryOptimizations" -> {
                            if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.M) {
                                val pm = context.getSystemService(Context.POWER_SERVICE) as? PowerManager
                                result.success(pm?.isIgnoringBatteryOptimizations(context.packageName) ?: false)
                            } else {
                                result.success(true)
                            }
                        }

                        "markDartReady" -> {
                            isDartReady = true
                            android.util.Log.d("MainActivity", "Dart handler marked ready")
                            result.success(true)
                        }

                        "getPendingRoutine" -> {
                            loadPersistedQueues(context)
                            val rId = synchronized(pendingRoutineIds) {
                                if (pendingRoutineIds.isNotEmpty()) pendingRoutineIds.removeAt(0) else null
                            }
                            persistRoutineQueue(context)
                            result.success(rId)
                        }

                        "getPendingRoutines" -> {
                            loadPersistedQueues(context)
                            val list = synchronized(pendingRoutineIds) {
                                val copy = pendingRoutineIds.toList()
                                pendingRoutineIds.clear()
                                copy
                            }
                            persistRoutineQueue(context)
                            result.success(list)
                        }

                        "getPendingTelegramMessage" -> {
                            loadPersistedQueues(context)
                            val msg = synchronized(pendingTelegramMessages) {
                                if (pendingTelegramMessages.isNotEmpty()) pendingTelegramMessages.removeAt(0) else null
                            }
                            persistTelegramQueue(context)
                            result.success(msg)
                        }

                        "getPendingTelegramMessages" -> {
                            loadPersistedQueues(context)
                            val list = synchronized(pendingTelegramMessages) {
                                val copy = pendingTelegramMessages.toList()
                                pendingTelegramMessages.clear()
                                copy
                            }
                            persistTelegramQueue(context)
                            result.success(list)
                        }

                        "reloadTelegramPoller" -> {
                            val botToken = call.argument<String>("botToken")
                            val telegramEnabled = call.argument<Boolean>("telegramEnabled")
                            MacroForegroundService.reloadTelegramPoller(botToken, telegramEnabled)
                            result.success(true)
                        }

                        "moveTaskToBack" -> {
                            currentActivity?.moveTaskToBack(true)
                            result.success(true)
                        }

                        "setKeepScreenOn" -> {
                            val enabled = call.argument<Boolean>("enabled") ?: false
                            currentActivity?.applyKeepScreenOn(enabled)
                            result.success(true)
                        }

                        "setShowWhenLocked" -> {
                            val enabled = call.argument<Boolean>("enabled") ?: true
                            currentActivity?.applyShowWhenLocked(enabled)
                            result.success(true)
                        }

                        "setTaskKeepAwake" -> {
                            val enabled = call.argument<Boolean>("enabled") ?: false
                            val owner = call.argument<String>("owner") ?: "task_executor"
                            if (enabled) {
                                AgentAccessibilityService.acquireKeepAwake(owner)
                                currentActivity?.applyKeepScreenOn(true)
                            } else {
                                AgentAccessibilityService.releaseKeepAwake(owner)
                                if (!AgentAccessibilityService.hasKeepAwakeOwners() && !MacroForegroundService.isExecutingRoutine) {
                                    currentActivity?.applyKeepScreenOn(false)
                                }
                            }
                            result.success(true)
                        }

                        "canUseFullScreenIntent" -> {
                            if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
                                val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as? android.app.NotificationManager
                                result.success(nm?.canUseFullScreenIntent() ?: true)
                            } else {
                                result.success(true)
                            }
                        }

                        "requestFullScreenIntentPermission" -> {
                            if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
                                val intent = Intent(Settings.ACTION_MANAGE_APP_USE_FULL_SCREEN_INTENT).apply {
                                    data = Uri.parse("package:${context.packageName}")
                                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                                }
                                context.startActivity(intent)
                                result.success(true)
                            } else {
                                result.success(true)
                            }
                        }

                        "launchPackage" -> {
                            val pkg = call.argument<String>("packageName") ?: ""
                            if (pkg.isEmpty()) {
                                result.success(false)
                            } else {
                                val launchIntent = context.packageManager.getLaunchIntentForPackage(pkg)
                                if (launchIntent != null) {
                                    launchIntent.addFlags(
                                        Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_RESET_TASK_IF_NEEDED
                                    )
                                    try {
                                        (currentActivity ?: context).startActivity(launchIntent)
                                        result.success(true)
                                    } catch (e: Exception) {
                                        android.util.Log.e("MainActivity", "launchPackage failed for $pkg: ${e.message}")
                                        result.success(false)
                                    }
                                } else {
                                    result.success(false)
                                }
                            }
                        }

                        "dismissKeyguard" -> {
                            val act = currentActivity
                            if (act != null) {
                                act.dismissKeyguardWithCallback { dismissed ->
                                    result.success(dismissed)
                                }
                            } else {
                                val km = context.getSystemService(Context.KEYGUARD_SERVICE) as? KeyguardManager
                                result.success(!(km?.isKeyguardLocked ?: false))
                            }
                        }

                        "canScheduleExactAlarms" -> {
                            result.success(MacroAlarmScheduler.canScheduleExactAlarms(context))
                        }

                        "requestExactAlarmPermission" -> {
                            if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.S) {
                                val intent = Intent(Settings.ACTION_REQUEST_SCHEDULE_EXACT_ALARM).apply {
                                    data = Uri.parse("package:${context.packageName}")
                                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                                }
                                context.startActivity(intent)
                                result.success(true)
                            } else {
                                result.success(true)
                            }
                        }

                        "openAppDetailsSettings" -> {
                            val intent = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
                                data = Uri.parse("package:${context.packageName}")
                                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            }
                            context.startActivity(intent)
                            result.success(true)
                        }

                        "lockScreen" -> {
                            AgentAccessibilityService.clearAllKeepAwake()
                            currentActivity?.applyKeepScreenOn(false)
                            val service = AgentAccessibilityService.instance
                            if (service == null) {
                                result.error("SERVICE_NOT_RUNNING", "Accessibility service is not running", null)
                            } else {
                                result.success(service.lockScreen())
                            }
                        }

                        "isKeyguardLocked" -> {
                            val km = context.getSystemService(Context.KEYGUARD_SERVICE) as? KeyguardManager
                            result.success(km?.isKeyguardLocked ?: false)
                        }

                        "isScreenInteractive" -> {
                            val pm = context.getSystemService(Context.POWER_SERVICE) as? PowerManager
                            result.success(pm?.isInteractive ?: false)
                        }

                        "isUserInteracting" -> {
                            val windowMs = (call.argument<Number>("windowMs")?.toLong()) ?: 30000L
                            result.success(AgentAccessibilityService.isUserActivelyInteracting(windowMs))
                        }

                        "wakeScreen" -> {
                            try {
                                val pm = context.getSystemService(Context.POWER_SERVICE) as? PowerManager
                                @Suppress("DEPRECATION")
                                val wakeLock = pm?.newWakeLock(
                                    PowerManager.SCREEN_BRIGHT_WAKE_LOCK or PowerManager.ACQUIRE_CAUSES_WAKEUP,
                                    "PrivateAgent:WakeScreen"
                                )
                                wakeLock?.acquire(3000L)
                                result.success(true)
                            } catch (e: Exception) {
                                result.error("WAKE_FAILED", e.message, null)
                            }
                        }

                        "acquireWakeLock" -> {
                            MacroWakeReceiver.acquireWakeLock(context)
                            result.success(true)
                        }

                        "releaseWakeLock" -> {
                            MacroWakeReceiver.releaseWakeLock()
                            result.success(true)
                        }

                        "pickJsonFile" -> {
                            val activity = currentActivity
                            if (activity == null) {
                                result.error("NO_ACTIVITY", "Cannot pick file without active activity", null)
                            } else {
                                pendingFilePickerResult = result
                                try {
                                    val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                                        addCategory(Intent.CATEGORY_OPENABLE)
                                        type = "*/*"
                                        putExtra(
                                            Intent.EXTRA_MIME_TYPES,
                                            arrayOf("application/json", "text/plain", "application/octet-stream")
                                        )
                                    }
                                    activity.startActivityForResult(intent, FILE_PICKER_REQUEST_CODE)
                                } catch (e: Exception) {
                                    pendingFilePickerResult = null
                                    result.error("PICK_ERROR", e.message, null)
                                }
                            }
                        }

                        "saveJsonFileToDownloads" -> {
                            val fileName = call.argument<String>("fileName") ?: "private_agent_export.json"
                            val content = call.argument<String>("content") ?: ""
                            try {
                                var savedPath = ""
                                if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.Q) {
                                    val contentValues = android.content.ContentValues().apply {
                                        put(android.provider.MediaStore.MediaColumns.DISPLAY_NAME, fileName)
                                        put(android.provider.MediaStore.MediaColumns.MIME_TYPE, "application/json")
                                        put(
                                            android.provider.MediaStore.MediaColumns.RELATIVE_PATH,
                                            android.os.Environment.DIRECTORY_DOWNLOADS
                                        )
                                    }
                                    val uri = context.contentResolver.insert(
                                        android.provider.MediaStore.Downloads.EXTERNAL_CONTENT_URI,
                                        contentValues
                                    )
                                    if (uri != null) {
                                        context.contentResolver.openOutputStream(uri)?.use { outputStream ->
                                            outputStream.write(content.toByteArray(Charsets.UTF_8))
                                        }
                                        savedPath = "Downloads/$fileName"
                                    } else {
                                        throw Exception("Failed to create download URI")
                                    }
                                } else {
                                    val dir = android.os.Environment.getExternalStoragePublicDirectory(
                                        android.os.Environment.DIRECTORY_DOWNLOADS
                                    )
                                    if (!dir.exists()) dir.mkdirs()
                                    val file = java.io.File(dir, fileName)
                                    file.writeText(content, Charsets.UTF_8)
                                    savedPath = file.absolutePath
                                }
                                result.success(savedPath)
                            } catch (e: Exception) {
                                android.util.Log.e("PrivateAgent", "Failed to save file to downloads", e)
                                result.error("SAVE_ERROR", e.message, null)
                            }
                        }

                        else -> result.notImplemented()
                    }
                }
        }
    }
}

class BackgroundEngineReceiver : android.content.BroadcastReceiver() {
    override fun onReceive(context: android.content.Context, intent: android.content.Intent) {
        val engine = io.flutter.embedding.engine.FlutterEngineCache
            .getInstance()
            .get("myCachedEngine")
        if (engine == null) {
            android.util.Log.e("PrivateAgent", "Background engine myCachedEngine was not found")
            return
        }

        android.util.Log.d(
            "PrivateAgent",
            "Registering accessibility channel on myCachedEngine " +
                "(engine=${System.identityHashCode(engine)}, " +
                "dartExecuting=${engine.dartExecutor.isExecutingDart})"
        )
        MainActivity.registerAccessibilityChannel(engine, context.applicationContext)
    }
}
