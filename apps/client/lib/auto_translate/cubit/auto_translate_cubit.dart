import 'dart:async';

import 'package:bloc/bloc.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AutoTranslateCubit extends Cubit<bool> {
  AutoTranslateCubit({bool initial = false}) : super(initial) {
    unawaited(_initialize());
  }

  static SharedPreferencesWithCache? _prefs;
  static const _prefsKey = 'auto_translate';

  Future<void> _initialize() async {
    _prefs = await SharedPreferencesWithCache.create(
      cacheOptions: const SharedPreferencesWithCacheOptions(
        allowList: {_prefsKey},
      ),
    );
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
