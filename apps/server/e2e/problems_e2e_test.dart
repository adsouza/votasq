@Tags(['e2e'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:test/test.dart';

/// End-to-end integration test that exercises the /problems endpoints
/// against a live Dart Frog server backed by the Firebase Firestore emulator.
///
/// Prerequisites:
///   firebase emulators:start --only firestore
///   (Emulator must be running on localhost:8081)
void main() {
  Process? serverProcess;
  late Uri baseUrl;
  final client = http.Client();

  setUpAll(() async {
    const emulatorHost = 'localhost:8081';

    // Clear emulator data before the run.
    await http.delete(
      Uri.parse(
        'http://$emulatorHost/emulator/v1/projects/votasq-test/databases/(default)/documents',
      ),
    );

    // Start the Dart Frog server pointing at the emulator.
    serverProcess = await Process.start(
      'dart_frog',
      ['dev', '--port', '8085'],
      workingDirectory: 'apps/server',
      environment: {
        'GOOGLE_CLOUD_PROJECT': 'votasq-test',
        'FIRESTORE_EMULATOR_HOST': emulatorHost,
      },
    );

    // Wait for the server to be ready by polling.
    final serverUrl = Uri.parse('http://localhost:8085');
    var ready = false;
    for (var i = 0; i < 60; i++) {
      try {
        final response = await client.get(serverUrl);
        if (response.statusCode < 500) {
          ready = true;
          break;
        }
      } on Exception {
        // Server not up yet.
      }
      await Future<void>.delayed(const Duration(seconds: 1));
    }

    if (!ready) {
      fail('Dart Frog server did not start within 60 seconds');
    }

    baseUrl = serverUrl;
  });

  tearDownAll(() {
    serverProcess?.kill();
    client.close();
  });

  test('create, paginate, fetch, update, and verify problems', () async {
    // ── 1. Create 3 problems with only descriptions ──
    final descriptions = [
      'Fix login timeout on slow networks',
      'Add dark mode support',
      'Improve search result ranking',
    ];

    final createdIds = <String>[];
    for (final desc in descriptions) {
      final response = await client.post(
        baseUrl.resolve('/problems'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'description': desc}),
      );

      expect(response.statusCode, 201, reason: 'POST should return 201');

      final created = jsonDecode(response.body) as Map<String, dynamic>;
      expect(created['description'], desc);
      expect(created['votes'], 1, reason: 'New problems start with 1 vote');
      expect(created['id'], isNotEmpty, reason: 'Server should generate an ID');
      createdIds.add(created['id'] as String);
    }

    // All IDs should be unique.
    expect(createdIds.toSet().length, 3);

    // ── 2. Paginate through all problems, 2 at a time ──
    final allFetched = <Map<String, dynamic>>[];

    // First page.
    var listResponse = await client.get(
      baseUrl.resolve('/problems?pageSize=2'),
    );
    expect(listResponse.statusCode, 200);
    var listBody = jsonDecode(listResponse.body) as Map<String, dynamic>;
    var page = (listBody['data'] as List).cast<Map<String, dynamic>>();
    expect(page.length, 2, reason: 'First page should have 2 items');
    allFetched.addAll(page);

    // There should be a next page token.
    expect(listBody['nextPageToken'], isNotNull);

    // Second page.
    final token = listBody['nextPageToken'] as String;
    listResponse = await client.get(
      baseUrl.resolve('/problems?pageSize=2&pageToken=$token'),
    );
    expect(listResponse.statusCode, 200);
    listBody = jsonDecode(listResponse.body) as Map<String, dynamic>;
    page = (listBody['data'] as List).cast<Map<String, dynamic>>();
    expect(page.length, 1, reason: 'Second page should have 1 item');
    allFetched.addAll(page);

    // No more pages.
    expect(listBody.containsKey('nextPageToken'), isFalse);

    // All 3 problems should appear across both pages.
    final fetchedIds = allFetched.map((p) => p['id']).toSet();
    expect(fetchedIds, containsAll(createdIds));

    // ── 3. Fetch one problem by ID ──
    final targetId = createdIds.first;
    final getResponse = await client.get(
      baseUrl.resolve('/problems/$targetId'),
    );
    expect(getResponse.statusCode, 200);
    final fetched = jsonDecode(getResponse.body) as Map<String, dynamic>;
    expect(fetched['id'], targetId);
    expect(fetched['description'], descriptions.first);
    expect(fetched['votes'], 1);

    // ── 4. Update: change description & increment votes ──
    const updatedDescription = 'Fix login timeout on all network conditions';
    final putResponse = await client.put(
      baseUrl.resolve('/problems/$targetId'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'description': updatedDescription,
        'votes': 2,
      }),
    );
    expect(putResponse.statusCode, 200);
    final updated = jsonDecode(putResponse.body) as Map<String, dynamic>;
    expect(updated['description'], updatedDescription);
    expect(updated['votes'], 2);

    // ── 5. Fetch again to verify persistence ──
    final verifyResponse = await client.get(
      baseUrl.resolve('/problems/$targetId'),
    );
    expect(verifyResponse.statusCode, 200);
    final verified = jsonDecode(verifyResponse.body) as Map<String, dynamic>;
    expect(verified['id'], targetId);
    expect(verified['description'], updatedDescription);
    expect(verified['votes'], 2);
  });
}
