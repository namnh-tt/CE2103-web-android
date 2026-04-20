import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../models/device_reading.dart';

enum DeviceConnectionStatus { disconnected, connecting, connected, error }

class DeviceTelemetryState {
  const DeviceTelemetryState({
    required this.connectionStatus,
    required this.readings,
    required this.host,
    required this.port,
    required this.topic,
    required this.websocketPath,
    required this.useTls,
    this.lastError,
    this.lastMessageAt,
  });

  final DeviceConnectionStatus connectionStatus;
  final List<DeviceReading> readings;
  final String host;
  final int port;
  final String topic;
  final String websocketPath;
  final bool useTls;
  final String? lastError;
  final DateTime? lastMessageAt;

  String get brokerUrl =>
      '${useTls ? 'wss' : 'ws'}://$host:$port$websocketPath';

  static const _missing = Object();

  DeviceTelemetryState copyWith({
    DeviceConnectionStatus? connectionStatus,
    List<DeviceReading>? readings,
    Object? lastError = _missing,
    Object? lastMessageAt = _missing,
  }) {
    return DeviceTelemetryState(
      connectionStatus: connectionStatus ?? this.connectionStatus,
      readings: readings ?? this.readings,
      host: host,
      port: port,
      topic: topic,
      websocketPath: websocketPath,
      useTls: useTls,
      lastError: identical(lastError, _missing)
          ? this.lastError
          : lastError as String?,
      lastMessageAt: identical(lastMessageAt, _missing)
          ? this.lastMessageAt
          : lastMessageAt as DateTime?,
    );
  }
}

abstract class DeviceTelemetryService extends ChangeNotifier {
  DeviceTelemetryState get state;

  Future<void> start();

  Future<void> retry();

  void disposeService();
}

class MqttDeviceService extends DeviceTelemetryService {
  static const _cachedReadingsKey = 'mqtt_device_service.cached_readings.v1';

  MqttDeviceService({
    this.host = 'broker.mqttdashboard.com',
    this.port = 8000,
    this.topic = 'esp32/data',
    this.websocketPath = '/mqtt',
    this.useTls = false,
    this.keepAliveSeconds = 30,
  }) : _state = DeviceTelemetryState(
         connectionStatus: DeviceConnectionStatus.disconnected,
         readings: const [],
         host: host,
         port: port,
         topic: topic,
         websocketPath: websocketPath,
         useTls: useTls,
       );

  final String host;
  final int port;
  final String topic;
  final String websocketPath;
  final bool useTls;
  final int keepAliveSeconds;

  final String _clientId = 'alert_${DateTime.now().millisecondsSinceEpoch}';
  final Map<String, DeviceReading> _readingsByNode = {};
  final List<int> _incomingBuffer = <int>[];

  DeviceTelemetryState _state;
  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _channelSubscription;
  Completer<void>? _connectCompleter;
  Timer? _pingTimer;
  Timer? _pongTimeoutTimer;
  Timer? _reconnectTimer;

  bool _hasStarted = false;
  bool _isDisposed = false;
  bool _isConnecting = false;
  bool _disconnectRequestedByApp = false;
  int _reconnectAttempt = 0;
  int _nextPacketIdentifier = 1;
  int? _lastConnAckReturnCode;

  @override
  DeviceTelemetryState get state => _state;

  @override
  Future<void> start() async {
    if (_hasStarted || _isDisposed) {
      return;
    }

    _hasStarted = true;
    await _restoreCachedReadings();
    await _connect();
  }

  @override
  Future<void> retry() async {
    if (_isDisposed) {
      return;
    }

    _reconnectTimer?.cancel();
    await _disconnectCurrentConnection();
    await _connect();
  }

