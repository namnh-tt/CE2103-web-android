import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_android/shared_preferences_android.dart';

import '../models/device_reading.dart';
import 'mqtt_device_service.dart';

const _serviceChannelId = 'alert_background_monitor_service';
const _serviceChannelName = 'Giam sat chay nen';
const _alertChannelId = 'alert_background_monitor_alerts';
const _alertChannelName = 'Canh bao chay';
const _serviceNotificationId = 7001;
const _prefsEnabledKey = 'android_background_monitor.enabled';
const _prefsSnapshotKey = 'android_background_monitor.snapshots';
const _stopCommand = 'stopService';

final FlutterLocalNotificationsPlugin _notificationsPlugin =
    FlutterLocalNotificationsPlugin();

bool get _isAndroidRuntime =>
    !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

Future<void> initializeAndroidBackgroundMonitor() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (!_isAndroidRuntime) {
    return;
  }

  await _initializeNotificationPlugin();

  final service = FlutterBackgroundService();
  await service.configure(
    iosConfiguration: IosConfiguration(autoStart: false),
    androidConfiguration: AndroidConfiguration(
      onStart: backgroundMonitorEntryPoint,
      autoStart: false,
      autoStartOnBoot: false,
      isForegroundMode: true,
      notificationChannelId: _serviceChannelId,
      initialNotificationTitle: 'Giam sat chay nen',
      initialNotificationContent: 'San sang khoi dong',
      foregroundServiceNotificationId: _serviceNotificationId,
      foregroundServiceTypes: const [
        AndroidForegroundType.remoteMessaging,
      ],
    ),
  );
}

Future<bool> isAndroidBackgroundMonitorEnabled() async {
  if (!_isAndroidRuntime) {
    return false;
  }

  final preferences = await SharedPreferences.getInstance();
  return preferences.getBool(_prefsEnabledKey) ?? false;
}

Future<bool> isAndroidBackgroundMonitorRunning() async {
  if (!_isAndroidRuntime) {
    return false;
  }

  return FlutterBackgroundService().isRunning();
}

Future<void> ensureAndroidBackgroundMonitorRunningIfEnabled() async {
  if (!_isAndroidRuntime) {
    return;
  }

  final preferences = await SharedPreferences.getInstance();
  if (!preferences.containsKey(_prefsEnabledKey)) {
    await preferences.setBool(_prefsEnabledKey, true);
  }

  if (preferences.getBool(_prefsEnabledKey) ?? false) {
    await startAndroidBackgroundMonitor();
  }
}

Future<bool> startAndroidBackgroundMonitor() async {
  if (!_isAndroidRuntime) {
    return false;
  }

  final preferences = await SharedPreferences.getInstance();
  await preferences.setBool(_prefsEnabledKey, true);

  final service = FlutterBackgroundService();
  if (await service.isRunning()) {
    return true;
  }

  return service.startService();
}

Future<void> showAlertNotificationForReading(DeviceReading reading) {
  return _showAlertNotification(reading);
}

Future<void> clearAlertNotificationForNode(String nodeId) {
  return _notificationsPlugin.cancel(id: _notificationIdForNode(nodeId));
}

bool shouldTriggerAlertForReadings(
  DeviceReading? previous,
  DeviceReading current,
) {
  return _shouldTriggerAlert(
    previous == null ? null : _AlertSnapshot.fromReading(previous),
    _AlertSnapshot.fromReading(current),
  );
}

bool shouldClearAlertForReadings(
  DeviceReading? previous,
  DeviceReading current,
) {
  return _shouldClearAlert(
    previous == null ? null : _AlertSnapshot.fromReading(previous),
    _AlertSnapshot.fromReading(current),
  );
}

Future<void> stopAndroidBackgroundMonitor() async {
  if (!_isAndroidRuntime) {
    return;
  }

  final preferences = await SharedPreferences.getInstance();
  await preferences.setBool(_prefsEnabledKey, false);

  final service = FlutterBackgroundService();
  if (await service.isRunning()) {
    service.invoke(_stopCommand);
  }
}

