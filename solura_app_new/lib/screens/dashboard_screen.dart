import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import '../models/database_access.dart';
import '../services/auth_service.dart';
import '../services/notifications_service.dart';
import '../services/session.dart';
import 'login_screen.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'hours_summary_screen.dart';
import 'all_rota_screen.dart';
import 'holidays_screen.dart';
import 'earnings_screen.dart';
import 'notifications_screen.dart';
import 'holiday_requests_screen.dart';

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
  List<Map<String, dynamic>> rotaData = [];
  bool loadingRota = false;
  late Timer _timer;
  late Timer _dateCheckTimer;
  String currentTime = '';
  String? employeeName;
  String? employeeLastName;
  double? employeeWage;
  String? employeeDesignation;
  int? employeeId;

  // Welcome Animation
  late AnimationController _welcomeController;
  late Animation<double> _welcomeAnimation;
  bool showWelcome = true;

  // Today's shift management
  List<Map<String, dynamic>> todayShifts = [];
  bool loadingTodayShifts = false;
  
  // Shift status
  bool hasScheduledShiftToday = false;
  
  // Reminder management
  bool showClockInReminder = false;
  bool hasEnteredTimesToday = false;
  DateTime? lastReminderDate;

  List<DatabaseAccess> get _dbOptions {
  if (widget.databases.isNotEmpty) return widget.databases;
  if (Session.databases.isNotEmpty) return Session.databases; // ✅ NEW
  // Fallback: at least show the current selected db
      return [currentDb];
    }

    Future<void> _persistSelectedDb(DatabaseAccess db) async {
      Session.db = db.dbName;
      // keep role/email as-is
      await Session.save();
    }

  // ✅ Notifications
  int unreadCount = 0;
  bool loadingUnread = false;

  @override
  void initState() {
    super.initState();
    currentDb = widget.selectedDb;

    // Clock update
    _updateTime();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _updateTime());
    
    // Check date change every minute
    _dateCheckTimer = Timer.periodic(const Duration(minutes: 1), (_) => _checkDateChange());

    // Welcome Animation setup
    _welcomeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );
    _welcomeAnimation = CurvedAnimation(
      parent: _welcomeController,
      curve: Curves.easeInOutCubic,
    );

    // Fetch employee info, rota, and today's shifts
    _initializeData();
  }

  Future<void> _initializeData() async {
    await _fetchEmployeeInfo();
    await _loadUnreadCount(); // ✅ Load notifications count
    await fetchRota();
    await fetchTodayShifts();
    _checkDailyReminder();
  }

  Future<void> _loadUnreadCount() async {
    if (loadingUnread) return;

    final role = Session.role;
    if (role == null || role.trim().isEmpty) {
      return;
    }

    setState(() => loadingUnread = true);
    try {
      final count = await NotificationsService.fetchUnreadCount(
        db: currentDb.dbName,
        role: role,
      );
      if (!mounted) return;
      setState(() => unreadCount = count);
    } catch (_) {
      // keep silent to avoid spamming snackbars
    } finally {
      if (mounted) setState(() => loadingUnread = false);
    }
  }

  Future<void> _openNotifications() async {
    final role = Session.role ?? "";
    if (role.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("No role found in session.")),
      );
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

    // refresh badge when coming back
    await _loadUnreadCount();
  }

  void _updateTime() {
    final now = DateTime.now();
    setState(() {
      currentTime = DateFormat('EEEE, MMMM dd').format(now);
    });
  }

  void _checkDateChange() {
    final now = DateTime.now();
    final today = DateFormat('dd/MM/yyyy').format(now);
    
    if (lastReminderDate == null || 
        DateFormat('dd/MM/yyyy').format(lastReminderDate!) != today) {
      setState(() {
        hasEnteredTimesToday = false;
        showClockInReminder = true;
      });
    }
  }

  void _checkDailyReminder() {
    final now = DateTime.now();
    final todayStr = DateFormat('dd/MM/yyyy').format(now);
    
    final prefs = _getStoredReminderPrefs();
    final lastReminder = prefs['lastReminderDate'];
    final lastEntered = prefs['lastEnteredDate'];
    
    if (lastReminder != todayStr && lastEntered != todayStr) {
      setState(() {
        showClockInReminder = true;
      });
      _storeReminderPrefs(todayStr, null);
    }
  }

  Map<String, String?> _getStoredReminderPrefs() {
    return {
      'lastReminderDate': lastReminderDate != null 
          ? DateFormat('dd/MM/yyyy').format(lastReminderDate!)
          : null,
      'lastEnteredDate': null,
    };
  }

  void _storeReminderPrefs(String? reminderDate, String? enteredDate) {
    if (reminderDate != null) {
      lastReminderDate = DateFormat('dd/MM/yyyy').parse(reminderDate);
    }
  }

  Future<void> _fetchEmployeeInfo() async {
    try {
      final response = await http.get(
        Uri.parse("${AuthService.baseUrl}/employee?email=${widget.email}&db=${currentDb.dbName}"),
      );
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        setState(() {
          employeeName = data['name'];
          employeeLastName = data['lastName'];
          final wage = data['wage'];
          employeeWage = wage != null ? double.tryParse(wage.toString()) ?? 0.0 : 0.0;
          employeeDesignation = data['designation'];
          employeeId = data['id'];
        });
      }
    } catch (e) {
      print("Error fetching employee info: $e");
    }
  }

  Future<void> fetchTodayShifts() async {
    setState(() => loadingTodayShifts = true);
    
    try {
      final response = await http.get(
        Uri.parse("${AuthService.baseUrl}/today-shifts?email=${widget.email}&db=${currentDb.dbName}"),
      );
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true) {
          final shifts = List<Map<String, dynamic>>.from(data['shifts']);
          
          final processedShifts = shifts.map((shift) {
            final startTime = shift['startTime'] ?? '';
            final endTime = shift['endTime'] ?? '';
            
            return {
              ...shift,
              'startTime': _ensureHHmmFormat(startTime),
              'endTime': _ensureHHmmFormat(endTime),
            };
          }).toList();
          
          setState(() {
            todayShifts = processedShifts;
            hasEnteredTimesToday = todayShifts.isNotEmpty && 
                todayShifts.any((shift) => 
                    shift['startTime']?.isNotEmpty == true && 
                    shift['endTime']?.isNotEmpty == true);
          });
        }
      }
    } catch (e) {
      print("Error fetching today's shifts: $e");
    } finally {
      setState(() => loadingTodayShifts = false);
    }
  }

  String _ensureHHmmFormat(String time) {
    if (time.isEmpty) return '';
    
    try {
      if (time.contains(':') && time.split(':').length >= 2) {
        final parts = time.split(':');
        return '${parts[0].padLeft(2, '0')}:${parts[1].padLeft(2, '0')}';
      }
      return time;
    } catch (_) {
      return time;
    }
  }

  Future<void> switchDatabase(DatabaseAccess db) async {
    setState(() => currentDb = db);

    await _persistSelectedDb(db); // ✅ SAVE selection

    await _fetchEmployeeInfo();
    await fetchRota();
    await fetchTodayShifts();
  }

  List<Map<String, dynamic>> _mapWeekRota(List<Map<String, dynamic>> data) {
    final now = DateTime.now();
    final monday = now.subtract(Duration(days: now.weekday - 1));
    List<Map<String, dynamic>> weekRota = [];

    Map<String, List<Map<String, dynamic>>> groupedByDay = {};
    
    for (var entry in data) {
      final dayStr = entry['day'] ?? '';
      final datePart = dayStr.split(' ').first;
      
      if (!groupedByDay.containsKey(datePart)) {
        groupedByDay[datePart] = [];
      }
      groupedByDay[datePart]!.add(entry);
    }

    for (int i = 0; i < 7; i++) {
      final day = monday.add(Duration(days: i));
      final dayStr = DateFormat('dd/MM/yyyy').format(day);
      final entries = groupedByDay[dayStr] ?? [];

      weekRota.add({
        'date': dayStr,
        'entries': entries.isNotEmpty ? entries : [{
          'name': employeeName ?? '',
          'lastName': '',
          'day': dayStr,
          'startTime': '',
          'endTime': ''
        }],
      });
    }

    return weekRota;
  }

  Future<void> fetchRota() async {
    if (loadingRota) return;
    
    setState(() {
      loadingRota = true;
      showWelcome = false;
    });

    try {
      if (employeeName == null || employeeLastName == null) {
        await _fetchEmployeeInfo();
        if (employeeName == null || employeeLastName == null) {
          throw Exception("Employee info not available");
        }
      }

      if (showWelcome) {
        _welcomeController.forward();
        Timer(const Duration(seconds: 3), () {
          if (mounted) setState(() => showWelcome = false);
        });
      }

      final rotaResponse = await http.get(
        Uri.parse("${AuthService.baseUrl}/rota?db=${currentDb.dbName}&name=$employeeName&lastName=$employeeLastName"),
      );

      if (rotaResponse.statusCode != 200) throw Exception("Failed to fetch rota");
      final List<dynamic> rotaList = jsonDecode(rotaResponse.body);

      List<Map<String, dynamic>> entries = rotaList.map<Map<String, dynamic>>((e) {
        String formatTime(String t) {
          if (t.isEmpty) return '';
          try {
            if (t.contains(':')) {
              final parts = t.split(':');
              if (parts.length >= 2) {
                return '${parts[0].padLeft(2, '0')}:${parts[1].padLeft(2, '0')}';
              }
            }
            return t;
          } catch (_) {
            return t;
          }
        }

        return {
          "id": e['id'],
          "name": e['name'] ?? '',
          "lastName": e['lastName'] ?? '',
          "day": e['day'] ?? '',
          "startTime": formatTime(e['start_time'] ?? e['startTime'] ?? ''),
          "endTime": formatTime(e['end_time'] ?? e['endTime'] ?? ''),
        };
      }).toList();

      final mappedRotaData = _mapWeekRota(entries);
      
      final now = DateTime.now();
      final today = DateFormat('dd/MM/yyyy').format(now);
      
      bool hasShiftToday = false;
      for (var dayData in mappedRotaData) {
        if (dayData['date'] == today) {
          final entries = List<Map<String, dynamic>>.from(dayData['entries']);
          hasShiftToday = entries.any((entry) => 
              (entry['startTime']?.isNotEmpty == true && entry['endTime']?.isNotEmpty == true));
          break;
        }
      }
      
      setState(() {
        rotaData = mappedRotaData;
        hasScheduledShiftToday = hasShiftToday;
      });
      
    } catch (e) {
      print("Error fetching rota: $e");
    } finally {
      if (mounted) setState(() => loadingRota = false);
    }
  }

  Future<TimeOfDay?> _showTimePicker(BuildContext context, String initialTime) async {
    TimeOfDay initialTimeOfDay;
    
    if (initialTime.isNotEmpty) {
      final parts = initialTime.split(':');
      if (parts.length >= 2) {
        initialTimeOfDay = TimeOfDay(
          hour: int.parse(parts[0]),
          minute: int.parse(parts[1]),
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
              timePickerTheme: TimePickerThemeData(
                backgroundColor: const Color(0xFF172A45),
                dialBackgroundColor: const Color(0xFF1E3A5F),
                dialTextColor: Colors.white,
                entryModeIconColor: const Color(0xFF4CC9F0),
                hourMinuteColor: const Color(0xFF1E3A5F),
                hourMinuteTextColor: Colors.white,
                dayPeriodColor: const Color(0xFF1E3A5F),
                dayPeriodTextColor: Colors.white,
                dialHandColor: const Color(0xFF4CC9F0),
              ),
            ),
            child: child!,
          ),
        );
      },
    );
    
    return picked;
  }

  void _showEnterTimesDialog() {
    final now = DateTime.now();
    final today = DateFormat('dd/MM/yyyy').format(now);
    final dayName = DateFormat('EEEE').format(now);
    final displayDate = '$today ($dayName)';
    
    final todayRotaEntries = _getTodaysRotaEntries();
    
    List<TextEditingController> startControllers = [];
    List<TextEditingController> endControllers = [];
    List<int?> entryIds = [];
    
    if (todayRotaEntries.isEmpty) {
      for (int i = 0; i < 2; i++) {
        startControllers.add(TextEditingController());
        endControllers.add(TextEditingController());
        entryIds.add(null);
      }
    } else {
      for (int i = 0; i < 2; i++) {
        if (i < todayRotaEntries.length) {
          startControllers.add(TextEditingController(text: todayRotaEntries[i]['startTime'] ?? ''));
          endControllers.add(TextEditingController(text: todayRotaEntries[i]['endTime'] ?? ''));
          entryIds.add(todayRotaEntries[i]['id']);
        } else {
          startControllers.add(TextEditingController());
          endControllers.add(TextEditingController());
          entryIds.add(null);
        }
      }
    }
    
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) {
          return AlertDialog(
            backgroundColor: const Color(0xFF172A45),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
              side: BorderSide(color: Colors.white.withOpacity(0.1), width: 1),
            ),
            title: Text(
              "Update Scheduled Hours",
              style: TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.bold,
              ),
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    "Today: $displayDate",
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.8),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    "Enter your scheduled work periods",
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.6),
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 24),
                  
                  for (int i = 0; i < 2; i++)
                    Column(
                      children: [
                        if (i > 0) const SizedBox(height: 20),
                        
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              i == 0 ? "First Work Period" : "Second Work Period",
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: i == 0 ? Color(0xFF4CC9F0) : Color(0xFF4ADE80),
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
                                      title: Text(
                                        "Delete Schedule?",
                                        style: TextStyle(color: Colors.white),
                                      ),
                                      content: Text(
                                        "Are you sure you want to delete this scheduled period?",
                                        style: TextStyle(color: Colors.white.withOpacity(0.8)),
                                      ),
                                      actions: [
                                        TextButton(
                                          onPressed: () => Navigator.pop(context),
                                          child: Text(
                                            "Cancel",
                                            style: TextStyle(color: const Color(0xFF4CC9F0)),
                                          ),
                                        ),
                                        TextButton(
                                          onPressed: () async {
                                            try {
                                              await _deleteRotaEntry(entryIds[i]!);
                                              startControllers[i].clear();
                                              endControllers[i].clear();
                                              entryIds[i] = null;
                                              
                                              ScaffoldMessenger.of(context).showSnackBar(
                                                SnackBar(
                                                  content: Text("Schedule deleted successfully!"),
                                                  backgroundColor: Colors.green,
                                                ),
                                              );
                                              
                                              Navigator.pop(context);
                                              setState(() {});
                                              
                                            } catch (e) {
                                              Navigator.pop(context);
                                              ScaffoldMessenger.of(context).showSnackBar(
                                                SnackBar(
                                                  content: Text("Error deleting schedule: $e"),
                                                  backgroundColor: Colors.red,
                                                ),
                                              );
                                            }
                                          },
                                          child: Text(
                                            "Delete",
                                            style: TextStyle(color: Colors.red[300]),
                                          ),
                                        ),
                                      ],
                                    ),
                                  );
                                },
                              ),
                          ],
                        ),
                        
                        if (i == 1)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Text(
                              "(Break time is automatically calculated as the gap between periods)",
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.white.withOpacity(0.5),
                                fontStyle: FontStyle.italic,
                              ),
                            ),
                          ),
                        
                        _TimeInputField(
                          controller: startControllers[i],
                          label: i == 0 ? 'Start Time (First Period)' : 'Start Time (Second Period)',
                          onTap: () async {
                            final picked = await _showTimePicker(context, startControllers[i].text);
                            if (picked != null) {
                              startControllers[i].text = 
                                '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}';
                              setState(() {});
                            }
                          },
                        ),
                        const SizedBox(height: 16),
                        _TimeInputField(
                          controller: endControllers[i],
                          label: i == 0 ? 'End Time (First Period)' : 'End Time (Second Period)',
                          onTap: () async {
                            final picked = await _showTimePicker(context, endControllers[i].text);
                            if (picked != null) {
                              endControllers[i].text = 
                                '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}';
                              setState(() {});
                            }
                          },
                        ),
                      ],
                    ),
                  
                  const SizedBox(height: 24),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.05),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.white.withOpacity(0.1)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.info_outline, color: Color(0xFF4CC9F0), size: 20),
                            const SizedBox(width: 8),
                            Text(
                              "Important Notes:",
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF4CC9F0),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          "• Overnight shifts allowed (e.g., 23:30 - 00:30)\n"
                          "• Enter up to 2 work periods per day\n"
                          "• Break time is the gap between periods (calculated automatically)\n"
                          "• Leave second period empty if you only work one shift\n"
                          "• Manager will review and confirm these hours",
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.7),
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(
                  "Cancel",
                  style: TextStyle(color: Color(0xFF4CC9F0)),
                ),
              ),
              ElevatedButton(
                onPressed: () async {
                  List<Map<String, dynamic>> workPeriods = [];
                  
                  for (int i = 0; i < 2; i++) {
                    final startTime = startControllers[i].text.trim();
                    final endTime = endControllers[i].text.trim();
                    
                    if (startTime.isEmpty && endTime.isEmpty) continue;
                    
                    if (startTime.isEmpty || endTime.isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text("Please enter both times for ${i == 0 ? 'First Work Period' : 'Second Work Period'} or leave both empty")),
                      );
                      return;
                    }
                    
                    final timeRegex = RegExp(r'^([0-1]?[0-9]|2[0-3]):[0-5][0-9]$');
                    if (!timeRegex.hasMatch(startTime) || !timeRegex.hasMatch(endTime)) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text("Times must be in HH:mm format (24-hour clock) for ${i == 0 ? 'First Work Period' : 'Second Work Period'}")),
                      );
                      return;
                    }
                    
                    workPeriods.add({
                      'id': entryIds[i],
                      'startTime': startTime,
                      'endTime': endTime,
                    });
                  }
                  
                  bool hasAnyPeriods = workPeriods.isNotEmpty;
                  bool allPeriodsEmpty = startControllers[0].text.trim().isEmpty && 
                                        endControllers[0].text.trim().isEmpty &&
                                        startControllers[1].text.trim().isEmpty && 
                                        endControllers[1].text.trim().isEmpty;
                  
                  if (!hasAnyPeriods && !allPeriodsEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text("Please enter both start and end times for each period or leave both empty")),
                    );
                    return;
                  }
                  
                  await _saveRotaShifts(workPeriods);
                  Navigator.pop(context);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Color(0xFF4CC9F0),
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

  List<Map<String, dynamic>> _getTodaysRotaEntries() {
    final now = DateTime.now();
    final today = DateFormat('dd/MM/yyyy').format(now);
    
    for (var dayData in rotaData) {
      if (dayData['date'] == today) {
        final entries = List<Map<String, dynamic>>.from(dayData['entries']);
        return entries
            .where((entry) => (entry['startTime']?.isNotEmpty == true || 
                               entry['endTime']?.isNotEmpty == true))
            .toList();
      }
    }
    return [];
  }

  Future<void> _saveRotaShifts(List<Map<String, dynamic>> timeFrames) async {
    final now = DateTime.now();
    final today = DateFormat('dd/MM/yyyy').format(now);
    final dayName = DateFormat('EEEE').format(now);
    final formattedDay = '$today ($dayName)';
    
    try {
      List<int> keptEntryIds = [];
      
      for (int i = 0; i < timeFrames.length; i++) {
        final frame = timeFrames[i];
        final startTime = frame['startTime'];
        final endTime = frame['endTime'];
        final entryId = frame['id'];
        
        if (startTime == null || endTime == null || startTime.isEmpty || endTime.isEmpty) {
          continue;
        }
        
        final requestBody = {
          'db': currentDb.dbName,
          'name': employeeName,
          'lastName': employeeLastName,
          'employeeId': employeeId,
          'day': formattedDay,
          'startTime': startTime,
          'endTime': endTime,
          'wage': employeeWage?.toString() ?? '0.00',
          'designation': employeeDesignation ?? '',
        };
        
        if (entryId != null) {
          requestBody['entryId'] = entryId;
          keptEntryIds.add(entryId);
        }
        
        final response = await http.post(
          Uri.parse("${AuthService.baseUrl}/save-shift"),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode(requestBody),
        );
        
        final responseBody = response.body;
        if (responseBody.trim().startsWith('<!DOCTYPE html>')) {
          throw Exception("Server returned HTML error page.");
        }
        
        final data = jsonDecode(responseBody);
        
        if (response.statusCode != 200 || data['success'] != true) {
          throw Exception("Failed to save shift: ${data['message']}");
        }
        
        if (entryId == null && data.containsKey('entryId')) {
          keptEntryIds.add(data['entryId']);
        }
      }
      
      final existingEntries = _getTodaysRotaEntries();
      
      for (var entry in existingEntries) {
        final entryId = entry['id'];
        if (entryId != null && !keptEntryIds.contains(entryId)) {
          await _deleteRotaEntry(entryId);
        }
      }
      
      if (timeFrames.isNotEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Schedule updated successfully!"),
            backgroundColor: Colors.green,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("All shifts cleared for today!"),
            backgroundColor: Colors.blue,
          ),
        );
      }
      
      setState(() {
        hasScheduledShiftToday = timeFrames.isNotEmpty;
        showClockInReminder = false;
      });
      
      final todayStr = DateFormat('dd/MM/yyyy').format(DateTime.now());
      _storeReminderPrefs(null, todayStr);
      
      await fetchRota();
      await fetchTodayShifts();
      
    } catch (e) {
      print("Error saving rota shifts: $e");
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Error saving schedule: ${e.toString()}"),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _deleteRotaEntry(int entryId) async {
    try {
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
        throw Exception("Server returned HTML error page. Check backend API endpoint.");
      }
      
      final data = jsonDecode(responseBody);
      print("Delete rota entry response: $data");
      
      if (response.statusCode != 200 || data['success'] != true) {
        throw Exception("Failed to delete shift: ${data['message']}");
      }
      
    } catch (e) {
      print("Error deleting rota entry: $e");
      rethrow;
    }
  }

  Widget _buildClockInReminder() {
    if (!showClockInReminder || hasScheduledShiftToday) return const SizedBox();
    
    return Container(
      padding: const EdgeInsets.all(16),
      margin: const EdgeInsets.only(bottom: 20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Color(0xFF4CC9F0).withOpacity(0.15),
            Color(0xFF4ADE80).withOpacity(0.15),
          ],
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Color(0xFF4CC9F0).withOpacity(0.3)),
      ),
      child: Row(
        children: [
          Icon(Icons.notifications_active, color: Color(0xFF4CC9F0)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "No Shift Scheduled Today",
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  "You don't have any scheduled hours for today.",
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.white.withOpacity(0.7),
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: Icon(Icons.close, color: Color(0xFF4CC9F0)),
            onPressed: () {
              setState(() {
                showClockInReminder = false;
              });
              final today = DateFormat('dd/MM/yyyy').format(DateTime.now());
              _storeReminderPrefs(today, null);
            },
          ),
        ],
      ),
    );
  }

  Widget _buildScheduleSection() {
    final now = DateTime.now();
    final today = DateFormat('dd/MM/yyyy').format(now);
    final dayName = DateFormat('EEEE').format(now);
    final displayDate = '$today ($dayName)';
    
    final todaysRotaEntries = _getTodaysRotaEntries();
    
    bool hasScheduledShiftsToday = false;
    String todayRotaDate = DateFormat('dd/MM/yyyy').format(now);
    
    for (var dayData in rotaData) {
      if (dayData['date'] == todayRotaDate) {
        final entries = List<Map<String, dynamic>>.from(dayData['entries']);
        hasScheduledShiftsToday = entries.any((entry) => 
            (entry['startTime']?.isNotEmpty == true && entry['endTime']?.isNotEmpty == true));
        break;
      }
    }
    
    if (!hasScheduledShiftsToday) {
      return Card(
        margin: const EdgeInsets.only(bottom: 20),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color(0xFF1E3A5F).withOpacity(0.9),
                Color(0xFF0A192F).withOpacity(0.9),
              ],
            ),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white.withOpacity(0.1)),
          ),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                Icon(
                  Icons.beach_access,
                  size: 48,
                  color: Colors.white.withOpacity(0.5),
                ),
                const SizedBox(height: 16),
                Text(
                  "No Shift Scheduled Today",
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  displayDate,
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.7),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  "You don't have any scheduled hours for today.\nCheck your weekly rota below or contact your manager.",
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.6),
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    } else {
      return Card(
        elevation: 0,
        margin: const EdgeInsets.only(bottom: 20),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color(0xFF1E3A5F).withOpacity(0.9),
                Color(0xFF0A192F).withOpacity(0.9),
              ],
            ),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white.withOpacity(0.1)),
          ),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      "Today's Schedule",
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        displayDate,
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.8),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                
                if (todaysRotaEntries.isNotEmpty)
                  for (int i = 0; i < todaysRotaEntries.length; i++)
                    Column(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(12),
                          margin: const EdgeInsets.only(bottom: 8),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.05),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: i == 0 
                                  ? Color(0xFF4CC9F0).withOpacity(0.3)
                                  : Color(0xFF4ADE80).withOpacity(0.3),
                            ),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 36,
                                height: 36,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: i == 0 
                                      ? Color(0xFF4CC9F0).withOpacity(0.2)
                                      : Color(0xFF4ADE80).withOpacity(0.2),
                                ),
                                child: Icon(
                                  Icons.schedule,
                                  size: 18,
                                  color: i == 0 ? Color(0xFF4CC9F0) : Color(0xFF4ADE80),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      i == 0 ? "First Period" : "Second Period",
                                      style: TextStyle(
                                        fontSize: 14,
                                        color: Colors.white.withOpacity(0.6),
                                      ),
                                    ),
                                    Text(
                                      "${todaysRotaEntries[i]['startTime']} - ${todaysRotaEntries[i]['endTime']}",
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (i < todaysRotaEntries.length - 1) const SizedBox(height: 8),
                      ],
                    ),
                
                const SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.05),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              "Total Hours:",
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.7),
                              ),
                            ),
                            Text(
                              _calculateRotaHours(todaysRotaEntries),
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF4CC9F0),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    if (employeeWage != null && employeeWage! > 0)
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.05),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                "Est. Earnings:",
                                style: TextStyle(
                                  color: Colors.white.withOpacity(0.7),
                                ),
                              ),
                              Text(
                                "£${_calculateRotaEarnings(todaysRotaEntries).toStringAsFixed(2)}",
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF4ADE80),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 20),
                ElevatedButton.icon(
                  onPressed: _showEnterTimesDialog,
                  icon: Icon(Icons.edit, size: 20),
                  label: Text("Edit Schedule"),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Color(0xFF4CC9F0),
                    foregroundColor: Colors.white,
                    minimumSize: const Size(double.infinity, 48),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }
  }

  String _calculateRotaHours(List<Map<String, dynamic>> rotaEntries) {
    double totalMinutes = 0;
    int validEntriesCount = 0;
    
    for (var entry in rotaEntries) {
      final startTime = entry['startTime']?.toString().trim() ?? '';
      final endTime = entry['endTime']?.toString().trim() ?? '';
      
      if (startTime.isEmpty || endTime.isEmpty) {
        continue;
      }
      
      final formattedStartTime = _ensureHHmmFormat(startTime);
      final formattedEndTime = _ensureHHmmFormat(endTime);
      
      try {
        final startParts = formattedStartTime.split(':');
        final endParts = formattedEndTime.split(':');
        
        if (startParts.length < 2 || endParts.length < 2) {
          continue;
        }
        
        final startHour = int.tryParse(startParts[0]) ?? 0;
        final startMin = int.tryParse(startParts[1]) ?? 0;
        final endHour = int.tryParse(endParts[0]) ?? 0;
        final endMin = int.tryParse(endParts[1]) ?? 0;
        
        if (startHour < 0 || startHour > 23 || startMin < 0 || startMin > 59 ||
            endHour < 0 || endHour > 23 || endMin < 0 || endMin > 59) {
          continue;
        }
        
        int startTotal = startHour * 60 + startMin;
        int endTotal = endHour * 60 + endMin;
        
        if (endTotal < startTotal) {
          endTotal += 24 * 60;
        }
        
        final duration = endTotal - startTotal;
        if (duration > 0) {
          totalMinutes += duration;
          validEntriesCount++;
        }
      } catch (e) {
        print("Error calculating hours for entry: $e");
      }
    }
    
    if (validEntriesCount == 0) {
      return '-';
    }
    
    final hours = totalMinutes ~/ 60;
    final minutes = (totalMinutes % 60).toInt();
    
    if (minutes > 0) {
      return '${hours}h ${minutes}m';
    } else {
      return '${hours}h';
    }
  }

  double _calculateRotaEarnings(List<Map<String, dynamic>> rotaEntries) {
    if (employeeWage == null || employeeWage == 0) return 0.0;
    
    double totalMinutes = 0;
    
    for (var entry in rotaEntries) {
      final startTime = entry['startTime'] ?? '';
      final endTime = entry['endTime'] ?? '';
      
      if (startTime.isNotEmpty && endTime.isNotEmpty) {
        try {
          final startParts = startTime.split(':');
          final endParts = endTime.split(':');
          
          final startHour = int.parse(startParts[0]);
          final startMin = int.parse(startParts[1]);
          final endHour = int.parse(endParts[0]);
          final endMin = int.parse(endParts[1]);
          
          int startTotal = startHour * 60 + startMin;
          int endTotal = endHour * 60 + endMin;
          
          if (endTotal < startTotal) {
            endTotal += 24 * 60;
          }
          
          totalMinutes += (endTotal - startTotal);
        } catch (_) {}
      }
    }
    
    final totalHours = totalMinutes / 60.0;
    return totalHours * employeeWage!;
  }

  @override
  void dispose() {
    _timer.cancel();
    _dateCheckTimer.cancel();
    _welcomeController.dispose();
    super.dispose();
  }

  @override