  Future<void> _connect() async {
    if (_isDisposed || _isConnecting) {
      return;
    }

    _isConnecting = true;
    _lastConnAckReturnCode = null;
    _setState(
      _state.copyWith(
        connectionStatus: DeviceConnectionStatus.connecting,
        lastError: null,
      ),
    );

    try {
      final uri = Uri(
        scheme: useTls ? 'wss' : 'ws',
        host: host,
        port: port,
        path: websocketPath,
      );

      final channel = WebSocketChannel.connect(uri, protocols: const ['mqtt']);
      _channel = channel;
      _incomingBuffer.clear();
      _connectCompleter = Completer<void>();

      await _channelSubscription?.cancel();
      _channelSubscription = channel.stream.listen(
        _handleChannelEvent,
        onDone: _handleChannelDone,
        onError: _handleChannelError,
        cancelOnError: true,
      );

      _sendPacket(
        _encodeConnectPacket(
          clientId: _clientId,
          keepAliveSeconds: keepAliveSeconds,
        ),
      );

      await _connectCompleter!.future.timeout(
        const Duration(seconds: 5),
        onTimeout: () {
          throw TimeoutException(
            'Không nhận được CONNACK từ broker trong thời gian cho phép.',
          );
        },
      );

      _reconnectAttempt = 0;
      _startKeepAlive();
      _sendPacket(
        _encodeSubscribePacket(packetIdentifier: _nextPacketId(), topic: topic),
      );
    } catch (error) {
      final errorMessage = _normalizeConnectError(error);
      await _closeFailedConnection();
      _setState(
        _state.copyWith(
          connectionStatus: DeviceConnectionStatus.error,
          lastError: errorMessage,
        ),
      );
      if (_shouldAutoReconnect()) {
        _scheduleReconnect(errorMessage);
      }
    } finally {
      _connectCompleter = null;
      _isConnecting = false;
    }
  }

  void _handleChannelEvent(dynamic event) {
    final bytes = _eventToBytes(event);
    if (bytes == null || bytes.isEmpty) {
      return;
    }

    _incomingBuffer.addAll(bytes);
    while (true) {
      final packet = _tryReadPacket();
      if (packet == null) {
        return;
      }
      _handlePacket(packet);
    }
  }

  void _handleChannelDone() {
    if (_disconnectRequestedByApp || _isDisposed) {
      return;
    }

    final pendingConnect = _connectCompleter;
    if (pendingConnect != null && !pendingConnect.isCompleted) {
      pendingConnect.completeError(
        StateError('WebSocket đã đóng trước khi broker trả CONNACK.'),
      );
      return;
    }

    _pingTimer?.cancel();
    _pongTimeoutTimer?.cancel();
    _setState(
      _state.copyWith(
        connectionStatus: DeviceConnectionStatus.disconnected,
        lastError: _state.lastError ?? 'Kết nối MQTT đã bị đóng.',
      ),
    );
    if (_shouldAutoReconnect()) {
      _scheduleReconnect(_state.lastError);
    }
  }

  void _handleChannelError(Object error) {
    final pendingConnect = _connectCompleter;
    if (pendingConnect != null && !pendingConnect.isCompleted) {
      pendingConnect.completeError(error);
      return;
    }

    if (_disconnectRequestedByApp || _isDisposed) {
      return;
    }

    final message = _formatError(error);
    _setState(
      _state.copyWith(
        connectionStatus: DeviceConnectionStatus.error,
        lastError: message,
      ),
    );
    if (_shouldAutoReconnect()) {
      _scheduleReconnect(message);
    }
  }

  void _handlePacket(Uint8List packet) {
    final header = packet[0];
    final messageType = header >> 4;
    final remainingLengthFieldSize = _remainingLengthFieldSize(packet);
    var offset = 1 + remainingLengthFieldSize;

    switch (messageType) {
      case 2:
        _handleConnAck(packet, offset);
      case 3:
        _handlePublish(packet, header, offset);
      case 9:
        return;
      case 13:
        _pongTimeoutTimer?.cancel();
        return;
      default:
        return;
    }
  }

