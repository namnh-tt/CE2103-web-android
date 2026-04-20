import 'package:alert/models/device_reading.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parses payload with trailing comma', () {
    final reading = DeviceReading.fromPayload(
      '{"node_id":"NODE_01","temperature":27.88,"fire_status":"NORMAL","device_status":"2",}',
    );

    expect(reading.nodeId, 'NODE_01');
    expect(reading.temperature, 27.88);
    expect(reading.fireStatus, 'NORMAL');
    expect(reading.deviceStatus, '2');
  });

  test('parses payload with wrapping noise and null bytes', () {
    final reading = DeviceReading.fromPayload(
      '\u0000mqtt: {"node_id":"NODE_02","temperature":31.5,"fire_status":"ALERT","device_status":"3"}\n',
    );

    expect(reading.nodeId, 'NODE_02');
    expect(reading.temperature, 31.5);
    expect(reading.fireStatus, 'ALERT');
    expect(reading.deviceStatus, '3');
  });

  test('parses nested JSON string payload', () {
    final reading = DeviceReading.fromPayload(
      '"{\\"node_id\\":\\"NODE_03\\",\\"temperature\\":29.4,\\"fire_status\\":\\"NORMAL\\",\\"device_status\\":\\"1\\"}"',
    );

    expect(reading.nodeId, 'NODE_03');
    expect(reading.temperature, 29.4);
    expect(reading.fireStatus, 'NORMAL');
    expect(reading.deviceStatus, '1');
  });

  test('maps device display state for fully working sensors', () {
    final reading = DeviceReading.fromPayload(
      '{"node_id":"NODE_01","temperature":25.72,"fire_status":"NORMAL","device_status":"0"}',
    );

    expect(reading.deviceName, 'Thiết bị báo cháy 01');
    expect(reading.displayTemperature, '25.72');
    expect(reading.environmentLabel, 'Bình thường');
    expect(reading.sensor1Label, 'Hoạt động bình thường');
    expect(reading.sensor2Label, 'Hoạt động bình thường');
  });

  test('maps device display state for both failed sensors', () {
    final reading = DeviceReading.fromPayload(
      '{"node_id":"NODE_01","temperature":25.72,"fire_status":"NORMAL","device_status":"3"}',
    );

    expect(reading.displayTemperature, 'N/A');
    expect(reading.environmentLabel, 'N/A');
    expect(reading.sensor1Label, 'Không hoạt động');
    expect(reading.sensor2Label, 'Không hoạt động');
  });
}
