// lib/screens/shift_requests_screen.dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/database_access.dart';
import '../services/rota_service.dart';
import '../services/notifications_service.dart';

class ShiftRequestsScreen extends StatefulWidget {
  final DatabaseAccess selectedDb;
  final String userEmail;
  final String userName;
  final String userDesignation;
  final int initialTab; // 0 = requests, 1 = missing shifts (only for AM/Manager)

  const ShiftRequestsScreen({
    super.key,
    required this.selectedDb,
    required this.userEmail,
    required this.userName,
    required this.userDesignation,
    this.initialTab = 0,
  });

  @override
  State<ShiftRequestsScreen> createState() => _ShiftRequestsScreenState();
}

class _ShiftRequestsScreenState extends State<ShiftRequestsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final RotaService _rotaService = RotaService();

  // Request tab data
  bool _loading = true;
  List<Map<String, dynamic>> _requests = [];
  List<Map<String, dynamic>> _allRequests = [];
  final Map<String, List<Map<String, dynamic>>> _myRotaCache = {};

  // Missing shifts tab data (only for AM/Manager)
  List<Map<String, dynamic>> _missingShifts = [];
  DateTime _selectedDate = DateTime.now();
  bool _loadingMissing = false;
  Set<String> _sendingReminder = {};

  bool get _canManageShifts {
    final role = widget.selectedDb.access.trim().toLowerCase();
    return role == "am" || role == "manager" || role == "admin";
  }

  @override
  void initState() {
    super.initState();
    final tabCount = _canManageShifts ? 2 : 1;
    _tabController = TabController(
      length: tabCount,
      vsync: this,
      initialIndex: widget.initialTab.clamp(0, tabCount - 1),
    );
    
    // Add this listener to force rebuild when tab changes
    _tabController.addListener(() {
      if (mounted) {
        setState(() {}); // Force rebuild to show/hide FAB based on tab index
      }
    });
    
    _loadRequests();
    if (_canManageShifts && widget.initialTab == 1) {
      _fetchMissingShifts();
    }
    _tabController.addListener(() {
      if (_tabController.indexIsChanging && _tabController.index == 1) {
        _fetchMissingShifts();
      }
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  // ----------------------------------------------------------------------
  // Shift Requests tab logic
  // ----------------------------------------------------------------------
  String _norm(String v) => v.trim().toLowerCase();

  bool _shouldShowToUserByDesignation(String neededForRaw) {
    final need = _norm(neededForRaw.isEmpty ? "anyone" : neededForRaw);
    final des = _norm(widget.userDesignation);
    if (need == "anyone") return true;
    if (need == "foh") return des == "foh";
    if (need == "boh") return des == "boh";
    return true;
  }

  int _timeToMinutes(String hhmmss) {
    final t = hhmmss.trim();
    if (t.isEmpty) return 0;
    final parts = t.split(':');
    if (parts.length < 2) return 0;
    final hh = int.tryParse(parts[0]) ?? 0;
    final mm = int.tryParse(parts[1]) ?? 0;
    return (hh * 60) + mm;
  }

  bool _overlaps(int aStart, int aEnd, int bStart, int bEnd) {
    if (aEnd <= aStart) aEnd += 24 * 60;
    if (bEnd <= bStart) bEnd += 24 * 60;
    bool baseOverlap = aStart < bEnd && bStart < aEnd;
    if (baseOverlap) return true;
    bool shiftB = aStart < (bEnd + 1440) && (bStart + 1440) < aEnd;
    if (shiftB) return true;
    bool shiftA = (aStart + 1440) < bEnd && bStart < (aEnd + 1440);
    return shiftA;
  }

  String? _dayLabelToDateKey(String dayLabel) {
    final raw = dayLabel.trim();
    if (raw.isEmpty) return null;
    final datePart = raw.split(' ').first.trim();
    final seg = datePart.split('/');
    if (seg.length != 3) return null;
    final dd = seg[0].padLeft(2, '0');
    final mm = seg[1].padLeft(2, '0');
    final yyyy = seg[2].padLeft(4, '0');
    return "$yyyy-$mm-$dd";
  }

  Future<void> _loadRequests() async {
    setState(() => _loading = true);

    try {
      final data = await _rotaService.fetchShiftRequests(
        db: widget.selectedDb.dbName,
        userEmail: widget.userEmail,
      );

      _allRequests = data;
      final filtered = await _applyFilters(data);

      if (!mounted) return;
      setState(() {
        _requests = filtered;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      _showSnackBar("Failed to load shift requests: $e", Colors.red);
    }
  }

  Future<List<Map<String, dynamic>>> _applyFilters(
      List<Map<String, dynamic>> items) async {
    final out = <Map<String, dynamic>>[];

    for (final r in items) {
      final neededFor = (r["needed_for"] ?? "anyone").toString();
      if (!_shouldShowToUserByDesignation(neededFor)) continue;

      final status = (r["status"] ?? "pending").toString().toLowerCase();
      final dayLabel = (r["day_label"] ?? "").toString();
      final dateKey = _dayLabelToDateKey(dayLabel);

      if (dateKey == null) {
        out.add(r);
        continue;
      }

      if (status == "pending") {
        final st = (r["start_time"] ?? "").toString();
        final et = (r["end_time"] ?? "").toString();
        final reqStart = _timeToMinutes(st);
        final reqEnd = _timeToMinutes(et);

        final myShifts = await _getMyRotaForDate(dateKey);
        final hasConflict = myShifts.any((s) {
          final sst = (s["startTime"] ?? s["start_time"] ?? "").toString();
          final set = (s["endTime"] ?? s["end_time"] ?? "").toString();
          final aStart = _timeToMinutes(sst);
          final aEnd = _timeToMinutes(set);
          return _overlaps(reqStart, reqEnd, aStart, aEnd);
        });

        if (hasConflict) continue;
      }

      out.add(r);
    }

    return out;
  }

  Future<List<Map<String, dynamic>>> _getMyRotaForDate(String dateKey) async {
    if (_myRotaCache.containsKey(dateKey)) {
      return _myRotaCache[dateKey]!;
    }

    final shifts = await _rotaService.fetchMyRotaForDay(
      db: widget.selectedDb.dbName,
      userEmail: widget.userEmail,
      dateYYYYMMDD: dateKey,
    );

    _myRotaCache[dateKey] = shifts;
    return shifts;
  }

  Future<void> _acceptShift(String id) async {
    try {
      final ok = await _rotaService.acceptShiftRequest(
        db: widget.selectedDb.dbName,
        id: id,
        userEmail: widget.userEmail,
      );

      if (!mounted) return;

      if (ok) {
        _showSnackBar("✅ Shift accepted", Colors.green);
        _myRotaCache.clear();
        await _loadRequests();

        await _sendPushNotification(
          targetRole: 'AM',
          title: '✅ Shift Accepted',
          message: '${widget.userName} has accepted a shift',
        );
      } else {
        _showSnackBar("❌ Failed to accept shift", Colors.red);
      }
    } catch (e) {
      _showSnackBar("❌ Error: $e", Colors.red);
    }
  }

  // ----------------------------------------------------------------------
  // Missing shifts tab logic (only for AM/Manager)
  // ----------------------------------------------------------------------
  Future<void> _fetchMissingShifts() async {
    if (!_canManageShifts) return;
    setState(() => _loadingMissing = true);
    try {
      final day = DateFormat('yyyy-MM-dd').format(_selectedDate);
      final missing = await _rotaService.fetchMissingPublished(
        db: widget.selectedDb.dbName,
        day: day,
      );
      if (mounted) {
        setState(() {
          _missingShifts = missing;
          _loadingMissing = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loadingMissing = false);
        _showSnackBar("Error loading missing shifts: $e", Colors.red);
      }
    }
  }

  Future<void> _pickMissingDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 30)),
    );
    if (picked != null && picked != _selectedDate) {
      setState(() => _selectedDate = picked);
      _fetchMissingShifts();
    }
  }

  Future<void> _sendReminderToEmployees() async {
    if (_missingShifts.isEmpty) {
      _showSnackBar("No missing shifts to remind", Colors.orange);
      return;
    }

    final emails = _missingShifts
        .where((m) => m['email'] != null && m['email'].toString().isNotEmpty)
        .map((m) => m['email'].toString())
        .toSet();

    if (emails.isEmpty) {
      _showSnackBar("No valid employee emails found", Colors.red);
      return;
    }

    setState(() => _sendingReminder.add('all'));

    int successCount = 0;
    for (final email in emails) {
      final sent = await _sendPushNotification(
        targetEmail: email,
        targetRole: 'EMPLOYEE',
        title: '⚠️ Shift Confirmation Reminder',
        message:
            'Please confirm your shifts for ${DateFormat('dd/MM/yyyy').format(_selectedDate)}',
      );
      if (sent) successCount++;
    }

    setState(() => _sendingReminder.remove('all'));

    if (successCount > 0) {
      _showSnackBar("✅ Reminder sent to $successCount employee(s)", Colors.green);
    } else {
      _showSnackBar("❌ Failed to send reminders", Colors.red);
    }
  }

  // ----------------------------------------------------------------------
  // Notification helper
  // ----------------------------------------------------------------------
  Future<bool> _sendPushNotification({
    required String targetRole,
    required String title,
    required String message,
    String? targetEmail,
  }) async {
    try {
      print('📱 Sending push notification: $title');
      print('   targetRole: $targetRole, targetEmail: $targetEmail');

      final success = await NotificationsService.sendPushNotification(
        db: widget.selectedDb.dbName,
        targetEmail: targetEmail ?? '',
        targetRole: targetRole,
        title: title,
        message: message,
        type: 'SYSTEM',
      );

      if (success) {
        print('✅ Push notification sent successfully');
      } else {
        print('⚠️ Push notification failed');
      }
      return success;
    } catch (e) {
      print('❌ Error sending push notification: $e');
      return false;
    }
  }

  void _showSnackBar(String message, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Color _statusColor(String status) {
    final s = status.toLowerCase();
    if (s == "accepted") return Colors.green;
    if (s == "cancelled") return Colors.red;
    return Colors.orange;
  }

  // ----------------------------------------------------------------------
  // Dialogs
  // ----------------------------------------------------------------------
  Future<void> _openCreateShiftRequestDialog() async {
    final created = await showDialog<bool>(
      context: context,
      builder: (_) => _CreateShiftRequestDialog(
        dbName: widget.selectedDb.dbName,
        userEmail: widget.userEmail,
        rotaService: _rotaService,
        onSendPushNotification: _sendPushNotification,
      ),
    );
    if (created == true) {
      _showSnackBar("✅ Shift request(s) created", Colors.green);
      await _loadRequests();
    }
  }

  Future<void> _openAddToRotaDialog() async {
    final created = await showDialog<bool>(
      context: context,
      builder: (_) => _AddToRotaDialog(
        dbName: widget.selectedDb.dbName,
        userEmail: widget.userEmail,
        rotaService: _rotaService,
        onSendPushNotification: _sendPushNotification,
      ),
    );
    if (created == true) {
      _showSnackBar("✅ Shift(s) added to rota", Colors.green);
    }
  }

  // ----------------------------------------------------------------------
  // Build UI
  // ----------------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A192F),
      appBar: AppBar(
        title: const Text("Shift Requests", style: TextStyle(color: Colors.white)),
        backgroundColor: const Color(0xFF172A45),
        bottom: TabBar(
          controller: _tabController,
          tabs: [
            const Tab(text: "Requests"),
            if (_canManageShifts) const Tab(text: "Missing Shifts"),
          ],
          indicatorColor: const Color(0xFF4CC9F0),
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white54,
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Color(0xFF4CC9F0)),
            onPressed: () {
              if (_tabController.index == 0) {
                _loadRequests();
              } else {
                _fetchMissingShifts();
              }
            },
          ),
        ],
      ),
      floatingActionButton: _canManageShifts && _tabController.index == 0
          ? Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                FloatingActionButton.extended(
                  onPressed: _openCreateShiftRequestDialog,
                  backgroundColor: const Color(0xFF4CC9F0),
                  foregroundColor: Colors.white,
                  icon: const Icon(Icons.add_alert),
                  label: const Text("Request"),
                  heroTag: "request",
                ),
                const SizedBox(height: 10),
                FloatingActionButton.extended(
                  onPressed: _openAddToRotaDialog,
                  backgroundColor: const Color(0xFF4ADE80),
                  foregroundColor: Colors.white,
                  icon: const Icon(Icons.add),
                  label: const Text("Add to Rota"),
                  heroTag: "add",
                ),
              ],
            )
          : null,
      body: TabBarView(
        controller: _tabController,
        children: [
          // Requests tab
          _buildRequestsTab(),
          // Missing shifts tab (only if can manage)
          if (_canManageShifts) _buildMissingShiftsTab(),
        ],
      ),
    );
  }

  Widget _buildRequestsTab() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: Color(0xFF4CC9F0)));
    }
    if (_requests.isEmpty) {
      return Center(
        child: Text(
          "No shift requests available.",
          style: TextStyle(color: Colors.white.withOpacity(0.6)),
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _loadRequests,
      backgroundColor: const Color(0xFF172A45),
      color: const Color(0xFF4CC9F0),
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _requests.length,
        itemBuilder: (_, i) {
          final r = _requests[i];
          final id = (r["id"] ?? "").toString();
          final day = (r["day_label"] ?? "").toString();
          final st = (r["start_time"] ?? "").toString();
          final et = (r["end_time"] ?? "").toString();
          final neededFor = (r["needed_for"] ?? "anyone").toString();
          final status = (r["status"] ?? "pending").toString();
          final acceptedFn = (r["accepted_first_name"] ?? "").toString();
          final acceptedLn = (r["accepted_last_name"] ?? "").toString();

          final isPending = status.toLowerCase() == "pending";

          return Container(
            margin: const EdgeInsets.only(bottom: 14),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF172A45),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white.withOpacity(0.06)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  day,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  "$st → $et • Needed: ${neededFor.toUpperCase()}",
                  style: TextStyle(color: Colors.white.withOpacity(0.75)),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Flexible(
                      child: Container(
                        padding:
                            const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: _statusColor(status).withOpacity(0.15),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: _statusColor(status).withOpacity(0.35),
                          ),
                        ),
                        child: Text(
                          status.toUpperCase(),
                          style: TextStyle(
                            color: _statusColor(status),
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                          overflow: TextOverflow.ellipsis,
                          maxLines: 1,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          if (isPending) {
                            return SizedBox(
                              width: constraints.maxWidth,
                              height: 40,
                              child: ElevatedButton(
                                onPressed: () => _acceptShift(id),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF4ADE80),
                                  foregroundColor: Colors.white,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  padding: EdgeInsets.zero,
                                ),
                                child: const Text("Accept"),
                              ),
                            );
                          } else {
                            return Text(
                              "Accepted by: $acceptedFn $acceptedLn",
                              style: TextStyle(color: Colors.white.withOpacity(0.7)),
                              textAlign: TextAlign.right,
                              overflow: TextOverflow.ellipsis,
                              maxLines: 1,
                            );
                          }
                        },
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

  Widget _buildMissingShiftsTab() {
    return Column(
      children: [
        // Date picker and reminder button
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: _pickMissingDate,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF172A45),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFF4CC9F0).withOpacity(0.3)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.calendar_today,
                            color: Color(0xFF4CC9F0), size: 20),
                        const SizedBox(width: 12),
                        Text(
                          DateFormat('dd/MM/yyyy').format(_selectedDate),
                          style: const TextStyle(color: Colors.white, fontSize: 16),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              if (_missingShifts.isNotEmpty)
                ElevatedButton.icon(
                  onPressed: _sendingReminder.contains('all')
                      ? null
                      : _sendReminderToEmployees,
                  icon: _sendingReminder.contains('all')
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.notifications_active),
                  label: const Text("Remind All"),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF4CC9F0),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
            ],
          ),
        ),
        const Divider(color: Colors.white24, height: 1),
        Expanded(
          child: _loadingMissing
              ? const Center(child: CircularProgressIndicator(color: Color(0xFF4CC9F0)))
              : _missingShifts.isEmpty
                  ? Center(
                      child: Text(
                        'No missing shifts for ${DateFormat('dd/MM/yyyy').format(_selectedDate)}',
                        style: TextStyle(color: Colors.white.withOpacity(0.6)),
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: _missingShifts.length,
                      itemBuilder: (_, i) {
                        final shift = _missingShifts[i];
                        return Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: const Color(0xFF172A45),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: Colors.white.withOpacity(0.1),
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  const Icon(Icons.person,
                                      color: Color(0xFF4CC9F0), size: 20),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      '${shift['name']} ${shift['lastName']}',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  const Icon(Icons.schedule,
                                      color: Colors.white54, size: 16),
                                  const SizedBox(width: 8),
                                  Text(
                                    '${shift['startTime']} - ${shift['endTime']}',
                                    style: TextStyle(color: Colors.white70),
                                  ),
                                ],
                              ),
                              if (shift['day'] != null) ...[
                                const SizedBox(height: 4),
                                Row(
                                  children: [
                                    const Icon(Icons.calendar_today,
                                        color: Colors.white54, size: 16),
                                    const SizedBox(width: 8),
                                    Text(
                                      shift['day'],
                                      style: TextStyle(color: Colors.white54, fontSize: 12),
                                    ),
                                  ],
                                ),
                              ],
                            ],
                          ),
                        );
                      },
                    ),
        ),
      ],
    );
  }
}

