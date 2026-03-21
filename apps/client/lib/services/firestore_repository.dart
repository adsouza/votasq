import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared/shared.dart';
import 'package:uuid/uuid.dart';

/// Direct Firestore access layer, replacing the HTTP API service.
class FirestoreRepository {
  FirestoreRepository({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;
  static const _collection = 'problems';
  static const _pageSize = 20;

  CollectionReference<Map<String, dynamic>> get _problemsRef =>
      _firestore.collection(_collection);

  /// Compute all ancestor geoscopes for a given geoscope string.
  /// E.g. `"na/us/ny/nyc"` → `['/', 'na', 'na/us', 'na/us/ny', 'na/us/ny/nyc']`.
  static List<String> geoscopeAncestors(String geoscope) {
    if (geoscope == '/') return ['/'];
    final parts = geoscope.split('/');
    return [
      '/',
      for (var i = 0; i < parts.length; i++) parts.sublist(0, i + 1).join('/'),
    ];
  }

  /// Unsolved problems matching the given geoscope or any ancestor,
  /// ordered by votes DESC then doc ID ASC.
  Query<Map<String, dynamic>> _geoscopedQuery(String geoscope) => _problemsRef
      .where('geoscope', whereIn: geoscopeAncestors(geoscope))
      .where('solved', isEqualTo: false)
      .orderBy('votes', descending: true)
      .orderBy(FieldPath.documentId);

  /// Real-time stream of the first page of unsolved problems
  /// matching the given [geoscope] or any of its ancestors.
  Stream<({List<Problem> problems, DocumentSnapshot? lastDoc})> watchProblems({
    required String geoscope,
    int limit = _pageSize,
  }) {
    return _geoscopedQuery(geoscope).limit(limit).snapshots().map((snapshot) {
      final problems = snapshot.docs.map(_docToProblem).toList();
      final lastDoc = snapshot.docs.isNotEmpty ? snapshot.docs.last : null;
      return (problems: problems, lastDoc: lastDoc);
    });
  }

  /// Fetch a page of problems for infinite scroll,
  /// matching the given [geoscope] or any of its ancestors.
  Future<({List<Problem> problems, DocumentSnapshot? lastDoc})> getProblems({
    required String geoscope,
    int pageSize = _pageSize,
    DocumentSnapshot? startAfter,
  }) async {
    var query = _geoscopedQuery(geoscope).limit(pageSize);
    if (startAfter != null) {
      query = query.startAfterDocument(startAfter);
    }
    final snapshot = await query.get();
    final problems = snapshot.docs.map(_docToProblem).toList();
    final lastDoc = snapshot.docs.isNotEmpty ? snapshot.docs.last : null;
    return (problems: problems, lastDoc: lastDoc);
  }

  /// Create a new problem with a client-generated UUID.
  /// Uses a batched write to atomically create the main document and its
  /// first revision snapshot.
  Future<void> addProblem({
    required String description,
    required String ownerId,
    required String geoscope,
  }) async {
    final id = const Uuid().v4();
    final now = DateTime.now().toUtc();
    const version = 1;
    final problemData = {
      'description': description,
      'ownerId': ownerId,
      'geoscope': geoscope,
      'votes': 1,
      'solved': false,
      'version': version,
      'createdAt': now,
      'lastUpdatedAt': now,
    };
    final revisionData = {
      'description': description,
      'version': version,
      'archivedAt': now,
    };

    final batch = _firestore.batch()
      ..set(_problemsRef.doc(id), problemData)
      ..set(
        _problemsRef.doc(id).collection('versions').doc('$version'),
        revisionData,
      );
    await batch.commit();
  }

  /// Update a problem's fields.
  /// Uses a batched write to atomically update the main document and create
  /// a new revision snapshot.
  Future<void> updateProblem(Problem problem) async {
    final now = DateTime.now().toUtc();
    final newVersion = problem.version + 1;
    final mainData = {
      'description': problem.description,
      'geoscope': problem.geoscope,
      'votes': problem.votes,
      'complaints': problem.complaints,
      'solved': problem.solved,
      'version': newVersion,
      'lastUpdatedAt': now,
    };
    final revisionData = {
      'description': problem.description,
      'version': newVersion,
      'archivedAt': now,
    };

    final batch = _firestore.batch()
      ..update(_problemsRef.doc(problem.id), mainData)
      ..set(
        _problemsRef.doc(problem.id).collection('versions').doc('$newVersion'),
        revisionData,
      );
    await batch.commit();
  }

  /// Atomically add a user's complaint to a problem.
  /// Uses FieldValue.arrayUnion for concurrent-safe, idempotent append.
  Future<void> addComplaint({
    required String problemId,
    required String userId,
  }) async {
    await _problemsRef.doc(problemId).update({
      'complaints': FieldValue.arrayUnion([userId]),
    });
  }

  /// Fetch available geoscopes from the `geoscopes` collection,
  /// sorted by population descending.
  Future<List<({String id, String label})>> getGeoscopes() async {
    final snapshot = await _firestore.collection('geoscopes').get();
    final docs = snapshot.docs.toList()
      ..sort((a, b) {
        final popA = (a.data()['population'] as num?) ?? 0;
        final popB = (b.data()['population'] as num?) ?? 0;
        return popB.compareTo(popA);
      });
    return docs.map((doc) {
      final data = doc.data();
      return (
        id: data['id'] as String? ?? doc.id,
        label: data['label'] as String? ?? doc.id,
      );
    }).toList();
  }

  Problem _docToProblem(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data()!;
    return Problem(
      id: doc.id,
      description: data['description'] as String,
      ownerId: data['ownerId'] as String,
      geoscope: data['geoscope'] as String? ?? '/',
      votes: (data['votes'] as num).toInt(),
      complaints:
          (data['complaints'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          [],
      solved: data['solved'] as bool? ?? false,
      version: (data['version'] as num?)?.toInt() ?? 1,
      createdAt: (data['createdAt'] as Timestamp).toDate(),
      lastUpdatedAt: (data['lastUpdatedAt'] as Timestamp).toDate(),
    );
  }
}
