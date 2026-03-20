// models/alarm_model.dart
class AlarmModel {
  final String message;
  final DateTime scheduledTime;
  final bool isVibrationEnabled;
  final List<bool> repeatDays;
  final bool isRepeating;

  AlarmModel({
    required this.message,
    required this.scheduledTime,
    required this.isVibrationEnabled,
    this.repeatDays = const [false, false, false, false, false, false, false],
    this.isRepeating = false,
  });

  factory AlarmModel.fromJson(Map<String, dynamic> json) {
    return AlarmModel(
      message: json['message'] ?? '',
      scheduledTime: DateTime.fromMillisecondsSinceEpoch(json['scheduledTime']),
      isVibrationEnabled: json['isVibrationEnabled'] ?? true,
      repeatDays: json['repeatDays'] != null
          ? List<bool>.from(json['repeatDays'])
          : List.filled(7, false),
      isRepeating: json['isRepeating'] ?? false,
    );
  }

  Map<String, dynamic> toJson() => {
        'message': message,
        'scheduledTime': scheduledTime.millisecondsSinceEpoch,
        'isVibrationEnabled': isVibrationEnabled,
        'repeatDays': repeatDays,
        'isRepeating': isRepeating,
      };

  String getRepeatDaysText() {
    if (!isRepeating) return 'Không lặp';
    final days = ['T2', 'T3', 'T4', 'T5', 'T6', 'T7', 'CN'];
    final selected = <String>[];
    for (int i = 0; i < 7; i++) if (repeatDays[i]) selected.add(days[i]);

    if (selected.length == 7) return 'Hàng ngày';
    if (selected.length == 5 && repeatDays.take(5).every((e) => e))
      return 'Ngày làm việc';
    if (selected.length == 2 && repeatDays[5] && repeatDays[6])
      return 'Cuối tuần';
    return selected.join(', ');
  }
}
