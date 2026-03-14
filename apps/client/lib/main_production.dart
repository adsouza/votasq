import 'package:client/app/app.dart';
import 'package:client/bootstrap.dart';

Future<void> main() async {
  await bootstrap(() => const App());
}
