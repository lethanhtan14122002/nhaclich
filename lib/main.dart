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
import 'package:uuid/uuid.dart';

import 'models/alarm_model.dart';
import 'screens/create_alarm_screen.dart';
import 'screens/fullscreen_message_screen.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

const String _kChannelId = 'text_alarm_channel';
const String _kChannelName = 'Text Alarm Notifications';
const String _kChannelDesc = 'Notifications for text alarms';
const String _kAlarmsPrefsKey = 'saved_alarms';

const MethodChannel _messageChannel =
    MethodChannel('com.nhaclich.text_alarm/message');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  tzdata.initializeTimeZones();

  await _initializeNotifications();
  await requestPermissions();

  runApp(MaterialApp(
    debugShowCheckedModeBanner: false,
    navigatorKey: navigatorKey,
    home: const TextAlarmApp(),
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

class TextAlarmApp extends StatefulWidget {
  const TextAlarmApp({super.key});

  @override
  State<TextAlarmApp> createState() => _TextAlarmAppState();
}

class _TextAlarmAppState extends State<TextAlarmApp>
    with WidgetsBindingObserver {
  List<AlarmModel> alarms = [];

  final MethodChannel _alarmChannel =
      const MethodChannel('com.nhaclich.text_alarm/alarm');
  final MethodChannel _messageChannel =
      const MethodChannel('com.nhaclich.text_alarm/message');

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadSavedAlarms();

    _messageChannel.setMethodCallHandler((call) async {
      if (call.method == 'playMessageNow') {
        final args = call.arguments as Map;
        final message = args['message'] as String?;
        final vibration = args['vibrationEnabled'] as bool? ?? true;

        if (message != null && mounted) {
          await wakeUpDevice();

          AlarmModel? triggeredAlarm;
          try {
            triggeredAlarm = alarms.firstWhere(
              (a) => a.message == message && a.enabled,
              orElse: () => alarms.firstWhere((a) => a.message == message),
            );
          } catch (_) {}

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
              ).then((_) async {
                if (triggeredAlarm != null && triggeredAlarm.enabled) {
                  if (triggeredAlarm.isRepeating) {
                    // Lặp lại → lên lịch lần sau
                    await _scheduleAlarm(triggeredAlarm);
                  } else {
                    // Một lần → disable
                    triggeredAlarm.enabled = false;
                    await _saveAlarms();
                    setState(() {}); // Cập nhật UI
                  }
                }
              });
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

  Future<void> _loadSavedAlarms() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getStringList(_kAlarmsPrefsKey);

    if (saved != null) {
      final list = saved
          .map((e) => AlarmModel.fromJson(json.decode(e)))
          .where((a) => a.enabled)
          .toList();

      setState(() {
        alarms = list;
      });

      for (var alarm in list) {
        if (alarm.enabled) {
          await _scheduleAlarm(alarm);
        }
      }
    }
  }

  Future<void> _saveAlarms() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonList = alarms.map((e) => json.encode(e.toJson())).toList();
    await prefs.setStringList(_kAlarmsPrefsKey, jsonList);
  }

  // Hàm đặt alarm (dùng chung cho cả một lần và lặp lại)
  Future<void> _scheduleAlarm(AlarmModel alarm) async {
    final DateTime targetTime;

    if (alarm.isRepeating) {
      // Với lặp lại: tìm lần gần nhất trong tương lai
      targetTime = _getNextOccurrence(alarm) ?? alarm.scheduledTime;
      if (!targetTime.isAfter(DateTime.now())) {
        print("No future repeat time found for alarm ${alarm.id}");
        return;
      }
    } else {
      // Không lặp: chỉ đặt nếu chưa qua
      if (alarm.scheduledTime.isBefore(DateTime.now())) {
        print("One-time alarm ${alarm.id} already passed, skipping schedule.");
        return;
      }
      targetTime = alarm.scheduledTime;
    }

    await _setNativeAlarm(
      targetTime,
      alarm.message,
      alarm.isVibrationEnabled,
    );
  }

  DateTime? _getNextOccurrence(AlarmModel alarm) {
    if (!alarm.isRepeating || alarm.repeatDays.every((e) => !e)) {
      return null;
    }

    DateTime now = DateTime.now();
    DateTime candidate = now;

    for (int i = 0; i < 14; i++) {
      final weekdayIndex = candidate.weekday - 1;
      if (alarm.repeatDays[weekdayIndex]) {
        final next = DateTime(
          candidate.year,
          candidate.month,
          candidate.day,
          alarm.scheduledTime.hour,
          alarm.scheduledTime.minute,
        );

        if (next.isAfter(now) || next.isAtSameMomentAs(now)) {
          return next;
        }
      }
      candidate = candidate.add(const Duration(days: 1));
    }
    return null;
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
        print("Native alarm set for ${time.toString()} - $message");
      } catch (e) {
        print('Error setting native alarm: $e');
      }
    }
  }

  Future<void> _createNewAlarm() async {
    final result = await Navigator.push<AlarmModel>(
      context,
      MaterialPageRoute(builder: (_) => const CreateAlarmScreen()),
    );

    if (result != null) {
      setState(() {
        alarms.add(result);
        alarms.sort((a, b) => a.scheduledTime.compareTo(b.scheduledTime));
      });
      await _saveAlarms();

      await _scheduleAlarm(result);

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
      setState(() {
        alarms[index] = edited;
        alarms.sort((a, b) => a.scheduledTime.compareTo(b.scheduledTime));
      });
      await _saveAlarms();

      await _scheduleAlarm(edited);

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
        content: const Text('Bạn có chắc muốn xóa báo thức này?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Hủy'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              setState(() {
                alarms[index].enabled = false;
              });
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

  String _formatDateTime(DateTime dt) {
    return '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final activeAlarms = alarms.where((a) => a.enabled).toList();

    return Scaffold(
      appBar: AppBar(title: const Text('NHẮC LỊCH')),
      body: activeAlarms.isEmpty
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
              itemCount: activeAlarms.length,
              itemBuilder: (context, index) {
                final alarm = activeAlarms[index];

                return Card(
                  margin: const EdgeInsets.only(bottom: 16),
                  child: ListTile(
                    onTap: () => _editAlarm(alarms.indexOf(alarm)),
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
                        Text(
                          alarm.getRepeatDaysText(),
                          style: const TextStyle(color: Colors.blue),
                        ),
                      ],
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                            icon: const Icon(Icons.edit),
                            onPressed: () => _editAlarm(alarms.indexOf(alarm))),
                        IconButton(
                          icon: const Icon(Icons.delete, color: Colors.red),
                          onPressed: () => _deleteAlarm(alarms.indexOf(alarm)),
                        ),
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
