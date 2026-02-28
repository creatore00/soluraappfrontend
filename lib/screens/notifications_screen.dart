import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/database_access.dart';
import '../services/notifications_service.dart';
import 'holiday_requests_screen.dart';

class NotificationsScreen extends StatefulWidget {
  final DatabaseAccess selectedDb;
  final String role; // backend uses role, not email

  const NotificationsScreen({
    super.key,
    required this.selectedDb,
    required this.role,
  });

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  bool loading = true;
  bool markingAll = false;
  List<Map<String, dynamic>> items = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => loading = true);
    try {
      final list = await NotificationsService.fetchNotifications(
        db: widget.selectedDb.dbName,
        role: widget.role,
      );
      if (!mounted) return;
      setState(() => items = list);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Failed to load: $e")),
      );
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  bool _isRead(Map<String, dynamic> n) {
    final v = n['isRead'];
    return v == 1 || v == true;
  }

  // ✅ Always return UTC (consistent for grouping + timeAgo)
  DateTime? _parseCreatedAtUtc(dynamic createdAt) {
    if (createdAt == null) return null;
    final s = createdAt.toString().trim();
    if (s.isEmpty) return null;

    // 1) ISO with timezone ("Z" or "+01:00")
    try {
      final dt = DateTime.parse(s);
      return dt.toUtc();
    } catch (_) {}

    // 2) MySQL "yyyy-MM-dd HH:mm:ss" (NO timezone) -> treat as UTC
    try {
      return DateFormat("yyyy-MM-dd HH:mm:ss").parseUtc(s);
    } catch (_) {}

    return null;
  }

  String _timeAgoUtc(DateTime? dtUtc) {
    if (dtUtc == null) return '';
    final nowUtc = DateTime.now().toUtc();
    final diff = nowUtc.difference(dtUtc);

    if (diff.inSeconds < 30) return "just now";
    if (diff.inMinutes < 1) return "${diff.inSeconds}s ago";
    if (diff.inMinutes < 60) return "${diff.inMinutes} mins ago";
    if (diff.inHours < 24) return "${diff.inHours} hrs ago";
    if (diff.inDays < 7) return "${diff.inDays} days ago";

    return DateFormat('dd MMM yyyy').format(dtUtc.toLocal());
  }

  Future<void> _markOneAsRead(int id) async {
    try {
      await NotificationsService.markAsRead(db: widget.selectedDb.dbName, id: id);
      if (!mounted) return;
      setState(() {
        items = items.map((n) {
          if (n['id'] == id) return {...n, 'isRead': 1};
          return n;
        }).toList();
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Failed: $e")),
      );
    }
  }

  Future<void> _markAllAsRead() async {
    if (markingAll) return;

    final unreadIds = items
        .where((n) => !_isRead(n))
        .map((n) => n['id'])
        .whereType<int>()
        .toList();

    if (unreadIds.isEmpty) return;

    setState(() => markingAll = true);
    try {
      await NotificationsService.markAllAsRead(db: widget.selectedDb.dbName, ids: unreadIds);
      if (!mounted) return;
      setState(() {
        items = items.map((n) => {...n, 'isRead': 1}).toList();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("All notifications marked as read")),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Failed: $e")),
      );
    } finally {
      if (mounted) setState(() => markingAll = false);
    }
  }

  // ----------------------------
  // ✅ GROUPING HELPERS
  // ----------------------------

  String _bucketFor(DateTime? createdUtc) {
    if (createdUtc == null) return "Older";

    final nowUtc = DateTime.now().toUtc();
    final diff = nowUtc.difference(createdUtc);

    // Last 12 hours
    if (diff.inHours < 12) return "Last 12 hours";

    // Today (older than 12h)
    final nowLocal = DateTime.now();
    final local = createdUtc.toLocal();
    final sameDay = local.year == nowLocal.year && local.month == nowLocal.month && local.day == nowLocal.day;
    if (sameDay) return "Today";

    // This week (Mon-Sun) in local time
    final monday = DateTime(nowLocal.year, nowLocal.month, nowLocal.day)
        .subtract(Duration(days: nowLocal.weekday - 1));
    final startOfWeek = DateTime(monday.year, monday.month, monday.day);
    if (local.isAfter(startOfWeek)) return "This week";

    return "Older";
  }

  List<_ListEntry> _buildSectionedList() {
    // Sort newest first (in case backend ever changes order)
    final sorted = [...items];
    sorted.sort((a, b) {
      final da = _parseCreatedAtUtc(a['createdAt']) ?? DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
      final db = _parseCreatedAtUtc(b['createdAt']) ?? DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
      return db.compareTo(da);
    });

    final order = ["Last 12 hours", "Today", "This week", "Older"];
    final Map<String, List<Map<String, dynamic>>> groups = {
      for (final k in order) k: [],
    };

    for (final n in sorted) {
      final dt = _parseCreatedAtUtc(n['createdAt']);
      final bucket = _bucketFor(dt);
      groups[bucket]?.add(n);
    }

    final result = <_ListEntry>[];
    for (final k in order) {
      final list = groups[k] ?? [];
      if (list.isEmpty) continue;
      result.add(_ListEntry.header(k));
      for (final n in list) {
        result.add(_ListEntry.item(n));
      }
    }
    return result;
  }

  Widget _sectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 10),
      child: Text(
        title,
        style: TextStyle(
          color: Colors.white.withOpacity(0.85),
          fontWeight: FontWeight.w800,
          fontSize: 14,
          letterSpacing: 0.3,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final unread = items.where((n) => !_isRead(n)).length;
    final isApprover = widget.role == "AM" || widget.role == "Manager";

    final entries = _buildSectionedList();

    return Scaffold(
      backgroundColor: const Color(0xFF0A192F),
      appBar: AppBar(
        backgroundColor: const Color(0xFF172A45),
        elevation: 0,
        title: Text(
          unread > 0 ? "Notifications ($unread)" : "Notifications",
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        actions: [
          if (items.isNotEmpty)
            TextButton.icon(
              onPressed: markingAll ? null : _markAllAsRead,
              icon: Icon(Icons.done_all, color: markingAll ? Colors.white38 : const Color(0xFF4CC9F0)),
              label: Text(
                markingAll ? "..." : "Mark all as read",
                style: TextStyle(color: markingAll ? Colors.white38 : const Color(0xFF4CC9F0)),
              ),
            ),
          IconButton(
            icon: const Icon(Icons.refresh, color: Color(0xFF4CC9F0)),
            onPressed: _load,
          )
        ],
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF4CC9F0)))
          : items.isEmpty
              ? Center(
                  child: Text(
                    "No notifications",
                    style: TextStyle(color: Colors.white.withOpacity(0.7)),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: entries.length,
                  itemBuilder: (context, i) {
                    final entry = entries[i];

                    if (entry.isHeader) {
                      return _sectionHeader(entry.headerTitle!);
                    }

                    final n = entry.item!;
                    final isRead = _isRead(n);
                    final dtUtc = _parseCreatedAtUtc(n['createdAt']);

                    return TweenAnimationBuilder<double>(
                      duration: const Duration(milliseconds: 280),
                      tween: Tween(begin: 0, end: 1),
                      builder: (context, v, child) => Opacity(
                        opacity: v,
                        child: Transform.translate(offset: Offset(0, (1 - v) * 10), child: child),
                      ),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(16),
                        onTap: () async {
                          final id = n['id'];
                          final type = (n['type'] ?? '').toString().toUpperCase();

                          if (id is int && !isRead) {
                            await _markOneAsRead(id);
                          }

                          if (type == "HOLIDAY" && isApprover) {
                            if (!mounted) return;
                            await Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => HolidayRequestsScreen(
                                  selectedDb: widget.selectedDb,
                                  role: widget.role,
                                ),
                              ),
                            );

                            await _load();
                          }
                        },
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: const Color(0xFF172A45).withOpacity(isRead ? 0.6 : 0.95),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: isRead
                                  ? Colors.white.withOpacity(0.06)
                                  : const Color(0xFF4CC9F0).withOpacity(0.25),
                            ),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                width: 42,
                                height: 42,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: (isRead ? Colors.white : const Color(0xFF4CC9F0)).withOpacity(0.12),
                                ),
                                child: Icon(
                                  n['type'] == 'warning'
                                      ? Icons.warning_amber_rounded
                                      : n['type'] == 'success'
                                          ? Icons.check_circle_outline
                                          : Icons.notifications_none,
                                  color: isRead ? Colors.white70 : const Color(0xFF4CC9F0),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            (n['title'] ?? 'Notification').toString(),
                                            style: TextStyle(
                                              color: Colors.white,
                                              fontSize: 15,
                                              fontWeight: isRead ? FontWeight.w600 : FontWeight.w800,
                                            ),
                                          ),
                                        ),
                                        if (!isRead)
                                          Container(
                                            width: 8,
                                            height: 8,
                                            decoration: const BoxDecoration(
                                              shape: BoxShape.circle,
                                              color: Color(0xFF4ADE80),
                                            ),
                                          ),
                                      ],
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      (n['message'] ?? '').toString(),
                                      style: TextStyle(color: Colors.white.withOpacity(0.75)),
                                    ),
                                    const SizedBox(height: 10),
                                    Text(
                                      _timeAgoUtc(dtUtc),
                                      style: TextStyle(color: Colors.white.withOpacity(0.45), fontSize: 12),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}

// Small helper model for list entries (header or item)
class _ListEntry {
  final bool isHeader;
  final String? headerTitle;
  final Map<String, dynamic>? item;

  _ListEntry.header(this.headerTitle)
      : isHeader = true,
        item = null;

  _ListEntry.item(this.item)
      : isHeader = false,
        headerTitle = null;
}
