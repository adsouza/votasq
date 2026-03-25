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
  Db._(this._firestore, this._basePath, this._databasePath);

  final fs.FirestoreApi _firestore;
  final String _basePath;
  final String _databasePath;

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
    final databasePath = 'projects/$projectId/databases/(default)';
    final basePath = '$databasePath/documents';
    return Db._(firestore, basePath, databasePath);
  }

  /// Persist a [Problem] document and its revision snapshot atomically.
  Future<void> saveProblem(Problem problem) async {
    final mainDoc = _problemToDocument(problem)
      ..name = '$_basePath/problems/${problem.id}';
    final revision = ProblemRevision(
      description: problem.description,
      goal: problem.goal,
      version: problem.version,
      archivedAt: problem.lastUpdatedAt,
    );
    final revisionDoc = _revisionToDocument(revision)
      ..name = '$_basePath/problems/${problem.id}/versions/${problem.version}';

    await _firestore.projects.databases.documents.commit(
      fs.CommitRequest(
        writes: [
          fs.Write(update: mainDoc),
          fs.Write(update: revisionDoc),
        ],
      ),
      _databasePath,
    );
  }

  /// Compute all ancestor geoscopes for a given geoscope string.
  /// E.g. `"na/us/ny/nyc"` → `['/', 'na', 'na/us', 'na/us/ny', 'na/us/ny/nyc']`.
  static List<String> _geoscopeAncestors(String geoscope) {
    if (geoscope == '/') return ['/'];
    final parts = geoscope.split('/');
    return [
      '/',
      for (var i = 0; i < parts.length; i++) parts.sublist(0, i + 1).join('/'),
    ];
  }

  /// Fetch a page of problems, sorted by votes descending.
  /// When [geoscope] is provided, filters to problems matching that geoscope
  /// or any of its ancestors (e.g. country-level and global problems).
  Future<({List<Problem> problems, String? nextPageToken})> getProblems({
    int pageSize = 99,
    String? pageToken,
    String? geoscope,
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

    final solvedFilter = fs.Filter(
      fieldFilter: fs.FieldFilter(
        field: fs.FieldReference(fieldPath: 'solved'),
        op: 'EQUAL',
        value: fs.Value(booleanValue: false),
      ),
    );

    final fs.Filter whereFilter;
    if (geoscope != null) {
      final ancestors = _geoscopeAncestors(geoscope);
      final geoscopeFilter = fs.Filter(
        compositeFilter: fs.CompositeFilter(
          op: 'OR',
          filters: [
            for (final ancestor in ancestors)
              fs.Filter(
                fieldFilter: fs.FieldFilter(
                  field: fs.FieldReference(fieldPath: 'geoscope'),
                  op: 'EQUAL',
                  value: fs.Value(stringValue: ancestor),
                ),
              ),
          ],
        ),
      );
      whereFilter = fs.Filter(
        compositeFilter: fs.CompositeFilter(
          op: 'AND',
          filters: [solvedFilter, geoscopeFilter],
        ),
      );
    } else {
      whereFilter = solvedFilter;
    }

    final results = await _firestore.projects.databases.documents.runQuery(
      fs.RunQueryRequest(
        structuredQuery: fs.StructuredQuery(
          from: [fs.CollectionSelector(collectionId: 'problems')],
          where: whereFilter,
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
          goal: doc.fields?['goal']?.stringValue ?? '',
          ownerId: doc.fields!['ownerId']!.stringValue!,
          geoscope: doc.fields?['geoscope']?.stringValue ?? '/',
          lang: doc.fields?['lang']?.stringValue,
          votes: votes,
          complaints: _parseStringList(doc.fields?['complaints']),
          solved: doc.fields?['solved']?.booleanValue ?? false,
          version: _parseVersion(doc.fields),
          createdAt: _parseTimestamp(doc.fields!['createdAt']!),
          lastUpdatedAt: _parseTimestamp(doc.fields!['lastUpdatedAt']!),
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
      goal: doc.fields?['goal']?.stringValue ?? '',
      ownerId: doc.fields!['ownerId']!.stringValue!,
      geoscope: doc.fields?['geoscope']?.stringValue ?? '/',
      lang: doc.fields?['lang']?.stringValue,
      votes: int.parse(doc.fields!['votes']!.integerValue!),
      complaints: _parseStringList(doc.fields?['complaints']),
      solved: doc.fields?['solved']?.booleanValue ?? false,
      version: _parseVersion(doc.fields),
      createdAt: _parseTimestamp(doc.fields!['createdAt']!),
      lastUpdatedAt: _parseTimestamp(doc.fields!['lastUpdatedAt']!),
    );
  }

  /// Fetch all revisions of a [Problem], ordered by version ascending.
  Future<List<ProblemRevision>> getVersions(String problemId) async {
    final results = await _firestore.projects.databases.documents.runQuery(
      fs.RunQueryRequest(
        structuredQuery: fs.StructuredQuery(
          from: [fs.CollectionSelector(collectionId: 'versions')],
          orderBy: [
            fs.Order(
              field: fs.FieldReference(fieldPath: 'version'),
              direction: 'ASCENDING',
            ),
          ],
        ),
      ),
      '$_basePath/problems/$problemId',
    );

    final revisions = <ProblemRevision>[];
    for (final result in results) {
      final doc = result.document;
      if (doc == null) continue;
      revisions.add(
        ProblemRevision(
          description: doc.fields!['description']!.stringValue!,
          goal: doc.fields?['goal']?.stringValue ?? '',
          version: _parseVersion(doc.fields),
          archivedAt: _parseTimestamp(doc.fields!['archivedAt']!),
          restoredFrom: _parseOptionalInt(doc.fields?['restoredFrom']),
        ),
      );
    }
    return revisions;
  }

  /// Fetch a cached [TranslatedProblem] for the given problem and language.
  /// Returns `null` if no cached translation exists.
  Future<TranslatedProblem?> getTranslation(
    String problemId,
    String langCode,
  ) async {
    try {
      final doc = await _firestore.projects.databases.documents.get(
        '$_basePath/problems/$problemId/translations/$langCode',
      );
      return TranslatedProblem(
        description: doc.fields!['description']!.stringValue!,
        goal: doc.fields?['goal']?.stringValue ?? '',
      );
    } on fs.DetailedApiRequestError catch (e) {
      if (e.status == 404) return null;
      rethrow;
    }
  }

  /// Cache a [TranslatedProblem] for the given problem and language.
  Future<void> saveTranslation(
    String problemId,
    String langCode,
    TranslatedProblem translation,
  ) async {
    final doc = _translatedProblemToDocument(translation)
      ..name = '$_basePath/problems/$problemId/translations/$langCode';
    await _firestore.projects.databases.documents.commit(
      fs.CommitRequest(writes: [fs.Write(update: doc)]),
      _databasePath,
    );
  }

  /// Delete all cached translations for a problem.
  Future<void> deleteTranslations(String problemId) async {
    String? pageToken;
    do {
      final response = await _firestore.projects.databases.documents.list(
        '$_basePath/problems/$problemId',
        'translations',
        mask_fieldPaths: [],
        pageToken: pageToken,
      );
      final docs = response.documents;
      if (docs == null || docs.isEmpty) return;
      await _firestore.projects.databases.documents.commit(
        fs.CommitRequest(
          writes: [for (final doc in docs) fs.Write(delete: doc.name)],
        ),
        _databasePath,
      );
      pageToken = response.nextPageToken;
    } while (pageToken != null);
  }

  /// Write a voter doc without modifying the problem's vote count.
  /// Used during problem creation where the problem already has the
  /// correct vote total.
  Future<void> saveVoterDoc({
    required String problemId,
    required String voterId,
    required int votes,
  }) async {
    final voterDoc = fs.Document(
      name: '$_basePath/problems/$problemId/voters/$voterId',
      fields: {
        'uid': fs.Value(stringValue: voterId),
        'votes': fs.Value(integerValue: '$votes'),
      },
    );
    await _firestore.projects.databases.documents.commit(
      fs.CommitRequest(writes: [fs.Write(update: voterDoc)]),
      _databasePath,
    );
  }

  /// Atomically write a voter doc and increment the problem's vote count.
  Future<void> voteForProblem({
    required String problemId,
    required String voterId,
  }) async {
    // Read existing voter doc to determine current vote count.
    int currentVotes;
    try {
      final existing = await _firestore.projects.databases.documents.get(
        '$_basePath/problems/$problemId/voters/$voterId',
      );
      currentVotes = int.parse(existing.fields?['votes']?.integerValue ?? '0');
    } on fs.DetailedApiRequestError catch (e) {
      if (e.status == 404) {
        currentVotes = 0;
      } else {
        rethrow;
      }
    }

    final newVotes = currentVotes + 1;
    final voterDoc = fs.Document(
      name: '$_basePath/problems/$problemId/voters/$voterId',
      fields: {
        'uid': fs.Value(stringValue: voterId),
        'votes': fs.Value(integerValue: '$newVotes'),
      },
    );

    // Read problem to compute new total.
    final problem = await getProblem(problemId);
    final updatedProblem = Problem(
      id: problem.id,
      description: problem.description,
      goal: problem.goal,
      ownerId: problem.ownerId,
      geoscope: problem.geoscope,
      lang: problem.lang,
      votes: problem.votes + 1,
      complaints: problem.complaints,
      solved: problem.solved,
      version: problem.version,
      createdAt: problem.createdAt,
      lastUpdatedAt: problem.lastUpdatedAt,
    );
    final problemDoc = _problemToDocument(updatedProblem)
      ..name = '$_basePath/problems/$problemId';

    await _firestore.projects.databases.documents.commit(
      fs.CommitRequest(
        writes: [
          fs.Write(update: voterDoc),
          fs.Write(update: problemDoc),
        ],
      ),
      _databasePath,
    );
  }

  /// Fetch all problem IDs that a user has voted for
  /// via collection group query.
  Future<List<String>> getVotedProblemIds(String userId) async {
    final results = await _firestore.projects.databases.documents.runQuery(
      fs.RunQueryRequest(
        structuredQuery: fs.StructuredQuery(
          from: [
            fs.CollectionSelector(
              collectionId: 'voters',
              allDescendants: true,
            ),
          ],
          where: fs.Filter(
            fieldFilter: fs.FieldFilter(
              field: fs.FieldReference(fieldPath: 'uid'),
              op: 'EQUAL',
              value: fs.Value(stringValue: userId),
            ),
          ),
        ),
      ),
      _basePath,
    );

    return results.where((r) => r.document != null).map((r) {
      // Path: .../problems/{problemId}/voters/{voterId}
      final parts = r.document!.name!.split('/');
      final problemsIndex = parts.lastIndexOf('problems');
      return parts[problemsIndex + 1];
    }).toList();
  }

  fs.Document _problemToDocument(Problem problem) {
    return fs.Document(
      fields: {
        'description': fs.Value(stringValue: problem.description),
        'goal': fs.Value(stringValue: problem.goal),
        'ownerId': fs.Value(stringValue: problem.ownerId),
        'geoscope': fs.Value(stringValue: problem.geoscope),
        if (problem.lang != null) 'lang': fs.Value(stringValue: problem.lang),
        'votes': fs.Value(integerValue: '${problem.votes}'),
        'complaints': fs.Value(
          arrayValue: fs.ArrayValue(
            values: problem.complaints
                .map((uid) => fs.Value(stringValue: uid))
                .toList(),
          ),
        ),
        'solved': fs.Value(booleanValue: problem.solved),
        'version': fs.Value(integerValue: '${problem.version}'),
        'createdAt': fs.Value(
          timestampValue: problem.createdAt.toIso8601String(),
        ),
        'lastUpdatedAt': fs.Value(
          timestampValue: problem.lastUpdatedAt.toIso8601String(),
        ),
      },
    );
  }

  fs.Document _translatedProblemToDocument(TranslatedProblem translation) {
    return fs.Document(
      fields: {
        'description': fs.Value(stringValue: translation.description),
        'goal': fs.Value(stringValue: translation.goal),
      },
    );
  }

  fs.Document _revisionToDocument(ProblemRevision revision) {
    return fs.Document(
      fields: {
        'description': fs.Value(stringValue: revision.description),
        'goal': fs.Value(stringValue: revision.goal),
        'version': fs.Value(integerValue: '${revision.version}'),
        'archivedAt': fs.Value(
          timestampValue: revision.archivedAt.toIso8601String(),
        ),
        if (revision.restoredFrom != null)
          'restoredFrom': fs.Value(
            integerValue: '${revision.restoredFrom}',
          ),
      },
    );
  }

  /// Parse the version field, defaulting to 1 for backward compatibility.
  static int _parseVersion(Map<String, fs.Value>? fields) =>
      int.parse(fields?['version']?.integerValue ?? '1');

  static int? _parseOptionalInt(fs.Value? value) =>
      value?.integerValue != null ? int.parse(value!.integerValue!) : null;

  static DateTime _parseTimestamp(fs.Value value) =>
      DateTime.parse(value.timestampValue!);

  static List<String> _parseStringList(fs.Value? value) =>
      value?.arrayValue?.values?.map((v) => v.stringValue!).toList() ?? [];
}
