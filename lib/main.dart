import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:shared_preferences/shared_preferences.dart';

import 'models/alarm_model.dart';
import 'screens/create_alarm_screen.dart';
import 'screens/fullscreen_message_screen.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

// Constants
const String _kChannelId = 'text_alarm_channel';
const String _kChannelName = 'Text Alarm Notifications';
const String _kChannelDesc = 'Notifications for text alarms';
const String _kAlarmsPrefsKey = 'saved_alarms';

// Method channels
const MethodChannel _videoChannel =
    MethodChannel('com.nhaclich.text_alarm/message');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  tzdata.initializeTimeZones();

  await _initializeNotifications();
  await requestPermissions();

  runApp(const MaterialApp(
    debugShowCheckedModeBanner: false,
    home: TextAlarmApp(),
  ));
}

final FlutterLocalNotificationsPlugin _notificationsPlugin =
    FlutterLocalNotificationsPlugin();

Future<void> _initializeNotifications() async {
  const AndroidInitializationSettings androidSettings =
      AndroidInitializationSettings('@mipmap/ic_launcher');

  const DarwinInitializationSettings iosSettings = DarwinInitializationSettings(
    requestAlertPermission: true,
    requestBadgePermission: true,
    requestSoundPermission: true,
  );

  const InitializationSettings settings = InitializationSettings(
    android: androidSettings,
    iOS: iosSettings,
  );

  await _notificationsPlugin.initialize(
    settings,
    onDidReceiveNotificationResponse: _onNotificationTapped,
  );
}

void _onNotificationTapped(NotificationResponse response) {
  if (response.payload != null) {
    final parts = response.payload!.split('|');
    if (parts.length >= 2) {
      final message = parts[0];
      final vibrationEnabled = parts[1] == 'true';

      const platform = MethodChannel('com.nhaclich.text_alarm/alarm');
      platform.invokeMethod('playMessageDirectly', {
        'message': message,
        'vibrationEnabled': vibrationEnabled,
      });
    }
  }
}

Future<void> wakeUpDevice() async {
  await WakelockPlus.enable();
  if (Platform.isAndroid) {
    const platform = MethodChannel('com.nhaclich.text_alarm/wake');
    try {
      await platform.invokeMethod('wakeUpDevice');
    } catch (e) {
      print('Error waking device: $e');
    }
  }
}

Future<void> requestPermissions() async {
  await [
    Permission.notification,
    Permission.ignoreBatteryOptimizations,
    Permission.systemAlertWindow,
    Permission.accessNotificationPolicy,
  ].request();

  if (await Permission.ignoreBatteryOptimizations.isGranted == false) {
    await Permission.ignoreBatteryOptimizations.request();
  }
}

// ========================== MAIN APP ==========================

class TextAlarmApp extends StatefulWidget {
  const TextAlarmApp({super.key});

  @override
  State<TextAlarmApp> createState() => _TextAlarmAppState();
}

