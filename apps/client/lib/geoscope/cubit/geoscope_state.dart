enum GeoscopeStatus { initial, loading, success, failure }

class GeoscopeState {
  const GeoscopeState({
    this.status = GeoscopeStatus.initial,
    this.selectedGeoscope = '/',
    this.availableGeoscopes = const [],
  });

  final GeoscopeStatus status;
  final String selectedGeoscope;
  final List<({String id, String label})> availableGeoscopes;

  GeoscopeState copyWith({
    GeoscopeStatus? status,
    String? selectedGeoscope,
    List<({String id, String label})>? availableGeoscopes,
  }) {
    return GeoscopeState(
      status: status ?? this.status,
      selectedGeoscope: selectedGeoscope ?? this.selectedGeoscope,
      availableGeoscopes: availableGeoscopes ?? this.availableGeoscopes,
    );
  }
}
