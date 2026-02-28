// lib/screens/shift_requests_screen.dart
import 'package:flutter/material.dart';
import '../models/database_access.dart';
import '../services/rota_service.dart';

class ShiftRequestsScreen extends StatefulWidget {
  final DatabaseAccess selectedDb;
  final String userEmail;
  final String userName;

  /// REQUIRED: "FOH" or "BOH" (we normalize to lowercase)
  final String userDesignation;

  const ShiftRequestsScreen({
    super.key,
    required this.selectedDb,
    required this.userEmail,
    required this.userName,
    required this.userDesignation,
  });

  @override
  State<ShiftRequestsScreen> createState() => _ShiftRequestsScreenState();
}

class _ShiftRequestsScreenState extends State<ShiftRequestsScreen> {
  final RotaService _rotaService = RotaService();

  bool _loading = true;

  /// What we will display
  List<Map<String, dynamic>> _requests = [];

  /// Raw fetched requests (before filtering)
  List<Map<String, dynamic>> _allRequests = [];

  /// Cache: dateKey(yyyy-mm-dd) -> list of user's rota shifts on that day
  final Map<String, List<Map<String, dynamic>>> _myRotaCache = {};

  bool get _canCreateShift {
    final r = widget.selectedDb.access.trim().toLowerCase();
    return r == "am" || r == "assistant manager" || r == "admin";
  }

  String _norm(String v) => v.trim().toLowerCase();

  // --------------------------------------------
  // 1) Designation filtering (FOH/BOH/anyone)
  // --------------------------------------------
  bool _shouldShowToUserByDesignation(String neededForRaw) {
    final need = _norm(neededForRaw.isEmpty ? "anyone" : neededForRaw);
    final des = _norm(widget.userDesignation);

    if (need == "anyone") return true;
    if (need == "foh") return des == "foh";
    if (need == "boh") return des == "boh";

    // unknown => show (or return false if you want strict)
    return true;
  }

  // --------------------------------------------
  // 2) Time overlap helpers
  // --------------------------------------------
  int _timeToMinutes(String hhmmss) {
    // accepts "HH:mm:ss" or "HH:mm"
    final t = hhmmss.trim();
    if (t.isEmpty) return 0;

    final parts = t.split(':');
    if (parts.length < 2) return 0;

    final hh = int.tryParse(parts[0]) ?? 0;
    final mm = int.tryParse(parts[1]) ?? 0;
    return (hh * 60) + mm;
  }

  bool _overlaps(int aStart, int aEnd, int bStart, int bEnd) {
    // handle overnight shifts by pushing end into next day
    if (aEnd <= aStart) aEnd += 24 * 60;
    if (bEnd <= bStart) bEnd += 24 * 60;

    // if one is overnight and the other isn't, we also need to check "shifted" window
    // simplest: check overlap in same-day space and also if needed add +1440 to one window
    bool baseOverlap = aStart < bEnd && bStart < aEnd;
    if (baseOverlap) return true;

    // try shifting B by +24h (for cases where A is overnight and B is in next-day portion)
    bool shiftB = aStart < (bEnd + 1440) && (bStart + 1440) < aEnd;
    if (shiftB) return true;

    // try shifting A by +24h
    bool shiftA = (aStart + 1440) < bEnd && bStart < (aEnd + 1440);
    return shiftA;
  }

  /// Parse "dd/mm/yyyy (Day)" -> returns "yyyy-mm-dd"
  String? _dayLabelToDateKey(String dayLabel) {
    final raw = dayLabel.trim();
    if (raw.isEmpty) return null;

    // take only date part before space
    final datePart = raw.split(' ').first.trim(); // dd/mm/yyyy
    final seg = datePart.split('/');
    if (seg.length != 3) return null;

    final dd = seg[0].padLeft(2, '0');
    final mm = seg[1].padLeft(2, '0');
    final yyyy = seg[2].padLeft(4, '0');
    return "$yyyy-$mm-$dd";
  }

  // --------------------------------------------
  // 3) Fetch + filter logic
  // --------------------------------------------
  @override
  void initState() {
    super.initState();
    _loadRequests();
  }