// =====================================================
// DIALOG 1: CREATE SHIFT REQUEST (FUTURE DAYS)
// =====================================================
class _CreateShiftRequestDialog extends StatefulWidget {
  final String dbName;
  final String userEmail;
  final RotaService rotaService;
  final Function(
      {required String targetRole,
      required String title,
      required String message,
      String? targetEmail}) onSendPushNotification;

  const _CreateShiftRequestDialog({
    required this.dbName,
    required this.userEmail,
    required this.rotaService,
    required this.onSendPushNotification,
  });

  @override
  State<_CreateShiftRequestDialog> createState() =>
      _CreateShiftRequestDialogState();
}

class _CreateShiftRequestDialogState extends State<_CreateShiftRequestDialog> {
  DateTime? _day;

  final _startCtrl1 = TextEditingController();
  final _endCtrl1 = TextEditingController();
  String _neededFor1 = "anyone";

  final _startCtrl2 = TextEditingController();
  final _endCtrl2 = TextEditingController();
  String _neededFor2 = "anyone";
  bool _addSecondShift = false;

  bool _saving = false;

  @override
  void dispose() {
    _startCtrl1.dispose();
    _endCtrl1.dispose();
    _startCtrl2.dispose();
    _endCtrl2.dispose();
    super.dispose();
  }

