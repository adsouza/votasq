// Seeds a few sample notifications for a given user into the local Firestore
// emulator so the in-app reader (slice 2) can be exercised before the Cloud
// Functions producers (slice 3) exist.
//
// Usage:
//   firebase emulators:start --only auth,firestore
//   dart run apps/client/tool/seed_notifications.dart <uid> [--project votasq]
//
// The script talks to the Firestore REST API directly with the emulator's
// "Bearer owner" magic token, which bypasses security rules — exactly what
// Cloud Functions will do for real once they exist.

import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

const _emulatorHostDefault = 'localhost:8081';
const _projectDefault = 'votasq';

Future<void> main(List<String> args) async {
  if (args.isEmpty || args.first.startsWith('--')) {
    stderr.writeln(
      'usage: dart run apps/client/tool/seed_notifications.dart <uid> '
      '[--project <id>]',
    );
    exitCode = 64;
    return;
  }

  final uid = args.first;
  var project = _projectDefault;
  for (var i = 1; i < args.length - 1; i++) {
    if (args[i] == '--project') project = args[i + 1];
  }

  final host = Platform.environment['FIRESTORE_EMULATOR_HOST'] ??
      _emulatorHostDefault;
  final base = 'http://$host/v1/projects/$project/databases/(default)/documents';
  final headers = {
    'Authorization': 'Bearer owner',
    'Content-Type': 'application/json',
  };

  final now = DateTime.now().toUtc();
  final iso = now.toIso8601String();

  final samples = <_Sample>[
    _Sample(
      id: 'voteReceived__sample-problem-1__actor-alice',
      payload: {
        'type': 'voteReceived',
        'problemId': 'sample-problem-1',
        'actorUid': 'actor-alice',
      },
    ),
    _Sample(
      id: 'problemForked__sample-fork-1',
      payload: {
        'type': 'problemForked',
        'originalProblemId': 'sample-problem-2',
        'forkProblemId': 'sample-fork-1',
        'actorUid': 'actor-bob',
      },
    ),
    _Sample(
      id: 'problemLinked__sample-problem-3__sample-linker-1',
      payload: {
        'type': 'problemLinked',
        'linkedProblemId': 'sample-problem-3',
        'linkerProblemId': 'sample-linker-1',
        'actorUid': 'actor-carol',
      },
    ),
    _Sample(
      id: 'problemRevised__sample-problem-4__v2',
      payload: {
        'type': 'problemRevised',
        'problemId': 'sample-problem-4',
        'newVersion': 2,
      },
    ),
    _Sample(
      id: 'forkAdopted__sample-fork-2__sample-orig-2__v3',
      payload: {
        'type': 'forkAdopted',
        'forkProblemId': 'sample-fork-2',
        'originalProblemId': 'sample-orig-2',
        'newVersion': 3,
      },
    ),
  ];

  for (final sample in samples) {
    final url = Uri.parse(
      '$base/users/$uid/notifications?documentId=${sample.id}',
    );
    final body = jsonEncode({
      'fields': {
        'id': {'stringValue': sample.id},
        'recipientUid': {'stringValue': uid},
        'payload': {
          'mapValue': {
            'fields': _toFirestoreFields(sample.payload),
          },
        },
        'createdAt': {'timestampValue': iso},
        'updatedAt': {'timestampValue': iso},
        'readAt': {'nullValue': null},
      },
    });

    final response = await http.post(url, headers: headers, body: body);
    if (response.statusCode >= 200 && response.statusCode < 300) {
      stdout.writeln('  ok: ${sample.id}');
    } else {
      stderr
        ..writeln('  fail (${response.statusCode}): ${sample.id}')
        ..writeln('    ${response.body}');
      exitCode = 1;
    }
  }
}

class _Sample {
  _Sample({required this.id, required this.payload});

  final String id;
  final Map<String, dynamic> payload;
}

Map<String, dynamic> _toFirestoreFields(Map<String, dynamic> data) {
  return data.map((key, value) {
    if (value is String) return MapEntry(key, {'stringValue': value});
    if (value is int) return MapEntry(key, {'integerValue': '$value'});
    if (value is bool) return MapEntry(key, {'booleanValue': value});
    throw UnsupportedError(
      'seed_notifications: unsupported sample field type ${value.runtimeType}',
    );
  });
}
