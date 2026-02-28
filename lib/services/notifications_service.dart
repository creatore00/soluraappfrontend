import 'dart:convert';
import 'package:http/http.dart' as http;
import 'auth_service.dart';

class NotificationsService {
  static Future<List<Map<String, dynamic>>> fetchNotifications({
    required String db,
    required String role,
  }) async {
    final uri = Uri.parse("${AuthService.baseUrl}/notifications?db=$db&role=$role");
    final res = await http.get(uri);

    if (res.statusCode != 200) {
      throw Exception("Failed to fetch notifications (${res.statusCode})");
    }

    final body = res.body.trim();
    if (body.startsWith('<!DOCTYPE html>')) {
      throw Exception("Server returned HTML error page for /notifications");
    }

    final data = jsonDecode(body);
    if (data['success'] != true) {
      throw Exception(data['message'] ?? "Unknown error");
    }

    final list = List<Map<String, dynamic>>.from(data['notifications'] ?? []);
    return list;
  }

  static Future<void> markAsRead({
    required String db,
    required int id,
  }) async {
    final uri = Uri.parse("${AuthService.baseUrl}/notifications/read");
    final res = await http.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'db': db, 'id': id}),
    );

    final body = res.body.trim();
    if (body.startsWith('<!DOCTYPE html>')) {
      throw Exception("Server returned HTML error page for /notifications/read");
    }

    final data = jsonDecode(body);
    if (res.statusCode != 200 || data['success'] != true) {
      throw Exception(data['message'] ?? "Failed to mark as read");
    }
  }

  static Future<int> fetchUnreadCount({
    required String db,
    required String role,
  }) async {
    final list = await fetchNotifications(db: db, role: role);
    return list.where((n) => (n['isRead'] == 0 || n['isRead'] == false)).length;
  }

  static Future<void> markAllAsRead({
    required String db,
    required List<int> ids,
  }) async {
    // Backend doesn’t have bulk endpoint, so do sequential.
    for (final id in ids) {
      await markAsRead(db: db, id: id);
    }
  }
}
