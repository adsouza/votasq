import 'dart:io';

/// Returns the GCP project ID from the env var or the metadata server.
Future<String> resolveProjectId() async {
  final fromEnv = Platform.environment['GOOGLE_CLOUD_PROJECT'];
  if (fromEnv != null) return fromEnv;

  // On Cloud Run, query the metadata server.
  final client = HttpClient();
  try {
    final request = await client.getUrl(
      Uri.parse(
        'http://metadata.google.internal'
        '/computeMetadata/v1/project/project-id',
      ),
    );
    request.headers.set('Metadata-Flavor', 'Google');
    final response = await request.close();
    final body = await response
        .transform(const SystemEncoding().decoder)
        .join();
    if (response.statusCode == 200 && body.isNotEmpty) {
      return body.trim();
    }
  } finally {
    client.close();
  }
  throw Exception('Could not determine GCP project ID');
}
