// widgets/mention_text_field.dart
import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../services/auth_service.dart';

class MentionTextField extends StatefulWidget {
  final TextEditingController controller;
  final String dbName;
  final String currentUserEmail;
  final FocusNode? focusNode;
  final Function(String)? onTextChanged;
  final Function(Map<String, dynamic>)? onMentionSelected;
  final String hintText;
  final int maxLines;
  final EdgeInsetsGeometry padding;
  final Color? cursorColor;
  final TextStyle? style;

  const MentionTextField({
    super.key,
    required this.controller,
    required this.dbName,
    required this.currentUserEmail,
    this.focusNode,
    this.onTextChanged,
    this.onMentionSelected,
    this.hintText = 'Write something... Use @ to mention someone',
    this.maxLines = 5,
    this.padding = const EdgeInsets.all(16),
    this.cursorColor,
    this.style,
  });

  @override
  State<MentionTextField> createState() => _MentionTextFieldState();
}

class _MentionTextFieldState extends State<MentionTextField> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;

  final LayerLink _layerLink = LayerLink();
  OverlayEntry? _overlayEntry;

  Timer? _debounceTimer;

  bool _isLoading = false;

  int _mentionTriggerIndex = -1;
  String _currentMentionQuery = '';

  List<Map<String, dynamic>> _mentionSuggestions = [];

  // Bulk mention options (always available)
  final List<Map<String, dynamic>> _bulkMentions = [
    {
      'id': 'bulk_foh',
      'type': 'bulk',
      'fullName': 'FOH',
      'displayName': 'FOH',
      'designation': 'FOH',
      'email': 'bulk_foh',
      'avatar': '👥',
      'count': null,
    },
    {
      'id': 'bulk_boh',
      'type': 'bulk',
      'fullName': 'BOH',
      'displayName': 'BOH',
      'designation': 'BOH',
      'email': 'bulk_boh',
      'avatar': '👥',
      'count': null,
    },
    {
      'id': 'bulk_everyone',
      'type': 'bulk',
      'fullName': 'EVERYONE',
      'displayName': 'EVERYONE',
      'designation': 'ALL',
      'email': 'bulk_everyone',
      'avatar': '🌍',
      'count': null,
    },
    {
      'id': 'bulk_all',
      'type': 'bulk',
      'fullName': 'ALL',
      'displayName': 'ALL',
      'designation': 'ALL',
      'email': 'bulk_all',
      'avatar': '🌍',
      'count': null,
    },
  ];

  @override
  void initState() {
    super.initState();
    _controller = widget.controller;
    _focusNode = widget.focusNode ?? FocusNode();

    _controller.addListener(_onTextChanged);
    _focusNode.addListener(_onFocusChanged);
  }

  @override
  void dispose() {
    _controller.removeListener(_onTextChanged);
    _focusNode.removeListener(_onFocusChanged);
    _debounceTimer?.cancel();
    _hideOverlay();

    if (widget.focusNode == null) {
      _focusNode.dispose();
    }
    super.dispose();
  }

  void _onFocusChanged() {
    if (!_focusNode.hasFocus) {
      Future.delayed(const Duration(milliseconds: 100), () {
        if (mounted && !_focusNode.hasFocus) {
          _hideOverlay();
        }
      });
    }
  }

  void _onTextChanged() {
    final text = _controller.text;
    final selection = _controller.selection;

    widget.onTextChanged?.call(text);

    _checkForMentionTrigger(text, selection);
  }

  void _checkForMentionTrigger(String text, TextSelection selection) {
    if (!_focusNode.hasFocus) {
      _hideOverlay();
      return;
    }

    final cursorPos = selection.baseOffset;
    if (cursorPos <= 0 || cursorPos > text.length) {
      _hideOverlay();
      return;
    }

    int atIndex = -1;

    // Find nearest valid "@"
    for (int i = cursorPos - 1; i >= 0; i--) {
      if (text[i] == '@') {
        if (i == 0 || text[i - 1] == ' ' || text[i - 1] == '\n') {
          atIndex = i;
          break;
        } else {
          // '@' inside email/word -> ignore
          break;
        }
      }
      // Stop scanning when we hit whitespace/newline
      if (text[i] == ' ' || text[i] == '\n') break;
    }

    if (atIndex == -1) {
      _hideOverlay();
      return;
    }

    final query = text.substring(atIndex + 1, cursorPos);

    // If user typed space inside mention -> stop
    if (query.contains(' ')) {
      _hideOverlay();
      return;
    }

    if (_mentionTriggerIndex != atIndex || _currentMentionQuery != query) {
      _mentionTriggerIndex = atIndex;
      _currentMentionQuery = query;

      // Show immediately with bulk suggestions even before network
      _primeSuggestions(query);

      _debounceTimer?.cancel();
      _debounceTimer = Timer(const Duration(milliseconds: 200), () {
        _searchEmployees(query);
      });
    }
  }

  void _primeSuggestions(String query) {
    final lower = query.toLowerCase();

    final bulk = _bulkMentions.where((b) {
      final name = (b['fullName'] ?? '').toString().toLowerCase();
      return query.isEmpty || name.startsWith(lower);
    }).map((e) => Map<String, dynamic>.from(e)).toList();

    setState(() {
      _mentionSuggestions = bulk;
      _isLoading = true; // we will fetch employees next
    });

    _showOverlay();
  }

  Future<void> _searchEmployees(String query) async {
    if (!_focusNode.hasFocus) {
      _hideOverlay();
      return;
    }

    setState(() => _isLoading = true);

    try {
      final url = Uri.parse(
        "${AuthService.baseUrl}/employees/search"
        "?db=${Uri.encodeComponent(widget.dbName)}"
        "&search=${Uri.encodeComponent(query)}"
        "&excludeEmail=${Uri.encodeComponent(widget.currentUserEmail)}"
        "&limit=15",
      );

      final response = await http.get(url);

      if (response.statusCode != 200) {
        setState(() {
          _isLoading = false;
        });
        // keep bulk suggestions visible
        _showOverlay();
        return;
      }

      final data = jsonDecode(response.body);
      final ok = data is Map && data['success'] == true;

      List<Map<String, dynamic>> employees = [];
      if (ok) {
        employees = List<Map<String, dynamic>>.from(data['employees'] ?? []);
      }

      final lower = query.toLowerCase();

      // Filter employees "startsWith" (your create dialog behaviour)
      if (query.isNotEmpty) {
        employees = employees.where((emp) {
          final fullName = (emp['fullName'] ?? '').toString().toLowerCase();
          final firstName = (emp['name'] ?? '').toString().toLowerCase();
          final lastName = (emp['lastName'] ?? '').toString().toLowerCase();
          return fullName.startsWith(lower) ||
              firstName.startsWith(lower) ||
              lastName.startsWith(lower);
        }).toList();
      }

      // Bulk suggestions
      final bulk = _bulkMentions.where((b) {
        final name = (b['fullName'] ?? '').toString().toLowerCase();
        return query.isEmpty || name.startsWith(lower);
      }).map((e) => Map<String, dynamic>.from(e)).toList();

      // (Optional) counts based on returned employees (not global headcount)
      for (final b in bulk) {
        final name = (b['fullName'] ?? '').toString().toUpperCase();
        if (name == 'FOH') {
          b['count'] = employees.where((e) => (e['designation'] ?? '').toString().toUpperCase() == 'FOH').length;
        } else if (name == 'BOH') {
          b['count'] = employees.where((e) => (e['designation'] ?? '').toString().toUpperCase() == 'BOH').length;
        } else {
          b['count'] = employees.length;
        }
      }

      setState(() {
        _mentionSuggestions = [...bulk, ...employees];
        _isLoading = false;
      });

      _showOverlay();
    } catch (e) {
      debugPrint("❌ Mention search error: $e");
      if (!mounted) return;
      setState(() => _isLoading = false);
      // keep whatever we had (bulk) visible
      _showOverlay();
    }
  }

  void _insertMention(String display) {
    final triggerIndex = _mentionTriggerIndex;
    final query = _currentMentionQuery;

    if (triggerIndex == -1) return;

    final text = _controller.text;

    final before = text.substring(0, triggerIndex);
    final after = text.substring(triggerIndex + 1 + query.length);

    final mentionText = '@$display ';

    final newText = '$before$mentionText$after';

    _controller.text = newText;
    _controller.selection = TextSelection.collapsed(
      offset: before.length + mentionText.length,
    );

    _hideOverlay();
  }

  void _showOverlay() {
    _hideOverlay();

    if (!mounted) return;

    final overlay = Overlay.of(context);
    if (overlay == null) return;

    final renderBox = context.findRenderObject();
    if (renderBox is! RenderBox) return;

    final size = renderBox.size;

    _overlayEntry = OverlayEntry(
      builder: (context) => Positioned(
        width: size.width,
        child: CompositedTransformFollower(
          link: _layerLink,
          showWhenUnlinked: false,
          offset: Offset(0, size.height + 8),
          child: Material(
            elevation: 8,
            borderRadius: BorderRadius.circular(12),
            color: const Color(0xFF172A45),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: 350,
                minWidth: size.width,
              ),
              child: _buildSuggestionsList(),
            ),
          ),
        ),
      ),
    );

    overlay.insert(_overlayEntry!);
  }

  void _hideOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  Widget _buildSuggestionsList() {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF172A45),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
            child: Row(
              children: [
                Text(
                  _currentMentionQuery.isEmpty
                      ? 'SUGGESTIONS'
                      : "MATCHING '${_currentMentionQuery}'",
                  style: TextStyle(
                    color: const Color(0xFF4CC9F0).withOpacity(0.85),
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.8,
                  ),
                ),
                const Spacer(),
                if (_isLoading)
                  const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Color(0xFF4CC9F0),
                    ),
                  ),
              ],
            ),
          ),
          Divider(height: 1, color: Colors.white.withOpacity(0.08)),
          if (_mentionSuggestions.isEmpty && !_isLoading)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                _currentMentionQuery.isEmpty
                    ? 'No suggestions'
                    : "No matches for '${_currentMentionQuery}'",
                style: TextStyle(color: Colors.white.withOpacity(0.6)),
              ),
            )
          else
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                padding: const EdgeInsets.symmetric(vertical: 8),
                itemCount: _mentionSuggestions.length,
                separatorBuilder: (_, __) =>
                    Divider(height: 1, color: Colors.white.withOpacity(0.08)),
                itemBuilder: (context, index) {
                  final item = _mentionSuggestions[index];
                  final isBulk = item['type'] == 'bulk';
                  return isBulk
                      ? _buildBulkMentionTile(item)
                      : _buildEmployeeMentionTile(item);
                },
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildEmployeeMentionTile(Map<String, dynamic> employee) {
    final fullName = (employee['fullName'] ??
            '${employee['name'] ?? ''} ${employee['lastName'] ?? ''}')
        .toString()
        .trim();

    final designation = (employee['designation'] ?? '').toString();
    final email = (employee['email'] ?? '').toString();

    final avatarLetter = fullName.isNotEmpty ? fullName[0].toUpperCase() : '?';

    return InkWell(
      onTap: () {
        _insertMention(fullName);
        widget.onMentionSelected?.call({
          ...employee,
          'mentionType': 'employee',
          'mentionDisplay': '@$fullName',
        });
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            CircleAvatar(
              radius: 18,
              backgroundColor: _getColorForDesignation(designation),
              child: Text(
                avatarLetter,
                style: const TextStyle(
                    color: Colors.white, fontWeight: FontWeight.bold),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    fullName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    email,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.55),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: _getColorForDesignation(designation).withOpacity(0.18),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Text(
                designation.isNotEmpty ? designation : 'STAFF',
                style: TextStyle(
                  color: _getColorForDesignation(designation),
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBulkMentionTile(Map<String, dynamic> bulk) {
    final name = (bulk['fullName'] ?? '').toString().toUpperCase();
    final count = bulk['count'];

    final color = name == 'FOH'
        ? Colors.green
        : name == 'BOH'
            ? Colors.blue
            : Colors.purple;

    return InkWell(
      onTap: () {
        _insertMention(name);
        widget.onMentionSelected?.call({
          'type': 'bulk',
          'fullName': name,
          'designation': name,
          'mentionType': 'bulk',
          'mentionDisplay': '@$name',
        });
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            CircleAvatar(
              radius: 18,
              backgroundColor: color.withOpacity(0.9),
              child: Text(
                (bulk['avatar'] ?? '👥').toString(),
                style: const TextStyle(fontSize: 16),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: TextStyle(
                      color: color,
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    name == 'EVERYONE' || name == 'ALL'
                        ? 'Mention everyone'
                        : 'Mention all ${name.toLowerCase()} staff',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.55),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            if (count != null) ...[
              const SizedBox(width: 10),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.18),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Text(
                  '$count',
                  style: TextStyle(
                    color: color,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Color _getColorForDesignation(String designation) {
    switch (designation.toLowerCase()) {
      case 'manager':
        return Colors.purple;
      case 'am':
        return Colors.orange;
      case 'boh':
        return Colors.blue;
      case 'foh':
        return Colors.green;
      default:
        return const Color(0xFF4CC9F0);
    }
  }

  @override
  Widget build(BuildContext context) {
    return CompositedTransformTarget(
      link: _layerLink,
      child: TextField(
        controller: _controller,
        focusNode: _focusNode,
        maxLines: widget.maxLines,
        cursorColor: widget.cursorColor ?? const Color(0xFF4CC9F0),
        style: widget.style ?? const TextStyle(color: Colors.white),
        decoration: InputDecoration(
          hintText: widget.hintText,
          hintStyle: TextStyle(color: Colors.white.withOpacity(0.5)),
          border: InputBorder.none,
          contentPadding: widget.padding,
        ),
      ),
    );
  }
}
