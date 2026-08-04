import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FlutterLocalNotificationsPlugin _notificationsPlugin =
      FlutterLocalNotificationsPlugin();

  Future<void> init() async {
    // Cấu hình icon mặc định trên Android (sử dụng ic_launcher trong thư mục mipmap)
    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    const InitializationSettings initializationSettings =
        InitializationSettings(
      android: initializationSettingsAndroid,
    );

    await _notificationsPlugin.initialize(
      settings: initializationSettings,
      onDidReceiveNotificationResponse: (NotificationResponse response) {
        // Xử lý khi người dùng ấn vào thông báo
      },
    );

    final androidImplementation = _notificationsPlugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();

    // Khởi tạo sẵn Channel cho FCM Background Push (Bắt buộc phải có để hiện Popup/Âm thanh)
    const AndroidNotificationChannel channel = AndroidNotificationChannel(
      'emergency_alerts_channel', 
      'Cảnh báo khẩn cấp', 
      description: 'Kênh thông báo cho các sự cố nguy hiểm như rò rỉ khí gas hoặc cháy nổ.',
      importance: Importance.max,
      playSound: true,
      enableVibration: true,
    );

    await androidImplementation?.createNotificationChannel(channel);
  }

  Future<void> showWarningNotification({
    required int id,
    required String title,
    required String body,
  }) async {
    const AndroidNotificationDetails androidDetails =
        AndroidNotificationDetails(
      'emergency_alerts_channel',
      'Cảnh báo khẩn cấp',
      channelDescription:
          'Kênh thông báo cho các sự cố nguy hiểm như rò rỉ khí gas hoặc cháy nổ.',
      importance: Importance.max,
      priority: Priority.max,
      enableVibration: true,
      playSound: true,
      color: Colors.red, // Màu sắc cho Icon thông báo
      fullScreenIntent: true, // Ưu tiên hiển thị Popup trên cùng
      category: AndroidNotificationCategory.alarm,
      visibility: NotificationVisibility.public,
    );

    const NotificationDetails notificationDetails =
        NotificationDetails(android: androidDetails);

    await _notificationsPlugin.show(
      id: id,
      title: title,
      body: body,
      notificationDetails: notificationDetails,
    );
  }
}
