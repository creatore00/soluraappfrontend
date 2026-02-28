// ==================================
// FRONTEND: employees_screen.dart (FULL)
// - Fetches employees from backend
// - Sorts by POSITION: AM -> MANAGER -> SUPERVISOR -> TM (then lastName, name)
// - Shows full role labels: Area Manager / Manager / Supervisor / Team Member
// - Highlights logged-in user
// - Tap on avatar to view larger image
// ==================================
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../models/database_access.dart';
import '../services/auth_service.dart';

class EmployeesScreen extends StatefulWidget {
  final DatabaseAccess selectedDb;
  final String userEmail;

  const EmployeesScreen({
    super.key,
    required this.selectedDb,
    required this.userEmail,
  });

  @override
  State<EmployeesScreen> createState() => _EmployeesScreenState();
}

class EmployeeItem {
  final String name;
  final String lastName;
  final String email;

  // IMPORTANT: you said you want sorting by POSITION
  final String position;

  // You also have designation (kept, but not used for sorting/badge)
  final String designation;

  final String? profileImage;
  final String? profileImageMime;

  EmployeeItem({
    required this.name,
    required this.lastName,
    required this.email,
    required this.position,
    required this.designation,
    required this.profileImage,
    required this.profileImageMime,
  });

  factory EmployeeItem.fromJson(Map<String, dynamic> json) {
    return EmployeeItem(
      name: (json['name'] ?? '').toString(),
      lastName: (json['lastName'] ?? '').toString(),
      email: (json['email'] ?? '').toString(),
      position: (json['position'] ?? '').toString(),
      designation: (json['designation'] ?? '').toString(),
      profileImage: json['profileImage']?.toString(),
      profileImageMime: json['profileImageMime']?.toString(),
    );
  }
}

class _EmployeesScreenState extends State<EmployeesScreen> {
  bool loading = true;
  bool error = false;
  String errorMessage = "";

  List<EmployeeItem> employees = [];
  String currentEmail = "";

  @override
  void initState() {
    super.initState();
    fetchEmployees();
  }

  // ---------- POSITION sorting + labels ----------
  int _positionRank(String pos) {
    final p = pos.trim().toUpperCase();
    if (p == "AM" || p == "AREA MANAGER") return 0;
    if (p == "MANAGER") return 1;
    if (p == "SUPERVISOR") return 2;
    if (p == "TM" || p == "TEAM MEMBER") return 3;
    return 99;
  }

  String _positionLabel(String pos) {
    final p = pos.trim().toUpperCase();
    if (p == "AM" || p == "AREA MANAGER") return "Area Manager";
    if (p == "MANAGER") return "Manager";
    if (p == "SUPERVISOR") return "Supervisor";
    if (p == "TM" || p == "TEAM MEMBER") return "Team Member";
    return pos.trim().isEmpty ? "-" : pos.trim();
  }

  Color _positionColor(String pos) {
    final p = pos.trim().toUpperCase();
    if (p == "AM" || p == "AREA MANAGER") return const Color(0xFF4CC9F0);
    if (p == "MANAGER") return const Color(0xFF4ADE80);
    if (p == "SUPERVISOR") return Colors.orange;
    if (p == "TM" || p == "TEAM MEMBER") return Colors.white.withOpacity(0.7);
    return Colors.white.withOpacity(0.6);
  }

