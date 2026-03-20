import 'package:flutter/material.dart';
import 'package:ring_alarm/main.dart';
import 'package:vibration/vibration.dart';
import 'package:flutter/services.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'dart:async';

class FullScreenMessage extends StatefulWidget {
  final String message;
  final bool isVibrationEnabled;

  const FullScreenMessage({
    Key? key,
    required this.message,
    this.isVibrationEnabled = true,
  }) : super(key: key);

  @override
  State<FullScreenMessage> createState() => _FullScreenMessageState();
}

class _FullScreenMessageState extends State<FullScreenMessage> {
  final FlutterTts _flutterTts = FlutterTts();
  Timer? _vibrationTimer;
  bool _isSpeaking = true;

  late final String _fullText;

  @override
  void initState() {
    super.initState();
    WakelockPlus.enable();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

    // Kết hợp thời gian và nội dung thành một câu duy nhất
    final now = DateTime.now();
    final timeStr =
        "${now.hour} giờ ${now.minute.toString().padLeft(2, '0')} phút";
    _fullText = "Bây giờ là $timeStr. ${widget.message}";

    _initTts();
    _startSpeaking();

    if (widget.isVibrationEnabled) {
      _startVibration();
    }
  }

  Future<void> _initTts() async {
    await _flutterTts.setLanguage("vi-VN");
    await _flutterTts.setSpeechRate(0.5); // Đọc chậm hơn (0.5)
    await _flutterTts.setVolume(100);
    await _flutterTts.setPitch(1.0);
    await _flutterTts.awaitSpeakCompletion(true);
  }

  void _startSpeaking() async {
    while (_isSpeaking) {
      await _speak(); // Đọc xong thì tiếp tục
      await Future.delayed(
          const Duration(seconds: 1)); // Nghỉ 1 giây trước khi đọc lại
    }
  }

  Future<void> _speak() async {
    await _flutterTts.speak(_fullText); // Đọc cả thời gian và thông điệp
  }

  void _startVibration() async {
    if (await Vibration.hasVibrator() ?? false) {
      Vibration.vibrate(duration: 1300);
      _vibrationTimer = Timer.periodic(const Duration(seconds: 2), (_) {
        Vibration.vibrate(duration: 800);
      });
    }
  }

  void _stopAlarm() async {
    _isSpeaking = false;
    _vibrationTimer?.cancel();
    await _flutterTts.stop();
    await Vibration.cancel();
    await WakelockPlus.disable();

    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    if (mounted) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => const TextAlarmApp()),
      );
    }
  }

  @override
  void dispose() {
    _vibrationTimer?.cancel();
    _flutterTts.stop();
    Vibration.cancel();
    WakelockPlus.disable();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async => false,
      child: Scaffold(
        backgroundColor: const Color(0xFF1a0033),
        body: SafeArea(
          child: Stack(
            children: [
              Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0xFF2a0055), Colors.black87],
                  ),
                ),
              ),
              Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 40),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.alarm, size: 90, color: Colors.white70),
                      const SizedBox(height: 30),
                      Text(
                        widget.message,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 44,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                          height: 1.35,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Positioned(
                bottom: 70,
                left: 40,
                right: 40,
                child: ElevatedButton(
                  onPressed: _stopAlarm,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red.shade700,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 22),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                  ),
                  child: const Text(
                    'DỪNG BÁO THỨC',
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
