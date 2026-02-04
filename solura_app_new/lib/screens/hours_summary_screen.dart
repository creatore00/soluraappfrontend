import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import '../models/database_access.dart';
import '../services/auth_service.dart';
import 'all_rota_screen.dart';
import 'holidays_screen.dart';
import 'earnings_screen.dart';
import 'dashboard_screen.dart';

class HoursSummaryScreen extends StatefulWidget {
  final String email;
  final DatabaseAccess selectedDb;
  final String employeeName;
  final String employeeLastName;

  const HoursSummaryScreen({
    super.key,
    required this.email,
    required this.selectedDb,
    required this.employeeName,
    required this.employeeLastName,
  });

  @override
  State<HoursSummaryScreen> createState() => _HoursSummaryScreenState();
}

enum HoursView { daily, weekly, monthly }

class _HoursSummaryScreenState extends State<HoursSummaryScreen> {
  List<Map<String, dynamic>> rotaData = [];
  bool loading = false;
  HoursView selectedView = HoursView.weekly;
  DateTime selectedMonth = DateTime.now();

  String? _name;
  String? _lastName;
  bool _loadingEmployee = false;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    _name = widget.employeeName.trim().isNotEmpty ? widget.employeeName.trim() : null;
    _lastName = widget.employeeLastName.trim().isNotEmpty ? widget.employeeLastName.trim() : null;

    if (_name == null || _lastName == null) {
      await _loadEmployeeFromEmail();
    }

    if (!mounted) return;

