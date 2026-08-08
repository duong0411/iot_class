import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';
import '../models/node_model.dart';

class MqttService extends ChangeNotifier {
  static const String brokerHost = 'mqtt.aiotlearninghub.com';
  static const String wssUrl = 'wss://mqtt.aiotlearninghub.com/mqtt';
  static const int port = 443;

  MqttServerClient? _client;
  bool _isConnected = false;
  bool get isConnected => _isConnected;

  List<NodeModel> _currentNodes = [];

  // Stream truyền dữ liệu về UI & DeviceProvider
  final _messageController = StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get messages => _messageController.stream;

  MqttService();

  // ═══════════════════════════════════════════════════════════
  //  KẾT NỐI WSS SSL/TLS MOUNT
  // ═══════════════════════════════════════════════════════════
  Future<bool> connect() async {
    if (_isConnected && _client?.connectionStatus?.state == MqttConnectionState.connected) {
      return true;
    }

    final clientId = 'flutter_${DateTime.now().millisecondsSinceEpoch}';

    _client = MqttServerClient.withPort(brokerHost, clientId, port);
    _client!.useWebSocket = true;
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
        .withClientIdentifier(clientId)
        .startClean()
        .withWillTopic('tele/flutter_app/status')
        .withWillMessage('offline')
        .withWillRetain()
        .withWillQos(MqttQos.atLeastOnce);

    _client!.connectionMessage = connMsg;

    try {
      if (kDebugMode) print('MQTT: Đang kết nối WSS tới $wssUrl ...');
      await _client!.connect().timeout(const Duration(seconds: 12));
    } catch (e) {
      if (kDebugMode) print('MQTT: Lỗi kết nối - $e');
      _isConnected = false;
      notifyListeners();
      return false;
    }

    if (_client?.connectionStatus?.state == MqttConnectionState.connected) {
      _isConnected = true;
      _listenMessages();
      subscribeNodes(_currentNodes);
      notifyListeners();
      return true;
    }

    return false;
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
    };

    for (var node in nodes) {
      if (node.chipId.isNotEmpty) {
        topics.add('tele/${node.chipId}/status');
      }
    }

    for (final t in topics) {
      try {
        _client!.subscribe(t, MqttQos.atLeastOnce);
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
  //  PUBLISH LỆNH & LỊCH TỰ ĐỘNG
  // ═══════════════════════════════════════════════════════════
  void publish(String topic, String message) {
    if (!_isConnected || _client == null || _client?.connectionStatus?.state != MqttConnectionState.connected) {
      if (kDebugMode) print('MQTT TX Warning: Chưa kết nối MQTT, đang kết nối lại...');
      connect().then((ok) {
        if (ok) publish(topic, message);
      });
      return;
    }

    try {
      final builder = MqttClientPayloadBuilder();
      builder.addUTF8String(message);

      if (kDebugMode) print('MQTT TX: [$topic] → $message');
      _client!.publishMessage(topic, MqttQos.atLeastOnce, builder.payload!);
    } catch (e) {
      if (kDebugMode) print('MQTT TX error: $e');
    }
  }

  // Helper cho lệnh thiết bị
  void publishCommand(String chipId, String deviceSuffix, String command) {
    publish('cmnd/${chipId}_$deviceSuffix/POWER', command);
  }

  // Helper cho Lịch Tự Động & Lời Dẫn Xiaozhi
  void publishScheduleSet(List<Map<String, dynamic>> schedules) {
    final payload = jsonEncode({'schedules': schedules});
    publish('cmnd/classroom_schedule/set', payload);
  }

  void publishScheduleDelete(String scheduleId) {
    final payload = jsonEncode({'id': scheduleId});
    publish('cmnd/classroom_schedule/delete', payload);
  }

  void publishScheduleGet() {
    publish('cmnd/classroom_schedule/get', '{}');
  }

  // Helper phát giọng nói trực tiếp qua loa Xiaozhi ESP32
  void publishTtsSay(String prompt) {
    final payload = jsonEncode({
      'prompt': prompt,
      'text': prompt,
      'emotion': 'happy',
    });
    publish('cmnd/xiaozhi_tts/say', payload);
  }

  // ═══════════════════════════════════════════════════════════
  //  CALLBACKS
  // ═══════════════════════════════════════════════════════════
  void _onConnected() {
    if (kDebugMode) print('MQTT: ✅ Đã kết nối WSS thành công!');
    _isConnected = true;
    notifyListeners();
  }

  void _onDisconnected() {
    if (kDebugMode) print('MQTT: ⚠️ Đã ngắt kết nối');
    _isConnected = false;
    notifyListeners();
  }

  void _onAutoReconnect() {
    if (kDebugMode) print('MQTT: 🔄 Đang tự động kết nối lại...');
  }

  void _onAutoReconnected() {
    if (kDebugMode) print('MQTT: ✅ Tự động kết nối lại thành công!');
    _isConnected = true;
    subscribeNodes(_currentNodes);
    notifyListeners();
  }

  void _onSubscribed(String topic) {
    // if (kDebugMode) print('MQTT: 📡 Subscribed: $topic');
  }

  // ═══════════════════════════════════════════════════════════
  //  CLEANUP
  // ═══════════════════════════════════════════════════════════
  void disconnect() {
    _client?.disconnect();
    _isConnected = false;
    _currentNodes.clear();
    notifyListeners();
  }
}