  void _handleConnAck(Uint8List packet, int offset) {
    if (packet.length < offset + 2) {
      return;
    }

    final returnCode = packet[offset + 1];
    _lastConnAckReturnCode = returnCode;
    final pendingConnect = _connectCompleter;

    if (returnCode == 0) {
      _setState(
        _state.copyWith(
          connectionStatus: DeviceConnectionStatus.connected,
          lastError: null,
        ),
      );
      if (pendingConnect != null && !pendingConnect.isCompleted) {
        pendingConnect.complete();
      }
      return;
    }

    final message = 'Broker từ chối kết nối (CONNACK code $returnCode).';
    if (pendingConnect != null && !pendingConnect.isCompleted) {
      pendingConnect.completeError(StateError(message));
    } else {
      _setState(
        _state.copyWith(
          connectionStatus: DeviceConnectionStatus.error,
          lastError: message,
        ),
      );
    }
  }

  void _handlePublish(Uint8List packet, int header, int offset) {
    if (packet.length < offset + 2) {
      return;
    }

    final topicLength = (packet[offset] << 8) | packet[offset + 1];
    offset += 2;
    if (packet.length < offset + topicLength) {
      return;
    }

    final messageTopic = utf8.decode(
      packet.sublist(offset, offset + topicLength),
    );
    offset += topicLength;

    final qos = (header >> 1) & 0x03;
    int? packetIdentifier;
    if (qos > 0) {
      if (packet.length < offset + 2) {
        return;
      }
      packetIdentifier = (packet[offset] << 8) | packet[offset + 1];
      offset += 2;
    }

    final payloadText = utf8.decode(
      packet.sublist(offset),
      allowMalformed: true,
    );

    if (qos == 1 && packetIdentifier != null) {
      _sendPacket(_encodePubAckPacket(packetIdentifier));
    }

    if (messageTopic != topic) {
      return;
    }

    try {
      final reading = DeviceReading.fromPayload(payloadText);
      _readingsByNode[reading.nodeId] = reading;
      _setState(
        _state.copyWith(
          readings: _sortedReadings(),
          lastMessageAt: reading.receivedAt,
          lastError: null,
        ),
      );
      unawaited(_persistCachedReadings());
    } catch (error) {
      _setState(
        _state.copyWith(lastError: 'Payload không hợp lệ: ${error.toString()}'),
      );
    }
  }

  Future<void> _restoreCachedReadings() async {
    try {
      final preferences = await SharedPreferences.getInstance();
      final raw = preferences.getString(_cachedReadingsKey);
      if (raw == null || raw.isEmpty) {
        return;
      }

      final decoded = jsonDecode(raw);
      if (decoded is! List) {
        return;
      }

      _readingsByNode
        ..clear()
        ..addEntries(
          decoded.whereType<Map>().map((item) {
            final payload = item.map(
              (key, value) => MapEntry(key.toString(), value),
            );
            final reading = DeviceReading.fromJson(payload);
            return MapEntry(reading.nodeId, reading);
          }),
        );

      final restoredReadings = _sortedReadings();
      final restoredLastMessageAt = restoredReadings.isEmpty
          ? null
          : restoredReadings
                .map((reading) => reading.receivedAt)
                .reduce((left, right) => left.isAfter(right) ? left : right);

      _setState(
        _state.copyWith(
          readings: restoredReadings,
          lastMessageAt: restoredLastMessageAt,
        ),
      );
    } catch (_) {
      // Ignore cache restoration failures and reconnect normally.
    }
  }

  Future<void> _persistCachedReadings() async {
    try {
      final preferences = await SharedPreferences.getInstance();
      final payload = _sortedReadings().map((reading) => reading.toJson()).toList();
      await preferences.setString(_cachedReadingsKey, jsonEncode(payload));
    } catch (_) {
      // Ignore cache persistence failures so live MQTT processing keeps working.
    }
  }

