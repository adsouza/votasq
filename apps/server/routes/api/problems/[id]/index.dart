import 'dart:convert';
import 'dart:developer';

import 'package:dart_frog/dart_frog.dart';
import 'package:server/src/db.dart';
import 'package:shared/shared.dart';

Future<Response> onRequest(RequestContext context, String id) async {
  return switch (context.request.method) {
    HttpMethod.get => _get(context, id),
    HttpMethod.put => _put(context, id),
    _ => Future.value(Response(statusCode: 405)),
  };
}

Future<Response> _get(RequestContext context, String id) async {
  final db = await context.read<Future<Db>>();
  try {
    final problem = await db.getProblem(id);
    return Response.json(body: problem.toJson());
  } on Exception catch (e) {
    log('GET /api/problems/$id failed: $e');
    return Response(statusCode: 404);
  }
}

Future<Response> _put(RequestContext context, String id) async {
  final db = await context.read<Future<Db>>();
  final Problem existing;
  try {
    existing = await db.getProblem(id);
  } on Exception catch (e) {
    log('PUT /api/problems/$id lookup failed: $e');
    return Response(statusCode: 404);
  }
  try {
    final body =
        jsonDecode(await context.request.body()) as Map<String, dynamic>;
    final problem = Problem.fromJson({
      ...body,
      'id': id,
      'ownerId': existing.ownerId,
      'votes': existing.votes,
      'version': existing.version + 1,
      'createdAt': existing.createdAt.toIso8601String(),
      'lastUpdatedAt': DateTime.now().toUtc().toIso8601String(),
    });
    if (body['description'] != existing.description ||
        body['goal'] != existing.goal) {
      await db.deleteTranslations(id);
    }
    await db.saveProblem(problem);
    return Response.json(body: problem.toJson());
  } on FormatException catch (e) {
    log('PUT /api/problems/$id bad request: $e');
    return Response.json(
      statusCode: 400,
      body: {'error': 'Invalid request body'},
    );
  } on Exception catch (e) {
    log('PUT /api/problems/$id update failed: $e');
    return Response(statusCode: 500);
  }
}
