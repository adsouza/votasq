import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:client/services/language_detection_service.dart';
import 'package:client/services/language_validator.dart';
import 'package:client/services/translation_repository.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:crypto/crypto.dart';
import 'package:shared/shared.dart';
import 'package:uuid/uuid.dart';

export 'package:client/services/language_validator.dart'
    show LanguageMismatchException;

/// Direct Firestore access layer, replacing the HTTP API service.
///
/// Language detection is handled here (not in views) because the ML Kit
/// packages register method channels that break text input on desktop
/// platforms. Keeping the import chain in the service layer prevents views
/// from transitively pulling in those packages.
class FirestoreRepository {
  FirestoreRepository({
    FirebaseFirestore? firestore,
    FirebaseFunctions? functions,
    LanguageDetectionService? languageDetectionService,
    TranslationRepository? translationRepository,
  }) : _firestore = firestore ?? FirebaseFirestore.instance,
       _functions = functions,
       _langValidator = LanguageValidator(
         langService: languageDetectionService ?? LanguageDetectionService(),
         translationRepo: translationRepository,
       );

  final FirebaseFirestore _firestore;

  // Lazy: `FirebaseFunctions.instance` looks up the default Firebase app,
  // which throws in tests that haven't initialized Firebase. Keeping this
  // nullable lets repository methods that don't use Functions construct
  // and run in isolation.
  final FirebaseFunctions? _functions;
  FirebaseFunctions get _functionsInstance =>
      _functions ?? FirebaseFunctions.instance;

  final LanguageValidator _langValidator;
  static const _collection = 'problems';
  static const _pageSize = 20;

  CollectionReference<Map<String, dynamic>> get _problemsRef =>
      _firestore.collection(_collection);

  /// Unsolved, non-hidden problems matching the given geoscope or any
  /// ancestor, ordered by votes DESC then doc ID ASC.
  Query<Map<String, dynamic>> _geoscopedQuery(String geoscope) => _problemsRef
      .where('geoscope', whereIn: geoscopeAncestors(geoscope))
      .where('solved', isEqualTo: false)
      .where('hidden', isEqualTo: false)
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

