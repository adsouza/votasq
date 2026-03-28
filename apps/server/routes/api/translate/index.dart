import 'dart:convert';
import 'dart:developer';

import 'package:dart_frog/dart_frog.dart';
import 'package:server/src/translator.dart';

Future<Response> onRequest(RequestContext context) async {
  return switch (context.request.method) {
    HttpMethod.post => _post(context),
    _ => Future.value(Response(statusCode: 405)),
  };
}

/// Translates the input to English and returns both the detected source
/// language and the English translation. This costs the same as pure detection
/// but gives us a usable translation for free.
Future<Response> _post(RequestContext context) async {
  final translator = await context.read<Future<Translator>>();
  try {
    final body =
        jsonDecode(await context.request.body()) as Map<String, dynamic>;
    final text = body['text'] as String?;
    if (text == null || text.isEmpty) {
      return Response.json(
        statusCode: 400,
        body: {'error': 'Missing required field: text'},
      );
    }
    final (:translatedText, :detectedLanguage) = await translator
        .translateWithDetection(
          text: text,
          targetLanguage: 'en',
        );
    return Response.json(
      body: {
        'detectedLanguage': detectedLanguage,
        'translation': translatedText,
      },
    );
  } on FormatException catch (e) {
    log('POST /api/translate bad request: $e');
    return Response.json(
      statusCode: 400,
      body: {'error': 'Invalid request body'},
    );
  } on Exception catch (e) {
    log('POST /api/translate failed: $e');
    return Response(statusCode: 500);
  }
}
