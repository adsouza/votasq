@Tags(['e2e'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:test/test.dart';

/// E2E rules test: exercises `firestore.rules` directly via the Firestore
/// emulator's REST API, using a real ID token from the Auth emulator so
/// security rules are enforced exactly as in production.
///
/// This is the layer that `fake_cloud_firestore` (used by the client's
/// unit tests) cannot model — it does not run rules. Rule mistakes only
/// surface against a real emulator or production. Bugs in this category
/// have shipped before; this file is the regression net for them.
///
/// Prerequisites (matches `problems_e2e_test.dart`):
///   firebase emulators:start --only auth,firestore
///
/// Uses project ID `votasq-rules-test` so this file and
/// `problems_e2e_test.dart` can run concurrently against the same
/// emulator without sharing document state (the emulator partitions docs
/// by project ID while applying a single rules file across all projects).
void main() {
  const projectId = 'votasq-rules-test';
  const firestoreHost = 'localhost:8081';
  const authHost = 'localhost:9099';

  late String idToken;
  late String uid;
  final client = http.Client();

  Uri docUri(String docPath) => Uri.parse(
    'http://$firestoreHost/v1/projects/$projectId/databases/(default)'
    '/documents/$docPath',
  );

  // Firestore REST API wire-format value helpers.
  Map<String, dynamic> sVal(String s) => {'stringValue': s};
  Map<String, dynamic> iVal(int i) => {'integerValue': '$i'};
  Map<String, dynamic> tsVal(DateTime dt) => {
    'timestampValue': dt.toUtc().toIso8601String(),
  };
  Map<String, dynamic> arrVal(List<Map<String, dynamic>> values) => {
    'arrayValue': {'values': values},
  };
  Map<String, dynamic> typedLinkVal(String targetId, String kind) => {
    'mapValue': {
      'fields': {'targetId': sVal(targetId), 'kind': sVal(kind)},
    },
  };

  setUpAll(() async {
    // Wait for the Firestore emulator to be ready, then clear its data
    // for this project ID.
    final clearUrl = Uri.parse(
      'http://$firestoreHost/emulator/v1/projects/$projectId'
      '/databases/(default)/documents',
    );
    var ready = false;
    for (var i = 0; i < 30; i++) {
      try {
        await client.delete(clearUrl);
        ready = true;
        break;
      } on Exception {
        await Future<void>.delayed(const Duration(seconds: 1));
      }
    }
    if (!ready) {
      fail('Firestore emulator not reachable at $firestoreHost');
    }

    // Push the current firestore.rules into the emulator. Firestore
    // claims to hot-reload rules on file change, but in practice the
    // emulator caches the rules loaded at startup — so an emulator
    // started before a rules edit will keep serving the stale rules.
    // Pushing via the management endpoint forces a fresh load and
    // makes this test self-contained regardless of when the emulator
    // was started. Resolved relative to the test's working directory
    // (project root, per the e2e test convention).
    final rulesContent = await File('firestore.rules').readAsString();
    final rulesUrl = Uri.parse(
      'http://$firestoreHost/emulator/v1/projects/$projectId:securityRules',
    );
    final rulesResp = await client.put(
      rulesUrl,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'rules': {
          'files': [
            {'content': rulesContent, 'name': 'firestore.rules'},
          ],
        },
      }),
    );
    if (rulesResp.statusCode != 200) {
      fail(
        'Failed to push firestore.rules to emulator: '
        '${rulesResp.statusCode} ${rulesResp.body}',
      );
    }

    // Sign up an anonymous user via the Auth emulator. The returned
    // idToken is what the rules engine uses to populate `request.auth`.
    final signUpUrl = Uri.parse(
      'http://$authHost/identitytoolkit.googleapis.com/v1/accounts:signUp'
      '?key=fake-api-key',
    );
    final signUpResp = await client.post(
      signUpUrl,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'returnSecureToken': true}),
    );
    if (signUpResp.statusCode != 200) {
      fail('signUp failed: ${signUpResp.statusCode} ${signUpResp.body}');
    }
    final body = jsonDecode(signUpResp.body) as Map<String, dynamic>;
    uid = body['localId'] as String;
    idToken = body['idToken'] as String;
  });

  tearDownAll(client.close);

  /// Create a `problems/{id}` doc via PATCH (which upserts) using the
  /// authed user's idToken. Goes through the `create` rule the first
  /// time, which requires the listed fields and specific initial values.
  Future<void> seedProblem(
    String id, {
    List<String> linkedProblemIds = const [],
    List<Map<String, dynamic>> typedLinks = const [],
  }) async {
    final now = DateTime.now().toUtc();
    final fields = <String, dynamic>{
      'description': sVal('seed problem'),
      'goal': sVal(''),
      'ownerId': sVal(uid),
      'geoscope': sVal('/'),
      'votes': iVal(1),
      'solved': {'booleanValue': false},
      'version': iVal(1),
      'createdAt': tsVal(now),
      'lastUpdatedAt': tsVal(now),
      'linkedProblemIds': arrVal(linkedProblemIds.map(sVal).toList()),
      'typedLinks': arrVal(typedLinks),
    };
    final resp = await client.patch(
      docUri('problems/$id'),
      headers: {
        'Authorization': 'Bearer $idToken',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({'fields': fields}),
    );
    if (resp.statusCode >= 400) {
      fail('seedProblem($id) failed: ${resp.statusCode} ${resp.body}');
    }
  }

  /// Send a rules-enforced PATCH against `problems/{id}`. The
  /// [updateMask] scopes which field paths are written (mirroring the
  /// `cloud_firestore` SDK's batch.update behavior, which sets only the
  /// keys it's given). [auth] toggles the Authorization header.
  Future<http.Response> patchProblem(
    String id,
    Map<String, dynamic> fields, {
    required List<String> updateMask,
    bool auth = true,
  }) async {
    final qs = updateMask.map((f) => 'updateMask.fieldPaths=$f').join('&');
    final url = Uri.parse('${docUri('problems/$id')}?$qs');
    final headers = {
      'Content-Type': 'application/json',
      if (auth) 'Authorization': 'Bearer $idToken',
    };
    return client.patch(
      url,
      headers: headers,
      body: jsonEncode({'fields': fields}),
    );
  }

  group('firestore.rules — problem typed links', () {
    test(
      'authed: updating linkedProblemIds AND typedLinks in one write '
      'is permitted (regression for the tagProblemLink path)',
      () async {
        // Seed p1 already generic-linked to p2 — this is the exact
        // pre-state when a user "promotes" a generic link to a typed
        // one. The promotion sends linkedProblemIds=[] (severing the
        // generic edge) and typedLinks=[{p2, specialization}] together.
        await seedProblem('p1', linkedProblemIds: ['p2']);

        final resp = await patchProblem(
          'p1',
          {
            'linkedProblemIds': arrVal([]),
            'typedLinks': arrVal([typedLinkVal('p2', 'specialization')]),
          },
          updateMask: ['linkedProblemIds', 'typedLinks'],
        );

        expect(
          resp.statusCode,
          200,
          reason:
              'Expected 200; pre-fix rule rejected this with 403. '
              'Got ${resp.statusCode}: ${resp.body}',
        );
      },
    );

    test('authed: updating typedLinks alone is permitted', () async {
      await seedProblem('p3');

      final resp = await patchProblem(
        'p3',
        {
          'typedLinks': arrVal([typedLinkVal('p4', 'generalization')]),
        },
        updateMask: ['typedLinks'],
      );

      expect(resp.statusCode, 200, reason: resp.body);
    });

    test(
      'authed: updating linkedProblemIds alone is permitted '
      '(existing clique-link path, regression check)',
      () async {
        await seedProblem('p5');

        final resp = await patchProblem(
          'p5',
          {
            'linkedProblemIds': arrVal([sVal('p6')]),
          },
          updateMask: ['linkedProblemIds'],
        );

        expect(resp.statusCode, 200, reason: resp.body);
      },
    );

    test('unauthed: typedLinks write is rejected', () async {
      await seedProblem('p7');

      final resp = await patchProblem(
        'p7',
        {
          'typedLinks': arrVal([typedLinkVal('p8', 'specialization')]),
        },
        updateMask: ['typedLinks'],
        auth: false,
      );

      expect(
        resp.statusCode,
        403,
        reason:
            'Expected 403 PERMISSION_DENIED for unauthed write. '
            'Got ${resp.statusCode}: ${resp.body}',
      );
    });

    test(
      'authed: list over the 100-entry cap is rejected',
      () async {
        await seedProblem('p9');
        final manyEntries = List<Map<String, dynamic>>.generate(
          101,
          (i) => typedLinkVal('t$i', 'specialization'),
        );

        final resp = await patchProblem(
          'p9',
          {'typedLinks': arrVal(manyEntries)},
          updateMask: ['typedLinks'],
        );

        expect(
          resp.statusCode,
          403,
          reason:
              'Expected 403 PERMISSION_DENIED for >100-entry typedLinks. '
              'Got ${resp.statusCode}: ${resp.body}',
        );
      },
    );

    test(
      'authed: write touching an unrelated field via the linking clause '
      'is rejected (must use the full-update path instead)',
      () async {
        await seedProblem('p10');

        // affectedKeys = {typedLinks, description}, which is NOT a
        // subset of {linkedProblemIds, typedLinks}. The linking clause
        // rejects it; the "Full problem update" clause would require
        // version > existing, which we don't bump here.
        final resp = await patchProblem(
          'p10',
          {
            'typedLinks': arrVal([typedLinkVal('p11', 'specialization')]),
            'description': sVal('mutated via wrong clause'),
          },
          updateMask: ['typedLinks', 'description'],
        );

        expect(
          resp.statusCode,
          403,
          reason:
              'Expected 403; the linking clause must not allow '
              'description mutation. Got ${resp.statusCode}: ${resp.body}',
        );
      },
    );
  });

  group('firestore.rules — problem hidden flag', () {
    // Mint a second authed user so we can exercise "non-owner cannot set
    // hidden". Done lazily inside this group (not setUpAll) to keep the
    // top-level setup focused.
    Future<({String uid, String idToken})> signUpSecondUser() async {
      final signUpUrl = Uri.parse(
        'http://$authHost/identitytoolkit.googleapis.com/v1/accounts:signUp'
        '?key=fake-api-key',
      );
      final resp = await client.post(
        signUpUrl,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'returnSecureToken': true}),
      );
      if (resp.statusCode != 200) {
        fail('second signUp failed: ${resp.statusCode} ${resp.body}');
      }
      final body = jsonDecode(resp.body) as Map<String, dynamic>;
      return (
        uid: body['localId'] as String,
        idToken: body['idToken'] as String,
      );
    }

    test('owner: can set hidden=true on their own problem', () async {
      await seedProblem('h1');
      final resp = await patchProblem(
        'h1',
        {
          'hidden': {'booleanValue': true},
        },
        updateMask: ['hidden'],
      );
      expect(resp.statusCode, 200, reason: resp.body);
    });

    test('owner: can set hidden=false (unhide)', () async {
      await seedProblem('h2');
      // First hide it.
      final hide = await patchProblem(
        'h2',
        {
          'hidden': {'booleanValue': true},
        },
        updateMask: ['hidden'],
      );
      expect(hide.statusCode, 200, reason: hide.body);
      // Then unhide.
      final unhide = await patchProblem(
        'h2',
        {
          'hidden': {'booleanValue': false},
        },
        updateMask: ['hidden'],
      );
      expect(unhide.statusCode, 200, reason: unhide.body);
    });

    test('non-owner authed user cannot set hidden', () async {
      await seedProblem('h3');
      final other = await signUpSecondUser();

      final url = Uri.parse(
        '${docUri('problems/h3')}?updateMask.fieldPaths=hidden',
      );
      final resp = await client.patch(
        url,
        headers: {
          'Authorization': 'Bearer ${other.idToken}',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'fields': {
            'hidden': {'booleanValue': true},
          },
        }),
      );
      expect(
        resp.statusCode,
        403,
        reason:
            'Expected 403 for non-owner hide write. Got '
            '${resp.statusCode}: ${resp.body}',
      );
    });

    test('unauthed write setting hidden is rejected', () async {
      await seedProblem('h4');
      final resp = await patchProblem(
        'h4',
        {
          'hidden': {'booleanValue': true},
        },
        updateMask: ['hidden'],
        auth: false,
      );
      expect(resp.statusCode, 403, reason: resp.body);
    });

    test(
      'hide-toggle write that also changes description is rejected',
      () async {
        await seedProblem('h5');
        // The hide-toggle branch requires affectedKeys().hasOnly(['hidden']),
        // so a write that also touches description must fail through that
        // branch. The full-update branch should also reject it (the new
        // guard forbids hidden changes there). Net: 403.
        final resp = await patchProblem(
          'h5',
          {
            'hidden': {'booleanValue': true},
            'description': sVal('changed description'),
          },
          updateMask: ['hidden', 'description'],
        );
        expect(resp.statusCode, 403, reason: resp.body);
      },
    );

    test('full-update write that flips hidden is rejected', () async {
      await seedProblem('h6');
      // Send a full-update-shaped payload that also flips hidden. The
      // full-update branch will be guarded by hidden==get('hidden', false),
      // so this must fail.
      final now = DateTime.now().toUtc();
      final resp = await patchProblem(
        'h6',
        {
          'description': sVal('updated'),
          'goal': sVal(''),
          'geoscope': sVal('/'),
          'votes': iVal(1),
          'solved': {'booleanValue': false},
          'version': iVal(2),
          'lastUpdatedAt': tsVal(now),
          'hidden': {'booleanValue': true},
        },
        updateMask: [
          'description',
          'goal',
          'geoscope',
          'votes',
          'solved',
          'version',
          'lastUpdatedAt',
          'hidden',
        ],
      );
      expect(resp.statusCode, 403, reason: resp.body);
    });
  });
}
