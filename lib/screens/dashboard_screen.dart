import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';

import '../models/database_access.dart';
import '../services/auth_service.dart';
import '../services/notifications_service.dart';
import '../services/session.dart';

import 'employee_profile_screen.dart';
import 'employees_screen.dart';
import 'earnings_screen.dart';
import 'holidays_screen.dart';
import 'holiday_requests_screen.dart';
import 'hours_summary_screen.dart';
import 'login_screen.dart';
import 'notifications_screen.dart';
import 'shift_requests_screen.dart';

class DashboardScreen extends StatefulWidget {
  final String email;
  final List<DatabaseAccess> databases;
  final DatabaseAccess selectedDb;

  const DashboardScreen({
    super.key,
    required this.email,
    required this.databases,
    required this.selectedDb,
  });

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen>
    with SingleTickerProviderStateMixin {
  late DatabaseAccess currentDb;

  // Clock + date
  Timer? _timer;
  String appBarDateText = '';

  // Employee
  String? employeeName;
  String? employeeLastName;
  double? employeeWage;
  String? employeeDesignation;
  int? employeeId;

  // Profile image
  Uint8List? _profileImageBytes;

  // Notifications
  int unreadCount = 0;
  bool loadingUnread = false;

  // Welcome animation (kept, but not forcing rebuild during build)
  late AnimationController _welcomeController;
  late Animation<double> _welcomeAnimation;
  bool showWelcome = true;

  // Weekly rota
  bool loadingRota = false;
  List<_RotaDayRow> weekRota = [];
  bool hasScheduledShiftToday = false;

  // Reminder
  bool showClockInReminder = false;
  DateTime? lastReminderDate;

  bool _initializing = false;

  @override
  void initState() {
    super.initState();
    currentDb = widget.selectedDb;

    _welcomeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    _welcomeAnimation = CurvedAnimation(
      parent: _welcomeController,
      curve: Curves.easeInOutCubic,
    );

    _updateAppBarDate();
    _timer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (!mounted) return;
      _updateAppBarDate();
    });

