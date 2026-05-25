import 'dart:developer';
import 'dart:math' as math;
import 'dart:ui';

import 'package:bloc/bloc.dart';
import 'package:client/geoscope/cubit/geoscope_state.dart';
import 'package:client/services/firestore_repository.dart';
import 'package:meta/meta.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Superstates whose 2-part children are countries (e.g. `eu/fr` = France),
/// rather than subdivisions of a single country. Locale-based inference looks
/// here when the bare country code (e.g. `fr`) has no top-level row, so an
/// `en-CA` user lands at `/` rather than `us/ca` (California, a US state).
const _countryContainingSuperstateIds = {'eu', 'scm', 'sea', 'las'};

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
      final geoscope = resolveGeoscope(
        persisted: persisted,
        inferred: _inferFromLocale(),
        availableIds: availableIds,
      );
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

  /// Resolve the best geoscope to use given the inputs. Pure function:
  /// [inferred] is computed by the caller (typically via [_inferFromLocale])
  /// so the resolution logic can be unit-tested with arbitrary locales.
  ///
  /// Resolution order:
  /// 1. [persisted] if it's still a valid id.
  /// 2. Any id ending in `/$persisted` (handles hierarchy reshapes like
  ///    `us` → `na/us`).
  /// 3. [inferred] if it's a valid 1-part id (e.g. `us`, `ca`).
  /// 4. `<superstate>/<inferred>` for each [_countryContainingSuperstateIds]
  ///    (e.g. `eu/fr`). Restricted to country-containing superstates so a
  ///    locale country code never matches a subdivision id like `us/ca`.
  /// 5. `'/'` (global).
  @visibleForTesting
  static String resolveGeoscope({
    required String? persisted,
    required String inferred,
    required Set<String> availableIds,
  }) {
    if (persisted != null && availableIds.contains(persisted)) {
      return persisted;
    }
    if (persisted != null && persisted != '/') {
      final suffix = '/$persisted';
      final match = availableIds.where((id) => id.endsWith(suffix)).firstOrNull;
      if (match != null) return match;
    }
    if (inferred == '/') return '/';
    if (availableIds.contains(inferred)) return inferred;
    for (final superstate in _countryContainingSuperstateIds) {
      final candidate = '$superstate/$inferred';
      if (availableIds.contains(candidate)) return candidate;
    }
    return '/';
  }

  /// Earth radius in km, used by [findNearestMetro].
  static const _earthRadiusKm = 6371.0;

  /// Returns the metro in [available] closest to ([lat], [lng]), or null
  /// if no row carries both `lat` and `lng`. Threshold logic is the
  /// caller's responsibility — this function always returns the absolute
  /// nearest if any candidate exists.
  @visibleForTesting
  static ({String id, double distanceKm})? findNearestMetro({
    required double lat,
    required double lng,
    required List<
      ({
        String id,
        String label,
        int population,
        double? lat,
        double? lng,
      })
    >
    available,
  }) {
    ({String id, double distanceKm})? best;
    for (final g in available) {
      final gLat = g.lat;
      final gLng = g.lng;
      if (gLat == null || gLng == null) continue;
      final d = _haversineKm(lat, lng, gLat, gLng);
      if (best == null || d < best.distanceKm) {
        best = (id: g.id, distanceKm: d);
      }
    }
    return best;
  }

  static double _haversineKm(
    double lat1,
    double lng1,
    double lat2,
    double lng2,
  ) {
    final dLat = _toRadians(lat2 - lat1);
    final dLng = _toRadians(lng2 - lng1);
    final a =
        math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_toRadians(lat1)) *
            math.cos(_toRadians(lat2)) *
            math.sin(dLng / 2) *
            math.sin(dLng / 2);
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return _earthRadiusKm * c;
  }

  static double _toRadians(double deg) => deg * math.pi / 180;

  /// Infer a country-level geoscope from the device locale's country code.
  /// Falls back to `'/'` (global) if unavailable.
  static String _inferFromLocale() {
    final locale = PlatformDispatcher.instance.locale;
    final country = locale.countryCode?.toLowerCase();
    if (country == null || country.isEmpty) return '/';
    return country;
  }
}
