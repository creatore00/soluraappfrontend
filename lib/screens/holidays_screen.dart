// ==================================
// FRONTEND: holidays_screen.dart (FULL)
// - Builds year dropdown: prev/current/next based on backend current year
// - Fetches holidays for selected year via yearStart/yearEnd query params
// - Default tab = Approved
// - Fixes summary card overflow for small screens
// ==================================
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../models/database_access.dart';
import '../services/auth_service.dart';
import 'hours_summary_screen.dart';
import 'all_rota_screen.dart';
import 'earnings_screen.dart';
import 'package:intl/intl.dart';

class HolidaysScreen extends StatefulWidget {
  final String email;
  final DatabaseAccess selectedDb;

  const HolidaysScreen({
    super.key,
    required this.email,
    required this.selectedDb,
  });

  @override
  State<HolidaysScreen> createState() => _HolidaysScreenState();
}

class HolidayItem {
  final String startDate;
  final String endDate;
  final String requestDate;
  final int days;
  final String who;
  final String notes;
  final String status; // Pending / Approved (Paid/Unpaid) / Declined
  final String type; // Paid / Unpaid

  HolidayItem({
    required this.startDate,
    required this.endDate,
    required this.requestDate,
    required this.days,
    required this.who,
    required this.notes,
    required this.status,
    required this.type,
  });

  factory HolidayItem.fromJson(Map<String, dynamic> json) {
    return HolidayItem(
      startDate: (json['startDate'] ?? '').toString(),
      endDate: (json['endDate'] ?? '').toString(),
      requestDate: (json['requestDate'] ?? '').toString(),
      days: int.tryParse((json['days'] ?? 0).toString()) ?? 0,
      who: (json['who'] ?? '').toString(),
      notes: (json['notes'] ?? '').toString(),
      status: (json['status'] ?? 'Pending').toString(),
      type: (json['type'] ?? 'Paid').toString(),
    );
  }
}

class HolidaySummary {
  final num allowanceDays;
  final num accruedDays;
  final num takenPaidDays;
  final num takenUnpaidDays;
  final num pendingPaidDays;
  final num pendingUnpaidDays;
  final num declinedDays;
  final num remainingYearDays;
  final num availableNowDays;

  HolidaySummary({
    required this.allowanceDays,
    required this.accruedDays,
    required this.takenPaidDays,
    required this.takenUnpaidDays,
    required this.pendingPaidDays,
    required this.pendingUnpaidDays,
    required this.declinedDays,
    required this.remainingYearDays,
    required this.availableNowDays,
  });

  factory HolidaySummary.fromJson(Map<String, dynamic> json) {
    num n(dynamic x) => num.tryParse((x ?? 0).toString()) ?? 0;
    return HolidaySummary(
      allowanceDays: n(json['allowanceDays']),
      accruedDays: n(json['accruedDays']),
      takenPaidDays: n(json['takenPaidDays']),
      takenUnpaidDays: n(json['takenUnpaidDays']),
      pendingPaidDays: n(json['pendingPaidDays']),
      pendingUnpaidDays: n(json['pendingUnpaidDays']),
      declinedDays: n(json['declinedDays']),
      remainingYearDays: n(json['remainingYearDays']),
      availableNowDays: n(json['availableNowDays']),
    );
  }
}

class YearOption {
  final String start; // yyyy-mm-dd
  final String end;   // yyyy-mm-dd
  final String key;   // "yyyy-mm-dd → yyyy-mm-dd"

  YearOption({required this.start, required this.end}) : key = "$start → $end";
}

class _HolidaysScreenState extends State<HolidaysScreen> with SingleTickerProviderStateMixin {
  bool loading = true;
  bool error = false;
  String errorMessage = '';

  // 3-year options (prev/current/next)
  List<YearOption> _yearOptions = [];
  YearOption? _selectedYear;

  HolidaySummary? _summary;
  List<HolidayItem> _approved = [];
  List<HolidayItem> _pending = [];
  List<HolidayItem> _declined = [];

  late TabController _tabs;

