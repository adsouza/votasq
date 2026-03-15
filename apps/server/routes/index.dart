import 'dart:io';

import 'package:dart_frog/dart_frog.dart';

Response onRequest(RequestContext context) {
  final indexFile = File('public/index.html');
  if (indexFile.existsSync()) {
    return Response(
      body: indexFile.readAsStringSync(),
      headers: {'content-type': 'text/html'},
    );
  }
  return Response(body: 'ok');
}
