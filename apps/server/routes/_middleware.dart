import 'dart:io';

import 'package:dart_frog/dart_frog.dart';

/// SPA catch-all: serves the Flutter web app for any non-API path that would
/// otherwise 404, enabling client-side deep linking.
Handler middleware(Handler handler) {
  return (context) async {
    final response = await handler(context);

    if (response.statusCode == 404 &&
        !context.request.uri.path.startsWith('api')) {
      final indexFile = File('public/index.html');
      if (indexFile.existsSync()) {
        return Response(
          body: indexFile.readAsStringSync(),
          headers: {'content-type': 'text/html'},
        );
      }
    }

    return response;
  };
}