Widget build(BuildContext context) {
  final userName = employeeName ?? 'User';

  final welcomeMessage = widget.databases.length > 1
      ? "Welcome back, $userName! You're in ${currentDb.dbName} workspace."
      : "Welcome back, $userName! Your Solura workspace awaits.";

  final role = (Session.role ?? "").trim().toLowerCase();
  final isManagerOrAm = role == "manager" || role == "am";

  return Scaffold(
    backgroundColor: const Color(0xFF0A192F),

    // ✅ CLEAN DRAWER: removed Notifications / Hours Summary / Rota
    // ✅ Added Requests (only AM/Manager)
    drawer: Drawer(
      backgroundColor: const Color(0xFF0A192F),
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          DrawerHeader(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Color(0xFF1E3A5F),
                  Color(0xFF0A192F),
                ],
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  backgroundColor: const Color(0xFF4CC9F0),
                  radius: 30,
                  child: Text(
                    userName.substring(0, 1).toUpperCase(),
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Solura Dashboard',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  widget.email,
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.7),
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  "Role: ${Session.role ?? '-'}",
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.5),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),

          if (isManagerOrAm)
            _DrawerTile(
              icon: Icons.assignment,
              title: "Requests",
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    // ✅ create this screen: HolidayRequestsScreen
                    builder: (_) => HolidayRequestsScreen(
                      selectedDb: currentDb,
                      role: Session.role ?? "",
                    ),

                  ),
                );
              },
            ),

          _DrawerTile(
            icon: Icons.bar_chart,
            title: 'Reports',
            onTap: () {},
          ),
          _DrawerTile(
            icon: Icons.settings,
            title: 'Settings',
            onTap: () {},
          ),

          const Divider(color: Color(0xFF1E3A5F)),

          _DrawerTile(
            icon: Icons.logout,
            title: 'Logout',
            color: Colors.red[300],
            onTap: () async {
              await Session.clear();
              if (!mounted) return;
              Navigator.of(context).popUntil((route) => route.isFirst);
            },
          ),
        ],
      ),
    ),

        appBar: AppBar(
      backgroundColor: const Color(0xFF172A45),
      elevation: 0,
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "Dashboard",
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            DateFormat('EEEE, MMMM dd').format(DateTime.now()),
            style: TextStyle(
              fontSize: 14,
              color: Colors.white.withOpacity(0.7),
            ),
          ),
        ],
      ),
      actions: [
        // ✅ Notification bell is BACK
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
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
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

        // ✅ DB selector ALWAYS shown
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: DropdownButton<DatabaseAccess>(
            value: currentDb,
            dropdownColor: const Color(0xFF1E3A5F),
            underline: const SizedBox(),
            icon: const Icon(Icons.arrow_drop_down, color: Color(0xFF4CC9F0), size: 20),
            style: const TextStyle(fontSize: 14, color: Colors.white),
            items: _dbOptions.map((db) {
              return DropdownMenuItem(
                value: db,
                child: Text(db.dbName, style: const TextStyle(color: Colors.white)),
              );
            }).toList(),
            onChanged: (db) async {
              if (db != null) await switchDatabase(db);
            },
          ),
        ),

        IconButton(
          icon: const Icon(Icons.refresh, color: Color(0xFF4CC9F0)),
          onPressed: () async {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text("Refreshing data..."),
                backgroundColor: Color(0xFF4CC9F0),
              ),
            );
            await _initializeData();
          },
          tooltip: 'Refresh data',
        ),
      ],
    ),


    body: Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color(0xFF0A192F),
            Color(0xFF172A45),
            Color(0xFF0A192F),
          ],
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: SingleChildScrollView(
          child: Column(
            children: [
              if (showWelcome && employeeName != null)
                FadeTransition(
                  opacity: _welcomeAnimation,
                  child: Container(
                    padding: const EdgeInsets.all(20),
                    margin: const EdgeInsets.only(bottom: 20),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [
                          Color(0xFF4CC9F0),
                          Color(0xFF1E3A5F),
                        ],
                      ),
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.3),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 40,
                          height: 40,
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.white,
                          ),
                          child: const Icon(
                            Icons.person,
                            color: Color(0xFF4CC9F0),
                            size: 24,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Text(
                            welcomeMessage,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

              _buildClockInReminder(),

              if (loadingTodayShifts)
                Container(
                  padding: const EdgeInsets.all(40),
                  child: const Column(
                    children: [
                      CircularProgressIndicator(color: Color(0xFF4CC9F0)),
                      SizedBox(height: 16),
                      Text(
                        "Loading schedule...",
                        style: TextStyle(color: Colors.white),
                      ),
                    ],
                  ),
                )
              else
                _buildScheduleSection(),

              Container(
                padding: const EdgeInsets.all(16),
                margin: const EdgeInsets.only(bottom: 20, top: 4),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.white.withOpacity(0.1)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      "📅 Weekly Rota Schedule",
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    const Icon(
                      Icons.calendar_today,
                      color: Color(0xFF4CC9F0),
                    ),
                  ],
                ),
              ),

              loadingRota
                  ? Container(
                      padding: const EdgeInsets.all(40),
                      child: const Column(
                        children: [
                          CircularProgressIndicator(color: Color(0xFF4CC9F0)),
                          SizedBox(height: 16),
                          Text(
                            "Loading rota data...",
                            style: TextStyle(color: Colors.white),
                          ),
                        ],
                      ),
                    )
                  : rotaData.isEmpty
                      ? Container(
                          padding: const EdgeInsets.all(40),
                          child: Column(
                            children: [
                              Icon(
                                Icons.schedule,
                                size: 64,
                                color: Colors.white.withOpacity(0.3),
                              ),
                              const SizedBox(height: 16),
                              Text(
                                "No rota entries found",
                                style: TextStyle(
                                  color: Colors.white.withOpacity(0.7),
                                  fontSize: 16,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                "Check back later or contact your manager",
                                style: TextStyle(
                                  color: Colors.white.withOpacity(0.5),
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        )
                      : Container(
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.03),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: Colors.white.withOpacity(0.1)),
                          ),
                          child: SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: ConstrainedBox(
                              constraints: BoxConstraints(
                                minWidth: MediaQuery.of(context).size.width - 32,
                              ),
                              child: DataTable(
                                headingRowColor: MaterialStateProperty.all(
                                  Colors.white.withOpacity(0.05),
                                ),
                                headingTextStyle: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                ),
                                dataRowHeight: 50,
                                columnSpacing: 24,
                                horizontalMargin: 16,
                                columns: const [
                                  DataColumn(label: Text("Day"), numeric: false),
                                  DataColumn(label: Text("Time Frames"), numeric: false),
                                  DataColumn(label: Text("Hours"), numeric: false),
                                ],
                                rows: _buildRotaTableRows(),
                              ),
                            ),
                          ),
                        ),
            ],
          ),
        ),
      ),
    ),

    bottomNavigationBar: _buildBottomNavigationBar(),
  );
} 

  Widget _buildBottomNavigationBar() {
    return Container(
      height: 70,
      decoration: BoxDecoration(
        color: const Color(0xFF172A45),
        border: Border(
          top: BorderSide(
            color: Colors.white.withOpacity(0.1),
            width: 1,
          ),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          // Hours Summary Button (left)
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
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text("Employee info not loaded yet")),
                );
              }
            },
          ),
          
          // Rota Button (left-middle)
          _buildNavButton(
            icon: Icons.calendar_today,
            label: 'Rota',
            onTap: () {
              Navigator.push(
                context,
                PageRouteBuilder(
                  pageBuilder: (context, animation, secondaryAnimation) => AllRotaScreen(
                    email: widget.email,
                    selectedDb: currentDb,
                  ),
                  transitionsBuilder: (context, animation, secondaryAnimation, child) {
                    const begin = Offset(1.0, 0.0);
                    const end = Offset.zero;
                    const curve = Curves.easeInOut;
                    var tween = Tween(begin: begin, end: end).chain(CurveTween(curve: curve));
                    return SlideTransition(
                      position: animation.drive(tween),
                      child: child,
                    );
                  },
                ),
              );
            },
          ),
          
          // Home Button (center) - larger
          _buildHomeButton(),
          
          // Holidays Button (right-middle)
          _buildNavButton(
            icon: Icons.beach_access,
            label: 'Holidays',
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => HolidaysScreen(
                    email: widget.email,
                    selectedDb: currentDb,
                  ),
                ),
              );
            },
          ),
          
          // Earnings Button (right)
          _buildNavButton(
            icon: Icons.attach_money,
            label: 'Earnings',
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => EarningsScreen(
                    email: widget.email,
                    selectedDb: currentDb,
                  ),
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
                Icon(
                  icon,
                  color: Colors.white.withOpacity(0.7),
                  size: 24,
                ),
                const SizedBox(height: 4),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.white.withOpacity(0.7),
                  ),
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
                colors: [
                  Color(0xFF4CC9F0),
                  Color(0xFF1E3A5F),
                ],
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.3),
                  blurRadius: 8,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: IconButton(
              icon: const Icon(Icons.home, size: 28),
              color: Colors.white,
              onPressed: () {
                Navigator.of(context).popUntil((route) => route.isFirst);
              },
            ),
          ),
          const SizedBox(height: 2),
          Text(
            'Home',
            style: TextStyle(
              fontSize: 12,
              color: Colors.white.withOpacity(0.7),
            ),
          ),
        ],
      ),
    );
  }

  List<DataRow> _buildRotaTableRows() {
    return rotaData.asMap().entries.map((entry) {
      final index = entry.key;
      final dayData = entry.value;
      final dateStr = dayData['date'];
      final entries = List<Map<String, dynamic>>.from(dayData['entries']);
      final now = DateTime.now();
      final today = DateFormat('dd/MM/yyyy').format(now);
      final isToday = dateStr == today;
      
      double totalMinutes = 0;
      String hoursText = '-';
      
      if (entries.isNotEmpty && entries[0]['startTime'].isNotEmpty && entries[0]['endTime'].isNotEmpty) {
        for (var entry in entries) {
          final startTime = entry['startTime'] ?? '';
          final endTime = entry['endTime'] ?? '';
          
          if (startTime.isNotEmpty && endTime.isNotEmpty) {
            try {
              final startParts = startTime.split(':');
              final endParts = endTime.split(':');
              
              final startHour = int.parse(startParts[0]);
              final startMin = int.parse(startParts[1]);
              final endHour = int.parse(endParts[0]);
              final endMin = int.parse(endParts[1]);
              
              int startTotal = startHour * 60 + startMin;
              int endTotal = endHour * 60 + endMin;
              
              if (endTotal < startTotal) {
                endTotal += 24 * 60;
              }
              
              totalMinutes += (endTotal - startTotal);
            } catch (_) {}
          }
        }
        
        final hours = totalMinutes ~/ 60;
        final minutes = (totalMinutes % 60).toInt();
        hoursText = minutes > 0 ? '${hours}h ${minutes}m' : '${hours}h';
      }
      
      String timeFramesText = '';
      for (var entry in entries) {
        final startTime = entry['startTime'] ?? '';
        final endTime = entry['endTime'] ?? '';
        
        if (startTime.isNotEmpty && endTime.isNotEmpty) {
          if (timeFramesText.isNotEmpty) {
            timeFramesText += '\n';
          }
          timeFramesText += '$startTime - $endTime';
        }
      }
      
      if (timeFramesText.isEmpty) {
        timeFramesText = 'No shift';
      }
      
      return DataRow(
        color: MaterialStateProperty.resolveWith<Color?>(
          (Set<MaterialState> states) {
            if (isToday) return Color(0xFF4CC9F0).withOpacity(0.1);
            return index.isEven 
                ? Colors.white.withOpacity(0.02)
                : Colors.white.withOpacity(0.05);
          },
        ),
        cells: [
          DataCell(
            Row(
              children: [
                if (isToday)
                  Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: Color(0xFF4ADE80),
                    ),
                  ),
                if (isToday) const SizedBox(width: 8),
                Text(
                  dateStr,
                  style: TextStyle(
                    color: isToday ? Color(0xFF4ADE80) : Colors.white.withOpacity(0.8),
                    fontWeight: isToday ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
              ],
            ),
          ),
          DataCell(
            Text(
              timeFramesText,
              style: TextStyle(
                color: isToday ? Color(0xFF4CC9F0) : Colors.white.withOpacity(0.7),
                fontWeight: isToday ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ),
          DataCell(
            Text(
              hoursText,
              style: TextStyle(
                color: isToday ? Color(0xFF4ADE80) : Colors.white.withOpacity(0.7),
                fontWeight: isToday ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ),
        ],
      );
    }).toList();
  }
}

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
      leading: Icon(
        icon,
        color: color ?? Colors.white.withOpacity(0.8),
      ),
      title: Text(
        title,
        style: TextStyle(
          color: color ?? Colors.white.withOpacity(0.8),
        ),
      ),
      onTap: onTap,
      hoverColor: Colors.white.withOpacity(0.05),
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
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.white.withOpacity(0.5),
                    ),
                  ),
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
            Icon(
              Icons.access_time,
              color: Color(0xFF4CC9F0),
            ),
          ],
        ),
      ),
    );
  }
}