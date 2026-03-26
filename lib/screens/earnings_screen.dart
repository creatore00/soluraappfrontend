import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:open_file/open_file.dart';
import 'dart:io';
import '../models/database_access.dart';
import '../services/auth_service.dart';
import 'dashboard_screen.dart';
import 'hours_summary_screen.dart';
import 'all_rota_screen.dart';
import 'holidays_screen.dart';

class EarningsScreen extends StatefulWidget {
  final String email;
  final DatabaseAccess selectedDb;

  const EarningsScreen({
    super.key,
    required this.email,
    required this.selectedDb,
  });

  @override
  State<EarningsScreen> createState() => _EarningsScreenState();
}

class _EarningsScreenState extends State<EarningsScreen> {
  List<Map<String, dynamic>> _payslips = [];
  bool _isLoading = true;
  String? _selectedMonth;
  List<String> _availableMonths = [];
  
  // Track which payslip is being downloaded
  Set<int> _downloadingIds = {};

  @override
  void initState() {
    super.initState();
    _fetchAvailableMonths();
  }

  Future<void> _fetchAvailableMonths() async {
    try {
      final response = await http.get(
        Uri.parse(
          "${AuthService.baseUrl}/employee/payslip-months?db=${widget.selectedDb.dbName}&email=${widget.email}"
        ),
      );
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] && data['months'] != null) {
          setState(() {
            _availableMonths = List<String>.from(data['months'].map((m) => m['value']));
            if (_availableMonths.isNotEmpty) {
              _selectedMonth = _availableMonths.first;
            }
          });
          await _fetchPayslips();
        } else {
          setState(() {
            _isLoading = false;
          });
        }
      } else {
        setState(() {
          _isLoading = false;
        });
      }
    } catch (e) {
      print('Error fetching months: $e');
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _fetchPayslips() async {
    if (_selectedMonth == null) return;
    
    setState(() {
      _isLoading = true;
      _payslips = [];
    });
    
    try {
      final url = "${AuthService.baseUrl}/employee/payslips?"
          "db=${widget.selectedDb.dbName}"
          "&email=${widget.email}"
          "&month=${Uri.encodeComponent(_selectedMonth!)}"
          "&page=1"
          "&limit=5";
      
      final response = await http.get(Uri.parse(url));
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success']) {
          setState(() {
            _payslips = List<Map<String, dynamic>>.from(data['payslips']);
            _isLoading = false;
          });
        } else {
          setState(() {
            _isLoading = false;
          });
          _showErrorSnackBar(data['message'] ?? 'Failed to load earnings');
        }
      } else {
        setState(() {
          _isLoading = false;
        });
        _showErrorSnackBar('Server error');
      }
    } catch (e) {
      print('Error fetching earnings: $e');
      setState(() {
        _isLoading = false;
      });
      _showErrorSnackBar('Network error');
    }
  }

  Future<void> _downloadPayslip(int id, String month, int payslipNumber) async {
    if (_downloadingIds.contains(id)) return;
    
    setState(() {
      _downloadingIds.add(id);
    });
    
    try {
      final response = await http.get(
        Uri.parse("${AuthService.baseUrl}/employee/download-payslip/$id?db=${widget.selectedDb.dbName}&email=${widget.email}"),
      );
      
      if (response.statusCode == 200) {
        final bytes = response.bodyBytes;
        final directory = await getApplicationDocumentsDirectory();
        final monthDisplay = _formatMonthDisplay(month);
        
        // Get file extension from Content-Type header
        String fileExt = 'pdf';
        final contentType = response.headers['content-type'];
        
        if (contentType != null) {
          if (contentType.contains('image/png')) {
            fileExt = 'png';
          } else if (contentType.contains('image/jpeg')) {
            fileExt = 'jpg';
          } else if (contentType.contains('application/pdf')) {
            fileExt = 'pdf';
          }
        }
        
        final fileName = 'earnings_${widget.email.split('@')[0]}_${monthDisplay.replaceAll(' ', '_')}_${payslipNumber}.$fileExt';
        final filePath = '${directory.path}/$fileName';
        final file = File(filePath);
        await file.writeAsBytes(bytes);
        
        // Open the file
        await OpenFile.open(filePath);
        _showSuccessSnackBar('Earnings statement downloaded');
      } else {
        _showErrorSnackBar('Failed to download earnings statement');
      }
    } catch (e) {
      print('Error downloading earnings statement: $e');
      _showErrorSnackBar('Error downloading earnings statement');
    } finally {
      setState(() {
        _downloadingIds.remove(id);
      });
    }
  }

  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.redAccent,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  void _showSuccessSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.green,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  String _formatDate(String dateString) {
    if (dateString.isEmpty) return 'No date';
    try {
      final date = DateTime.parse(dateString);
      return DateFormat('dd/MM/yyyy').format(date);
    } catch (e) {
      return dateString;
    }
  }

  String _formatMonthDisplay(String monthYear) {
    if (monthYear.isEmpty) return '';
    final parts = monthYear.split('-');
    if (parts.length != 2) return monthYear;
    final year = parts[0];
    final month = int.parse(parts[1]);
    const monthNames = [
      'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December'
    ];
    return '${monthNames[month - 1]} $year';
  }

  String _getMonthDisplay(String month) {
    final monthNames = {
      '01': 'January', '02': 'February', '03': 'March', '04': 'April',
      '05': 'May', '06': 'June', '07': 'July', '08': 'August',
      '09': 'September', '10': 'October', '11': 'November', '12': 'December'
    };
    final parts = month.split('-');
    if (parts.length != 2) return month;
    return '${monthNames[parts[1]]} ${parts[0]}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A192F),
      appBar: AppBar(
        backgroundColor: const Color(0xFF172A45),
        elevation: 0,
        title: const Text(
          "Earnings",
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
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
            colors: [
              Color(0xFF0A192F),
              Color(0xFF172A45),
              Color(0xFF0A192F),
            ],
          ),
        ),
        child: Column(
          children: [
            // Month Selector
            Container(
              margin: const EdgeInsets.all(16),
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: const Color(0xFF172A45),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: const Color(0xFF4CC9F0).withOpacity(0.3),
                ),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: _selectedMonth,
                  isExpanded: true,
                  hint: const Text(
                    'Select Month',
                    style: TextStyle(color: Colors.white70),
                  ),
                  dropdownColor: const Color(0xFF172A45),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                  ),
                  icon: const Icon(
                    Icons.arrow_drop_down,
                    color: Color(0xFF4CC9F0),
                    size: 32,
                  ),
                  items: _availableMonths.map((month) {
                    return DropdownMenuItem<String>(
                      value: month,
                      child: Row(
                        children: [
                          const Icon(Icons.calendar_month, color: Color(0xFF4CC9F0), size: 20),
                          const SizedBox(width: 12),
                          Text(_getMonthDisplay(month), style: const TextStyle(color: Colors.white)),
                        ],
                      ),
                    );
                  }).toList(),
                  onChanged: (String? newValue) {
                    setState(() {
                      _selectedMonth = newValue;
                    });
                    _fetchPayslips();
                  },
                ),
              ),
            ),
            
            // Payslips List
            Expanded(
              child: _buildPayslipsList(),
            ),
          ],
        ),
      ),
      bottomNavigationBar: _buildBottomNavigationBar(),
    );
  }

  Widget _buildPayslipsList() {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(
          color: Color(0xFF4CC9F0),
        ),
      );
    }
    
    if (_payslips.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.attach_money_outlined,
              size: 80,
              color: Colors.white.withOpacity(0.3),
            ),
            const SizedBox(height: 16),
            Text(
              _selectedMonth != null 
                  ? 'No earnings found for ${_getMonthDisplay(_selectedMonth!)}' 
                  : 'Select a month to view earnings',
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
    
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _payslips.length,
      itemBuilder: (context, index) {
        return _buildEarningsCard(_payslips[index]);
      },
    );
  }

  Widget _buildEarningsCard(Map<String, dynamic> payslip) {
    final int id = payslip['id'];
    final String month = payslip['month'];
    final String monthDisplay = payslip['monthDisplay'] ?? _getMonthDisplay(month);
    final String uploadDate = payslip['uploadDate'] ?? '';
    final int payslipNumber = payslip['payslipNumber'] ?? 1;
    final bool isDownloading = _downloadingIds.contains(id);
    
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: const Color(0xFF172A45),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Colors.white.withOpacity(0.1),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF4CC9F0).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    Icons.attach_money,
                    color: const Color(0xFF4CC9F0),
                    size: 28,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        monthDisplay,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        payslipNumber == 1 ? 'First Payslip' : 'Second Payslip',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.6),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                if (isDownloading)
                  const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Color(0xFF4CC9F0),
                    ),
                  )
                else
                  ElevatedButton.icon(
                    onPressed: () => _downloadPayslip(id, month, payslipNumber),
                    icon: const Icon(Icons.download, size: 18),
                    label: const Text('Download'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF4CC9F0),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Divider(
              color: Colors.white.withOpacity(0.1),
              height: 1,
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(
                  Icons.calendar_today,
                  size: 14,
                  color: Colors.white.withOpacity(0.5),
                ),
                const SizedBox(width: 8),
                Text(
                  'Issued: ${_formatDate(uploadDate)}',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.5),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
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
          _buildNavButton(
            icon: Icons.access_time,
            label: 'Hours',
            onTap: () {
              Navigator.pushReplacement(
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
              Navigator.pushReplacement(
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
          _buildNavButton(
            icon: Icons.beach_access,
            label: 'Holidays',
            onTap: () {
              Navigator.pushReplacement(
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
          _buildActiveNavButton(
            icon: Icons.attach_money,
            label: 'Earnings',
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
                Navigator.of(context).pushAndRemoveUntil(
                  MaterialPageRoute(
                    builder: (_) => DashboardScreen(
                      email: widget.email,
                      databases: [widget.selectedDb],
                      selectedDb: widget.selectedDb,
                    ),
                  ),
                  (route) => false,
                );
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
}