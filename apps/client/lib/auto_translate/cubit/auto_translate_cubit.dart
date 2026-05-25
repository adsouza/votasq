import 'dart:async';

import 'package:bloc/bloc.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AutoTranslateCubit extends Cubit<bool> {
  AutoTranslateCubit({
    bool initial = false,
    SharedPreferencesWithCache? prefsForTesting,
  }) : super(initial) {
    _prefsForTesting = prefsForTesting;
    unawaited(_initialize());
  }

  static SharedPreferencesWithCache? _prefs;
  static SharedPreferencesWithCache? _prefsForTesting;
  static const _prefsKey = 'auto_translate';

  Future<void> _initialize() async {
    // Use injected instance for testing, otherwise create real instance
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
        // profile, or sandboxing edge case — fall back to the in-memory
        // default. Toggle still works this session; it just doesn't persist.
        _prefs = null;
      }
    }
    final persisted = _prefs?.getBool(_prefsKey);
    if (persisted != null) emit(persisted);
  }

  Future<void> toggle() async {
    final newValue = !state;
    emit(newValue);
    if (_prefs != null) {
      await _prefs!.setBool(_prefsKey, newValue);
    }
  }
}
