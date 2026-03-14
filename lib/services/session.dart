import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/database_access.dart';

class Session {
  static String? email;
  static String? db;    // selected dbName
  static String? role;
  static String? userId; // Add userId field

  // ✅ store full db list
  static List<DatabaseAccess> databases = [];

  // Session expiry (epoch millis)
  static int? expiresAtMs;

  static const _kEmail = "email";
  static const _kDb = "db";
  static const _kRole = "role";
  static const _kUserId = "userId"; // Add this constant
  static const _kExpiresAt = "expiresAtMs";
  static const _kDatabases = "databases";

  static const int ttlMinutes = 10;

  // Add getter methods
  static Future<String?> getEmail() async {
    if (email != null) return email;
    await load();
    return email;
  }

  static Future<String?> getUserId() async {
    if (userId != null) return userId;
    await load();
    return userId;
  }

  static Future<String?> getDb() async {
    if (db != null) return db;
    await load();
    return db;
  }

  static Future<String?> getRole() async {
    if (role != null) return role;
    await load();
    return role;
  }

  static Future<void> save() async {
    final prefs = await SharedPreferences.getInstance();

    final now = DateTime.now().millisecondsSinceEpoch;
    expiresAtMs = now + Duration(minutes: ttlMinutes).inMilliseconds;

    await prefs.setString(_kEmail, email ?? "");
    await prefs.setString(_kDb, db ?? "");
    await prefs.setString(_kRole, role ?? "");
    await prefs.setString(_kUserId, userId ?? ""); // Save userId
    await prefs.setInt(_kExpiresAt, expiresAtMs ?? 0);

    // ✅ save databases list as JSON
    final dbJson = jsonEncode(databases.map((d) => {
      "dbName": d.dbName,
      "access": d.access,
    }).toList());
    await prefs.setString(_kDatabases, dbJson);
  }

  static Future<void> touch() async {
    if (email == null || db == null || role == null) return;
    await save();
  }

  static Future<bool> load() async {
    final prefs = await SharedPreferences.getInstance();

    final storedEmail = prefs.getString(_kEmail) ?? "";
    final storedDb = prefs.getString(_kDb) ?? "";
    final storedRole = prefs.getString(_kRole) ?? "";
    final storedUserId = prefs.getString(_kUserId) ?? ""; // Load userId
    final storedExpiresAt = prefs.getInt(_kExpiresAt) ?? 0;
    final storedDatabases = prefs.getString(_kDatabases) ?? "";

    if (storedEmail.isEmpty || storedDb.isEmpty || storedRole.isEmpty) {
      return false;
    }

    final now = DateTime.now().millisecondsSinceEpoch;
    if (storedExpiresAt <= now) {
      await clear();
      return false;
    }

    email = storedEmail;
    db = storedDb;
    role = storedRole;
    userId = storedUserId.isEmpty ? null : storedUserId; // Set userId
    expiresAtMs = storedExpiresAt;

    // ✅ load databases list
    databases = [];
    if (storedDatabases.isNotEmpty) {
      try {
        final decoded = jsonDecode(storedDatabases);
        if (decoded is List) {
          databases = decoded.map((x) => DatabaseAccess(
            dbName: x["dbName"] ?? "",
            access: x["access"] ?? "",
          )).where((d) => d.dbName.trim().isNotEmpty).toList();
        }
      } catch (_) {}
    }

    return true;
  }

  static bool isExpired() {
    if (expiresAtMs == null) return true;
    final now = DateTime.now().millisecondsSinceEpoch;
    return expiresAtMs! <= now;
  }

  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kEmail);
    await prefs.remove(_kDb);
    await prefs.remove(_kRole);
    await prefs.remove(_kUserId); // Remove userId
    await prefs.remove(_kExpiresAt);
    await prefs.remove(_kDatabases);

    email = null;
    db = null;
    role = null;
    userId = null; // Clear userId
    databases = [];
    expiresAtMs = null;
  }
}