    if ((_name ?? "").isEmpty || (_lastName ?? "").isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Employee info not loaded. Please login again.")),
      );
      return;
    }

    await fetchRota(month: selectedMonth.month, year: selectedMonth.year);
  }

  Future<void> fetchRota({int? month, int? year}) async {
  setState(() {
    loading = true;
    rotaData = [];
  });

  try {
    final currentMonth = month ?? DateTime.now().month;
    final currentYear = year ?? DateTime.now().year;
    
    if (month != null && year != null) {
      selectedMonth = DateTime(year, month);
    }

    // Add debug logging
    print("Fetching rota with params:");
    print("Database: ${widget.selectedDb.dbName}");
    print("Name: ${widget.employeeName}");
    print("LastName: ${widget.employeeLastName}");
    print("Month: $currentMonth");
    print("Year: $currentYear");

    // URL encode parameters to handle special characters
    final queryParams = {
      'db': widget.selectedDb.dbName,
      'name': _name ?? widget.employeeName,
      'lastName': _lastName ?? widget.employeeLastName,
      'month': currentMonth.toString(),
      'year': currentYear.toString(),
    };

    // Construct URL with better error handling
    final baseUrl = AuthService.baseUrl;
    final endpoint = "/confirmedRota";
    
    print("Full URL: $baseUrl$endpoint");
    
    final uri = Uri.parse("$baseUrl$endpoint")
        .replace(queryParameters: queryParams);

    print("Final URI: ${uri.toString()}");

    final response = await http.get(uri);
    
    print("Response status: ${response.statusCode}");
    print("Response body: ${response.body}");

    if (response.statusCode != 200) {
      throw Exception("Failed to fetch confirmed rota: ${response.statusCode} - ${response.body}");
    }

    final responseBody = response.body;
    if (responseBody.trim().isEmpty) {
      throw Exception("Empty response from server");
    }

    final List<dynamic> data = jsonDecode(responseBody);
    
    print("Received ${data.length} entries");

    final List<Map<String, dynamic>> processedData = [];
    
    for (var entry in data) {
      try {
        final day = entry['day']?.toString() ?? '';
        final startTime = entry['startTime']?.toString() ?? '';
        final endTime = entry['endTime']?.toString() ?? '';
        
        print("Processing entry: day=$day, start=$startTime, end=$endTime");
        
        processedData.add({
          'day': day,
          'startTime': _formatTime(startTime),
          'endTime': _formatTime(endTime),
          'hours': _calculateHours(_formatTime(startTime), _formatTime(endTime)),
        });
      } catch (e) {
        print("Error processing entry: $e, entry: $entry");
      }
    }

    setState(() {
      rotaData = processedData;
    });
    
  } catch (e, stackTrace) {
    print("Error in fetchRota: $e");
    print("Stack trace: $stackTrace");
    
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Error fetching hours: ${e.toString()}"),
          backgroundColor: Colors.red,
        ),
      );
    }
  } finally {
    if (mounted) setState(() => loading = false);
  }
}

  String _formatTime(String time) {
    if (time.isEmpty) return '';
    
    try {
      if (time.contains(':')) {
        final parts = time.split(':');
        if (parts.length >= 2) {
          final hour = parts[0].padLeft(2, '0');
          final minute = parts[1].padLeft(2, '0');
          return '$hour:$minute';
        }
      }
      return time;
    } catch (_) {
      return time;
    }
  }

  double _calculateHours(String start, String end) {
    if (start.isEmpty || end.isEmpty) return 0.0;

    try {
      final format = DateFormat('HH:mm');
      final startTime = format.parse(start);
      final endTime = format.parse(end);
      
      Duration diff;
      if (endTime.isBefore(startTime)) {
        final nextDay = endTime.add(const Duration(days: 1));
        diff = nextDay.difference(startTime);
      } else {
        diff = endTime.difference(startTime);
      }
      
      final hours = diff.inMinutes / 60.0;
      return hours;
    } catch (e) {
      print("Error calculating hours for $start - $end: $e");
      return 0.0;
    }
  }

  Map<String, double> _aggregateByDay() {
    final Map<String, double> result = {};
    
    for (var entry in rotaData) {
      final day = entry['day']?.toString() ?? 'Unknown';
      final hours = entry['hours'] as double? ?? 0.0;
      
      String displayDay = day;
      try {
        if (day.contains('(')) {
          displayDay = day;
        } else {
          final parsedDate = DateFormat('dd/MM/yyyy').parse(day);
          final dayName = DateFormat('EEEE').format(parsedDate);
          displayDay = '$day ($dayName)';
        }
      } catch (_) {}
      
      result[displayDay] = (result[displayDay] ?? 0) + hours;
    }
    
    return result;
  }

  Map<String, double> _aggregateByWeek() {
    final Map<String, double> weekResult = {};
    
    for (var entry in rotaData) {
      final dayStr = entry['day']?.toString() ?? '';
      final hours = entry['hours'] as double? ?? 0.0;
      
      try {
        String datePart = dayStr;
        if (dayStr.contains('(')) {
          datePart = dayStr.split('(').first.trim();
        }
        
        final parsedDate = DateFormat('dd/MM/yyyy').parse(datePart);
        final monday = parsedDate.subtract(Duration(days: parsedDate.weekday - 1));
        final weekKey = 'Week of ${DateFormat('dd/MM/yyyy').format(monday)}';
        
        weekResult[weekKey] = (weekResult[weekKey] ?? 0) + hours;
      } catch (e) {
        print("Error aggregating by week for day $dayStr: $e");
      }
    }
    
    return weekResult;
  }

  double _aggregateMonthly() {
    double total = 0.0;
    for (var entry in rotaData) {
      total += entry['hours'] as double? ?? 0.0;
    }
    return total;
  }

  Widget _buildDataTable() {
    if (selectedView == HoursView.daily) {
      final daily = _aggregateByDay();
      if (daily.isEmpty) {
        return _buildEmptyState("No daily data available for selected month");
      }
      
      final sortedKeys = daily.keys.toList()..sort((a, b) {
        try {
          String dateA = a.contains('(') ? a.split('(').first.trim() : a;
          String dateB = b.contains('(') ? b.split('(').first.trim() : b;
          
          final da = DateFormat('dd/MM/yyyy').parse(dateA);
          final db = DateFormat('dd/MM/yyyy').parse(dateB);
          return da.compareTo(db);
        } catch (_) {
          return a.compareTo(b);
        }
      });
      
      return SingleChildScrollView(
        child: DataTable(
          headingRowColor: MaterialStateProperty.all(Colors.white.withOpacity(0.05)),
          headingTextStyle: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
          dataRowColor: MaterialStateProperty.resolveWith<Color?>(
            (Set<MaterialState> states) {
              return Colors.white.withOpacity(0.02);
            },
          ),
          columnSpacing: 24,
          horizontalMargin: 16,
          columns: const [
            DataColumn(
              label: Text("Day"),
              numeric: false,
            ),
            DataColumn(
              label: Text("Hours Worked"),
              numeric: false,
            ),
          ],
          rows: sortedKeys.map((day) {
            final hours = daily[day]!;
            return DataRow(
              cells: [
                DataCell(
                  Text(
                    day,
                    style: const TextStyle(color: Colors.white),
                  ),
                ),
                DataCell(
                  Text(
                    '${hours.toStringAsFixed(2)}h',
                    style: TextStyle(
                      color: const Color(0xFF4CC9F0),
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            );
          }).toList(),
        ),
      );
      
    } else if (selectedView == HoursView.weekly) {
      final weekly = _aggregateByWeek();
      if (weekly.isEmpty) {
        return _buildEmptyState("No weekly data available for selected month");
      }
      
      final sortedKeys = weekly.keys.toList()..sort((a, b) {
        try {
          final weekA = a.replaceAll('Week of ', '');
          final weekB = b.replaceAll('Week of ', '');
          final da = DateFormat('dd/MM/yyyy').parse(weekA);
          final db = DateFormat('dd/MM/yyyy').parse(weekB);
          return da.compareTo(db);
        } catch (_) {
          return a.compareTo(b);
        }
      });
      
      return SingleChildScrollView(
        child: DataTable(
          headingRowColor: MaterialStateProperty.all(Colors.white.withOpacity(0.05)),
          headingTextStyle: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
          dataRowColor: MaterialStateProperty.resolveWith<Color?>(
            (Set<MaterialState> states) {
              return Colors.white.withOpacity(0.02);
            },
          ),
          columnSpacing: 24,
          horizontalMargin: 16,
          columns: const [
            DataColumn(
              label: Text("Week Starting"),
              numeric: false,
            ),
            DataColumn(
              label: Text("Hours Worked"),
              numeric: false,
            ),
          ],
          rows: sortedKeys.map((week) {
            final hours = weekly[week]!;
            return DataRow(
              cells: [
                DataCell(
                  Text(
                    week,
                    style: const TextStyle(color: Colors.white),
                  ),
                ),
                DataCell(
                  Text(
                    '${hours.toStringAsFixed(2)}h',
                    style: TextStyle(
                      color: const Color(0xFF4CC9F0),
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            );
          }).toList(),
        ),
      );
      
    } else {
      final monthlyHours = _aggregateMonthly();
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(32),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    const Color(0xFF4CC9F0).withOpacity(0.2),
                    const Color(0xFF1E3A5F).withOpacity(0.3),
                  ],
                ),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: const Color(0xFF4CC9F0).withOpacity(0.3)),
              ),
              child: Column(
                children: [
                  Text(
                    DateFormat('MMMM yyyy').format(selectedMonth),
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Colors.white.withOpacity(0.8),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    '${monthlyHours.toStringAsFixed(2)}',
                    style: const TextStyle(
                      fontSize: 48,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF4CC9F0),
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Hours',
                    style: TextStyle(
                      fontSize: 18,
                      color: Colors.white70,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    '${rotaData.length} ${rotaData.length == 1 ? 'Shift' : 'Shifts'}',
                    style: TextStyle(
                      fontSize: 16,
                      color: Colors.white.withOpacity(0.6),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }
  }

  Widget _buildEmptyState(String message) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.hourglass_empty,
            size: 64,
            color: Colors.white.withOpacity(0.3),
          ),
          const SizedBox(height: 16),
          Text(
            message,
            style: TextStyle(
              color: Colors.white.withOpacity(0.6),
              fontSize: 16,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Future<void> _loadEmployeeFromEmail() async {
    if (_loadingEmployee) return;
    setState(() => _loadingEmployee = true);

    try {
      final uri = Uri.parse("${AuthService.baseUrl}/employee").replace(
        queryParameters: {
          "email": widget.email.trim(),
          "db": widget.selectedDb.dbName,
        },
      );

      final res = await http.get(uri);
      if (res.statusCode != 200) return;

      final data = jsonDecode(res.body);
      if (data is Map && data["success"] == true) {
        _name = (data["name"] ?? "").toString().trim();
        _lastName = (data["lastName"] ?? "").toString().trim();
      }
    } catch (_) {
      // ignore
    } finally {
      if (mounted) setState(() => _loadingEmployee = false);
    }
  }

  Future<void> _pickMonth() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: selectedMonth,
      firstDate: DateTime(now.year - 5),
      lastDate: DateTime(now.year + 5),
      initialDatePickerMode: DatePickerMode.year,
      builder: (context, child) {
        return Theme(
          data: ThemeData.dark().copyWith(
            colorScheme: const ColorScheme.dark(
              primary: Color(0xFF4CC9F0),
              onPrimary: Colors.white,
              surface: Color(0xFF0A192F),
              onSurface: Colors.white,
            ),
            dialogBackgroundColor: const Color(0xFF172A45),
          ),
          child: child!,
        );
      },
    );
    if (picked != null && mounted) {
      await fetchRota(month: picked.month, year: picked.year);
    }
  }

  // Bottom Navigation Bar Methods
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
          // Hours Button (left) - Active
          _buildActiveNavButton(
            icon: Icons.access_time,
            label: 'Hours',
          ),
          
          // Rota Button (left-middle)
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
                    selectedDb: widget.selectedDb,
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

  Widget _buildActiveNavButton({
    required IconData icon,
    required String label,
  }) {
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
            child: Icon(
              icon,
              color: const Color(0xFF4CC9F0),
              size: 24,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              color: Color(0xFF4CC9F0),
              fontWeight: FontWeight.bold,
            ),
          ),
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A192F),
      appBar: AppBar(
        backgroundColor: const Color(0xFF172A45),
        elevation: 0,
        title: const Text(
          "Hours Summary",
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
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
          child: Column(
            children: [
              // Month selector and view selector
              Container(
                padding: const EdgeInsets.all(16),
                margin: const EdgeInsets.only(bottom: 20),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.white.withOpacity(0.1)),
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: _pickMonth,
                            icon: const Icon(Icons.calendar_today, size: 20),
                            label: Text(
                              DateFormat('MMMM yyyy').format(selectedMonth),
                              style: const TextStyle(fontSize: 16),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF1E3A5F),
                              foregroundColor: Colors.white,
                              minimumSize: const Size(double.infinity, 50),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                                side: BorderSide(color: const Color(0xFF4CC9F0).withOpacity(0.3)),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Container(
                          width: 1,
                          height: 40,
                          color: Colors.white.withOpacity(0.1),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            decoration: BoxDecoration(
                              color: const Color(0xFF1E3A5F),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: const Color(0xFF4CC9F0).withOpacity(0.3)),
                            ),
                            child: DropdownButton<HoursView>(
                              value: selectedView,
                              dropdownColor: const Color(0xFF1E3A5F),
                              underline: const SizedBox(),
                              icon: const Icon(Icons.arrow_drop_down, color: Color(0xFF4CC9F0)),
                              isExpanded: true,
                              items: const [
                                DropdownMenuItem(
                                  value: HoursView.daily,
                                  child: Text(
                                    "Daily View",
                                    style: TextStyle(color: Colors.white),
                                  ),
                                ),
                                DropdownMenuItem(
                                  value: HoursView.weekly,
                                  child: Text(
                                    "Weekly View",
                                    style: TextStyle(color: Colors.white),
                                  ),
                                ),
                                DropdownMenuItem(
                                  value: HoursView.monthly,
                                  child: Text(
                                    "Monthly Total",
                                    style: TextStyle(color: Colors.white),
                                  ),
                                ),
                              ],
                              onChanged: (v) {
                                if (v != null && mounted) setState(() => selectedView = v);
                              },
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              
              // Employee info card
              Container(
                padding: const EdgeInsets.all(16),
                margin: const EdgeInsets.only(bottom: 20),
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
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: const Color(0xFF4CC9F0).withOpacity(0.2),
                        border: Border.all(color: const Color(0xFF4CC9F0).withOpacity(0.3)),
                      ),
                      child: const Icon(
                        Icons.person,
                        color: Color(0xFF4CC9F0),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            "${_name ?? widget.employeeName} ${_lastName ?? widget.employeeLastName}",
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              Icon(
                                Icons.work,
                                size: 14,
                                color: Colors.white.withOpacity(0.6),
                              ),
                              const SizedBox(width: 4),
                              Text(
                                widget.selectedDb.dbName,
                                style: TextStyle(
                                  fontSize: 14,
                                  color: Colors.white.withOpacity(0.7),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              
              Expanded(
                child: loading
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const CircularProgressIndicator(color: Color(0xFF4CC9F0)),
                            const SizedBox(height: 16),
                            Text(
                              "Loading hours data...",
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.7),
                              ),
                            ),
                          ],
                        ),
                      )
                    : rotaData.isEmpty
                        ? _buildEmptyState(
                            "No confirmed hours found for ${widget.employeeName} ${widget.employeeLastName}\nin ${DateFormat('MMMM yyyy').format(selectedMonth)}"
                          )
                        : Container(
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.03),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: Colors.white.withOpacity(0.1)),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(12),
                                    margin: const EdgeInsets.only(bottom: 16),
                                    decoration: BoxDecoration(
                                      color: Colors.white.withOpacity(0.05),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Row(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Icon(
                                          Icons.info_outline,
                                          size: 16,
                                          color: Colors.white.withOpacity(0.6),
                                        ),
                                        const SizedBox(width: 8),
                                        Text(
                                          "Showing ${rotaData.length} ${rotaData.length == 1 ? 'confirmed shift' : 'confirmed shifts'}",
                                          style: TextStyle(
                                            color: Colors.white.withOpacity(0.7),
                                            fontSize: 14,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Expanded(
                                    child: _buildDataTable(),
                                  ),
                                ],
                              ),
                            ),
                          ),
              ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: _buildBottomNavigationBar(),
    );
  }
}