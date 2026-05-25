import 'package:bloc_test/bloc_test.dart';
import 'package:client/settings/settings.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/helpers.dart';

void main() {
  group('TextScaleCubit', () {
    late MockSharedPreferencesWithCache mockPrefs;

    setUp(() {
      mockPrefs = createMockSharedPreferences();
    });

    test('initial state is 1.0 (default scale)', () {
      expect(
        TextScaleCubit(prefsForTesting: mockPrefs).state,
        1.0,
      );
    });

    test('initial state respects parameter', () {
      expect(
        TextScaleCubit(initial: 1.15, prefsForTesting: mockPrefs).state,
        1.15,
      );
    });

    test('allowedScales exposes five steps in ascending order', () {
      expect(TextScaleCubit.allowedScales, [0.85, 1.0, 1.15, 1.30, 1.50]);
    });

    blocTest<TextScaleCubit, double>(
      'setScale emits and persists',
      build: () => TextScaleCubit(prefsForTesting: mockPrefs),
      act: (cubit) => cubit.setScale(1.30),
      expect: () => [1.30],
      verify: (_) async {
        expect(mockPrefs.getDouble('text_scale'), 1.30);
      },
    );

    blocTest<TextScaleCubit, double>(
      'setScale to current value still persists',
      build: () => TextScaleCubit(prefsForTesting: mockPrefs),
      act: (cubit) async {
        await cubit.setScale(1.15);
        await cubit.setScale(1.15);
      },
      // Cubit dedupes identical emits, so only one state appears.
      expect: () => [1.15],
      verify: (_) async {
        expect(mockPrefs.getDouble('text_scale'), 1.15);
      },
    );

    test('loads persisted value on creation', () async {
      final mockPrefsWithValue = createMockSharedPreferences(
        initialValues: {'text_scale': 1.50},
      );
      final cubit = TextScaleCubit(prefsForTesting: mockPrefsWithValue);
      // Wait for _initialize() to complete.
      await Future<void>.delayed(Duration.zero);
      expect(cubit.state, 1.50);
      await cubit.close();
    });

    test('survives missing shared_preferences platform', () async {
      // Construct without prefsForTesting — forces the real
      // SharedPreferencesWithCache.create path, which throws in this test
      // environment because no platform plugin is bound. The try/catch in
      // _initialize must swallow that and leave the cubit at its default.
      // Regression guard: this is the bug that crashed app_test.dart when
      // BlocBuilder<TextScaleCubit> eagerly read the cubit in
      // MaterialApp.builder.
      final cubit = TextScaleCubit();
      // Let _initialize() complete (and its catch fire).
      await Future<void>.delayed(Duration.zero);
      expect(cubit.state, 1.0);
      await cubit.close();
    });
  });
}
