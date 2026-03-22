import 'dart:developer';
import 'dart:js_interop';

import 'package:client/services/trigram_language_detector.dart';

/// Feature-detect the LanguageDetector global (Chrome 138+).
@JS('LanguageDetector')
external JSAny? get _languageDetectorGlobal;

/// JS interop bindings for the Chrome Language Detector API (Chrome 138+).
@JS('LanguageDetector')
extension type _JSLanguageDetector._(JSObject _) implements JSObject {
  external static JSPromise<JSString> availability();
  external static JSPromise<_JSLanguageDetector> create();
  external JSPromise<JSArray<_JSDetectionResult>> detect(String input);
  external void destroy();
}

@JS()
extension type _JSDetectionResult._(JSObject _) implements JSObject {
  external String get detectedLanguage;
  external double get confidence;
}

/// On-device language detection for the web platform.
///
/// Uses the Chrome Language Detector API when available, falling back to a
/// pure-Dart trigram-based detector on other browsers.
class LanguageDetectionService {
  _JSLanguageDetector? _detector;
  bool _chromeApiUnavailable = false;
  final _trigramDetector = TrigramLanguageDetector();

  Future<_JSLanguageDetector?> _getDetector() async {
    if (_chromeApiUnavailable) return null;
    if (_detector != null) return _detector;
    try {
      // Check whether the global LanguageDetector class exists.
      if (_languageDetectorGlobal.isUndefinedOrNull) {
        _chromeApiUnavailable = true;
        return null;
      }
      final status = (await _JSLanguageDetector.availability().toDart).toDart;
      if (status == 'unavailable') {
        _chromeApiUnavailable = true;
        return null;
      }
      return _detector = await _JSLanguageDetector.create().toDart;
    } on Object catch (e) {
      log('Chrome Language Detector API init failed: $e');
      _chromeApiUnavailable = true;
      return null;
    }
  }

  /// Returns `true` when [text] appears to be in a different language than
  /// [userLanguage] (a BCP-47 primary subtag such as `"en"` or `"es"`).
  Future<bool> needsTranslation({
    required String text,
    required String userLanguage,
  }) async {
    // Try the Chrome Language Detector API first.
    final detector = await _getDetector();
    if (detector != null) {
      try {
        final results = (await detector.detect(text).toDart).toDart;
        if (results.isNotEmpty) {
          final best = results.first;
          if (best.detectedLanguage != 'und' && best.confidence >= 0.5) {
            return best.detectedLanguage != userLanguage;
          }
        }
      } on Object catch (e) {
        log('Chrome language detection failed: $e');
      }
    }

    // Fall back to the trigram detector — check whether the text matches the
    // user's language. If not, it needs translation regardless of what
    // language it actually is.
    return !_trigramDetector.isLanguage(text, userLanguage);
  }

  /// Returns the detected BCP-47 language code for [text], or `null` if
  /// detection is inconclusive.
  Future<String?> detectLanguage(String text) async {
    final detector = await _getDetector();
    if (detector != null) {
      try {
        final results = (await detector.detect(text).toDart).toDart;
        if (results.isNotEmpty) {
          final best = results.first;
          if (best.detectedLanguage != 'und' && best.confidence >= 0.5) {
            return best.detectedLanguage;
          }
        }
      } on Object catch (e) {
        log('Chrome detectLanguage failed: $e');
      }
    }
    final detected = _trigramDetector.detect(text);
    return detected == 'und' ? null : detected;
  }

  /// Releases resources held by the detector.
  Future<void> dispose() async {
    _detector?.destroy();
    _detector = null;
  }
}
