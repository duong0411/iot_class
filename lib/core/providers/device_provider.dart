import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../models/node_model.dart';
import '../services/mqtt_service.dart';
import '../services/node_service.dart';
import 'student_provider.dart';

class DeviceProvider extends ChangeNotifier {
  final MqttService _mqttService = MqttService();
  final NodeService _nodeService = NodeService();
  StreamSubscription? _mqttSubscription;

  List<NodeModel> _nodes = [];
  List<NodeModel> get nodes => _nodes;

  final Map<String, Timer?> _watchdogs = {};

  bool get isMqttConnected => _mqttService.isConnected;

  DeviceProvider() {
    _init();
  }

  Future<void> _init() async {
    await fetchNodes();
    await _connectMqtt();
  }

  Future<void> fetchNodes() async {
    _nodes = await _nodeService.getNodes();
    if (_mqttService.isConnected) {
      _mqttService.subscribeNodes(_nodes);
    }
    notifyListeners();
  }

  Future<void> _connectMqtt() async {
    final connected = await _mqttService.connect();
    if (connected) {
      _mqttSubscription?.cancel();
      _mqttSubscription = _mqttService.messages.listen((data) {
        _handleMqttMessage(data['topic']!, data['raw']!.toString());
      });
      _mqttService.subscribeNodes(_nodes);
      notifyListeners();
    }
  }

  Future<void> addNode(String name, String chipId, String templateType) async {
    final newNode = await _nodeService.createNode(name, chipId, templateType);
    if (newNode != null) {
      _nodes.add(newNode);
      _mqttService.subscribeNodes(_nodes);
      notifyListeners();
    }
  }

  Future<void> removeNode(String id) async {
    final success = await _nodeService.deleteNode(id);
    if (success) {
      _nodes.removeWhere((n) => n.id == id);
      _watchdogs[id]?.cancel();
      _watchdogs.remove(id);
      _mqttService.subscribeNodes(_nodes);
      notifyListeners();
    }
  }

  NodeModel? getNodeById(String id) {
    try {
      return _nodes.firstWhere((n) => n.id == id);
    } catch (_) {
      return null;
    }
  }

  void _resetWatchdog(String nodeId) {
    final nodeIndex = _nodes.indexWhere((n) => n.id == nodeId);
    if (nodeIndex == -1) return;

    if (!_nodes[nodeIndex].isOnline) {
      _nodes[nodeIndex].isOnline = true;
      notifyListeners();
    }

    _watchdogs[nodeId]?.cancel();
    _watchdogs[nodeId] = Timer(const Duration(seconds: 5), () {
      final idx = _nodes.indexWhere((n) => n.id == nodeId);
      if (idx != -1 && _nodes[idx].isOnline) {
        _nodes[idx].isOnline = false;
        notifyListeners();
      }
    });
  }

  // Classroom State Variables
  double classroomTemp = 0.0;
  double classroomHumi = 0.0;
  String classroomLightStatus = "Tot";
  bool classroomFanState = false;
  bool classroomLedState = false;
  bool classroomDoorState = false;
  double classroomDoorAngle = 0.0;
  String classroomMode = "AUTO"; // "AUTO" hoặc "MANUAL"
  bool get isClassroomAutoMode => classroomMode == "AUTO";
  StudentProvider? studentProvider;

  bool isClassroomDeviceOnline = false;
  DateTime? lastClassroomDataTime;
  Timer? _classroomWatchdogTimer;

  void attachStudentProvider(StudentProvider provider) {
    studentProvider = provider;
    _startClassroomWatchdog();
  }

