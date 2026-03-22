import 'package:dart_frog/dart_frog.dart';
import 'package:server/src/db.dart';

Future<Response> onRequest(RequestContext context, String id) async {
  return switch (context.request.method) {
    HttpMethod.get => _get(context, id),
    _ => Future.value(Response(statusCode: 405)),
  };
}

Future<Response> _get(RequestContext context, String id) async {
  final db = await context.read<Future<Db>>();
  try {
    final versions = await db.getVersions(id);
    return Response.json(
      body: {'data': versions.map((v) => v.toJson()).toList()},
    );
  } on Exception {
    return Response(statusCode: 500);
  }
}