  /// Create a new problem with a client-generated UUID. Returns the created
  /// [Problem] so callers can update local state without waiting for the
  /// Firestore listener (which won't emit if the new doc falls outside the
  /// limited query's first page).
  /// Uses a batched write to atomically create the main document and its
  /// first revision snapshot.
  Future<Problem> addProblem({
    required String description,
    required String ownerId,
    required String geoscope,
    required String userLanguage,
    String goal = '',
  }) async {
    final result = await _langValidator.detectAndValidateLang(
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

    return Problem(
      id: id,
      description: description,
      goal: goal,
      ownerId: ownerId,
      geoscope: geoscope,
      lang: result.lang,
      createdAt: now,
      lastUpdatedAt: now,
    );
  }

  /// Create a fork of the problem identified by [sourceProblemId], owned by
  /// [ownerId]. Copies description, goal, geoscope, lang, and any cached
  /// translations, and stamps the new problem with `inspoProblemId` +
  /// `inspoVersion` referencing the source's latest revision at fork time.
  /// Skips language detection because the text isn't user-authored on this
  /// flow.
  Future<Problem> forkProblem({
    required String sourceProblemId,
    required String ownerId,
  }) async {
    // Re-read the source so the inspo fields reference whatever the latest
    // revision is right now, not whatever the caller's snapshot says.
    final source = await getProblem(sourceProblemId);
    if (source == null) {
      throw StateError(
        'Cannot fork: source problem $sourceProblemId not found',
      );
    }
    final id = const Uuid().v4();
    final now = DateTime.now().toUtc();
    const version = 1;
    final problemData = <String, Object?>{
      'description': source.description,
      'goal': source.goal,
      'ownerId': ownerId,
      'geoscope': source.geoscope,
      'lang': ?source.lang,
      'votes': 1,
      'solved': false,
      'version': version,
      'createdAt': now,
      'lastUpdatedAt': now,
      'inspoProblemId': source.id,
      'inspoVersion': source.version,
    };
    final revisionData = {
      'description': source.description,
      'goal': source.goal,
      'version': version,
      'archivedAt': now,
    };

    final translations = await _problemsRef
        .doc(source.id)
        .collection('translations')
        .get();

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
    for (final doc in translations.docs) {
      batch.set(
        _problemsRef.doc(id).collection('translations').doc(doc.id),
        doc.data(),
      );
    }
    await batch.commit();

    return Problem(
      id: id,
      description: source.description,
      goal: source.goal,
      ownerId: ownerId,
      geoscope: source.geoscope,
      lang: source.lang,
      createdAt: now,
      lastUpdatedAt: now,
      inspoProblemId: source.id,
      inspoVersion: source.version,
    );
  }

  /// Fetch every problem that was forked from [sourceProblemId], sorted by
  /// votes descending (then by document id for stable ordering). Sorts in
  /// memory rather than via a server `orderBy` so we don't need a composite
  /// index — fork counts are expected to stay small.
  Future<List<Problem>> getForksOfProblem(String sourceProblemId) async {
    final snapshot = await _problemsRef
        .where('inspoProblemId', isEqualTo: sourceProblemId)
        .get();
    return snapshot.docs.map(_docToProblem).toList()..sort((a, b) {
      final cmp = b.votes.compareTo(a.votes);
      if (cmp != 0) return cmp;
      return a.id.compareTo(b.id);
    });
  }

  /// Update a problem's fields.
  /// Uses a batched write to atomically update the main document and create
  /// a new revision snapshot.
  ///
  /// If [userLanguage] is provided, re-detects the description language.
  /// If [copiedFromProblemId] is provided, the new revision is stamped with
  /// that fork's id so the notifications producer can emit `forkAdopted`.
  Future<void> updateProblem(
    Problem problem, {
    String? userLanguage,
    String? copiedFromProblemId,
  }) async {
    final result = userLanguage != null
        ? await _langValidator.detectAndValidateLang(
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
    final revisionData = <String, Object?>{
      'description': problem.description,
      'goal': problem.goal,
      'version': newVersion,
      'archivedAt': now,
      'copiedFromProblemId': ?copiedFromProblemId,
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

  /// Owner-only single-field write that flips a problem's `hidden` flag.
  /// Targets just the one field so the rules' hide-toggle branch
  /// (`affectedKeys().hasOnly(['hidden'])`) matches the wire payload.
  Future<void> setHidden({
    required String problemId,
    required bool hidden,
  }) => _problemsRef.doc(problemId).update({'hidden': hidden});

  /// Ensure a user document exists in the `users` collection.
  /// Creates one from [user] if missing. Returns the stored [User].
  ///
  /// Does not touch `lastActiveAt` for existing users — that timer is owned
  /// by [grantVotesAndTouch], and resetting it here would zero out the
  /// elapsed-time calculation that drives vote grants.
  Future<User> ensureUserDoc(User user) async {
    final doc = await _firestore.collection('users').doc(user.uid).get();
    if (doc.exists) {
      if (user.displayName != null) {
        await doc.reference.update({'displayName': user.displayName});
        return _docToUser(
          await _firestore.collection('users').doc(user.uid).get(),
        );
      }
      return _docToUser(doc);
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
  Future<List<({String id, String label, int population})>>
  getGeoscopes() async {
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
        population: ((data['population'] as num?) ?? 0).toInt(),
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
      inspoProblemId: data['inspoProblemId'] as String?,
      inspoVersion: (data['inspoVersion'] as num?)?.toInt(),
      linkedProblemIds:
          (data['linkedProblemIds'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          [],
      typedLinks: _decodeTypedLinks(data['typedLinks']),
    );
  }

  static List<ProblemLink> _decodeTypedLinks(dynamic value) {
    if (value is! List) return const [];
    final out = <ProblemLink>[];
    for (final entry in value) {
      if (entry is! Map) continue;
      final targetId = entry['targetId'];
      final kindWire = entry['kind'];
      if (targetId is! String || kindWire is! String) continue;
      final kind = switch (kindWire) {
        'specialization' => ProblemLinkKind.specialization,
        'generalization' => ProblemLinkKind.generalization,
        _ => null,
      };
      if (kind == null) continue;
      out.add(ProblemLink(targetId: targetId, kind: kind));
    }
    return out;
  }

  static String _typedLinkKindToWire(ProblemLinkKind kind) => switch (kind) {
    ProblemLinkKind.specialization => 'specialization',
    ProblemLinkKind.generalization => 'generalization',
  };

  static Map<String, dynamic> _typedLinkToMap(ProblemLink link) => {
    'targetId': link.targetId,
    'kind': _typedLinkKindToWire(link.kind),
  };

  // ---------------------------------------------------------------------------
  // Notifications
  // ---------------------------------------------------------------------------

  Query<Map<String, dynamic>> _notificationsQuery(String uid) => _firestore
      .collection('users')
      .doc(uid)
      .collection('notifications')
      .orderBy('updatedAt', descending: true)
      .orderBy(FieldPath.documentId, descending: true);

  /// Real-time stream of the first page of notifications for [uid], ordered
  /// by `updatedAt` descending (so re-emitted notifications resurface at the
  /// top).
  Stream<({List<AppNotification> notifications, DocumentSnapshot? lastDoc})>
  watchNotifications(String uid, {int limit = _pageSize}) {
    return _notificationsQuery(uid).limit(limit).snapshots().map((snapshot) {
      final notifications = snapshot.docs.map(_docToNotification).toList();
      final lastDoc = snapshot.docs.isNotEmpty ? snapshot.docs.last : null;
      return (notifications: notifications, lastDoc: lastDoc);
    });
  }

  /// Fetch the next page of notifications for [uid] (used by infinite scroll).
  Future<({List<AppNotification> notifications, DocumentSnapshot? lastDoc})>
  getNotifications(
    String uid, {
    int pageSize = _pageSize,
    DocumentSnapshot? startAfter,
  }) async {
    var query = _notificationsQuery(uid).limit(pageSize);
    if (startAfter != null) {
      query = query.startAfterDocument(startAfter);
    }
    final snapshot = await query.get();
    final notifications = snapshot.docs.map(_docToNotification).toList();
    final lastDoc = snapshot.docs.isNotEmpty ? snapshot.docs.last : null;
    return (notifications: notifications, lastDoc: lastDoc);
  }

  /// Returns the current unread notification count for [uid].
  ///
  /// Uses Firestore's `count()` aggregation so the call doesn't depend on the
  /// loaded page — the badge stays accurate even with many unread.
  Future<int> unreadNotificationCount(String uid) async {
    final snapshot = await _firestore
        .collection('users')
        .doc(uid)
        .collection('notifications')
        .where('readAt', isNull: true)
        .count()
        .get();
    return snapshot.count ?? 0;
  }

  /// Stamp `readAt = serverTimestamp` on a notification. The security rules
  /// permit this exact one-field update and reject anything else.
  Future<void> markNotificationRead(String uid, String notificationId) async {
    await _firestore
        .collection('users')
        .doc(uid)
        .collection('notifications')
        .doc(notificationId)
        .update({'readAt': FieldValue.serverTimestamp()});
  }

  /// Invokes the `markAllNotificationsRead` callable Cloud Function, which
  /// stamps `readAt = serverTimestamp` on every unread notification for the
  /// signed-in caller in batches. Returns the count of notifications that
  /// were flipped (zero if none were unread).
  Future<int> markAllNotificationsRead() async {
    final callable = _functionsInstance.httpsCallable(
      'markAllNotificationsRead',
    );
    final result = await callable.call<Map<Object?, Object?>>();
    final marked = result.data['marked'];
    if (marked is num) return marked.toInt();
    return 0;
  }

  /// Stable doc id for an FCM [token] — sha256 hex digest. We use a hash
  /// rather than the token verbatim because tokens can contain characters
  /// outside the safe Firestore doc-id alphabet (rare but defended). The
  /// hash also gives us deterministic dedupe: re-registering the same
  /// token on the same device upserts the existing doc.
  static String _fcmTokenDocId(String token) {
    return sha256.convert(utf8.encode(token)).toString();
  }

  /// Upsert this device's FCM registration under
  /// `users/{uid}/fcmTokens/{sha256(token)}`. Safe to call repeatedly with
  /// the same token (e.g. on every app start); only `lastUsedAt` updates.
  Future<void> registerFcmToken({
    required String uid,
    required String token,
    required String platform,
  }) async {
    final docRef = _firestore
        .collection('users')
        .doc(uid)
        .collection('fcmTokens')
        .doc(_fcmTokenDocId(token));
    final now = DateTime.now().toUtc();
    final existing = await docRef.get();
    if (existing.exists) {
      // Only lastUsedAt changes — the security rule rejects anything else
      // on update, so we don't try to bump platform/token here even if
      // they were stored slightly differently.
      await docRef.update({'lastUsedAt': now});
    } else {
      await docRef.set({
        'token': token,
        'platform': platform,
        'createdAt': now,
        'lastUsedAt': now,
      });
    }
  }

  /// Delete this device's FCM registration (called on sign-out).
  Future<void> unregisterFcmToken({
    required String uid,
    required String token,
  }) async {
    await _firestore
        .collection('users')
        .doc(uid)
        .collection('fcmTokens')
        .doc(_fcmTokenDocId(token))
        .delete();
  }

  AppNotification _docToNotification(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data()!;
    final payloadData = Map<String, dynamic>.from(data['payload'] as Map);
    return AppNotification(
      id: doc.id,
      recipientUid: data['recipientUid'] as String,
      payload: NotificationPayload.fromJson(payloadData),
      createdAt: (data['createdAt'] as Timestamp).toDate(),
      updatedAt: (data['updatedAt'] as Timestamp).toDate(),
      readAt: (data['readAt'] as Timestamp?)?.toDate(),
    );
  }

  /// Symmetrically link two problems together into a merged cluster (clique).
  Future<void> linkProblems(String problemIdA, String problemIdB) async {
    final problemA = await getProblem(problemIdA);
    final problemB = await getProblem(problemIdB);
    if (problemA == null || problemB == null) return;

    final allIds = {
      problemIdA,
      problemIdB,
      ...problemA.linkedProblemIds,
      ...problemB.linkedProblemIds,
    };

    final batch = _firestore.batch();
    for (final id in allIds) {
      final otherIds = allIds.difference({id}).toList();
      batch.update(_problemsRef.doc(id), {
        'linkedProblemIds': otherIds,
      });
    }
    await batch.commit();
  }

  /// Tag (or re-tag) a directional relationship between [sourceId] and
  /// [targetId]. Removes the pair from either side's generic
  /// `linkedProblemIds` to preserve the cross-list invariant; writes the
  /// directional entry to [sourceId] and the mirrored inverse to [targetId].
  Future<void> tagProblemLink({
    required String sourceId,
    required String targetId,
    required ProblemLinkKind kind,
  }) async {
    if (sourceId == targetId) return;
    final source = await getProblem(sourceId);
    final target = await getProblem(targetId);
    if (source == null || target == null) return;

    final sourceLinked = source.linkedProblemIds
        .where((id) => id != targetId)
        .toList();
    final sourceTyped = [
      ...source.typedLinks.where((l) => l.targetId != targetId),
      ProblemLink(targetId: targetId, kind: kind),
    ];

    final targetLinked = target.linkedProblemIds
        .where((id) => id != sourceId)
        .toList();
    final targetTyped = [
      ...target.typedLinks.where((l) => l.targetId != sourceId),
      ProblemLink(targetId: sourceId, kind: kind.inverse),
    ];

    final batch = _firestore.batch()
      ..update(_problemsRef.doc(sourceId), {
        'linkedProblemIds': sourceLinked,
        'typedLinks': sourceTyped.map(_typedLinkToMap).toList(),
      })
      ..update(_problemsRef.doc(targetId), {
        'linkedProblemIds': targetLinked,
        'typedLinks': targetTyped.map(_typedLinkToMap).toList(),
      });
    await batch.commit();
  }

  /// Remove the directional relationship between [sourceId] and [targetId]
  /// from both sides' `typedLinks`. Does NOT restore the generic clique
  /// link — re-linking is an explicit user action.
  Future<void> untagProblemLink({
    required String sourceId,
    required String targetId,
  }) async {
    if (sourceId == targetId) return;
    final source = await getProblem(sourceId);
    final target = await getProblem(targetId);
    if (source == null || target == null) return;

    final sourceTyped = source.typedLinks
        .where((l) => l.targetId != targetId)
        .toList();
    final targetTyped = target.typedLinks
        .where((l) => l.targetId != sourceId)
        .toList();

    final batch = _firestore.batch()
      ..update(_problemsRef.doc(sourceId), {
        'typedLinks': sourceTyped.map(_typedLinkToMap).toList(),
      })
      ..update(_problemsRef.doc(targetId), {
        'typedLinks': targetTyped.map(_typedLinkToMap).toList(),
      });
    await batch.commit();
  }

  /// Unlink a problem from its cluster symmetrically.
  Future<void> unlinkProblem(String problemId) async {
    final problem = await getProblem(problemId);
    if (problem == null || problem.linkedProblemIds.isEmpty) return;

    final clusterIds = problem.linkedProblemIds;
    final batch = _firestore.batch()
      ..update(_problemsRef.doc(problemId), {
        'linkedProblemIds': <String>[],
      });

    // Remove this problem ID from all other problems in the cluster
    for (final otherId in clusterIds) {
      batch.update(_problemsRef.doc(otherId), {
        'linkedProblemIds': FieldValue.arrayRemove([problemId]),
      });
    }
    await batch.commit();
  }

  /// Fetch up to 100 unsolved problems globally, sorted by votes DESC,
  /// then doc ID ASC, for search.
  Future<List<Problem>> getGlobalProblemsForSearch({int limit = 100}) async {
    final snapshot = await _problemsRef
        .where('solved', isEqualTo: false)
        .orderBy('votes', descending: true)
        .orderBy(FieldPath.documentId)
        .limit(limit)
        .get();
    return snapshot.docs.map(_docToProblem).toList();
  }
}
