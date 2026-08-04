import 'dart:io';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';

Future<void> main() async {
  print('--- Testing correct WSS setup ---');
  final client = MqttServerClient('wss://mqtt.aiotlearninghub.com/mqtt', 'test_client_123');
  client.port = 443;
  client.useWebSocket = true;
  client.websocketProtocols = MqttClientConstants.protocolsSingleDefault; // MUST INCLUDE THIS!
  
  try {
    print('Connecting...');
    final status = await client.connect();
    print('SUCCESS: ${status?.state}');
  } catch (e) {
    print('FAIL: $e');
  }
  exit(0);
}
