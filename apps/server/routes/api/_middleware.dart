import 'package:dart_frog/dart_frog.dart';
import 'package:server/src/db.dart';
import 'package:server/src/resolve_project_id.dart';
import 'package:server/src/translator.dart';

/// Lazily initialized — created once on first request.
final Future<String> _projectIdFuture = resolveProjectId();
final Future<Db> _dbFuture = _initDb();
final Future<Translator> _translatorFuture = _initTranslator();

Future<Db> _initDb() async => Db.initialize(await _projectIdFuture);
Future<Translator> _initTranslator() async =>
    Translator.initialize(await _projectIdFuture);

Handler middleware(Handler handler) {
  return handler
      .use(provider<Future<Db>>((context) => _dbFuture))
      .use(provider<Future<Translator>>((context) => _translatorFuture));
}
