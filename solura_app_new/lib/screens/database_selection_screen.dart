import 'package:flutter/material.dart';
import '../models/database_access.dart';
import 'dashboard_screen.dart';
import '../services/session.dart';


class DatabaseSelectionScreen extends StatelessWidget {
  final String email;
  final List<DatabaseAccess> databases;

  const DatabaseSelectionScreen({
    super.key,
    required this.email,
    required this.databases,
  });

  void selectDatabase(BuildContext context, DatabaseAccess db) async {
    Session.email = email;
    Session.db = db.dbName;
    Session.role = db.access;

    await Session.save(); // ✅ persists login

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => DashboardScreen(
          email: email,
          databases: databases,
          selectedDb: db,
        ),
      ),
    );
  }


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        width: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [
              Color(0xFF061A2D), // deep matte navy
              Color(0xFF0B2A45), // navy blue
              Color(0xFF0E3A5C), // slightly lighter navy
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 22),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 30),

                // Title
                const Text(
                  "Select Workspace",
                  style: TextStyle(
                    fontSize: 30,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                    letterSpacing: 0.4,
                  ),
                ),
                const SizedBox(height: 10),

                // Subtitle
                Text(
                  "Choose the workspace you want to access",
                  style: TextStyle(
                    fontSize: 16,
                    color: Colors.white.withOpacity(0.75),
                    height: 1.3,
                  ),
                ),

                const SizedBox(height: 30),

                // List
                Expanded(
                  child: ListView.separated(
                    physics: const BouncingScrollPhysics(),
                    itemCount: databases.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 14),
                    itemBuilder: (context, index) {
                      final db = databases[index];

                      return InkWell(
                        onTap: () => selectDatabase(context, db),
                        borderRadius: BorderRadius.circular(16),
                        child: Ink(
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.08),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: Colors.white.withOpacity(0.10),
                            ),
                            boxShadow: const [
                              BoxShadow(
                                color: Colors.black45,
                                blurRadius: 12,
                                offset: Offset(0, 6),
                              ),
                            ],
                          ),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 18,
                              vertical: 18,
                            ),
                            child: Row(
                              children: [
                                // Icon
                                Container(
                                  width: 46,
                                  height: 46,
                                  decoration: BoxDecoration(
                                    color: Colors.white.withOpacity(0.12),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: const Icon(
                                    Icons.workspaces_outline,
                                    color: Colors.white,
                                    size: 24,
                                  ),
                                ),

                                const SizedBox(width: 14),

                                // Texts
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        db.dbName,
                                        style: const TextStyle(
                                          fontSize: 18,
                                          fontWeight: FontWeight.w700,
                                          color: Colors.white,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        db.access,
                                        style: TextStyle(
                                          fontSize: 14,
                                          color: Colors.white.withOpacity(0.70),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),

                                // Chevron
                                Icon(
                                  Icons.chevron_right_rounded,
                                  color: Colors.white.withOpacity(0.75),
                                  size: 28,
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),

                const SizedBox(height: 18),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
