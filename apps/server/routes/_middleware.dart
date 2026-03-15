import 'package:dart_frog/dart_frog.dart';
import 'package:server/src/db.dart';
import 'package:server/src/resolve_project_id.dart';

/// Lazily initialized — created once on first request.
final Future<Db> _dbFuture = _initDb();

Future<Db> _initDb() async {
  final projectId = await resolveProjectId();
  return Db.initialize(projectId);
}

Handler middleware(Handler handler) {
  return handler.use(provider<Future<Db>>((context) => _dbFuture));
}
