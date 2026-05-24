import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:server/src/db.dart';

Future<Response> onRequest(RequestContext context, String id) async {
  return switch (context.request.method) {
    HttpMethod.get => _get(context, id),
    _ => Future.value(Response(statusCode: 405)),
  };
}

Future<Response> _get(RequestContext context, String id) async {
  try {
    final db = await context.read<Future<Db>>();
    final versions = await db.getVersions(id);
    return Response.json(
      body: {'data': versions.map((v) => v.toJson()).toList()},
    );
  } catch (e, s) {
    stderr.writeln('GET /api/problems/$id/versions failed: $e\n$s');
    return Response(statusCode: 500);
  }
}
