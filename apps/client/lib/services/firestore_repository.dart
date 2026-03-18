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

  /// Unsolved problems, ordered by votes DESC then doc ID ASC.
  Query<Map<String, dynamic>> get _baseQuery => _problemsRef
      .where('solved', isEqualTo: false)
      .orderBy('votes', descending: true)
      .orderBy(FieldPath.documentId);

  /// Real-time stream of the first page of unsolved problems.
  Stream<({List<Problem> problems, DocumentSnapshot? lastDoc})> watchProblems({
    int limit = _pageSize,
  }) {
    return _baseQuery.limit(limit).snapshots().map((snapshot) {
      final problems = snapshot.docs.map(_docToProblem).toList();
      final lastDoc = snapshot.docs.isNotEmpty ? snapshot.docs.last : null;
      return (problems: problems, lastDoc: lastDoc);
    });
  }

  /// Fetch a page of problems for infinite scroll.
  Future<({List<Problem> problems, DocumentSnapshot? lastDoc})> getProblems({
    int pageSize = _pageSize,
    DocumentSnapshot? startAfter,
  }) async {
    var query = _baseQuery.limit(pageSize);
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
  Future<void> addProblem({required String description}) async {
    final id = const Uuid().v4();
    final now = DateTime.now().toUtc();
    const version = 1;
    final problemData = {
      'description': description,
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
      'votes': problem.votes,
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

  Problem _docToProblem(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data()!;
    return Problem(
      id: doc.id,
      description: data['description'] as String,
      votes: (data['votes'] as num).toInt(),
      solved: data['solved'] as bool? ?? false,
      version: (data['version'] as num?)?.toInt() ?? 1,
      createdAt: (data['createdAt'] as Timestamp).toDate(),
      lastUpdatedAt: (data['lastUpdatedAt'] as Timestamp).toDate(),
    );
  }
}
