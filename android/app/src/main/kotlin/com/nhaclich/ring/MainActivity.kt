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
            // Wake lock mạnh để đánh thức thiết bị
            val powerManager = context.getSystemService(Context.POWER_SERVICE) as PowerManager
            val wakeLock = powerManager.newWakeLock(
                PowerManager.FULL_WAKE_LOCK or
                        PowerManager.ACQUIRE_CAUSES_WAKEUP or
                        PowerManager.ON_AFTER_RELEASE,
                "TextAlarm::FinalWakeLock"
            )
            wakeLock.acquire(20 * 60 * 1000L) // 20 phút

            // Intent mở MainActivity với flag fullscreen + play ngay
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
            Log.d("AlarmReceiver", "Launched MainActivity with message: $message, vibration: $vibrationEnabled")
        } catch (e: Exception) {
            Log.e("AlarmReceiver", "Failed to launch activity: ${e.message}", e)
        }
    }
}

// ====================== MAIN ACTIVITY ======================
class MainActivity : FlutterActivity() {

    companion object {
        private const val WAKE_CHANNEL = "com.nhaclich.text_alarm/wake"
        private const val ALARM_CHANNEL = "com.nhaclich.text_alarm/alarm"
        private const val MESSAGE_CHANNEL = "com.nhaclich.text_alarm/message"
        private const val VOLUME_CHANNEL = "com.nhaclich.ring/volume"  // khớp với channel bạn dùng trong FullScreenMessage
    }

    private var flutterEngineReady = false

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        // Cho phép hiển thị trên màn hình khóa và bật màn hình
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

        // Giữ màn hình sáng khi báo thức đang chạy
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)

        // Xử lý intent ngay từ đầu (khi app được mở từ AlarmReceiver)
        handleIncomingIntent(intent)
    }

    private fun handleIncomingIntent(intent: Intent?) {
        if (intent == null || !intent.getBooleanExtra("playImmediately", false)) {
            return
        }

        val message = intent.getStringExtra("message") ?: "Đã đến giờ!"
        val vibrationEnabled = intent.getBooleanExtra("vibrationEnabled", true)

        Log.d("MainActivity", "Handling incoming alarm intent - message: $message, vibration: $vibrationEnabled")

        // Lưu tạm vào SharedPreferences (phòng trường hợp Flutter engine chưa sẵn sàng)
        val prefs = getSharedPreferences("TextAlarmPrefs", Context.MODE_PRIVATE)
        prefs.edit()
            .putBoolean("AUTO_PLAY_KEY", true)
            .putString("MESSAGE_KEY", message)
            .putBoolean("VIBRATION_ENABLED_KEY", vibrationEnabled)
            .apply()

        // Nếu Flutter engine đã sẵn sàng → gửi ngay lệnh play
        if (flutterEngineReady) {
            playMessageNow(message, vibrationEnabled)
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // Channel wake device
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, WAKE_CHANNEL).setMethodCallHandler { call, result ->
            if (call.method == "wakeUpDevice") {
                result.success(wakeUpDevice())
            } else {
                result.notImplemented()
            }
        }

        // Channel set alarm
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, ALARM_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "setAlarm" -> {
                    val timeMillis = call.argument<Long>("timeMillis")
                    val message = call.argument<String>("message")
                    val vibrationEnabled = call.argument<Boolean>("vibrationEnabled") ?: true

                    if (timeMillis != null && !message.isNullOrEmpty()) {
                        setAlarm(timeMillis, message, vibrationEnabled)
                        result.success(true)
                    } else {
                        result.error("INVALID_ARGUMENT", "Missing timeMillis or message", null)
                    }
                }
                else -> result.notImplemented()
            }
        }

        // Channel set alarm volume (dùng trong FullScreenMessage)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, VOLUME_CHANNEL).setMethodCallHandler { call, result ->
            if (call.method == "setAlarmVolume") {
                try {
                    val am = getSystemService(Context.AUDIO_SERVICE) as AudioManager
                    val max = am.getStreamMaxVolume(AudioManager.STREAM_ALARM)
                    val targetVolume = (max * 0.85).toInt()  // 85% volume báo thức
                    am.setStreamVolume(AudioManager.STREAM_ALARM, targetVolume, 0)
                    Log.d("VolumeChannel", "Set alarm volume to $targetVolume / $max")
                    result.success(true)
                } catch (e: Exception) {
                    Log.e("VolumeChannel", "Set volume failed: ${e.message}")
                    result.error("VOLUME_ERROR", e.message, null)
                }
            } else {
                result.notImplemented()
            }
        }

        flutterEngineReady = true

        // Kiểm tra lại intent sau khi engine sẵn sàng
        handleIncomingIntent(intent)
    }

    private fun playMessageNow(message: String, vibrationEnabled: Boolean) {
        Log.d("MainActivity", "Sending playMessageNow to Flutter: $message, vibration: $vibrationEnabled")

        wakeUpDevice()
        flutterEngine?.dartExecutor?.binaryMessenger?.let { messenger ->
            MethodChannel(messenger, MESSAGE_CHANNEL).invokeMethod(
                "playMessageNow",
                mapOf(
                    "message" to message,
                    "vibrationEnabled" to vibrationEnabled
                )
            )
        }
    }

    private fun wakeUpDevice(): Boolean {
        return try {
            val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
            val wl = pm.newWakeLock(
                PowerManager.FULL_WAKE_LOCK or PowerManager.ACQUIRE_CAUSES_WAKEUP or PowerManager.ON_AFTER_RELEASE,
                "TextAlarm:WakeLock"
            )
            wl.acquire(15 * 60 * 1000L) // 15 phút
            true
        } catch (e: Exception) {
            Log.e("MainActivity", "Wake up failed: ${e.message}")
            false
        }
    }

    private fun setAlarm(timeMillis: Long, message: String, vibrationEnabled: Boolean) {
        try {
            val alarmManager = getSystemService(Context.ALARM_SERVICE) as AlarmManager

            val intent = Intent(this, AlarmReceiver::class.java).apply {
                putExtra("message", message)
                putExtra("vibrationEnabled", vibrationEnabled)
            }

            val requestCode = (timeMillis / 1000).toInt()

            val flags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            } else {
                PendingIntent.FLAG_UPDATE_CURRENT
            }

            val pendingIntent = PendingIntent.getBroadcast(this, requestCode, intent, flags)

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                alarmManager.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, timeMillis, pendingIntent)
            } else {
                alarmManager.setExact(AlarmManager.RTC_WAKEUP, timeMillis, pendingIntent)
            }

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
                val alarmClockInfo = AlarmManager.AlarmClockInfo(timeMillis, pendingIntent)
                alarmManager.setAlarmClock(alarmClockInfo, pendingIntent)
            }

            Log.d("MainActivity", "Alarm scheduled at $timeMillis - message: $message")
        } catch (e: Exception) {
            Log.e("MainActivity", "Set alarm failed: ${e.message}", e)
        }
    }
}