  Future<void> _loadRequests() async {
    setState(() => _loading = true);

    try {
      final data = await _rotaService.fetchShiftRequests(
        db: widget.selectedDb.dbName,
        userEmail: widget.userEmail,
      );

      _allRequests = data;

      // ✅ Apply BOTH filters:
      // - designation filter
      // - time-conflict filter (user must be fully free)
      final filtered = await _applyFilters(data);

      if (!mounted) return;
      setState(() {
        _requests = filtered;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Failed to load shift requests: $e"),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<List<Map<String, dynamic>>> _applyFilters(List<Map<String, dynamic>> items) async {
    final out = <Map<String, dynamic>>[];

    for (final r in items) {
      final neededFor = (r["needed_for"] ?? "anyone").toString();
      if (!_shouldShowToUserByDesignation(neededFor)) {
        continue;
      }

      final status = (r["status"] ?? "pending").toString().toLowerCase();

      // if it's already accepted/cancelled, still show it (only if designation matches)
      // but if you want only pending -> uncomment:
      // if (status != "pending") continue;

      final dayLabel = (r["day_label"] ?? "").toString();
      final dateKey = _dayLabelToDateKey(dayLabel);
      if (dateKey == null) {
        // can't validate overlap => show it
        out.add(r);
        continue;
      }

      // Only block visibility if it's pending (because accepted shifts are informational)
      if (status == "pending") {
        final st = (r["start_time"] ?? "").toString();
        final et = (r["end_time"] ?? "").toString();

        final reqStart = _timeToMinutes(st);
        final reqEnd = _timeToMinutes(et);

        // fetch my rota shifts for that date (cached)
        final myShifts = await _getMyRotaForDate(dateKey);

        final hasConflict = myShifts.any((s) {
          final sst = (s["startTime"] ?? s["start_time"] ?? "").toString();
          final set = (s["endTime"] ?? s["end_time"] ?? "").toString();
          final aStart = _timeToMinutes(sst);
          final aEnd = _timeToMinutes(set);
          return _overlaps(reqStart, reqEnd, aStart, aEnd);
        });

        if (hasConflict) {
          // ✅ user not fully free -> do NOT show this request
          continue;
        }
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
      dateYYYYMMDD: dateKey, // yyyy-mm-dd
    );

    _myRotaCache[dateKey] = shifts;
    return shifts;
  }

  // --------------------------------------------
  // Actions
  // --------------------------------------------
  Future<void> _acceptShift(String id) async {
    try {
      final ok = await _rotaService.acceptShiftRequest(
        db: widget.selectedDb.dbName,
        id: id,
        userEmail: widget.userEmail,
      );

      if (!mounted) return;

      if (ok) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text("✅ Shift accepted"),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            duration: const Duration(seconds: 1),
          ),
        );

        // invalidate cache (rota changed)
        _myRotaCache.clear();

        await _loadRequests();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text("❌ Failed to accept shift"),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("❌ Error: $e"),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
    }
  }

  Future<void> _openCreateDialog() async {
    final created = await showDialog<bool>(
      context: context,
      builder: (_) => _CreateShiftDialog(
        dbName: widget.selectedDb.dbName,
        userEmail: widget.userEmail,
        rotaService: _rotaService,
      ),
    );

    if (created == true) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text("✅ Shift requested"),
          backgroundColor: Colors.green,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          duration: const Duration(seconds: 1),
        ),
      );

      _myRotaCache.clear();
      await _loadRequests();
    }
  }

  Color _statusColor(String status) {
    final s = status.toLowerCase();
    if (s == "accepted") return Colors.green;
    if (s == "cancelled") return Colors.red;
    return Colors.orange; // pending
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A192F),
      appBar: AppBar(
        title: const Text("Shift Requests", style: TextStyle(color: Colors.white)),
        backgroundColor: const Color(0xFF172A45),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Color(0xFF4CC9F0)),
            onPressed: _loadRequests,
          ),
        ],
      ),
      floatingActionButton: _canCreateShift
          ? FloatingActionButton(
              onPressed: _openCreateDialog,
              backgroundColor: const Color(0xFF4CC9F0),
              foregroundColor: Colors.white,
              child: const Icon(Icons.add),
            )
          : null,
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF4CC9F0)))
          : _requests.isEmpty
              ? Center(
                  child: Text(
                    "No shift requests available.",
                    style: TextStyle(color: Colors.white.withOpacity(0.6)),
                  ),
                )
              : RefreshIndicator(
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
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
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
                                  ),
                                ),
                                const Spacer(),
                                if (isPending)
                                  SizedBox(
                                    height: 40,
                                    child: ElevatedButton(
                                      onPressed: () => _acceptShift(id),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: const Color(0xFF4ADE80),
                                        foregroundColor: Colors.white,
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(12),
                                        ),
                                      ),
                                      child: const Text("Accept"),
                                    ),
                                  )
                                else
                                  Text(
                                    "Accepted by: $acceptedFn $acceptedLn",
                                    style: TextStyle(color: Colors.white.withOpacity(0.7)),
                                  ),
                              ],
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
    );
  }
}

