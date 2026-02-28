// lib/services/rota_service.dart
import 'dart:convert';
import 'package:http/http.dart' as http;

class RotaService {
  // ✅ Change this to your Render / API base
  // Example: const String baseUrl = "https://your-app.onrender.com";
  static const String baseUrl = "https://solura-backend.onrender.com";

  // -------------------------------------------
  // GET: list shift requests
  // -------------------------------------------
  Future<List<Map<String, dynamic>>> fetchShiftRequests({
    required String db,
    required String userEmail,
  }) async {
    final uri = Uri.parse("$baseUrl/rota/shift-requests")
        .replace(queryParameters: {"db": db, "userEmail": userEmail});

    final res = await http.get(uri);

    if (res.statusCode != 200) {
      throw Exception("fetchShiftRequests HTTP ${res.statusCode}: ${res.body}");
    }

    final decoded = jsonDecode(res.body);
    if (decoded is Map && decoded["success"] == false) {
      throw Exception(decoded["message"] ?? "Failed to fetch shift requests");
    }

    // expected: { success:true, shifts:[...] } OR just [...]
    if (decoded is Map && decoded["shifts"] is List) {
      return List<Map<String, dynamic>>.from(decoded["shifts"]);
    }
    if (decoded is List) {
      return decoded.map((e) => Map<String, dynamic>.from(e)).toList();
    }

    return [];
  }

  // -------------------------------------------
  // POST: create shift request (AM/admin only)
  // backend should generate unique 16-digit id
  // expects:
  // { db, userEmail, dayDate(YYYY-MM-DD), startTime(HH:mm:ss), endTime(HH:mm:ss), neededFor }
  // -------------------------------------------
  Future<bool> createShiftRequest({
    required String db,
    required String userEmail,
    required String dayDate,
    required String startTime,
    required String endTime,
    required String neededFor,
  }) async {
    final uri = Uri.parse("$baseUrl/rota/shift-request");

    final res = await http.post(
      uri,
      headers: {"Content-Type": "application/json"},
      body: jsonEncode({
        "db": db,
        "userEmail": userEmail,
        "dayDate": dayDate,
        "startTime": startTime,
        "endTime": endTime,
        "neededFor": neededFor, // anyone|foh|boh
      }),
    );

    if (res.statusCode != 200) {
      throw Exception("createShiftRequest HTTP ${res.statusCode}: ${res.body}");
    }

    final decoded = jsonDecode(res.body);
    if (decoded is Map && decoded["success"] == true) return true;

    return false;
  }

  // -------------------------------------------
  // POST: accept shift request (everyone including AM/admin)
  // expects:
  // { db, userEmail }
  //
  // backend must:
  // - lock ShiftRequests row
  // - check eligibility vs needed_for using Employees.designation
  // - insert into rota with:
  //   id (same as shiftRequestId) (check rota.id not exists)
  //   name, lastName from Employees
  //   day (already formatted dd/mm/yyyy (Day) in ShiftRequests.day_label)
  //   startTime, endTime from ShiftRequests
  //   designation from Employees (FOH/BOH/...)
  // -------------------------------------------
  Future<bool> acceptShiftRequest({
    required String db,
    required String id,
    required String userEmail,
  }) async {
    final uri = Uri.parse("$baseUrl/rota/shift-request/$id/accept");

    final res = await http.post(
      uri,
      headers: {"Content-Type": "application/json"},
      body: jsonEncode({
        "db": db,
        "userEmail": userEmail,
      }),
    );

    if (res.statusCode != 200) {
      throw Exception("acceptShiftRequest HTTP ${res.statusCode}: ${res.body}");
    }

    final decoded = jsonDecode(res.body);
    if (decoded is Map && decoded["success"] == true) return true;

    return false;
  }

Future<List<Map<String, dynamic>>> fetchMyRotaForDay({
  required String db,
  required String userEmail,
  required String dateYYYYMMDD, // yyyy-mm-dd
}) async {
  // YOU MUST CREATE THIS ENDPOINT IN NODE:
  // GET /rota/my-day?db=...&email=...&date=yyyy-mm-dd
  final uri = Uri.parse(
    "$baseUrl/rota/my-day?db=$db&email=$userEmail&date=$dateYYYYMMDD",
  );

  final res = await http.get(uri);
  if (res.statusCode != 200) {
    throw Exception("fetchMyRotaForDay failed: ${res.statusCode} ${res.body}");
  }

  final body = jsonDecode(res.body);
  if (body is Map && body["success"] == true) {
    final list = List<Map<String, dynamic>>.from(body["shifts"] ?? []);
    return list;
  }

  // if you return plain list, handle that too:
  if (body is List) {
    return List<Map<String, dynamic>>.from(body);
  }

  return [];
}
}