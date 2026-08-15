import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';
import '../models/node_model.dart';

class MqttService extends ChangeNotifier {
  static final MqttService _instance = MqttService._internal();
  factory MqttService() => _instance;
  MqttService._internal();

  static const String brokerHost = 'mqtt.duynguyen.io.vn';
  static const String wssUrl = 'wss://mqtt.duynguyen.io.vn/mqtt';
  static const int port = 443;

  MqttServerClient? _client;
  bool _isConnected = false;
  bool get isConnected => _isConnected;

  String? _persistentClientId;
  List<NodeModel> _currentNodes = [];

  final _messageController = StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get messages => _messageController.stream;

  Timer? _autoReconnectTimer;

  // ═══════════════════════════════════════════════════════════
  //  KẾT NỐI WSS SSL/TLS MOUNT
  // ═══════════════════════════════════════════════════════════
  Future<bool> connect() async {
    if (_isConnected && _client?.connectionStatus?.state == MqttConnectionState.connected) {
      return true;
    }

    _persistentClientId ??= 'flutter_app_client';

    if (_client != null) {
      try {
        _client!.disconnect();
      } catch (_) {}
    }

    _client = MqttServerClient.withPort(wssUrl, _persistentClientId!, port);
    _client!.useWebSocket = true;
    _client!.secure = false;
    _client!.websocketProtocols = MqttClientConstants.protocolsSingleDefault;

    _client!.logging(on: false);
    _client!.keepAlivePeriod = 30;
    _client!.autoReconnect = true;
    _client!.resubscribeOnAutoReconnect = true;
    _client!.onConnected = _onConnected;
    _client!.onDisconnected = _onDisconnected;
    _client!.onAutoReconnect = _onAutoReconnect;
    _client!.onAutoReconnected = _onAutoReconnected;
    _client!.onSubscribed = _onSubscribed;

    final connMsg = MqttConnectMessage()
        .withClientIdentifier(_persistentClientId!)
        .startClean()
        .withWillTopic('tele/flutter_app/status')
        .withWillMessage('offline')
        .withWillRetain()
        .withWillQos(MqttQos.atMostOnce);

    _client!.connectionMessage = connMsg;

    try {
      if (kDebugMode) print('MQTT: Đang kết nối WSS tới $wssUrl (Client ID: $_persistentClientId) ...');
      await _client!.connect().timeout(const Duration(seconds: 10));
    } catch (e) {
      if (kDebugMode) print('MQTT: Lỗi kết nối - $e');
      _isConnected = false;
      _startAutoReconnectTimer();
      notifyListeners();
      return false;
    }

    if (_client?.connectionStatus?.state == MqttConnectionState.connected) {
      _isConnected = true;
      _autoReconnectTimer?.cancel();
      _listenMessages();
      subscribeNodes(_currentNodes);
      requestClassroomStatus();
      notifyListeners();
      return true;
    }

    _startAutoReconnectTimer();
    return false;
  }

