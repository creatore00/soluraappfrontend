import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import '../models/database_access.dart';
import '../services/auth_service.dart';
import 'holidays_screen.dart';
import 'earnings_screen.dart';
import 'hours_summary_screen.dart';
import 'dashboard_screen.dart';

class AllRotaScreen extends StatefulWidget {
  final String email;
  final DatabaseAccess selectedDb;

  const AllRotaScreen({
    super.key,
    required this.email,
    required this.selectedDb,
  });

  @override
  State<AllRotaScreen> createState() => _AllRotaScreenState();
}

class _AllRotaScreenState extends State<AllRotaScreen> {
  List<Map<String, dynamic>> rotaData = [];
  Map<String, List<Map<String, dynamic>>> rotaByDay = {};
  bool loading = true;
  DateTime currentWeekStart = DateTime.now();
  String currentWeekRange = '';
  String selectedDesignation = 'All';
  List<String> designations = ['All', 'BOH', 'FOH'];
  
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  Timer? _searchDebounce;

  @override
  void initState() {
    super.initState();
    _setCurrentWeek();
    fetchAllRota();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchDebounce?.cancel();
    super.dispose();
  }

  void _setCurrentWeek() {
    final now = DateTime.now();
    final monday = now.subtract(Duration(days: now.weekday - 1));
    setState(() {
      currentWeekStart = monday;
      currentWeekRange = _getWeekRange(monday);
    });
  }

  String _getWeekRange(DateTime weekStart) {
    final sunday = weekStart.add(const Duration(days: 6));
    final weekNumber = _getWeekNumber(weekStart);
    return 'Week $weekNumber: ${DateFormat('dd MMM').format(weekStart)} - ${DateFormat('dd MMM').format(sunday)}';
  }

  int _getWeekNumber(DateTime date) {
    final firstDayOfYear = DateTime(date.year, 1, 1);
    final daysDifference = date.difference(firstDayOfYear).inDays;
    return ((daysDifference + firstDayOfYear.weekday) / 7).ceil();
  }

