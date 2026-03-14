import 'dart:convert';
import 'dart:io';

import 'package:logging/logging.dart';
import 'package:server/src/db.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as io;
import 'package:shelf_router/shelf_router.dart';

final _log = Logger('Server');

Db? _db;

Router _buildRouter() {
  return Router()
    ..get('/problem/<id>', (Request request, String id) async {
      final db = _db;
      if (db == null) {
        return Response(503, body: 'Service initializing');
      }
      try {
        final problem = await db.getProblem(id);
        return Response.ok(
          jsonEncode(problem.toJson()),
          headers: {'content-type': 'application/json'},
        );
      } on Exception catch (e) {
        _log.warning('Failed to get problem $id: $e');
        return Response.internalServerError();
      }
    });
}

void main() async {
  Logger.root.level = Level.ALL;
  Logger.root.onRecord.listen((record) {
    stderr.writeln(
      '${record.level.name}: ${record.time}: ${record.message}',
    );
  });

  final port = int.parse(Platform.environment['PORT'] ?? '8080');
  final router = _buildRouter();

  // Start listening immediately so Cloud Run's health check passes.
  await io.serve(router.call, '0.0.0.0', port);
  _log.info('Server listening on port $port');

  // Initialize DB after the server is up.
  final projectId = Platform.environment['GOOGLE_CLOUD_PROJECT'];
  if (projectId == null) {
    _log.severe('GOOGLE_CLOUD_PROJECT env var is required');
    exit(1);
  }
  try {
    _db = await Db.initialize(projectId);
    _log.info('Firestore connected');
  } on Exception catch (e) {
    _log.severe('Failed to initialize Firestore: $e');
  }
}
