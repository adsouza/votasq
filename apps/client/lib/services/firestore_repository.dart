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
  Future<void> addProblem({required String description}) async {
    final id = const Uuid().v4();
    await _problemsRef.doc(id).set({
      'description': description,
      'votes': 1,
      'solved': false,
      'createdAt': FieldValue.serverTimestamp(),
      'lastUpdatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Update a problem's fields.
  Future<void> updateProblem(Problem problem) async {
    await _problemsRef.doc(problem.id).update({
      'description': problem.description,
      'votes': problem.votes,
      'solved': problem.solved,
      'lastUpdatedAt': FieldValue.serverTimestamp(),
    });
  }

  Problem _docToProblem(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data()!;
    return Problem(
      id: doc.id,
      description: data['description'] as String,
      votes: (data['votes'] as num).toInt(),
      solved: data['solved'] as bool? ?? false,
      createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
      lastUpdatedAt: (data['lastUpdatedAt'] as Timestamp?)?.toDate(),
    );
  }
}
