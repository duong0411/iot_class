import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';
import '../models/node_model.dart';

class MqttService extends ChangeNotifier {
  static const String broker = 'mqtt.aiotlearninghub.com';
  static const int port = 443;
  
  MqttServerClient? _client;
  bool _isConnected = false;
  bool get isConnected => _isConnected;

  List<NodeModel> _currentNodes = [];

  // Stream để truyền dữ liệu sang DeviceProvider
  final _messageController = StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get messages => _messageController.stream;

  MqttService();

  // ═══════════════════════════════════════════════════════════
  //  KẾT NỐI
  // ═══════════════════════════════════════════════════════════
  Future<bool> connect() async {
    if (_isConnected) {
      return true;
    }

    final clientId = 'flutter_${DateTime.now().millisecondsSinceEpoch}';

    _client = MqttServerClient('mqtt.aiotlearninghub.com', clientId);
    _client!.port = port;
    _client!.useWebSocket = true;
    _client!.websocketProtocols = MqttClientConstants.protocolsSingleDefault;
    
    _client!.logging(on: false); 
    _client!.keepAlivePeriod = 60;
    _client!.autoReconnect = true;
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
      if (kDebugMode) print('MQTT: Đang kết nối tới ${_client!.server} qua port ${_client!.port} ...');
      await _client!.connect().timeout(const Duration(seconds: 10));
    } catch (e) {
      if (kDebugMode) print('MQTT: Lỗi kết nối - $e');
      _isConnected = false;
      notifyListeners();
      return false;
    }

    if (_client!.connectionStatus!.state == MqttConnectionState.connected) {
      _isConnected = true;
      _listenMessages();
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
    
    final topics = <String>[
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
    ];
    
    for (var node in nodes) {
      if (node.chipId.isEmpty) continue;
      final cId = node.chipId;
      topics.add('tele/$cId/status');
    }

    for (final t in topics) {
      _client!.subscribe(t, MqttQos.atLeastOnce);
    }
  }

  // ═══════════════════════════════════════════════════════════
  //  LẮNG NGHE MESSAGE
  // ═══════════════════════════════════════════════════════════
  void _listenMessages() {
    _client!.updates!.listen((List<MqttReceivedMessage<MqttMessage?>>? c) {
      if (c == null || c.isEmpty) return;

      final recMsg = c[0].payload as MqttPublishMessage;
      final payload = MqttPublishPayload.bytesToStringAsString(
          recMsg.payload.message);
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
    });
  }

  // ═══════════════════════════════════════════════════════════
  //  PUBLISH LỆNH
  // ═══════════════════════════════════════════════════════════
  void publish(String topic, String message) {
    if (!_isConnected || _client == null) return;

    final builder = MqttClientPayloadBuilder();
    builder.addString(message);

    if (kDebugMode) print('MQTT TX: [$topic] → $message');

    _client!.publishMessage(topic, MqttQos.atLeastOnce, builder.payload!);
  }

  // Helper cho lệnh
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
    if (kDebugMode) print('MQTT: ✅ Đã kết nối thành công');
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
    if (kDebugMode) print('MQTT: ✅ Tự động kết nối lại thành công');
    _isConnected = true;
    subscribeNodes(_currentNodes);
    notifyListeners();
  }

  void _onSubscribed(String topic) {
    // if (kDebugMode) print('MQTT: 📡 Đã subscribe: $topic');
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
