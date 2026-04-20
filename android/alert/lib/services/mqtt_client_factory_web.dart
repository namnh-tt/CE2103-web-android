import 'package:mqtt_client/mqtt_browser_client.dart';
import 'package:mqtt_client/mqtt_client.dart';

MqttClient buildMqttClient({
  required String server,
  required int port,
  required String clientId,
  required bool useTls,
  required String websocketPath,
}) {
  final scheme = useTls ? 'wss' : 'ws';
  final client = MqttBrowserClient.withPort(
    '$scheme://$server$websocketPath',
    clientId,
    port,
  );
  client.websocketProtocols = const ['mqtt'];
  return client;
}
