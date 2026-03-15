import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared/shared.dart';

class ApiService {
  ApiService(this.baseUrl);
  final String baseUrl;

  Future<Problem> getProblem(String id) async {
    final response = await http.get(Uri.parse('$baseUrl/problems/$id'));
    if (response.statusCode == 200) {
      return Problem.fromJson(
        jsonDecode(response.body) as Map<String, dynamic>,
      );
    }
    throw Exception('Failed to load problem');
  }

  Future<void> addProblem(Problem problem) async {
    final response = await http.post(
      Uri.parse('$baseUrl/problems'),
      headers: {'content-type': 'application/json'},
      body: jsonEncode(problem.toJson()),
    );
    if (response.statusCode != 201) {
      throw Exception('Failed to create problem');
    }
  }

  Future<Problem> putProblem(Problem problem) async {
    final response = await http.put(
      Uri.parse('$baseUrl/problems/${problem.id}'),
      headers: {'content-type': 'application/json'},
      body: jsonEncode(problem.toJson()),
    );
    if (response.statusCode == 200) {
      return Problem.fromJson(
        jsonDecode(response.body) as Map<String, dynamic>,
      );
    }
    throw Exception('Failed to update problem');
  }
}