@pragma('vm:entry-point')
void backgroundMonitorEntryPoint(ServiceInstance service) async {
  WidgetsFlutterBinding.ensureInitialized();
  AndroidFlutterLocalNotificationsPlugin.registerWith();
  SharedPreferencesAndroid.registerWith();
  await _initializeNotificationPlugin();

  final telemetryService = MqttDeviceService();
  final preferences = await SharedPreferences.getInstance();
  final lastSnapshots = await _loadSnapshots(preferences);

  if (service is AndroidServiceInstance) {
    await service.setAsForegroundService();
  }

  Future<void> updateForegroundNotification() async {
    if (service is! AndroidServiceInstance) {
      return;
    }

    final telemetry = telemetryService.state;
    final title = switch (telemetry.connectionStatus) {
      DeviceConnectionStatus.connected => 'Dang giam sat MQTT',
      DeviceConnectionStatus.connecting => 'Dang ket noi MQTT',
      DeviceConnectionStatus.error => 'Loi ket noi MQTT',
      DeviceConnectionStatus.disconnected => 'MQTT dang mat ket noi',
    };

    final content = switch (telemetry.connectionStatus) {
      DeviceConnectionStatus.connected when telemetry.lastMessageAt != null =>
        'Topic ${telemetry.topic} • ${telemetry.readings.length} thiet bi • ${_timeAgoLabel(telemetry.lastMessageAt!)}',
      DeviceConnectionStatus.connected =>
        'Da ket noi broker, dang cho du lieu tu ${telemetry.topic}',
      DeviceConnectionStatus.connecting =>
        'Dang ket noi toi ${telemetry.brokerUrl}',
      DeviceConnectionStatus.error =>
        telemetry.lastError ?? 'Dang thu ket noi lai toi broker MQTT',
      DeviceConnectionStatus.disconnected =>
        'Dang cho khoi phuc ket noi toi ${telemetry.topic}',
    };

    await service.setForegroundNotificationInfo(title: title, content: content);
  }

  Future<void> syncReadings() async {
    final telemetry = telemetryService.state;

    for (final reading in telemetry.readings) {
      final previous = lastSnapshots[reading.nodeId];
      final current = _AlertSnapshot.fromReading(reading);

      if (_shouldTriggerAlert(previous, current)) {
        await _showAlertNotification(reading);
      } else if (_shouldClearAlert(previous, current)) {
        await clearAlertNotificationForNode(reading.nodeId);
      }

      lastSnapshots[reading.nodeId] = current;
    }

    await _saveSnapshots(preferences, lastSnapshots);
    await updateForegroundNotification();
  }

  telemetryService.addListener(() {
    unawaited(syncReadings());
  });

  service.on(_stopCommand).listen((_) async {
    telemetryService.disposeService();
    await _notificationsPlugin.cancel(id: _serviceNotificationId);
    await service.stopSelf();
  });

  await updateForegroundNotification();
  await telemetryService.start();
}

Future<void> _initializeNotificationPlugin() async {
  const androidSettings = AndroidInitializationSettings(
    'ic_bg_service_small',
  );
  const initSettings = InitializationSettings(android: androidSettings);

  await _notificationsPlugin.initialize(settings: initSettings);

  final androidNotifications = _notificationsPlugin
      .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin
      >();

  await androidNotifications?.createNotificationChannel(
    const AndroidNotificationChannel(
      _serviceChannelId,
      _serviceChannelName,
      description: 'Thong bao thuong truc cho dich vu giam sat MQTT nen.',
      importance: Importance.low,
    ),
  );

  await androidNotifications?.createNotificationChannel(
    const AndroidNotificationChannel(
      _alertChannelId,
      _alertChannelName,
      description: 'Thong bao khan khi phat hien chay hoac loi sensor.',
      importance: Importance.max,
    ),
  );
}

bool _shouldTriggerAlert(_AlertSnapshot? previous, _AlertSnapshot current) {
  final fireStarted =
      current.isFireActive && !(previous?.isFireActive ?? false);
  final faultChanged =
      current.deviceStatus != '0' && previous?.deviceStatus != current.deviceStatus;

  return fireStarted || faultChanged;
}

