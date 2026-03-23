import 'package:bloc_test/bloc_test.dart';
import 'package:client/auto_translate/auto_translate.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('AutoTranslateCubit', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('initial state is false', () {
      expect(AutoTranslateCubit().state, isFalse);
    });

    test('initial state respects parameter', () {
      expect(AutoTranslateCubit(initial: true).state, isTrue);
    });

    blocTest<AutoTranslateCubit, bool>(
      'toggle flips state and persists',
      build: AutoTranslateCubit.new,
      act: (cubit) => cubit.toggle(),
      expect: () => [true],
      verify: (_) async {
        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getBool('auto_translate'), isTrue);
      },
    );

    blocTest<AutoTranslateCubit, bool>(
      'double toggle returns to false',
      build: AutoTranslateCubit.new,
      act: (cubit) async {
        await cubit.toggle();
        await cubit.toggle();
      },
      expect: () => [true, false],
    );

    test('loads persisted value on creation', () async {
      SharedPreferences.setMockInitialValues({'auto_translate': true});
      final cubit = AutoTranslateCubit();
      // Wait for _load() to complete.
      await Future<void>.delayed(Duration.zero);
      expect(cubit.state, isTrue);
      await cubit.close();
    });
  });
}
