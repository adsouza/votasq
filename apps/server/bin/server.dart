import 'dart:convert';
import 'dart:io';

import 'package:logging/logging.dart';
import 'package:server/src/db.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as io;
import 'package:shelf_router/shelf_router.dart';

final _log = Logger('Server');

Router _buildRouter(Db db) {
  return Router()
    ..get('/problem/<id>', (Request request, String id) async {
      final problem = await db.getProblem(id);
      return Response.ok(
        jsonEncode(problem.toJson()),
        headers: {'content-type': 'application/json'},
      );
    });
}

void main() async {
  Logger.root.level = Level.ALL;
  Logger.root.onRecord.listen((record) {
    stderr.writeln(
      '${record.level.name}: ${record.time}: ${record.message}',
    );
  });

  final projectId = Platform.environment['GOOGLE_CLOUD_PROJECT'];
  if (projectId == null) {
    _log.severe('GOOGLE_CLOUD_PROJECT env var is required');
    exit(1);
  }

  final db = await Db.initialize(projectId);
  final router = _buildRouter(db);
  final port = int.parse(Platform.environment['PORT'] ?? '8080');

  await io.serve(router.call, '0.0.0.0', port);
  _log.info('Server listening on port $port');
}
