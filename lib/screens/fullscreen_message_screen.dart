// screens/fullscreen_message_screen.dart
import 'package:flutter/material.dart';
import 'package:vibration/vibration.dart';
import 'package:flutter/services.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'dart:async';
import '../main.dart';

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
  final MethodChannel _volumeChannel =
      const MethodChannel('com.nhaclich.ring/volume');

  Timer? _vibrationTimer;
  bool _isSpeaking = true;
  bool _shouldContinueSpeaking = true;

  late final String _fullText;

  @override
  void initState() {
    super.initState();
    WakelockPlus.enable();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

    // Tạo nội dung đầy đủ
    final now = DateTime.now();
    final timeStr =
        "${now.hour} giờ ${now.minute.toString().padLeft(2, '0')} phút";
    _fullText = "Bây giờ là $timeStr. ${widget.message}";

    _initTtsAndVolume();
    _startSpeakingLoop();

    if (widget.isVibrationEnabled) {
      _startVibration();
    }
  }

  Future<void> _initTtsAndVolume() async {
    try {
      await _volumeChannel.invokeMethod('setAlarmVolume');
    } catch (e) {
      print("Không set được alarm volume: $e");
    }

    // Cấu hình TTS
    await _flutterTts.setLanguage("vi-VN");
    await _flutterTts.setSpeechRate(0.5);
    await _flutterTts.setVolume(1.0);
    await _flutterTts.setPitch(1.0);

    // Quan trọng: lắng nghe khi đọc xong 1 lần
    _flutterTts.setCompletionHandler(() {
      if (mounted && _shouldContinueSpeaking && _isSpeaking) {
        _speak(); // Đọc lại ngay khi hoàn thành lần trước
      }
    });

    // Optional: lắng nghe lỗi hoặc cancel để debug
    _flutterTts.setErrorHandler((msg) {
      print("TTS error: $msg");
    });
  }

  void _startSpeakingLoop() {
    _speak(); // Bắt đầu lần đầu tiên
  }

  Future<void> _speak() async {
    if (!_isSpeaking || !_shouldContinueSpeaking) return;

    try {
      await _flutterTts.speak(_fullText);
      // Không cần await awaitSpeakCompletion nữa vì ta dùng completion handler
    } catch (e) {
      print("Lỗi khi speak: $e");
    }
  }

  void _startVibration() async {
    if (await Vibration.hasVibrator() ?? false) {
      Vibration.vibrate(duration: 1300);
      _vibrationTimer = Timer.periodic(const Duration(seconds: 2), (_) {
        if (_isSpeaking) {
          Vibration.vibrate(duration: 800);
        }
      });
    }
  }

  void _stopAlarm() async {
    _isSpeaking = false;
    _shouldContinueSpeaking = false;

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
    _shouldContinueSpeaking = false;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async => false,
      child: Scaffold(
        backgroundColor: const Color(0xFF1a0033),
        floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
        floatingActionButton: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          child: ElevatedButton(
            onPressed: _stopAlarm,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red.shade700,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(28),
              ),
              elevation: 8,
              minimumSize:
                  const Size(double.infinity, 70), // rộng full nếu muốn
            ),
            child: const Text(
              'DỪNG BÁO THỨC',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.2,
              ),
            ),
          ),
        ),
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
              Container(
                  width: double.infinity,
                  height: 570,
                  child: SingleChildScrollView(
                    child: Center(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 40),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(
                              Icons.alarm,
                              size: 90,
                              color: Colors.white70,
                            ),
                            const SizedBox(height: 30),
                            Text(
                              widget.message,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontSize: 35,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                                height: 1.35,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  )),
            ],
          ),
        ),
      ),
    );
  }
}
