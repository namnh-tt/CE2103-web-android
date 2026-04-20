import 'dart:convert';

class DeviceReading {
  const DeviceReading({
    required this.nodeId,
    required this.temperature,
    required this.fireStatus,
    required this.deviceStatus,
    required this.receivedAt,
    required this.rawPayload,
  });

  final String nodeId;
  final double temperature;
  final String fireStatus;
  final String deviceStatus;
  final DateTime receivedAt;
  final String rawPayload;

  bool get isAlerting => fireStatus.toUpperCase() != 'NORMAL';
  bool get isFullyOffline => deviceStatus == '3';
  bool get isSensor1Working => deviceStatus != '1' && deviceStatus != '3';
  bool get isSensor2Working => deviceStatus != '2' && deviceStatus != '3';

  String get temperatureLabel => '${temperature.toStringAsFixed(2)} °C';
  String get displayTemperature =>
      isFullyOffline ? 'N/A' : temperature.toStringAsFixed(2);
  String get environmentLabel {
    if (isFullyOffline) {
      return 'N/A';
    }

    return switch (fireStatus.toUpperCase()) {
      'NORMAL' => 'Bình thường',
      'FIRE' => 'Phát hiện cháy',
      _ => fireStatus,
    };
  }

  String get deviceName {
    final match = RegExp(r'(\d+)$').firstMatch(nodeId);
    if (match == null) {
      return nodeId;
    }

    return 'Thiết bị báo cháy ${match.group(1)}';
  }

  String get sensor1Label =>
      isSensor1Working ? 'Hoạt động bình thường' : 'Không hoạt động';
  String get sensor2Label =>
      isSensor2Working ? 'Hoạt động bình thường' : 'Không hoạt động';

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'node_id': nodeId,
      'temperature': temperature,
      'fire_status': fireStatus,
      'device_status': deviceStatus,
      'received_at': receivedAt.toIso8601String(),
      'raw_payload': rawPayload,
    };
  }

  factory DeviceReading.fromJson(Map<String, dynamic> json) {
    return DeviceReading(
      nodeId: _readString(json['node_id'], fallback: 'UNKNOWN_NODE'),
      temperature: _readDouble(json['temperature']),
      fireStatus: _readString(json['fire_status'], fallback: 'UNKNOWN'),
      deviceStatus: _readString(json['device_status'], fallback: 'UNKNOWN'),
      receivedAt:
          DateTime.tryParse(json['received_at']?.toString() ?? '') ??
          DateTime.now(),
      rawPayload: _readString(
        json['raw_payload'],
        fallback: jsonEncode(
          <String, dynamic>{
            'node_id': json['node_id'],
            'temperature': json['temperature'],
            'fire_status': json['fire_status'],
            'device_status': json['device_status'],
          },
        ),
      ),
    );
  }

  factory DeviceReading.fromPayload(String payload, {DateTime? receivedAt}) {
    final decoded = _decodePayload(payload);

    if (decoded is! Map<String, dynamic>) {
      throw const FormatException(
        'Payload MQTT không phải JSON object hợp lệ.',
      );
    }

    return DeviceReading(
      nodeId: _readString(decoded['node_id'], fallback: 'UNKNOWN_NODE'),
      temperature: _readDouble(decoded['temperature']),
      fireStatus: _readString(decoded['fire_status'], fallback: 'UNKNOWN'),
      deviceStatus: _readString(decoded['device_status'], fallback: 'UNKNOWN'),
      receivedAt: receivedAt ?? DateTime.now(),
      rawPayload: payload,
    );
  }

  static Object _decodePayload(String payload) {
    Object? lastError;

    for (final candidate in _payloadCandidates(payload)) {
      try {
        final decoded = jsonDecode(candidate);

        if (decoded is String) {
          return _decodePayload(decoded);
        }

        if (decoded is Map) {
          return decoded.map((key, value) => MapEntry(key.toString(), value));
        }

        return decoded;
      } catch (error) {
        lastError = error;
      }
    }

    throw lastError ?? const FormatException('Payload MQTT không hợp lệ.');
  }

  static Iterable<String> _payloadCandidates(String payload) sync* {
    final base = payload
        .replaceAll('\u0000', '')
        .replaceFirst(RegExp(r'^\uFEFF'), '')
        .trim();

    final emitted = <String>{};

    void emit(String text) {
      final normalized = _removeTrailingCommas(text.trim());
      if (normalized.isNotEmpty) {
        emitted.add(normalized);
      }
    }

    emit(base);

    final objectStart = base.indexOf('{');
    final objectEnd = base.lastIndexOf('}');
    if (objectStart != -1 && objectEnd != -1 && objectEnd > objectStart) {
      emit(base.substring(objectStart, objectEnd + 1));
    }

    if (base.startsWith('"') && base.endsWith('"') && base.length >= 2) {
      emit(base.substring(1, base.length - 1).replaceAll(r'\"', '"'));
    }

    yield* emitted;
  }

  static String _removeTrailingCommas(String text) {
    return text.replaceAllMapped(
      RegExp(r',(\s*[}\]])'),
      (match) => match.group(1)!,
    );
  }

  static String _readString(Object? value, {required String fallback}) {
    final text = value?.toString().trim();
    if (text == null || text.isEmpty) {
      return fallback;
    }

    return text;
  }

  static double _readDouble(Object? value) {
    if (value is num) {
      return value.toDouble();
    }

    final parsedValue = double.tryParse(value?.toString() ?? '');
    if (parsedValue == null) {
      throw const FormatException(
        'Không đọc được temperature từ payload MQTT.',
      );
    }

    return parsedValue;
  }
}