class _TextAlarmAppState extends State<TextAlarmApp>
    with WidgetsBindingObserver {
  String? alarmMessage;
  DateTime? scheduledTime;
  bool isVibrationEnabled = true;
  List<AlarmModel> alarms = [];

  final MethodChannel _alarmChannel =
      const MethodChannel('com.nhaclich.text_alarm/alarm');
  final MethodChannel _wakeChannel =
      const MethodChannel('com.nhaclich.text_alarm/wake');
  final MethodChannel _messageChannel =
      const MethodChannel('com.nhaclich.text_alarm/message');

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadSavedSettings();
    _loadSavedAlarms();

    _messageChannel.setMethodCallHandler((call) async {
      if (call.method == 'playMessageNow') {
        final args = call.arguments as Map;
        final message = args['message'] as String?;
        final vibration = args['vibrationEnabled'] as bool? ?? true;

        if (message != null && mounted) {
          await wakeUpDevice();
          Future.delayed(Duration.zero, () {
            if (mounted) {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => FullScreenMessage(
                    message: message,
                    isVibrationEnabled: vibration,
                  ),
                ),
              );
            }
          });
        }
      }
      return null;
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _loadSavedSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      alarmMessage = prefs.getString('alarmMessage');
      isVibrationEnabled = prefs.getBool('vibrationEnabled') ?? true;

      final millis = prefs.getInt('scheduledTime');
      if (millis != null) {
        final time = DateTime.fromMillisecondsSinceEpoch(millis);
        if (time.isAfter(DateTime.now())) {
          scheduledTime = time;
        }
      }
    });
  }

  Future<void> _loadSavedAlarms() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getStringList(_kAlarmsPrefsKey);

    if (saved != null) {
      final now = DateTime.now();
      final list = saved
          .map((e) => AlarmModel.fromJson(json.decode(e)))
          .where((a) => a.scheduledTime.isAfter(now))
          .toList();

      setState(() => alarms = list);

      for (var alarm in list) {
        _setNativeAlarm(
            alarm.scheduledTime, alarm.message, alarm.isVibrationEnabled);
      }
    }
  }

  Future<void> _saveAlarms() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonList = alarms.map((e) => json.encode(e.toJson())).toList();
    await prefs.setStringList(_kAlarmsPrefsKey, jsonList);
  }

  Future<void> _showMessageInput() async {
    final controller = TextEditingController(text: alarmMessage);

    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Nội dung báo thức'),
        content: TextField(
          controller: controller,
          maxLines: 6,
          decoration: const InputDecoration(
            hintText: 'Nhập lời nhắn sẽ hiển thị khi báo thức kêu...',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Hủy')),
          TextButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Lưu'),
          ),
        ],
      ),
    );

    if (result != null && result.isNotEmpty) {
      setState(() => alarmMessage = result);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('alarmMessage', result);
    }
  }

  Future<void> _createNewAlarm() async {
    if (alarmMessage == null || alarmMessage!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Vui lòng nhập nội dung báo thức trước')),
      );
      await _showMessageInput();
      return;
    }

    final result = await Navigator.push<AlarmModel>(
      context,
      MaterialPageRoute(builder: (_) => const CreateAlarmScreen()),
    );

    if (result != null) {
      setState(() => alarms.add(result));
      alarms.sort((a, b) => a.scheduledTime.compareTo(b.scheduledTime));
      await _saveAlarms();

      _setNativeAlarm(
          result.scheduledTime, result.message, result.isVibrationEnabled);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(
                'Báo thức đã đặt: ${_formatDateTime(result.scheduledTime)}')),
      );
    }
  }

  Future<void> _editAlarm(int index) async {
    final alarm = alarms[index];
    final edited = await Navigator.push<AlarmModel>(
      context,
      MaterialPageRoute(
        builder: (_) => CreateAlarmScreen(existingAlarm: alarm),
      ),
    );

    if (edited != null) {
      setState(() => alarms[index] = edited);
      alarms.sort((a, b) => a.scheduledTime.compareTo(b.scheduledTime));
      await _saveAlarms();
      _setNativeAlarm(
          edited.scheduledTime, edited.message, edited.isVibrationEnabled);

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Báo thức đã được cập nhật')),
      );
    }
  }

  void _deleteAlarm(int index) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Xóa báo thức?'),
        content: const Text('Bạn có chắc muốn xóa?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Hủy')),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              setState(() => alarms.removeAt(index));
              await _saveAlarms();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Đã xóa báo thức')),
              );
            },
            child: const Text('Xóa', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  Future<void> _setNativeAlarm(
      DateTime time, String message, bool vibrationEnabled) async {
    if (Platform.isAndroid) {
      try {
        await _alarmChannel.invokeMethod('setAlarm', {
          'timeMillis': time.millisecondsSinceEpoch,
          'message': message,
          'vibrationEnabled': vibrationEnabled,
        });
      } catch (e) {
        print('Error setting native alarm: $e');
      }
    }
  }

  Future<void> _scheduleNotification(
      DateTime date, String message, bool vibration) async {
    final androidDetails = AndroidNotificationDetails(
      _kChannelId,
      _kChannelName,
      channelDescription: _kChannelDesc,
      importance: Importance.max,
      priority: Priority.high,
      fullScreenIntent: true,
    );

    final details = NotificationDetails(android: androidDetails);

    final tzTime = tz.TZDateTime.from(date, tz.local);

    await _notificationsPlugin.zonedSchedule(
      0,
      'Báo Thức',
      'Đã đến giờ!',
      tzTime,
      details,
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      payload: '$message|$vibration',
    );
  }

  String _formatDateTime(DateTime dt) {
    return '${dt.day}/${dt.month}/${dt.year} ${dt.hour}:${dt.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('NHẮC LỊCH')),
      body: alarms.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.alarm_off, size: 90, color: Colors.grey),
                  const SizedBox(height: 20),
                  const Text('Chưa có báo thức nào',
                      style: TextStyle(fontSize: 20, color: Colors.grey)),
                  const SizedBox(height: 10),
                  const Text('Nhấn + để tạo báo thức',
                      style: TextStyle(color: Colors.grey)),
                ],
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: alarms.length,
              itemBuilder: (context, index) {
                final alarm = alarms[index];
                return Card(
                  margin: const EdgeInsets.only(bottom: 16),
                  child: ListTile(
                    onTap: () => _editAlarm(index),
                    title: Text(
                      '${alarm.scheduledTime.hour.toString().padLeft(2, '0')}:${alarm.scheduledTime.minute.toString().padLeft(2, '0')}',
                      style: const TextStyle(
                          fontSize: 36, fontWeight: FontWeight.bold),
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(alarm.message,
                            maxLines: 2, overflow: TextOverflow.ellipsis),
                        const SizedBox(height: 8),
                        Text(alarm.getRepeatDaysText(),
                            style: const TextStyle(color: Colors.blue)),
                      ],
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                            icon: const Icon(Icons.edit),
                            onPressed: () => _editAlarm(index)),
                        IconButton(
                            icon: const Icon(Icons.delete, color: Colors.red),
                            onPressed: () => _deleteAlarm(index)),
                      ],
                    ),
                  ),
                );
              },
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: _createNewAlarm,
        child: const Icon(Icons.add),
      ),
    );
  }
}
