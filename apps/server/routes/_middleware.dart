import 'package:dart_frog/dart_frog.dart';
import 'package:server/src/db.dart';
import 'package:server/src/resolve_project_id.dart';
import 'package:server/src/translator.dart';

/// Lazily initialized — created once on first request.
final Future<Db> _dbFuture = _initDb();
final Future<Translator> _translatorFuture = _initTranslator();

Future<Db> _initDb() async {
  final projectId = await resolveProjectId();
  return Db.initialize(projectId);
}

Future<Translator> _initTranslator() async {
  final projectId = await resolveProjectId();
  return Translator.initialize(projectId);
}

Handler middleware(Handler handler) {
  return handler
      .use(provider<Future<Db>>((context) => _dbFuture))
      .use(provider<Future<Translator>>((context) => _translatorFuture));
}