  void _startAutoReconnectTimer() {
    _autoReconnectTimer?.cancel();
    _autoReconnectTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (!_isConnected && (_client?.connectionStatus?.state != MqttConnectionState.connected)) {
        if (kDebugMode) print('MQTT: Auto-reconnect timer checking connection...');
        connect();
      }
    });
  }

  // Helper yêu cầu ESP32 phản hồi ngay trạng thái mới nhất
  void requestClassroomStatus() {
    publish('cmnd/CLASSROOM_01/status', 'STATE', qos: MqttQos.atMostOnce);
    publish('cmnd/classroom_status/get', '{}', qos: MqttQos.atMostOnce);
    publish('cmnd/classroom_mode/get', '{}', qos: MqttQos.atMostOnce);
    publishScheduleGet();
  }

  // ═══════════════════════════════════════════════════════════
  //  SUBSCRIBE TỰ ĐỘNG THEO DANH SÁCH NODE
  // ═══════════════════════════════════════════════════════════
  void subscribeNodes(List<NodeModel> nodes) {
    _currentNodes = nodes;
    if (_client == null || !_isConnected) return;

    final topics = <String>{
      'tele/+/status',
      'tele/CLASSROOM_01/status',
      'tele/classroom_temp/status',
      'tele/classroom_humi/status',
      'tele/classroom_light/status',
      'tele/classroom_led/status',
      'tele/classroom_fan/status',
      'tele/classroom_door/status',
      'tele/classroom_rfid/status',
      'tele/classroom_mode/status',
      'stat/classroom_schedule/list',
      'stat/CLASSROOM_01/+',
      'stat/classroom/+',
    };

    for (var node in nodes) {
      if (node.chipId.isNotEmpty) {
        topics.add('tele/${node.chipId}/status');
        topics.add('stat/${node.chipId}/+');
      }
    }

    for (final t in topics) {
      try {
        _client!.subscribe(t, MqttQos.atMostOnce);
      } catch (_) {}
    }
  }

  // ═══════════════════════════════════════════════════════════
  //  LẮNG NGHE MESSAGES
  // ═══════════════════════════════════════════════════════════
  void _listenMessages() {
    _client?.updates?.listen((List<MqttReceivedMessage<MqttMessage?>>? c) {
      if (c == null || c.isEmpty) return;

      try {
        final recMsg = c[0].payload as MqttPublishMessage;
        final payload = MqttPublishPayload.bytesToStringAsString(recMsg.payload.message);
        final topic = c[0].topic;

        dynamic value;
        try {
          final json = jsonDecode(payload);
          value = json['value'] ?? json;
        } catch (_) {
          value = payload.trim();
        }

        _messageController.add({
          'topic': topic,
          'value': value,
          'raw': payload,
        });
      } catch (e) {
        if (kDebugMode) print('MQTT listen error: $e');
      }
    });
  }

  // ═══════════════════════════════════════════════════════════
  //  PUBLISH LỆNH & LỊCH TỰ ĐỘNG (QoS 0 làm mặc định)
  // ═══════════════════════════════════════════════════════════
  void publish(String topic, String message, {MqttQos qos = MqttQos.atMostOnce}) {
    if (!_isConnected || _client == null || _client?.connectionStatus?.state != MqttConnectionState.connected) {
      if (kDebugMode) print('MQTT TX Warning: Chưa kết nối MQTT, đang kết nối lại...');
      connect().then((ok) {
        if (ok) publish(topic, message, qos: qos);
      });
      return;
    }

    try {
      final builder = MqttClientPayloadBuilder();
      builder.addUTF8String(message);

      if (kDebugMode) print('MQTT TX: [$topic] → $message');
      _client!.publishMessage(topic, qos, builder.payload!);
    } catch (e) {
      if (kDebugMode) print('MQTT TX error: $e');
    }
  }

  // Helper cho lệnh thiết bị
  void publishCommand(String chipId, String deviceSuffix, String command) {
    publish('cmnd/${chipId}_$deviceSuffix/POWER', command, qos: MqttQos.atMostOnce);
  }

  // Helper cho Lịch Tự Động & Lời Dẫn Xiaozhi
  void publishScheduleSet(List<Map<String, dynamic>> schedules) {
    final payload = jsonEncode({'schedules': schedules});
    publish('cmnd/classroom_schedule/set', payload, qos: MqttQos.atMostOnce);
  }

  void publishScheduleDelete(String scheduleId) {
    final payload = jsonEncode({'id': scheduleId});
    publish('cmnd/classroom_schedule/delete', payload, qos: MqttQos.atMostOnce);
  }

  void publishScheduleGet() {
    publish('cmnd/classroom_schedule/get', '{}', qos: MqttQos.atMostOnce);
  }

  // Helper phát giọng nói trực tiếp qua loa Xiaozhi ESP32
  void publishTtsSay(String prompt) {
    final payload = jsonEncode({
      'prompt': prompt,
      'text': prompt,
      'emotion': 'happy',
    });
    publish('cmnd/xiaozhi_tts/say', payload, qos: MqttQos.atMostOnce);
  }

  // ═══════════════════════════════════════════════════════════
  //  CALLBACKS
  // ═══════════════════════════════════════════════════════════
  void _onConnected() {
    if (kDebugMode) print('MQTT: ✅ Đã kết nối WSS thành công!');
    _isConnected = true;
    _autoReconnectTimer?.cancel();
    requestClassroomStatus();
    notifyListeners();
  }

  void _onDisconnected() {
    if (kDebugMode) print('MQTT: ⚠️ Đã ngắt kết nối');
    _isConnected = false;
    _startAutoReconnectTimer();
    notifyListeners();
  }

  void _onAutoReconnect() {
    if (kDebugMode) print('MQTT: 🔄 Đang tự động kết nối lại...');
  }

  void _onAutoReconnected() {
    if (kDebugMode) print('MQTT: ✅ Tự động kết nối lại thành công!');
    _isConnected = true;
    _autoReconnectTimer?.cancel();
    subscribeNodes(_currentNodes);
    requestClassroomStatus();
    notifyListeners();
  }

  void _onSubscribed(String topic) {
    // if (kDebugMode) print('MQTT: 📡 Subscribed: $topic');
  }

  // ═══════════════════════════════════════════════════════════
  //  CLEANUP
  // ═══════════════════════════════════════════════════════════
  void disconnect() {
    _autoReconnectTimer?.cancel();
    _client?.disconnect();
    _isConnected = false;
    _currentNodes.clear();
  }
}

