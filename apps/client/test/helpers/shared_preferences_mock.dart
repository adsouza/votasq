import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Mock implementation of SharedPreferencesWithCache for testing.
class MockSharedPreferencesWithCache extends Mock
    implements SharedPreferencesWithCache {
  final Map<String, Object> _store = {};

  void _initialize({Map<String, Object> initialValues = const {}}) {
    _store.addAll(initialValues);
  }

  @override
  bool? getBool(String key) => _store[key] as bool?;

  @override
  double? getDouble(String key) => _store[key] as double?;

  @override
  int? getInt(String key) => _store[key] as int?;

  @override
  String? getString(String key) => _store[key] as String?;

  @override
  List<String>? getStringList(String key) => _store[key] as List<String>?;

  Set<String> getKeys() => _store.keys.toSet();

  @override
  Future<bool> setBool(String key, bool value) async {
    _store[key] = value;
    return true;
  }

  @override
  Future<bool> setDouble(String key, double value) async {
    _store[key] = value;
    return true;
  }

  @override
  Future<bool> setInt(String key, int value) async {
    _store[key] = value;
    return true;
  }

  @override
  Future<bool> setString(String key, String value) async {
    _store[key] = value;
    return true;
  }

  @override
  Future<bool> setStringList(String key, List<String> value) async {
    _store[key] = value;
    return true;
  }

  @override
  Future<bool> clear() async {
    _store.clear();
    return true;
  }

  @override
  Future<bool> remove(String key) async {
    _store.remove(key);
    return true;
  }
}

// Store the mock instance globally so it can be reused
late MockSharedPreferencesWithCache _mockInstance;

/// Creates and returns a mock SharedPreferencesWithCache for use in tests.
/// Should be passed to AutoTranslateCubit constructor when testing.
MockSharedPreferencesWithCache createMockSharedPreferences({
  Map<String, Object> initialValues = const {},
}) {
  _mockInstance = MockSharedPreferencesWithCache();
  _mockInstance._initialize(initialValues: initialValues);
  return _mockInstance;
}

/// Sets up mocks for SharedPreferences in tests.
/// Call this in setUp() before creating instances of cubits or widgets
/// that use SharedPreferencesAsync. This is mainly for backwards compatibility
/// with existing tests that expect this function.
void setupSharedPreferencesMocks({
  Map<String, Object> initialValues = const {},
}) {
  createMockSharedPreferences(initialValues: initialValues);
}
