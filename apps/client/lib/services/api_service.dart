import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared/shared.dart';

class ApiService {
  ApiService(this.baseUrl);
  final String baseUrl;

  Future<Problem> getProblem(String id) async {
    final response = await http.get(Uri.parse('$baseUrl/problem/$id'));
    if (response.statusCode == 200) {
      return Problem.fromJson(
        jsonDecode(response.body) as Map<String, dynamic>,
      );
    }
    throw Exception('Failed to load problem');
  }
}
