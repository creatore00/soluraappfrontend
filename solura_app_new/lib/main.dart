import 'package:flutter/material.dart';

import 'screens/login_screen.dart';
import 'screens/dashboard_screen.dart';
import 'services/session.dart';
import 'models/database_access.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final hasSession = await Session.load();
  runApp(SoluraApp(hasSession: hasSession));
}

class SoluraApp extends StatelessWidget {
  final bool hasSession;
  const SoluraApp({super.key, required this.hasSession});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Solura',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.light(useMaterial3: true),
      home: hasSession ? const SessionGate() : const LoginScreen(),
    );
  }
}

/// ✅ Ensures session still valid when opening app.
/// If expired -> login.
/// If valid -> dashboard.
class SessionGate extends StatelessWidget {
  const SessionGate({super.key});

  @override
  Widget build(BuildContext context) {
    // extra safety check
    if (Session.isExpired()) {
      return const LoginScreen();
    }

    // IMPORTANT:
    // Dashboard should fetch databases from backend OR you pass them here.
    // If you already fetch DBs in dashboard, pass empty is ok.
    // But you said you want to be able to SELECT database after reopen.
    // That means you need DB list loaded somewhere.

    return DashboardScreen(
      email: Session.email!,
      databases: Session.databases,
      selectedDb: DatabaseAccess(
        dbName: Session.db!,
        access: Session.role!,
      ),
    );
  }
}
