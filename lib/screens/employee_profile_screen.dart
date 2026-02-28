// ==================================
// FRONTEND: employee_profile_screen.dart (FULL)
// - GET /profile/employees
// - PATCH /profile/employees (allowlisted on backend)
// - Editable: email, phone, address, profile image
// - Read-only: name, lastName, nin, wage/salaryPrice, contractHours, startHoliday,
//              dateStart, designation, position
// - Wage hidden with show/hide
// - Salary=Yes => show SalaryPrice instead of wage
// - dateStart yyyy-mm-dd -> dd/mm/yyyy
// ==================================
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';

import '../models/database_access.dart';
import '../services/auth_service.dart';

class EmployeeProfileScreen extends StatefulWidget {
  final DatabaseAccess selectedDb;
  final String userEmail;

  const EmployeeProfileScreen({
    super.key,
    required this.selectedDb,
    required this.userEmail,
  });

  @override
  State<EmployeeProfileScreen> createState() => _EmployeeProfileScreenState();
}

class _EmployeeProfileScreenState extends State<EmployeeProfileScreen> {
  bool loading = true;
  bool saving = false;
  bool error = false;
  String errorMessage = "";

  bool showPay = false;

  // employee data
  String name = "";
  String lastName = "";
  String designation = "";
  String position = "";
  String nin = "";
  String contractHours = "";
  String startHoliday = "";
  String dateStartRaw = ""; // yyyy-mm-dd
  bool salaryYes = false;
  String wage = "";
  String salaryPrice = "";

  String profileImage = "";
  String profileImageMime = "";

  // editable
  final emailCtrl = TextEditingController();
  final phoneCtrl = TextEditingController();
  final addressCtrl = TextEditingController();

  // keep original email for update WHERE clause
  String originalEmail = "";

  @override
  void initState() {
    super.initState();
    fetchProfile();
  }

  @override
  void dispose() {
    emailCtrl.dispose();
    phoneCtrl.dispose();
    addressCtrl.dispose();
    super.dispose();
  }

  // yyyy-mm-dd -> dd/mm/yyyy
  String _fmtDateDMY(String ymd) {
    final s = ymd.trim();
    final parts = s.split("-");
    if (parts.length != 3) return s;
    final y = parts[0];
    final m = parts[1];
    final d = parts[2];
    if (y.isEmpty || m.isEmpty || d.isEmpty) return s;
    return "$d/$m/$y";
  }

  Uint8List? _imageBytesFromBase64(String b64) {
    if (b64.trim().isEmpty) return null;
    try {
      return base64Decode(b64);
    } catch (_) {
      return null;
    }
  }

