// lib/services/rota_service.dart
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'auth_service.dart'; // Aggiungi questo import

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
    try {
      final uri = Uri.parse("$baseUrl/rota/shift-requests")
          .replace(queryParameters: {"db": db, "userEmail": userEmail});

      print('📡 Fetching shift requests from: $uri');
      final res = await http.get(uri).timeout(const Duration(seconds: 10));

      if (res.statusCode != 200) {
        throw Exception("fetchShiftRequests HTTP ${res.statusCode}: ${res.body}");
      }

      final decoded = jsonDecode(res.body);
      
      // expected: { success:true, shifts:[...] } OR just [...]
      if (decoded is Map && decoded["success"] == false) {
        throw Exception(decoded["message"] ?? "Failed to fetch shift requests");
      }
      
      if (decoded is Map && decoded["shifts"] is List) {
        return List<Map<String, dynamic>>.from(decoded["shifts"]);
      }
      if (decoded is List) {
        return decoded.map((e) => Map<String, dynamic>.from(e)).toList();
      }

      return [];
    } catch (e) {
      print('❌ Error fetching shift requests: $e');
      rethrow;
    }
  }

  // -------------------------------------------
  // GET: fetch all employees
  // -------------------------------------------
  Future<List<Map<String, dynamic>>> fetchAllEmployees({
    required String db,
  }) async {
    try {
      final uri = Uri.parse("$baseUrl/rota/employees").replace(
        queryParameters: {"db": db},
      );
      
      print('📡 Fetching employees from: $uri');
      final response = await http.get(uri).timeout(const Duration(seconds: 10));
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true) {
          final employees = List<Map<String, dynamic>>.from(data['employees'] ?? []);
          print('📊 Found ${employees.length} employees');
          return employees;
        }
      }
      return [];
    } catch (e) {
      print('❌ Error fetching employees: $e');
      return [];
    }
  }

  // -------------------------------------------
  // POST: create shift request (AM/admin only)
  // backend should generate unique 16-digit id
  // expects:
  // { db, userEmail, dayDate(YYYY-MM-DD), startTime(HH:mm:ss), endTime(HH:mm:ss), neededFor, targetEmployeeEmail? }
  // -------------------------------------------
  Future<bool> createShiftRequest({
    required String db,
    required String userEmail,
    required String dayDate,
    required String startTime,
    required String endTime,
    required String neededFor,
    String? targetEmployeeEmail, // Nuovo parametro opzionale
  }) async {
    try {
      final uri = Uri.parse("$baseUrl/rota/shift-request");

      print('📡 Creating shift request: $dayDate $startTime-$endTime');
      
      final body = {
        "db": db,
        "userEmail": userEmail,
        "dayDate": dayDate,
        "startTime": startTime,
        "endTime": endTime,
        "neededFor": neededFor, // anyone|foh|boh
      };
      
      // Aggiungi targetEmployeeEmail se presente
      if (targetEmployeeEmail != null && targetEmployeeEmail.isNotEmpty) {
        body["targetEmployeeEmail"] = targetEmployeeEmail;
      }

      final res = await http.post(
        uri,
        headers: {"Content-Type": "application/json"},
        body: jsonEncode(body),
      ).timeout(const Duration(seconds: 10));

      if (res.statusCode != 200) {
        print('❌ Create shift request failed: ${res.statusCode}');
        print('❌ Response: ${res.body}');
        throw Exception("createShiftRequest HTTP ${res.statusCode}: ${res.body}");
      }

      final decoded = jsonDecode(res.body);
      final success = decoded is Map && decoded["success"] == true;
      
      if (success) {
        print('✅ Shift request created successfully');
      } else {
        print('❌ Create shift request failed: ${decoded["message"]}');
      }
      
      return success;
    } catch (e) {
      print('❌ Error creating shift request: $e');
      return false;
    }
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
    try {
      final uri = Uri.parse("$baseUrl/rota/shift-request/$id/accept");

      print('📡 Accepting shift request: $id');
      
      final res = await http.post(
        uri,
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "db": db,
          "userEmail": userEmail,
        }),
      ).timeout(const Duration(seconds: 10));

      if (res.statusCode != 200) {
        print('❌ Accept shift request failed: ${res.statusCode}');
        print('❌ Response: ${res.body}');
        throw Exception("acceptShiftRequest HTTP ${res.statusCode}: ${res.body}");
      }

      final decoded = jsonDecode(res.body);
      final success = decoded is Map && decoded["success"] == true;
      
      if (success) {
        print('✅ Shift request $id accepted successfully');
      } else {
        print('❌ Accept shift request failed: ${decoded["message"]}');
      }
      
      return success;
    } catch (e) {
      print('❌ Error accepting shift request: $e');
      return false;
    }
  }

  // -------------------------------------------
  // GET: fetch my rota for a specific day
  // -------------------------------------------
  Future<List<Map<String, dynamic>>> fetchMyRotaForDay({
    required String db,
    required String userEmail,
    required String dateYYYYMMDD, // yyyy-mm-dd
  }) async {
    try {
      final uri = Uri.parse(
        "$baseUrl/rota/my-day?db=$db&email=$userEmail&date=$dateYYYYMMDD",
      );

      print('📡 Fetching my rota for day: $dateYYYYMMDD');
      final res = await http.get(uri).timeout(const Duration(seconds: 10));
      
      if (res.statusCode != 200) {
        throw Exception("fetchMyRotaForDay failed: ${res.statusCode} ${res.body}");
      }

      final body = jsonDecode(res.body);
      
      if (body is Map && body["success"] == true) {
        final list = List<Map<String, dynamic>>.from(body["shifts"] ?? []);
        print('📊 Found ${list.length} shifts for day $dateYYYYMMDD');
        return list;
      }

      // if you return plain list, handle that too:
      if (body is List) {
        print('📊 Found ${body.length} shifts for day $dateYYYYMMDD');
        return List<Map<String, dynamic>>.from(body);
      }

      return [];
    } catch (e) {
      print('❌ Error fetching my rota for day: $e');
      return [];
    }
  }

  // -------------------------------------------
  // POST: create shift directly (for AM/Manager)
  // This creates a shift and assigns it to an employee immediately
  // -------------------------------------------
  Future<bool> createDirectShift({
    required String db,
    required String userEmail,
    required String dayDate,
    required String startTime,
    required String endTime,
    required String neededFor,
    required String targetEmployeeEmail,
    required String targetEmployeeName,
    required String targetEmployeeLastName,
    required String targetEmployeeDesignation,
  }) async {
    try {
      final uri = Uri.parse("$baseUrl/rota/direct-shift");

      print('📡 Creating direct shift for: $targetEmployeeEmail');
      
      final body = {
        "db": db,
        "userEmail": userEmail,
        "dayDate": dayDate,
        "startTime": startTime,
        "endTime": endTime,
        "neededFor": neededFor,
        "targetEmployeeEmail": targetEmployeeEmail,
        "targetEmployeeName": targetEmployeeName,
        "targetEmployeeLastName": targetEmployeeLastName,
        "targetEmployeeDesignation": targetEmployeeDesignation,
      };

      final res = await http.post(
        uri,
        headers: {"Content-Type": "application/json"},
        body: jsonEncode(body),
      ).timeout(const Duration(seconds: 10));

      if (res.statusCode != 200) {
        print('❌ Create direct shift failed: ${res.statusCode}');
        print('❌ Response: ${res.body}');
        throw Exception("createDirectShift HTTP ${res.statusCode}: ${res.body}");
      }

      final decoded = jsonDecode(res.body);
      final success = decoded is Map && decoded["success"] == true;
      
      if (success) {
        print('✅ Direct shift created successfully');
      } else {
        print('❌ Create direct shift failed: ${decoded["message"]}');
      }
      
      return success;
    } catch (e) {
      print('❌ Error creating direct shift: $e');
      return false;
    }
  }

  // Aggiungi questo metodo in rota_service.dart
  Future<bool> addShiftToRota({
  required String db,
  required String userEmail,
  required String dayLabel,
  required String dayDate,
  required String startTime,
  required String endTime,
  required String employeeEmail,
  required String employeeName,
  required String employeeLastName,
  required String employeeDesignation,
}) async {
  try {
    final uri = Uri.parse("$baseUrl/rota/add-direct");
    
    print('📡 Adding shift to rota: $dayLabel for $employeeEmail');
    print('📡 Data: start=$startTime, end=$endTime');
    
    final response = await http.post(
      uri,
      headers: {"Content-Type": "application/json"},
      body: jsonEncode({
        "db": db,
        "userEmail": userEmail,
        "dayLabel": dayLabel,
        "dayDate": dayDate,
        "startTime": startTime,
        "endTime": endTime,
        "employeeEmail": employeeEmail,
        "employeeName": employeeName,
        "employeeLastName": employeeLastName,
        "employeeDesignation": employeeDesignation,
      }),
    ).timeout(const Duration(seconds: 10));
    
    print('📡 Response status: ${response.statusCode}');
    print('📡 Response body: ${response.body}');
    
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return data['success'] == true;
    }
    return false;
  } catch (e) {
    print('❌ Error adding to rota: $e');
    return false;
  }
}

  // -------------------------------------------
  // GET: fetch shift requests created by user (for AM/Manager)
  // -------------------------------------------
  Future<List<Map<String, dynamic>>> fetchMyCreatedShiftRequests({
    required String db,
    required String userEmail,
  }) async {
    try {
      final uri = Uri.parse("$baseUrl/rota/my-created-requests")
          .replace(queryParameters: {"db": db, "userEmail": userEmail});

      print('📡 Fetching my created shift requests');
      final res = await http.get(uri).timeout(const Duration(seconds: 10));

      if (res.statusCode != 200) {
        throw Exception("fetchMyCreatedShiftRequests HTTP ${res.statusCode}: ${res.body}");
      }

      final decoded = jsonDecode(res.body);
      
      if (decoded is Map && decoded["success"] == true) {
        return List<Map<String, dynamic>>.from(decoded["shifts"] ?? []);
      }
      if (decoded is List) {
        return decoded.map((e) => Map<String, dynamic>.from(e)).toList();
      }

      return [];
    } catch (e) {
      print('❌ Error fetching my created shift requests: $e');
      return [];
    }
  }

  // -------------------------------------------
  // POST: cancel shift request (AM/Manager only)
  // -------------------------------------------
  Future<bool> cancelShiftRequest({
    required String db,
    required String id,
    required String userEmail,
  }) async {
    try {
      final uri = Uri.parse("$baseUrl/rota/shift-request/$id/cancel");

      print('📡 Cancelling shift request: $id');
      
      final res = await http.post(
        uri,
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "db": db,
          "userEmail": userEmail,
        }),
      ).timeout(const Duration(seconds: 10));

      if (res.statusCode != 200) {
        throw Exception("cancelShiftRequest HTTP ${res.statusCode}: ${res.body}");
      }

      final decoded = jsonDecode(res.body);
      return decoded is Map && decoded["success"] == true;
    } catch (e) {
      print('❌ Error cancelling shift request: $e');
      return false;
    }
  }
}