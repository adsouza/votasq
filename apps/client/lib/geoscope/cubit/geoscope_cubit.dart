import 'dart:developer';
import 'dart:ui';

import 'package:bloc/bloc.dart';
import 'package:client/geoscope/cubit/geoscope_state.dart';
import 'package:client/services/firestore_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

class GeoscopeCubit extends Cubit<GeoscopeState> {
  GeoscopeCubit(this._repo) : super(const GeoscopeState());

  final FirestoreRepository _repo;
  static const _prefsKey = 'selected_geoscope';

  /// Load persisted geoscope and available geoscopes.
  /// If no persisted value, infer from device locale region and flag the state
  /// as needing an explicit selection so the UI can prompt the user.
  Future<void> initialize() async {
    emit(state.copyWith(status: GeoscopeStatus.loading));
    try {
      final prefs = await SharedPreferences.getInstance();
      final persisted = prefs.getString(_prefsKey);
      final available = await _repo.getGeoscopes();
      final availableIds = {'/'}..addAll(available.map((g) => g.id));
      final geoscope = _resolveGeoscope(persisted, availableIds);
      // Only persist when migrating a stale stored value (e.g. "us" → "na/us").
      // Don't persist the locale-inferred default — the absence of a stored
      // value is what tells us the user still hasn't explicitly picked.
      if (persisted != null && geoscope != persisted) {
        await prefs.setString(_prefsKey, geoscope);
      }
      emit(
        state.copyWith(
          status: GeoscopeStatus.success,
          selectedGeoscope: geoscope,
          availableGeoscopes: available,
          needsSelection: persisted == null,
        ),
      );
    } on Exception catch (e, st) {
      log('GeoscopeCubit.initialize failed: $e', stackTrace: st);
      emit(state.copyWith(status: GeoscopeStatus.failure));
    }
  }

  /// Select a geoscope and persist the choice.
  Future<void> selectGeoscope(String geoscope) async {
    emit(state.copyWith(selectedGeoscope: geoscope, needsSelection: false));
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, geoscope);
  }

  /// Mark the first-time selection prompt as shown without persisting a choice.
  /// Stops the picker from re-opening on every rebuild within this session;
  /// the next cold start will prompt again until [selectGeoscope] is called.
  void acknowledgeSelectionPrompt() {
    if (state.needsSelection) {
      emit(state.copyWith(needsSelection: false));
    }
  }

  /// Resolve the best geoscope to use given a persisted value and the set of
  /// available geoscope IDs. If [persisted] is still valid, use it. Otherwise,
  /// try to find an available geoscope whose path ends with the persisted value
  /// (handles hierarchy changes, e.g. "us" → "na/us"). Falls back to locale
  /// inference with the same suffix-match logic, then to `'/'`.
  static String _resolveGeoscope(String? persisted, Set<String> availableIds) {
    if (persisted != null && availableIds.contains(persisted)) {
      return persisted;
    }
    // Try suffix match for persisted value (e.g. "us" matches "na/us").
    if (persisted != null && persisted != '/') {
      final suffix = '/$persisted';
      final match = availableIds.where((id) => id.endsWith(suffix)).firstOrNull;
      if (match != null) return match;
    }
    // Fall back to locale inference.
    final inferred = _inferFromLocale();
    if (availableIds.contains(inferred)) return inferred;
    final suffix = '/$inferred';
    final match = availableIds.where((id) => id.endsWith(suffix)).firstOrNull;
    if (match != null) return match;
    return '/';
  }

  /// Infer a country-level geoscope from the device locale's country code.
  /// Falls back to `'/'` (global) if unavailable.
  static String _inferFromLocale() {
    final locale = PlatformDispatcher.instance.locale;
    final country = locale.countryCode?.toLowerCase();
    if (country == null || country.isEmpty) return '/';
    return country;
  }
}