  Future<void> _pickDay() async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final picked = await showDatePicker(
      context: context,
      initialDate: today,
      firstDate: today,
      lastDate: today.add(const Duration(days: 365)),
    );
    if (picked != null) {
      setState(() => _day = picked);
    }
  }

  Future<void> _pickTime(TextEditingController ctrl) async {
    final t = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.now(),
      builder: (context, child) {
        return MediaQuery(
          data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
          child: child!,
        );
      },
    );
    if (t != null) {
      final hh = t.hour.toString().padLeft(2, '0');
      final mm = t.minute.toString().padLeft(2, '0');
      ctrl.text = "$hh:$mm:00";
    }
  }

  bool _validateShift(String start, String end) {
    if (_day == null) return false;
    if (start.isEmpty || end.isEmpty) return false;
    return true;
  }

  Future<void> _create() async {
    if (_day == null) {
      _showError("Please select a day");
      return;
    }
    if (!_validateShift(_startCtrl1.text, _endCtrl1.text)) {
      _showError("Please fill all fields for shift 1");
      return;
    }
    if (_addSecondShift && !_validateShift(_startCtrl2.text, _endCtrl2.text)) {
      _showError("Please fill all fields for shift 2");
      return;
    }

    setState(() => _saving = true);

    try {
      int successCount = 0;

      final yyyy = _day!.year.toString().padLeft(4, '0');
      final mm = _day!.month.toString().padLeft(2, '0');
      final dd = _day!.day.toString().padLeft(2, '0');
      final dayDate = "$yyyy-$mm-$dd";

      final ok1 = await widget.rotaService.createShiftRequest(
        db: widget.dbName,
        userEmail: widget.userEmail,
        dayDate: dayDate,
        startTime: _startCtrl1.text.trim(),
        endTime: _endCtrl1.text.trim(),
        neededFor: _neededFor1,
      );

      if (ok1) {
        successCount++;
        await widget.onSendPushNotification(
          targetRole: 'ALL',
          targetEmail: '',
          title: '🆕 New Shift Available',
          message: 'A new shift has been requested',
        );
      }

      if (_addSecondShift) {
        final ok2 = await widget.rotaService.createShiftRequest(
          db: widget.dbName,
          userEmail: widget.userEmail,
          dayDate: dayDate,
          startTime: _startCtrl2.text.trim(),
          endTime: _endCtrl2.text.trim(),
          neededFor: _neededFor2,
        );
        if (ok2) {
          successCount++;
          await widget.onSendPushNotification(
            targetRole: 'ALL',
            targetEmail: '',
            title: '🆕 Another Shift Available',
            message: 'Another shift has been requested',
          );
        }
      }

      if (!mounted) return;

      if (successCount > 0) {
        Navigator.pop(context, true);
      } else {
        _showError("Failed to create shift requests");
      }
    } catch (e) {
      _showError("Error: $e");
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF172A45),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      title: const Text("Request Shift(s)", style: TextStyle(color: Colors.white)),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    _day == null
                        ? "Select day"
                        : "${_day!.day.toString().padLeft(2, '0')}/${_day!.month.toString().padLeft(2, '0')}/${_day!.year}",
                    style: TextStyle(color: Colors.white.withOpacity(0.8), fontSize: 16),
                  ),
                ),
                TextButton(
                  onPressed: _saving ? null : _pickDay,
                  child: const Text("Pick", style: TextStyle(color: Color(0xFF4CC9F0))),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Text("Shift 1",
                style: TextStyle(color: Colors.white70, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            TextField(
              controller: _startCtrl1,
              readOnly: true,
              onTap: _saving ? null : () => _pickTime(_startCtrl1),
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                labelText: "Start Time",
                labelStyle: const TextStyle(color: Colors.white60),
                enabledBorder: UnderlineInputBorder(
                  borderSide: BorderSide(color: Colors.white.withOpacity(0.2)),
                ),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _endCtrl1,
              readOnly: true,
              onTap: _saving ? null : () => _pickTime(_endCtrl1),
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                labelText: "End Time",
                labelStyle: const TextStyle(color: Colors.white60),
                enabledBorder: UnderlineInputBorder(
                  borderSide: BorderSide(color: Colors.white.withOpacity(0.2)),
                ),
              ),
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              value: _neededFor1,
              dropdownColor: const Color(0xFF0A192F),
              items: const [
                DropdownMenuItem(value: "anyone", child: Text("Anyone", style: TextStyle(color: Colors.white))),
                DropdownMenuItem(value: "foh", child: Text("FOH", style: TextStyle(color: Colors.white))),
                DropdownMenuItem(value: "boh", child: Text("BOH", style: TextStyle(color: Colors.white))),
              ],
              onChanged: _saving ? null : (v) => setState(() => _neededFor1 = v ?? "anyone"),
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                labelText: "Needed For",
                labelStyle: const TextStyle(color: Colors.white60),
                enabledBorder: UnderlineInputBorder(
                  borderSide: BorderSide(color: Colors.white.withOpacity(0.2)),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Divider(color: Colors.white.withOpacity(0.2)),
            const SizedBox(height: 10),
            Row(
              children: [
                Checkbox(
                  value: _addSecondShift,
                  onChanged: _saving ? null : (v) => setState(() => _addSecondShift = v ?? false),
                  fillColor: MaterialStateProperty.resolveWith((states) => const Color(0xFF4CC9F0)),
                ),
                const Text("Add second shift (same day)", style: TextStyle(color: Colors.white)),
              ],
            ),
            if (_addSecondShift) ...[
              const SizedBox(height: 10),
              Text("Shift 2",
                  style: TextStyle(color: Colors.white70, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              TextField(
                controller: _startCtrl2,
                readOnly: true,
                onTap: _saving ? null : () => _pickTime(_startCtrl2),
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  labelText: "Start Time",
                  labelStyle: const TextStyle(color: Colors.white60),
                  enabledBorder: UnderlineInputBorder(
                    borderSide: BorderSide(color: Colors.white.withOpacity(0.2)),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _endCtrl2,
                readOnly: true,
                onTap: _saving ? null : () => _pickTime(_endCtrl2),
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  labelText: "End Time",
                  labelStyle: const TextStyle(color: Colors.white60),
                  enabledBorder: UnderlineInputBorder(
                    borderSide: BorderSide(color: Colors.white.withOpacity(0.2)),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                value: _neededFor2,
                dropdownColor: const Color(0xFF0A192F),
                items: const [
                  DropdownMenuItem(value: "anyone", child: Text("Anyone", style: TextStyle(color: Colors.white))),
                  DropdownMenuItem(value: "foh", child: Text("FOH", style: TextStyle(color: Colors.white))),
                  DropdownMenuItem(value: "boh", child: Text("BOH", style: TextStyle(color: Colors.white))),
                ],
                onChanged: _saving ? null : (v) => setState(() => _neededFor2 = v ?? "anyone"),
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  labelText: "Needed For",
                  labelStyle: const TextStyle(color: Colors.white60),
                  enabledBorder: UnderlineInputBorder(
                    borderSide: BorderSide(color: Colors.white.withOpacity(0.2)),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context, false),
          child: const Text("Cancel", style: TextStyle(color: Color(0xFF4CC9F0))),
        ),
        ElevatedButton(
          onPressed: _saving ? null : _create,
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF4CC9F0),
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          child: _saving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
              : const Text("Create Request(s)"),
        ),
      ],
    );
  }
}

// =====================================================
// DIALOG 2: ADD TO ROTA DIRECTLY (with scrolling)
// =====================================================
class _AddToRotaDialog extends StatefulWidget {
  final String dbName;
  final String userEmail;
  final RotaService rotaService;
  final Function(
      {required String targetRole,
      required String title,
      required String message,
      String? targetEmail}) onSendPushNotification;

  const _AddToRotaDialog({
    required this.dbName,
    required this.userEmail,
    required this.rotaService,
    required this.onSendPushNotification,
  });

  @override
  State<_AddToRotaDialog> createState() => _AddToRotaDialogState();
}

class _AddToRotaDialogState extends State<_AddToRotaDialog> {
  DateTime? _day;
  Map<String, dynamic>? _selectedEmployee;

  final _startCtrl1 = TextEditingController();
  final _endCtrl1 = TextEditingController();

  final _startCtrl2 = TextEditingController();
  final _endCtrl2 = TextEditingController();
  bool _addSecondShift = false;

  bool _loading = false;
  bool _saving = false;

  List<Map<String, dynamic>> _employees = [];

  @override
  void initState() {
    super.initState();
    _loadEmployees();
  }

  @override
  void dispose() {
    _startCtrl1.dispose();
    _endCtrl1.dispose();
    _startCtrl2.dispose();
    _endCtrl2.dispose();
    super.dispose();
  }

  Future<void> _loadEmployees() async {
    setState(() => _loading = true);
    try {
      final employees = await widget.rotaService.fetchAllEmployees(
        db: widget.dbName,
      );
      if (mounted) {
        setState(() {
          _employees = employees;
          _loading = false;
        });
      }
    } catch (e) {
      print('❌ Error loading employees: $e');
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error loading employees: $e")),
        );
      }
    }
  }

  Future<void> _pickDay() async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final picked = await showDatePicker(
      context: context,
      initialDate: today,
      firstDate: today.subtract(const Duration(days: 365)),
      lastDate: today.add(const Duration(days: 365)),
    );
    if (picked != null) {
      setState(() => _day = picked);
    }
  }

  Future<void> _pickTime(TextEditingController ctrl) async {
    final t = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.now(),
      builder: (context, child) {
        return MediaQuery(
          data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
          child: child!,
        );
      },
    );
    if (t != null) {
      final hh = t.hour.toString().padLeft(2, '0');
      final mm = t.minute.toString().padLeft(2, '0');
      ctrl.text = "$hh:$mm:00";
    }
  }

  bool _validateShift(String start, String end) {
    if (_day == null) return false;
    if (_selectedEmployee == null) return false;
    if (start.isEmpty || end.isEmpty) return false;
    return true;
  }

  Future<void> _addToRota() async {
    if (_day == null) {
      _showError("Please select a day");
      return;
    }
    if (_selectedEmployee == null) {
      _showError("Please select an employee");
      return;
    }
    if (!_validateShift(_startCtrl1.text, _endCtrl1.text)) {
      _showError("Please fill all fields for shift 1");
      return;
    }
    if (_addSecondShift && !_validateShift(_startCtrl2.text, _endCtrl2.text)) {
      _showError("Please fill all fields for shift 2");
      return;
    }

    setState(() => _saving = true);

    try {
      int successCount = 0;

      final weekdays = [
        'Monday',
        'Tuesday',
        'Wednesday',
        'Thursday',
        'Friday',
        'Saturday',
        'Sunday'
      ];
      final yyyy = _day!.year.toString().padLeft(4, '0');
      final mm = _day!.month.toString().padLeft(2, '0');
      final dd = _day!.day.toString().padLeft(2, '0');
      final dayDate = "$yyyy-$mm-$dd";
      final dayName = weekdays[_day!.weekday - 1];
      final dayLabel =
          "${_day!.day.toString().padLeft(2, '0')}/${_day!.month.toString().padLeft(2, '0')}/${_day!.year} ($dayName)";

      print('📝 Adding shift 1 for: ${_selectedEmployee!['email']} on $dayLabel');

      final ok1 = await widget.rotaService.addShiftToRota(
        db: widget.dbName,
        userEmail: widget.userEmail,
        dayLabel: dayLabel,
        dayDate: dayDate,
        startTime: _startCtrl1.text.trim(),
        endTime: _endCtrl1.text.trim(),
        employeeEmail: _selectedEmployee!['email'],
        employeeName: _selectedEmployee!['name'] ?? '',
        employeeLastName: _selectedEmployee!['lastName'] ?? '',
        employeeDesignation: _selectedEmployee!['designation'] ?? 'FOH',
      );

      if (ok1) {
        successCount++;
        print('✅ Shift 1 added successfully');
        await widget.onSendPushNotification(
          targetEmail: _selectedEmployee!['email'],
          targetRole: 'EMPLOYEE',
          title: '📅 New Shift Assigned',
          message: 'You have been assigned a new shift',
        );
      } else {
        print('❌ Failed to add shift 1');
      }

      if (_addSecondShift) {
        print('📝 Adding shift 2 for: ${_selectedEmployee!['email']} on $dayLabel');

        final ok2 = await widget.rotaService.addShiftToRota(
          db: widget.dbName,
          userEmail: widget.userEmail,
          dayLabel: dayLabel,
          dayDate: dayDate,
          startTime: _startCtrl2.text.trim(),
          endTime: _endCtrl2.text.trim(),
          employeeEmail: _selectedEmployee!['email'],
          employeeName: _selectedEmployee!['name'] ?? '',
          employeeLastName: _selectedEmployee!['lastName'] ?? '',
          employeeDesignation: _selectedEmployee!['designation'] ?? 'FOH',
        );

        if (ok2) {
          successCount++;
          print('✅ Shift 2 added successfully');
          await widget.onSendPushNotification(
            targetEmail: _selectedEmployee!['email'],
            targetRole: 'EMPLOYEE',
            title: '📅 Another Shift Assigned',
            message: 'You have been assigned another shift on the same day',
          );
        } else {
          print('❌ Failed to add shift 2');
        }
      }

      if (!mounted) return;

      if (successCount > 0) {
        _showSnackBar("✅ $successCount shift(s) added to rota", Colors.green);
        Navigator.pop(context, true);
      } else {
        _showError("Failed to add shifts to rota");
      }
    } catch (e) {
      print('❌ Exception: $e');
      _showError("Error: $e");
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
  }

  void _showSnackBar(String message, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: color),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF172A45),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      title: const Text("Add to Rota", style: TextStyle(color: Colors.white)),
      content: Container(
        width: double.maxFinite,
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.5,
        ),
        child: _loading
            ? const Center(child: CircularProgressIndicator(color: Color(0xFF4CC9F0)))
            : SingleChildScrollView(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Employee selector
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.white24),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<Map<String, dynamic>>(
                          value: _selectedEmployee,
                          dropdownColor: const Color(0xFF0A192F),
                          hint: const Text("Select Employee",
                              style: TextStyle(color: Colors.white70)),
                          isExpanded: true,
                          items: _employees.map((emp) {
                            return DropdownMenuItem(
                              value: emp,
                              child: Text(
                                "${emp['name']} ${emp['lastName']} (${emp['designation']})",
                                style: const TextStyle(color: Colors.white),
                                overflow: TextOverflow.ellipsis,
                              ),
                            );
                          }).toList(),
                          onChanged: _saving ? null : (v) => setState(() => _selectedEmployee = v),
                          style: const TextStyle(color: Colors.white),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    // Day selector
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              _day == null
                                  ? "Select day"
                                  : "${_day!.day.toString().padLeft(2, '0')}/${_day!.month.toString().padLeft(2, '0')}/${_day!.year}",
                              style: TextStyle(
                                  color: Colors.white.withOpacity(0.8), fontSize: 16),
                            ),
                          ),
                          TextButton(
                            onPressed: _saving ? null : _pickDay,
                            style: TextButton.styleFrom(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            ),
                            child: const Text("Pick",
                                style: TextStyle(color: Color(0xFF4CC9F0))),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                    // Shift 1
                    Text("Shift 1",
                        style:
                            TextStyle(color: Colors.white70, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _startCtrl1,
                      readOnly: true,
                      onTap: _saving ? null : () => _pickTime(_startCtrl1),
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        labelText: "Start Time",
                        labelStyle: const TextStyle(color: Colors.white60),
                        enabledBorder: UnderlineInputBorder(
                          borderSide: BorderSide(color: Colors.white.withOpacity(0.2)),
                        ),
                        focusedBorder: const UnderlineInputBorder(
                          borderSide: BorderSide(color: Color(0xFF4CC9F0)),
                        ),
                        contentPadding: const EdgeInsets.symmetric(vertical: 8),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _endCtrl1,
                      readOnly: true,
                      onTap: _saving ? null : () => _pickTime(_endCtrl1),
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        labelText: "End Time",
                        labelStyle: const TextStyle(color: Colors.white60),
                        enabledBorder: UnderlineInputBorder(
                          borderSide: BorderSide(color: Colors.white.withOpacity(0.2)),
                        ),
                        focusedBorder: const UnderlineInputBorder(
                          borderSide: BorderSide(color: Color(0xFF4CC9F0)),
                        ),
                        contentPadding: const EdgeInsets.symmetric(vertical: 8),
                      ),
                    ),
                    const SizedBox(height: 20),
                    Divider(color: Colors.white.withOpacity(0.2), height: 1),
                    const SizedBox(height: 12),
                    // Second shift option
                    Row(
                      children: [
                        SizedBox(
                          height: 24,
                          width: 24,
                          child: Checkbox(
                            value: _addSecondShift,
                            onChanged: _saving ? null : (v) => setState(() => _addSecondShift = v ?? false),
                            fillColor: MaterialStateProperty.resolveWith(
                                (states) => const Color(0xFF4CC9F0)),
                            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                        ),
                        const SizedBox(width: 8),
                        const Expanded(
                          child: Text(
                            "Add second shift (same day/employee)",
                            style: TextStyle(color: Colors.white),
                          ),
                        ),
                      ],
                    ),
                    if (_addSecondShift) ...[
                      const SizedBox(height: 16),
                      Text("Shift 2",
                          style: TextStyle(
                              color: Colors.white70, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _startCtrl2,
                        readOnly: true,
                        onTap: _saving ? null : () => _pickTime(_startCtrl2),
                        style: const TextStyle(color: Colors.white),
                        decoration: InputDecoration(
                          labelText: "Start Time",
                          labelStyle: const TextStyle(color: Colors.white60),
                          enabledBorder: UnderlineInputBorder(
                            borderSide: BorderSide(color: Colors.white.withOpacity(0.2)),
                          ),
                          focusedBorder: const UnderlineInputBorder(
                            borderSide: BorderSide(color: Color(0xFF4CC9F0)),
                          ),
                          contentPadding: const EdgeInsets.symmetric(vertical: 8),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _endCtrl2,
                        readOnly: true,
                        onTap: _saving ? null : () => _pickTime(_endCtrl2),
                        style: const TextStyle(color: Colors.white),
                        decoration: InputDecoration(
                          labelText: "End Time",
                          labelStyle: const TextStyle(color: Colors.white60),
                          enabledBorder: UnderlineInputBorder(
                            borderSide: BorderSide(color: Colors.white.withOpacity(0.2)),
                          ),
                          focusedBorder: const UnderlineInputBorder(
                            borderSide: BorderSide(color: Color(0xFF4CC9F0)),
                          ),
                          contentPadding: const EdgeInsets.symmetric(vertical: 8),
                        ),
                      ),
                    ],
                    const SizedBox(height: 16),
                  ],
                ),
              ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context, false),
          child: const Text("Cancel", style: TextStyle(color: Color(0xFF4CC9F0))),
        ),
        ElevatedButton(
          onPressed: _saving ? null : _addToRota,
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF4ADE80),
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          child: _saving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
              : const Text("Add to Rota"),
        ),
      ],
    );
  }
}