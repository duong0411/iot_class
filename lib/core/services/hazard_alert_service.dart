import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:ui';

import 'package:flutter/widgets.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';

/// Giữ một dịch vụ nền (giống app thanh toán) để hiện cảnh báo cháy / CO2
/// ngay cả khi người dùng đã thoát màn hình lớp học.
class HazardAlertService {
  static const guardChannelId = 'classroom_guard';
  static const hazardChannelId = 'classroom_hazard';
  static const _broker = 'wss://mqtt.duynguyen.io.vn/mqtt';

  static final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();

  static Future<void> start() async {
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosInit = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );
    await _plugin.initialize(const InitializationSettings(android: androidInit, iOS: iosInit));

    final androidPlugin = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    await androidPlugin?.requestNotificationsPermission();
    await _plugin.resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>()?.requestPermissions(
          alert: true,
          badge: true,
          sound: true,
        );

    const guard = AndroidNotificationChannel(
      guardChannelId,
      'Giám sát lớp học',
      description: 'Giữ kết nối mạng để báo cháy và CO2 khi app đang tắt',
      importance: Importance.low,
    );
    const hazard = AndroidNotificationChannel(
      hazardChannelId,
      'Cảnh báo cháy và CO2',
      description: 'Cảnh báo khẩn trên màn hình, kể cả khi app đã đóng',
      importance: Importance.max,
      playSound: true,
      enableVibration: true,
    );
    await androidPlugin?.createNotificationChannel(guard);
    await androidPlugin?.createNotificationChannel(hazard);

    final service = FlutterBackgroundService();
    await service.configure(
      androidConfiguration: AndroidConfiguration(
        onStart: classroomGuardOnStart,
        autoStart: true,
        autoStartOnBoot: true,
        isForegroundMode: true,
        notificationChannelId: guardChannelId,
        initialNotificationTitle: 'Lớp học thông minh',
        initialNotificationContent: 'Đang giám sát cháy và CO2',
        foregroundServiceNotificationId: 880,
        foregroundServiceTypes: [AndroidForegroundType.dataSync],
      ),
      iosConfiguration: IosConfiguration(
        autoStart: true,
        onForeground: classroomGuardOnStart,
        onBackground: classroomGuardIosBackground,
      ),
    );
    await service.startService();
  }
}

@pragma('vm:entry-point')
Future<bool> classroomGuardIosBackground(ServiceInstance service) async {
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();
  return true;
}

@pragma('vm:entry-point')
void classroomGuardOnStart(ServiceInstance service) async {
  DartPluginRegistrant.ensureInitialized();
  WidgetsFlutterBinding.ensureInitialized();

  if (service is AndroidServiceInstance) {
    service.setAsForegroundService();
    service.on('stopService').listen((_) => service.stopSelf());
  }

  final notifications = FlutterLocalNotificationsPlugin();
  const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
  const iosInit = DarwinInitializationSettings();
  await notifications.initialize(const InitializationSettings(android: androidInit, iOS: iosInit));

  final clientId = 'cls-guard-${Random().nextInt(1 << 30)}';
  final client = MqttServerClient.withPort(HazardAlertService._broker, clientId, 443);
  client.useWebSocket = true;
  client.secure = false;
  client.websocketProtocols = MqttClientConstants.protocolsSingleDefault;
  client.keepAlivePeriod = 30;
  client.autoReconnect = true;
  client.resubscribeOnAutoReconnect = true;
  client.connectionMessage = MqttConnectMessage().withClientIdentifier(clientId).startClean();

  var gasOn = false;
  var fireOn = false;
  var listening = false;

  Future<void> showAlarm(String title, String body) async {
    const android = AndroidNotificationDetails(
      HazardAlertService.hazardChannelId,
      'Cảnh báo cháy và CO2',
      channelDescription: 'Cảnh báo khẩn trên màn hình, kể cả khi app đã đóng',
      importance: Importance.max,
      priority: Priority.high,
      category: AndroidNotificationCategory.alarm,
      fullScreenIntent: true,
      playSound: true,
      enableVibration: true,
      visibility: NotificationVisibility.public,
      ticker: 'Cảnh báo lớp học',
    );
    const ios = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
      interruptionLevel: InterruptionLevel.timeSensitive,
    );
    await notifications.show(
      title.hashCode & 0x7fffffff,
      title,
      body,
      const NotificationDetails(android: android, iOS: ios),
    );
    if (service is AndroidServiceInstance) {
      service.setForegroundNotificationInfo(title: title, content: body);
    }
  }

  client.onConnected = () {
    client.subscribe('tele/CLASSROOM_02_gas/status', MqttQos.atMostOnce);
    client.subscribe('tele/CLASSROOM_02_fire/status', MqttQos.atMostOnce);
    client.subscribe('tele/CLASSROOM_02_alarm/status', MqttQos.atMostOnce);
    if (!listening && client.updates != null) {
      listening = true;
      client.updates!.listen((events) async {
    for (final event in events) {
      final rec = event.payload as MqttPublishMessage;
      final text = utf8.decode(rec.payload.message);
      final topic = event.topic.toLowerCase();
      var value = text.trim();
      try {
        final decoded = jsonDecode(text);
        if (decoded is Map && decoded['value'] != null) value = decoded['value'].toString();
      } catch (_) {}
      final on = value.toUpperCase() == 'ON' || value == '1';

      if (topic.contains('classroom_02_gas')) {
        if (on && !gasOn) {
          await showAlarm('Cảnh báo CO2 / khí gas', 'Lớp học phát hiện khí gas hoặc CO2. Kiểm tra phòng ngay.');
        }
        gasOn = on;
      } else if (topic.contains('classroom_02_fire')) {
        if (on && !fireOn) {
          await showAlarm('Cảnh báo cháy', 'Cảm biến lửa trong lớp học đang báo cháy.');
        }
        fireOn = on;
      }

      if (!gasOn && !fireOn && service is AndroidServiceInstance) {
        service.setForegroundNotificationInfo(
          title: 'Lớp học thông minh',
          content: 'An toàn. Đang giám sát cháy và CO2',
        );
      }
      }
      });
    }
    if (service is AndroidServiceInstance) {
      service.setForegroundNotificationInfo(
        title: 'Lớp học thông minh',
        content: 'Đã có mạng. Đang giám sát cháy và CO2',
      );
    }
  };

  while (true) {
    try {
      if (client.connectionStatus?.state != MqttConnectionState.connected) {
        await client.connect().timeout(const Duration(seconds: 12));
      }
    } catch (_) {
      if (service is AndroidServiceInstance) {
        service.setForegroundNotificationInfo(
          title: 'Lớp học thông minh',
          content: 'Mất mạng. Sẽ báo lại khi có kết nối',
        );
      }
    }
    await Future.delayed(const Duration(seconds: 8));
    if (service is AndroidServiceInstance && !(await service.isForegroundService())) {
      break;
    }
  }
}
