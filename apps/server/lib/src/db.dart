import 'package:googleapis/firestore/v1.dart' as fs;
import 'package:googleapis_auth/auth_io.dart';
import 'package:shared/shared.dart';

/// Storage via Firestore using the official googleapis client.
/// Authenticates automatically via App Default Creds on Cloud Run.
class Db {
  Db._(this._firestore, this._basePath);

  final fs.FirestoreApi _firestore;
  final String _basePath;

  /// Creates a [Db] instance authenticated via ADC.
  static Future<Db> initialize(String projectId) async {
    final client = await clientViaApplicationDefaultCredentials(
      scopes: [fs.FirestoreApi.datastoreScope],
    );
    final firestore = fs.FirestoreApi(client);
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

  /// Fetch a page of problems.
  Future<({List<Problem> problems, String? nextPageToken})> getProblems({
    int pageSize = 99,
    String? pageToken,
  }) async {
    final result = await _firestore.projects.databases.documents.list(
      _basePath,
      'problems',
      pageSize: pageSize,
      pageToken: pageToken,
    );
    final problems = (result.documents ?? []).map((doc) {
      final id = doc.name!.split('/').last;
      return Problem(
        id: id,
        description: doc.fields!['description']!.stringValue!,
        votes: int.parse(doc.fields!['votes']!.integerValue!),
      );
    }).toList();
    return (problems: problems, nextPageToken: result.nextPageToken);
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