    // init AFTER first frame (prevents "build scheduled during frame")
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeData();
    });
  }

  // -----------------------------
  // Safe UI error showing (NO setState during build)
  // -----------------------------
  void _showErrorSnack(String msg) {
    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(msg),
          backgroundColor: Colors.redAccent,
        ),
      );
    });
  }

  // -----------------------------
  // DB options + init
  // -----------------------------
  List<DatabaseAccess> get _dbOptions {
    if (widget.databases.isNotEmpty) return widget.databases;
    if (Session.databases.isNotEmpty) return Session.databases;
    return [currentDb];
  }

  Future<void> _persistSelectedDb(DatabaseAccess db) async {
    Session.db = db.dbName;
    await Session.save();
  }

  Future<void> _initializeData() async {
    if (_initializing) return;
    _initializing = true;

    try {
      await _fetchEmployeeInfo();
      await _fetchProfileImage();
      await _loadUnreadCount();
      await _fetchWeeklyRota();
      _checkDailyReminder();
    } catch (e) {
      _showErrorSnack("Dashboard init error: $e");
    } finally {
      _initializing = false;
    }
  }

  void _updateAppBarDate() {
    final now = DateTime.now();
    if (!mounted) return;
    setState(() {
      appBarDateText = DateFormat('EEEE, d MMMM').format(now);
    });
  }

  // -----------------------------
  // Employee + profile image
  // -----------------------------
  Future<void> _fetchEmployeeInfo() async {
    try {
      final response = await http.get(
        Uri.parse(
          "${AuthService.baseUrl}/employee?email=${widget.email}&db=${currentDb.dbName}",
        ),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (!mounted) return;

        setState(() {
          employeeName = data['name'];
          employeeLastName = data['lastName'];
          final wage = data['wage'];
          employeeWage =
              wage != null ? double.tryParse(wage.toString()) ?? 0.0 : 0.0;
          employeeDesignation = data['designation'];
          employeeId = data['id'];
        });
      } else {
        _showErrorSnack("Failed to load employee info (${response.statusCode})");
      }
    } catch (e) {
      _showErrorSnack("Employee info error: $e");
    }
  }

  Future<void> _fetchProfileImage() async {
    try {
      final url = Uri.parse(
        "${AuthService.baseUrl}/profile/employees?db=${currentDb.dbName}&email=${widget.email}",
      );
      final response = await http.get(url);

      if (response.statusCode != 200) return;

      final decoded = jsonDecode(response.body);
      if (decoded is! Map) return;

      if (decoded['success'] == true && decoded['employee'] is Map) {
        final emp = decoded['employee'] as Map;
        final base64Str = (emp['profileImage'] ?? '').toString().trim();

        Uint8List? bytes;
        if (base64Str.isNotEmpty) {
          try {
            bytes = base64Decode(base64Str);
          } catch (_) {
            bytes = null;
          }
        }

        if (!mounted) return;
        setState(() => _profileImageBytes = bytes);
      }
    } catch (e) {
      // don’t spam user for image; silent or gentle message
      // _showErrorSnack("Profile image error: $e");
    }
  }

  // -----------------------------
  // Notifications
  // -----------------------------
  Future<void> _loadUnreadCount() async {
    if (loadingUnread) return;

    final role = (Session.role ?? "").trim();
    if (role.isEmpty) return;

    if (!mounted) return;
    setState(() => loadingUnread = true);

    try {
      final count = await NotificationsService.fetchUnreadCount(
        db: currentDb.dbName,
        role: role,
      );
      if (!mounted) return;
      setState(() => unreadCount = count);
    } catch (e) {
      // keep it clean: no red screens, just ignore or show once
      // _showErrorSnack("Unread count error: $e");
    } finally {
      if (mounted) setState(() => loadingUnread = false);
    }
  }

  Future<void> _openNotifications() async {
    final role = (Session.role ?? "").trim();
    if (role.isEmpty) {
      _showErrorSnack("No role found in session.");
      return;
    }

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => NotificationsScreen(
          selectedDb: currentDb,
          role: role,
        ),
      ),
    );

    await _loadUnreadCount();
  }

  // -----------------------------
  // Reminder
  // -----------------------------
  void _checkDailyReminder() {
    final todayStr = DateFormat('dd/MM/yyyy').format(DateTime.now());
    final last = lastReminderDate != null
        ? DateFormat('dd/MM/yyyy').format(lastReminderDate!)
        : null;

    // Only show reminder if today has NO scheduled shift
    if (last != todayStr && !hasScheduledShiftToday) {
      if (!mounted) return;
      setState(() => showClockInReminder = true);
      lastReminderDate = DateTime.now();
    }
  }

  // -----------------------------
  // Switch DB
  // -----------------------------
  Future<void> switchDatabase(DatabaseAccess db) async {
    if (!mounted) return;

    setState(() {
      currentDb = db;
      weekRota = [];
      hasScheduledShiftToday = false;
      showClockInReminder = false;
      _profileImageBytes = null;
    });

    await _persistSelectedDb(db);
    await _initializeData();
  }

  // -----------------------------
  // Weekly rota (GET /rota)
  // day stored as "dd/MM/yyyy (Day)"
  // -----------------------------
  Future<void> _fetchWeeklyRota() async {
    if (loadingRota) return;

    if (!mounted) return;
    setState(() {
      loadingRota = true;
      showWelcome = false;
    });

    try {
      if ((employeeName ?? "").trim().isEmpty ||
          (employeeLastName ?? "").trim().isEmpty) {
        await _fetchEmployeeInfo();
      }

      if ((employeeName ?? "").trim().isEmpty ||
          (employeeLastName ?? "").trim().isEmpty) {
        throw Exception("Employee name/lastName not available.");
      }

      final response = await http.get(
        Uri.parse(
          "${AuthService.baseUrl}/rota?db=${currentDb.dbName}&name=$employeeName&lastName=$employeeLastName",
        ),
      );

      if (response.statusCode != 200) {
        throw Exception("Failed to fetch rota (${response.statusCode}).");
      }

      final decoded = jsonDecode(response.body);
      if (decoded is! List) {
        throw Exception("Unexpected rota response format.");
      }

      _buildWeekRotaRows(List<Map<String, dynamic>>.from(decoded));
    } catch (e) {
      _showErrorSnack("Error loading rota: $e");
    } finally {
      if (mounted) setState(() => loadingRota = false);
    }
  }

  void _buildWeekRotaRows(List<Map<String, dynamic>> rows) {
    final Map<String, List<_ShiftFrame>> grouped = {};

    for (final r in rows) {
      final rawDay = (r['day'] ?? '').toString().trim();
      final datePart = rawDay.isEmpty ? '' : rawDay.split(' ').first;
      if (datePart.isEmpty) continue;

      final id = r['id'];
      final start =
          _ensureHHmmFormat((r['startTime'] ?? r['start_time'] ?? '').toString());
      final end =
          _ensureHHmmFormat((r['endTime'] ?? r['end_time'] ?? '').toString());

      grouped.putIfAbsent(datePart, () => []);
      grouped[datePart]!.add(
        _ShiftFrame(
          id: (id is int) ? id : int.tryParse(id?.toString() ?? ''),
          start: start,
          end: end,
        ),
      );
    }

    final now = DateTime.now();
    final monday = DateTime(now.year, now.month, now.day)
        .subtract(Duration(days: now.weekday - 1));

    final List<_RotaDayRow> normalized = [];
    for (int i = 0; i < 7; i++) {
      final day = monday.add(Duration(days: i));
      final dateStr = DateFormat('dd/MM/yyyy').format(day);
      final dayName = DateFormat('EEEE').format(day);

      final frames = (grouped[dateStr] ?? [])
        ..sort((a, b) => a.start.compareTo(b.start));

      normalized.add(
        _RotaDayRow(
          date: day,
          dateStr: dateStr,
          dayName: dayName,
          shifts: frames,
        ),
      );
    }

    final todayStr = DateFormat('dd/MM/yyyy').format(DateTime.now());
    final todayRow = normalized.firstWhere(
      (r) => r.dateStr == todayStr,
      orElse: () => normalized.first,
    );

    final hasToday =
        todayRow.shifts.any((s) => s.start.isNotEmpty && s.end.isNotEmpty);

    if (!mounted) return;
    setState(() {
      weekRota = normalized;
      hasScheduledShiftToday = hasToday;
    });
  }

  String _ensureHHmmFormat(String time) {
    final t = time.trim();
    if (t.isEmpty) return '';
    try {
      final parts = t.split(':');
      if (parts.length >= 2) {
        final hh = parts[0].padLeft(2, '0');
        final mm = parts[1].padLeft(2, '0');
        return '$hh:$mm';
      }
      return t;
    } catch (_) {
      return t;
    }
  }

  // -----------------------------
  // EDIT SCHEDULE (ONLY if shift exists today)
  // -----------------------------
  List<_ShiftFrame> _getTodayShiftFrames() {
    final todayStr = DateFormat('dd/MM/yyyy').format(DateTime.now());
    final row = weekRota.firstWhere(
      (r) => r.dateStr == todayStr,
      orElse: () => _RotaDayRow(
        date: DateTime.now(),
        dateStr: todayStr,
        dayName: DateFormat('EEEE').format(DateTime.now()),
        shifts: const [],
      ),
    );

    return row.shifts
        .where((s) => (s.start.isNotEmpty || s.end.isNotEmpty))
        .toList()
      ..sort((a, b) => a.start.compareTo(b.start));
  }

  bool _hasShiftToday() {
    final todayStr = DateFormat('dd/MM/yyyy').format(DateTime.now());
    final row = weekRota.firstWhere(
      (r) => r.dateStr == todayStr,
      orElse: () => _RotaDayRow(
        date: DateTime.now(),
        dateStr: todayStr,
        dayName: DateFormat('EEEE').format(DateTime.now()),
        shifts: const [],
      ),
    );

    return row.shifts.any((s) => s.start.isNotEmpty && s.end.isNotEmpty);
  }

  Future<TimeOfDay?> _showTimePicker(
      BuildContext context, String initialTime) async {
    TimeOfDay initialTimeOfDay;

    if (initialTime.trim().isNotEmpty) {
      final parts = initialTime.split(':');
      if (parts.length >= 2) {
        initialTimeOfDay = TimeOfDay(
          hour: int.tryParse(parts[0]) ?? TimeOfDay.now().hour,
          minute: int.tryParse(parts[1]) ?? TimeOfDay.now().minute,
        );
      } else {
        initialTimeOfDay = TimeOfDay.now();
      }
    } else {
      initialTimeOfDay = TimeOfDay.now();
    }

    final picked = await showTimePicker(
      context: context,
      initialTime: initialTimeOfDay,
      builder: (context, child) {
        if (child == null) return const SizedBox.shrink(); // ✅ avoids null crash
        return MediaQuery(
          data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
          child: Theme(
            data: ThemeData.dark().copyWith(
              colorScheme: const ColorScheme.dark(
                primary: Color(0xFF4CC9F0),
                onPrimary: Colors.white,
                surface: Color(0xFF0A192F),
                onSurface: Colors.white,
              ),
              dialogBackgroundColor: const Color(0xFF172A45),
              timePickerTheme: const TimePickerThemeData(
                backgroundColor: Color(0xFF172A45),
                dialBackgroundColor: Color(0xFF1E3A5F),
                dialTextColor: Colors.white,
                entryModeIconColor: Color(0xFF4CC9F0),
                hourMinuteColor: Color(0xFF1E3A5F),
                hourMinuteTextColor: Colors.white,
                dayPeriodColor: Color(0xFF1E3A5F),
                dayPeriodTextColor: Colors.white,
                dialHandColor: Color(0xFF4CC9F0),
              ),
            ),
            child: child,
          ),
        );
      },
    );

    return picked;
  }

  void _showEnterTimesDialog() {
    if (!_hasShiftToday()) {
      _showErrorSnack(
          "You can’t edit today because no shift is scheduled. Contact your manager.");
      return;
    }

    final now = DateTime.now();
    final today = DateFormat('dd/MM/yyyy').format(now);
    final dayName = DateFormat('EEEE').format(now);
    final displayDate = '$today ($dayName)';

    final todayFrames = _getTodayShiftFrames();

    final startControllers = <TextEditingController>[];
    final endControllers = <TextEditingController>[];
    final entryIds = <int?>[];

    for (int i = 0; i < 2; i++) {
      if (i < todayFrames.length) {
        startControllers.add(TextEditingController(text: todayFrames[i].start));
        endControllers.add(TextEditingController(text: todayFrames[i].end));
        entryIds.add(todayFrames[i].id);
      } else {
        startControllers.add(TextEditingController());
        endControllers.add(TextEditingController());
        entryIds.add(null);
      }
    }

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, localSetState) {
          return AlertDialog(
            backgroundColor: const Color(0xFF172A45),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
              side: BorderSide(color: Colors.white.withOpacity(0.10), width: 1),
            ),
            title: const Text(
              "Update Scheduled Hours",
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold),
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    "Today: $displayDate",
                    style: TextStyle(
                        color: Colors.white.withOpacity(0.75),
                        fontWeight: FontWeight.w500),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    "Enter your work periods (up to 2). Overnight shifts allowed.",
                    style: TextStyle(
                        color: Colors.white.withOpacity(0.55), fontSize: 13),
                  ),
                  const SizedBox(height: 18),
                  for (int i = 0; i < 2; i++)
                    Column(
                      children: [
                        if (i > 0) const SizedBox(height: 18),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              i == 0 ? "First Work Period" : "Second Work Period",
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.bold,
                                color: i == 0
                                    ? const Color(0xFF4CC9F0)
                                    : const Color(0xFF4ADE80),
                              ),
                            ),
                            if (entryIds[i] != null)
                              IconButton(
                                icon: Icon(Icons.delete, color: Colors.red[300]),
                                onPressed: () {
                                  showDialog(
                                    context: context,
                                    builder: (context) => AlertDialog(
                                      backgroundColor: const Color(0xFF172A45),
                                      title: const Text("Delete Schedule?",
                                          style:
                                              TextStyle(color: Colors.white)),
                                      content: Text(
                                        "Are you sure you want to delete this period?",
                                        style: TextStyle(
                                            color:
                                                Colors.white.withOpacity(0.8)),
                                      ),
                                      actions: [
                                        TextButton(
                                          onPressed: () =>
                                              Navigator.pop(context),
                                          child: const Text("Cancel",
                                              style: TextStyle(
                                                  color: Color(0xFF4CC9F0))),
                                        ),
                                        TextButton(
                                          onPressed: () async {
                                            final id = entryIds[i]!;
                                            try {
                                              await _deleteRotaEntry(id);
                                              startControllers[i].clear();
                                              endControllers[i].clear();
                                              entryIds[i] = null;

                                              if (mounted) {
                                                ScaffoldMessenger.of(context)
                                                    .showSnackBar(
                                                  const SnackBar(
                                                    content: Text(
                                                        "Schedule deleted successfully!"),
                                                    backgroundColor:
                                                        Colors.green,
                                                  ),
                                                );
                                              }

                                              Navigator.pop(context);
                                              localSetState(() {});
                                            } catch (e) {
                                              Navigator.pop(context);
                                              _showErrorSnack(
                                                  "Error deleting schedule: $e");
                                            }
                                          },
                                          child: Text("Delete",
                                              style: TextStyle(
                                                  color: Colors.red[300])),
                                        ),
                                      ],
                                    ),
                                  );
                                },
                              ),
                          ],
                        ),
                        _TimeInputField(
                          controller: startControllers[i],
                          label: "Start Time (HH:mm)",
                          onTap: () async {
                            final picked = await _showTimePicker(
                                context, startControllers[i].text);
                            if (picked != null) {
                              startControllers[i].text =
                                  "${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}";
                              localSetState(() {});
                            }
                          },
                        ),
                        const SizedBox(height: 12),
                        _TimeInputField(
                          controller: endControllers[i],
                          label: "End Time (HH:mm)",
                          onTap: () async {
                            final picked = await _showTimePicker(
                                context, endControllers[i].text);
                            if (picked != null) {
                              endControllers[i].text =
                                  "${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}";
                              localSetState(() {});
                            }
                          },
                        ),
                      ],
                    ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text("Cancel",
                    style: TextStyle(color: Color(0xFF4CC9F0))),
              ),
              ElevatedButton(
                onPressed: () async {
                  final workPeriods = <Map<String, dynamic>>[];

                  for (int i = 0; i < 2; i++) {
                    final startTime = startControllers[i].text.trim();
                    final endTime = endControllers[i].text.trim();

                    if (startTime.isEmpty && endTime.isEmpty) continue;

                    if (startTime.isEmpty || endTime.isEmpty) {
                      _showErrorSnack(
                          "Please enter both times for ${i == 0 ? 'First' : 'Second'} period.");
                      return;
                    }

                    final timeRegex =
                        RegExp(r'^([0-1]?[0-9]|2[0-3]):[0-5][0-9]$');
                    if (!timeRegex.hasMatch(startTime) ||
                        !timeRegex.hasMatch(endTime)) {
                      _showErrorSnack(
                          "Times must be HH:mm for ${i == 0 ? 'First' : 'Second'} period.");
                      return;
                    }

                    workPeriods.add({
                      'id': entryIds[i],
                      'startTime': _ensureHHmmFormat(startTime),
                      'endTime': _ensureHHmmFormat(endTime),
                    });
                  }

                  await _saveRotaShifts(workPeriods);
                  if (mounted) Navigator.pop(context);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF4CC9F0),
                  foregroundColor: Colors.white,
                ),
                child: const Text("Save Changes"),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _saveRotaShifts(List<Map<String, dynamic>> timeFrames) async {
    final now = DateTime.now();
    final today = DateFormat('dd/MM/yyyy').format(now);
    final dayName = DateFormat('EEEE').format(now);
    final formattedDay = '$today ($dayName)';

    try {
      if ((employeeName ?? "").trim().isEmpty ||
          (employeeLastName ?? "").trim().isEmpty) {
        await _fetchEmployeeInfo();
      }
      if ((employeeName ?? "").trim().isEmpty ||
          (employeeLastName ?? "").trim().isEmpty) {
        throw Exception("Employee info not available.");
      }

      final keptEntryIds = <int>[];

      for (final frame in timeFrames) {
        final startTime = (frame['startTime'] ?? '').toString().trim();
        final endTime = (frame['endTime'] ?? '').toString().trim();
        final entryId = frame['id'];

        if (startTime.isEmpty || endTime.isEmpty) continue;

        final body = <String, dynamic>{
          'db': currentDb.dbName,
          'name': employeeName,
          'lastName': employeeLastName,
          'employeeId': employeeId,
          'day': formattedDay,
          'startTime': startTime,
          'endTime': endTime,
          'wage': (employeeWage ?? 0).toStringAsFixed(2),
          'designation': employeeDesignation ?? '',
        };

        if (entryId != null) {
          body['entryId'] = entryId;
          final parsed =
              entryId is int ? entryId : int.tryParse(entryId.toString());
          if (parsed != null) keptEntryIds.add(parsed);
        }

        final response = await http.post(
          Uri.parse("${AuthService.baseUrl}/save-shift"),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode(body),
        );

        final responseBody = response.body;
        if (responseBody.trim().startsWith('<!DOCTYPE html>')) {
          throw Exception("Server returned HTML error page.");
        }

        final data = jsonDecode(responseBody);

        if (response.statusCode != 200 ||
            (data is Map && data['success'] != true)) {
          throw Exception(
              (data is Map ? data['message'] : null) ?? "Failed to save shift.");
        }

        if (entryId == null && data is Map && data['entryId'] != null) {
          final newId = data['entryId'];
          final parsed =
              newId is int ? newId : int.tryParse(newId.toString());
          if (parsed != null) keptEntryIds.add(parsed);
        }
      }

      final existing = _getTodayShiftFrames();
      for (final e in existing) {
        if (e.id != null && !keptEntryIds.contains(e.id)) {
          await _deleteRotaEntry(e.id!);
        }
      }

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(timeFrames.isNotEmpty
              ? "Schedule updated successfully!"
              : "All shifts cleared for today!"),
          backgroundColor: timeFrames.isNotEmpty ? Colors.green : Colors.blue,
        ),
      );

      setState(() {
        hasScheduledShiftToday = timeFrames.isNotEmpty;
        showClockInReminder = false;
      });

      await _fetchWeeklyRota();
    } catch (e) {
      _showErrorSnack("Error saving schedule: $e");
    }
  }

  Future<void> _deleteRotaEntry(int entryId) async {
    final response = await http.post(
      Uri.parse("${AuthService.baseUrl}/delete-shift"),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'db': currentDb.dbName,
        'entryId': entryId,
      }),
    );

    final responseBody = response.body;
    if (responseBody.trim().startsWith('<!DOCTYPE html>')) {
      throw Exception("Server returned HTML error page.");
    }

    final data = jsonDecode(responseBody);
    if (response.statusCode != 200 ||
        (data is Map && data['success'] != true)) {
      throw Exception(
          (data is Map ? data['message'] : null) ?? "Failed to delete shift.");
    }
  }

  // -----------------------------
  // Drawer + logout + settings
  // -----------------------------
  Future<void> _showDbPicker() async {
    final options = _dbOptions;
    if (options.length <= 1) return;

    await showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF0A192F),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 46,
                  height: 5,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    const Icon(Icons.apartment, color: Color(0xFF4CC9F0)),
                    const SizedBox(width: 10),
                    const Text(
                      "Select workspace",
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold),
                    ),
                    const Spacer(),
                    Text(
                      currentDb.dbName,
                      style: TextStyle(
                          color: Colors.white.withOpacity(0.6), fontSize: 12),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                ...options.map((db) {
                  final isSelected = db.dbName == currentDb.dbName;
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: CircleAvatar(
                      radius: 18,
                      backgroundColor: isSelected
                          ? const Color(0xFF4CC9F0)
                          : Colors.white.withOpacity(0.10),
                      child: Icon(
                        isSelected ? Icons.check : Icons.storage,
                        color: isSelected
                            ? Colors.white
                            : Colors.white.withOpacity(0.8),
                        size: 18,
                      ),
                    ),
                    title: Text(
                      db.dbName,
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight:
                            isSelected ? FontWeight.bold : FontWeight.w500,
                      ),
                    ),
                    trailing: isSelected
                        ? const Icon(Icons.verified, color: Color(0xFF4ADE80))
                        : Icon(Icons.chevron_right,
                            color: Colors.white.withOpacity(0.35)),
                    onTap: () async {
                      Navigator.pop(context);
                      await switchDatabase(db);
                    },
                  );
                }),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _logout() async {
    try {
      await Session.clear();
    } catch (_) {}

    if (!mounted) return;

    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (route) => false,
    );
  }

  void _openSettingsPlaceholder() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Settings page will be added later.")),
    );
  }

  // -----------------------------
  // UI
  // -----------------------------
  Widget _buildClockInReminder() {
    if (!showClockInReminder || hasScheduledShiftToday) {
      return const SizedBox();
    }

    return Container(
      padding: const EdgeInsets.all(14),
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(14),
        border:
            Border.all(color: const Color(0xFF4CC9F0).withOpacity(0.25)),
      ),
      child: Row(
        children: [
          const Icon(Icons.info_outline, color: Color(0xFF4CC9F0)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              "No shift scheduled today. You can’t edit schedule. Contact your manager.",
              style: TextStyle(color: Colors.white.withOpacity(0.75), fontSize: 13),
            ),
          ),
          IconButton(
            onPressed: () => setState(() => showClockInReminder = false),
            icon: Icon(Icons.close, color: Colors.white.withOpacity(0.7)),
          )
        ],
      ),
    );
  }

  Widget _buildTodayCard() {
    final now = DateTime.now();
    final todayStr = DateFormat('dd/MM/yyyy').format(now);

    final todayRow = weekRota.firstWhere(
      (r) => r.dateStr == todayStr,
      orElse: () => _RotaDayRow(
        date: now,
        dateStr: todayStr,
        dayName: DateFormat('EEEE').format(now),
        shifts: const [],
      ),
    );

    final hasShifts =
        todayRow.shifts.any((s) => s.start.isNotEmpty && s.end.isNotEmpty);

    final total = _calcTotalText(todayRow.shifts);
    final est = _calcEarnings(todayRow.shifts);

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.10)),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            const Color(0xFF172A45).withOpacity(0.95),
            const Color(0xFF0A192F).withOpacity(0.95),
          ],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.today, color: Color(0xFF4CC9F0)),
              const SizedBox(width: 10),
              const Text(
                "Today",
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold),
              ),
              const Spacer(),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.06),
                    borderRadius: BorderRadius.circular(999)),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    "${todayRow.dayName} • ${todayRow.dateStr}",
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: Colors.white.withOpacity(0.75), fontSize: 12),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (!hasShifts)
            Text(
              "No shift scheduled. You can’t edit schedule.",
              style: TextStyle(color: Colors.white.withOpacity(0.70), fontSize: 14),
            )
          else
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ...todayRow.shifts
                    .where((s) => s.start.isNotEmpty && s.end.isNotEmpty)
                    .map((s) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(
                      children: [
                        const Icon(Icons.schedule,
                            size: 16, color: Color(0xFF4ADE80)),
                        const SizedBox(width: 8),
                        Text(
                          "${s.start} - ${s.end}",
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  );
                }),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: _StatChip(
                        label: "Total",
                        value: total,
                        valueColor: const Color(0xFF4CC9F0),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _StatChip(
                        label: "Est. earnings",
                        value: (employeeWage ?? 0) > 0
                            ? "£${est.toStringAsFixed(2)}"
                            : "-",
                        valueColor: const Color(0xFF4ADE80),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          const SizedBox(height: 14),
          if (hasShifts)
            ElevatedButton.icon(
              onPressed: _showEnterTimesDialog,
              icon: const Icon(Icons.edit, size: 18),
              label: const Text("Edit Today's Schedule"),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF4CC9F0),
                foregroundColor: Colors.white,
                minimumSize: const Size(double.infinity, 46),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildMyRotaTable() {
    if (loadingRota) {
      return Container(
        padding: const EdgeInsets.all(28),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.04),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withOpacity(0.08)),
        ),
        child: const Center(
          child: CircularProgressIndicator(color: Color(0xFF4CC9F0)),
        ),
      );
    }

    if (weekRota.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.04),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withOpacity(0.08)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "My Rota (This week)",
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            Text("No rota data available.",
                style: TextStyle(color: Colors.white.withOpacity(0.65))),
          ],
        ),
      );
    }

    final todayStr = DateFormat('dd/MM/yyyy').format(DateTime.now());

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.04),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                "My Rota (This week)",
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold),
              ),
              const Spacer(),
              TextButton.icon(
                onPressed: _fetchWeeklyRota,
                icon: const Icon(Icons.refresh,
                    size: 18, color: Color(0xFF4CC9F0)),
                label: const Text("Refresh",
                    style: TextStyle(color: Color(0xFF4CC9F0))),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.05),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white.withOpacity(0.08)),
            ),
            child: Row(
              children: [
                _headerCell("Day", flex: 6), // ✅ more space for day
                _headerCell("Shifts", flex: 5),
                _headerCell("Total", flex: 2, alignRight: true), // ✅ tighter total column
              ],
            ),
          ),
          const SizedBox(height: 8),
          ...weekRota.map((row) {
            final isToday = row.dateStr == todayStr;

            final shiftFrames = row.shifts
                .where((s) => s.start.isNotEmpty && s.end.isNotEmpty)
                .toList();

            final shiftsText = shiftFrames.isEmpty
                ? "Off"
                : shiftFrames.map((s) => "${s.start}-${s.end}").join(" • ");

            final totalText =
                shiftFrames.isEmpty ? "-" : _calcTotalText(shiftFrames);

            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: isToday
                    ? const Color(0xFF4CC9F0).withOpacity(0.10)
                    : Colors.white.withOpacity(0.03),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isToday
                      ? const Color(0xFF4ADE80).withOpacity(0.35)
                      : Colors.white.withOpacity(0.06),
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 6, // ✅ more space
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (isToday)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Container(
                              width: 8,
                              height: 8,
                              decoration: const BoxDecoration(
                                shape: BoxShape.circle,
                                color: Color(0xFF4ADE80),
                              ),
                            ),
                          ),
                        if (isToday) const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                row.dayName, // ✅ no substring, no cut
                                style: TextStyle(
                                  color: Colors.white.withOpacity(0.92),
                                  fontWeight: isToday
                                      ? FontWeight.bold
                                      : FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                row.dateStr,
                                style: TextStyle(
                                  color: Colors.white.withOpacity(0.65),
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    flex: 5,
                    child: Padding(
                      padding: const EdgeInsets.only(top: 1),
                      child: Text(
                        shiftsText,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: shiftFrames.isEmpty
                              ? Colors.white.withOpacity(0.45)
                              : Colors.white.withOpacity(0.85),
                          fontWeight:
                              isToday ? FontWeight.w600 : FontWeight.w500,
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    flex: 1, // ✅ less gap between shifts and total
                    child: Align(
                      alignment: Alignment.topRight,
                      child: Text(
                        totalText,
                        style: TextStyle(
                          color: isToday
                              ? const Color(0xFF4ADE80)
                              : Colors.white.withOpacity(0.80),
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _headerCell(String text, {required int flex, bool alignRight = false}) {
    return Expanded(
      flex: flex,
      child: Align(
        alignment: alignRight ? Alignment.centerRight : Alignment.centerLeft,
        child: Text(
          text,
          maxLines: 1,
          softWrap: false,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: Colors.white.withOpacity(0.55),
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }

  String _calcTotalText(List<_ShiftFrame> shifts) {
    int totalMinutes = 0;
    for (final s in shifts) {
      if (s.start.isEmpty || s.end.isEmpty) continue;
      totalMinutes += _diffMinutes(s.start, s.end);
    }
    if (totalMinutes <= 0) return "-";
    final h = totalMinutes ~/ 60;
    final m = totalMinutes % 60;
    return m == 0 ? "${h}h" : "${h}h ${m}m";
  }

  double _calcEarnings(List<_ShiftFrame> shifts) {
    final wage = employeeWage ?? 0.0;
    if (wage <= 0) return 0.0;

    int totalMinutes = 0;
    for (final s in shifts) {
      if (s.start.isEmpty || s.end.isEmpty) continue;
      totalMinutes += _diffMinutes(s.start, s.end);
    }
    return (totalMinutes / 60.0) * wage;
  }

  int _diffMinutes(String startHHmm, String endHHmm) {
    try {
      final sp = startHHmm.split(':');
      final ep = endHHmm.split(':');
      if (sp.length < 2 || ep.length < 2) return 0;

      final sh = int.tryParse(sp[0]) ?? 0;
      final sm = int.tryParse(sp[1]) ?? 0;
      final eh = int.tryParse(ep[0]) ?? 0;
      final em = int.tryParse(ep[1]) ?? 0;

      int start = sh * 60 + sm;
      int end = eh * 60 + em;
      if (end < start) end += 24 * 60;

      final d = end - start;
      return d > 0 ? d : 0;
    } catch (_) {
      return 0;
    }
  }

  Widget _buildBottomNavigationBar() {
    return Container(
      height: 70,
      decoration: BoxDecoration(
        color: const Color(0xFF172A45),
        border: Border(
          top: BorderSide(color: Colors.white.withOpacity(0.10), width: 1),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildNavButton(
            icon: Icons.access_time,
            label: 'Hours',
            onTap: () {
              if (employeeName != null && employeeLastName != null) {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => HoursSummaryScreen(
                      email: widget.email,
                      selectedDb: currentDb,
                      employeeName: employeeName!,
                      employeeLastName: employeeLastName!,
                    ),
                  ),
                );
              }
            },
          ),
          _buildNavButton(
            icon: Icons.work_outline,
            label: 'Requests',
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => ShiftRequestsScreen(
                    selectedDb: currentDb,
                    userEmail: widget.email,
                    userName: employeeName ?? 'User',
                    userDesignation: (employeeDesignation ?? "").trim(),
                  ),
                ),
              );
            },
          ),
          _buildHomeButton(),
          _buildNavButton(
            icon: Icons.beach_access,
            label: 'Holidays',
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) =>
                      HolidaysScreen(email: widget.email, selectedDb: currentDb),
                ),
              );
            },
          ),
          _buildNavButton(
            icon: Icons.attach_money,
            label: 'Earnings',
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) =>
                      EarningsScreen(email: widget.email, selectedDb: currentDb),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildNavButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
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
                Icon(icon, color: Colors.white.withOpacity(0.70), size: 24),
                const SizedBox(height: 4),
                Text(
                  label,
                  style:
                      TextStyle(fontSize: 12, color: Colors.white.withOpacity(0.70)),
                ),
              ],
            ),
          ),
        ),
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
              gradient: const LinearGradient(
                colors: [Color(0xFF4CC9F0), Color(0xFF1E3A5F)],
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.30),
                  blurRadius: 8,
                  offset: const Offset(0, 4),
                )
              ],
            ),
            child: IconButton(
              icon: const Icon(Icons.home, size: 28),
              color: Colors.white,
              onPressed: () =>
                  Navigator.of(context).popUntil((route) => route.isFirst),
              tooltip: "Home",
            ),
          ),
          const SizedBox(height: 2),
          Text('Home',
              style:
                  TextStyle(fontSize: 12, color: Colors.white.withOpacity(0.70))),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    _welcomeController.dispose();
    super.dispose();
  }

  // -----------------------------
  // BUILD
  // -----------------------------
  @override
  Widget build(BuildContext context) {
  final String first = (employeeName ?? '').trim();
  final String last  = (employeeLastName ?? '').trim();

  final String displayName = first.isNotEmpty ? first : 'User';

  final String initials = (() {
    final a = displayName.isNotEmpty ? displayName[0].toUpperCase() : 'U';
    final b = last.isNotEmpty ? last[0].toUpperCase() : '';
    return '$a$b';
  })();

  final role = (Session.role ?? "").trim().toLowerCase();
  final canSeeHolidayRequests =
      role == "manager" || role == "am" || role == "assistant manager";

  return Scaffold(
      backgroundColor: const Color(0xFF0A192F),
      drawer: Drawer(
        backgroundColor: const Color(0xFF0A192F),
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            DrawerHeader(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFF1E3A5F), Color(0xFF0A192F)],
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CircleAvatar(
                    radius: 32,
                    backgroundColor: const Color(0xFF4CC9F0),
                    backgroundImage: _profileImageBytes != null
                        ? MemoryImage(_profileImageBytes!)
                        : null,
                    child: _profileImageBytes == null
                        ? Text(
                            initials,
                            style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: Colors.white),
                          )
                        : null,
                  ),
                  const SizedBox(height: 12),
                  const Text('Solura',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  Text(
                    widget.email,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: Colors.white.withOpacity(0.70), fontSize: 14),
                  ),

                  Text(
                    "Workspace: ${currentDb.dbName}",
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: Colors.white.withOpacity(0.55), fontSize: 12),
                  ),
                ],
              ),
            ),
            _DrawerTile(
              icon: Icons.person,
              title: 'Profile',
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => EmployeeProfileScreen(
                        selectedDb: currentDb, userEmail: widget.email),
                  ),
                );
              },
            ),
            _DrawerTile(
              icon: Icons.people,
              title: 'Employees',
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => EmployeesScreen(
                        selectedDb: currentDb, userEmail: widget.email),
                  ),
                );
              },
            ),
            _DrawerTile(
              icon: Icons.work_outline,
              title: 'Shift Requests',
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ShiftRequestsScreen(
                      selectedDb: currentDb,
                      userEmail: widget.email,
                      userName: displayName,
                      userDesignation: (employeeDesignation ?? "").trim(),
                    ),
                  ),
                );
              },
            ),
            if (canSeeHolidayRequests)
              _DrawerTile(
                icon: Icons.assignment,
                title: "Holiday Requests",
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => HolidayRequestsScreen(
                          selectedDb: currentDb, role: Session.role ?? ""),
                    ),
                  );
                },
              ),
            _DrawerTile(
              icon: Icons.settings,
              title: 'Settings',
              onTap: () {
                Navigator.pop(context);
                _openSettingsPlaceholder();
              },
            ),
            const Divider(color: Color(0xFF1E3A5F)),
            _DrawerTile(
              icon: Icons.logout,
              title: 'Logout',
              color: Colors.redAccent,
              onTap: _logout,
            ),
          ],
        ),
      ),
      appBar: AppBar(
        backgroundColor: const Color(0xFF172A45),
        elevation: 0,
        titleSpacing: 0,
        title: Padding(
          padding: const EdgeInsets.only(right: 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text("Dashboard",
                  style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Colors.white)),
              const SizedBox(height: 2),
              Text(appBarDateText,
                  style: TextStyle(fontSize: 13, color: Colors.white.withOpacity(0.70))),
            ],
          ),
        ),
        actions: [
          if (_dbOptions.length > 1)
            IconButton(
              tooltip: "Workspace",
              onPressed: _showDbPicker,
              icon: const Icon(Icons.apartment, color: Color(0xFF4CC9F0)),
            ),
          IconButton(
            tooltip: "Notifications",
            onPressed: _openNotifications,
            icon: Stack(
              clipBehavior: Clip.none,
              children: [
                const Icon(Icons.notifications, color: Color(0xFF4CC9F0)),
                if (unreadCount > 0)
                  Positioned(
                    right: -2,
                    top: -2,
                    child: Container(
                      padding:
                          const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.redAccent,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        unreadCount > 99 ? "99+" : unreadCount.toString(),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.refresh, color: Color(0xFF4CC9F0)),
            onPressed: () async {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                    content: Text("Refreshing..."),
                    backgroundColor: Color(0xFF4CC9F0)),
              );
              await _initializeData();
            },
            tooltip: 'Refresh',
          ),
          const SizedBox(width: 6),
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
          child: SingleChildScrollView(
            child: Column(
              children: [
                _buildClockInReminder(),
                _buildTodayCard(),
                _buildMyRotaTable(),
                const SizedBox(height: 8),
              ],
            ),
          ),
        ),
      ),
      bottomNavigationBar: _buildBottomNavigationBar(),
    );
  }
}

