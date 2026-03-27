import 'package:bloc_test/bloc_test.dart';
import 'package:client/auto_translate/auto_translate.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/helpers.dart';

void main() {
  group('AutoTranslateCubit', () {
    late MockSharedPreferencesWithCache mockPrefs;

    setUp(() {
      mockPrefs = createMockSharedPreferences();
    });

    test('initial state is false', () {
      expect(
        AutoTranslateCubit(prefsForTesting: mockPrefs).state,
        isFalse,
      );
    });

    test('initial state respects parameter', () {
      expect(
        AutoTranslateCubit(initial: true, prefsForTesting: mockPrefs).state,
        isTrue,
      );
    });

    blocTest<AutoTranslateCubit, bool>(
      'toggle flips state and persists',
      build: () => AutoTranslateCubit(prefsForTesting: mockPrefs),
      act: (cubit) => cubit.toggle(),
      expect: () => [true],
      verify: (_) async {
        expect(mockPrefs.getBool('auto_translate'), isTrue);
      },
    );

    blocTest<AutoTranslateCubit, bool>(
      'double toggle returns to false',
      build: () => AutoTranslateCubit(prefsForTesting: mockPrefs),
      act: (cubit) async {
        await cubit.toggle();
        await cubit.toggle();
      },
      expect: () => [true, false],
    );

    test('loads persisted value on creation', () async {
      final mockPrefsWithValue = createMockSharedPreferences(
        initialValues: {'auto_translate': true},
      );
      final cubit = AutoTranslateCubit(prefsForTesting: mockPrefsWithValue);
      // Wait for _load() to complete.
      await Future<void>.delayed(Duration.zero);
      expect(cubit.state, isTrue);
      await cubit.close();
    });
  });
}
