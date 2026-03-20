package com.example.ring

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Bundle
import android.os.PowerManager
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.util.Log

// ====================== ALARM RECEIVER ======================
class AlarmReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context?, intent: Intent?) {
        Log.d("AlarmReceiver", "Alarm triggered!")

        if (context == null) return

        val message = intent?.getStringExtra("message") ?: "Đã đến giờ!"
        val vibrationEnabled = intent?.getBooleanExtra("vibrationEnabled", true) ?: true

        try {
            val powerManager = context.getSystemService(Context.POWER_SERVICE) as PowerManager
            val wakeLock = powerManager.newWakeLock(
                PowerManager.FULL_WAKE_LOCK or PowerManager.ACQUIRE_CAUSES_WAKEUP or PowerManager.ON_AFTER_RELEASE,
                "TextAlarm::WakeLock"
            )
            wakeLock.acquire(10 * 60 * 1000L)

            val launchIntent = Intent(context, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_CLEAR_TASK
                putExtra("message", message)
                putExtra("vibrationEnabled", vibrationEnabled)
                putExtra("playImmediately", true)
            }

            context.startActivity(launchIntent)
        } catch (e: Exception) {
            Log.e("AlarmReceiver", "Error: ${e.message}")
        }
    }
}

// ====================== MAIN ACTIVITY ======================
class MainActivity : FlutterActivity() {

    private val WAKE_CHANNEL = "com.example.text_alarm/wake"
    private val ALARM_CHANNEL = "com.example.text_alarm/alarm"
    private val MESSAGE_CHANNEL = "com.example.text_alarm/message"

    private var flutterEngineReady = false

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
            setShowWhenLocked(true)
            setTurnScreenOn(true)
        } else {
            window.addFlags(
                WindowManager.LayoutParams.FLAG_DISMISS_KEYGUARD or
                WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
                WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON
            )
        }
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)

        handleIncomingIntent(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        handleIncomingIntent(intent)
    }

    private fun handleIncomingIntent(intent: Intent?) {
        if (intent == null || !intent.getBooleanExtra("playImmediately", false)) return

        val message = intent.getStringExtra("message") ?: "Đã đến giờ!"
        val vibrationEnabled = intent.getBooleanExtra("vibrationEnabled", true)

        val prefs = getSharedPreferences("TextAlarmPrefs", Context.MODE_PRIVATE)
        prefs.edit()
            .putBoolean("AUTO_PLAY_KEY", true)
            .putString("MESSAGE_KEY", message)
            .putBoolean("VIBRATION_ENABLED_KEY", vibrationEnabled)
            .apply()

        if (flutterEngineReady) {
            playMessageNow(message, vibrationEnabled)
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // Wake Channel
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, WAKE_CHANNEL).setMethodCallHandler { call, result ->
            if (call.method == "wakeUpDevice") result.success(wakeUpDevice())
        }

        // Alarm Channel
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, ALARM_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "setAlarm" -> {
                    val timeMillis = call.argument<Long>("timeMillis")
                    val message = call.argument<String>("message")
                    val vibration = call.argument<Boolean>("vibrationEnabled") ?: true
                    if (timeMillis != null && message != null) {
                        setAlarm(timeMillis, message, vibration)
                        result.success(true)
                    } else result.error("INVALID", "Missing arguments", null)
                }
                "playMessageDirectly" -> {
                    val msg = call.argument<String>("message")
                    val vib = call.argument<Boolean>("vibrationEnabled") ?: true
                    if (msg != null) playMessageNow(msg, vib)
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }

        flutterEngineReady = true

        // Auto play
        val prefs = getSharedPreferences("TextAlarmPrefs", Context.MODE_PRIVATE)
        if (prefs.getBoolean("AUTO_PLAY_KEY", false)) {
            val msg = prefs.getString("MESSAGE_KEY", null)
            val vib = prefs.getBoolean("VIBRATION_ENABLED_KEY", true)
            if (msg != null) {
                prefs.edit().putBoolean("AUTO_PLAY_KEY", false).apply()
                android.os.Handler(mainLooper).postDelayed({
                    playMessageNow(msg, vib)
                }, 800)
            }
        }
    }

    private fun playMessageNow(message: String, vibrationEnabled: Boolean) {
        flutterEngine?.dartExecutor?.binaryMessenger?.let {
            MethodChannel(it, MESSAGE_CHANNEL).invokeMethod(
                "playMessageNow",
                mapOf("message" to message, "vibrationEnabled" to vibrationEnabled)
            )
        }
    }

    private fun wakeUpDevice(): Boolean {
        try {
            val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
            val wl = pm.newWakeLock(PowerManager.FULL_WAKE_LOCK or PowerManager.ACQUIRE_CAUSES_WAKEUP, "TextAlarm:WakeLock")
            wl.acquire(10 * 60 * 1000L)
            return true
        } catch (e: Exception) {
            return false
        }
    }

    private fun setAlarm(timeMillis: Long, message: String, vibrationEnabled: Boolean) {
        val alarmManager = getSystemService(Context.ALARM_SERVICE) as AlarmManager
        val intent = Intent(this, AlarmReceiver::class.java).apply {
            putExtra("message", message)
            putExtra("vibrationEnabled", vibrationEnabled)
        }

        val flags = if (Build.VERSION.SDK_INT >= 23) {
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        } else PendingIntent.FLAG_UPDATE_CURRENT

        val pendingIntent = PendingIntent.getBroadcast(this, 0, intent, flags)

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            alarmManager.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, timeMillis, pendingIntent)
        } else {
            alarmManager.setExact(AlarmManager.RTC_WAKEUP, timeMillis, pendingIntent)
        }
    }
}