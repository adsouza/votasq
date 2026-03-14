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

/// Returns the GCP project ID from the env var or the metadata server.
Future<String> _resolveProjectId() async {
  final fromEnv = Platform.environment['GOOGLE_CLOUD_PROJECT'];
  if (fromEnv != null) return fromEnv;

  // On Cloud Run, query the metadata server.
  final client = HttpClient();
  try {
    final request = await client.getUrl(
      Uri.parse(
        'http://metadata.google.internal'
        '/computeMetadata/v1/project/project-id',
      ),
    );
    request.headers.set('Metadata-Flavor', 'Google');
    final response = await request.close();
    final body = await response.transform(const SystemEncoding().decoder).join();
    if (response.statusCode == 200 && body.isNotEmpty) return body.trim();
  } finally {
    client.close();
  }
  throw Exception('Could not determine GCP project ID');
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
  try {
    final projectId = await _resolveProjectId();
    _db = await Db.initialize(projectId);
    _log.info('Firestore connected (project: $projectId)');
  } on Exception catch (e) {
    _log.severe('Failed to initialize Firestore: $e');
  }
}
