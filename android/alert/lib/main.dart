import 'dart:async';

import 'package:app_settings/app_settings.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

import 'models/device_reading.dart';
import 'services/android_background_monitor.dart';
import 'services/mqtt_device_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeAndroidBackgroundMonitor();
  runApp(const AlertApp());
}

class AlertApp extends StatelessWidget {
  const AlertApp({super.key, this.telemetryService});

  final DeviceTelemetryService? telemetryService;

  @override
  Widget build(BuildContext context) {
    const seedColor = Color(0xFF1C7C54);

    return MaterialApp(
      title: 'Alert',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: seedColor),
        scaffoldBackgroundColor: const Color(0xFFF4F7F2),
        appBarTheme: const AppBarTheme(
          centerTitle: false,
          backgroundColor: Colors.transparent,
          surfaceTintColor: Colors.transparent,
        ),
      ),
      home: AlertDashboard(telemetryService: telemetryService),
    );
  }
}

class AlertDashboard extends StatefulWidget {
  const AlertDashboard({super.key, this.telemetryService});

  final DeviceTelemetryService? telemetryService;

  @override
  State<AlertDashboard> createState() => _AlertDashboardState();
}

class _AlertDashboardState extends State<AlertDashboard>
    with WidgetsBindingObserver {
  static const MethodChannel _notificationChannel = MethodChannel(
    'com.khanhnd.alert/notifications',
  );

  late final DeviceTelemetryService _telemetryService;
  late final bool _ownsTelemetryService;

  int _selectedIndex = 0;
  bool _notificationsEnabled = false;
  bool _isCheckingNotificationStatus = true;
  bool _hasRequestedNotificationPermission = false;
  bool _backgroundMonitorEnabled = false;
  bool _isUpdatingBackgroundMonitor = false;
  final Map<String, DeviceReading> _foregroundAlertReadings =
      <String, DeviceReading>{};

  @override
  void initState() {
    super.initState();
    _ownsTelemetryService = widget.telemetryService == null;
    _telemetryService = widget.telemetryService ?? MqttDeviceService();
    _telemetryService.addListener(_handleTelemetryChanged);
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _bootstrap());
  }

  @override
  void dispose() {
    _telemetryService.removeListener(_handleTelemetryChanged);
    if (_ownsTelemetryService) {
      _telemetryService.disposeService();
    }
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void _handleTelemetryChanged() {
    if (!mounted) {
      return;
    }

    unawaited(_syncForegroundNotifications());
    setState(() {});
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _syncNotificationStatus();
      unawaited(_syncBackgroundMonitorStatus());
    }
  }

  Future<void> _bootstrap() async {
    unawaited(_telemetryService.start());
    await _syncNotificationStatus();
    await _requestNotificationPermissionIfNeeded();
    await ensureAndroidBackgroundMonitorRunningIfEnabled();
    await _syncBackgroundMonitorStatus();
  }

  Future<void> _requestNotificationPermissionIfNeeded() async {
    if (_selectedIndex != 0 || _hasRequestedNotificationPermission) {
      return;
    }

    _hasRequestedNotificationPermission = true;

    try {
      await Permission.notification.request();
    } on MissingPluginException {
      return;
    } on PlatformException {
      return;
    }

    await _syncNotificationStatus();
  }

  Future<void> _syncNotificationStatus() async {
    final enabled = await _readNotificationStatus();
    if (!mounted) {
      return;
    }

    setState(() {
      _notificationsEnabled = enabled;
      _isCheckingNotificationStatus = false;
    });
  }

  Future<bool> _readNotificationStatus() async {
    if (kIsWeb) {
      return true;
    }

    try {
      final enabled = await _notificationChannel.invokeMethod<bool>(
        'areNotificationsEnabled',
      );
      if (enabled != null) {
        return enabled;
      }
    } on MissingPluginException {
      return true;
    } on PlatformException {
      return true;
    }

    try {
      final status = await Permission.notification.status;
      return status.isGranted || status.isLimited || status.isProvisional;
    } on MissingPluginException {
      return true;
    } on PlatformException {
      return true;
    }
  }

  Future<void> _openNotificationSettings() async {
    try {
      await AppSettings.openAppSettings(type: AppSettingsType.notification);
    } on MissingPluginException {
      return;
    } on PlatformException {
      return;
    }
  }

  Future<void> _syncBackgroundMonitorStatus() async {
    final enabled = await isAndroidBackgroundMonitorRunning();
    if (!mounted) {
      return;
    }

    setState(() {
      _backgroundMonitorEnabled = enabled;
    });
  }

  Future<void> _toggleBackgroundMonitor(bool enabled) async {
    if (_isUpdatingBackgroundMonitor) {
      return;
    }

    setState(() {
      _isUpdatingBackgroundMonitor = true;
    });

    try {
      if (enabled) {
        if (!_hasRequestedNotificationPermission) {
          await _requestNotificationPermissionIfNeeded();
        }

        await _syncNotificationStatus();
        if (!_notificationsEnabled) {
          await _openNotificationSettings();
          return;
        }

        final started = await startAndroidBackgroundMonitor();
        if (!mounted) {
          return;
        }

        setState(() {
          _backgroundMonitorEnabled = started;
        });
        return;
      }

      await stopAndroidBackgroundMonitor();
      if (!mounted) {
        return;
      }

      setState(() {
        _backgroundMonitorEnabled = false;
      });
    } finally {
      if (mounted) {
        setState(() {
          _isUpdatingBackgroundMonitor = false;
        });
      }
    }
  }

  Future<void> _syncForegroundNotifications() async {
    if (!_notificationsEnabled) {
      return;
    }

    if (await isAndroidBackgroundMonitorRunning()) {
      return;
    }

    final telemetry = _telemetryService.state;
    for (final reading in telemetry.readings) {
      final previous = _foregroundAlertReadings[reading.nodeId];

      if (shouldTriggerAlertForReadings(previous, reading)) {
        await showAlertNotificationForReading(reading);
      } else if (shouldClearAlertForReadings(previous, reading)) {
        await clearAlertNotificationForNode(reading.nodeId);
      }

      _foregroundAlertReadings[reading.nodeId] = reading;
    }
  }

  void _onDestinationSelected(int index) {
    setState(() {
      _selectedIndex = index;
    });

    if (index == 0) {
      _requestNotificationPermissionIfNeeded();
    }
  }

  @override
  Widget build(BuildContext context) {
    final telemetry = _telemetryService.state;
    final title = _selectedIndex == 0
        ? 'Thông tin thiết bị'
        : 'Thông tin profile';
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          title,
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        actions: _selectedIndex == 0
            ? [
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _connectionStatusLabel(telemetry.connectionStatus),
                        style: theme.textTheme.labelLarge?.copyWith(
                          color: _connectionStatusColor(
                            telemetry.connectionStatus,
                          ),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(width: 32),
                      IconButton(
                        onPressed: () {
                          unawaited(_telemetryService.retry());
                        },
                        tooltip: 'Kết nối lại',
                        icon: const Icon(Icons.refresh_rounded),
                      ),
                    ],
                  ),
                ),
              ]
            : null,
      ),
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 220),
        child: _selectedIndex == 0
            ? _HomeSection(key: ValueKey('home'), telemetry: telemetry)
            : _SettingsSection(
                key: const ValueKey('settings'),
                notificationsEnabled: _notificationsEnabled,
                isCheckingNotificationStatus: _isCheckingNotificationStatus,
                backgroundMonitorEnabled: _backgroundMonitorEnabled,
                isUpdatingBackgroundMonitor: _isUpdatingBackgroundMonitor,
                onOpenNotificationSettings: _openNotificationSettings,
                onToggleBackgroundMonitor: _toggleBackgroundMonitor,
              ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home_rounded), label: 'Home'),
          NavigationDestination(
            icon: Icon(Icons.settings_rounded),
            label: 'Setting',
          ),
        ],
        onDestinationSelected: _onDestinationSelected,
      ),
    );
  }
}

