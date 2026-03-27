/// Compute all ancestor geoscopes for a given geoscope string.
/// E.g. `"na/us/ny/nyc"` → `['/', 'na', 'na/us', 'na/us/ny', 'na/us/ny/nyc']`.
List<String> geoscopeAncestors(String geoscope) {
  if (geoscope == '/') return ['/'];
  final parts = geoscope.split('/');
  return [
    '/',
    for (var i = 0; i < parts.length; i++) parts.sublist(0, i + 1).join('/'),
  ];
}
