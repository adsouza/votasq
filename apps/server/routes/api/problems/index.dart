import 'dart:convert';
import 'dart:developer';

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
    final geoscope = params['geoscope'];
    final (:problems, :nextPageToken) = await db.getProblems(
      pageSize: pageSize,
      pageToken: pageToken,
      geoscope: geoscope,
    );
    return Response.json(
      body: {
        'data': problems.map((p) => p.toJson()).toList(),
        if (nextPageToken != null) 'nextPageToken': nextPageToken,
      },
    );
  } on Exception catch (e) {
    log('GET /api/problems failed: $e');
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
    final description = body['description'] as String?;
    final ownerId = body['ownerId'] as String?;
    if (description == null || description.isEmpty) {
      return Response.json(
        statusCode: 400,
        body: {'error': 'Missing required field: description'},
      );
    }
    if (ownerId == null || ownerId.isEmpty) {
      return Response.json(
        statusCode: 400,
        body: {'error': 'Missing required field: ownerId'},
      );
    }
    final now = DateTime.now().toUtc().toIso8601String();
    final problem = Problem.fromJson({
      ...body,
      'id': const Uuid().v4(),
      'votes': 1,
      'createdAt': now,
      'lastUpdatedAt': now,
    });
    await db.saveProblem(problem);
    await db.saveVoterDoc(
      problemId: problem.id,
      voterId: problem.ownerId,
      votes: 1,
    );
    return Response.json(statusCode: 201, body: problem.toJson());
  } on FormatException catch (e) {
    log('POST /api/problems bad request: $e');
    return Response.json(
      statusCode: 400,
      body: {'error': 'Invalid request body'},
    );
  } on Exception catch (e) {
    log('POST /api/problems failed: $e');
    return Response(statusCode: 500);
  }
}