  // ---------- Fetch ----------
  Future<void> fetchEmployees() async {
    if (!mounted) return;

    setState(() {
      loading = true;
      error = false;
      errorMessage = "";
    });

    try {
      final uri = Uri.parse("${AuthService.baseUrl}/employees").replace(
        queryParameters: {
          "db": widget.selectedDb.dbName,
          "email": widget.userEmail,
        },
      );

      final response = await http.get(uri);

      if (response.statusCode != 200) {
        throw Exception("Failed: ${response.statusCode} - ${response.body}");
      }

      final body = response.body.trim();
      if (body.startsWith("<!DOCTYPE html>")) {
        throw Exception("Server returned HTML. Check backend route mapping for /employees.");
      }

      final data = jsonDecode(body);
      if (data["success"] != true) {
        throw Exception(data["message"] ?? "Failed to fetch employees");
      }

      final list = (data["employees"] ?? []) as List;
      final parsed = list.map((e) => EmployeeItem.fromJson(e as Map<String, dynamic>)).toList();

      // ✅ Sort by POSITION (not designation)
      parsed.sort((a, b) {
        final ra = _positionRank(a.position);
        final rb = _positionRank(b.position);
        if (ra != rb) return ra.compareTo(rb);

        final ln = a.lastName.toLowerCase().compareTo(b.lastName.toLowerCase());
        if (ln != 0) return ln;

        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });

      if (!mounted) return;
      setState(() {
        employees = parsed;
        currentEmail = (data["currentEmail"] ?? "").toString().trim().toLowerCase();
        loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        loading = false;
        error = true;
        errorMessage = e.toString();
      });
    }
  }

  // ---------- UI helpers ----------
  String _initials(EmployeeItem e) {
    final a = e.name.trim().isNotEmpty ? e.name.trim()[0].toUpperCase() : "";
    final b = e.lastName.trim().isNotEmpty ? e.lastName.trim()[0].toUpperCase() : "";
    final s = (a + b).trim();
    return s.isEmpty ? "?" : s;
  }

