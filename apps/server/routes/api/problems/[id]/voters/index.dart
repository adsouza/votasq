import 'dart:convert';
import 'dart:io';

import 'package:dart_frog/dart_frog.dart';
import 'package:server/src/db.dart';

Future<Response> onRequest(RequestContext context, String id) async {
  return switch (context.request.method) {
    HttpMethod.post => _post(context, id),
    _ => Future.value(Response(statusCode: 405)),
  };
}

Future<Response> _post(RequestContext context, String id) async {
  try {
    final db = await context.read<Future<Db>>();
    final body =
        jsonDecode(await context.request.body()) as Map<String, dynamic>;
    final voterId = body['uid'] as String?;
    if (voterId == null || voterId.isEmpty) {
      return Response(statusCode: 400);
    }
    await db.voteForProblem(problemId: id, voterId: voterId);
    return Response();
  } catch (e, s) {
    stderr.writeln('POST /api/problems/$id/voters failed: $e\n$s');
    return Response(statusCode: 500);
  }
}
