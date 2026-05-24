import 'dart:convert';
import 'dart:io';

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
  try {
    final db = await context.read<Future<Db>>();
    final problem = await db.getProblem(id);
    return Response.json(body: problem.toJson());
  } catch (e, s) {
    stderr.writeln('GET /api/problems/$id failed: $e\n$s');
    return Response(statusCode: 404);
  }
}

Future<Response> _put(RequestContext context, String id) async {
  final Db db;
  final Problem existing;
  try {
    db = await context.read<Future<Db>>();
    existing = await db.getProblem(id);
  } catch (e, s) {
    stderr.writeln('PUT /api/problems/$id lookup failed: $e\n$s');
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
      if (!body.containsKey('linkedProblemIds'))
        'linkedProblemIds': existing.linkedProblemIds,
      if (!body.containsKey('typedLinks'))
        'typedLinks': existing.typedLinks.map((l) => l.toJson()).toList(),
    });
    if (body['description'] != existing.description ||
        body['goal'] != existing.goal) {
      await db.deleteTranslations(id);
    }
    await db.saveProblem(problem);
    return Response.json(body: problem.toJson());
  } on FormatException catch (e, s) {
    stderr.writeln('PUT /api/problems/$id bad request: $e\n$s');
    return Response.json(
      statusCode: 400,
      body: {'error': 'Invalid request body'},
    );
  } catch (e, s) {
    stderr.writeln('PUT /api/problems/$id update failed: $e\n$s');
    return Response(statusCode: 500);
  }
}
