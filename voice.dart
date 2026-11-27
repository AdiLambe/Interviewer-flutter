// Interviewer ki awaaz (TTS) aur aapka jawab sunna (STT).
//
// Mic "dictation mode" mein chalta hai: Android ka recognizer 2-3 second chup rehne
// par khud band ho jata hai, isliye hum turant naya session shuru karke saara text
// jodte rehte hain - jab tak user STOP/SEND na dabaye ya max time (default 1.5 min)
// na ho jaye. Lambe descriptive jawab ke liye.
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';

bool get isAndroid =>
    !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

/// Do text jodna, beech mein ek space
String joinText(String a, String b) {
  a = a.trim();
  b = b.trim();
  if (a.isEmpty) return b;
  if (b.isEmpty) return a;
  return '$a $b';
}

class Voice {
  final FlutterTts _tts = FlutterTts();
  final SpeechToText _stt = SpeechToText();
  bool _sttReady = false;
  bool _ttsReady = false;

  // ---- dictation state ----
  bool _dictating = false;
  void Function()? _sessionEnd; // current session khatam hone par
  String? _fatalError; // permission jaisa error: dobara try mat karo

  bool get canListen => _sttReady;

  /// Sirf tests ke liye: asli mic ki jagah nakli recognizer session.
  @visibleForTesting
  Future<void> Function(
    void Function(String words, bool isFinal) onResult,
    Duration remaining,
  )?
  debugSession;
  @visibleForTesting
  set debugReady(bool v) => _sttReady = v;
  @visibleForTesting
  void debugEndSession() => _endSession();
  bool get isDictating => _dictating;

  Future<void> init() async {
    try {
      await _tts.awaitSpeakCompletion(true).timeout(const Duration(seconds: 5));
      _ttsReady = true;
    } catch (e) {
      debugPrint('TTS init error $e');
    }
    try {
      _sttReady = await _stt
          .initialize(
            onError: _onError,
            onStatus: (s) {
              if (s == 'done' || s == 'notListening') _endSession();
            },
          )
          .timeout(const Duration(seconds: 8), onTimeout: () => false);
    } catch (e) {
      debugPrint('STT init error $e');
      _sttReady = false;
    }
  }

  void _onError(SpeechRecognitionError e) {
    debugPrint('STT error ${e.errorMsg} permanent=${e.permanent}');
    // no_match / speech_timeout = kuch suna nahi, bas agla session chalao
    const harmless = [
      'error_no_match',
      'error_speech_timeout',
      'error_client',
      'error_busy',
    ];
    if (!harmless.contains(e.errorMsg) &&
        (e.errorMsg.contains('permission') || e.errorMsg.contains('audio'))) {
      _fatalError = e.errorMsg;
    }
    _endSession();
  }

  void _endSession() {
    final f = _sessionEnd;
    _sessionEnd = null;
    if (f != null) f();
  }

  /// Bolta hai aur bolna khatam hone tak wait karta hai.
  /// TTS kabhi atak jaye toh app na ruke: max time ke baad aage badho.
  Future<void> speak(
    String text, {
    String lang = 'en-IN',
    double pitch = 0.8,
    double rate = 0.48,
  }) async {
    debugPrint('[BOT] $text');
    if (!_ttsReady) return;
    Future<void> run() async {
      await _tts.setLanguage(lang);
      await _tts.setPitch(pitch); // kam pitch = male awaaz
      await _tts.setSpeechRate(rate);
      await _tts.speak(text);
    }

    try {
      await run().timeout(Duration(milliseconds: 4000 + text.length * 120));
    } catch (e) {
      debugPrint('TTS error/timeout $e');
    }
  }

  Future<void> stopSpeaking() async {
    try {
      await _tts.stop().timeout(const Duration(seconds: 2));
    } catch (_) {}
  }

  /// Sab band: bolna aur sunna.
  Future<void> stop() async {
    await stopSpeaking();
    await stopDictation();
  }

  /// Lamba jawab suno. [onText] har naye shabd par poora text deta hai.
  /// Return: final text ('' = kuch nahi suna). User [stopDictation] se rok sakta hai.
  Future<String> dictate({
    required void Function(String text) onText,
    Duration maxDuration = const Duration(seconds: 90),
    String localeId = 'en_IN',
  }) async {
    if (!_sttReady || _dictating) return '';
    await stopSpeaking();
    _dictating = true;
    _fatalError = null;
    final deadline = DateTime.now().add(maxDuration);
    var committed = '';

    while (_dictating && DateTime.now().isBefore(deadline)) {
      final remaining = deadline.difference(DateTime.now());
      var session = '';
      final done = Completer<void>();
      _sessionEnd = () {
        if (!done.isCompleted) done.complete();
      };
      try {
        void onRes(String words, bool isFinal) {
          session = words;
          onText(joinText(committed, session));
          if (isFinal) _endSession();
        }

        if (debugSession != null) {
          await debugSession!(onRes, remaining);
        } else {
          await _stt.listen(
            onResult: (SpeechRecognitionResult r) =>
                onRes(r.recognizedWords, r.finalResult),
            listenOptions: SpeechListenOptions(
              localeId: localeId,
              listenFor: remaining,
              pauseFor: remaining, // lambi chuppi par bhi band na ho (Android jitna allow kare)
              partialResults: true,
              cancelOnError: false,
              listenMode: ListenMode.dictation,
            ),
          );
        }
        await done.future.timeout(
          remaining + const Duration(seconds: 2),
          onTimeout: () {},
        );
      } catch (e) {
        debugPrint('STT listen error $e');
        await Future.delayed(const Duration(milliseconds: 400));
      }
      committed = joinText(committed, session);
      onText(committed);
      if (_fatalError != null) break;
      // Android ko agla session shuru karne ke liye thoda waqt
      if (_dictating) await Future.delayed(const Duration(milliseconds: 250));
    }

    _dictating = false;
    _sessionEnd = null;
    try {
      if (_stt.isListening) {
        await _stt.stop().timeout(const Duration(seconds: 2));
      }
    } catch (_) {}
    return committed;
  }

  /// Mic band (user ne STOP/SEND dabaya). Jo bola woh rakha jata hai.
  Future<void> stopDictation() async {
    if (!_dictating) return;
    _dictating = false;
    try {
      // stop() = abhi tak ka final result deta hai (cancel() nahi)
      await _stt.stop().timeout(const Duration(seconds: 2));
    } catch (_) {}
    // final result aane ka thoda intezaar, phir session band
    await Future.delayed(const Duration(milliseconds: 300));
    _endSession();
  }

  String? get lastFatalError => _fatalError;
}