  Future<void> _selectWeekFromCalendar() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: currentWeekStart,
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
      helpText: 'Select a week',
      initialEntryMode: DatePickerEntryMode.calendarOnly,
      builder: (context, child) {
        return Theme(
          data: ThemeData.dark().copyWith(
            colorScheme: const ColorScheme.dark(
              primary: Color(0xFF4CC9F0),
              onPrimary: Colors.white,
              surface: Color(0xFF172A45),
              onSurface: Colors.white,
            ),
            dialogBackgroundColor: const Color(0xFF172A45),
          ),
          child: child!,
        );
      },
    );
    
    if (picked != null) {
      final selectedMonday = picked.subtract(Duration(days: picked.weekday - 1));
      if (mounted) {
        setState(() {
          currentWeekStart = selectedMonday;
          currentWeekRange = _getWeekRange(selectedMonday);
        });
        await fetchAllRota();
      }
    }
  }

  void _goToPreviousWeek() {
    if (mounted) {
      setState(() {
        currentWeekStart = currentWeekStart.subtract(const Duration(days: 7));
        currentWeekRange = _getWeekRange(currentWeekStart);
        fetchAllRota();
      });
    }
  }

  void _goToNextWeek() {
    if (mounted) {
      setState(() {
        currentWeekStart = currentWeekStart.add(const Duration(days: 7));
        currentWeekRange = _getWeekRange(currentWeekStart);
        fetchAllRota();
      });
    }
  }

  void _goToCurrentWeek() {
    if (mounted) {
      setState(() {
        _setCurrentWeek();
        fetchAllRota();
      });
    }
  }

  Future<void> fetchAllRota() async {
    if (mounted) {
      setState(() => loading = true);
    }

    try {
      final monday = currentWeekStart;
      final sunday = monday.add(const Duration(days: 6));
      
      final queryParams = {
        'db': widget.selectedDb.dbName,
        'startDate': DateFormat('dd/MM/yyyy').format(monday),
        'endDate': DateFormat('dd/MM/yyyy').format(sunday),
      };

      final uri = Uri.parse("${AuthService.baseUrl}/all-rota")
          .replace(queryParameters: queryParams);

      final response = await http.get(uri);
      
      if (response.statusCode != 200) {
        throw Exception("Failed to fetch rota data: ${response.statusCode}");
      }

      final responseBody = response.body;
      if (responseBody.trim().isEmpty) {
        throw Exception("Empty response from server");
      }

      final List<dynamic> data = jsonDecode(responseBody);

      final List<Map<String, dynamic>> processedData = [];
      
      for (var entry in data) {
        try {
          final name = entry['name']?.toString() ?? '';
          final lastName = entry['lastName']?.toString() ?? '';
          final day = entry['day']?.toString() ?? '';
          final startTime = _formatTime(entry['startTime']?.toString() ?? '');
          final endTime = _formatTime(entry['endTime']?.toString() ?? '');
          final designation = entry['designation']?.toString() ?? '';
          
          if (startTime.isNotEmpty && endTime.isNotEmpty) {
            processedData.add({
              'name': name,
              'lastName': lastName,
              'fullName': '$name $lastName'.trim(),
              'day': day,
              'date': _extractDate(day),
              'startTime': startTime,
              'endTime': endTime,
              'designation': designation,
              'hours': _calculateHours(startTime, endTime),
              'timeFrame': '$startTime - $endTime',
            });
          }
        } catch (e) {
          print("Error processing rota entry: $e");
        }
      }

      if (mounted) {
        setState(() {
          rotaData = processedData;
          _groupDataByDay();
        });
      }
      
    } catch (e) {
      print("Error fetching all rota: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Error loading rota: ${e.toString()}"),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => loading = false);
      }
    }
  }

  void _groupDataByDay() {
    final Map<String, Map<String, Map<String, dynamic>>> groupedByDayAndEmployee = {};
    
    for (var entry in rotaData) {
      final day = entry['day'];
      final employeeKey = '${entry['fullName']}_${entry['designation']}';
      
      if (!groupedByDayAndEmployee.containsKey(day)) {
        groupedByDayAndEmployee[day] = {};
      }
      
      if (!groupedByDayAndEmployee[day]!.containsKey(employeeKey)) {
        groupedByDayAndEmployee[day]![employeeKey] = {
          'fullName': entry['fullName'],
          'name': entry['name'],
          'lastName': entry['lastName'],
          'day': day,
          'designation': entry['designation'],
          'timeFrames': <String>[],
          'totalHours': 0.0,
        };
      }
      
      final employeeData = groupedByDayAndEmployee[day]![employeeKey]!;
      final timeFrames = employeeData['timeFrames'] as List<String>;
      timeFrames.add(entry['timeFrame']);
      
      employeeData['totalHours'] = (employeeData['totalHours'] as double) + (entry['hours'] as double);
    }
    
    for (var day in groupedByDayAndEmployee.keys) {
      for (var employeeKey in groupedByDayAndEmployee[day]!.keys) {
        final employeeData = groupedByDayAndEmployee[day]![employeeKey]!;
        final timeFrames = employeeData['timeFrames'] as List<String>;
        timeFrames.sort((a, b) {
          final startA = a.split(' - ').first;
          final startB = b.split(' - ').first;
          return startA.compareTo(startB);
        });
      }
    }
    
    final Map<String, List<Map<String, dynamic>>> finalGroupedByDay = {};
    
    for (var day in groupedByDayAndEmployee.keys) {
      final employees = groupedByDayAndEmployee[day]!.values.toList();
      
      List<Map<String, dynamic>> filteredEmployees = employees;
      
      if (selectedDesignation != 'All') {
        filteredEmployees = employees.where((employee) => 
            employee['designation'] == selectedDesignation).toList();
      }
      
      if (_searchQuery.isNotEmpty) {
        filteredEmployees = filteredEmployees.where((employee) {
          final fullName = employee['fullName'].toString().toLowerCase();
          return fullName.contains(_searchQuery.toLowerCase());
        }).toList();
      }
      
      filteredEmployees.sort((a, b) {
        final designationA = a['designation'] as String;
        final designationB = b['designation'] as String;
        
        if (designationA != designationB) {
          if (designationA == 'BOH') return -1;
          if (designationB == 'BOH') return 1;
          return designationA.compareTo(designationB);
        }
        
        final lastNameA = a['lastName'] as String;
        final lastNameB = b['lastName'] as String;
        return lastNameA.compareTo(lastNameB);
      });
      
      if (filteredEmployees.isNotEmpty) {
        finalGroupedByDay[day] = filteredEmployees;
      }
    }
    
    if (mounted) {
      setState(() {
        rotaByDay = finalGroupedByDay;
      });
    }
  }

  String _extractDate(String dayStr) {
    try {
      if (dayStr.contains('(')) {
        return dayStr.split('(').first.trim();
      }
      return dayStr;
    } catch (_) {
      return dayStr;
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
      
      return diff.inMinutes / 60.0;
    } catch (e) {
      print("Error calculating hours for $start - $end: $e");
      return 0.0;
    }
  }

  void _onSearchChanged(String query) {
    if (_searchDebounce?.isActive ?? false) {
      _searchDebounce!.cancel();
    }
    
    _searchDebounce = Timer(const Duration(milliseconds: 300), () {
      if (mounted) {
        setState(() {
          _searchQuery = query;
          _groupDataByDay();
        });
      }
    });
  }

  void _clearSearch() {
    if (mounted) {
      setState(() {
        _searchController.clear();
        _searchQuery = '';
        _groupDataByDay();
      });
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
          // Hours Button (left)
          _buildNavButton(
            icon: Icons.access_time,
            label: 'Hours',
            onTap: () {
              // Need employee info for HoursSummaryScreen
              // For now, navigate to a simplified version or pass dummy data
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => HoursSummaryScreen(
                    email: widget.email,
                    selectedDb: widget.selectedDb,
                    employeeName: '', // This should come from your auth/user system
                    employeeLastName: '',
                  ),
                ),
              );
            },
          ),
          
          // Rota Button (left-middle) - Active
          _buildActiveNavButton(
            icon: Icons.calendar_today,
            label: 'Rota',
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

  // UI Components (keep your existing UI components as they are)
  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF172A45),
        border: Border(
          bottom: BorderSide(color: Colors.white.withOpacity(0.1)),
        ),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconButton(
                onPressed: _goToPreviousWeek,
                icon: const Icon(Icons.chevron_left, color: Colors.white),
                tooltip: 'Previous Week',
              ),
              Expanded(
                child: Column(
                  children: [
                    const Text(
                      "Weekly Rota",
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      currentWeekRange,
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.white.withOpacity(0.8),
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: _goToNextWeek,
                icon: const Icon(Icons.chevron_right, color: Colors.white),
                tooltip: 'Next Week',
              ),
            ],
          ),
          const SizedBox(height: 16),
          
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              ElevatedButton.icon(
                onPressed: _selectWeekFromCalendar,
                icon: const Icon(Icons.calendar_month, size: 16),
                label: const Text("Select Week"),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF4ADE80),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                ),
              ),
              
              ElevatedButton.icon(
                onPressed: _goToCurrentWeek,
                icon: const Icon(Icons.today, size: 16),
                label: const Text("This Week"),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF4CC9F0),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFilters() {
    return Container(
      padding: const EdgeInsets.all(16),
      margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
      decoration: BoxDecoration(
        color: const Color(0xFF1E3A5F),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
      ),
      child: Column(
        children: [
          Container(
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.05),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    onChanged: _onSearchChanged,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      hintText: "Search by name...",
                      hintStyle: TextStyle(color: Colors.white.withOpacity(0.4)),
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 14,
                      ),
                      prefixIcon: Icon(
                        Icons.search,
                        color: Colors.white.withOpacity(0.6),
                      ),
                    ),
                  ),
                ),
                if (_searchQuery.isNotEmpty)
                  IconButton(
                    onPressed: _clearSearch,
                    icon: Icon(
                      Icons.clear,
                      color: Colors.white.withOpacity(0.6),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          
          Row(
            children: [
              Icon(
                Icons.group,
                color: Colors.white.withOpacity(0.7),
                size: 20,
              ),
              const SizedBox(width: 8),
              Text(
                "Filter by role:",
                style: TextStyle(
                  color: Colors.white.withOpacity(0.8),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.05),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: DropdownButton<String>(
                    value: selectedDesignation,
                    dropdownColor: const Color(0xFF1E3A5F),
                    underline: const SizedBox(),
                    icon: const Icon(Icons.arrow_drop_down, color: Color(0xFF4CC9F0)),
                    isExpanded: true,
                    items: designations.map((designation) {
                      return DropdownMenuItem(
                        value: designation,
                        child: Text(
                          designation,
                          style: const TextStyle(color: Colors.white),
                        ),
                      );
                    }).toList(),
                    onChanged: (value) {
                      if (value != null && mounted) {
                        setState(() {
                          selectedDesignation = value;
                          _groupDataByDay();
                        });
                      }
                    },
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDayCard(String day, List<Map<String, dynamic>> employees) {
    final now = DateTime.now();
    final dayDate = DateFormat('dd/MM/yyyy').parse(_extractDate(day));
    final isToday = DateFormat('dd/MM/yyyy').format(now) == DateFormat('dd/MM/yyyy').format(dayDate);
    
    final bohEmployees = employees.where((e) => e['designation'] == 'BOH').toList();
    final fohEmployees = employees.where((e) => e['designation'] == 'FOH').toList();
    final otherEmployees = employees.where((e) => 
        e['designation'] != 'BOH' && e['designation'] != 'FOH').toList();
    
    return Container(
      margin: const EdgeInsets.only(bottom: 16, left: 16, right: 16),
      decoration: BoxDecoration(
        color: const Color(0xFF1E3A5F),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isToday 
              ? const Color(0xFF4CC9F0)
              : Colors.white.withOpacity(0.1),
          width: isToday ? 2 : 1,
        ),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: isToday 
                  ? const Color(0xFF4CC9F0).withOpacity(0.1)
                  : Colors.white.withOpacity(0.03),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(12),
                topRight: Radius.circular(12),
              ),
            ),
            child: Row(
              children: [
                if (isToday)
                  Container(
                    width: 8,
                    height: 8,
                    margin: const EdgeInsets.only(right: 8),
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: Color(0xFF4ADE80),
                    ),
                  ),
                Expanded(
                  child: Text(
                    day,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: isToday ? const Color(0xFF4CC9F0) : Colors.white,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Text(
                    '${employees.length}',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.9),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
          
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (bohEmployees.isNotEmpty)
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text(
                          'Back of House',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: const Color(0xFF4ADE80),
                          ),
                        ),
                      ),
                      _buildEmployeeList(bohEmployees),
                      const SizedBox(height: 16),
                    ],
                  ),
                
                if (fohEmployees.isNotEmpty)
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text(
                          'Front of House',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: const Color(0xFF4CC9F0),
                          ),
                        ),
                      ),
                      _buildEmployeeList(fohEmployees),
                      const SizedBox(height: 16),
                    ],
                  ),
                
                if (otherEmployees.isNotEmpty)
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text(
                          'Other Staff',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: Colors.white.withOpacity(0.8),
                          ),
                        ),
                      ),
                      _buildEmployeeList(otherEmployees),
                    ],
                  ),
              ],
            ),
          ),
        ],
      )
    );
  }

  Widget _buildEmployeeList(List<Map<String, dynamic>> employees) {
    return Column(
      children: employees.map((employee) {
        final timeFrames = employee['timeFrames'] as List<String>;
        final totalHours = employee['totalHours'] as double;
        
        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.03),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.white.withOpacity(0.05)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      employee['fullName'],
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: employee['designation'] == 'BOH'
                            ? const Color(0xFF4ADE80).withOpacity(0.2)
                            : employee['designation'] == 'FOH'
                                ? const Color(0xFF4CC9F0).withOpacity(0.2)
                                : Colors.white.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        employee['designation'],
                        style: TextStyle(
                          fontSize: 11,
                          color: employee['designation'] == 'BOH'
                              ? const Color(0xFF4ADE80)
                              : employee['designation'] == 'FOH'
                                  ? const Color(0xFF4CC9F0)
                                  : Colors.white.withOpacity(0.7),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (var timeFrame in timeFrames)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Text(
                          timeFrame,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              
              Container(
                width: 60,
                alignment: Alignment.centerRight,
                child: Text(
                  '${totalHours.toStringAsFixed(1)}h',
                  style: const TextStyle(
                    color: Color(0xFF4CC9F0),
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.schedule,
            size: 64,
            color: Colors.white.withOpacity(0.3),
          ),
          const SizedBox(height: 16),
          Text(
            "No rota data found",
            style: TextStyle(
              color: Colors.white.withOpacity(0.7),
              fontSize: 18,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            "for the selected week and filters",
            style: TextStyle(
              color: Colors.white.withOpacity(0.5),
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 24),
          if (_searchQuery.isNotEmpty || selectedDesignation != 'All')
            ElevatedButton(
              onPressed: () {
                _clearSearch();
                if (mounted) {
                  setState(() {
                    selectedDesignation = 'All';
                  });
                }
                _groupDataByDay();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF4CC9F0),
                foregroundColor: Colors.white,
              ),
              child: const Text("Clear Filters"),
            ),
        ],
      ),
    );
  }

  Widget _buildLoadingState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const CircularProgressIndicator(color: Color(0xFF4CC9F0)),
          const SizedBox(height: 16),
          Text(
            "Loading rota data...",
            style: TextStyle(
              color: Colors.white.withOpacity(0.7),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final List<String> weekDays = [];
    for (int i = 0; i < 7; i++) {
      final day = currentWeekStart.add(Duration(days: i));
      final dayStr = DateFormat('dd/MM/yyyy (EEEE)').format(day);
      weekDays.add(dayStr);
    }

    return Scaffold(
      backgroundColor: const Color(0xFF0A192F),
      appBar: AppBar(
        backgroundColor: const Color(0xFF172A45),
        elevation: 0,
        title: const Text(
          "Weekly Rota",
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Color(0xFF4CC9F0)),
            onPressed: fetchAllRota,
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: Column(
        children: [
          _buildHeader(),
          _buildFilters(),
          Expanded(
            child: loading
                ? _buildLoadingState()
                : rotaByDay.isEmpty
                    ? _buildEmptyState()
                    : ListView.builder(
                        padding: const EdgeInsets.only(top: 8, bottom: 24),
                        itemCount: weekDays.length,
                        itemBuilder: (context, index) {
                          final day = weekDays[index];
                          final employees = rotaByDay[day] ?? [];
                          
                          if (employees.isEmpty) {
                            return const SizedBox();
                          }
                          
                          return _buildDayCard(day, employees);
                        },
                      ),
          ),
        ],
      ),
      bottomNavigationBar: _buildBottomNavigationBar(),
    );
  }
}