import 'package:client/services/firestore_repository.dart';
import 'package:client/services/language_detection_service.dart';
import 'package:client/services/translation_repository.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared/shared.dart';

class _FakeLangService implements LanguageDetectionService {
  @override
  Future<bool> needsTranslation({
    required String text,
    required String userLanguage,
  }) async => false;

  @override
  Future<String?> detectLanguage(String text) async => 'en';

  @override
  Future<void> dispose() async {}
}

class _FakeTranslationRepo implements TranslationRepository {
  @override
  String get baseUrl => '';
  @override
  http.Client get client => http.Client();

  @override
  bool get canTranslateOnDevice => false;

  @override
  Future<String?> translate({
    required String text,
    required String targetLanguage,
    String? sourceLanguage,
  }) async => null;

  @override
  Future<TranslatedProblem> translateProblem({
    required String problemId,
    required String targetLanguage,
  }) async => throw UnimplementedError();

  @override
  Future<({String detectedLanguage, String translation})>
      translateToEnglish(String text) async =>
          throw UnimplementedError();
}

void main() {
  group('geoscopeAncestors', () {
    test('returns ["/"] for global scope', () {
      expect(geoscopeAncestors('/'), ['/']);
    });

    test('returns root + country for single-level scope', () {
      expect(geoscopeAncestors('us'), ['/', 'us']);
    });

    test('returns root + all ancestors for two-level scope', () {
      expect(
        geoscopeAncestors('us/nyc'),
        ['/', 'us', 'us/nyc'],
      );
    });

    test(
      'returns root + all ancestors for four-level scope',
      () {
        expect(
          geoscopeAncestors('na/us/ny/nyc'),
          ['/', 'na', 'na/us', 'na/us/ny', 'na/us/ny/nyc'],
        );
      },
    );

    test(
      'returns root + all ancestors for five-level scope',
      () {
        expect(
          geoscopeAncestors('na/us/ny/nyc/brooklyn'),
          [
            '/',
            'na',
            'na/us',
            'na/us/ny',
            'na/us/ny/nyc',
            'na/us/ny/nyc/brooklyn',
          ],
        );
      },
    );
  });

  group('FirestoreRepository', () {
    late FakeFirebaseFirestore firestore;
    late FirestoreRepository repo;

    setUp(() {
      firestore = FakeFirebaseFirestore();
      repo = FirestoreRepository(
        firestore: firestore,
        languageDetectionService: _FakeLangService(),
        translationRepository: _FakeTranslationRepo(),
      );
    });

    Future<void> seedProblem({
      required String id,
      String description = 'Test problem description',
      String goal = '',
      String ownerId = 'owner1',
      String geoscope = '/',
      int votes = 1,
      bool solved = false,
    }) async {
      final now = DateTime.now().toUtc();
      await firestore.collection('problems').doc(id).set({
        'description': description,
        'goal': goal,
        'ownerId': ownerId,
        'geoscope': geoscope,
        'votes': votes,
        'solved': solved,
        'version': 1,
        'createdAt': now,
        'lastUpdatedAt': now,
      });
    }

    group('getProblem', () {
      test('returns problem when it exists', () async {
        await seedProblem(id: 'p1');
        final problem = await repo.getProblem('p1');
        expect(problem, isNotNull);
        expect(problem!.id, 'p1');
        expect(problem.description, 'Test problem description');
      });

      test('returns null when problem does not exist', () async {
        final problem = await repo.getProblem('nonexistent');
        expect(problem, isNull);
      });
    });

    group('addProblem', () {
      test('creates problem and voter doc', () async {
        await repo.addProblem(
          description: 'A new problem to solve',
          ownerId: 'user1',
          geoscope: '/',
          userLanguage: 'en',
        );

        final snapshot =
            await firestore.collection('problems').get();
        expect(snapshot.docs, hasLength(1));

        final doc = snapshot.docs.first;
        expect(doc.data()['description'], 'A new problem to solve');
        expect(doc.data()['ownerId'], 'user1');
        expect(doc.data()['votes'], 1);
        expect(doc.data()['solved'], false);

        // Check voter doc was created.
        final voters = await firestore
            .collection('problems')
            .doc(doc.id)
            .collection('voters')
            .get();
        expect(voters.docs, hasLength(1));
        expect(voters.docs.first.data()['uid'], 'user1');
        expect(voters.docs.first.data()['votes'], 1);

        // Check version snapshot was created.
        final versions = await firestore
            .collection('problems')
            .doc(doc.id)
            .collection('versions')
            .get();
        expect(versions.docs, hasLength(1));
      });

      test('stores goal when provided', () async {
        await repo.addProblem(
          description: 'Problem with a goal',
          goal: 'Achieve this outcome',
          ownerId: 'user1',
          geoscope: '/',
          userLanguage: 'en',
        );

        final snapshot =
            await firestore.collection('problems').get();
        expect(
          snapshot.docs.first.data()['goal'],
          'Achieve this outcome',
        );
      });
    });

    group('updateProblem', () {
      test('updates description and creates version', () async {
        await seedProblem(id: 'p1');
        final original = (await repo.getProblem('p1'))!;

        await repo.updateProblem(
          original.copyWith(description: 'Updated description'),
        );

        final updated = (await repo.getProblem('p1'))!;
        expect(updated.description, 'Updated description');
        expect(updated.version, 2);

        // Check version snapshot was created.
        final versions = await firestore
            .collection('problems')
            .doc('p1')
            .collection('versions')
            .get();
        expect(versions.docs, hasLength(1));
      });
    });

    group('translation cache', () {
      test('getTranslation returns null when no cache', () async {
        final result = await repo.getTranslation('p1', 'es');
        expect(result, isNull);
      });

      test('saveTranslation then getTranslation round-trips',
          () async {
        const translation = TranslatedProblem(
          description: 'Traducción',
          goal: 'Meta',
        );
        await repo.saveTranslation('p1', 'es', translation);

        final result = await repo.getTranslation('p1', 'es');
        expect(result, isNotNull);
        expect(result!.description, 'Traducción');
        expect(result.goal, 'Meta');
      });
    });

    group('addComplaint', () {
      test('adds userId to complaints array', () async {
        await seedProblem(id: 'p1');

        await repo.addComplaint(
          problemId: 'p1',
          userId: 'complainer1',
        );

        final doc =
            await firestore.collection('problems').doc('p1').get();
        final complaints =
            (doc.data()!['complaints'] as List).cast<String>();
        expect(complaints, contains('complainer1'));
      });
    });

    group('ensureUserDoc', () {
      test('creates user doc when it does not exist', () async {
        final now = DateTime.now().toUtc();
        final user = User(
          uid: 'u1',
          votes: 5,
          lastActiveAt: now,
          displayName: 'Alice',
        );

        final result = await repo.ensureUserDoc(user);
        expect(result.uid, 'u1');
        expect(result.votes, 5);
        expect(result.displayName, 'Alice');

        final doc =
            await firestore.collection('users').doc('u1').get();
        expect(doc.exists, isTrue);
      });

      test(
        'updates existing user and preserves votes',
        () async {
          final oldTime = DateTime.utc(2024);
          await firestore.collection('users').doc('u1').set({
            'uid': 'u1',
            'votes': 10,
            'lastActiveAt': oldTime,
            'displayName': 'OldName',
          });

          final now = DateTime.now().toUtc();
          final user = User(
            uid: 'u1',
            votes: 0,
            lastActiveAt: now,
            displayName: 'NewName',
          );

          final result = await repo.ensureUserDoc(user);
          expect(result.uid, 'u1');
          // Votes should be preserved from existing doc.
          expect(result.votes, 10);
          expect(result.displayName, 'NewName');
        },
      );
    });

    group('vote', () {
      test(
        'increments problem votes and decrements user budget',
        () async {
          await seedProblem(id: 'p1', votes: 5);
          await firestore.collection('users').doc('u1').set({
            'uid': 'u1',
            'votes': 3,
            'lastActiveAt': DateTime.now().toUtc(),
          });

          await repo.vote(problemId: 'p1', userId: 'u1');

          final problem =
              await firestore.collection('problems').doc('p1').get();
          expect(problem.data()!['votes'], 6);

          final user =
              await firestore.collection('users').doc('u1').get();
          expect(user.data()!['votes'], 2);

          // Voter doc should exist.
          final voter = await firestore
              .collection('problems')
              .doc('p1')
              .collection('voters')
              .doc('u1')
              .get();
          expect(voter.exists, isTrue);
        },
      );
    });

    group('getVotedProblemIds', () {
      test('returns problem IDs where user voted', () async {
        // Create voter docs in different problems.
        await firestore
            .collection('problems')
            .doc('p1')
            .collection('voters')
            .doc('u1')
            .set({'uid': 'u1', 'votes': 1});
        await firestore
            .collection('problems')
            .doc('p2')
            .collection('voters')
            .doc('u1')
            .set({'uid': 'u1', 'votes': 2});

        final ids = await repo.getVotedProblemIds('u1');
        expect(ids, containsAll(['p1', 'p2']));
      });

      test('returns empty set when user has no votes', () async {
        final ids = await repo.getVotedProblemIds('nobody');
        expect(ids, isEmpty);
      });
    });

    group('watchUserVotes', () {
      test('emits current vote budget', () async {
        await firestore.collection('users').doc('u1').set({
          'uid': 'u1',
          'votes': 7,
          'lastActiveAt': DateTime.now().toUtc(),
        });

        final votes = repo.watchUserVotes('u1');
        expect(await votes.first, 7);
      });

      test('emits 0 for non-existent user', () async {
        final votes = repo.watchUserVotes('ghost');
        expect(await votes.first, 0);
      });
    });

    group('getGeoscopes', () {
      test(
        'returns geoscopes sorted by population descending',
        () async {
          await firestore.collection('geoscopes').doc('us').set({
            'id': 'us',
            'label': 'United States',
            'population': 330000000,
          });
          await firestore.collection('geoscopes').doc('in').set({
            'id': 'in',
            'label': 'India',
            'population': 1400000000,
          });
          await firestore.collection('geoscopes').doc('uk').set({
            'id': 'uk',
            'label': 'United Kingdom',
            'population': 67000000,
          });

          final geoscopes = await repo.getGeoscopes();
          expect(geoscopes, hasLength(3));
          expect(geoscopes[0].label, 'India');
          expect(geoscopes[1].label, 'United States');
          expect(geoscopes[2].label, 'United Kingdom');
        },
      );
    });

    group('getVotersForProblem', () {
      test(
        'returns sorted voter list with display names',
        () async {
          // Create problem with voters.
          await seedProblem(id: 'p1');
          await firestore
              .collection('problems')
              .doc('p1')
              .collection('voters')
              .doc('u1')
              .set({'uid': 'u1', 'votes': 3});
          await firestore
              .collection('problems')
              .doc('p1')
              .collection('voters')
              .doc('u2')
              .set({'uid': 'u2', 'votes': 5});

          // Create user docs.
          await firestore.collection('users').doc('u1').set({
            'displayName': 'Alice',
            'votes': 0,
            'lastActiveAt': DateTime.now().toUtc(),
          });
          await firestore.collection('users').doc('u2').set({
            'displayName': 'Bob',
            'votes': 0,
            'lastActiveAt': DateTime.now().toUtc(),
          });

          final voters = await repo.getVotersForProblem('p1');
          expect(voters, hasLength(2));
          // Sorted by votes DESC.
          expect(voters[0].name, 'Bob');
          expect(voters[0].votes, 5);
          expect(voters[1].name, 'Alice');
          expect(voters[1].votes, 3);
        },
      );

      test('excludes specified uid', () async {
        await seedProblem(id: 'p1');
        await firestore
            .collection('problems')
            .doc('p1')
            .collection('voters')
            .doc('u1')
            .set({'uid': 'u1', 'votes': 1});
        await firestore
            .collection('problems')
            .doc('p1')
            .collection('voters')
            .doc('u2')
            .set({'uid': 'u2', 'votes': 2});

        await firestore.collection('users').doc('u2').set({
          'displayName': 'Bob',
          'votes': 0,
          'lastActiveAt': DateTime.now().toUtc(),
        });

        final voters = await repo.getVotersForProblem(
          'p1',
          excludeUid: 'u1',
        );
        expect(voters, hasLength(1));
        expect(voters[0].name, 'Bob');
      });

      test(
        'uses anonymous for users without displayName',
        () async {
          await seedProblem(id: 'p1');
          await firestore
              .collection('problems')
              .doc('p1')
              .collection('voters')
              .doc('u1')
              .set({'uid': 'u1', 'votes': 1});

          final voters = await repo.getVotersForProblem('p1');
          expect(voters, hasLength(1));
          expect(voters[0].name, 'Anonymous');
        },
      );
    });

    group('grantVotesAndTouch', () {
      test('grants votes based on hours elapsed', () async {
        // Set lastActiveAt to 27+ hours ago (log₃(27) = 3).
        final longAgo = DateTime.now()
            .toUtc()
            .subtract(const Duration(hours: 28));
        await firestore.collection('users').doc('u1').set({
          'uid': 'u1',
          'votes': 5,
          'lastActiveAt': longAgo,
        });

        await repo.grantVotesAndTouch('u1');

        final doc =
            await firestore.collection('users').doc('u1').get();
        // Should have granted floor(log₃(28)) = 3 votes.
        expect(doc.data()!['votes'], 8);
      });

      test('grants 0 votes when less than 3 hours', () async {
        final recent = DateTime.now()
            .toUtc()
            .subtract(const Duration(hours: 1));
        await firestore.collection('users').doc('u1').set({
          'uid': 'u1',
          'votes': 5,
          'lastActiveAt': recent,
        });

        await repo.grantVotesAndTouch('u1');

        final doc =
            await firestore.collection('users').doc('u1').get();
        expect(doc.data()!['votes'], 5);
      });

      test('does nothing for nonexistent user', () async {
        // Should not throw.
        await repo.grantVotesAndTouch('ghost');
      });
    });
  });
}