class _HomeSection extends StatelessWidget {
  const _HomeSection({required this.telemetry, super.key});

  final DeviceTelemetryState telemetry;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
      children: [
        if (telemetry.lastError case final String lastError) ...[
          _TelemetryNoticeCard(message: lastError),
          const SizedBox(height: 16),
        ],
        _DeviceCardsSection(telemetry: telemetry),
      ],
    );
  }
}

class _SettingsSection extends StatelessWidget {
  const _SettingsSection({
    required this.notificationsEnabled,
    required this.isCheckingNotificationStatus,
    required this.backgroundMonitorEnabled,
    required this.isUpdatingBackgroundMonitor,
    required this.onOpenNotificationSettings,
    required this.onToggleBackgroundMonitor,
    super.key,
  });

  final bool notificationsEnabled;
  final bool isCheckingNotificationStatus;
  final bool backgroundMonitorEnabled;
  final bool isUpdatingBackgroundMonitor;
  final VoidCallback onOpenNotificationSettings;
  final ValueChanged<bool> onToggleBackgroundMonitor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
      children: [
        _SurfaceCard(
          child: Column(
            children: [
              const _SettingsRow(icon: Icons.home_rounded, title: 'Admin'),
              const Divider(indent: 32, endIndent: 32, height: 1),
              _SettingsRow(
                icon: Icons.notifications_none_rounded,
                title: 'Thông báo',
                subtitle: isCheckingNotificationStatus
                    ? 'Đang đồng bộ trạng thái'
                    : notificationsEnabled
                    ? 'Đang bật'
                    : 'Đang tắt',
                trailing: Switch.adaptive(
                  value: notificationsEnabled,
                  onChanged: (_) => onOpenNotificationSettings(),
                ),
                onTap: onOpenNotificationSettings,
              ),
              const Divider(indent: 32, endIndent: 32, height: 1),
              _SettingsRow(
                icon: Icons.shield_outlined,
                title: 'Giám sát nền Android',
                subtitle: isUpdatingBackgroundMonitor
                    ? 'Đang cập nhật'
                    : backgroundMonitorEnabled
                    ? 'Đang bật'
                    : 'Đang tắt',
                trailing: Switch.adaptive(
                  value: backgroundMonitorEnabled,
                  onChanged: isUpdatingBackgroundMonitor
                      ? null
                      : onToggleBackgroundMonitor,
                ),
                onTap: () => onToggleBackgroundMonitor(
                  !backgroundMonitorEnabled,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Text(
            'Chạm vào dòng thông báo để mở đúng phần cài đặt notification. Khi bật giám sát nền, Android sẽ giữ một thông báo thường trực để app tiếp tục nghe MQTT kể cả khi bạn đóng giao diện.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: const Color(0xFF667085),
              height: 1.5,
            ),
          ),
        ),
        const SizedBox(height: 10),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Text(
            'Nếu bạn force stop app từ Settings hoặc bấm Stop trong mục Active apps trên Android 13+, dịch vụ nền sẽ dừng hẳn và bạn cần mở app lại để bật lại giám sát.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: const Color(0xFF667085),
              height: 1.5,
            ),
          ),
        ),
      ],
    );
  }
}

