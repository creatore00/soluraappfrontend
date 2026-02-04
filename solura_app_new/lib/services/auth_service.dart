import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/database_access.dart';

class AuthResult {
  final bool success;
  final String message;
  final String? email;
  final List<DatabaseAccess> databases;

  AuthResult({
    required this.success,
    required this.message,
    this.email,
    required this.databases,
  });
}

class AuthService {
  // Hosted backend
  static const String baseUrl = "https://solura-backend.onrender.com";

  static Future<AuthResult> login(String email, String password) async {
    final url = Uri.parse("$baseUrl/login");

    try {
      final response = await http.post(
        url,
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({"email": email, "password": password}),
      );

      final data = jsonDecode(response.body);

      if (data["success"] != true) {
        return AuthResult(
          success: false,
          message: data["message"] ?? "Login failed",
          databases: [],
        );
      }

      final List databasesJson = data["databases"] ?? [];
      final databases = databasesJson
          .map((db) => DatabaseAccess.fromJson(db))
          .toList()
          .cast<DatabaseAccess>();

      return AuthResult(
        success: true,
        message: data["message"] ?? "Login successful",
        email: data["email"],
        databases: databases,
      );
    } catch (e) {
      return AuthResult(
        success: false,
        message: "Server connection error: $e",
        databases: [],
      );
    }
  }
}
