Never buildMqttClient({
  required String server,
  required int port,
  required String clientId,
  required bool useTls,
  required String websocketPath,
}) {
  throw UnsupportedError('Nền tảng hiện tại không hỗ trợ MQTT WebSocket.');
}
