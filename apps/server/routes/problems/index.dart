import 'dart:convert';

import 'package:dart_frog/dart_frog.dart';
import 'package:server/src/db.dart';
import 'package:shared/shared.dart';

Future<Response> onRequest(RequestContext context) async {
  return switch (context.request.method) {
    HttpMethod.post => _post(context),
    _ => Future.value(Response(statusCode: 405)),
  };
}

Future<Response> _post(RequestContext context) async {
  final db = await context.read<Future<Db>>();
  try {
    final body = jsonDecode(
      await context.request.body(),
    ) as Map<String, dynamic>;
    final problem = Problem.fromJson(body);
    await db.saveProblem(problem);
    return Response(statusCode: 201);
  } on Exception {
    return Response(statusCode: 400);
  }
}
