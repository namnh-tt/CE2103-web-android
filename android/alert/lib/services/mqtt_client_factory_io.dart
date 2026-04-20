import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';

MqttClient buildMqttClient({
  required String server,
  required int port,
  required String clientId,
  required bool useTls,
  required String websocketPath,
}) {
  final scheme = useTls ? 'wss' : 'ws';
  final client = MqttServerClient.withPort(
    '$scheme://$server$websocketPath',
    clientId,
    port,
  );
  client.useWebSocket = true;
  client.websocketProtocols = const ['mqtt'];
  return client;
}
