import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/node_model.dart';
import '../services/mqtt_service.dart';
import '../services/node_service.dart';
import 'student_provider.dart';

class DeviceProvider extends ChangeNotifier with WidgetsBindingObserver {
  final MqttService _mqttService = MqttService();
  final NodeService _nodeService = NodeService();
  StreamSubscription? _mqttSubscription;

  List<NodeModel> _nodes = [];
  List<NodeModel> get nodes => _nodes;
  MqttService get mqttService => _mqttService;

  final Map<String, Timer?> _watchdogs = {};
  final Map<String, DateTime> _userActionLock = {};

  bool get isMqttConnected => _mqttService.isConnected;

  static const String _cacheKeyPrefix = 'classroom_cache_';
  static const String classroomChip = 'CLASSROOM_02';

  DeviceProvider() {
    _init();
  }

  Future<void> _init() async {
    WidgetsBinding.instance.addObserver(this);
    await _loadCachedState();
    _startClassroomWatchdog();
    _startStatusPolling();
    await fetchNodes();
    await _connectMqtt();
  }

  Future<void> _loadCachedState() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      classroomTemp = prefs.getDouble('${_cacheKeyPrefix}temp') ?? classroomTemp;
      classroomHumi = prefs.getDouble('${_cacheKeyPrefix}humi') ?? classroomHumi;
      classroomLightStatus = prefs.getString('${_cacheKeyPrefix}light') ?? classroomLightStatus;
      classroomLightPercent = prefs.getInt('${_cacheKeyPrefix}light_pct') ?? classroomLightPercent;
      classroomFanState = prefs.getBool('${_cacheKeyPrefix}fan') ?? classroomFanState;
      classroomLedState = prefs.getBool('${_cacheKeyPrefix}led') ?? classroomLedState;
      classroomLedMode = prefs.getString('${_cacheKeyPrefix}led_mode') ?? classroomLedMode;
      classroomFanMode = prefs.getString('${_cacheKeyPrefix}fan_mode') ?? classroomFanMode;
      classroomLedReason = prefs.getString('${_cacheKeyPrefix}led_reason') ?? classroomLedReason;
      classroomFanReason = prefs.getString('${_cacheKeyPrefix}fan_reason') ?? classroomFanReason;
      classroomGas = prefs.getBool('${_cacheKeyPrefix}gas') ?? classroomGas;
      classroomFire = prefs.getBool('${_cacheKeyPrefix}fire') ?? classroomFire;
      classroomDoorState = prefs.getBool('${_cacheKeyPrefix}door') ?? classroomDoorState;
      classroomDoorAngle = prefs.getDouble('${_cacheKeyPrefix}door_angle') ?? classroomDoorAngle;
      classroomLastUid = prefs.getString('${_cacheKeyPrefix}uid') ?? classroomLastUid;
      if (prefs.containsKey('${_cacheKeyPrefix}body')) {
        classroomBody = prefs.getDouble('${_cacheKeyPrefix}body');
      }
      final lastMs = prefs.getInt('${_cacheKeyPrefix}last_time');
      if (lastMs != null) {
        lastClassroomDataTime = DateTime.fromMillisecondsSinceEpoch(lastMs);
      }
      notifyListeners();
    } catch (_) {}
  }

  Future<void> _saveCachedState() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble('${_cacheKeyPrefix}temp', classroomTemp);
      await prefs.setDouble('${_cacheKeyPrefix}humi', classroomHumi);
      await prefs.setString('${_cacheKeyPrefix}light', classroomLightStatus);
      await prefs.setInt('${_cacheKeyPrefix}light_pct', classroomLightPercent);
      await prefs.setBool('${_cacheKeyPrefix}fan', classroomFanState);
      await prefs.setBool('${_cacheKeyPrefix}led', classroomLedState);
      await prefs.setString('${_cacheKeyPrefix}led_mode', classroomLedMode);
      await prefs.setString('${_cacheKeyPrefix}fan_mode', classroomFanMode);
      await prefs.setString('${_cacheKeyPrefix}led_reason', classroomLedReason);
      await prefs.setString('${_cacheKeyPrefix}fan_reason', classroomFanReason);
      await prefs.setBool('${_cacheKeyPrefix}gas', classroomGas);
      await prefs.setBool('${_cacheKeyPrefix}fire', classroomFire);
      await prefs.setBool('${_cacheKeyPrefix}door', classroomDoorState);
      await prefs.setDouble('${_cacheKeyPrefix}door_angle', classroomDoorAngle);
      await prefs.setString('${_cacheKeyPrefix}uid', classroomLastUid);
      if (classroomBody != null) {
        await prefs.setDouble('${_cacheKeyPrefix}body', classroomBody!);
      }
      if (lastClassroomDataTime != null) {
        await prefs.setInt('${_cacheKeyPrefix}last_time', lastClassroomDataTime!.millisecondsSinceEpoch);
      }
    } catch (_) {}
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      if (kDebugMode) print('DeviceProvider: App resumed -> Re-checking MQTT & polling status');
      if (!_mqttService.isConnected) {
        _connectMqtt();
      }
      requestClassroomStatus();
    } else if (state == AppLifecycleState.paused || state == AppLifecycleState.detached) {
      _saveCachedState();
    }
  }

  void _startStatusPolling() {
    _statusPollingTimer?.cancel();
    _statusPollingTimer = Timer.periodic(const Duration(seconds: 20), (_) {
      if (_mqttService.isConnected) {
        requestClassroomStatus();
      }
    });
  }

  void requestClassroomStatus() {
    _mqttService.requestClassroomStatus();
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
      requestClassroomStatus();
      notifyListeners();
    } else {
      Timer(const Duration(seconds: 3), () {
        if (!_mqttService.isConnected) {
          _connectMqtt();
        }
      });
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
  String classroomLightStatus = 'Đang đọc';
  bool classroomLightDark = false;
  int classroomLightPercent = 0;
  bool classroomFanState = false;
  bool classroomLedState = false;
  String classroomLedMode = 'AUTO';
  String classroomFanMode = 'AUTO';
  String classroomLedReason = 'Đang chờ cảm biến quang';
  String classroomFanReason = 'Đang chờ DHT11';
  bool classroomGas = false;
  bool classroomFire = false;
  double? classroomBody;
  String classroomLastUid = '';
  String classroomRfidResult = '';
  bool classroomDoorState = false;
  double classroomDoorAngle = 0.0;
  bool get isLedAuto => classroomLedMode == 'AUTO';
  bool get isFanAuto => classroomFanMode == 'AUTO';
  StudentProvider? studentProvider;

  bool isClassroomDeviceOnline = false;
  DateTime? lastClassroomDataTime;
  Timer? _classroomWatchdogTimer;
  Timer? _statusPollingTimer;

  void attachStudentProvider(StudentProvider provider) {
    studentProvider = provider;
    _startClassroomWatchdog();
  }

  void _startClassroomWatchdog() {
    _classroomWatchdogTimer?.cancel();
    _classroomWatchdogTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      final shouldBeOnline = isMqttConnected &&
          lastClassroomDataTime != null &&
          DateTime.now().difference(lastClassroomDataTime!).inSeconds <= 15;
      if (isClassroomDeviceOnline != shouldBeOnline) {
        isClassroomDeviceOnline = shouldBeOnline;
        notifyListeners();
      }
    });
  }

  bool _locked(String key) {
    final lastLock = _userActionLock[key];
    return lastLock != null && DateTime.now().difference(lastLock).inMilliseconds <= 1800;
  }

  bool _isOnValue(dynamic value) {
    final s = value.toString().toUpperCase();
    return s == 'ON' || s == '1' || s == 'TRUE' || s == 'OPEN';
  }

  String _modeValue(dynamic value) {
    return value.toString().toUpperCase().contains('MANUAL') ? 'MANUAL' : 'AUTO';
  }

  void _handleMqttMessage(String topic, String payload) {
    final topicKey = topic.toLowerCase();
    final isClassroomTopic = topicKey.contains('classroom_02') || topicKey.contains('classroom');
    if (isClassroomTopic) {
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

    dynamic value;
    Map<String, dynamic>? jsonData;

    try {
      final decoded = jsonDecode(payload);
      if (decoded is Map<String, dynamic>) {
        jsonData = decoded;
        value = decoded['value'] ?? decoded['val'] ?? decoded['data'] ?? decoded['state'] ?? decoded['status'] ?? decoded['uid'];
      } else {
        value = decoded;
      }
    } catch (_) {
      value = payload.trim();
    }
    value ??= payload.trim();

    bool classroomStateChanged = false;
    final t = topic.toLowerCase();

    if (t.contains('classroom_02_temp') || t.contains('classroom_temp')) {
      final parsed = (value is num) ? value.toDouble() : double.tryParse(value.toString());
      if (parsed != null) {
        classroomTemp = parsed;
        classroomStateChanged = true;
      }
    } else if (t.contains('classroom_02_humi') || t.contains('classroom_humi')) {
      final parsed = (value is num) ? value.toDouble() : double.tryParse(value.toString());
      if (parsed != null) {
        classroomHumi = parsed;
        classroomStateChanged = true;
      }
    } else if (t.contains('classroom_02_light') || t.contains('classroom_light')) {
      final state = (jsonData?['state'] ?? value).toString().toUpperCase();
      final pct = (value is num) ? value.toInt() : int.tryParse(value.toString());
      final dark = state == 'DARK' || pct == 0;
      classroomLightDark = dark;
      classroomLightPercent = dark ? 0 : (pct ?? 100);
      classroomLightStatus = dark ? 'Tối' : 'Sáng';
      classroomStateChanged = true;
    } else if (t.contains('classroom_02_led_mode')) {
      if (!_locked('led_mode')) {
        classroomLedMode = _modeValue(value);
        classroomStateChanged = true;
      }
    } else if (t.contains('classroom_02_fan_mode')) {
      if (!_locked('fan_mode')) {
        classroomFanMode = _modeValue(value);
        classroomStateChanged = true;
      }
    } else if (t.contains('classroom_02_led') || t.contains('classroom_led')) {
      if (!_locked('led')) {
        classroomLedState = _isOnValue(value);
        if (jsonData?['mode'] != null) classroomLedMode = _modeValue(jsonData!['mode']);
        if (jsonData?['reason'] != null) classroomLedReason = jsonData!['reason'].toString();
        classroomStateChanged = true;
      }
    } else if (t.contains('classroom_02_fan') || t.contains('classroom_fan')) {
      if (!_locked('fan')) {
        classroomFanState = _isOnValue(value);
        if (jsonData?['mode'] != null) classroomFanMode = _modeValue(jsonData!['mode']);
        if (jsonData?['reason'] != null) classroomFanReason = jsonData!['reason'].toString();
        classroomStateChanged = true;
      }
    } else if (t.contains('classroom_02_door') || t.contains('classroom_door')) {
      if (!_locked('door')) {
        final angle = (value is num) ? value.toDouble() : double.tryParse(value.toString()) ?? 0;
        classroomDoorAngle = angle;
        classroomDoorState = angle > 0 || _isOnValue(value);
        classroomStateChanged = true;
      }
    } else if (t.contains('classroom_02_body') || t.contains('classroom_body')) {
      final parsed = (value is num) ? value.toDouble() : double.tryParse(value.toString());
      if (parsed != null) {
        classroomBody = parsed;
        classroomStateChanged = true;
      }
    } else if (t.contains('classroom_02_gas') || t.contains('classroom_gas')) {
      classroomGas = _isOnValue(value);
      classroomStateChanged = true;
    } else if (t.contains('classroom_02_fire') || t.contains('classroom_fire')) {
      classroomFire = _isOnValue(value);
      classroomStateChanged = true;
    } else if (t.contains('classroom_02_rfid') || t.contains('classroom_rfid')) {
      final rfidUid = (jsonData != null && jsonData['uid'] != null)
          ? jsonData['uid'].toString()
          : value.toString();
      classroomLastUid = rfidUid;
      classroomRfidResult = (jsonData?['result'] ?? '').toString();
      final body = jsonData?['body'];
      if (body is num) classroomBody = body.toDouble();
      if (rfidUid.isNotEmpty && rfidUid != 'online' && studentProvider != null) {
        studentProvider!.handleRFIDScanned(rfidUid);
      }
      classroomStateChanged = true;
    }

    if (classroomStateChanged) {
      _saveCachedState();
      notifyListeners();
      return;
    }

    try {
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
  void setClassroomLedMode(bool auto) {
    classroomLedMode = auto ? 'AUTO' : 'MANUAL';
    _userActionLock['led_mode'] = DateTime.now();
    _mqttService.publish('cmnd/${classroomChip}_led_mode/POWER', classroomLedMode, qos: MqttQos.atMostOnce);
    _saveCachedState();
    notifyListeners();
  }

  void setClassroomFanMode(bool auto) {
    classroomFanMode = auto ? 'AUTO' : 'MANUAL';
    _userActionLock['fan_mode'] = DateTime.now();
    _mqttService.publish('cmnd/${classroomChip}_fan_mode/POWER', classroomFanMode, qos: MqttQos.atMostOnce);
    _saveCachedState();
    notifyListeners();
  }

  void toggleClassroomLed() {
    classroomLedState = !classroomLedState;
    classroomLedMode = 'MANUAL';
    _userActionLock['led'] = DateTime.now();
    _mqttService.publish(
      'cmnd/${classroomChip}_led/POWER',
      classroomLedState ? 'ON' : 'OFF',
      qos: MqttQos.atMostOnce,
    );
    _saveCachedState();
    notifyListeners();
  }

  void toggleClassroomFan() {
    classroomFanState = !classroomFanState;
    classroomFanMode = 'MANUAL';
    _userActionLock['fan'] = DateTime.now();
    _mqttService.publish(
      'cmnd/${classroomChip}_fan/POWER',
      classroomFanState ? 'ON' : 'OFF',
      qos: MqttQos.atMostOnce,
    );
    _saveCachedState();
    notifyListeners();
  }

  void toggleClassroomDoor() {
    classroomDoorState = !classroomDoorState;
    classroomDoorAngle = classroomDoorState ? 90.0 : 0.0;
    _userActionLock['door'] = DateTime.now();
    _mqttService.publish('cmnd/${classroomChip}_door/POWER', classroomDoorState ? 'OPEN' : 'CLOSE', qos: MqttQos.atMostOnce);
    _saveCachedState();
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
    WidgetsBinding.instance.removeObserver(this);
    _statusPollingTimer?.cancel();
    _classroomWatchdogTimer?.cancel();
    _mqttSubscription?.cancel();
    for (var timer in _watchdogs.values) {
      timer?.cancel();
    }
    _mqttService.disconnect();
    super.dispose();
  }
}

