import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  // Initialize but don't actually do anything
  Future<void> init() async {
    print('📱 Notification service initialized (disabled)');
    return;
  }

  // Empty methods - do nothing
  Future<void> scheduleWelcomeNotification() async {
    print('📱 Welcome notification skipped');
    return;
  }

  Future<void> scheduleTenMinuteNotification() async {
    print('📱 10 minute notification skipped');
    return;
  }

  Future<void> scheduleLoginNotifications() async {
    print('📱 Login notifications skipped');
    return;
  }

  Future<void> cancelAllNotifications() async {
    print('📱 Cancel all notifications skipped');
    return;
  }

  Future<void> cancelNotification(int id) async {
    print('📱 Cancel notification $id skipped');
    return;
  }

  Future<void> testNow() async {
    print('📱 Test notification skipped');
    return;
  }
}