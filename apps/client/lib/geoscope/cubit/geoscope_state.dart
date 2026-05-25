enum GeoscopeStatus { initial, loading, success, failure }

/// Transient status of an in-flight location lookup. `denied` and
/// `unavailable` outcomes signal via [GeoscopeState.locationDenied]
/// (persisted) and [GeoscopeState.pendingToast] (one-shot) respectively;
/// they don't need a sticky enum value here.
enum GeoscopeLocationStatus { idle, fetching }

/// One-shot toast signal consumed by the picker's BlocListener.
enum GeoscopeToast { denied, unavailable }

class GeoscopeState {
  const GeoscopeState({
    this.status = GeoscopeStatus.initial,
    this.selectedGeoscope = '/',
    this.availableGeoscopes = const [],
    this.needsSelection = false,
    this.locationStatus = GeoscopeLocationStatus.idle,
    this.locationSuggestion,
    this.pendingToast,
    this.locationDenied = false,
  });

  final GeoscopeStatus status;
  final String selectedGeoscope;
  final List<
    ({
      String id,
      String label,
      int population,
      double? lat,
      double? lng,
    })
  >
  availableGeoscopes;

  /// True when no geoscope has ever been explicitly chosen by the user — the
  /// current [selectedGeoscope] is either the global fallback or a locale
  /// inference. UI uses this to prompt for a first-time selection.
  final bool needsSelection;

  /// Transient state of an in-flight location lookup.
  final GeoscopeLocationStatus locationStatus;

  /// Set when the nearest metro is outside the auto-select threshold.
  /// The UI shows a confirmation row; tapping "Use" calls
  /// [GeoscopeCubit.acceptLocationSuggestion].
  final ({String id, double distanceKm})? locationSuggestion;

  /// One-shot toast signal, cleared by [GeoscopeCubit.clearPendingToast]
  /// after the listener fires.
  final GeoscopeToast? pendingToast;

  /// True if the user has ever denied OS location permission for this app.
  /// When true, the "Use my location" row is hidden in the picker.
  /// Persisted to SharedPreferences under `geoscope_location_denied`.
  final bool locationDenied;

  GeoscopeState copyWith({
    GeoscopeStatus? status,
    String? selectedGeoscope,
    List<
      ({
        String id,
        String label,
        int population,
        double? lat,
        double? lng,
      })
    >?
    availableGeoscopes,
    bool? needsSelection,
    GeoscopeLocationStatus? locationStatus,
    ({String id, double distanceKm})? locationSuggestion,
    bool clearLocationSuggestion = false,
    GeoscopeToast? pendingToast,
    bool clearPendingToast = false,
    bool? locationDenied,
  }) {
    return GeoscopeState(
      status: status ?? this.status,
      selectedGeoscope: selectedGeoscope ?? this.selectedGeoscope,
      availableGeoscopes: availableGeoscopes ?? this.availableGeoscopes,
      needsSelection: needsSelection ?? this.needsSelection,
      locationStatus: locationStatus ?? this.locationStatus,
      locationSuggestion: clearLocationSuggestion
          ? null
          : (locationSuggestion ?? this.locationSuggestion),
      pendingToast: clearPendingToast
          ? null
          : (pendingToast ?? this.pendingToast),
      locationDenied: locationDenied ?? this.locationDenied,
    );
  }
}