class _SurfaceCard extends StatelessWidget {
  const _SurfaceCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(28),
        boxShadow: const [
          BoxShadow(
            color: Color(0x140F172A),
            blurRadius: 24,
            offset: Offset(0, 14),
          ),
        ],
      ),
      child: child,
    );
  }
}

class _TelemetryNoticeCard extends StatelessWidget {
  const _TelemetryNoticeCard({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFFFEECEB),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFF7B4AE)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.error_outline_rounded, color: Color(0xFFB42318)),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: const Color(0xFF912018),
                height: 1.45,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DeviceCardsSection extends StatelessWidget {
  const _DeviceCardsSection({required this.telemetry});

  final DeviceTelemetryState telemetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final devices = telemetry.readings;
    final helperText = switch (telemetry.connectionStatus) {
      DeviceConnectionStatus.connected =>
        'Đã kết nối thành công nhưng chưa nhận được bản tin nào từ topic ${telemetry.topic}.',
      DeviceConnectionStatus.connecting =>
        'Ứng dụng đang kết nối tới broker MQTT và chờ dữ liệu đầu tiên.',
      DeviceConnectionStatus.error =>
        'Không nhận được dữ liệu vì payload hoặc kết nối đang có lỗi.',
      DeviceConnectionStatus.disconnected =>
        'Ứng dụng đang chờ khôi phục kết nối MQTT để nhận dữ liệu thiết bị.',
    };

    if (devices.isEmpty) {
      return _SurfaceCard(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
          child: Text(
            helperText,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: const Color(0xFF667085),
              height: 1.5,
            ),
          ),
        ),
      );
    }

    return Column(
      children: [
        for (final reading in devices) ...[
          _DeviceStatusCard(reading: reading),
          const SizedBox(height: 16),
        ],
      ],
    );
  }
}

