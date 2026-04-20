import 'package:mqtt_client/mqtt_client.dart';

import 'mqtt_client_factory_stub.dart'
    if (dart.library.html) 'mqtt_client_factory_web.dart'
    if (dart.library.io) 'mqtt_client_factory_io.dart'
    as platform;

MqttClient buildMqttClient({
  required String server,
  required int port,
  required String clientId,
  required bool useTls,
  required String websocketPath,
}) {
  return platform.buildMqttClient(
    server: server,
    port: port,
    clientId: clientId,
    useTls: useTls,
    websocketPath: websocketPath,
  );
}
