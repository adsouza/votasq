enum GeoscopeStatus { initial, loading, success, failure }

class GeoscopeState {
  const GeoscopeState({
    this.status = GeoscopeStatus.initial,
    this.selectedGeoscope = '/',
    this.availableGeoscopes = const [],
    this.needsSelection = false,
  });

  final GeoscopeStatus status;
  final String selectedGeoscope;
  final List<({String id, String label})> availableGeoscopes;

  /// True when no geoscope has ever been explicitly chosen by the user — the
  /// current [selectedGeoscope] is either the global fallback or a locale
  /// inference. UI uses this to prompt for a first-time selection.
  final bool needsSelection;

  GeoscopeState copyWith({
    GeoscopeStatus? status,
    String? selectedGeoscope,
    List<({String id, String label})>? availableGeoscopes,
    bool? needsSelection,
  }) {
    return GeoscopeState(
      status: status ?? this.status,
      selectedGeoscope: selectedGeoscope ?? this.selectedGeoscope,
      availableGeoscopes: availableGeoscopes ?? this.availableGeoscopes,
      needsSelection: needsSelection ?? this.needsSelection,
    );
  }
}
