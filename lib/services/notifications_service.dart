import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'auth_service.dart';
import 'session.dart';

class NotificationsService {
  static final FirebaseMessaging _fcm = FirebaseMessaging.instance;
  static final FlutterLocalNotificationsPlugin _localNotifications = 
      FlutterLocalNotificationsPlugin();

  // Initialize push notifications
  static Future<void> initPushNotifications() async {
    try {
      // 1. Richiedi permessi
      NotificationSettings settings = await _fcm.requestPermission(
        alert: true,
        badge: true,
        sound: true,
        provisional: true,
      );

      print('🔔 Notification permissions: ${settings.authorizationStatus}');

      if (settings.authorizationStatus != AuthorizationStatus.authorized) {
        print('⚠️ User declined notification permissions');
        return;
      }

      // 2. CREA IL CANALE PRINCIPALE PER LE ROTA NOTIFICATIONS
      const AndroidNotificationChannel rotaChannel = AndroidNotificationChannel(
        'rota_notifications', // 🔴 IMPORTANTE: deve coincidere col backend!
        'Rota Notifications',
        description: 'Notifiche per pubblicazione turni e aggiornamenti',
        importance: Importance.high,
      );

      await _localNotifications
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(rotaChannel);

      print('✅ Canale "rota_notifications" creato');

      // 3. CREA IL CANALE GENERICO PER ALTRE NOTIFICHE
      const AndroidNotificationChannel highChannel = AndroidNotificationChannel(
        'high_importance_channel',
        'High Importance Notifications',
        description: 'This channel is used for important notifications.',
        importance: Importance.high,
      );

      await _localNotifications
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(highChannel);

      print('✅ Canale "high_importance_channel" creato');

      // 4. Inizializza local notifications con l'icona
      const AndroidInitializationSettings androidSettings = 
          AndroidInitializationSettings('@drawable/icon');
      
      const DarwinInitializationSettings iosSettings = 
          DarwinInitializationSettings(
        requestAlertPermission: true,
        requestBadgePermission: true,
        requestSoundPermission: true,
      );
      
      const InitializationSettings initSettings = InitializationSettings(
        android: androidSettings,
        iOS: iosSettings,
      );

      await _localNotifications.initialize(
        initSettings,
        onDidReceiveNotificationResponse: (NotificationResponse response) {
          _handleNotificationTap(response);
        },
      );

      print('✅ Local notifications initialized');

      // 5. Gestisci notifiche in FOREGROUND
      FirebaseMessaging.onMessage.listen(_handleForegroundMessage);

      // 6. Gestisci quando l'app viene aperta da notifica (background)
      FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
        print('📱 App aperta da notifica in background');
        if (message.data.isNotEmpty) {
          final response = NotificationResponse(
            payload: jsonEncode(message.data),
            notificationResponseType: NotificationResponseType.selectedNotification,
          );
          _handleNotificationTap(response);
        }
      });

      // 7. Gestisci quando l'app viene aperta da notifica (killed state)
      RemoteMessage? initialMessage = await _fcm.getInitialMessage();
      if (initialMessage != null) {
        print('📱 App aperta da notifica in killed state');
        if (initialMessage.data.isNotEmpty) {
          final response = NotificationResponse(
            payload: jsonEncode(initialMessage.data),
            notificationResponseType: NotificationResponseType.selectedNotification,
          );
          _handleNotificationTap(response);
        }
      }

      // 8. Ottieni e registra il token FCM
      String? token = await _fcm.getToken();
      if (token != null) {
        print('🔑 FCM Token ottenuto: ${token.substring(0, 20)}...');
        // Non aspettare - fire and forget
        _registerDeviceToken(token).catchError((e) {
          print('⚠️ Token registration failed (non-critical): $e');
        });
      } else {
        print('⚠️ FCM Token è null');
      }

      // 9. Ascolta i refresh del token
      _fcm.onTokenRefresh.listen((token) {
        print('🔄 FCM token refreshed: ${token.substring(0, 20)}...');
        _registerDeviceToken(token).catchError((e) {
          print('⚠️ Token refresh registration failed: $e');
        });
      });

