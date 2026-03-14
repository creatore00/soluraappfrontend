import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  static final FlutterLocalNotificationsPlugin _notifications = 
      FlutterLocalNotificationsPlugin();

  // Inizializza le notifiche locali
  Future<void> init() async {
    print('📱 ===== INIZIO INIT NOTIFICATION SERVICE =====');
    
    try {
      // Inizializza timezone
      print('📱 1. Inizializzo timezone...');
      tz.initializeTimeZones();
      print('📱 ✅ Timezone inizializzata');
      
      // Configura Android - usa un'icona che esiste sempre
      print('📱 2. Configuro Android con icona: @drawable/ic_stat_notify');
      const AndroidInitializationSettings androidSettings = 
          AndroidInitializationSettings('@drawable/ic_stat_notify'); // 🔴 CAMBIATO!
      
      // Configura iOS
      print('📱 3. Configuro iOS...');
      const DarwinInitializationSettings iosSettings = 
          DarwinInitializationSettings(
        requestAlertPermission: true,
        requestBadgePermission: true,
        requestSoundPermission: true,
      );
      
      print('📱 4. Creo InitializationSettings...');
      const InitializationSettings initSettings = InitializationSettings(
        android: androidSettings,
        iOS: iosSettings,
      );

      print('📱 5. Inizializzo _notifications...');
      await _notifications.initialize(
        initSettings,
        onDidReceiveNotificationResponse: (NotificationResponse response) {
          print('📱 Notifica tappata: ${response.payload}');
          // Qui puoi gestire il tap sulla notifica
        },
      );
      print('📱 ✅ _notifications.initialize completato');
      
      // Crea canale per Android
      print('📱 6. Creo canale Android "test_channel"...');
      const AndroidNotificationChannel channel = AndroidNotificationChannel(
        'test_channel',
        'Test Notifications',
        description: 'Canale per notifiche di test',
        importance: Importance.high,
      );
      print('📱 ✅ Canale creato');

      print('📱 7. Creo canale nel sistema Android...');
      await _notifications
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(channel);
      print('📱 ✅ Canale creato nel sistema');

      print('📱 ✅ NOTIFICATION SERVICE INITIALIZED SUCCESSFULLY');
      
    } catch (e, stackTrace) {
      print('📱 ❌ ERRORE IN INIT: $e');
      print('📱 📍 StackTrace: $stackTrace');
    }
    
    print('📱 ===== FINE INIT NOTIFICATION SERVICE =====');
  }

  // Test immediato (mostra subito) - VERSIONE CORRETTA
  Future<void> testImmediate() async {
    print('📱 ===== INIZIO TEST IMMEDIATE =====');
    
    try {
      print('📱 1. Chiamo show con ID: 1');
      print('📱 2. Titolo: "🔔 Notifica Immediata"');
      print('📱 3. Corpo: "Questa notifica appare SUBITO!"');
      
      await _notifications.show(
        1,
        '🔔 Notifica Immediata',
        'Questa notifica appare SUBITO!',
        const NotificationDetails(
          android: AndroidNotificationDetails(
            'test_channel',
            'Test Notifications',
            importance: Importance.high,
            priority: Priority.high,
            icon: '@drawable/ic_stat_notify', // 🔴 ICONA CORRETTA
            // 🔴 NESSUN SUONO PERSONALIZZATO - usa default
          ),
          iOS: DarwinNotificationDetails(
            presentAlert: true,
            presentBadge: true,
            presentSound: true,
          ),
        ),
      );
      
      print('📱 ✅ show completato senza errori');
      print('📱 ✅ Immediate notification shown');
      
    } catch (e, stackTrace) {
      print('📱 ❌ ERRORE IN TESTIMMEDIATE: $e');
      print('📱 📍 StackTrace: $stackTrace');
    }
    
    print('📱 ===== FINE TEST IMMEDIATE =====');
  }

  // Test semplice - notifica dopo 5 secondi - VERSIONE CORRETTA
  Future<void> testNow() async {
    print('📱 ===== INIZIO TEST NOW =====');
    
    try {
      final now = tz.TZDateTime.now(tz.local);
      final scheduledTime = now.add(const Duration(seconds: 5));
      
      print('📱 1. Ora attuale: $now');
      print('📱 2. Ora programmata: $scheduledTime');
      print('📱 3. Titolo: "🔔 Test Notifica"');
      print('📱 4. Corpo: "Questa è una notifica di test locale"');
      
      await _notifications.zonedSchedule(
        0,
        '🔔 Test Notifica',
        'Questa è una notifica di test locale',
        scheduledTime,
        const NotificationDetails(
          android: AndroidNotificationDetails(
            'test_channel',
            'Test Notifications',
            importance: Importance.high,
            priority: Priority.high,
            icon: '@drawable/ic_stat_notify', // 🔴 ICONA CORRETTA
          ),
          iOS: DarwinNotificationDetails(
            presentAlert: true,
            presentBadge: true,
            presentSound: true,
          ),
        ),
        androidScheduleMode: AndroidScheduleMode.exact,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
      );
      
      print('📱 ✅ zonedSchedule completato');
      print('📱 ✅ Test notification scheduled for 5 seconds from now');
      
    } catch (e, stackTrace) {
      print('📱 ❌ ERRORE IN TESTNOW: $e');
      print('📱 📍 StackTrace: $stackTrace');
    }
    
    print('📱 ===== FINE TEST NOW =====');
  }

  // Test ogni minuto - VERSIONE CORRETTA
  Future<void> startPeriodicTest() async {
    print('📱 ===== INIZIO START PERIODIC TEST =====');
    
    try {
      print('📱 1. Cancello notifica periodica precedente (ID: 999)');
      await _notifications.cancel(999);
      print('📱 ✅ Notifica 999 cancellata');
      
      print('📱 2. Avvio test periodico ogni minuto...');
      
      await _notifications.periodicallyShow(
        999,
        '🔄 Test Periodico',
        'Questa notifica arriva ogni minuto',
        RepeatInterval.everyMinute,
        const NotificationDetails(
          android: AndroidNotificationDetails(
            'test_channel',
            'Test Notifications',
            importance: Importance.high,
            priority: Priority.high,
            icon: '@drawable/ic_stat_notify', // 🔴 ICONA CORRETTA
          ),
          iOS: DarwinNotificationDetails(
            presentAlert: true,
            presentBadge: true,
            presentSound: true,
          ),
        ),
        androidScheduleMode: AndroidScheduleMode.exact,
      );
      
      print('📱 ✅ periodicallyShow completato');
      print('📱 ✅ Periodic test started - riceverai una notifica ogni minuto');
      
    } catch (e, stackTrace) {
      print('📱 ❌ ERRORE IN STARTPERIODICTEST: $e');
      print('📱 📍 StackTrace: $stackTrace');
    }
    
    print('📱 ===== FINE START PERIODIC TEST =====');
  }

  // Ferma il test periodico
  Future<void> stopPeriodicTest() async {
    print('📱 Fermo test periodico...');
    await _notifications.cancel(999);
    print('🛑 Periodic test stopped');
  }

  // Cancella tutte le notifiche
  Future<void> cancelAllNotifications() async {
    print('📱 Cancello tutte le notifiche...');
    await _notifications.cancelAll();
    print('📱 All notifications cancelled');
  }

  // Cancella una notifica specifica
  Future<void> cancelNotification(int id) async {
    print('📱 Cancello notifica $id...');
    await _notifications.cancel(id);
    print('📱 Notification $id cancelled');
  }

  // Metodi originali mantenuti per compatibilità
  Future<void> scheduleWelcomeNotification() async {
    print('📱 Welcome notification (usa testNow() invece)');
    return;
  }

  Future<void> scheduleTenMinuteNotification() async {
    print('📱 10 minute notification (usa testNow() invece)');
    return;
  }

  Future<void> scheduleLoginNotifications() async {
    print('📱 Login notifications (usa testNow() invece)');
    return;
  }
}