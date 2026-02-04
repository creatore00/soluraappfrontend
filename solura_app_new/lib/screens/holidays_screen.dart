import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
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

class Holiday {
  final String name;
  final String lastName;
  final String startDate;
  final String endDate;
  final String requestDate;
  final int days;
  final String accepted;
  final String who;
  final String notes;

  Holiday({
    required this.name,
    required this.lastName,
    required this.startDate,
    required this.endDate,
    required this.requestDate,
    required this.days,
    required this.accepted,
    required this.who,
    required this.notes,
  });

  factory Holiday.fromJson(Map<String, dynamic> json) {
    return Holiday(
      name: (json['name'] ?? '').toString(),
      lastName: (json['lastName'] ?? '').toString(),
      startDate: (json['startDate'] ?? '').toString(),
      endDate: (json['endDate'] ?? '').toString(),
      requestDate: (json['requestDate'] ?? '').toString(),
      days: json['days'] != null ? int.tryParse(json['days'].toString()) ?? 0 : 0,
      accepted: (json['accepted'] ?? '').toString(),
      who: (json['who'] ?? '').toString(),
      notes: (json['notes'] ?? '').toString(),
    );
  }
}

class _HolidaysScreenState extends State<HolidaysScreen> {
  bool loading = true;
  bool error = false;
  String errorMessage = '';

  String holidayYearLabel = "";

  List<Holiday> pendingHolidays = [];
  List<Holiday> currentApproved = [];
  Map<String, List<Holiday>> pastByYear = {};

  @override
  void initState() {
    super.initState();
    fetchHolidays();
  }

  Future<void> fetchHolidays() async {
    if (!mounted) return;

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

      final data = jsonDecode(response.body);
      if (data["success"] != true) {
        throw Exception(data["message"] ?? "Failed to fetch holidays");
      }

      final hy = data["holidayYear"];
      final start = (hy?["start"] ?? "").toString();
      final end = (hy?["end"] ?? "").toString();

      final List<dynamic> pendingList = data["pendingHolidays"] ?? [];
      final List<dynamic> currentList = data["currentHolidays"] ?? [];
      final Map<String, dynamic> pastMap = (data["pastByYear"] ?? {}) as Map<String, dynamic>;

      final parsedPending = pendingList.map((x) => Holiday.fromJson(x)).toList();
      final parsedCurrent = currentList.map((x) => Holiday.fromJson(x)).toList();

      final Map<String, List<Holiday>> parsedPast = {};
      pastMap.forEach((year, list) {
        final l = (list as List).map((x) => Holiday.fromJson(x)).toList();
        parsedPast[year.toString()] = l;
      });

      // sort years desc (latest year first)
      final keys = parsedPast.keys.toList()..sort((a, b) => b.compareTo(a));
      final sortedPast = {for (final k in keys) k: parsedPast[k]!};

      if (!mounted) return;
      setState(() {
        holidayYearLabel = (start.isNotEmpty && end.isNotEmpty) ? "$start → $end" : "";
        pendingHolidays = parsedPending;
        currentApproved = parsedCurrent;
        pastByYear = sortedPast;

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
  Widget _sectionTitle(String title, {String? subtitle, IconData? icon}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
      ),
      child: Row(
        children: [
          if (icon != null) ...[
            Icon(icon, color: const Color(0xFF4CC9F0)),
            const SizedBox(width: 10),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                ),
                if (subtitle != null && subtitle.trim().isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: TextStyle(color: Colors.white.withOpacity(0.65), fontSize: 12),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
Widget _holidayCard(Holiday h, {required bool isPending}) {
  final acceptedLower = h.accepted.trim().toLowerCase();

  // Your rules:
  // Paid approved -> accepted == "true"
  // Unpaid approved -> accepted == "unpaid" AND who not empty
  // Pending -> isPending == true (from backend pending list)
  final isUnpaid = acceptedLower == "unpaid";
  final holidayType = isUnpaid ? "Unpaid" : "Paid";

  final isUnpaidApproved = !isPending && isUnpaid && h.who.trim().isNotEmpty;

  final badgeText = isPending
      ? "Pending"
      : isUnpaidApproved
          ? "Approved (Unpaid)"
          : "Approved (Paid)";

  final badgeColor = isPending
      ? Colors.orange
      : isUnpaidApproved
          ? Colors.blue
          : Colors.green;

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
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: badgeColor.withOpacity(0.18),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: badgeColor.withOpacity(0.35)),
              ),
              child: Text(
                badgeText,
                style: TextStyle(
                  color: badgeColor,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),

        Text(
          "${h.days} day${h.days == 1 ? '' : 's'} • $holidayType",
          style: TextStyle(color: Colors.white.withOpacity(0.7)),
        ),

        const SizedBox(height: 6),

        if (h.requestDate.isNotEmpty)
          Text(
            "Requested: ${h.requestDate}",
            style: TextStyle(color: Colors.white.withOpacity(0.55), fontSize: 12),
          ),

        // Only show "Approved by" for approved holidays where who is set
        if (!isPending && h.who.trim().isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              "Approved by: ${h.who}",
              style: TextStyle(color: Colors.white.withOpacity(0.55), fontSize: 12),
            ),
          ),

        if (h.notes.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(
            "Notes: ${h.notes}",
            style: TextStyle(color: Colors.white.withOpacity(0.6)),
          ),
        ],
      ],
    ),
  );
}



  Widget _holidayList(List<Holiday> list, {required bool isPending}) {
    if (list.isEmpty) {
      return Center(
        child: Text(
          isPending ? "No pending holidays." : "No holidays found.",
          style: TextStyle(color: Colors.white.withOpacity(0.6)),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: list.length,
      itemBuilder: (_, i) => _holidayCard(list[i], isPending: isPending),
    );
  }

  // ---------- Holiday request dialog (kept from your code) ----------
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
              title: const Text(
                "Request Holiday",
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
              ),
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
                      onChanged: (v) {
                        if (v == null) return;
                        setDialogState(() => type = v);
                      },
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
                          if (end != null && end!.isBefore(start!)) {
                            setDialogState(() => end = null);
                          }
                        }
                      },
                      child: _dateField(
                        label: "Start date",
                        value: start == null ? "Select date" : format(start!),
                      ),
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
                              if (picked != null) {
                                setDialogState(() => end = picked);
                              }
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
                  child: Text(
                    "Cancel",
                    style: TextStyle(color: Colors.white.withOpacity(0.7)),
                  ),
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

      final Map<String, dynamic> data = jsonDecode(response.body);

      if (response.statusCode != 200 || data["success"] != true) {
        throw Exception(data["message"] ?? "Failed to submit holiday request");
      }

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Holiday request submitted successfully")),
      );

