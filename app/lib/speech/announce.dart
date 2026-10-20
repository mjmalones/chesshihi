import 'package:flutter_tts/flutter_tts.dart';

/// Spoken best-move output (TTS; VoiceOver-friendly announcements later).
class MoveAnnouncer {
  MoveAnnouncer() : _tts = FlutterTts();

  final FlutterTts _tts;
  bool _ready = false;

  Future<void> ensureReady() async {
    if (_ready) return;
    await _tts.setLanguage('en-US');
    await _tts.setSpeechRate(0.45);
    await _tts.setVolume(1.0);
    await _tts.setPitch(1.0);
    _ready = true;
  }

  Future<void> speak(String text) async {
    await ensureReady();
    await _tts.stop();
    await _tts.speak(text);
  }

  Future<void> dispose() async {
    await _tts.stop();
  }
}
