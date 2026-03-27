import 'dart:async';
import 'dart:developer';
import 'dart:math' as math;

import 'package:client/services/language_detection_service.dart';
import 'package:client/services/translation_repository.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared/shared.dart';
import 'package:uuid/uuid.dart';

/// Thrown when the description and goal are detected as different languages.
class LanguageMismatchException implements Exception {
  const LanguageMismatchException({
    required this.descriptionLang,
    required this.goalLang,
  });

  final String descriptionLang;
  final String goalLang;
}

/// Result of language detection. When the server fallback is used, English
/// translations come back for free and can be cached.
typedef DetectionResult = ({
  String lang,
  TranslatedProblem? englishTranslation,
});

/// Direct Firestore access layer, replacing the HTTP API service.
///
/// Language detection is handled here (not in views) because the ML Kit
/// packages register method channels that break text input on desktop
/// platforms. Keeping the import chain in the service layer prevents views
/// from transitively pulling in those packages.
class FirestoreRepository {
  FirestoreRepository({
    FirebaseFirestore? firestore,
    LanguageDetectionService? languageDetectionService,
    TranslationRepository? translationRepository,
  }) : _firestore = firestore ?? FirebaseFirestore.instance,
       _langService = languageDetectionService ?? LanguageDetectionService(),
       _translationRepo = translationRepository;

  final FirebaseFirestore _firestore;
  final LanguageDetectionService _langService;
  final TranslationRepository? _translationRepo;
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

  /// Fetch a single problem by its document ID.
  /// Returns `null` if the document does not exist.
  Future<Problem?> getProblem(String id) async {
    final doc = await _problemsRef.doc(id).get();
    if (!doc.exists) return null;
    return _docToProblem(doc);
  }

  /// Create a new problem with a client-generated UUID.
  /// Uses a batched write to atomically create the main document and its
  /// first revision snapshot.
  Future<void> addProblem({
    required String description,
    required String ownerId,
    required String geoscope,
    required String userLanguage,
    String goal = '',
  }) async {
    final result = await _detectAndValidateLang(
      description,
      goal,
      userLanguage,
    );
    final id = const Uuid().v4();
    final now = DateTime.now().toUtc();
    const version = 1;
    final problemData = {
      'description': description,
      'goal': goal,
      'ownerId': ownerId,
      'geoscope': geoscope,
      'lang': result.lang,
      'votes': 1,
      'solved': false,
      'version': version,
      'createdAt': now,
      'lastUpdatedAt': now,
    };
    final revisionData = {
      'description': description,
      'goal': goal,
      'version': version,
      'archivedAt': now,
    };

    final batch = _firestore.batch()
      ..set(_problemsRef.doc(id), problemData)
      ..set(
        _problemsRef.doc(id).collection('versions').doc('$version'),
        revisionData,
      )
      ..set(
        _problemsRef.doc(id).collection('voters').doc(ownerId),
        {'uid': ownerId, 'votes': 1},
      );
    await batch.commit();

    // Cache the free English translation if the server fallback was used.
    final english = result.englishTranslation;
    if (english != null) {
      unawaited(saveTranslation(id, 'en', english));
    }
  }

