import 'dart:developer';

import 'package:dart_frog/dart_frog.dart';
import 'package:server/src/db.dart';
import 'package:server/src/translator.dart';
import 'package:shared/shared.dart';

Future<Response> onRequest(
  RequestContext context,
  String id,
  String lang,
) async {
  return switch (context.request.method) {
    HttpMethod.get => _get(context, id, lang),
    _ => Future.value(Response(statusCode: 405)),
  };
}

/// Returns a cached [TranslatedProblem], or translates via Cloud Translate,
/// caches the result, and returns it.
Future<Response> _get(
  RequestContext context,
  String id,
  String lang,
) async {
  final db = await context.read<Future<Db>>();
  final cached = await db.getTranslation(id, lang);
  if (cached != null) {
    return Response.json(body: cached.toJson());
  }

  final translator = await context.read<Future<Translator>>();
  try {
    final problem = await db.getProblem(id);
    final translatedDesc = await translator.translate(
      text: problem.description,
      targetLanguage: lang,
    );
    final translatedGoal = problem.goal.isNotEmpty
        ? await translator.translate(
            text: problem.goal,
            targetLanguage: lang,
          )
        : '';
    final translatedProblem = TranslatedProblem(
      description: translatedDesc,
      goal: translatedGoal,
    );
    await db.saveTranslation(id, lang, translatedProblem);
    return Response.json(body: translatedProblem.toJson());
  } on Exception catch (e) {
    log('GET /api/problems/$id/translations/$lang failed: $e');
    return Response(statusCode: 404);
  }
}
