import 'package:client/services/firestore_repository.dart';
import 'package:client/services/language_detection_service.dart';
import 'package:client/services/translation_repository.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
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
  Future<({String detectedLanguage, String translation})> translateToEnglish(
    String text,
  ) async => throw UnimplementedError();
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
      bool hidden = false,
    }) async {
      final now = DateTime.now().toUtc();
      await firestore.collection('problems').doc(id).set({
        'description': description,
        'goal': goal,
        'ownerId': ownerId,
        'geoscope': geoscope,
        'votes': votes,
        'solved': solved,
        'hidden': hidden,
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

        final snapshot = await firestore.collection('problems').get();
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

        final snapshot = await firestore.collection('problems').get();
        expect(
          snapshot.docs.first.data()['goal'],
          'Achieve this outcome',
        );
      });
    });

    group('forkProblem', () {
      Future<void> seedProblemWithVersion({
        required String id,
        required int version,
        String description = 'Original problem',
        String goal = 'Original goal',
        String ownerId = 'owner1',
        String geoscope = '/',
        String? lang = 'en',
      }) async {
        final now = DateTime.now().toUtc();
        await firestore.collection('problems').doc(id).set({
          'description': description,
          'goal': goal,
          'ownerId': ownerId,
          'geoscope': geoscope,
          'lang': ?lang,
          'votes': 17,
          'solved': false,
          'version': version,
          'createdAt': now,
          'lastUpdatedAt': now,
        });
      }

      test(
        'creates a fork owned by the new user with copied content and inspo',
        () async {
          await seedProblemWithVersion(id: 'src', version: 4);

          final fork = await repo.forkProblem(
            sourceProblemId: 'src',
            ownerId: 'forker',
          );

          expect(fork.description, 'Original problem');
          expect(fork.goal, 'Original goal');
          expect(fork.ownerId, 'forker');
          expect(fork.inspoProblemId, 'src');
          expect(fork.inspoVersion, 4);
          // Fork starts fresh: votes=1 (forker's vote), version=1.
          expect(fork.id, isNot('src'));

          final stored = await firestore
              .collection('problems')
              .doc(fork.id)
              .get();
          expect(stored.data()!['inspoProblemId'], 'src');
          expect(stored.data()!['inspoVersion'], 4);
          expect(stored.data()!['votes'], 1);
          expect(stored.data()!['version'], 1);
          expect(stored.data()!['ownerId'], 'forker');

          // Original problem should be untouched.
          final original = await firestore
              .collection('problems')
              .doc('src')
              .get();
          expect(original.data()!['ownerId'], 'owner1');
          expect(original.data()!['votes'], 17);
          expect(original.data()!.containsKey('inspoProblemId'), isFalse);
          expect(original.data()!.containsKey('inspoVersion'), isFalse);
        },
      );

      test('seeds the fork with a voter doc for the new owner', () async {
        await seedProblemWithVersion(id: 'src', version: 1);

        final fork = await repo.forkProblem(
          sourceProblemId: 'src',
          ownerId: 'forker',
        );

        final voters = await firestore
            .collection('problems')
            .doc(fork.id)
            .collection('voters')
            .get();
        expect(voters.docs, hasLength(1));
        expect(voters.docs.first.data()['uid'], 'forker');
        expect(voters.docs.first.data()['votes'], 1);
      });

      test('writes a v1 revision snapshot for the fork', () async {
        await seedProblemWithVersion(id: 'src', version: 4);

        final fork = await repo.forkProblem(
          sourceProblemId: 'src',
          ownerId: 'forker',
        );

        final versions = await firestore
            .collection('problems')
            .doc(fork.id)
            .collection('versions')
            .get();
        expect(versions.docs, hasLength(1));
        expect(versions.docs.first.id, '1');
        expect(versions.docs.first.data()['description'], 'Original problem');
      });

      test('copies cached translations into the fork', () async {
        await seedProblemWithVersion(id: 'src', version: 1);
        await firestore
            .collection('problems')
            .doc('src')
            .collection('translations')
            .doc('es')
            .set({'description': 'Problema original', 'goal': 'Meta original'});

        final fork = await repo.forkProblem(
          sourceProblemId: 'src',
          ownerId: 'forker',
        );

        final forkTranslation = await firestore
            .collection('problems')
            .doc(fork.id)
            .collection('translations')
            .doc('es')
            .get();
        expect(forkTranslation.exists, isTrue);
        expect(forkTranslation.data()!['description'], 'Problema original');
        expect(forkTranslation.data()!['goal'], 'Meta original');
      });

      test('throws StateError when source does not exist', () async {
        expect(
          () => repo.forkProblem(
            sourceProblemId: 'ghost',
            ownerId: 'forker',
          ),
          throwsStateError,
        );
      });

      test(
        'updateProblem on a fork does not touch the inspo fields',
        () async {
          await seedProblemWithVersion(id: 'src', version: 2);
          final fork = await repo.forkProblem(
            sourceProblemId: 'src',
            ownerId: 'forker',
          );

          await repo.updateProblem(
            fork.copyWith(description: 'Edited by forker'),
          );

          final stored = await firestore
              .collection('problems')
              .doc(fork.id)
              .get();
          expect(stored.data()!['inspoProblemId'], 'src');
          expect(stored.data()!['inspoVersion'], 2);
          expect(stored.data()!['description'], 'Edited by forker');
        },
      );

      test(
        'getForksOfProblem returns only forks of the given source',
        () async {
          await seedProblemWithVersion(id: 'src', version: 1);
          final aliceFork = await repo.forkProblem(
            sourceProblemId: 'src',
            ownerId: 'alice',
          );
          final bobFork = await repo.forkProblem(
            sourceProblemId: 'src',
            ownerId: 'bob',
          );
          // Unrelated problem + fork must not show up.
          await seedProblemWithVersion(id: 'other', version: 1);
          await repo.forkProblem(sourceProblemId: 'other', ownerId: 'eve');

          final forks = await repo.getForksOfProblem('src');
          expect(forks.map((f) => f.id).toSet(), {aliceFork.id, bobFork.id});
        },
      );

      test('getForksOfProblem sorts by votes desc, then id asc', () async {
        await seedProblemWithVersion(id: 'src', version: 1);
        final a = await repo.forkProblem(
          sourceProblemId: 'src',
          ownerId: 'alice',
        );
        final b = await repo.forkProblem(
          sourceProblemId: 'src',
          ownerId: 'bob',
        );
        final c = await repo.forkProblem(
          sourceProblemId: 'src',
          ownerId: 'carol',
        );
        // Manually adjust votes (all forks start at 1).
        await firestore.collection('problems').doc(a.id).update({'votes': 5});
        await firestore.collection('problems').doc(b.id).update({'votes': 9});
        await firestore.collection('problems').doc(c.id).update({'votes': 9});

        final forks = await repo.getForksOfProblem('src');
        // c may sort before or after b purely by id comparison; both have
        // votes=9, then a with votes=5.
        expect(forks[2].id, a.id);
        expect({forks[0].id, forks[1].id}, {b.id, c.id});
        // Stable tiebreak by id ascending.
        final tied = [forks[0].id, forks[1].id]..sort();
        expect([forks[0].id, forks[1].id], tied);
      });

      test(
        'getForksOfProblem returns empty list when there are no forks',
        () async {
          await seedProblemWithVersion(id: 'src', version: 1);
          final forks = await repo.getForksOfProblem('src');
          expect(forks, isEmpty);
        },
      );

      test('enumerates all forks of a problem via inspoProblemId', () async {
        await seedProblemWithVersion(id: 'src', version: 1);
        await repo.forkProblem(sourceProblemId: 'src', ownerId: 'alice');
        // Bump source version and fork again so we cover multiple versions.
        await firestore.collection('problems').doc('src').update({
          'version': 2,
        });
        await repo.forkProblem(sourceProblemId: 'src', ownerId: 'bob');
        // Unrelated problem and fork that must not show up.
        await seedProblemWithVersion(id: 'other', version: 1);
        await repo.forkProblem(sourceProblemId: 'other', ownerId: 'eve');

        final query = await firestore
            .collection('problems')
            .where('inspoProblemId', isEqualTo: 'src')
            .get();
        final ownerIds = query.docs
            .map((d) => d.data()['ownerId'] as String)
            .toSet();
        expect(ownerIds, {'alice', 'bob'});
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

      test('saveTranslation then getTranslation round-trips', () async {
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

        final doc = await firestore.collection('problems').doc('p1').get();
        final complaints = (doc.data()!['complaints'] as List).cast<String>();
        expect(complaints, contains('complainer1'));
      });
    });

    group('setHidden', () {
      test('sets hidden=true on the doc', () async {
        await seedProblem(id: 'h1');
        await repo.setHidden(problemId: 'h1', hidden: true);
        final doc = await firestore.collection('problems').doc('h1').get();
        expect(doc.data()!['hidden'], isTrue);
      });

      test('sets hidden=false on the doc', () async {
        await seedProblem(id: 'h2');
        await repo.setHidden(problemId: 'h2', hidden: true);
        await repo.setHidden(problemId: 'h2', hidden: false);
        final doc = await firestore.collection('problems').doc('h2').get();
        expect(doc.data()!['hidden'], isFalse);
      });

      test('does not touch other fields', () async {
        await seedProblem(id: 'h3', description: 'untouched');
        await repo.setHidden(problemId: 'h3', hidden: true);
        final doc = await firestore.collection('problems').doc('h3').get();
        expect(doc.data()!['description'], 'untouched');
      });
    });

    group('watchProblems / getProblems hidden filter', () {
      test('excludes problems with hidden=true', () async {
        await seedProblem(id: 'visible');
        await seedProblem(id: 'hidden');
        await firestore.collection('problems').doc('hidden').update({
          'hidden': true,
        });

        final result = await repo.getProblems(geoscope: '/');
        expect(result.problems.map((p) => p.id), ['visible']);
      });

      test('includes problems with hidden=false', () async {
        await seedProblem(id: 'v1');
        await firestore.collection('problems').doc('v1').update({
          'hidden': false,
        });

        final result = await repo.getProblems(geoscope: '/');
        expect(result.problems.map((p) => p.id), ['v1']);
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

        final doc = await firestore.collection('users').doc('u1').get();
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

      test('preserves lastActiveAt on existing doc', () async {
        final oldTime = DateTime.utc(2024);
        await firestore.collection('users').doc('u1').set({
          'uid': 'u1',
          'votes': 10,
          'lastActiveAt': oldTime,
        });

        await repo.ensureUserDoc(
          User(uid: 'u1', votes: 0, lastActiveAt: DateTime.now().toUtc()),
        );

        final stored = await firestore.collection('users').doc('u1').get();
        final actualLastActive = (stored.data()!['lastActiveAt'] as Timestamp)
            .toDate();
        expect(actualLastActive.isAtSameMomentAs(oldTime), isTrue);
      });
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

          final problem = await firestore
              .collection('problems')
              .doc('p1')
              .get();
          expect(problem.data()!['votes'], 6);

          final user = await firestore.collection('users').doc('u1').get();
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
        final longAgo = DateTime.now().toUtc().subtract(
          const Duration(hours: 28),
        );
        await firestore.collection('users').doc('u1').set({
          'uid': 'u1',
          'votes': 5,
          'lastActiveAt': longAgo,
        });

        await repo.grantVotesAndTouch('u1');

        final doc = await firestore.collection('users').doc('u1').get();
        // Should have granted floor(log₃(28)) = 3 votes.
        expect(doc.data()!['votes'], 8);
      });

      test('grants 0 votes when less than 3 hours', () async {
        final recent = DateTime.now().toUtc().subtract(
          const Duration(hours: 1),
        );
        await firestore.collection('users').doc('u1').set({
          'uid': 'u1',
          'votes': 5,
          'lastActiveAt': recent,
        });

        await repo.grantVotesAndTouch('u1');

        final doc = await firestore.collection('users').doc('u1').get();
        expect(doc.data()!['votes'], 5);
      });

      test('does nothing for nonexistent user', () async {
        // Should not throw.
        await repo.grantVotesAndTouch('ghost');
      });
    });

    group('linking and search', () {
      test('linkProblems merges cliques symmetrically', () async {
        await seedProblem(id: 'p1');
        await seedProblem(id: 'p2');
        await seedProblem(id: 'p3');

        // Link p1 and p2 first
        await repo.linkProblems('p1', 'p2');

        var updatedP1 = await repo.getProblem('p1');
        var updatedP2 = await repo.getProblem('p2');
        expect(updatedP1!.linkedProblemIds, ['p2']);
        expect(updatedP2!.linkedProblemIds, ['p1']);

        // Merge p3 into the cluster
        await repo.linkProblems('p2', 'p3');

        updatedP1 = await repo.getProblem('p1');
        updatedP2 = await repo.getProblem('p2');
        final updatedP3 = await repo.getProblem('p3');

        // Fully connected clique: p1, p2, p3 each linked to all others
        expect(updatedP1!.linkedProblemIds.toSet(), {'p2', 'p3'});
        expect(updatedP2!.linkedProblemIds.toSet(), {'p1', 'p3'});
        expect(updatedP3!.linkedProblemIds.toSet(), {'p1', 'p2'});
      });

      test('unlinkProblem removes a problem symmetrically', () async {
        await seedProblem(id: 'p1');
        await seedProblem(id: 'p2');
        await seedProblem(id: 'p3');

        // Link p1, p2, p3
        await repo.linkProblems('p1', 'p2');
        await repo.linkProblems('p2', 'p3');

        // Unlink p3
        await repo.unlinkProblem('p3');

        final updatedP1 = await repo.getProblem('p1');
        final updatedP2 = await repo.getProblem('p2');
        final updatedP3 = await repo.getProblem('p3');

        // p1 and p2 should still be linked together
        expect(updatedP1!.linkedProblemIds, ['p2']);
        expect(updatedP2!.linkedProblemIds, ['p1']);
        // p3 should be completely unlinked
        expect(updatedP3!.linkedProblemIds, isEmpty);
      });

      test('tagProblemLink writes mirrored kinds on both sides', () async {
        await seedProblem(id: 'p1');
        await seedProblem(id: 'p2');

        await repo.tagProblemLink(
          sourceId: 'p1',
          targetId: 'p2',
          kind: ProblemLinkKind.specialization,
        );

        final p1 = await repo.getProblem('p1');
        final p2 = await repo.getProblem('p2');
        expect(p1!.typedLinks, [
          const ProblemLink(
            targetId: 'p2',
            kind: ProblemLinkKind.specialization,
          ),
        ]);
        expect(p2!.typedLinks, [
          const ProblemLink(
            targetId: 'p1',
            kind: ProblemLinkKind.generalization,
          ),
        ]);
      });

      test('tagProblemLink severs pre-existing generic link', () async {
        await seedProblem(id: 'p1');
        await seedProblem(id: 'p2');
        await repo.linkProblems('p1', 'p2');

        await repo.tagProblemLink(
          sourceId: 'p1',
          targetId: 'p2',
          kind: ProblemLinkKind.specialization,
        );

        final p1 = await repo.getProblem('p1');
        final p2 = await repo.getProblem('p2');
        expect(p1!.linkedProblemIds, isEmpty);
        expect(p2!.linkedProblemIds, isEmpty);
        expect(p1.typedLinks, hasLength(1));
        expect(p2.typedLinks, hasLength(1));
      });

      test('tagProblemLink replacing kind deduplicates', () async {
        await seedProblem(id: 'p1');
        await seedProblem(id: 'p2');

        await repo.tagProblemLink(
          sourceId: 'p1',
          targetId: 'p2',
          kind: ProblemLinkKind.specialization,
        );
        await repo.tagProblemLink(
          sourceId: 'p1',
          targetId: 'p2',
          kind: ProblemLinkKind.generalization,
        );

        final p1 = await repo.getProblem('p1');
        final p2 = await repo.getProblem('p2');
        expect(p1!.typedLinks, [
          const ProblemLink(
            targetId: 'p2',
            kind: ProblemLinkKind.generalization,
          ),
        ]);
        expect(p2!.typedLinks, [
          const ProblemLink(
            targetId: 'p1',
            kind: ProblemLinkKind.specialization,
          ),
        ]);
      });

      test('untagProblemLink removes both sides without restoring '
          'generic link', () async {
        await seedProblem(id: 'p1');
        await seedProblem(id: 'p2');
        await repo.tagProblemLink(
          sourceId: 'p1',
          targetId: 'p2',
          kind: ProblemLinkKind.specialization,
        );

        await repo.untagProblemLink(sourceId: 'p1', targetId: 'p2');

        final p1 = await repo.getProblem('p1');
        final p2 = await repo.getProblem('p2');
        expect(p1!.typedLinks, isEmpty);
        expect(p2!.typedLinks, isEmpty);
        expect(p1.linkedProblemIds, isEmpty);
        expect(p2.linkedProblemIds, isEmpty);
      });

      test('invariant: a pair never appears in both lists at once', () async {
        await seedProblem(id: 'p1');
        await seedProblem(id: 'p2');
        await seedProblem(id: 'p3');

        await repo.linkProblems('p1', 'p2');
        await repo.linkProblems('p2', 'p3');
        await repo.tagProblemLink(
          sourceId: 'p1',
          targetId: 'p2',
          kind: ProblemLinkKind.generalization,
        );

        Future<void> assertInvariant(String id) async {
          final p = await repo.getProblem(id);
          final genericIds = p!.linkedProblemIds.toSet();
          final typedIds = p.typedLinks.map((l) => l.targetId).toSet();
          expect(
            genericIds.intersection(typedIds),
            isEmpty,
            reason:
                'problem $id has overlap between linkedProblemIds and '
                'typedLinks',
          );
        }

        await assertInvariant('p1');
        await assertInvariant('p2');
        await assertInvariant('p3');
      });

      test('getGlobalProblemsForSearch returns active problems', () async {
        await seedProblem(id: 'p1', votes: 10);
        await seedProblem(id: 'p2', solved: true, votes: 50);
        await seedProblem(id: 'p3', votes: 20);

        final results = await repo.getGlobalProblemsForSearch();
        expect(results, hasLength(2));
        // Sorted by votes DESC, then ID ASC
        expect(results[0].id, 'p3');
        expect(results[1].id, 'p1');
      });

      test('getGlobalProblemsForSearch excludes hidden problems', () async {
        await seedProblem(id: 'p1', votes: 10);
        await seedProblem(id: 'p2', votes: 20, hidden: true);
        await seedProblem(id: 'p3', votes: 30);

        final results = await repo.getGlobalProblemsForSearch();
        expect(results.map((p) => p.id).toList(), ['p3', 'p1']);
      });
    });
  });
}
