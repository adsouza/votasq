import 'dart:convert';

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
  } on Exception {
    return Response(statusCode: 404);
  }
}

Future<Response> _put(RequestContext context, String id) async {
  final db = await context.read<Future<Db>>();
  try {
    final body =
        jsonDecode(
              await context.request.body(),
            )
            as Map<String, dynamic>;
    final problem = Problem.fromJson({...body, 'id': id});
    await db.saveProblem(problem);
    return Response.json(body: problem.toJson());
  } on Exception {
    return Response(statusCode: 400);
  }
}
