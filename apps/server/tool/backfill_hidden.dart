// One-off backfill: stamps `hidden: false` onto every `problems/*` doc
// that does not have the field set. Idempotent — safe to re-run.
//
// Why: when the client's listing query filters `where('hidden',
// isEqualTo: false)`, Firestore excludes docs where the field is missing.
// Without this backfill, every existing problem would vanish from the
// list on the day the new client ships.
//
// Run from `apps/server/`:
//   gcloud auth application-default login   # one-time
//   export GOOGLE_CLOUD_PROJECT=votasq      # or votasq-dev for staging
//   dart run tool/backfill_hidden.dart [--dry-run]
//
// The script lists all `problems` docs page by page, and for each doc
// that has no `hidden` field, issues an update that sets `hidden: false`
// with an updateMask scoped to the `hidden` field only (so the write
// passes through the new hide-toggle rules branch even when the script
// runs as a regular user — though it actually runs with Application
// Default Credentials, which bypass rules).

import 'dart:io';

import 'package:googleapis/firestore/v1.dart';
import 'package:googleapis_auth/auth_io.dart' as auth_io;

const _scopes = <String>[FirestoreApi.datastoreScope];
const _pageSize = 200;

Future<void> main(List<String> args) async {
  final dryRun = args.contains('--dry-run');
  final projectId = Platform.environment['GOOGLE_CLOUD_PROJECT'];
  if (projectId == null || projectId.isEmpty) {
    stderr.writeln('GOOGLE_CLOUD_PROJECT must be set.');
    exit(2);
  }

  final authClient = await auth_io.clientViaApplicationDefaultCredentials(
    scopes: _scopes,
  );
  final api = FirestoreApi(authClient);

  final parent = 'projects/$projectId/databases/(default)/documents';
  String? pageToken;
  var scanned = 0;
  var patched = 0;

  try {
    do {
      final page = await api.projects.databases.documents.list(
        parent,
        'problems',
        pageSize: _pageSize,
        pageToken: pageToken,
      );

      for (final doc in page.documents ?? const <Document>[]) {
        scanned++;
        final fields = doc.fields ?? const <String, Value>{};
        if (fields.containsKey('hidden')) continue;

        if (dryRun) {
          patched++;
          continue;
        }

        await api.projects.databases.documents.patch(
          Document(fields: {'hidden': Value(booleanValue: false)}),
          doc.name!,
          updateMask_fieldPaths: ['hidden'],
        );
        patched++;
      }

      pageToken = page.nextPageToken;
    } while (pageToken != null && pageToken.isNotEmpty);
  } finally {
    authClient.close();
  }

  stdout.writeln(
    'scanned=$scanned patched=$patched dryRun=$dryRun project=$projectId',
  );
}
