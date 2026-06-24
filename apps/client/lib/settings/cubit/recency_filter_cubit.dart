import 'dart:async';

import 'package:bloc/bloc.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Holds the user's "show only problems updated within the last N days"
/// filter for the problems listing, and persists it across launches via
/// SharedPreferences.
///
/// The state is the maximum age in days; `0` means "any time" (the filter is
/// off). The dialog UI exposes a seven-step slider over [allowedDays]; the
/// chosen value is applied client-side in `ProblemsView._applyFilters`
/// against each `Problem.lastUpdatedAt`. Because the listing is ordered
/// votes-first and filtered over a paginated window, this surfaces recent
/// problems among the items already loaded — it is not a server-side query
/// over the whole collection.
///
/// Mirrors `TextScaleCubit`'s persistence shape: any value can be set
/// programmatically too, in which case persistence still works —
/// [allowedDays] is purely the UI's discrete affordance.
class RecencyFilterCubit extends Cubit<int> {
  RecencyFilterCubit({
    int initial = 0,
    SharedPreferencesWithCache? prefsForTesting,
  }) : super(initial) {
    _prefsForTesting = prefsForTesting;
    unawaited(_initialize());
  }

  /// The seven discrete steps the in-app slider exposes, in ascending order.
  /// `0` is the "any time" / off position; the rest are day thresholds. The
  /// corresponding labels live in the l10n bundle under `recencyFilterAnyTime`
  /// (for `0`) and `recencyFilterWithinDays` (a plural over the day count).
  static const List<int> allowedDays = [0, 1, 3, 7, 15, 31, 91];

  static SharedPreferencesWithCache? _prefs;
  static SharedPreferencesWithCache? _prefsForTesting;
  static const _prefsKey = 'recency_filter_days';

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
        // profile, or sandboxing edge case — fall back to "any time". The
        // cubit stays usable in-memory; writes via setMaxAgeDays just don't
        // persist this session.
        _prefs = null;
      }
    }
    final persisted = _prefs?.getInt(_prefsKey);
    if (persisted != null) emit(persisted);
  }

  Future<void> setMaxAgeDays(int days) async {
    emit(days);
    if (_prefs != null) {
      await _prefs!.setInt(_prefsKey, days);
    }
  }
}