  List<DeviceReading> _sortedReadings() {
    final items = _readingsByNode.values.toList()
      ..sort((left, right) => left.nodeId.compareTo(right.nodeId));
    return List<DeviceReading>.unmodifiable(items);
  }

  void _startKeepAlive() {
    _pingTimer?.cancel();
    _pongTimeoutTimer?.cancel();
    _pingTimer = Timer.periodic(Duration(seconds: keepAliveSeconds ~/ 2), (_) {
      if (_state.connectionStatus != DeviceConnectionStatus.connected) {
        return;
      }

      _sendPacket(const <int>[0xC0, 0x00]);
      _pongTimeoutTimer?.cancel();
      _pongTimeoutTimer = Timer(const Duration(seconds: 10), () {
        if (_disconnectRequestedByApp || _isDisposed) {
          return;
        }

        _setState(
          _state.copyWith(
            connectionStatus: DeviceConnectionStatus.error,
            lastError: 'Broker không phản hồi gói PINGRESP.',
          ),
        );
        unawaited(_disconnectCurrentConnection());
        if (_shouldAutoReconnect()) {
          _scheduleReconnect(_state.lastError);
        }
      });
    });
  }

  void _scheduleReconnect(String? errorMessage) {
    if (_isDisposed || _reconnectTimer?.isActive == true) {
      return;
    }

    _reconnectAttempt += 1;
    _reconnectTimer = Timer(_nextReconnectDelay(errorMessage), () {
      if (_isDisposed) {
        return;
      }

      _connect();
    });
  }

  Duration _nextReconnectDelay(String? errorMessage) {
    final normalized = errorMessage?.toLowerCase() ?? '';
    if (normalized.contains('connack')) {
      return const Duration(seconds: 15);
    }

    final seconds = switch (_reconnectAttempt) {
      1 => 5,
      2 => 10,
      3 => 20,
      _ => 30,
    };
    return Duration(seconds: seconds);
  }

  bool _shouldAutoReconnect() {
    return switch (_lastConnAckReturnCode) {
      2 || 4 || 5 => false,
      _ => true,
    };
  }

  int _nextPacketId() {
    final packetId = _nextPacketIdentifier;
    _nextPacketIdentifier += 1;
    if (_nextPacketIdentifier > 0xFFFF) {
      _nextPacketIdentifier = 1;
    }
    return packetId;
  }

  Uint8List? _tryReadPacket() {
    if (_incomingBuffer.length < 2) {
      return null;
    }

    var multiplier = 1;
    var remainingLength = 0;
    var index = 1;

    while (true) {
      if (index >= _incomingBuffer.length) {
        return null;
      }

      final digit = _incomingBuffer[index];
      remainingLength += (digit & 0x7F) * multiplier;
      if ((digit & 0x80) == 0) {
        break;
      }

      multiplier *= 128;
      index += 1;
      if (index > 4) {
        throw const FormatException('MQTT remaining length không hợp lệ.');
      }
    }

    final totalLength = index + 1 + remainingLength;
    if (_incomingBuffer.length < totalLength) {
      return null;
    }

    final packet = Uint8List.fromList(_incomingBuffer.sublist(0, totalLength));
    _incomingBuffer.removeRange(0, totalLength);
    return packet;
  }

  int _remainingLengthFieldSize(Uint8List packet) {
    var index = 1;
    while (index < packet.length && (packet[index] & 0x80) != 0) {
      index += 1;
    }
    return index;
  }

  List<int>? _eventToBytes(dynamic event) {
    if (event is Uint8List) {
      return event;
    }
    if (event is ByteBuffer) {
      return Uint8List.view(event);
    }
    if (event is List<int>) {
      return event;
    }
    if (event is String) {
      return utf8.encode(event);
    }
    return null;
  }

  void _sendPacket(List<int> packet) {
    final channel = _channel;
    if (channel == null) {
      return;
    }

    channel.sink.add(Uint8List.fromList(packet));
  }