  void _startClassroomWatchdog() {
    _classroomWatchdogTimer?.cancel();
    _classroomWatchdogTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      final shouldBeOnline = isMqttConnected &&
          lastClassroomDataTime != null &&
          DateTime.now().difference(lastClassroomDataTime!).inSeconds <= 7;
      if (isClassroomDeviceOnline != shouldBeOnline) {
        isClassroomDeviceOnline = shouldBeOnline;
        notifyListeners();
      }
    });
  }

  void _handleMqttMessage(String topic, String payload) {
    // Handle CLASSROOM_01 LWT and telemetry status
    if (topic.contains("CLASSROOM_01") || topic.startsWith("tele/classroom")) {
      if (payload == "offline") {
        isClassroomDeviceOnline = false;
        notifyListeners();
        return;
      } else {
        isClassroomDeviceOnline = true;
        lastClassroomDataTime = DateTime.now();
      }
    }

    // Handle raw LWT and Heartbeat messages for other nodes
    if (payload == "online" || payload == "offline") {
      final isOnline = payload == "online";
      for (var node in _nodes) {
        if (node.chipId.isNotEmpty && topic.contains(node.chipId)) {
          if (isOnline) {
            _resetWatchdog(node.id);
          } else {
            node.isOnline = false;
            _watchdogs[node.id]?.cancel();
            notifyListeners();
          }
          break;
        }
      }
      return;
    }

    try {
      final data = jsonDecode(payload);
      dynamic value = data['value'];

      // Handle ESP32 Smart Classroom Specific Topics
      if (topic == 'tele/classroom_temp/status') {
        classroomTemp = (value is num) ? value.toDouble() : double.tryParse(value.toString()) ?? classroomTemp;
        notifyListeners();
        return;
      } else if (topic == 'tele/classroom_humi/status') {
        classroomHumi = (value is num) ? value.toDouble() : double.tryParse(value.toString()) ?? classroomHumi;
        notifyListeners();
        return;
      } else if (topic == 'tele/classroom_light/status') {
        final rawVal = data['raw'] != null ? " (${data['raw']})" : "";
        classroomLightStatus = "${value?.toString() ?? ''}$rawVal";
        notifyListeners();
        return;
      } else if (topic == 'tele/classroom_mode/status') {
        classroomMode = value?.toString().toUpperCase() ?? classroomMode;
        notifyListeners();
        return;
      } else if (topic == 'tele/classroom_led/status') {
        classroomLedState = (value.toString().toUpperCase() == "ON");
        notifyListeners();
        return;
      } else if (topic == 'tele/classroom_fan/status') {
        classroomFanState = (value.toString().toUpperCase() == "ON");
        notifyListeners();
        return;
      } else if (topic == 'tele/classroom_door/status') {
        classroomDoorAngle = (value is num) ? value.toDouble() : double.tryParse(value.toString()) ?? 0;
        classroomDoorState = classroomDoorAngle > 0;
        notifyListeners();
        return;
      } else if (topic == 'tele/classroom_rfid/status') {
        final rfidUid = data['uid']?.toString() ?? '';
        if (rfidUid.isNotEmpty && studentProvider != null) {
          studentProvider!.handleRFIDScanned(rfidUid);
        }
        notifyListeners();
        return;
      }

      for (int i = 0; i < _nodes.length; i++) {
        final node = _nodes[i];
        if (node.chipId.isNotEmpty && topic.contains(node.chipId)) {
          _resetWatchdog(node.id);

          bool stateChanged = false;

          if (topic.endsWith('_temp_livingroom/status')) {
            node.state['temperature'] = (value is num) ? value.toDouble() : double.tryParse(value.toString()) ?? node.state['temperature'];
            stateChanged = true;
          } else if (topic.endsWith('_humi_living_room/status')) {
            node.state['humidity'] = (value is num) ? value.toDouble() : double.tryParse(value.toString()) ?? node.state['humidity'];
            stateChanged = true;
          } else if (topic.endsWith('_led1/status')) {
            node.state['light'] = (value.toString().toUpperCase() == "ON");
            stateChanged = true;
          } else if (topic.endsWith('_fan_livingroom/status')) {
            node.state['fan'] = (value.toString().toUpperCase() == "ON");
            stateChanged = true;
          } else if (topic.endsWith('_door_livingroom1/status')) {
            final double angle = (value is num) ? value.toDouble() : double.tryParse(value.toString()) ?? 0;
            node.state['doorAngle'] = angle;
            node.state['door'] = angle > 0;
            stateChanged = true;
          }

          if (stateChanged) {
            notifyListeners();
          }
          break;
        }
      }
    } catch (e) {
      if (kDebugMode) print("Lỗi parse MQTT Payload: $e - Payload raw: $payload");
    }
  }

  // ─── Actions: Smart Classroom ESP32 ─────────────────────────────────────
  void toggleClassroomMode() {
    classroomMode = (classroomMode == "AUTO") ? "MANUAL" : "AUTO";
    _mqttService.publish('cmnd/classroom_mode/POWER', classroomMode);
    notifyListeners();
  }

  void toggleClassroomLed() {
    classroomLedState = !classroomLedState;
    _mqttService.publish('cmnd/classroom_led/POWER', classroomLedState ? "ON" : "OFF");
    notifyListeners();
  }

  void toggleClassroomFan() {
    classroomFanState = !classroomFanState;
    _mqttService.publish('cmnd/classroom_fan/POWER', classroomFanState ? "ON" : "OFF");
    notifyListeners();
  }

  void toggleClassroomDoor() {
    classroomDoorState = !classroomDoorState;
    classroomDoorAngle = classroomDoorState ? 90.0 : 0.0;
    _mqttService.publish('cmnd/classroom_door/POWER', classroomDoorState ? "ON" : "OFF");
    notifyListeners();
  }

  // ─── Actions: Bếp & Khách ─────────────────────────────────────────────────
  void toggleKitchenLight(String nodeId) {
    final node = getNodeById(nodeId);
    if (node == null || !node.isOnline) return;
    final newState = !node.light;
    node.state['light'] = newState;
    _mqttService.publishCommand(node.chipId, 'led1', newState ? "ON" : "OFF");
    _nodeService.updateNodeState(node.id, node.state);
    notifyListeners();
  }

  void toggleKitchenFan(String nodeId) {
    final node = getNodeById(nodeId);
    if (node == null || !node.isOnline) return;
    final newState = !node.fan;
    node.state['fan'] = newState;
    _mqttService.publishCommand(node.chipId, 'fan_livingroom', newState ? "ON" : "OFF");
    _nodeService.updateNodeState(node.id, node.state);
    notifyListeners();
  }

  void toggleKitchenDoor(String nodeId) {
    final node = getNodeById(nodeId);
    if (node == null || !node.isOnline) return;
    final newState = !node.door;
    node.state['door'] = newState;
    node.state['doorAngle'] = newState ? 90.0 : 0.0;
    _mqttService.publishCommand(node.chipId, 'door_livingroom1', newState ? "ON" : "OFF");
    _nodeService.updateNodeState(node.id, node.state);
    notifyListeners();
  }

  void toggleClothesDryer(String nodeId) {
    final node = getNodeById(nodeId);
    if (node == null || !node.isOnline) return;
    final newState = !node.clothesDryer;
    node.state['clothesDryer'] = newState;
    node.state['clothesDryerAngle'] = newState ? 90.0 : 0.0;
    _mqttService.publishCommand(node.chipId, 'dryer_livingroom', newState ? "ON" : "OFF");
    _nodeService.updateNodeState(node.id, node.state);
    notifyListeners();
  }

  void setKitchenDoorAngle(String nodeId, double angle) {
    final node = getNodeById(nodeId);
    if (node == null || !node.isOnline) return;
    node.state['doorAngle'] = angle;
    node.state['door'] = angle > 0;
    _mqttService.publishCommand(node.chipId, 'door_livingroom1', angle.toStringAsFixed(0));
    _nodeService.updateNodeState(node.id, node.state);
    notifyListeners();
  }

  void setClothesDryerAngle(String nodeId, double angle) {
    final node = getNodeById(nodeId);
    if (node == null || !node.isOnline) return;
    node.state['clothesDryerAngle'] = angle;
    node.state['clothesDryer'] = angle > 0;
    _mqttService.publishCommand(node.chipId, 'dryer_livingroom', angle.toStringAsFixed(0));
    _nodeService.updateNodeState(node.id, node.state);
    notifyListeners();
  }

  // ─── Actions: Phòng Ngủ ───────────────────────────────────────────────────
  void toggleBedroomLight(String nodeId) {
    final node = getNodeById(nodeId);
    if (node == null || !node.isOnline) return;
    final newState = !node.bedroomLight;
    node.state['bedroomLight'] = newState;
    _mqttService.publishCommand(node.chipId, 'led_bedroom', newState ? "ON" : "OFF");
    _nodeService.updateNodeState(node.id, node.state);
    notifyListeners();
  }

  void toggleBedroomFan(String nodeId) {
    final node = getNodeById(nodeId);
    if (node == null || !node.isOnline) return;
    final newState = !node.bedroomFan;
    node.state['bedroomFan'] = newState;
    _mqttService.publishCommand(node.chipId, 'fan_bedroom', newState ? "ON" : "OFF");
    _nodeService.updateNodeState(node.id, node.state);
    notifyListeners();
  }

  void toggleCurtain(String nodeId) {
    final node = getNodeById(nodeId);
    if (node == null || !node.isOnline) return;
    final newState = !node.curtain;
    node.state['curtain'] = newState;
    node.state['curtainAngle'] = newState ? 90.0 : 0.0;
    _mqttService.publishCommand(node.chipId, 'curtain', newState ? "ON" : "OFF");
    _nodeService.updateNodeState(node.id, node.state);
    notifyListeners();
  }

  void setCurtainAngle(String nodeId, double angle) {
    final node = getNodeById(nodeId);
    if (node == null || !node.isOnline) return;
    node.state['curtainAngle'] = angle;
    node.state['curtain'] = angle > 0;
    _mqttService.publishCommand(node.chipId, 'curtain', angle.toStringAsFixed(0));
    _nodeService.updateNodeState(node.id, node.state);
    notifyListeners();
  }

  @override
  void dispose() {
    _mqttSubscription?.cancel();
    for (var timer in _watchdogs.values) {
      timer?.cancel();
    }
    _mqttService.disconnect();
    super.dispose();
  }
}