  // ---------- Show larger image dialog ----------
  void _showLargeImage(EmployeeItem e) {
    if (e.profileImage == null || e.profileImage!.isEmpty) {
      // No image to show
      return;
    }

    try {
      final bytes = base64Decode(e.profileImage!);
      
      showDialog(
        context: context,
        builder: (BuildContext context) {
          return Dialog(
            backgroundColor: Colors.transparent,
            insetPadding: const EdgeInsets.all(20),
            child: Stack(
              alignment: Alignment.center,
              children: [
                // Close button at top right
                Positioned(
                  top: 0,
                  right: 0,
                  child: Container(
                    margin: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.5),
                      shape: BoxShape.circle,
                    ),
                    child: IconButton(
                      icon: const Icon(Icons.close, color: Colors.white, size: 28),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ),
                ),
                
                // Image container
                Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.white.withOpacity(0.2), width: 2),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.5),
                        blurRadius: 20,
                        spreadRadius: 5,
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(18),
                    child: Image.memory(
                      bytes,
                      fit: BoxFit.contain,
                      errorBuilder: (context, error, stackTrace) {
                        return Container(
                          width: 300,
                          height: 300,
                          color: Colors.grey[900],
                          child: const Center(
                            child: Text(
                              "Failed to load image",
                              style: TextStyle(color: Colors.white),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
                
                // Employee name at bottom
                Positioned(
                  bottom: 20,
                  left: 0,
                  right: 0,
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 20),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.6),
                      borderRadius: BorderRadius.circular(30),
                      border: Border.all(color: Colors.white.withOpacity(0.2)),
                    ),
                    child: Text(
                      "${e.name} ${e.lastName}".trim(),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      );
    } catch (_) {
      // Handle error silently
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text("Failed to load image"),
          backgroundColor: Colors.red[700],
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Widget _avatar(EmployeeItem e) {
    Widget avatarWidget;
    
    if (e.profileImage != null && e.profileImage!.isNotEmpty) {
      try {
        final bytes = base64Decode(e.profileImage!);
        avatarWidget = CircleAvatar(
          radius: 24,
          backgroundImage: MemoryImage(bytes),
          backgroundColor: Colors.white.withOpacity(0.08),
        );
      } catch (_) {
        // fallback below
        avatarWidget = CircleAvatar(
          radius: 24,
          backgroundColor: Colors.white.withOpacity(0.08),
          child: Text(
            _initials(e),
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          ),
        );
      }
    } else {
      avatarWidget = CircleAvatar(
        radius: 24,
        backgroundColor: Colors.white.withOpacity(0.08),
        child: Text(
          _initials(e),
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
      );
    }

    // Wrap with InkWell for tap functionality
    return InkWell(
      onTap: () => _showLargeImage(e),
      borderRadius: BorderRadius.circular(30),
      child: avatarWidget,
    );
  }

  Widget _employeeCard(EmployeeItem e) {
    final isMe = e.email.trim().toLowerCase() == currentEmail;

    // ✅ badge uses POSITION
    final roleColor = _positionColor(e.position);

    final bg = isMe ? Colors.white.withOpacity(0.06) : Colors.white.withOpacity(0.03);
    final border = isMe ? const Color(0xFF4CC9F0).withOpacity(0.55) : Colors.white.withOpacity(0.08);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: border),
      ),
      child: Row(
        children: [
          _avatar(e),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        "${e.name} ${e.lastName}".trim(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 15,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Container(
                      constraints: const BoxConstraints(maxWidth: 170),
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: roleColor.withOpacity(0.18),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(color: roleColor.withOpacity(0.35)),
                      ),
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          _positionLabel(e.position),
                          style: TextStyle(color: roleColor, fontWeight: FontWeight.bold, fontSize: 12),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 10,
                  runSpacing: 6,
                  children: [
                    // show designation as secondary text if you want
                    if (e.designation.trim().isNotEmpty)
                      Text(
                        e.designation.trim(),
                        style: TextStyle(color: Colors.white.withOpacity(0.75)),
                      ),
                    if (e.email.trim().isNotEmpty)
                      Text(
                        e.email.trim(),
                        style: TextStyle(color: Colors.white.withOpacity(0.55), fontSize: 12),
                      ),
                  ],
                ),
                if (isMe) ...[
                  const SizedBox(height: 6),
                  Text(
                    "You",
                    style: TextStyle(
                      color: const Color(0xFF4CC9F0).withOpacity(0.9),
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ---------- Build ----------
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A192F),
      appBar: AppBar(
        backgroundColor: const Color(0xFF172A45),
        elevation: 0,
        title: const Text(
          "Employees",
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Color(0xFF4CC9F0)),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            tooltip: "Refresh",
            icon: const Icon(Icons.refresh, color: Color(0xFF4CC9F0)),
            onPressed: fetchEmployees,
          ),
        ],
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF0A192F), Color(0xFF172A45), Color(0xFF0A192F)],
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: loading
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const CircularProgressIndicator(color: Color(0xFF4CC9F0)),
                      const SizedBox(height: 12),
                      Text("Loading employees...", style: TextStyle(color: Colors.white.withOpacity(0.7))),
                    ],
                  ),
                )
              : error
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.error_outline, size: 60, color: Colors.red.withOpacity(0.7)),
                          const SizedBox(height: 12),
                          Text(
                            "Failed to load employees",
                            style: TextStyle(color: Colors.white.withOpacity(0.85), fontSize: 16),
                          ),
                          const SizedBox(height: 8),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 10),
                            child: Text(
                              errorMessage,
                              textAlign: TextAlign.center,
                              style: TextStyle(color: Colors.white.withOpacity(0.6)),
                            ),
                          ),
                          const SizedBox(height: 14),
                          ElevatedButton(
                            onPressed: fetchEmployees,
                            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF4CC9F0)),
                            child: const Text("Try Again"),
                          ),
                        ],
                      ),
                    )
                  : employees.isEmpty
                      ? Center(
                          child: Text(
                            "No employees found.",
                            style: TextStyle(color: Colors.white.withOpacity(0.6)),
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.only(bottom: 12),
                          itemCount: employees.length,
                          itemBuilder: (_, i) => _employeeCard(employees[i]),
                        ),
        ),
      ),
    );
  }
}