// =====================================================
// Create Shift Dialog (same file)
// =====================================================
class _CreateShiftDialog extends StatefulWidget {
  final String dbName;
  final String userEmail;
  final RotaService rotaService;

  const _CreateShiftDialog({
    required this.dbName,
    required this.userEmail,
    required this.rotaService,
  });

  @override
  State<_CreateShiftDialog> createState() => _CreateShiftDialogState();
}

class _CreateShiftDialogState extends State<_CreateShiftDialog> {
  DateTime? _day;
  final _startCtrl = TextEditingController();
  final _endCtrl = TextEditingController();
  String _neededFor = "anyone";
  bool _saving = false;

  @override
  void dispose() {
    _startCtrl.dispose();
    _endCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDay() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: now,
      firstDate: now.subtract(const Duration(days: 0)),
      lastDate: now.add(const Duration(days: 365)),
    );
    if (picked != null) setState(() => _day = picked);
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
      ctrl.text = "$hh:$mm:00"; // HH:mm:ss
    }
  }

  Future<void> _create() async {
    if (_day == null || _startCtrl.text.isEmpty || _endCtrl.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please fill all fields")),
      );
      return;
    }

    setState(() => _saving = true);

    try {
      final yyyy = _day!.year.toString().padLeft(4, '0');
      final mm = _day!.month.toString().padLeft(2, '0');
      final dd = _day!.day.toString().padLeft(2, '0');
      final dayDate = "$yyyy-$mm-$dd";

      final ok = await widget.rotaService.createShiftRequest(
        db: widget.dbName,
        userEmail: widget.userEmail,
        dayDate: dayDate,
        startTime: _startCtrl.text.trim(),
        endTime: _endCtrl.text.trim(),
        neededFor: _neededFor,
      );

      if (!mounted) return;

      if (ok) {
        Navigator.pop(context, true);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Failed to create shift request")),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Error: $e")),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF172A45),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      title: const Text("Request a Shift", style: TextStyle(color: Colors.white)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  _day == null
                      ? "Select day"
                      : "${_day!.day.toString().padLeft(2, '0')}/${_day!.month.toString().padLeft(2, '0')}/${_day!.year}",
                  style: TextStyle(color: Colors.white.withOpacity(0.8)),
                ),
              ),
              TextButton(
                onPressed: _saving ? null : _pickDay,
                child: const Text("Pick", style: TextStyle(color: Color(0xFF4CC9F0))),
              ),
            ],
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _startCtrl,
            readOnly: true,
            onTap: _saving ? null : () => _pickTime(_startCtrl),
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              labelText: "Start Time (HH:mm:ss)",
              labelStyle: const TextStyle(color: Colors.white60),
              enabledBorder: UnderlineInputBorder(
                borderSide: BorderSide(color: Colors.white.withOpacity(0.2)),
              ),
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _endCtrl,
            readOnly: true,
            onTap: _saving ? null : () => _pickTime(_endCtrl),
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              labelText: "End Time (HH:mm:ss)",
              labelStyle: const TextStyle(color: Colors.white60),
              enabledBorder: UnderlineInputBorder(
                borderSide: BorderSide(color: Colors.white.withOpacity(0.2)),
              ),
            ),
          ),
          const SizedBox(height: 14),
          DropdownButtonFormField<String>(
            value: _neededFor,
            dropdownColor: const Color(0xFF0A192F),
            items: const [
              DropdownMenuItem(value: "anyone", child: Text("Anyone")),
              DropdownMenuItem(value: "foh", child: Text("FOH")),
              DropdownMenuItem(value: "boh", child: Text("BOH")),
            ],
            onChanged: _saving ? null : (v) => setState(() => _neededFor = v ?? "anyone"),
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
              : const Text("Create"),
        ),
      ],
    );
  }
}
