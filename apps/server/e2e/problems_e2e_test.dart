@Tags(['e2e'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:test/test.dart';

/// End-to-end integration test that exercises the /problems endpoints
/// against a live Dart Frog server backed by the Firebase emulators.
///
/// Prerequisites:
///   firebase emulators:start --only auth,firestore
///   (Auth emulator on localhost:9099, Firestore emulator on localhost:8081)
void main() {
  Process? serverProcess;
  late Uri baseUrl;
  late String uid;
  final client = http.Client();

  setUpAll(() async {
    const emulatorHost = 'localhost:8081';

    // Wait for the Firestore emulator to be ready, then clear its data.
    final clearUrl = Uri.parse(
      'http://$emulatorHost/emulator/v1/projects/votasq-test/databases/(default)/documents',
    );
    var emulatorReady = false;
    for (var i = 0; i < 30; i++) {
      try {
        await http.delete(clearUrl);
        emulatorReady = true;
        break;
      } on Exception {
        await Future<void>.delayed(const Duration(seconds: 1));
      }
    }
    if (!emulatorReady) {
      fail('Firestore emulator not reachable at $emulatorHost');
    }

    // Sign in anonymously via the Auth emulator to get a real UID.
    const authHost = 'localhost:9099';
    final signUpUrl = Uri.parse(
      'http://$authHost/identitytoolkit.googleapis.com/v1/accounts:signUp?key=fake-api-key',
    );
    final authResponse = await http.post(
      signUpUrl,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'returnSecureToken': true}),
    );
    if (authResponse.statusCode != 200) {
      fail('Anonymous sign-in failed: ${authResponse.body}');
    }
    final authBody = jsonDecode(authResponse.body) as Map<String, dynamic>;
    uid = authBody['localId'] as String;

    // Build the Dart Frog server, then run the compiled binary.
    // Using the compiled server avoids stdin issues with `dart_frog dev`.
    final buildResult = await Process.run(
      'dart_frog',
      ['build'],
      workingDirectory: 'apps/server',
    );
    if (buildResult.exitCode != 0) {
      fail('dart_frog build failed: ${buildResult.stderr}');
    }
    serverProcess = await Process.start(
      'dart',
      ['build/bin/server.dart'],
      workingDirectory: 'apps/server',
      environment: {
        'GOOGLE_CLOUD_PROJECT': 'votasq-test',
        'FIRESTORE_EMULATOR_HOST': emulatorHost,
        'PORT': '8085',
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
        body: jsonEncode({'description': desc, 'ownerId': uid}),
      );

      expect(response.statusCode, 201, reason: 'POST should return 201');

      final created = jsonDecode(response.body) as Map<String, dynamic>;
      expect(created['description'], desc);
      expect(created['votes'], 1, reason: 'New problems start with 1 vote');
      expect(created['version'], 1, reason: 'New problems start at version 1');
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
        'votes': 3,
      }),
    );
    expect(putResponse.statusCode, 200);
    final updated = jsonDecode(putResponse.body) as Map<String, dynamic>;
    expect(updated['description'], updatedDescription);
    expect(updated['votes'], 3);
    expect(updated['version'], 2, reason: 'Version should increment on update');

    // ── 5. Fetch again to verify persistence ──
    final verifyResponse = await client.get(
      baseUrl.resolve('/problems/$targetId'),
    );
    expect(verifyResponse.statusCode, 200);
    final verified = jsonDecode(verifyResponse.body) as Map<String, dynamic>;
    expect(verified['id'], targetId);
    expect(verified['description'], updatedDescription);
    expect(verified['votes'], 3);
    expect(verified['version'], 2);

    // ── 6. Fetch version history ──
    final versionsResponse = await client.get(
      baseUrl.resolve('/problems/$targetId/versions'),
    );
    expect(versionsResponse.statusCode, 200);
    final versionsBody =
        jsonDecode(versionsResponse.body) as Map<String, dynamic>;
    final versions = (versionsBody['data'] as List)
        .cast<Map<String, dynamic>>();
    expect(versions.length, 2, reason: 'Should have 2 versions after 1 update');

    // Revisions should not contain Problem-specific fields.
    expect(versions[0].containsKey('id'), isFalse);
    expect(versions[0].containsKey('votes'), isFalse);
    expect(versions[0].containsKey('solved'), isFalse);
    expect(versions[0].containsKey('createdAt'), isFalse);
    expect(versions[0].containsKey('lastUpdatedAt'), isFalse);

    // Version 1: original state.
    expect(versions[0]['version'], 1);
    expect(versions[0]['description'], descriptions.first);
    expect(versions[0]['archivedAt'], isNotNull);
    expect(versions[0]['restoredFrom'], isNull);

    // Version 2: updated state.
    expect(versions[1]['version'], 2);
    expect(versions[1]['description'], updatedDescription);
    expect(versions[1]['archivedAt'], isNotNull);
  });

  test('geoscope filtering is ancestor-inclusive', () async {
    // Create problems at different geoscope levels.
    Future<String> create(String desc, String geoscope) async {
      final r = await client.post(
        baseUrl.resolve('/problems'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'description': desc,
          'ownerId': uid,
          'geoscope': geoscope,
        }),
      );
      expect(r.statusCode, 201);
      return (jsonDecode(r.body) as Map<String, dynamic>)['id'] as String;
    }

    final globalId = await create('Global issue here', '/');
    final countryId = await create('Country issue here', 'na/us');
    final cityId = await create('City-level issue here', 'na/us/ny/nyc');
    final otherId = await create('Other city problem', 'eu/gb/eng/london');

    // Helper to fetch all problem IDs for a given geoscope.
    Future<Set<String>> fetchIds(String geoscope) async {
      final r = await client.get(
        baseUrl.resolve('/problems?geoscope=$geoscope'),
      );
      expect(r.statusCode, 200);
      final body = jsonDecode(r.body) as Map<String, dynamic>;
      final data = (body['data'] as List).cast<Map<String, dynamic>>();
      return data.map((p) => p['id'] as String).toSet();
    }

    // ── Querying at city level should include city, country, and global ──
    final nycResults = await fetchIds('na/us/ny/nyc');
    expect(nycResults, contains(cityId));
    expect(nycResults, contains(countryId));
    expect(nycResults, contains(globalId));
    expect(nycResults, isNot(contains(otherId)));

    // ── Querying at country level should include country and global ──
    final usResults = await fetchIds('na/us');
    expect(usResults, contains(countryId));
    expect(usResults, contains(globalId));
    expect(usResults, isNot(contains(cityId)));
    expect(usResults, isNot(contains(otherId)));

    // ── Querying at global should only include global ──
    final globalResults = await fetchIds('/');
    expect(globalResults, contains(globalId));
    expect(globalResults, isNot(contains(countryId)));
    expect(globalResults, isNot(contains(cityId)));
    expect(globalResults, isNot(contains(otherId)));

    // ── Querying a different branch should not see US/NYC problems ──
    final londonResults = await fetchIds('eu/gb/eng/london');
    expect(londonResults, contains(otherId));
    expect(londonResults, contains(globalId));
    expect(londonResults, isNot(contains(countryId)));
    expect(londonResults, isNot(contains(cityId)));
  });

  test('translation cache: hit, invalidation on description change', () async {
    // ── 1. Create a problem ──
    final createResponse = await client.post(
      baseUrl.resolve('/problems'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'description': 'Arreglar las calles', 'ownerId': uid}),
    );
    expect(createResponse.statusCode, 201);
    final problem = jsonDecode(createResponse.body) as Map<String, dynamic>;
    final problemId = problem['id'] as String;

    // ── 2. Seed a cached translation via the Firestore emulator ──
    const emulatorHost = 'localhost:8081';
    final translationDocUrl = Uri.parse(
      'http://$emulatorHost/v1/projects/votasq-test'
      '/databases/(default)/documents'
      '/problems/$problemId/translations/en',
    );
    final seedResponse = await client.patch(
      translationDocUrl,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'fields': {
          'description': {'stringValue': 'Fix the streets'},
        },
      }),
    );
    expect(
      seedResponse.statusCode,
      200,
      reason: 'Seeding translation via emulator should succeed',
    );

    // ── 3. GET the translation — should return the cached value ──
    final cacheHitResponse = await client.get(
      baseUrl.resolve('/problems/$problemId/translations/en'),
    );
    expect(cacheHitResponse.statusCode, 200);
    final cached = jsonDecode(cacheHitResponse.body) as Map<String, dynamic>;
    expect(
      cached['description'],
      'Fix the streets',
      reason: 'Should return the seeded cached translation',
    );

    // ── 4. Update the problem description ──
    final putResponse = await client.put(
      baseUrl.resolve('/problems/$problemId'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'description': 'Reparar las aceras',
        'votes': 1,
      }),
    );
    expect(putResponse.statusCode, 200);

    // ── 5. Verify the cached translation was invalidated ──
    // Reading the translation doc directly from the emulator should 404.
    final deletedResponse = await client.get(translationDocUrl);
    expect(
      deletedResponse.statusCode,
      isNot(200),
      reason:
          'Cached translation should have been deleted '
          'after description change',
    );
  });
}
