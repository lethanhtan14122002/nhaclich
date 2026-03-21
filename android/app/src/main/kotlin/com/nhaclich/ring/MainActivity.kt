package com.nhaclich.ring

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.media.AudioManager
import android.os.Build
import android.os.Bundle
import android.os.PowerManager
import android.util.Log
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

// ====================== ALARM RECEIVER ======================
class AlarmReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context?, intent: Intent?) {
        Log.d("AlarmReceiver", "=== ALARM TRIGGERED ===")

        if (context == null) return

        val message = intent?.getStringExtra("message") ?: "Đã đến giờ!"
        val vibrationEnabled = intent?.getBooleanExtra("vibrationEnabled", true) ?: true

        try {
            // WakeLock mạnh hơn
            val powerManager = context.getSystemService(Context.POWER_SERVICE) as PowerManager
            val wakeLock = powerManager.newWakeLock(
                PowerManager.FULL_WAKE_LOCK or 
                PowerManager.ACQUIRE_CAUSES_WAKEUP or 
                PowerManager.ON_AFTER_RELEASE,
                "TextAlarm::FinalWakeLock"
            )
            wakeLock.acquire(20 * 60 * 1000L) // 20 phút

            val launchIntent = Intent(context, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or 
                        Intent.FLAG_ACTIVITY_CLEAR_TOP or
                        Intent.FLAG_ACTIVITY_CLEAR_TASK or
                        Intent.FLAG_ACTIVITY_RESET_TASK_IF_NEEDED
                putExtra("message", message)
                putExtra("vibrationEnabled", vibrationEnabled)
                putExtra("playImmediately", true)
            }

            context.startActivity(launchIntent)
            Log.d("AlarmReceiver", "Launched MainActivity from receiver")
        } catch (e: Exception) {
            Log.e("AlarmReceiver", "Launch error: ${e.message}")
        }
    }
}

// ====================== MAIN ACTIVITY ======================
class MainActivity : FlutterActivity() {

    private val WAKE_CHANNEL = "com.nhaclich.text_alarm/wake"
    private val ALARM_CHANNEL = "com.nhaclich.text_alarm/alarm"
    private val MESSAGE_CHANNEL = "com.nhaclich.text_alarm/message"
    private val VOLUME_CHANNEL = "com.nhaclich.text_alarm/volume"

    private var flutterEngineReady = false

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        // Quan trọng: Cho phép hiện trên màn hình khóa
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
            setShowWhenLocked(true)
            setTurnScreenOn(true)
        } else {
            window.addFlags(
                WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
                WindowManager.LayoutParams.FLAG_DISMISS_KEYGUARD or
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

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, WAKE_CHANNEL).setMethodCallHandler { call, result ->
            if (call.method == "wakeUpDevice") result.success(wakeUpDevice())
        }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, ALARM_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "setAlarm" -> {
                    val timeMillis = call.argument<Long>("timeMillis")
                    val message = call.argument<String>("message")
                    val vibrationEnabled = call.argument<Boolean>("vibrationEnabled") ?: true

                    if (timeMillis != null && message != null) {
                        setAlarm(timeMillis, message, vibrationEnabled)
                        result.success(true)
                    } else {
                        result.error("INVALID_ARGUMENT", "Missing data", null)
                    }
                }
                "cancelAlarm" -> {
                    cancelAlarm()
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, VOLUME_CHANNEL).setMethodCallHandler { call, result ->
            if (call.method == "setAlarmVolume") {
                try {
                    val am = getSystemService(Context.AUDIO_SERVICE) as AudioManager
                    val current = am.getStreamVolume(AudioManager.STREAM_ALARM)
                    val max = am.getStreamMaxVolume(AudioManager.STREAM_ALARM)
                    if (current < max * 0.7) {
                        am.setStreamVolume(AudioManager.STREAM_ALARM, (max * 0.8).toInt(), 0)
                    }
                    result.success(true)
                } catch (e: Exception) {
                    result.error("ERROR", e.message, null)
                }
            } else {
                result.notImplemented()
            }
        }

        flutterEngineReady = true
    }

    private fun playMessageNow(message: String, vibrationEnabled: Boolean) {
        wakeUpDevice()
        flutterEngine?.dartExecutor?.binaryMessenger?.let { messenger ->
            MethodChannel(messenger, MESSAGE_CHANNEL).invokeMethod(
                "playMessageNow",
                mapOf("message" to message, "vibrationEnabled" to vibrationEnabled)
            )
        }
    }

    private fun wakeUpDevice(): Boolean {
        try {
            val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
            val wl = pm.newWakeLock(
                PowerManager.FULL_WAKE_LOCK or PowerManager.ACQUIRE_CAUSES_WAKEUP or PowerManager.ON_AFTER_RELEASE,
                "TextAlarm:WakeLock"
            )
            wl.acquire(15 * 60 * 1000L)
            return true
        } catch (e: Exception) {
            return false
        }
    }

    private fun setAlarm(timeMillis: Long, message: String, vibrationEnabled: Boolean) {
        try {
            val alarmManager = getSystemService(Context.ALARM_SERVICE) as AlarmManager

            val intent = Intent(this, AlarmReceiver::class.java).apply {
                putExtra("message", message)
                putExtra("vibrationEnabled", vibrationEnabled)
            }

            val flags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            } else {
                PendingIntent.FLAG_UPDATE_CURRENT
            }

            val requestCode = (timeMillis / 1000).toInt()
            val pendingIntent = PendingIntent.getBroadcast(this, requestCode, intent, flags)

            // Cách mạnh nhất hiện nay
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                alarmManager.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, timeMillis, pendingIntent)
            } else {
                alarmManager.setExact(AlarmManager.RTC_WAKEUP, timeMillis, pendingIntent)
            }

            val alarmClockInfo = AlarmManager.AlarmClockInfo(timeMillis, pendingIntent)
            alarmManager.setAlarmClock(alarmClockInfo, pendingIntent)

            Log.d("MainActivity", "Alarm set at $timeMillis")
        } catch (e: Exception) {
            Log.e("MainActivity", "Set alarm failed: ${e.message}")
        }
    }

    private fun cancelAlarm() {
        try {
            val alarmManager = getSystemService(Context.ALARM_SERVICE) as AlarmManager
            val intent = Intent(this, AlarmReceiver::class.java)
            val flags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            } else PendingIntent.FLAG_UPDATE_CURRENT

            val pendingIntent = PendingIntent.getBroadcast(this, 0, intent, flags)
            alarmManager.cancel(pendingIntent)
        } catch (e: Exception) {
            Log.e("MainActivity", "Cancel error: ${e.message}")
        }
    }
}