bool _shouldClearAlert(_AlertSnapshot? previous, _AlertSnapshot current) {
  return previous != null &&
      (previous.isFireActive || previous.deviceStatus != '0') &&
      !current.isFireActive &&
      current.deviceStatus == '0';
}

Future<Map<String, _AlertSnapshot>> _loadSnapshots(
  SharedPreferences preferences,
) async {
  final raw = preferences.getString(_prefsSnapshotKey);
  if (raw == null || raw.isEmpty) {
    return <String, _AlertSnapshot>{};
  }

  try {
    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, dynamic>) {
      return <String, _AlertSnapshot>{};
    }

    return decoded.map((key, value) {
      final payload = value is Map
          ? value.map((mapKey, mapValue) => MapEntry('$mapKey', mapValue))
          : const <String, dynamic>{};
      return MapEntry(key, _AlertSnapshot.fromJson(payload));
    });
  } catch (_) {
    return <String, _AlertSnapshot>{};
  }
}

Future<void> _saveSnapshots(
  SharedPreferences preferences,
  Map<String, _AlertSnapshot> snapshots,
) {
  final payload = snapshots.map(
    (key, value) => MapEntry(key, value.toJson()),
  );
  return preferences.setString(_prefsSnapshotKey, jsonEncode(payload));
}

Future<void> _showAlertNotification(DeviceReading reading) async {
  final title = reading.isAlerting && !reading.isFullyOffline
      ? 'Canh bao chay - ${reading.deviceName}'
      : 'Canh bao thiet bi - ${reading.deviceName}';

  final body = _buildAlertBody(reading);

  await _notificationsPlugin.show(
    id: _notificationIdForNode(reading.nodeId),
    title: title,
    body: body,
    notificationDetails: NotificationDetails(
      android: AndroidNotificationDetails(
        _alertChannelId,
        _alertChannelName,
        channelDescription: 'Thong bao khan cho canh bao chay va loi sensor.',
        importance: Importance.max,
        priority: Priority.max,
        category: AndroidNotificationCategory.alarm,
        visibility: NotificationVisibility.public,
        playSound: true,
        enableVibration: true,
        icon: 'ic_bg_service_small',
        styleInformation: BigTextStyleInformation(body),
      ),
    ),
  );
}

String _buildAlertBody(DeviceReading reading) {
  final temperature = reading.isFullyOffline
      ? 'Nhiet do N/A'
      : 'Nhiet do ${reading.temperatureLabel}';
  final environment = 'Moi truong ${reading.environmentLabel}';
  final sensors =
      'Sensor 1: ${reading.sensor1Label} • Sensor 2: ${reading.sensor2Label}';
  return '$temperature • $environment • $sensors';
}

int _notificationIdForNode(String nodeId) {
  final hash = nodeId.hashCode.abs() % 50000;
  return 10000 + hash;
}

String _timeAgoLabel(DateTime dateTime) {
  final difference = DateTime.now().difference(dateTime);
  if (difference.inSeconds < 10) {
    return 'vua nhan du lieu';
  }
  if (difference.inMinutes < 1) {
    return '${difference.inSeconds}s truoc';
  }
  if (difference.inHours < 1) {
    return '${difference.inMinutes} phut truoc';
  }
  return '${difference.inHours} gio truoc';
}

class _AlertSnapshot {
  const _AlertSnapshot({
    required this.fireStatus,
    required this.deviceStatus,
  });

  final String fireStatus;
  final String deviceStatus;

  bool get isFireActive => fireStatus.toUpperCase() == 'FIRE' && deviceStatus != '3';

  factory _AlertSnapshot.fromReading(DeviceReading reading) {
    return _AlertSnapshot(
      fireStatus: reading.fireStatus,
      deviceStatus: reading.deviceStatus,
    );
  }

  factory _AlertSnapshot.fromJson(Map<String, dynamic> json) {
    return _AlertSnapshot(
      fireStatus: json['fireStatus']?.toString() ?? 'UNKNOWN',
      deviceStatus: json['deviceStatus']?.toString() ?? 'UNKNOWN',
    );
  }

  Map<String, String> toJson() {
    return <String, String>{
      'fireStatus': fireStatus,
      'deviceStatus': deviceStatus,
    };
  }
}
