// Throwaway: copies every doc in the prod `geoscopes` collection into the
// local Firestore emulator, verbatim. Idempotent — re-running overwrites.
//
// Source and destination project id are both hardcoded to `votasq` — that's
// the prod project and also the id the Flutter client uses against the
// emulator (see apps/client/lib/firebase_options.dart). Don't parameterise.
//
// Usage (run from `apps/server/`):
//   gcloud auth application-default login                  # for prod read
//   gcloud auth application-default set-quota-project votasq  # if you hit 403
//   export FIRESTORE_EMULATOR_HOST=127.0.0.1:8081          # dest emulator
//   dart run tool/copy_geoscopes_to_emulator.dart [--dry-run]

import 'dart:io';

import 'package:googleapis/firestore/v1.dart';
import 'package:googleapis_auth/auth_io.dart' as auth_io;
import 'package:http/http.dart' as http;

const _scopes = <String>[FirestoreApi.datastoreScope];
const _pageSize = 300;
const _commitBatch = 200;
const _projectId = 'votasq';

Future<void> main(List<String> args) async {
  final dryRun = args.contains('--dry-run');
  final emulatorHost = Platform.environment['FIRESTORE_EMULATOR_HOST'];
  if (emulatorHost == null || emulatorHost.isEmpty) {
    stderr.writeln(
      'FIRESTORE_EMULATOR_HOST must be set (e.g. 127.0.0.1:8081).',
    );
    exit(2);
  }

  final prodClient = await auth_io.clientViaApplicationDefaultCredentials(
    scopes: _scopes,
  );
  final emulatorClient = _EmulatorOwnerClient(http.Client());

  final prodApi = FirestoreApi(prodClient);
  final emulatorApi = FirestoreApi(
    emulatorClient,
    rootUrl: 'http://$emulatorHost/',
  );

  const databasePath = 'projects/$_projectId/databases/(default)';
  const destBase = '$databasePath/documents';
  const sourceParent = destBase;

  var copied = 0;
  String? pageToken;

  try {
    do {
      final page = await prodApi.projects.databases.documents.list(
        sourceParent,
        'geoscopes',
        pageSize: _pageSize,
        pageToken: pageToken,
      );

      final docs = page.documents ?? const <Document>[];
      final writes = <Write>[];
      for (final doc in docs) {
        final id = doc.name!.split('/').last;
        writes.add(
          Write(
            update: Document(fields: doc.fields)
              ..name = '$destBase/geoscopes/$id',
          ),
        );
      }

      if (!dryRun) {
        for (var i = 0; i < writes.length; i += _commitBatch) {
          final slice = writes.sublist(
            i,
            i + _commitBatch > writes.length ? writes.length : i + _commitBatch,
          );
          await emulatorApi.projects.databases.documents.commit(
            CommitRequest(writes: slice),
            databasePath,
          );
        }
      }

      copied += writes.length;
      pageToken = page.nextPageToken;
    } while (pageToken != null && pageToken.isNotEmpty);
  } finally {
    prodClient.close();
    emulatorClient.close();
  }

  stdout.writeln(
    'copied=$copied dryRun=$dryRun '
    'project=$_projectId emulator=$emulatorHost',
  );
}

/// Wraps an [http.Client] so every request carries
/// `Authorization: Bearer owner`, the documented Firebase emulator
/// admin-bypass token. Lets the script write to the emulator without
/// holding a real Firebase ID token.
class _EmulatorOwnerClient extends http.BaseClient {
  _EmulatorOwnerClient(this._inner);

  final http.Client _inner;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    request.headers['Authorization'] = 'Bearer owner';
    return _inner.send(request);
  }

  @override
  void close() => _inner.close();
}
