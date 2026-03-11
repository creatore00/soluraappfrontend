import 'dart:convert';
import 'package:http/http.dart' as http;

class NotificationsService {
  static const String baseUrl = "https://solura-backend.onrender.com";

  static Future<List<dynamic>> fetchNotifications({required String db, required String role}) async {
    try {
      final response = await http.get(
        Uri.parse("$baseUrl/notifications?db=$db&role=$role"),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true) {
          return data['notifications'] ?? [];
        }
      }
      return [];
    } catch (e) {
      print('Error fetching notifications: $e');
      return [];
    }
  }

  static Future<int> fetchUnreadCount({required String db, required String role}) async {
    try {
      final response = await http.get(
        Uri.parse("$baseUrl/notifications/unread?db=$db&role=$role"),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true) {
          return data['unreadCount'] ?? 0;
        }
      }
      return 0;
    } catch (e) {
      print('Error fetching unread count: $e');
      return 0;
    }
  }

  static Future<void> markAsRead({required String db, required int id}) async {
    try {
      await http.post(
        Uri.parse("$baseUrl/notifications/mark-read"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({"db": db, "id": id}),
      );
    } catch (e) {
      print('Error marking notification as read: $e');
    }
  }

  static Future<void> markAllAsRead({required String db, required List<int> ids}) async {
    try {
      await http.post(
        Uri.parse("$baseUrl/notifications/mark-all-read"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({"db": db, "ids": ids}),
      );
    } catch (e) {
      print('Error marking all notifications as read: $e');
    }
  }
}