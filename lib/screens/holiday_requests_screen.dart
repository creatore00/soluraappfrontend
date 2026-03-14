import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/database_access.dart';
import '../services/holidays_service.dart';
import '../services/session.dart';
import '../services/notifications_service.dart';
import '../services/rota_service.dart'; // ← AGGIUNTO per fetchEmployeeByEmail

class HolidayRequestsScreen extends StatefulWidget {
  final DatabaseAccess selectedDb;
  final String role; // "AM" or "Manager"

  const HolidayRequestsScreen({
    super.key,
    required this.selectedDb,
    required this.role,
  });

  @override
  State<HolidayRequestsScreen> createState() => _HolidayRequestsScreenState();
}

class _HolidayRequestsScreenState extends State<HolidayRequestsScreen> {
  bool loading = true;
  bool acting = false;
  List<Map<String, dynamic>> pending = [];
  final RotaService _rotaService = RotaService(); // ← AGGIUNTO

  @override
  void initState() {
    super.initState();
    _loadPending();
  }

  bool get _isApprover {
    final r = widget.role.trim().toLowerCase();
    return r == "am" || r == "manager";
  }

  Future<void> _loadPending() async {
    setState(() => loading = true);
    try {
      final list = await HolidaysService.fetchPending(
        db: widget.selectedDb.dbName,
      );
      if (!mounted) return;

      // Only pending: accepted == '' or null
      final filtered = list.where((h) {
        final a = (h["accepted"] ?? "").toString().trim().toLowerCase();
        return a.isEmpty;
      }).toList();

      setState(() => pending = filtered);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Failed to load requests: $e")),
      );
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  String _safe(dynamic v) => (v ?? "").toString().trim();

  DateTime? _tryParseDate(dynamic v) {
    if (v == null) return null;
    final s = v.toString().trim();
    if (s.isEmpty) return null;

    // "dd/MM/yyyy (Day)" or "dd/MM/yyyy"
    final m = RegExp(r"^(\d{2})\/(\d{2})\/(\d{4})").firstMatch(s);
    if (m != null) {
      final dd = int.parse(m.group(1)!);
      final mm = int.parse(m.group(2)!);
      final yy = int.parse(m.group(3)!);
      return DateTime(yy, mm, dd);
    }

    // ISO / "yyyy-MM-dd ..."
    try {
      return DateTime.parse(s);
    } catch (_) {
      try {
        return DateFormat("yyyy-MM-dd HH:mm:ss").parse(s);
      } catch (_) {
        return null;
      }
    }
  }

  String _formatRange(dynamic start, dynamic end) {
    final s = _safe(start);
    final e = _safe(end);

    // If DB already stores "dd/MM/yyyy (Day)"
    if (s.contains("/") && s.contains("(") && e.contains("/") && e.contains("(")) {
      return "$s  →  $e";
    }

    final ds = _tryParseDate(start);
    final de = _tryParseDate(end);
    if (ds == null || de == null) return "$s  →  $e";

    return "${DateFormat("dd/MM/yyyy (EEE)").format(ds)}  →  ${DateFormat("dd/MM/yyyy (EEE)").format(de)}";
  }

  // 🔔 FUNZIONE PER TROVARE EMAIL DALLA TABELLA EMPLOYEES
  Future<String?> _findEmployeeEmail(String name, String lastName) async {
    try {
      print('🔍 Cercando email per: $name $lastName');
      
      // Prima cerca tutti gli employees
      final employees = await _rotaService.fetchAllEmployees(
        db: widget.selectedDb.dbName,
      );
      
      // Cerca per nome e cognome (case insensitive)
      final matchingEmployee = employees.firstWhere(
        (emp) => 
          emp['name']?.toString().toLowerCase() == name.toLowerCase() &&
          emp['lastName']?.toString().toLowerCase() == lastName.toLowerCase(),
        orElse: () => <String, dynamic>{},
      );
      
      if (matchingEmployee.isNotEmpty) {
        final email = matchingEmployee['email']?.toString();
        print('✅ Trovata email: $email per $name $lastName');
        return email;
      }
      
      print('⚠️ Nessuna email trovata per $name $lastName');
      return null;
    } catch (e) {
      print('❌ Errore nella ricerca email: $e');
      return null;
    }
  }

  // 🔔 FUNZIONE PER INVIARE NOTIFICA ALL'EMPLOYEE
  Future<void> _sendDecisionNotification({
    required String employeeEmail,
    required String decision, // "approved" or "declined"
    required String employeeName,
    required String startDate,
    required String endDate,
    String? managerMessage,
  }) async {
    try {
      print('📱 Sending $decision notification to $employeeEmail');
      
      // Se l'email è placeholder, non inviare la notifica
      if (employeeEmail == 'placeholder@email.com') {
        print('⚠️ Skipping notification for placeholder email');
        return;
      }
      
      // Formatta le date in formato leggibile
      final formattedStart = _formatDateForNotification(startDate);
      final formattedEnd = _formatDateForNotification(endDate);
      final dateRange = formattedStart == formattedEnd 
          ? formattedStart 
          : '$formattedStart - $formattedEnd';
      
      // Crea il titolo e il messaggio in base alla decisione
      String title;
      String message;
      
      if (decision == 'approved') {
        title = '✅ Holiday Approved';
        message = 'Your holiday request for $dateRange has been approved';
      } else {
        title = '❌ Holiday Declined';
        message = 'Your holiday request for $dateRange has been declined';
      }
      
      // Aggiungi il messaggio del manager se presente
      if (managerMessage != null && managerMessage.isNotEmpty) {
        message += '\n\nManager message: $managerMessage';
      }

      // Invia notifica push all'employee
      await NotificationsService.sendPushNotification(
        db: widget.selectedDb.dbName,
        targetEmail: employeeEmail,
        targetRole: 'EMPLOYEE',
        title: title,
        message: message,
        type: 'HOLIDAY',
      );
      
      print('✅ Decision notification sent to $employeeEmail');
    } catch (e) {
      print('❌ Error sending decision notification: $e');
    }
  }

  String _formatDateForNotification(String dateStr) {
    try {
      final date = _tryParseDate(dateStr);
      if (date != null) {
        return DateFormat('dd/MM/yyyy').format(date);
      }
    } catch (e) {
      print('Error formatting date: $e');
    }
    return dateStr;
  }

  Future<void> _approve(int holidayId, String employeeName, String startDate, String endDate) async {
    // Separa nome e cognome
    final nameParts = employeeName.split(' ');
    final firstName = nameParts.isNotEmpty ? nameParts[0] : '';
    final lastName = nameParts.length > 1 ? nameParts.sublist(1).join(' ') : '';
    
    // Cerca l'email
    final employeeEmail = await _findEmployeeEmail(firstName, lastName);
    
    if (employeeEmail == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Could not find email for $employeeName"),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }
    
    await _decide(
      holidayId: holidayId,
      decision: "approve",
      reason: "",
      employeeEmail: employeeEmail,
      employeeName: employeeName,
      startDate: startDate,
      endDate: endDate,
    );
  }

  Future<void> _promptDecline(int holidayId, String employeeName, String startDate, String endDate) async {
    // Separa nome e cognome
    final nameParts = employeeName.split(' ');
    final firstName = nameParts.isNotEmpty ? nameParts[0] : '';
    final lastName = nameParts.length > 1 ? nameParts.sublist(1).join(' ') : '';
    
    // Cerca l'email
    final employeeEmail = await _findEmployeeEmail(firstName, lastName);
    
    if (employeeEmail == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Could not find email for $employeeName"),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }
    
    final controller = TextEditingController();

    final reason = await showDialog<String?>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: const Color(0xFF172A45),
          title: const Text(
            "Decline Holiday Request",
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                "Optional: add a reason (saved in notes).",
                style: TextStyle(color: Colors.white.withOpacity(0.7)),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                maxLines: 3,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  hintText: "Reason (optional)",
                  hintStyle: TextStyle(color: Colors.white.withOpacity(0.4)),
                  filled: true,
                  fillColor: Colors.white.withOpacity(0.06),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: Colors.white.withOpacity(0.12)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: Colors.white.withOpacity(0.12)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Color(0xFF4CC9F0)),
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, null),
              child: const Text("Cancel", style: TextStyle(color: Color(0xFF4CC9F0))),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, controller.text.trim()),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.redAccent,
                foregroundColor: Colors.white,
              ),
              child: const Text("Decline"),
            ),
          ],
        );
      },
    );

    if (reason == null) return; // cancelled

    await _decide(
      holidayId: holidayId,
      decision: "decline",
      reason: reason,
      employeeEmail: employeeEmail,
      employeeName: employeeName,
      startDate: startDate,
      endDate: endDate,
    );
  }

  Future<void> _decide({
    required int holidayId,
    required String decision, // "approve" | "decline"
    required String reason,
    required String employeeEmail,
    required String employeeName,
    required String startDate,
    required String endDate,
  }) async {
    if (acting) return;

    final actorEmail = (Session.email ?? "").trim();
    if (actorEmail.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("No session email found. Please login again.")),
      );
      return;
    }

    setState(() => acting = true);

    try {
      await HolidaysService.decide(
        db: widget.selectedDb.dbName,
        id: holidayId,
        decision: decision,
        actorEmail: actorEmail,
        reason: reason,
      );

      if (!mounted) return;
      
      // 🔔 DOPO IL SUCCESSO, INVIA NOTIFICA ALL'EMPLOYEE
      await _sendDecisionNotification(
        employeeEmail: employeeEmail,
        decision: decision == "approve" ? "approved" : "declined",
        employeeName: employeeName,
        startDate: startDate,
        endDate: endDate,
        managerMessage: reason.isNotEmpty ? reason : null,
      );

      setState(() {
        pending.removeWhere((h) => h["id"] == holidayId);
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(decision == "approve" ? "Approved" : "Declined")),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Failed: $e")),
      );
    } finally {
      if (mounted) setState(() => acting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_isApprover) {
      return Scaffold(
        backgroundColor: const Color(0xFF0A192F),
        appBar: AppBar(
          backgroundColor: const Color(0xFF172A45),
          title: const Text("Holiday Requests", style: TextStyle(color: Colors.white)),
        ),
        body: Center(
          child: Text(
            "You don't have permission to access this page.",
            style: TextStyle(color: Colors.white.withOpacity(0.7)),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFF0A192F),
      appBar: AppBar(
        backgroundColor: const Color(0xFF172A45),
        elevation: 0,
        title: Text(
          pending.isEmpty ? "Holiday Requests" : "Holiday Requests (${pending.length})",
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Color(0xFF4CC9F0)),
            onPressed: _loadPending,
          ),
        ],
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF4CC9F0)))
          : pending.isEmpty
              ? Center(
                  child: Text(
                    "No pending requests",
                    style: TextStyle(color: Colors.white.withOpacity(0.7)),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: pending.length,
                  itemBuilder: (context, i) {
                    final h = pending[i];

                    final id = h["id"];
                    final name = "${_safe(h["name"])} ${_safe(h["lastName"])}".trim();
                    final range = _formatRange(h["startDate"], h["endDate"]);
                    final days = _safe(h["days"]);
                    final type = _safe(h["type"]);
                    final notes = _safe(h["notes"]);
                    final startDate = _safe(h["startDate"]);
                    final endDate = _safe(h["endDate"]);

                    return Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: const Color(0xFF172A45).withOpacity(0.95),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: const Color(0xFF4CC9F0).withOpacity(0.15)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            name.isEmpty ? "Holiday Request" : name,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(range, style: TextStyle(color: Colors.white.withOpacity(0.8))),
                          const SizedBox(height: 6),
                          if (days.isNotEmpty)
                            Text("Days: $days",
                                style: TextStyle(color: Colors.white.withOpacity(0.65))),
                          if (type.isNotEmpty)
                            Text("Type: $type",
                                style: TextStyle(color: Colors.white.withOpacity(0.65))),
                          if (notes.isNotEmpty) ...[
                            const SizedBox(height: 10),
                            Text("Employee notes: $notes",
                                style: TextStyle(color: Colors.white.withOpacity(0.65))),
                          ],
                          const SizedBox(height: 14),
                          Row(
                            children: [
                              Expanded(
                                child: ElevatedButton.icon(
                                  onPressed: (id is int && !acting) 
                                      ? () => _approve(id, name, startDate, endDate) 
                                      : null,
                                  icon: const Icon(Icons.check, color: Colors.white),
                                  label: const Text("Approve", style: TextStyle(color: Colors.white)),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFF4ADE80),
                                    foregroundColor: Colors.white,
                                    minimumSize: const Size(double.infinity, 46),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: ElevatedButton.icon(
                                  onPressed: (id is int && !acting) 
                                      ? () => _promptDecline(id, name, startDate, endDate) 
                                      : null,
                                  icon: const Icon(Icons.close, color: Colors.white),
                                  label: const Text("Decline", style: TextStyle(color: Colors.white)),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.redAccent,
                                    foregroundColor: Colors.white,
                                    minimumSize: const Size(double.infinity, 46),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    );
                  },
                ),
    );
  }
}