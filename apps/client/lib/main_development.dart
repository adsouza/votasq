import 'package:client/app/app.dart';
import 'package:client/bootstrap.dart';

Future<void> main() async {
  // Dev flavor talks to the local Firebase emulators (Auth + Firestore).
  // Override with `--dart-define=USE_EMULATORS=false` to hit real Firebase
  // from a dev build instead.
  const useEmulators = bool.fromEnvironment(
    'USE_EMULATORS',
    defaultValue: true,
  );
  await bootstrap(() => const App(), useEmulators: useEmulators);
}
