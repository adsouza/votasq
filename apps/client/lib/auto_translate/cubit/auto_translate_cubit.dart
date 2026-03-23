import 'dart:async';

import 'package:bloc/bloc.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AutoTranslateCubit extends Cubit<bool> {
  AutoTranslateCubit({bool initial = false}) : super(initial) {
    unawaited(_load());
  }

  static const _prefsKey = 'auto_translate';

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final persisted = prefs.getBool(_prefsKey);
    if (persisted != null) emit(persisted);
  }

  Future<void> toggle() async {
    final newValue = !state;
    emit(newValue);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefsKey, newValue);
  }
}
