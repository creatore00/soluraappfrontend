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

class SessionGate extends StatelessWidget {
  const SessionGate({super.key});

  @override
  Widget build(BuildContext context) {
    if (Session.isExpired()) return const LoginScreen();

    final email = Session.email;
    final role = Session.role;
    final dbName = Session.db;

    if (email == null || email.trim().isEmpty) return const LoginScreen();
    if (role == null || role.trim().isEmpty) return const LoginScreen();
    if (dbName == null || dbName.trim().isEmpty) return const LoginScreen();

    return DashboardScreen(
      email: email,
      databases: Session.databases,
      selectedDb: DatabaseAccess(
        dbName: dbName,
        access: role,
      ),
    );
  }
}