class _DeviceStatusCard extends StatelessWidget {
  const _DeviceStatusCard({required this.reading});

  final DeviceReading reading;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isFireCard = reading.isAlerting && !reading.isFullyOffline;
    final badgeBackground = _deviceBadgeBackground(reading);
    final badgeForeground = _deviceBadgeForeground(reading);
    final cardBackground = isFireCard
        ? const Color(0xFFD92D20)
        : Colors.white;
    final cardBorderColor = isFireCard
        ? const Color(0xFFFDA29B)
        : const Color(0xFFE4E7EC);
    final primaryTextColor = isFireCard
        ? Colors.white
        : const Color(0xFF101828);
    final secondaryTextColor = isFireCard
        ? const Color(0xFFFEE4E2)
        : const Color(0xFF667085);
    final dividerColor = isFireCard
        ? const Color(0xFFFB6514)
        : const Color(0xFFF2F4F7);

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: cardBackground,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: cardBorderColor),
        boxShadow: const [
          BoxShadow(
            color: Color(0x120F172A),
            blurRadius: 20,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        reading.deviceName,
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: primaryTextColor,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        reading.nodeId,
                        style: theme.textTheme.labelLarge?.copyWith(
                          color: secondaryTextColor,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.2,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 9,
                  ),
                  decoration: BoxDecoration(
                    color: badgeBackground,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    _deviceBadgeLabel(reading),
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: badgeForeground,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: dividerColor),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 8, 18, 10),
            child: Column(
              children: [
                _DeviceDetailRow(
                  icon: Icons.thermostat_rounded,
                  iconColor: isFireCard
                      ? Colors.white
                      : const Color(0xFFD92D20),
                  label: 'Nhiệt độ',
                  value: reading.isFullyOffline
                      ? 'N/A'
                      : '${reading.temperature.toStringAsFixed(2)}°C',
                  labelColor: isFireCard
                      ? const Color(0xFFFEE4E2)
                      : const Color(0xFF344054),
                  valueColor: isFireCard ? Colors.white : null,
                ),
                Divider(height: 18, color: dividerColor),
                _DeviceDetailRow(
                  icon: reading.isAlerting && !reading.isFullyOffline
                      ? Icons.error_rounded
                      : Icons.check_circle_rounded,
                  iconColor: isFireCard
                      ? Colors.white
                      : _environmentValueColor(reading),
                  label: 'Tình trạng môi trường',
                  value: reading.environmentLabel,
                  labelColor: isFireCard
                      ? const Color(0xFFFEE4E2)
                      : const Color(0xFF344054),
                  valueColor: isFireCard
                      ? Colors.white
                      : _environmentValueColor(reading),
                ),
                Divider(height: 18, color: dividerColor),
                _DeviceDetailRow(
                  icon: reading.isSensor1Working
                      ? Icons.check_circle_rounded
                      : Icons.cancel_rounded,
                  iconColor: isFireCard
                      ? Colors.white
                      : reading.isSensor1Working
                      ? const Color(0xFF16A34A)
                      : const Color(0xFFD92D20),
                  label: 'Sensor 1',
                  value: reading.sensor1Label,
                  labelColor: isFireCard
                      ? const Color(0xFFFEE4E2)
                      : const Color(0xFF344054),
                  valueColor: isFireCard
                      ? Colors.white
                      : reading.isSensor1Working
                      ? const Color(0xFF101828)
                      : const Color(0xFFD92D20),
                ),
                Divider(height: 18, color: dividerColor),
                _DeviceDetailRow(
                  icon: reading.isSensor2Working
                      ? Icons.check_circle_rounded
                      : Icons.cancel_rounded,
                  iconColor: isFireCard
                      ? Colors.white
                      : reading.isSensor2Working
                      ? const Color(0xFF16A34A)
                      : const Color(0xFFD92D20),
                  label: 'Sensor 2',
                  value: reading.sensor2Label,
                  labelColor: isFireCard
                      ? const Color(0xFFFEE4E2)
                      : const Color(0xFF344054),
                  valueColor: isFireCard
                      ? Colors.white
                      : reading.isSensor2Working
                      ? const Color(0xFF101828)
                      : const Color(0xFFD92D20),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DeviceDetailRow extends StatelessWidget {
  const _DeviceDetailRow({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.value,
    this.labelColor,
    this.valueColor,
  });

  final IconData icon;
  final Color iconColor;
  final String label;
  final String value;
  final Color? labelColor;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Icon(icon, size: 20, color: iconColor),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: '$label: ',
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: labelColor ?? const Color(0xFF344054),
                    fontWeight: FontWeight.w700,
                    height: 1.4,
                  ),
                ),
                TextSpan(
                  text: value,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: valueColor ?? const Color(0xFF101828),
                    fontWeight: FontWeight.w800,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

String _deviceBadgeLabel(DeviceReading reading) {
  if (reading.isFullyOffline) {
    return 'NGỪNG HOẠT ĐỘNG';
  }

  if (reading.isAlerting) {
    return 'PHÁT HIỆN CHÁY';
  }

  return 'BÌNH THƯỜNG';
}

Color _deviceBadgeBackground(DeviceReading reading) {
  if (reading.isFullyOffline) {
    return const Color(0xFFF2F4F7);
  }

  if (reading.isAlerting) {
    return const Color(0xFFFEE4E2);
  }

  return const Color(0xFFE9F8EF);
}

Color _deviceBadgeForeground(DeviceReading reading) {
  if (reading.isFullyOffline) {
    return const Color(0xFF475467);
  }

  if (reading.isAlerting) {
    return const Color(0xFFB42318);
  }

  return const Color(0xFF027A48);
}

Color _environmentValueColor(DeviceReading reading) {
  if (reading.isFullyOffline) {
    return const Color(0xFF475467);
  }

  if (reading.isAlerting) {
    return const Color(0xFFB42318);
  }

  return const Color(0xFF16A34A);
}

class _SettingsRow extends StatelessWidget {
  const _SettingsRow({
    required this.icon,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final content = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: const Color(0xFFEFF7F1),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: theme.colorScheme.primary),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    subtitle!,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: const Color(0xFF667085),
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (trailing case final Widget widget) widget,
        ],
      ),
    );

    if (onTap == null) {
      return content;
    }

    return InkWell(
      borderRadius: BorderRadius.circular(28),
      onTap: onTap,
      child: content,
    );
  }
}

String _connectionStatusLabel(DeviceConnectionStatus status) {
  return switch (status) {
    DeviceConnectionStatus.connected => 'Đã kết nối',
    DeviceConnectionStatus.connecting => 'Đang kết nối',
    DeviceConnectionStatus.error => 'Có lỗi',
    DeviceConnectionStatus.disconnected => 'Mất kết nối',
  };
}

Color _connectionStatusColor(DeviceConnectionStatus status) {
  return switch (status) {
    DeviceConnectionStatus.connected => const Color(0xFF027A48),
    DeviceConnectionStatus.connecting => const Color(0xFFB54708),
    DeviceConnectionStatus.error => const Color(0xFFB42318),
    DeviceConnectionStatus.disconnected => const Color(0xFF475467),
  };
}
