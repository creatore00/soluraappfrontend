import 'dart:convert';
import 'package:http/http.dart' as http;

import 'auth_service.dart';

class HolidaysService {
  static Future<List<Map<String, dynamic>>> fetchPending({
    required String db,
  }) async {
    final uri = Uri.parse("${AuthService.baseUrl}/holidays/pending?db=$db");

    final res = await http.get(uri);
    if (res.statusCode != 200) {
      throw Exception("Failed to load pending holidays (${res.statusCode})");
    }

    final body = jsonDecode(res.body);

    // {success:true, holidays:[...]}
    if (body is Map && body["success"] == true && body["holidays"] is List) {
      return List<Map<String, dynamic>>.from(body["holidays"]);
    }

    // direct array
    if (body is List) {
      return List<Map<String, dynamic>>.from(body);
    }

    throw Exception("Unexpected response format");
  }

static Future<void> decide({
  required String db,
  required int id,
  required String decision,   // "approve" or "decline"
  required String actorEmail, // manager/AM email
  String? reason,             // optional decline reason
}) async {
  final res = await http.post(
    Uri.parse("${AuthService.baseUrl}/holidays/decide"),
    headers: {'Content-Type': 'application/json'},
    body: jsonEncode({
      "db": db,
      "id": id,
      "decision": decision,
      "actorEmail": actorEmail,
      "reason": reason ?? "",
    }),
  );

  final data = jsonDecode(res.body);
  if (res.statusCode != 200 || data['success'] != true) {
    throw Exception(data['message'] ?? "Failed to save decision");
  }
}

}