      print('✅ Notifications service initialized successfully');
      
    } catch (e) {
      print('❌ Error initializing push notifications: $e');
    }
  }

  // Register device token with backend
  static Future<void> _registerDeviceToken(String token) async {
    try {
      final email = await Session.getEmail();
      final userId = await Session.getUserId();
      final dbName = await Session.getDb();
      
      // Only register if we have all required data
      if (email != null && userId != null && dbName != null) {
        print('📱 Registering device for: $email in $dbName');
        print('   Token: ${token.substring(0, 20)}...');
        
        final response = await http.post(
          Uri.parse('${AuthService.baseUrl}/register-device'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'userId': userId,
            'email': email,
            'fcmToken': token,
            'deviceType': 'android',
            'dbName': dbName,
          }),
        ).timeout(const Duration(seconds: 5));

        print('📡 Response status: ${response.statusCode}');
        
        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          if (data['success'] == true) {
            print('✅ Device registered successfully');
          } else {
            print('⚠️ Device registration failed: ${data['message']}');
          }
        } else {
          print('⚠️ Device registration failed with status: ${response.statusCode}');
          print('📡 Response body: ${response.body}');
        }
      } else {
        print('⚠️ Cannot register device: missing user data');
        print('   email: $email, userId: $userId, dbName: $dbName');
      }
    } catch (e) {
      // Don't rethrow - this is non-critical
      print('⚠️ Device registration error (non-critical): $e');
    }
  }

  // Handle foreground messages - MOSTRA NOTIFICHE QUANDO L'APP È APERTA
  static void _handleForegroundMessage(RemoteMessage message) {
    print('📱 NOTIFICA IN FOREGROUND: ${message.notification?.title}');
    
    RemoteNotification? notification = message.notification;
    
    if (notification != null) {
      // Determina quale canale usare in base al tipo di notifica
      String channelId = 'high_importance_channel';
      String channelName = 'High Importance Notifications';
      
      // Se è una notifica di rota, usa il canale specifico
      if (message.data['type'] == 'SYSTEM' && 
          message.data['notificationSubtype'] == 'ROTA') {
        channelId = 'rota_notifications';
        channelName = 'Rota Notifications';
      }
      
      _localNotifications.show(
        notification.hashCode,
        notification.title,
        notification.body,
        NotificationDetails(
          android: AndroidNotificationDetails(
            channelId,
            channelName,
            channelDescription: 'Notifiche importanti',
            importance: Importance.high,
            priority: Priority.high,
            icon: '@drawable/icon',
          ),
          iOS: const DarwinNotificationDetails(
            presentAlert: true,
            presentBadge: true,
            presentSound: true,
          ),
        ),
        payload: jsonEncode(message.data),
      );
      
      print('✅ Notifica locale mostrata per foreground message');
    }
  }

  // Handle notification tap
  static void _handleNotificationTap(NotificationResponse response) {
    if (response.payload != null) {
      try {
        final data = jsonDecode(response.payload!);
        print('📱 Notification tapped: $data');
        
        // Qui puoi aggiungere la logica per navigare a schermate specifiche
        // Esempio: se è una notifica di rota, apri la schermata delle rota
        
        // Puoi usare un stream o un callback per comunicare con la UI
        // _notificationStreamController.add(data);
        
      } catch (e) {
        print('❌ Error parsing notification payload: $e');
      }
    }
  }

  // Fetch notifications from backend
  static Future<List<Map<String, dynamic>>> fetchNotifications({
    required String db,
    required String role,
  }) async {
    try {
      final email = await Session.getEmail();
      final uri = Uri.parse("${AuthService.baseUrl}/notifications").replace(
        queryParameters: {
          "db": db,
          "role": role,
          "userEmail": email ?? '',
        }.map((key, value) => MapEntry(key, value.toString())),
      );
      
      print('📡 Fetching notifications from: $uri');
      final res = await http.get(uri).timeout(const Duration(seconds: 10));

      if (res.statusCode != 200) {
        throw Exception("Failed to fetch notifications (${res.statusCode})");
      }

      final body = res.body.trim();
      if (body.startsWith('<!DOCTYPE html>')) {
        throw Exception("Server returned HTML error page");
      }

      final data = jsonDecode(body);
      if (data['success'] != true) {
        throw Exception(data['message'] ?? "Unknown error");
      }

      final notifications = List<Map<String, dynamic>>.from(data['notifications'] ?? []);
      print('📊 Fetched ${notifications.length} notifications');
      return notifications;
      
    } catch (e) {
      print('❌ Error fetching notifications: $e');
      return [];
    }
  }

  // Mark as read
  static Future<void> markAsRead({
    required String db,
    required int id,
  }) async {
    try {
      final uri = Uri.parse("${AuthService.baseUrl}/notifications/read");
      final res = await http.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'db': db, 'id': id}),
      ).timeout(const Duration(seconds: 10));

      if (res.statusCode != 200) {
        throw Exception("Failed to mark as read");
      }

      final data = jsonDecode(res.body);
      if (data['success'] != true) {
        throw Exception(data['message'] ?? "Failed to mark as read");
      }
      
      print('✅ Notification $id marked as read');
    } catch (e) {
      print('❌ Error marking notification as read: $e');
      rethrow;
    }
  }

  // Send notification to a specific user
  static Future<bool> sendNotificationToUser({
    required String db,
    required String targetEmail,
    required String title,
    required String message,
    String? type,
    int? postId,
  }) async {
    try {
      final uri = Uri.parse("${AuthService.baseUrl}/notifications/send");
      final response = await http.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'db': db,
          'targetEmail': targetEmail,
          'title': title,
          'message': message,
          'type': type ?? 'info',
          'postId': postId,
        }),
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['success'] == true;
      }
      return false;
    } catch (e) {
      print('❌ Error sending notification: $e');
      return false;
    }
  }

  // Send notification to a role (ALL users with that role)
  static Future<bool> sendNotificationToRole({
    required String db,
    required String targetRole,
    required String title,
    required String message,
    String? type,
    int? postId,
  }) async {
    try {
      final uri = Uri.parse("${AuthService.baseUrl}/notifications/send-to-role");
      final response = await http.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'db': db,
          'targetRole': targetRole,
          'title': title,
          'message': message,
          'type': type ?? 'info',
          'postId': postId,
        }),
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['success'] == true;
      }
      return false;
    } catch (e) {
      print('❌ Error sending notification to role: $e');
      return false;
    }
  }

  // Send notification with FCM push
  static Future<bool> sendPushNotification({
    required String db,
    required String targetEmail,
    required String targetRole,
    required String title,
    required String message,
    String? type,
    int? postId,
  }) async {
    try {
      final uri = Uri.parse("${AuthService.baseUrl}/notifications/send-push");
      final response = await http.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'db': db,
          'targetEmail': targetEmail,
          'targetRole': targetRole,
          'title': title,
          'message': message,
          'type': type ?? 'info',
          'postId': postId,
        }),
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['success'] == true;
      }
      return false;
    } catch (e) {
      print('❌ Error sending push notification: $e');
      return false;
    }
  }

  // Get unread count
  static Future<int> fetchUnreadCount({
    required String db,
    required String role,
  }) async {
    try {
      final email = await Session.getEmail();
      final uri = Uri.parse("${AuthService.baseUrl}/notifications/unread-count").replace(
        queryParameters: {
          "db": db,
          "role": role,
          "userEmail": email ?? '',
        }.map((key, value) => MapEntry(key, value.toString())),
      );
      
      print('📡 Fetching unread count from: $uri');
      final res = await http.get(uri).timeout(const Duration(seconds: 5));
      
      print('📡 Response status: ${res.statusCode}');
      
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        if (data['success'] == true) {
          final count = data['count'] ?? 0;
          print('📊 Unread count: $count');
          return count;
        }
      }
      return 0;
    } catch (e) {
      print('❌ Error fetching unread count: $e');
      return 0;
    }
  }

  // Mark all notifications as read
  static Future<void> markAllAsRead({
    required String db,
    required String role,
  }) async {
    try {
      final email = await Session.getEmail();
      
      print('📝 Marking all notifications as read for $email in $db');
      
      final uri = Uri.parse("${AuthService.baseUrl}/notifications/mark-all-read");
      final res = await http.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'db': db,
          'role': role,
          'userEmail': email ?? '',
        }),
      ).timeout(const Duration(seconds: 10));

      if (res.statusCode != 200) {
        throw Exception("Failed to mark all as read (${res.statusCode})");
      }

      final data = jsonDecode(res.body);
      if (data['success'] != true) {
        throw Exception(data['message'] ?? "Failed to mark all as read");
      }
      
      final count = data['markedCount'] ?? 'all';
      print('✅ Successfully marked $count notifications as read');
      
    } catch (e) {
      print('❌ Error marking all as read: $e');
      rethrow;
    }
  }
}

// Background message handler (deve essere una funzione top-level)
@pragma('vm:entry-point')
Future<void> _firebaseBackgroundHandler(RemoteMessage message) async {
  print("📱 Handling background message: ${message.messageId}");
  print("📱 Data: ${message.data}");
  
  // Non puoi fare operazioni UI qui, ma puoi salvare dati, fare chiamate API, ecc.
  // La notifica verrà mostrata automaticamente dal sistema grazie al payload
}