      await fetchHolidays();
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

  // ---------- Build ----------
  @override
  Widget build(BuildContext context) {
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
          child: Column(
            children: [
              // Header card
              Container(
                padding: const EdgeInsets.all(16),
                margin: const EdgeInsets.only(bottom: 14),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      const Color(0xFF1E3A5F).withOpacity(0.8),
                      const Color(0xFF0A192F).withOpacity(0.9),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.white.withOpacity(0.1)),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 50,
                      height: 50,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(colors: [Color(0xFF4CC9F0), Color(0xFF1E3A5F)]),
                      ),
                      child: const Icon(Icons.beach_access, color: Colors.white),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            "Your Holidays",
                            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
                          ),
                          const SizedBox(height: 6),
                          if (holidayYearLabel.isNotEmpty)
                            Text(
                              "Business Holiday Year: $holidayYearLabel",
                              style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 12),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              // Request + Refresh
              Container(
                margin: const EdgeInsets.only(bottom: 14),
                child: Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: _showRequestHolidayDialog,
                        icon: const Icon(Icons.add, size: 20),
                        label: const Text("Request Holiday"),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF4CC9F0),
                          foregroundColor: Colors.white,
                          minimumSize: const Size(double.infinity, 50),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    ElevatedButton(
                      onPressed: fetchHolidays,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF1E3A5F),
                        foregroundColor: Colors.white,
                        minimumSize: const Size(52, 50),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: BorderSide(color: const Color(0xFF4CC9F0).withOpacity(0.3)),
                        ),
                      ),
                      child: const Icon(Icons.refresh),
                    ),
                  ],
                ),
              ),

              // Content container
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.03),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.white.withOpacity(0.1)),
                  ),
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
                                    Text("Error loading holidays", style: TextStyle(color: Colors.white.withOpacity(0.85), fontSize: 18)),
                                    const SizedBox(height: 8),
                                    Text(errorMessage, style: TextStyle(color: Colors.white.withOpacity(0.6)), textAlign: TextAlign.center),
                                    const SizedBox(height: 16),
                                    ElevatedButton(
                                      onPressed: fetchHolidays,
                                      style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF4CC9F0)),
                                      child: const Text("Try Again"),
                                    ),
                                  ],
                                ),
                              ),
                            )
                          : _buildAllSections(),
                ),
              ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: _buildBottomNavigationBar(),
    );
  }

 Widget _buildAllSections() {
  return SingleChildScrollView(
    padding: const EdgeInsets.only(bottom: 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // PENDING
        _sectionTitle(
          "Pending Holidays",
          subtitle: "Waiting for manager approval",
          icon: Icons.hourglass_top,
        ),
        _holidayListEmbedded(pendingHolidays, isPending: true),

        const SizedBox(height: 14),

        // CURRENT APPROVED
        _sectionTitle(
          "Approved (Current Year)",
          subtitle: "Approved holidays inside the business holiday year",
          icon: Icons.verified,
        ),
        _holidayListEmbedded(currentApproved, isPending: false),

        const SizedBox(height: 14),

        // PAST
        _sectionTitle(
          "Past Holidays",
          subtitle: "Tap a year to expand",
          icon: Icons.history,
        ),

        if (pastByYear.isEmpty)
          Padding(
            padding: const EdgeInsets.all(12),
            child: Center(
              child: Text(
                "No past holidays.",
                style: TextStyle(color: Colors.white.withOpacity(0.6)),
              ),
            ),
          )
        else
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Column(
              children: pastByYear.entries.map((e) {
                final year = e.key;
                final list = e.value;

                return Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF172A45).withOpacity(0.6),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: Colors.white.withOpacity(0.08)),
                  ),
                  child: ExpansionTile(
                    collapsedIconColor: const Color(0xFF4CC9F0),
                    iconColor: const Color(0xFF4CC9F0),
                    title: Text(
                      year,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    subtitle: Text(
                      "${list.length} holiday${list.length == 1 ? '' : 's'}",
                      style: TextStyle(color: Colors.white.withOpacity(0.6)),
                    ),
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                        child: _holidayListEmbedded(list, isPending: false),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ),
      ],
    ),
  );
}

Widget _holidayListEmbedded(List<Holiday> list, {required bool isPending}) {
  if (list.isEmpty) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Center(
        child: Text(
          isPending ? "No pending holidays." : "No holidays found.",
          style: TextStyle(color: Colors.white.withOpacity(0.6)),
        ),
      ),
    );
  }

  return ListView.builder(
    shrinkWrap: true,
    physics: const NeverScrollableScrollPhysics(),
    padding: const EdgeInsets.all(12),
    itemCount: list.length,
    itemBuilder: (_, i) => _holidayCard(list[i], isPending: isPending),
  );
}


  // ---------- Bottom nav (kept simple) ----------
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
