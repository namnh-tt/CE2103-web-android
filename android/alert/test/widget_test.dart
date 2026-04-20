import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alert/main.dart';
import 'package:alert/models/device_reading.dart';
import 'package:alert/services/mqtt_device_service.dart';

class _FakeTelemetryService extends DeviceTelemetryService {
  _FakeTelemetryService()
    : _state = DeviceTelemetryState(
        connectionStatus: DeviceConnectionStatus.connected,
        readings: [
          DeviceReading(
            nodeId: 'NODE_01',
            temperature: 27.88,
            fireStatus: 'NORMAL',
            deviceStatus: '2',
            receivedAt: DateTime(2026, 4, 14, 9, 30),
            rawPayload:
                '{"node_id":"NODE_01","temperature":27.88,"fire_status":"NORMAL","device_status":"2"}',
          ),
        ],
        host: 'broker.mqttdashboard.com',
        port: 8000,
        topic: 'esp32/data',
        websocketPath: '/mqtt',
        useTls: false,
        lastMessageAt: DateTime(2026, 4, 14, 9, 30),
      );

  final DeviceTelemetryState _state;

  @override
  DeviceTelemetryState get state => _state;

  @override
  Future<void> retry() async {}

  @override
  Future<void> start() async {}

  @override
  void disposeService() {
    dispose();
  }
}

void main() {
  testWidgets('renders home and setting sections', (WidgetTester tester) async {
    await tester.pumpWidget(
      AlertApp(telemetryService: _FakeTelemetryService()),
    );
    await tester.pump();

    expect(find.text('Thông tin thiết bị'), findsOneWidget);
    expect(find.text('Home'), findsOneWidget);
    expect(find.text('Setting'), findsOneWidget);
    expect(find.text('Đã kết nối'), findsOneWidget);
    expect(find.byIcon(Icons.refresh_rounded), findsOneWidget);
    expect(find.text('Thiết bị báo cháy 01'), findsOneWidget);
    expect(find.text('NODE_01'), findsOneWidget);
    expect(find.text('BÌNH THƯỜNG'), findsOneWidget);
    expect(find.textContaining('Nhiệt độ: 27.88°C'), findsOneWidget);
    expect(find.textContaining('Tình trạng môi trường: Bình thường'), findsOneWidget);
    expect(find.textContaining('Sensor 1: Hoạt động bình thường'), findsOneWidget);
    expect(find.textContaining('Sensor 2: Không hoạt động'), findsOneWidget);

    await tester.tap(find.text('Setting'));
    await tester.pumpAndSettle();

    expect(find.text('Thông tin profile'), findsOneWidget);
    expect(find.text('Admin'), findsOneWidget);
    expect(find.text('Thông báo'), findsOneWidget);
  });
}
