// screens/create_alarm_screen.dart
import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:intl/intl.dart';
import '../models/alarm_model.dart';
import 'ad_helper.dart'; // ← Đảm bảo file này tồn tại

class CreateAlarmScreen extends StatefulWidget {
  final AlarmModel? existingAlarm;

  const CreateAlarmScreen({super.key, this.existingAlarm});

  @override
  State<CreateAlarmScreen> createState() => _CreateAlarmScreenState();
}

class _CreateAlarmScreenState extends State<CreateAlarmScreen> {
  late DateTime selectedDateTime;
  late String message;
  bool isVibrationEnabled = true;
  bool isRepeating = false;
  List<bool> repeatDays = List.filled(7, false); // T2 đến CN

  final List<String> dayLabels = ['T2', 'T3', 'T4', 'T5', 'T6', 'T7', 'CN'];

  // ==================== QUẢNG CÁO INTERSTITIAL ====================
  InterstitialAd? _interstitialAd;
  bool _isAdLoaded = false;

  @override
  void initState() {
    super.initState();

    _loadInterstitialAd(); // Tải quảng cáo khi vào màn hình

    if (widget.existingAlarm != null) {
      // Chỉnh sửa báo thức cũ
      final alarm = widget.existingAlarm!;
      selectedDateTime = alarm.scheduledTime;
      message = alarm.message;
      isVibrationEnabled = alarm.isVibrationEnabled;
      isRepeating = alarm.isRepeating;
      repeatDays = List.from(alarm.repeatDays);
    } else {
      // Tạo báo thức mới
      final now = DateTime.now();
      selectedDateTime = now.add(const Duration(minutes: 5));
      message = "";
      isVibrationEnabled = true;
      isRepeating = false;
    }
  }

  // Tải quảng cáo xen kẽ
  void _loadInterstitialAd() {
    InterstitialAd.load(
      adUnitId: AdHelper.interstitialAdUnitId,
      request: const AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (InterstitialAd ad) {
          _interstitialAd = ad;
          _isAdLoaded = true;

          ad.fullScreenContentCallback = FullScreenContentCallback(
            onAdDismissedFullScreenContent: (InterstitialAd ad) {
              ad.dispose();
              _interstitialAd = null;
              _isAdLoaded = false;
              _loadInterstitialAd(); // Tải lại quảng cáo cho lần sau
            },
            onAdFailedToShowFullScreenContent:
                (InterstitialAd ad, AdError error) {
              ad.dispose();
              _interstitialAd = null;
              _isAdLoaded = false;
            },
          );
        },
        onAdFailedToLoad: (LoadAdError error) {
          _interstitialAd = null;
          _isAdLoaded = false;
        },
      ),
    );
  }

  Future<void> _pickTime() async {
    final TimeOfDay? pickedTime = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(selectedDateTime),
    );

    if (pickedTime != null) {
      setState(() {
        selectedDateTime = DateTime(
          selectedDateTime.year,
          selectedDateTime.month,
          selectedDateTime.day,
          pickedTime.hour,
          pickedTime.minute,
        );

        // Nếu thời gian đã qua thì chuyển sang ngày mai
        if (selectedDateTime.isBefore(DateTime.now())) {
          selectedDateTime = selectedDateTime.add(const Duration(days: 1));
        }
      });
    }
  }

  void _toggleRepeatDay(int index) {
    setState(() {
      repeatDays[index] = !repeatDays[index];
    });
  }

  Future<void> _saveAlarm() async {
    if (message.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Vui lòng nhập nội dung báo thức')),
      );
      return;
    }

    // ==================== HIỂN THỊ QUẢNG CÁO KHI NHẤN LƯU ====================
    if (_isAdLoaded && _interstitialAd != null) {
      await _interstitialAd!.show();
      // Lưu báo thức sẽ được thực hiện sau khi quảng cáo đóng (xem callback ở trên)
    }

    // Tạo model báo thức
    final alarm = AlarmModel(
      message: message.trim(),
      scheduledTime: selectedDateTime,
      isVibrationEnabled: isVibrationEnabled,
      repeatDays: List.from(repeatDays),
      isRepeating: isRepeating && repeatDays.contains(true),
    );

    // Quay về màn hình trước và truyền dữ liệu báo thức
    Navigator.pop(context, alarm);
  }

  @override
  void dispose() {
    _interstitialAd?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.existingAlarm == null ? 'Tạo báo thức' : 'Chỉnh sửa báo thức',
        ),
        actions: [
          TextButton(
            onPressed: _saveAlarm,
            child: const Text(
              'Lưu',
              style: TextStyle(
                color: Color.fromARGB(255, 5, 97, 154),
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
      body: ListView(
        children: [
          SingleChildScrollView(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Nội dung báo thức
                const Text(
                  'Nội dung hiển thị khi báo thức kêu',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                TextField(
                  maxLines: 5,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    hintText: 'Ví dụ: Sáng rồi đừng lười nữa ...',
                  ),
                  controller: TextEditingController(text: message),
                  onChanged: (value) => message = value,
                ),

                const SizedBox(height: 24),

                // Thời gian
                const Text(
                  'Thời gian báo thức',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.access_time, color: Colors.blue),
                    title: Text(
                      DateFormat('HH:mm').format(selectedDateTime),
                      style: const TextStyle(
                          fontSize: 40, fontWeight: FontWeight.bold),
                    ),
                    subtitle: Text(
                      DateFormat('EEEE, dd/MM/yyyy').format(selectedDateTime),
                    ),
                    onTap: _pickTime,
                  ),
                ),

                const SizedBox(height: 24),

                // Rung
                SwitchListTile(
                  title: const Text('Bật rung'),
                  subtitle: const Text('Thiết bị sẽ rung khi báo thức kêu'),
                  value: isVibrationEnabled,
                  onChanged: (value) =>
                      setState(() => isVibrationEnabled = value),
                  secondary: const Icon(Icons.vibration),
                ),

                const SizedBox(height: 16),

                // Lặp lại
                SwitchListTile(
                  title: const Text('Lặp lại'),
                  value: isRepeating,
                  onChanged: (value) => setState(() => isRepeating = value),
                  secondary: const Icon(Icons.repeat),
                ),

                if (isRepeating) ...[
                  const SizedBox(height: 12),
                  const Text(
                    'Chọn ngày lặp lại:',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: List.generate(7, (index) {
                      return FilterChip(
                        label: Text(dayLabels[index]),
                        selected: repeatDays[index],
                        onSelected: (_) => _toggleRepeatDay(index),
                        selectedColor: Colors.blue.withOpacity(0.3),
                      );
                    }),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