// -----------------------------
// Shared widgets + models
// -----------------------------
class _DrawerTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final VoidCallback onTap;
  final Color? color;

  const _DrawerTile({
    required this.icon,
    required this.title,
    required this.onTap,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon, color: color ?? Colors.white.withOpacity(0.85)),
      title: Text(title,
          style: TextStyle(color: color ?? Colors.white.withOpacity(0.85))),
      onTap: onTap,
      hoverColor: Colors.white.withOpacity(0.05),
    );
  }
}

class _StatChip extends StatelessWidget {
  final String label;
  final String value;
  final Color valueColor;

  const _StatChip({
    required this.label,
    required this.value,
    required this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: TextStyle(color: Colors.white.withOpacity(0.65), fontSize: 12)),
          Text(value,
              style: TextStyle(color: valueColor, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}

class _TimeInputField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final VoidCallback onTap;

  const _TimeInputField({
    required this.controller,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.05),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white.withOpacity(0.1)),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style:
                          TextStyle(fontSize: 12, color: Colors.white.withOpacity(0.5))),
                  const SizedBox(height: 4),
                  Text(
                    controller.text.isEmpty ? 'HH:mm' : controller.text,
                    style: TextStyle(
                      fontSize: 16,
                      color: controller.text.isEmpty
                          ? Colors.white.withOpacity(0.3)
                          : Colors.white,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.access_time, color: Color(0xFF4CC9F0)),
          ],
        ),
      ),
    );
  }
}

class _ShiftFrame {
  final int? id;
  final String start;
  final String end;

  const _ShiftFrame({
    required this.id,
    required this.start,
    required this.end,
  });
}

class _RotaDayRow {
  final DateTime date;
  final String dateStr;
  final String dayName;
  final List<_ShiftFrame> shifts;

  const _RotaDayRow({
    required this.date,
    required this.dateStr,
    required this.dayName,
    required this.shifts,
  });
}