  Future<void> fetchProfile() async {
    if (!mounted) return;

    setState(() {
      loading = true;
      error = false;
      errorMessage = "";
    });

    try {
      final uri = Uri.parse("${AuthService.baseUrl}/profile/employees").replace(
        queryParameters: {
          "db": widget.selectedDb.dbName,
          "email": widget.userEmail,
        },
      );

      final resp = await http.get(uri);

      if (resp.statusCode != 200) {
        throw Exception("Failed: ${resp.statusCode} - ${resp.body}");
      }

      final body = resp.body.trim();
      if (body.startsWith("<!DOCTYPE html>")) {
        throw Exception("Server returned HTML. Check backend route mapping for /profile/employees.");
      }

      final data = jsonDecode(body);
      if (data["success"] != true) {
        throw Exception(data["message"] ?? "Failed to fetch profile");
      }

      final e = (data["employee"] ?? {}) as Map<String, dynamic>;

      final fetchedEmail = (e["email"] ?? "").toString();

      if (!mounted) return;
      setState(() {
        name = (e["name"] ?? "").toString();
        lastName = (e["lastName"] ?? "").toString();
        designation = (e["designation"] ?? "").toString();
        position = (e["position"] ?? "").toString();

        nin = (e["nin"] ?? "").toString();
        contractHours = (e["contractHours"] ?? "").toString();
        startHoliday = (e["startHoliday"] ?? "").toString();
        dateStartRaw = (e["dateStart"] ?? "").toString();

        salaryYes = (e["salaryYes"] == true);
        wage = (e["wage"] ?? "").toString();
        salaryPrice = (e["salaryPrice"] ?? "").toString();

        profileImage = (e["profileImage"] ?? "").toString();
        profileImageMime = (e["profileImageMime"] ?? "").toString();

        originalEmail = fetchedEmail;

        emailCtrl.text = fetchedEmail;
        phoneCtrl.text = (e["phone"] ?? "").toString();
        addressCtrl.text = (e["address"] ?? "").toString();

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

  Future<void> _pickProfileImage() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery, imageQuality: 85);
    if (picked == null) return;

    final bytes = await picked.readAsBytes();
    final ext = picked.name.toLowerCase();

    String mime = "image/jpeg";
    if (ext.endsWith(".png")) mime = "image/png";
    if (ext.endsWith(".webp")) mime = "image/webp";
    if (ext.endsWith(".jpg") || ext.endsWith(".jpeg")) mime = "image/jpeg";

    setState(() {
      profileImage = base64Encode(bytes);
      profileImageMime = mime;
    });
  }

  void _removeProfileImage() {
    setState(() {
      profileImage = "";
      profileImageMime = "";
    });
  }

  Future<void> saveProfile() async {
    if (!mounted) return;

    setState(() {
      saving = true;
      error = false;
      errorMessage = "";
    });

    try {
      final uri = Uri.parse("${AuthService.baseUrl}/profile/employees");

      final updates = <String, dynamic>{
        "email": emailCtrl.text.trim(),
        "phone": phoneCtrl.text.trim(),
        "address": addressCtrl.text.trim(),
        "profileImage": profileImage.trim().isEmpty ? null : profileImage.trim(),
        "profileImageMime": profileImageMime.trim().isEmpty ? null : profileImageMime.trim(),
      };

      final payload = {
        "db": widget.selectedDb.dbName,
        // use originalEmail as WHERE email = ?
        "email": originalEmail,
        "updates": updates,
      };

      final resp = await http.patch(
        uri,
        headers: {"Content-Type": "application/json"},
        body: jsonEncode(payload),
      );

      final body = resp.body.trim();
      if (body.startsWith("<!DOCTYPE html>")) {
        throw Exception("Server returned HTML. Check backend route mapping for PATCH /profile/employees.");
      }

      final data = jsonDecode(body);

      if (resp.statusCode != 200 || data["success"] != true) {
        throw Exception(data["message"] ?? "Failed to save profile");
      }

      // if email changed, update originalEmail so next save works
      final newEmail = emailCtrl.text.trim();
      originalEmail = newEmail;

      if (!mounted) return;
      setState(() => saving = false);

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Profile updated")),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        saving = false;
        error = true;
        errorMessage = e.toString();
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Error: $e")),
      );
    }
  }

  Widget _field({
    required String label,
    required TextEditingController controller,
    bool readOnly = false,
    int maxLines = 1,
  }) {
    return TextField(
      controller: controller,
      readOnly: readOnly,
      maxLines: maxLines,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: Colors.white.withOpacity(0.7)),
        filled: true,
        fillColor: Colors.white.withOpacity(readOnly ? 0.03 : 0.06),
        enabledBorder: OutlineInputBorder(
          borderSide: BorderSide(color: Colors.white.withOpacity(0.12)),
          borderRadius: BorderRadius.circular(12),
        ),
        focusedBorder: OutlineInputBorder(
          borderSide: const BorderSide(color: Color(0xFF4CC9F0)),
          borderRadius: BorderRadius.circular(12),
        ),
      ),
    );
  }

  Widget _readonlyLine(String label, String value, {bool sensitive = false}) {
    final shown = !sensitive || showPay;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.04),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 12),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 12),
          Flexible(
            child: Text(
              shown ? (value.isEmpty ? "-" : value) : "••••••",
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }

  Color _roleColor(String role) {
    final r = role.trim().toUpperCase();
    if (r == "AM") return const Color(0xFF4CC9F0);
    if (r == "MANAGER") return const Color(0xFF4ADE80);
    if (r == "SUPERVISOR") return Colors.orange;
    if (r == "TM") return Colors.white.withOpacity(0.7);
    return Colors.white.withOpacity(0.6);
  }

  String _roleLabel(String role) {
    final r = role.trim().toUpperCase();
    if (r == "AM") return "Area Manager";
    if (r == "MANAGER") return "Manager";
    if (r == "SUPERVISOR") return "Supervisor";
    if (r == "TM") return "Team Member";
    return role.trim().isEmpty ? "-" : role.trim();
  }

  @override
  Widget build(BuildContext context) {
    final imgBytes = _imageBytesFromBase64(profileImage);

    return Scaffold(
      backgroundColor: const Color(0xFF0A192F),
      appBar: AppBar(
        backgroundColor: const Color(0xFF172A45),
        elevation: 0,
        title: const Text("My Profile", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Color(0xFF4CC9F0)),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            tooltip: "Refresh",
            icon: const Icon(Icons.refresh, color: Color(0xFF4CC9F0)),
            onPressed: fetchProfile,
          ),
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
          child: loading
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const CircularProgressIndicator(color: Color(0xFF4CC9F0)),
                      const SizedBox(height: 12),
                      Text("Loading profile...", style: TextStyle(color: Colors.white.withOpacity(0.7))),
                    ],
                  ),
                )
              : error
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.error_outline, size: 60, color: Colors.red.withOpacity(0.7)),
                          const SizedBox(height: 12),
                          Text("Failed to load profile", style: TextStyle(color: Colors.white.withOpacity(0.85), fontSize: 16)),
                          const SizedBox(height: 8),
                          Text(errorMessage, textAlign: TextAlign.center, style: TextStyle(color: Colors.white.withOpacity(0.6))),
                          const SizedBox(height: 14),
                          ElevatedButton(
                            onPressed: fetchProfile,
                            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF4CC9F0)),
                            child: const Text("Try Again"),
                          ),
                        ],
                      ),
                    )
                  : SingleChildScrollView(
                      padding: const EdgeInsets.only(bottom: 20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Header card
                          Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.03),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: Colors.white.withOpacity(0.1)),
                            ),
                            child: Row(
                              children: [
                                CircleAvatar(
                                  radius: 32,
                                  backgroundColor: Colors.white.withOpacity(0.08),
                                  backgroundImage: imgBytes != null ? MemoryImage(imgBytes) : null,
                                  child: imgBytes == null
                                      ? Text(
                                          "${name.isNotEmpty ? name[0].toUpperCase() : "?"}${lastName.isNotEmpty ? lastName[0].toUpperCase() : ""}",
                                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18),
                                        )
                                      : null,
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        "$name $lastName".trim(),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w800),
                                      ),
                                      const SizedBox(height: 6),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                        decoration: BoxDecoration(
                                          color: _roleColor(position).withOpacity(0.18),
                                          borderRadius: BorderRadius.circular(999),
                                          border: Border.all(color: _roleColor(position).withOpacity(0.35)),
                                        ),
                                        child: Text(
                                          _roleLabel(position),
                                          style: TextStyle(color: _roleColor(position), fontWeight: FontWeight.bold, fontSize: 12),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),

                          const SizedBox(height: 12),

                          // Image controls
                          Row(
                            children: [
                              Expanded(
                                child: ElevatedButton.icon(
                                  onPressed: _pickProfileImage,
                                  icon: const Icon(Icons.photo),
                                  label: const Text("Upload / Change"),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFF4CC9F0),
                                    foregroundColor: Colors.white,
                                    minimumSize: const Size(double.infinity, 46),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              ElevatedButton.icon(
                                onPressed: _removeProfileImage,
                                icon: const Icon(Icons.delete_outline),
                                label: const Text("Remove"),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.red.withOpacity(0.75),
                                  foregroundColor: Colors.white,
                                  minimumSize: const Size(120, 46),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                ),
                              ),
                            ],
                          ),

                          const SizedBox(height: 14),

                          // Editable fields
                          _field(label: "Email", controller: emailCtrl),
                          const SizedBox(height: 12),
                          _field(label: "Phone", controller: phoneCtrl),
                          const SizedBox(height: 12),
                          _field(label: "Address", controller: addressCtrl, maxLines: 2),

                          const SizedBox(height: 14),

                          // Read-only fields
                          _readonlyLine("Designation", designation),
                          const SizedBox(height: 10),
                          _readonlyLine("Position", _roleLabel(position)),
                          const SizedBox(height: 10),
                          _readonlyLine("Start date", _fmtDateDMY(dateStartRaw)),
                          const SizedBox(height: 10),
                          _readonlyLine("Contract hours", contractHours),
                          const SizedBox(height: 10),
                          _readonlyLine("Holiday allowance", startHoliday),

                          const SizedBox(height: 14),

                          // Pay section (hidden toggle)
                          Row(
                            children: [
                              Expanded(
                                child: _readonlyLine(
                                  salaryYes ? "Salary" : "Wage",
                                  salaryYes ? salaryPrice : wage,
                                  sensitive: true,
                                ),
                              ),
                              const SizedBox(width: 10),
                              ElevatedButton(
                                onPressed: () => setState(() => showPay = !showPay),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF1E3A5F),
                                  foregroundColor: Colors.white,
                                  minimumSize: const Size(90, 46),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                  side: BorderSide(color: const Color(0xFF4CC9F0).withOpacity(0.25)),
                                ),
                                child: Text(showPay ? "Hide" : "Show"),
                              ),
                            ],
                          ),

                          const SizedBox(height: 10),
                          _readonlyLine("NIN", nin, sensitive: true),

                          const SizedBox(height: 18),

                          // Save button
                          ElevatedButton(
                            onPressed: saving ? null : saveProfile,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF4CC9F0),
                              foregroundColor: Colors.white,
                              minimumSize: const Size(double.infinity, 50),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                            child: saving
                                ? const SizedBox(
                                    width: 22,
                                    height: 22,
                                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                  )
                                : const Text("Save Changes"),
                          ),
                        ],
                      ),
                    ),
        ),
      ),
    );
  }
}