  @override
  void initState() {
    super.initState();
    // default tab = Approved (index 1)
    _tabs = TabController(length: 3, vsync: this, initialIndex: 1);
    _fetchInitialCurrentYear();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  // ---------------- Date helpers ----------------
  // Year window is yyyy-mm-dd to yyyy-mm-dd
  DateTime _parseYMD(String ymd) {
    final parts = ymd.split('-');
    if (parts.length != 3) return DateTime.now();
    final y = int.tryParse(parts[0]) ?? 1970;
    final m = int.tryParse(parts[1]) ?? 1;
    final d = int.tryParse(parts[2]) ?? 1;
    return DateTime(y, m, d);
  }

  // Build prev/current/next by shifting both start/end by +/- 1 year
  YearOption _shiftYear(YearOption base, int deltaYears) {
    final s = _parseYMD(base.start);
    final e = _parseYMD(base.end);
    final s2 = DateTime(s.year + deltaYears, s.month, s.day);
    final e2 = DateTime(e.year + deltaYears, e.month, e.day);

    String fmt(DateTime d) => DateFormat("yyyy-MM-dd").format(d);
    return YearOption(start: fmt(s2), end: fmt(e2));
  }

  // ---------------- Fetch logic ----------------
  Future<void> _fetchInitialCurrentYear() async {
    // call /holidays without yearStart/yearEnd to get currentYear from backend
    setState(() {
      loading = true;
      error = false;
      errorMessage = '';
    });

    try {
      final uri = Uri.parse("${AuthService.baseUrl}/holidays").replace(
        queryParameters: {
          'db': widget.selectedDb.dbName,
          'email': widget.email,
        },
      );

      final response = await http.get(uri);

      if (response.statusCode != 200) {
        throw Exception("Failed: ${response.statusCode} - ${response.body}");
      }

      final body = response.body.trim();
      if (body.startsWith("<!DOCTYPE html>")) {
        throw Exception("Server returned HTML. Check backend route mapping for /holidays.");
      }

      final data = jsonDecode(body);
      if (data["success"] != true) {
        throw Exception(data["message"] ?? "Failed to fetch holidays");
      }

      final year = data["year"];
      if (year == null) {
        // no HolidayYearSettings row matches today
        if (!mounted) return;
        setState(() {
          _yearOptions = [];
          _selectedYear = null;
          _summary = null;
          _approved = [];
          _pending = [];
          _declined = [];
          loading = false;
        });
        return;
      }

      final current = YearOption(
        start: (year["start"] ?? "").toString(),
        end: (year["end"] ?? "").toString(),
      );

      final prev = _shiftYear(current, -1);
      final next = _shiftYear(current, 1);

      _yearOptions = [prev, current, next];
      _selectedYear = current;

      // Now fetch for current year explicitly (so same parsing path)
      await _fetchForYear(current);

      if (!mounted) return;
      setState(() => loading = false);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        loading = false;
        error = true;
        errorMessage = e.toString();
      });
    }
  }

  Future<void> _fetchForYear(YearOption year) async {
    setState(() {
      loading = true;
      error = false;
      errorMessage = '';
    });

    try {
      final uri = Uri.parse("${AuthService.baseUrl}/holidays").replace(
        queryParameters: {
          'db': widget.selectedDb.dbName,
          'email': widget.email,
          'yearStart': year.start,
          'yearEnd': year.end,
        },
      );

      final response = await http.get(uri);

      if (response.statusCode != 200) {
        throw Exception("Failed: ${response.statusCode} - ${response.body}");
      }

      final body = response.body.trim();
      if (body.startsWith("<!DOCTYPE html>")) {
        throw Exception("Server returned HTML. Check backend route mapping for /holidays.");
      }

      final data = jsonDecode(body);
      if (data["success"] != true) {
        throw Exception(data["message"] ?? "Failed to fetch holidays");
      }

      final summaryRaw = data["summary"];
      final approvedRaw = (data["approvedHolidays"] ?? []) as List;
      final pendingRaw = (data["pendingHolidays"] ?? []) as List;
      final declinedRaw = (data["declinedHolidays"] ?? []) as List;

      final summary = summaryRaw == null ? null : HolidaySummary.fromJson(summaryRaw as Map<String, dynamic>);

      final approved = approvedRaw.map((e) => HolidayItem.fromJson(e as Map<String, dynamic>)).toList();
      final pending = pendingRaw.map((e) => HolidayItem.fromJson(e as Map<String, dynamic>)).toList();
      final declined = declinedRaw.map((e) => HolidayItem.fromJson(e as Map<String, dynamic>)).toList();

      if (!mounted) return;
      setState(() {
        _summary = summary;
        _approved = approved;
        _pending = pending;
        _declined = declined;
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

  // ---------------- UI helpers ----------------
  Color _statusColor(String status) {
    final s = status.toLowerCase();
    if (s.startsWith("approved")) return Colors.green;
    if (s == "declined") return Colors.red;
    return Colors.orange;
  }

  String _fmt(num v, {int dp = 2}) => v.toStringAsFixed(dp);

  Widget _tightValue(String text, {double max = 18}) {
    // prevents overflow in cards
    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.centerLeft,
      child: Text(
        text,
        maxLines: 1,
        style: TextStyle(color: Colors.white, fontSize: max, fontWeight: FontWeight.bold),
      ),
    );
  }

  Widget _summaryCardMinimal({
  required String title,
  required String value,
  required IconData icon,
  required Color accent,
}) {
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
    decoration: BoxDecoration(
      color: Colors.white.withOpacity(0.04),
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: Colors.white.withOpacity(0.08)),
    ),
    child: Row(
      children: [
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: accent.withOpacity(0.18),
            border: Border.all(color: accent.withOpacity(0.35)),
          ),
          child: Icon(icon, color: accent, size: 20),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Colors.white.withOpacity(0.7),
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  value,
                  maxLines: 1,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}


  Widget _holidayCard(HolidayItem h) {
    final badgeColor = _statusColor(h.status);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.03),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  "${h.startDate}  →  ${h.endDate}",
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800),
                ),
              ),
              const SizedBox(width: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: badgeColor.withOpacity(0.18),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: badgeColor.withOpacity(0.35)),
                ),
                child: Text(
                  h.status,
                  style: TextStyle(color: badgeColor, fontSize: 12, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            "${h.days} day${h.days == 1 ? '' : 's'} • ${h.type}",
            style: TextStyle(color: Colors.white.withOpacity(0.75)),
          ),
          if (h.requestDate.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text("Requested: ${h.requestDate}",
                style: TextStyle(color: Colors.white.withOpacity(0.55), fontSize: 12)),
          ],
          if (h.who.trim().isNotEmpty) ...[
            const SizedBox(height: 4),
            Text("Approved by: ${h.who}",
                style: TextStyle(color: Colors.white.withOpacity(0.55), fontSize: 12)),
          ],
          if (h.notes.trim().isNotEmpty) ...[
            const SizedBox(height: 8),
            Text("Notes: ${h.notes}", style: TextStyle(color: Colors.white.withOpacity(0.65))),
          ],
        ],
      ),
    );
  }

  Widget _emptyState(String text) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Center(child: Text(text, style: TextStyle(color: Colors.white.withOpacity(0.6)))),
    );
  }

  // ---------------- Request Holiday dialog ----------------
  Future<void> _showRequestHolidayDialog() async {
    DateTime? start;
    DateTime? end;

    final notesController = TextEditingController();
    String type = "Paid";

    String format(DateTime d) => DateFormat("yyyy-MM-dd").format(d);

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: const Color(0xFF172A45),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: const Text("Request Holiday", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    DropdownButtonFormField<String>(
                      value: type,
                      dropdownColor: const Color(0xFF172A45),
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        labelText: "Type",
                        labelStyle: TextStyle(color: Colors.white.withOpacity(0.7)),
                        enabledBorder: OutlineInputBorder(
                          borderSide: BorderSide(color: Colors.white.withOpacity(0.15)),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderSide: const BorderSide(color: Color(0xFF4CC9F0)),
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      items: const [
                        DropdownMenuItem(value: "Paid", child: Text("Paid")),
                        DropdownMenuItem(value: "Unpaid", child: Text("Unpaid")),
                      ],
                      onChanged: (v) => setDialogState(() => type = v ?? "Paid"),
                    ),
                    const SizedBox(height: 14),
                    InkWell(
                      onTap: () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: DateTime.now(),
                          firstDate: DateTime.now(),
                          lastDate: DateTime.now().add(const Duration(days: 365)),
                        );
                        if (picked != null) {
                          setDialogState(() => start = picked);
                          if (end != null && end!.isBefore(start!)) setDialogState(() => end = null);
                        }
                      },
                      child: _dateField(label: "Start date", value: start == null ? "Select date" : format(start!)),
                    ),
                    const SizedBox(height: 12),
                    InkWell(
                      onTap: start == null
                          ? null
                          : () async {
                              final picked = await showDatePicker(
                                context: context,
                                initialDate: start!,
                                firstDate: start!,
                                lastDate: DateTime.now().add(const Duration(days: 365)),
                              );
                              if (picked != null) setDialogState(() => end = picked);
                            },
                      child: _dateField(
                        label: "End date",
                        value: end == null ? "Select date" : format(end!),
                        disabled: start == null,
                      ),
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: notesController,
                      maxLines: 3,
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        labelText: "Notes (optional)",
                        labelStyle: TextStyle(color: Colors.white.withOpacity(0.7)),
                        enabledBorder: OutlineInputBorder(
                          borderSide: BorderSide(color: Colors.white.withOpacity(0.15)),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderSide: const BorderSide(color: Color(0xFF4CC9F0)),
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: Text("Cancel", style: TextStyle(color: Colors.white.withOpacity(0.7))),
                ),
                ElevatedButton(
                  onPressed: () async {
                    if (start == null || end == null) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text("Please select start and end date")),
                      );
                      return;
                    }
                    Navigator.pop(ctx);
                    await _submitHolidayRequest(
                      startDate: format(start!),
                      endDate: format(end!),
                      notes: notesController.text.trim(),
                      type: type,
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF4CC9F0),
                    foregroundColor: Colors.white,
                  ),
                  child: const Text("Submit"),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _dateField({required String label, required String value, bool disabled = false}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      decoration: BoxDecoration(
        color: disabled ? Colors.white.withOpacity(0.03) : Colors.white.withOpacity(0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withOpacity(0.12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 12)),
          const SizedBox(height: 6),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: disabled ? Colors.white.withOpacity(0.35) : Colors.white,
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _submitHolidayRequest({
    required String startDate,
    required String endDate,
    required String notes,
    required String type,
  }) async {
    try {
      setState(() {
        loading = true;
        error = false;
      });

      final uri = Uri.parse("${AuthService.baseUrl}/holidays/request");

      final payload = {
        "db": widget.selectedDb.dbName,
        "email": widget.email,
        "startDate": startDate,
        "endDate": endDate,
        "notes": notes,
        "type": type,
      };

      final response = await http.post(
        uri,
        headers: {"Content-Type": "application/json"},
        body: jsonEncode(payload),
      );

      final body = response.body.trim();
      if (body.startsWith("<!DOCTYPE html>")) {
        throw Exception("Server returned HTML. Check /holidays/request route mapping.");
      }

      final data = jsonDecode(body);

      if (response.statusCode != 200 || data["success"] != true) {
        throw Exception(data["message"] ?? "Failed to submit holiday request");
      }

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Holiday request submitted successfully")),
      );

      // refresh currently selected year
      final y = _selectedYear;
      if (y != null) {
        await _fetchForYear(y);
      } else {
        await _fetchInitialCurrentYear();
      }
    } catch (e) {
      if (!mounted) return;

      setState(() {
        loading = false;
        error = true;
        errorMessage = e.toString();
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Error: $e")),
      );
    }
  }

  // ---------------- Build ----------------
@override
Widget build(BuildContext context) {
  final y = _selectedYear;
  final s = _summary;

  return Scaffold(
    backgroundColor: const Color(0xFF0A192F),
    appBar: AppBar(
      backgroundColor: const Color(0xFF172A45),
      elevation: 0,
      title: const Text(
        "Holidays",
        style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white),
      ),
      leading: IconButton(
        icon: const Icon(Icons.arrow_back, color: Color(0xFF4CC9F0)),
        onPressed: () => Navigator.pop(context),
      ),
      actions: [
        IconButton(
          tooltip: "Request Holiday",
          icon: const Icon(Icons.add, color: Color(0xFF4CC9F0)),
          onPressed: _showRequestHolidayDialog,
        ),
        IconButton(
          tooltip: "Refresh",
          icon: const Icon(Icons.refresh, color: Color(0xFF4CC9F0)),
          onPressed: () async {
            final yr = _selectedYear;
            if (yr != null) await _fetchForYear(yr);
            else await _fetchInitialCurrentYear();
          },
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
                    const SizedBox(height: 16),
                    Text("Loading holidays...", style: TextStyle(color: Colors.white.withOpacity(0.7))),
                  ],
                ),
              )
            : error
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.error_outline, size: 64, color: Colors.red.withOpacity(0.7)),
                          const SizedBox(height: 16),
                          Text(
                            "Error loading holidays",
                            style: TextStyle(color: Colors.white.withOpacity(0.85), fontSize: 18),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            errorMessage,
                            style: TextStyle(color: Colors.white.withOpacity(0.6)),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 16),
                          ElevatedButton(
                            onPressed: _fetchInitialCurrentYear,
                            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF4CC9F0)),
                            child: const Text("Try Again"),
                          ),
                        ],
                      ),
                    ),
                  )
                : (_yearOptions.isEmpty || y == null)
                    ? _emptyState(
                        "No current holiday year found.\nAdd a row in HolidayYearSettings where today is inside it.",
                      )
                    : Column(
                        children: [
                          // Top section scrolls if needed + bottom list stays fixed
                          Expanded(
                            child: Column(
                              children: [
                                // Scrollable header section (selector + summary + tabs header)
                                SingleChildScrollView(
                                  padding: const EdgeInsets.only(bottom: 10),
                                  child: Column(
                                    children: [
                                      // Year selector
                                      Container(
                                        padding: const EdgeInsets.all(14),
                                        decoration: BoxDecoration(
                                          color: Colors.white.withOpacity(0.03),
                                          borderRadius: BorderRadius.circular(16),
                                          border: Border.all(color: Colors.white.withOpacity(0.1)),
                                        ),
                                        child: DropdownButtonFormField<String>(
                                          value: y.key,
                                          dropdownColor: const Color(0xFF0A192F),
                                          decoration: InputDecoration(
                                            labelText: "Holiday Year",
                                            labelStyle: TextStyle(color: Colors.white.withOpacity(0.7)),
                                            enabledBorder: OutlineInputBorder(
                                              borderRadius: BorderRadius.circular(12),
                                              borderSide: BorderSide(color: Colors.white.withOpacity(0.15)),
                                            ),
                                            focusedBorder: OutlineInputBorder(
                                              borderRadius: BorderRadius.circular(12),
                                              borderSide: const BorderSide(color: Color(0xFF4CC9F0)),
                                            ),
                                          ),
                                          style: const TextStyle(color: Colors.white),
                                          items: _yearOptions
                                              .map((opt) => DropdownMenuItem(
                                                    value: opt.key,
                                                    child: Text(opt.key),
                                                  ))
                                              .toList(),
                                          onChanged: (v) async {
                                            if (v == null) return;
                                            final opt = _yearOptions.firstWhere((o) => o.key == v);
                                            setState(() => _selectedYear = opt);
                                            await _fetchForYear(opt);
                                          },
                                        ),
                                      ),

                                      const SizedBox(height: 12),

                                      // Summary cards (2 per row)
                                      if (s != null)
                                        GridView.count(
                                          shrinkWrap: true,
                                          physics: const NeverScrollableScrollPhysics(),
                                          crossAxisCount: 2,
                                          mainAxisSpacing: 10,
                                          crossAxisSpacing: 10,
                                          childAspectRatio: 3.05, // slightly safer
                                          children: [
                                            _summaryCardMinimal(
                                              title: "Allowance",
                                              value: "${_fmt(s.allowanceDays, dp: 0)}",
                                              icon: Icons.verified,
                                              accent: const Color(0xFF4CC9F0),
                                            ),
                                            _summaryCardMinimal(
                                              title: "Accrued",
                                              value: _fmt(s.accruedDays),
                                              icon: Icons.timeline,
                                              accent: const Color(0xFF4ADE80),
                                            ),
                                            _summaryCardMinimal(
                                              title: "Taken",
                                              value: "${_fmt(s.takenPaidDays, dp: 0)}",
                                              icon: Icons.check_circle,
                                              accent: Colors.green,
                                            ),
                                            _summaryCardMinimal(
                                              title: "Pending",
                                              value: "${_fmt(s.pendingPaidDays, dp: 0)}",
                                              icon: Icons.hourglass_top,
                                              accent: Colors.orange,
                                            ),
                                            _summaryCardMinimal(
                                              title: "Remaining",
                                              value: _fmt(s.remainingYearDays),
                                              icon: Icons.savings,
                                              accent: const Color(0xFF4CC9F0),
                                            ),
                                            _summaryCardMinimal(
                                              title: "Available",
                                              value: _fmt(s.availableNowDays),
                                              icon: Icons.lock_open,
                                              accent: const Color(0xFF4ADE80),
                                            ),
                                          ],
                                        ),

                                      const SizedBox(height: 12),

                                      // Tabs header
                                      Container(
                                        decoration: BoxDecoration(
                                          color: const Color(0xFF172A45),
                                          borderRadius: BorderRadius.circular(14),
                                          border: Border.all(color: Colors.white.withOpacity(0.08)),
                                        ),
                                        child: TabBar(
                                          controller: _tabs,
                                          indicatorColor: const Color(0xFF4CC9F0),
                                          labelColor: Colors.white,
                                          unselectedLabelColor: Colors.white.withOpacity(0.6),
                                          tabs: const [
                                            Tab(text: "Pending"),
                                            Tab(text: "Approved"),
                                            Tab(text: "Declined"),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),

                                const SizedBox(height: 10),

                                // Fixed list area
                                Expanded(
                                  child: TabBarView(
                                    controller: _tabs,
                                    children: [
                                      _buildList(_pending, emptyText: "No pending holidays in this year."),
                                      _buildList(_approved, emptyText: "No approved holidays in this year."),
                                      _buildList(_declined, emptyText: "No declined holidays in this year."),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
      ),
    ),
    bottomNavigationBar: _buildBottomNavigationBar(),
  );
}


  Widget _buildList(List<HolidayItem> list, {required String emptyText}) {
    if (list.isEmpty) return _emptyState(emptyText);
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: list.length,
      itemBuilder: (_, i) => _holidayCard(list[i]),
    );
  }

  // ---------- Bottom nav ----------
  Widget _buildBottomNavigationBar() {
    return Container(
      height: 70,
      decoration: BoxDecoration(
        color: const Color(0xFF172A45),
        border: Border(top: BorderSide(color: Colors.white.withOpacity(0.1), width: 1)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildNavButton(
            icon: Icons.access_time,
            label: 'Hours',
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => HoursSummaryScreen(
                    email: widget.email,
                    selectedDb: widget.selectedDb,
                    employeeName: '',
                    employeeLastName: '',
                  ),
                ),
              );
            },
          ),
          _buildNavButton(
            icon: Icons.calendar_today,
            label: 'Rota',
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => AllRotaScreen(
                    email: widget.email,
                    selectedDb: widget.selectedDb,
                  ),
                ),
              );
            },
          ),
          _buildHomeButton(),
          _buildActiveNavButton(icon: Icons.beach_access, label: 'Holidays'),
          _buildNavButton(
            icon: Icons.attach_money,
            label: 'Earnings',
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => EarningsScreen(
                    email: widget.email,
                    selectedDb: widget.selectedDb,
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildNavButton({required IconData icon, required String label, required VoidCallback onTap}) {
    return Expanded(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          child: SizedBox(
            height: 70,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, color: Colors.white.withOpacity(0.7), size: 24),
                const SizedBox(height: 4),
                Text(label, style: TextStyle(fontSize: 12, color: Colors.white.withOpacity(0.7))),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildActiveNavButton({required IconData icon, required String label}) {
    return Expanded(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0xFF4CC9F0).withOpacity(0.2),
            ),
            child: Icon(icon, color: const Color(0xFF4CC9F0), size: 24),
          ),
          const SizedBox(height: 4),
          Text(label, style: const TextStyle(fontSize: 12, color: Color(0xFF4CC9F0), fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _buildHomeButton() {
    return Expanded(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const LinearGradient(colors: [Color(0xFF4CC9F0), Color(0xFF1E3A5F)]),
              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.3), blurRadius: 8, offset: const Offset(0, 4))],
            ),
            child: IconButton(
              icon: const Icon(Icons.home, size: 28),
              color: Colors.white,
              onPressed: () => Navigator.of(context).popUntil((route) => route.isFirst),
            ),
          ),
          const SizedBox(height: 2),
          Text('Home', style: TextStyle(fontSize: 12, color: Colors.white.withOpacity(0.7))),
        ],
      ),
    );
  }
}
