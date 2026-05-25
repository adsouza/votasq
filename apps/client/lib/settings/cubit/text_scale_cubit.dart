import 'dart:async';

import 'package:bloc/bloc.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Holds the user's preferred text-scale factor (1.0 = default, larger = bigger
/// text) and persists it across launches via SharedPreferences.
///
/// Wraps a `Cubit<double>` so the app root can wrap `MaterialApp` in a
/// `MediaQuery` override of `textScaler: TextScaler.linear(state)` and have
/// every `Text` / `textTheme.*` widget pick the scale up automatically.
///
/// The dialog UI exposes a five-step slider over [allowedScales]; any other
/// value can be set programmatically too, in which case persistence still
/// works — `allowedScales` is purely the UI's discrete affordance.
class TextScaleCubit extends Cubit<double> {
  TextScaleCubit({
    double initial = 1.0,
    SharedPreferencesWithCache? prefsForTesting,
  }) : super(initial) {
    _prefsForTesting = prefsForTesting;
    unawaited(_initialize());
  }

  /// The five discrete scale steps the in-app slider exposes: 0.85x, 1.0x,
  /// 1.15x, 1.30x, 1.50x. The corresponding labels live in the l10n bundle
  /// under `textSizeOption{Small,Default,Large,XLarge,XXLarge}`.
  static const List<double> allowedScales = [0.85, 1.0, 1.15, 1.30, 1.50];

  static SharedPreferencesWithCache? _prefs;
  static SharedPreferencesWithCache? _prefsForTesting;
  static const _prefsKey = 'text_scale';

  Future<void> _initialize() async {
    if (_prefsForTesting != null) {
      _prefs = _prefsForTesting;
    } else {
      try {
        _prefs = await SharedPreferencesWithCache.create(
          cacheOptions: const SharedPreferencesWithCacheOptions(
            allowList: {_prefsKey},
          ),
        );
      } on Object {
        // No platform plugin (e.g. unit tests that don't bind one), corrupted
        // profile, or sandboxing edge case — fall back to the default scale.
        // The cubit stays usable in-memory; writes via setScale just don't
        // persist this session.
        _prefs = null;
      }
    }
    final persisted = _prefs?.getDouble(_prefsKey);
    if (persisted != null) emit(persisted);
  }

  Future<void> setScale(double value) async {
    emit(value);
    if (_prefs != null) {
      await _prefs!.setDouble(_prefsKey, value);
    }
  }
}
