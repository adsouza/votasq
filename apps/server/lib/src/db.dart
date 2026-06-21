import 'dart:convert';
import 'dart:io';

import 'package:googleapis/firestore/v1.dart' as fs;
import 'package:googleapis_auth/auth_io.dart';
import 'package:http/http.dart' as http;
import 'package:shared/shared.dart';

/// HTTP client that adds the `Bearer owner` token to bypass Firestore
/// security rules in the emulator.
class _EmulatorAdminClient extends http.BaseClient {
  _EmulatorAdminClient(this._inner);

  final http.Client _inner;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    request.headers['Authorization'] = 'Bearer owner';
    return _inner.send(request);
  }

  @override
  void close() => _inner.close();
}

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
      client = _EmulatorAdminClient(http.Client());
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
    final mainDoc = problemToDocument(problem)
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
        // Cursor values must match the orderBy: votes, lastUpdatedAt, __name__.
        values: [
          fs.Value(integerValue: '${cursor['v']}'),
          fs.Value(timestampValue: cursor['u'] as String),
          fs.Value(referenceValue: cursor['r'] as String),
        ],
        before: false,
      );
    }

    final results = await _firestore.projects.databases.documents.runQuery(
      fs.RunQueryRequest(
        structuredQuery: buildProblemsListingQuery(
          pageSize: pageSize,
          startAt: startAt,
          geoscope: geoscope,
        ),
      ),
      _basePath,
    );

    final problems = <Problem>[];
    String? lastDocName;
    int? lastVotes;
    String? lastUpdatedAtRaw;

    for (final result in results) {
      final doc = result.document;
      if (doc == null) continue;
      final id = doc.name!.split('/').last;
      final problem = documentToProblem(doc, id);
      problems.add(problem);
      lastDocName = doc.name;
      lastVotes = problem.votes;
      // Use the raw timestampValue string (not the parsed DateTime) so the
      // cursor round-trips to the exact stored value, avoiding skip/duplicate.
      lastUpdatedAtRaw = doc.fields?['lastUpdatedAt']?.timestampValue;
    }

    String? nextPageToken;
    if (problems.length == pageSize && lastDocName != null) {
      nextPageToken = base64Encode(
        utf8.encode(
          jsonEncode({
            'v': lastVotes,
            'u': lastUpdatedAtRaw,
            'r': lastDocName,
          }),
        ),
      );
    }

    return (problems: problems, nextPageToken: nextPageToken);
  }

  /// Fetch a [Problem] by id.
  Future<Problem> getProblem(String id) async {
    final doc = await _firestore.projects.databases.documents.get(
      '$_basePath/problems/$id',
    );
    return documentToProblem(doc, id);
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
          description:
              doc.fields?['description']?.stringValue ??
              (throw StateError('Missing required field: description')),
          goal: doc.fields?['goal']?.stringValue ?? '',
          version: _parseVersion(doc.fields),
          archivedAt: _parseTimestamp(
            doc.fields?['archivedAt'] ??
                (throw StateError('Missing required field: archivedAt')),
          ),
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
        description:
            doc.fields?['description']?.stringValue ??
            (throw StateError('Missing required field: description')),
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

  /// Ensure a user document exists in the `users` collection.
  /// Creates one from [user] if missing. Returns the stored [User].
  Future<User> ensureUserDoc(User user) async {
    try {
      final doc = await _firestore.projects.databases.documents.get(
        '$_basePath/users/${user.uid}',
      );
      return User(
        uid: user.uid,
        votes: int.parse(doc.fields?['votes']?.integerValue ?? '0'),
        lastActiveAt: _parseTimestamp(
          doc.fields?['lastActiveAt'] ??
              (throw StateError('Missing required field: lastActiveAt')),
        ),
        displayName: doc.fields?['displayName']?.stringValue,
      );
    } on fs.DetailedApiRequestError catch (e) {
      if (e.status != 404) rethrow;
    }
    final userDoc = _userToDocument(user)
      ..name = '$_basePath/users/${user.uid}';
    await _firestore.projects.databases.documents.commit(
      fs.CommitRequest(writes: [fs.Write(update: userDoc)]),
      _databasePath,
    );
    return user;
  }

  fs.Document _userToDocument(User user) {
    return fs.Document(
      fields: {
        'uid': fs.Value(stringValue: user.uid),
        'votes': fs.Value(integerValue: '${user.votes}'),
        'lastActiveAt': fs.Value(
          timestampValue: user.lastActiveAt.toIso8601String(),
        ),
        if (user.displayName != null)
          'displayName': fs.Value(stringValue: user.displayName),
      },
    );
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
    final updatedProblem = problem.copyWith(votes: problem.votes + 1);
    final problemDoc = problemToDocument(updatedProblem)
      ..name = '$_basePath/problems/$problemId';

    // Read user doc to decrement vote budget.
    int userVotes;
    try {
      final userDoc = await _firestore.projects.databases.documents.get(
        '$_basePath/users/$voterId',
      );
      userVotes = int.parse(
        userDoc.fields?['votes']?.integerValue ?? '0',
      );
    } on fs.DetailedApiRequestError catch (e) {
      if (e.status == 404) {
        userVotes = 0;
      } else {
        rethrow;
      }
    }

    final updatedUserDoc = fs.Document(
      name: '$_basePath/users/$voterId',
      fields: {
        'uid': fs.Value(stringValue: voterId),
        'votes': fs.Value(integerValue: '${userVotes - 1}'),
      },
    );

    await _firestore.projects.databases.documents.commit(
      fs.CommitRequest(
        writes: [
          fs.Write(update: voterDoc),
          fs.Write(update: problemDoc),
          fs.Write(update: updatedUserDoc),
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

  /// Decode a Firestore [fs.Document] into a [Problem]. Exposed (static) so
  /// `apps/server/test/problem_document_round_trip_test.dart` can assert that
  /// every model field round-trips through both serializers — a missed field
  /// here silently drops the stored value to its `@Default`, as happened with
  /// the May 2026 `hidden` regression.
  static Problem documentToProblem(fs.Document doc, String id) {
    return Problem(
      id: id,
      description:
          doc.fields?['description']?.stringValue ??
          (throw StateError('Missing required field: description')),
      goal: doc.fields?['goal']?.stringValue ?? '',
      ownerId:
          doc.fields?['ownerId']?.stringValue ??
          (throw StateError('Missing required field: ownerId')),
      geoscope: doc.fields?['geoscope']?.stringValue ?? '/',
      lang: doc.fields?['lang']?.stringValue,
      votes: int.parse(
        doc.fields?['votes']?.integerValue ??
            (throw StateError('Missing required field: votes')),
      ),
      complaints: _parseStringList(doc.fields?['complaints']),
      solved: doc.fields?['solved']?.booleanValue ?? false,
      hidden: doc.fields?['hidden']?.booleanValue ?? false,
      version: _parseVersion(doc.fields),
      createdAt: _parseTimestamp(
        doc.fields?['createdAt'] ??
            (throw StateError('Missing required field: createdAt')),
      ),
      lastUpdatedAt: _parseTimestamp(
        doc.fields?['lastUpdatedAt'] ??
            (throw StateError('Missing required field: lastUpdatedAt')),
      ),
      inspoProblemId: doc.fields?['inspoProblemId']?.stringValue,
      inspoVersion: _parseOptionalInt(doc.fields?['inspoVersion']),
      linkedProblemIds: _parseStringList(doc.fields?['linkedProblemIds']),
      typedLinks: _parseProblemLinkList(doc.fields?['typedLinks']),
    );
  }

  /// Encode a [Problem] as a Firestore [fs.Document]. Static partner of
  /// [documentToProblem]; same testing rationale.
  static fs.Document problemToDocument(Problem problem) {
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
        'hidden': fs.Value(booleanValue: problem.hidden),
        'version': fs.Value(integerValue: '${problem.version}'),
        'createdAt': fs.Value(
          timestampValue: problem.createdAt.toIso8601String(),
        ),
        'lastUpdatedAt': fs.Value(
          timestampValue: problem.lastUpdatedAt.toIso8601String(),
        ),
        if (problem.inspoProblemId != null)
          'inspoProblemId': fs.Value(stringValue: problem.inspoProblemId),
        if (problem.inspoVersion != null)
          'inspoVersion': fs.Value(integerValue: '${problem.inspoVersion}'),
        'linkedProblemIds': fs.Value(
          arrayValue: fs.ArrayValue(
            values: problem.linkedProblemIds
                .map((id) => fs.Value(stringValue: id))
                .toList(),
          ),
        ),
        'typedLinks': fs.Value(
          arrayValue: fs.ArrayValue(
            values: problem.typedLinks
                .map(
                  (link) => fs.Value(
                    mapValue: fs.MapValue(
                      fields: {
                        'targetId': fs.Value(stringValue: link.targetId),
                        'kind': fs.Value(
                          stringValue: _problemLinkKindToWire(link.kind),
                        ),
                      },
                    ),
                  ),
                )
                .toList(),
          ),
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

  static List<ProblemLink> _parseProblemLinkList(fs.Value? value) {
    final entries = value?.arrayValue?.values;
    if (entries == null) return const [];
    return entries.map((v) {
      final fields = v.mapValue?.fields ?? const <String, fs.Value>{};
      final targetId =
          fields['targetId']?.stringValue ??
          (throw StateError('Missing required field: typedLinks.targetId'));
      final wire =
          fields['kind']?.stringValue ??
          (throw StateError('Missing required field: typedLinks.kind'));
      return ProblemLink(
        targetId: targetId,
        kind: _problemLinkKindFromWire(wire),
      );
    }).toList();
  }

  static String _problemLinkKindToWire(ProblemLinkKind kind) => switch (kind) {
    ProblemLinkKind.specialization => 'specialization',
    ProblemLinkKind.generalization => 'generalization',
  };

  static ProblemLinkKind _problemLinkKindFromWire(String wire) =>
      switch (wire) {
        'specialization' => ProblemLinkKind.specialization,
        'generalization' => ProblemLinkKind.generalization,
        _ => throw StateError('Unknown ProblemLinkKind: $wire'),
      };
}

/// Build the Firestore `StructuredQuery` for the problems listing endpoint.
///
/// Extracted from [Db.getProblems] so the query shape can be inspected by
/// tests and asserted against `firestore.indexes.json`. The Firestore
/// emulator does not enforce composite indexes, so this is the only way
/// to catch index drift locally.
fs.StructuredQuery buildProblemsListingQuery({
  required int pageSize,
  fs.Cursor? startAt,
  String? geoscope,
}) {
  final solvedFilter = fs.Filter(
    fieldFilter: fs.FieldFilter(
      field: fs.FieldReference(fieldPath: 'solved'),
      op: 'EQUAL',
      value: fs.Value(booleanValue: false),
    ),
  );
  final hiddenFilter = fs.Filter(
    fieldFilter: fs.FieldFilter(
      field: fs.FieldReference(fieldPath: 'hidden'),
      op: 'EQUAL',
      value: fs.Value(booleanValue: false),
    ),
  );

  final fs.Filter whereFilter;
  if (geoscope != null) {
    final ancestors = geoscopeAncestors(geoscope);
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
        filters: [solvedFilter, hiddenFilter, geoscopeFilter],
      ),
    );
  } else {
    whereFilter = fs.Filter(
      compositeFilter: fs.CompositeFilter(
        op: 'AND',
        filters: [solvedFilter, hiddenFilter],
      ),
    );
  }

  return fs.StructuredQuery(
    from: [fs.CollectionSelector(collectionId: 'problems')],
    where: whereFilter,
    orderBy: [
      fs.Order(
        field: fs.FieldReference(fieldPath: 'votes'),
        direction: 'DESCENDING',
      ),
      // Most recently touched first within a vote tier. Keep in lockstep with
      // the client query / cubit comparator and the composite index.
      fs.Order(
        field: fs.FieldReference(fieldPath: 'lastUpdatedAt'),
        direction: 'DESCENDING',
      ),
      fs.Order(
        field: fs.FieldReference(fieldPath: '__name__'),
        direction: 'ASCENDING',
      ),
    ],
    limit: pageSize,
    startAt: startAt,
  );
}
