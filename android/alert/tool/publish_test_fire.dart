import 'dart:convert';
import 'dart:io';

import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';

Future<void> main(List<String> args) async {
  final nodeId = args.isNotEmpty ? args.first : 'NODE_01';
  final client = MqttServerClient.withPort(
    'broker.mqttdashboard.com',
    'alert_test_${DateTime.now().millisecondsSinceEpoch}',
    1883,
  );

  client.logging(on: false);
  client.keepAlivePeriod = 20;
  client.autoReconnect = false;
  client.onConnected = () => stdout.writeln('Connected to MQTT broker.');
  client.onDisconnected = () => stdout.writeln('Disconnected from MQTT broker.');
  client.connectionMessage = MqttConnectMessage()
      .withClientIdentifier(client.clientIdentifier)
      .startClean()
      .withWillQos(MqttQos.atMostOnce);

  try {
    await client.connect();
  } on Exception catch (error) {
    stderr.writeln('MQTT connect failed: $error');
    client.disconnect();
    exitCode = 1;
    return;
  }

  if (client.connectionStatus?.state != MqttConnectionState.connected) {
    stderr.writeln(
      'MQTT connection failed: ${client.connectionStatus?.state}',
    );
    client.disconnect();
    exitCode = 1;
    return;
  }

  final payload = <String, dynamic>{
    'node_id': nodeId,
    'temperature': 85.72,
    'fire_status': 'FIRE',
    'device_status': '2',
  };

  final builder = MqttClientPayloadBuilder()
    ..addString(jsonEncode(payload));

  client.publishMessage(
    'esp32/data',
    MqttQos.atMostOnce,
    builder.payload!,
    retain: false,
  );

  stdout.writeln('Published payload: ${jsonEncode(payload)}');
  await Future<void>.delayed(const Duration(seconds: 1));
  client.disconnect();
}
