// lib/services/device_registration_service.dart
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:firebase_messaging/firebase_messaging.dart';
import 'auth_service.dart';
import 'session.dart';

class DeviceRegistrationService {
  static final FirebaseMessaging _fcm = FirebaseMessaging.instance;

  // Chiamare questa funzione DOPO il login
  static Future<void> registerCurrentDevice() async {
     try {
    final email = await Session.getEmail();
    final userId = await Session.getUserId();
    final dbName = await Session.getDb();
    
    print('🔍 REGISTER DEVICE - Valori sessione:');
    print('   email: $email');
    print('   userId: $userId');
    print('   dbName: $dbName');
    
    if (email == null || userId == null || dbName == null) {
      print('❌ REGISTER DEVICE FALLITO - Dati mancanti');
      print('   email: $email, userId: $userId, dbName: $dbName');
      return;
    }

      // Ottieni il token FCM
      String? token = await _fcm.getToken();
      if (token == null) {
        print('⚠️ Cannot register device: no FCM token');
        return;
      }

      print('📱 Registering device for: $email in $dbName');
      
      // Chiama il backend
      final response = await http.post(
        Uri.parse('${AuthService.baseUrl}/register-device'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'userId': userId,
          'email': email,
          'fcmToken': token,
          'deviceType': 'android', // o 'ios' a seconda della piattaforma
          'dbName': dbName,
        }),
      ).timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true) {
          print('✅ Device registered successfully');
        } else {
          print('⚠️ Device registration failed: ${data['message']}');
        }
      } else {
        print('⚠️ Device registration failed with status: ${response.statusCode}');
      }
    } catch (e) {
      // Non bloccare l'app se la registrazione fallisce
      print('⚠️ Device registration error (non-critical): $e');
    }
  }

  // Ascolta i refresh del token FCM
  static void listenForTokenRefresh() {
    _fcm.onTokenRefresh.listen((newToken) {
      print('🔄 FCM token refreshed: $newToken');
      // Registra il nuovo token
      registerCurrentDevice();
    });
  }
}