import 'package:bloc_test/bloc_test.dart';
import 'package:client/settings/settings.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/helpers.dart';

void main() {
  group('RecencyFilterCubit', () {
    late MockSharedPreferencesWithCache mockPrefs;

    setUp(() {
      mockPrefs = createMockSharedPreferences();
    });

    test('initial state is 0 (any time / filter off)', () {
      expect(
        RecencyFilterCubit(prefsForTesting: mockPrefs).state,
        0,
      );
    });

    test('initial state respects parameter', () {
      expect(
        RecencyFilterCubit(initial: 7, prefsForTesting: mockPrefs).state,
        7,
      );
    });

    test('allowedDays exposes seven steps in ascending order, off-first', () {
      expect(RecencyFilterCubit.allowedDays, [0, 1, 3, 7, 15, 31, 91]);
    });

    blocTest<RecencyFilterCubit, int>(
      'setMaxAgeDays emits and persists',
      build: () => RecencyFilterCubit(prefsForTesting: mockPrefs),
      act: (cubit) => cubit.setMaxAgeDays(7),
      expect: () => [7],
      verify: (_) async {
        expect(mockPrefs.getInt('recency_filter_days'), 7);
      },
    );

    blocTest<RecencyFilterCubit, int>(
      'setMaxAgeDays back to 0 turns the filter off and persists',
      build: () => RecencyFilterCubit(initial: 31, prefsForTesting: mockPrefs),
      act: (cubit) => cubit.setMaxAgeDays(0),
      expect: () => [0],
      verify: (_) async {
        expect(mockPrefs.getInt('recency_filter_days'), 0);
      },
    );

    test('loads persisted value on creation', () async {
      final mockPrefsWithValue = createMockSharedPreferences(
        initialValues: {'recency_filter_days': 15},
      );
      final cubit = RecencyFilterCubit(prefsForTesting: mockPrefsWithValue);
      // Wait for _initialize() to complete.
      await Future<void>.delayed(Duration.zero);
      expect(cubit.state, 15);
      await cubit.close();
    });

    test('survives missing shared_preferences platform', () async {
      // Construct without prefsForTesting — forces the real
      // SharedPreferencesWithCache.create path, which throws in this test
      // environment because no platform plugin is bound. The try/catch in
      // _initialize must swallow that and leave the cubit at its default.
      final cubit = RecencyFilterCubit();
      await Future<void>.delayed(Duration.zero);
      expect(cubit.state, 0);
      await cubit.close();
    });
  });
}