  /// Update a problem's fields.
  /// Uses a batched write to atomically update the main document and create
  /// a new revision snapshot.
  ///
  /// If [userLanguage] is provided, re-detects the description language.
  Future<void> updateProblem(
    Problem problem, {
    String? userLanguage,
  }) async {
    final result = userLanguage != null
        ? await _detectAndValidateLang(
            problem.description,
            problem.goal,
            userLanguage,
          )
        : null;
    final lang = result?.lang ?? problem.lang;

    // Invalidate cached translations when the text changes.
    final existing = await _problemsRef.doc(problem.id).get();
    if (existing.exists &&
        (existing.data()?['description'] != problem.description ||
            existing.data()?['goal'] != problem.goal)) {
      await _deleteTranslations(problem.id);
    }

    final now = DateTime.now().toUtc();
    final newVersion = problem.version + 1;
    final mainData = {
      'description': problem.description,
      'goal': problem.goal,
      'geoscope': problem.geoscope,
      'lang': ?lang,
      'votes': problem.votes,
      'complaints': problem.complaints,
      'solved': problem.solved,
      'version': newVersion,
      'lastUpdatedAt': now,
    };
    final revisionData = {
      'description': problem.description,
      'goal': problem.goal,
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

    // Cache the free English translation if the server fallback was used.
    final english = result?.englishTranslation;
    if (english != null) {
      unawaited(saveTranslation(problem.id, 'en', english));
    }
  }

  /// Detects the language of [description] and [goal], validating that both
  /// fields are in the same language. Throws [LanguageMismatchException] if
  /// they differ.
  ///
  /// When the server fallback is used, returns English translations obtained
  /// for free alongside the detected language.
  Future<DetectionResult> _detectAndValidateLang(
    String description,
    String goal,
    String userLanguage,
  ) async {
    final descForeign = await _langService.needsTranslation(
      text: description,
      userLanguage: userLanguage,
    );

    // No goal — single-field detection only.
    if (goal.isEmpty) {
      return _detectSingleLang(description, descForeign, userLanguage);
    }

    final goalForeign = await _langService.needsTranslation(
      text: goal,
      userLanguage: userLanguage,
    );

    // Both match the user's language.
    if (!descForeign && !goalForeign) {
      return (lang: userLanguage, englishTranslation: null);
    }

    // One matches, one doesn't — mismatch.
    if (descForeign != goalForeign) {
      final descLang = descForeign
          ? await _langService.detectLanguage(description) ?? '?'
          : userLanguage;
      final goalLang = goalForeign
          ? await _langService.detectLanguage(goal) ?? '?'
          : userLanguage;
      throw LanguageMismatchException(
        descriptionLang: descLang,
        goalLang: goalLang,
      );
    }

    // Both foreign — detect each on-device and check they agree.
    final descLang = await _langService.detectLanguage(description);
    final goalLang = await _langService.detectLanguage(goal);

    if (descLang != null && goalLang != null && descLang != goalLang) {
      throw LanguageMismatchException(
        descriptionLang: descLang,
        goalLang: goalLang,
      );
    }

    // Use whichever was detected on-device.
    final detected = descLang ?? goalLang;
    if (detected != null) {
      return (lang: detected, englishTranslation: null);
    }

    // Fall back to server: translate both fields to English. This gives us
    // language detection for free plus cacheable English translations.
    final repo = _translationRepo;
    if (repo != null) {
      try {
        final descResult = await repo.translateToEnglish(description);
        final goalResult = await repo.translateToEnglish(goal);
        if (descResult.detectedLanguage != goalResult.detectedLanguage) {
          throw LanguageMismatchException(
            descriptionLang: descResult.detectedLanguage,
            goalLang: goalResult.detectedLanguage,
          );
        }
        return (
          lang: descResult.detectedLanguage,
          englishTranslation: TranslatedProblem(
            description: descResult.translation,
            goal: goalResult.translation,
          ),
        );
      } on LanguageMismatchException {
        rethrow;
      } on Exception catch (e) {
        log('Server language detection failed: $e');
      }
    }

    return (lang: 'und', englishTranslation: null);
  }

  /// Single-field language detection (no cross-field validation needed).
  Future<DetectionResult> _detectSingleLang(
    String text,
    bool isForeign,
    String userLanguage,
  ) async {
    if (!isForeign) return (lang: userLanguage, englishTranslation: null);

    final detected = await _langService.detectLanguage(text);
    if (detected != null) return (lang: detected, englishTranslation: null);

    final repo = _translationRepo;
    if (repo != null) {
      try {
        final result = await repo.translateToEnglish(text);
        return (
          lang: result.detectedLanguage,
          englishTranslation: TranslatedProblem(
            description: result.translation,
          ),
        );
      } on Exception catch (e) {
        log('Server language detection failed: $e');
      }
    }

    return (lang: 'und', englishTranslation: null);
  }

  /// Fetch a cached [TranslatedProblem] for the given problem and language.
  /// Returns `null` if no cached translation exists.
  Future<TranslatedProblem?> getTranslation(
    String problemId,
    String langCode,
  ) async {
    final doc = await _problemsRef
        .doc(problemId)
        .collection('translations')
        .doc(langCode)
        .get();
    if (!doc.exists) return null;
    final data = doc.data();
    if (data == null) return null;
    return TranslatedProblem(
      description: data['description'] as String,
      goal: data['goal'] as String? ?? '',
    );
  }

  /// Cache a [TranslatedProblem] for the given problem and language.
  Future<void> saveTranslation(
    String problemId,
    String langCode,
    TranslatedProblem translation,
  ) async {
    await _problemsRef
        .doc(problemId)
        .collection('translations')
        .doc(langCode)
        .set({
          'description': translation.description,
          'goal': translation.goal,
        });
  }

  /// Delete all cached translations for a problem.
  Future<void> _deleteTranslations(String problemId) async {
    final snapshot = await _problemsRef
        .doc(problemId)
        .collection('translations')
        .get();
    if (snapshot.docs.isEmpty) return;
    final batch = _firestore.batch();
    for (final doc in snapshot.docs) {
      batch.delete(doc.reference);
    }
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

  /// Ensure a user document exists in the `users` collection.
  /// Creates one from [user] if missing. Returns the stored [User].
  Future<User> ensureUserDoc(User user) async {
    final doc = await _firestore.collection('users').doc(user.uid).get();
    if (doc.exists) {
      // Update displayName and lastActiveAt but preserve votes budget.
      await doc.reference.update({
        if (user.displayName != null) 'displayName': user.displayName,
        'lastActiveAt': user.lastActiveAt,
      });
      return _docToUser(
        await _firestore.collection('users').doc(user.uid).get(),
      );
    }
    final data = {
      'uid': user.uid,
      'votes': user.votes,
      'lastActiveAt': user.lastActiveAt,
      if (user.displayName != null) 'displayName': user.displayName,
    };
    await _firestore.collection('users').doc(user.uid).set(data);
    return user;
  }

  User _docToUser(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data()!;
    return User(
      uid: doc.id,
      votes: (data['votes'] as num).toInt(),
      lastActiveAt: (data['lastActiveAt'] as Timestamp).toDate(),
      displayName: data['displayName'] as String?,
    );
  }

  /// Grant votes based on log₃(hoursElapsed) and update the timestamp.
  Future<void> grantVotesAndTouch(String userId) async {
    final now = DateTime.now().toUtc();
    final doc = await _firestore.collection('users').doc(userId).get();
    if (!doc.exists) return;
    final data = doc.data()!;
    final lastActive = (data['lastActiveAt'] as Timestamp).toDate();
    final hoursElapsed = now.difference(lastActive).inHours;
    final grant = hoursElapsed >= 3
        ? (math.log(hoursElapsed) / math.log(3)).floor()
        : 0;
    if (grant > 0) {
      await doc.reference.update({
        'votes': FieldValue.increment(grant),
        'lastActiveAt': now,
      });
    } else {
      await doc.reference.update({'lastActiveAt': now});
    }
  }

  /// Update the user's `lastActiveAt` timestamp.
  Future<void> touchLastActiveAt(String userId) async {
    await _firestore.collection('users').doc(userId).update({
      'lastActiveAt': DateTime.now().toUtc(),
    });
  }

  /// Real-time stream of a user's remaining vote budget.
  Stream<int> watchUserVotes(String userId) {
    return _firestore
        .collection('users')
        .doc(userId)
        .snapshots()
        .map((doc) => doc.exists ? (doc.data()!['votes'] as num).toInt() : 0);
  }

  /// Atomically increment a user's vote on a problem.
  /// Creates the voter doc if it doesn't exist, or increments votes.
  /// Also increments the problem's denormalized `votes` field
  /// and decrements the user's vote budget.
  Future<void> vote({
    required String problemId,
    required String userId,
  }) async {
    final batch = _firestore.batch()
      ..set(
        _problemsRef.doc(problemId).collection('voters').doc(userId),
        {'uid': userId, 'votes': FieldValue.increment(1)},
        SetOptions(merge: true),
      )
      ..update(
        _problemsRef.doc(problemId),
        {'votes': FieldValue.increment(1)},
      )
      ..update(
        _firestore.collection('users').doc(userId),
        {'votes': FieldValue.increment(-1)},
      );
    await batch.commit();
  }

  /// Fetch all problem IDs that a user has voted for.
  /// Uses a collection group query across all `voters` subcollections.
  Future<Set<String>> getVotedProblemIds(String userId) async {
    final snapshot = await _firestore
        .collectionGroup('voters')
        .where('uid', isEqualTo: userId)
        .get();
    return snapshot.docs.map((doc) => doc.reference.parent.parent!.id).toSet();
  }

  /// Fetch the voter leaderboard for a problem.
  /// Returns voters sorted by votes DESC, then display name ASC.
  Future<List<({String name, int votes})>> getVotersForProblem(
    String problemId, {
    String? excludeUid,
    String anonymous = 'Anonymous',
  }) async {
    final voterSnapshot = await _problemsRef
        .doc(problemId)
        .collection('voters')
        .get();
    final entries = <({String uid, int votes})>[];
    for (final doc in voterSnapshot.docs) {
      final data = doc.data();
      final uid = data['uid'] as String;
      if (uid == excludeUid) continue;
      entries.add((
        uid: uid,
        votes: (data['votes'] as num).toInt(),
      ));
    }
    // Batch-fetch user docs for display names.
    final uids = entries.map((e) => e.uid).toList();
    final nameMap = <String, String?>{};
    // Firestore whereIn supports up to 30 items.
    for (var i = 0; i < uids.length; i += 30) {
      final end = i + 30 > uids.length ? uids.length : i + 30;
      final batch = uids.sublist(i, end);
      final snapshot = await _firestore
          .collection('users')
          .where(FieldPath.documentId, whereIn: batch)
          .get();
      for (final doc in snapshot.docs) {
        nameMap[doc.id] = doc.data()['displayName'] as String?;
      }
    }
    final result =
        entries.map((e) {
          final name = nameMap[e.uid] ?? anonymous;
          return (name: name, votes: e.votes);
        }).toList()..sort((a, b) {
          final cmp = b.votes.compareTo(a.votes);
          if (cmp != 0) return cmp;
          return a.name.compareTo(b.name);
        });
    return result;
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
      goal: data['goal'] as String? ?? '',
      ownerId: data['ownerId'] as String,
      geoscope: data['geoscope'] as String? ?? '/',
      lang: data['lang'] as String?,
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
