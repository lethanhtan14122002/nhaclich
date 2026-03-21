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
  Timer? _speechTimer;
  bool _isSpeaking = true;

  late final String _fullText;

  @override
  void initState() {
    super.initState();
    WakelockPlus.enable();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

    // Tạo câu nói đầy đủ chỉ 1 lần
    final now = DateTime.now();
    final timeStr =
        "${now.hour} giờ ${now.minute.toString().padLeft(2, '0')} phút";
    _fullText = "Bây giờ là $timeStr. ${widget.message}";

    _initTtsAndVolume();
    _startSpeaking();

    if (widget.isVibrationEnabled) {
      _startVibration();
    }
  }

  Future<void> _initTtsAndVolume() async {
    // Buộc dùng âm lượng báo thức (Alarm Volume)
    try {
      await _volumeChannel.invokeMethod('setAlarmVolume');
    } catch (e) {
      print("Không set được alarm volume: $e");
    }

    await _flutterTts.setLanguage("vi-VN");
    await _flutterTts.setSpeechRate(0.73);
    await _flutterTts.setVolume(1.0);
    await _flutterTts.setPitch(1.0);
    await _flutterTts.awaitSpeakCompletion(true);
  }

  void _startSpeaking() {
    _speak();

    _speechTimer = Timer.periodic(const Duration(milliseconds: 2500), (_) {
      if (mounted && _isSpeaking) {
        _speak();
      }
    });
  }

  Future<void> _speak() async {
    if (!_isSpeaking) return;
    await _flutterTts.speak(_fullText);
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
    _speechTimer?.cancel();
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
    _speechTimer?.cancel();
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
