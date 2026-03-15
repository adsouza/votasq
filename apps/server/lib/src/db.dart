import 'dart:convert';
import 'dart:io';

import 'package:googleapis/firestore/v1.dart' as fs;
import 'package:googleapis_auth/auth_io.dart';
import 'package:http/http.dart' as http;
import 'package:shared/shared.dart';

/// Storage via Firestore using the official googleapis client.
/// Authenticates automatically via App Default Creds on Cloud Run.
/// When the FIRESTORE_EMULATOR_HOST env var is set, connects to the local
/// emulator without authentication.
class Db {
  Db._(this._firestore, this._basePath);

  final fs.FirestoreApi _firestore;
  final String _basePath;

  /// Creates a [Db] instance authenticated via ADC, or unauthenticated when
  /// connecting to the Firestore emulator.
  static Future<Db> initialize(String projectId) async {
    final emulatorHost = Platform.environment['FIRESTORE_EMULATOR_HOST'];
    final http.Client client;
    final String? rootUrl;

    if (emulatorHost != null) {
      client = http.Client();
      rootUrl = 'http://$emulatorHost/';
    } else {
      client = await clientViaApplicationDefaultCredentials(
        scopes: [fs.FirestoreApi.datastoreScope],
      );
      rootUrl = null;
    }

    final firestore = fs.FirestoreApi(
      client,
      rootUrl: rootUrl ?? 'https://firestore.googleapis.com/',
    );
    final basePath = 'projects/$projectId/databases/(default)/documents';
    return Db._(firestore, basePath);
  }

  /// Persist a [Problem] document (create or overwrite).
  Future<void> saveProblem(Problem problem) async {
    final document = fs.Document(
      fields: {
        'description': fs.Value(stringValue: problem.description),
        'votes': fs.Value(integerValue: '${problem.votes}'),
      },
    );
    await _firestore.projects.databases.documents.patch(
      document,
      '$_basePath/problems/${problem.id}',
    );
  }

  /// Fetch a page of problems, sorted by votes descending.
  Future<({List<Problem> problems, String? nextPageToken})> getProblems({
    int pageSize = 99,
    String? pageToken,
  }) async {
    fs.Cursor? startAt;
    if (pageToken != null) {
      final cursor =
          jsonDecode(utf8.decode(base64Decode(pageToken)))
              as Map<String, dynamic>;
      startAt = fs.Cursor(
        values: [
          fs.Value(integerValue: '${cursor['v']}'),
          fs.Value(referenceValue: cursor['r'] as String),
        ],
        before: false,
      );
    }

    final results = await _firestore.projects.databases.documents.runQuery(
      fs.RunQueryRequest(
        structuredQuery: fs.StructuredQuery(
          from: [fs.CollectionSelector(collectionId: 'problems')],
          orderBy: [
            fs.Order(
              field: fs.FieldReference(fieldPath: 'votes'),
              direction: 'DESCENDING',
            ),
            fs.Order(
              field: fs.FieldReference(fieldPath: '__name__'),
              direction: 'ASCENDING',
            ),
          ],
          limit: pageSize,
          startAt: startAt,
        ),
      ),
      _basePath,
    );

    final problems = <Problem>[];
    String? lastDocName;
    int? lastVotes;

    for (final result in results) {
      final doc = result.document;
      if (doc == null) continue;
      final id = doc.name!.split('/').last;
      final votes = int.parse(doc.fields!['votes']!.integerValue!);
      problems.add(
        Problem(
          id: id,
          description: doc.fields!['description']!.stringValue!,
          votes: votes,
        ),
      );
      lastDocName = doc.name;
      lastVotes = votes;
    }

    String? nextPageToken;
    if (problems.length == pageSize && lastDocName != null) {
      nextPageToken = base64Encode(
        utf8.encode(jsonEncode({'v': lastVotes, 'r': lastDocName})),
      );
    }

    return (problems: problems, nextPageToken: nextPageToken);
  }

  /// Fetch a [Problem] by id.
  Future<Problem> getProblem(String id) async {
    final doc = await _firestore.projects.databases.documents.get(
      '$_basePath/problems/$id',
    );
    return Problem(
      id: id,
      description: doc.fields!['description']!.stringValue!,
      votes: int.parse(doc.fields!['votes']!.integerValue!),
    );
  }
}