  List<int> _encodeConnectPacket({
    required String clientId,
    required int keepAliveSeconds,
  }) {
    final payload = _encodeUtf8String(clientId);
    final variableHeader = <int>[
      ..._encodeUtf8String('MQTT'),
      0x04,
      0x02,
      (keepAliveSeconds >> 8) & 0xFF,
      keepAliveSeconds & 0xFF,
    ];
    final body = <int>[...variableHeader, ...payload];
    return <int>[0x10, ..._encodeRemainingLength(body.length), ...body];
  }

  List<int> _encodeSubscribePacket({
    required int packetIdentifier,
    required String topic,
  }) {
    final payload = <int>[..._encodeUtf8String(topic), 0x00];
    final variableHeader = <int>[
      (packetIdentifier >> 8) & 0xFF,
      packetIdentifier & 0xFF,
    ];
    final body = <int>[...variableHeader, ...payload];
    return <int>[0x82, ..._encodeRemainingLength(body.length), ...body];
  }

  List<int> _encodePubAckPacket(int packetIdentifier) {
    return <int>[
      0x40,
      0x02,
      (packetIdentifier >> 8) & 0xFF,
      packetIdentifier & 0xFF,
    ];
  }

  List<int> _encodeUtf8String(String value) {
    final encoded = utf8.encode(value);
    return <int>[
      (encoded.length >> 8) & 0xFF,
      encoded.length & 0xFF,
      ...encoded,
    ];
  }

  List<int> _encodeRemainingLength(int value) {
    final bytes = <int>[];
    var remaining = value;
    do {
      var digit = remaining % 128;
      remaining ~/= 128;
      if (remaining > 0) {
        digit |= 0x80;
      }
      bytes.add(digit);
    } while (remaining > 0);
    return bytes;
  }

  String _normalizeConnectError(Object error) {
    final rawMessage = _formatError(error);
    final normalized = rawMessage.toLowerCase();

    if (normalized.contains('connack')) {
      return 'Broker chưa trả phản hồi CONNACK. Kiểm tra lại endpoint WebSocket hoặc thử kết nối lại sau vài giây.';
    }

    if (normalized.contains('403') || normalized.contains('forbidden')) {
      return 'Broker từ chối nâng cấp WebSocket (403 Forbidden).';
    }

    return rawMessage;
  }

  Future<void> _closeFailedConnection() async {
    await _disconnectCurrentConnection(sendDisconnectPacket: false);
  }

  Future<void> _disconnectCurrentConnection({
    bool sendDisconnectPacket = true,
  }) async {
    _reconnectTimer?.cancel();
    _pingTimer?.cancel();
    _pongTimeoutTimer?.cancel();
    _incomingBuffer.clear();

    await _channelSubscription?.cancel();
    _channelSubscription = null;

    final channel = _channel;
    _channel = null;
    if (channel == null) {
      return;
    }

    _disconnectRequestedByApp = true;
    try {
      if (sendDisconnectPacket) {
        channel.sink.add(const <int>[0xE0, 0x00]);
      }
      await channel.sink.close();
    } catch (_) {
      // Ignore cleanup errors from already-closed sockets.
    } finally {
      _disconnectRequestedByApp = false;
    }
  }

  void _setState(DeviceTelemetryState nextState) {
    _state = nextState;
    if (!_isDisposed) {
      notifyListeners();
    }
  }

  String _formatError(Object error) {
    final message = error.toString();
    if (message.startsWith('Exception: ')) {
      return message.substring('Exception: '.length);
    }
    if (message.startsWith('StateError: ')) {
      return message.substring('StateError: '.length);
    }
    return message;
  }

  @override
  void disposeService() {
    _isDisposed = true;
    _reconnectTimer?.cancel();
    _pingTimer?.cancel();
    _pongTimeoutTimer?.cancel();
    unawaited(_disconnectCurrentConnection());
    dispose();
  }
}
