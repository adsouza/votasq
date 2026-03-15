import 'dart:convert';

import 'package:dart_frog/dart_frog.dart';
import 'package:server/src/db.dart';
import 'package:shared/shared.dart';
import 'package:uuid/uuid.dart';

Future<Response> onRequest(RequestContext context) async {
  return switch (context.request.method) {
    HttpMethod.get => _get(context),
    HttpMethod.post => _post(context),
    _ => Future.value(Response(statusCode: 405)),
  };
}

Future<Response> _get(RequestContext context) async {
  final db = await context.read<Future<Db>>();
  final params = context.request.uri.queryParameters;
  final pageSize = int.tryParse(params['pageSize'] ?? '') ?? 99;
  final pageToken = params['pageToken'];
  try {
    final (:problems, :nextPageToken) = await db.getProblems(
      pageSize: pageSize,
      pageToken: pageToken,
    );
    return Response.json(
      body: {
        'data': problems.map((p) => p.toJson()).toList(),
        if (nextPageToken != null) 'nextPageToken': nextPageToken,
      },
    );
  } on Exception {
    return Response(statusCode: 500);
  }
}

Future<Response> _post(RequestContext context) async {
  final db = await context.read<Future<Db>>();
  try {
    final body =
        jsonDecode(
              await context.request.body(),
            )
            as Map<String, dynamic>;
    final problem = Problem.fromJson({
      ...body,
      'id': const Uuid().v4(),
      'votes': 1,
    });
    await db.saveProblem(problem);
    return Response.json(statusCode: 201, body: problem.toJson());
  } on Exception {
    return Response(statusCode: 400);
  }
}
