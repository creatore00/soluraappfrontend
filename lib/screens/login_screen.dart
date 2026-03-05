import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import '../models/database_access.dart';
import 'database_selection_screen.dart';
import 'dashboard_screen.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final emailController = TextEditingController();
  final passwordController = TextEditingController();
  final storage = const FlutterSecureStorage();
  final auth = LocalAuthentication();

  bool loading = false;
  bool showPassword = false;
  String message = "";
  bool _autoLoginAttempted = false;

  // Secure storage keys
  static const _keyEmail = "email";
  static const _keyPassword = "password";
  static const _keyBiometricsEnabled = "biometrics_enabled";

  @override
  void initState() {
    super.initState();
    _tryAutoBiometricLogin();
  }

  Future<void> _tryAutoBiometricLogin() async {
    if (_autoLoginAttempted) return;
    _autoLoginAttempted = true;

    final enabled = await storage.read(key: _keyBiometricsEnabled);
    if (enabled != "true") return;

    final savedEmail = await storage.read(key: _keyEmail);
    final savedPassword = await storage.read(key: _keyPassword);
    if (savedEmail == null || savedPassword == null) return;

    if (!mounted) return;
    setState(() => loading = true);

    try {
      // Check if biometrics are available and enrolled
      final canCheck = await auth.canCheckBiometrics;
      final isSupported = await auth.isDeviceSupported();
      final availableBiometrics = await auth.getAvailableBiometrics();
      
      if (!canCheck || !isSupported || availableBiometrics.isEmpty) {
        setState(() => loading = false);
        return;
      }

      final success = await auth.authenticate(
        localizedReason: "Authenticate to access Solura",
      );

      if (!success) {
        setState(() => loading = false);
        return;
      }

      final result = await AuthService.login(savedEmail, savedPassword);
      if (!mounted) return;
      setState(() => loading = false);

      if (!result.success) {
        setState(() => message = result.message);
        return;
      }

      _navigateAfterLogin(savedEmail, result.databases);
    } catch (e) {
      print("Auto biometric error: $e");
      if (mounted) setState(() => loading = false);
    }
  }

  Future<bool> _checkBiometricAvailability() async {
    try {
      final canCheck = await auth.canCheckBiometrics;
      final isSupported = await auth.isDeviceSupported();
      final availableBiometrics = await auth.getAvailableBiometrics();
      
      print("Can check biometrics: $canCheck");
      print("Device supported: $isSupported");
      print("Available biometrics: $availableBiometrics");
      
      // Check if there are any biometrics enrolled
      return canCheck && isSupported && availableBiometrics.isNotEmpty;
    } catch (e) {
      print("Error checking biometrics: $e");
      return false;
    }
  }

  Future<bool> _askEnableBiometrics() async {
    // First check if biometrics are available and enrolled
    final isAvailable = await _checkBiometricAvailability();
    
    if (!isAvailable) {
      print("Biometrics not available for dialog");
      return false;
    }

    // Get the actual biometric types
    final availableBiometrics = await auth.getAvailableBiometrics();
    
    String biometricType = "Biometric";
    if (availableBiometrics.contains(BiometricType.face)) {
      biometricType = "Face ID";
    } else if (availableBiometrics.contains(BiometricType.fingerprint)) {
      biometricType = "Touch ID / Fingerprint";
    }

    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => Theme(
        data: ThemeData.dark().copyWith(
          dialogBackgroundColor: const Color(0xFF172A45),
        ),
        child: AlertDialog(
          backgroundColor: const Color(0xFF172A45),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: BorderSide(color: Colors.white.withOpacity(0.1), width: 1),
          ),
          title: const Text(
            "Enable Biometric Login?",
            style: TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.bold,
            ),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                biometricType.contains("Face") ? Icons.face : Icons.fingerprint,
                color: const Color(0xFF4CC9F0),
                size: 64,
              ),
              const SizedBox(height: 20),
              Text(
                "Would you like to use $biometricType for faster login next time?",
                style: TextStyle(
                  color: Colors.white.withOpacity(0.9),
                  fontSize: 16,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                "You'll be prompted to authenticate with your biometrics",
                style: TextStyle(
                  color: Colors.white.withOpacity(0.6),
                  fontSize: 14,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text(
                "Not Now",
                style: TextStyle(
                  color: Color(0xFF4CC9F0),
                  fontSize: 16,
                ),
              ),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF4CC9F0),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              ),
              child: const Text(
                "Enable",
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      ),
    );
    
    return result == true;
  }

  Future<void> handleLogin() async {
    final email = emailController.text.trim();
    final password = passwordController.text;

    if (email.isEmpty || password.isEmpty) {
      setState(() => message = "Please enter your email and password.");
      return;
    }

    setState(() {
      loading = true;
      message = "";
    });

    try {
      final result = await AuthService.login(email, password);
      if (!mounted) return;
      setState(() => loading = false);

      if (!result.success) {
        setState(() => message = result.message);
        return;
      }

      if (result.databases.isEmpty) {
        setState(() => message = "No workspaces available for this user.");
        return;
      }

      // Check if biometrics are available on the device
      final biometricsAvailable = await _checkBiometricAvailability();
      
      print("Biometrics available for dialog: $biometricsAvailable");

      // Ask to enable biometrics if supported
      bool enableBiometrics = false;
      
      if (biometricsAvailable) {
        enableBiometrics = await _askEnableBiometrics();
        print("User chose to enable biometrics: $enableBiometrics");
      }

      if (enableBiometrics) {
        // Test biometric authentication first
        try {
          final authenticated = await auth.authenticate(
            localizedReason: "Verify your identity to enable biometric login",
          );

          if (authenticated) {
            await storage.write(key: _keyEmail, value: email);
            await storage.write(key: _keyPassword, value: password);
            await storage.write(key: _keyBiometricsEnabled, value: "true");
            
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text("Biometric login enabled successfully!"),
                  backgroundColor: Colors.green,
                  duration: Duration(seconds: 2),
                ),
              );
            }
          } else {
            // If biometric test fails, don't enable
            await storage.write(key: _keyBiometricsEnabled, value: "false");
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text("Biometric authentication failed"),
                  backgroundColor: Colors.orange,
                ),
              );
            }
          }
        } catch (e) {
          print("Biometric test error: $e");
          await storage.write(key: _keyBiometricsEnabled, value: "false");
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text("Biometric error: ${e.toString().split('.').last}"),
                backgroundColor: Colors.red,
              ),
            );
          }
        }
      } else {
        // User declined biometrics or biometrics not available
        await storage.write(key: _keyBiometricsEnabled, value: "false");
        await storage.delete(key: _keyEmail);
        await storage.delete(key: _keyPassword);
      }

      _navigateAfterLogin(email, result.databases);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        loading = false;
        message = "Login error: ${e.toString()}";
      });
    }
  }

  void _navigateAfterLogin(String email, List<DatabaseAccess> databases) {
    if (!mounted) return;
    if (databases.length == 1) {
      Navigator.pushReplacement(
        context,
        PageRouteBuilder(
          pageBuilder: (context, animation, secondaryAnimation) => DashboardScreen(
            email: email,
            databases: databases,
            selectedDb: databases.first,
          ),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            const begin = Offset(1.0, 0.0);
            const end = Offset.zero;
            const curve = Curves.easeInOut;
            var tween = Tween(begin: begin, end: end).chain(CurveTween(curve: curve));
            return SlideTransition(
              position: animation.drive(tween),
              child: child,
            );
          },
        ),
      );
    } else {
      Navigator.pushReplacement(
        context,
        PageRouteBuilder(
          pageBuilder: (context, animation, secondaryAnimation) =>
              DatabaseSelectionScreen(email: email, databases: databases),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            const begin = Offset(1.0, 0.0);
            const end = Offset.zero;
            const curve = Curves.easeInOut;
            var tween = Tween(begin: begin, end: end).chain(CurveTween(curve: curve));
            return SlideTransition(
              position: animation.drive(tween),
              child: child,
            );
          },
        ),
      );
    }
  }

  @override
  void dispose() {
    emailController.dispose();
    passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;
    final screenWidth = MediaQuery.of(context).size.width;

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFF0A192F),
              Color(0xFF172A45),
              Color(0xFF1E3A5F),
            ],
            stops: [0.0, 0.5, 1.0],
          ),
        ),
        child: Stack(
          children: [
            // Decorative elements
            Positioned(
              top: -100,
              right: -100,
              child: Container(
                width: 300,
                height: 300,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      const Color(0xFF4CC9F0).withOpacity(0.1),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),
            Positioned(
              bottom: -50,
              left: -50,
              child: Container(
                width: 200,
                height: 200,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      const Color(0xFF4ADE80).withOpacity(0.1),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),

            SingleChildScrollView(
              child: SizedBox(
                height: screenHeight,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // Logo and App Name
                    Container(
                      width: 100,
                      height: 100,
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
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Center(
                        child: ClipOval(
                          child: Image.asset(
                            "assets/icon/icon.png",
                            width: 60,
                            height: 60,
                            fit: BoxFit.cover,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    const Text(
                      "Solura",
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 42,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.5,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      "Enterprise Dashboard",
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.7),
                        fontSize: 16,
                        letterSpacing: 3,
                      ),
                    ),
                    const SizedBox(height: 40),

                    // Login Card
                    Container(
                      width: screenWidth > 600 ? 500 : screenWidth * 0.9,
                      margin: const EdgeInsets.symmetric(horizontal: 20),
                      padding: const EdgeInsets.all(32),
                      decoration: BoxDecoration(
                        color: const Color(0xFF172A45).withOpacity(0.8),
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(color: Colors.white.withOpacity(0.1)),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.3),
                            blurRadius: 20,
                            offset: const Offset(0, 10),
                          ),
                        ],
                      ),
                      child: Column(
                        children: [
                          const Text(
                            "Welcome Back",
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 28,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            "Sign in to your workspace",
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.6),
                              fontSize: 16,
                            ),
                          ),
                          const SizedBox(height: 32),

                          // Email Field
                          Container(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(12),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.1),
                                  blurRadius: 5,
                                  offset: const Offset(0, 3),
                                ),
                              ],
                            ),
                            child: TextField(
                              controller: emailController,
                              style: const TextStyle(color: Colors.white),
                              decoration: InputDecoration(
                                labelText: "Email Address",
                                labelStyle: TextStyle(
                                  color: Colors.white.withOpacity(0.6),
                                ),
                                filled: true,
                                fillColor: Colors.white.withOpacity(0.05),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: BorderSide.none,
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: const BorderSide(
                                    color: Color(0xFF4CC9F0),
                                    width: 2,
                                  ),
                                ),
                                prefixIcon: Icon(
                                  Icons.email,
                                  color: Colors.white.withOpacity(0.6),
                                ),
                                contentPadding: const EdgeInsets.symmetric(
                                  vertical: 16,
                                  horizontal: 20,
                                ),
                              ),
                              keyboardType: TextInputType.emailAddress,
                            ),
                          ),
                          const SizedBox(height: 20),

                          // Password Field
                          Container(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(12),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.1),
                                  blurRadius: 5,
                                  offset: const Offset(0, 3),
                                ),
                              ],
                            ),
                            child: TextField(
                              controller: passwordController,
                              style: const TextStyle(color: Colors.white),
                              obscureText: !showPassword,
                              decoration: InputDecoration(
                                labelText: "Password",
                                labelStyle: TextStyle(
                                  color: Colors.white.withOpacity(0.6),
                                ),
                                filled: true,
                                fillColor: Colors.white.withOpacity(0.05),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: BorderSide.none,
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: const BorderSide(
                                    color: Color(0xFF4CC9F0),
                                    width: 2,
                                  ),
                                ),
                                prefixIcon: Icon(
                                  Icons.lock,
                                  color: Colors.white.withOpacity(0.6),
                                ),
                                suffixIcon: IconButton(
                                  icon: Icon(
                                    showPassword
                                        ? Icons.visibility
                                        : Icons.visibility_off,
                                    color: Colors.white.withOpacity(0.6),
                                  ),
                                  onPressed: () {
                                    setState(() {
                                      showPassword = !showPassword;
                                    });
                                  },
                                ),
                                contentPadding: const EdgeInsets.symmetric(
                                  vertical: 16,
                                  horizontal: 20,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 24),

                          // Error Message
                          if (message.isNotEmpty)
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.red.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: Colors.red.withOpacity(0.3),
                                ),
                              ),
                              child: Row(
                                children: [
                                  const Icon(
                                    Icons.error_outline,
                                    color: Colors.red,
                                    size: 20,
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Text(
                                      message,
                                      style: const TextStyle(
                                        color: Colors.red,
                                        fontSize: 14,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          if (message.isNotEmpty) const SizedBox(height: 16),

                          // Login Button
                          SizedBox(
                            width: double.infinity,
                            height: 56,
                            child: ElevatedButton(
                              onPressed: loading ? null : handleLogin,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF4CC9F0),
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                elevation: 0,
                                shadowColor: Colors.transparent,
                              ),
                              child: loading
                                  ? const SizedBox(
                                      width: 24,
                                      height: 24,
                                      child: CircularProgressIndicator(
                                        color: Colors.white,
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Row(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Text(
                                          "Sign In",
                                          style: TextStyle(
                                            fontSize: 18,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                        SizedBox(width: 8),
                                        Icon(Icons.arrow_forward, size: 20),
                                      ],
                                    ),
                            ),
                          ),

                          const SizedBox(height: 16),

                          // Footer
                          Text(
                            "© 2024 Solura Enterprise. All rights reserved.",
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.4),
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}