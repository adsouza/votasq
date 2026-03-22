import 'dart:convert';

import 'package:dart_frog/dart_frog.dart';
import 'package:server/src/translator.dart';

Future<Response> onRequest(RequestContext context) async {
  return switch (context.request.method) {
    HttpMethod.post => _post(context),
    _ => Future.value(Response(statusCode: 405)),
  };
}

Future<Response> _post(RequestContext context) async {
  final translator = await context.read<Future<Translator>>();
  try {
    final body =
        jsonDecode(await context.request.body()) as Map<String, dynamic>;
    final text = body['text'] as String;
    final detected = await translator.detectLanguage(text);
    return Response.json(body: {'detectedLanguage': detected});
  } on Exception {
    return Response(statusCode: 400);
  }
}
