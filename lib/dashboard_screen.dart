import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

final supabase = Supabase.instance.client;
final FlutterLocalNotificationsPlugin _notificationsPlugin =
    FlutterLocalNotificationsPlugin();

// ─── Notification Helper ──────────────────────────────────────────────────────
Future<void> initNotifications() async {
  const android = AndroidInitializationSettings('@mipmap/ic_launcher');
  const ios = DarwinInitializationSettings();
  await _notificationsPlugin.initialize(
    const InitializationSettings(android: android, iOS: ios),
  );
}

Future<void> showLowWaterNotification(int level) async {
  const details = NotificationDetails(
    android: AndroidNotificationDetails(
      'water_alert', 'Water Alerts',
      channelDescription: 'Critical water level alerts',
      importance: Importance.high,
      priority: Priority.high,
      color: Color(0xFF00D4FF),
    ),
    iOS: DarwinNotificationDetails(),
  );
  await _notificationsPlugin.show(
    0,
    '⚠️ Critical Water Level',
    'Tank is at $level%. Pump is starting automatically.',
    details,
  );
}

// ─── Dashboard Screen ─────────────────────────────────────────────────────────
class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen>
    with TickerProviderStateMixin {
  // Animations
  late AnimationController _waveController;
  late AnimationController _pulseController;
  late AnimationController _fadeController;

  // Device state
  bool _isPumpOn = false;
  bool _deviceEnabled = true;
  String _mode = 'auto';
  bool _isUpdating = false;
  int _lastNotifiedLevel = 100;

  // Logs
  List<Map<String, dynamic>> _logs = [];
  StreamSubscription? _logSubscription;

  @override
  void initState() {
    super.initState();
    _waveController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..forward();

    initNotifications();
    _loadDevice();
    _subscribeToLogs();
  }

  Future<void> _loadDevice() async {
    try {
      final data = await supabase
          .from('devices')
          .select()
          .eq('id', 'esp32-tank-1')
          .single();
      if (mounted) {
        setState(() {
          _isPumpOn = data['pump_cmd'] as bool? ?? false;
          _deviceEnabled = data['device_enabled'] as bool? ?? true;
          _mode = data['mode'] as String? ?? 'auto';
        });
      }
    } catch (_) {}
  }

  void _subscribeToLogs() {
    _logSubscription = supabase
        .from('activity_logs')
        .stream(primaryKey: ['id'])
        .order('created_at', ascending: false)
        .limit(10)
        .listen((data) {
          if (mounted) setState(() => _logs = data);
        });
  }

  Future<void> _update(Map<String, dynamic> fields) async {
    setState(() => _isUpdating = true);
    try {
      await supabase
          .from('devices')
          .update({...fields, 'updated_at': DateTime.now().toIso8601String()})
          .eq('id', 'esp32-tank-1');

      // Log activity
      String msg = '';
      if (fields.containsKey('pump_cmd')) {
        msg = fields['pump_cmd'] == true ? 'Pump turned ON manually' : 'Pump turned OFF manually';
      } else if (fields.containsKey('mode')) {
        msg = 'Mode changed to ${fields['mode'].toString().toUpperCase()}';
      } else if (fields.containsKey('device_enabled')) {
        msg = fields['device_enabled'] == true ? 'Device enabled' : 'Device disabled';
      }
      if (msg.isNotEmpty) {
        await supabase.from('activity_logs').insert({'message': msg});
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Update failed: $e',
                style: GoogleFonts.lato(color: Colors.white)),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isUpdating = false);
    }
  }

  void _handleWaterLevel(int level) {
    // Trigger notification only once per low-water event
    if (level < 10 && _lastNotifiedLevel >= 10) {
      showLowWaterNotification(level);
    }
    _lastNotifiedLevel = level;
  }

  bool _isOnline(String? updatedAt) {
    if (updatedAt == null) return false;
    return DateTime.now()
            .difference(DateTime.parse(updatedAt).toLocal())
            .inSeconds <=
        10;
  }

  Color _levelColor(int level) {
    if (level <= 20) return const Color(0xFFFF4757);
    if (level <= 50) return const Color(0xFFFFB347);
    return const Color(0xFF00D4FF);
  }

  String _formatTime(String iso) {
    final t = DateTime.parse(iso).toLocal();
    return '${t.hour.toString().padLeft(2, '0')}:'
        '${t.minute.toString().padLeft(2, '0')}:'
        '${t.second.toString().padLeft(2, '0')}';
  }

  @override
  void dispose() {
    _waveController.dispose();
    _pulseController.dispose();
    _fadeController.dispose();
    _logSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: const Color(0xFF060E1A),
        body: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF0A1628), Color(0xFF060E1A), Color(0xFF091520)],
            ),
          ),
          child: StreamBuilder<List<Map<String, dynamic>>>(
            stream: supabase
                .from('devices')
                .stream(primaryKey: ['id'])
                .eq('id', 'esp32-tank-1')
                .limit(1),
            builder: (context, snapshot) {
              final device = snapshot.data?.isNotEmpty == true
                  ? snapshot.data!.first
                  : null;

              final level = (device?['water_level'] as int?) ?? 0;
              final flowRate =
                  ((device?['flow_rate'] as num?)?.toDouble()) ?? 0.0;
              final pumpStatus =
                  (device?['pump_status'] as bool?) ?? false;
              final updatedAt = device?['updated_at'] as String?;
              final online = _isOnline(updatedAt);

              // Side effect: check for low water
              if (device != null) {
                WidgetsBinding.instance
                    .addPostFrameCallback((_) => _handleWaterLevel(level));
              }

              return FadeTransition(
                opacity: _fadeController,
                child: SafeArea(
                  child: CustomScrollView(
                    physics: const BouncingScrollPhysics(),
                    slivers: [
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // ── Top Bar ──
                              _buildTopBar(online),
                              const SizedBox(height: 28),

                              // ── Master Switch + Mode Row ──
                              _buildControlsRow(),
                              const SizedBox(height: 28),

                              // ── Water Gauge ──
                              _buildWaterGauge(level, pumpStatus),
                              const SizedBox(height: 24),

                              // ── Warning Banner ──
                              if (level <= 20) ...[
                                _buildWarningBanner(level),
                                const SizedBox(height: 16),
                              ],
                              if (level == 100) ...[
                                _buildFullBanner(),
                                const SizedBox(height: 16),
                              ],

                              // ── Stats Row ──
                              _buildStatsRow(
                                  level, flowRate, pumpStatus, updatedAt),
                              const SizedBox(height: 24),

                              // ── Pump Toggle Button ──
                              _buildPumpButton(),
                              const SizedBox(height: 28),

                              // ── Activity Log ──
                              _buildActivityLog(),
                              const SizedBox(height: 24),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  // ── Top Bar ─────────────────────────────────────────────────────────────────
  Widget _buildTopBar(bool online) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Water Manager',
                style: GoogleFonts.lato(
                  fontSize: 26,
                  fontWeight: FontWeight.w900,
                  color: Colors.white,
                  letterSpacing: 0.3,
                )),
            Text('ESP32 · Tank Monitor',
                style: GoogleFonts.lato(
                    fontSize: 12,
                    color: Colors.white38,
                    letterSpacing: 1.2)),
          ],
        ),
        AnimatedBuilder(
          animation: _pulseController,
          builder: (_, __) => _GlassBadge(
            label: online ? 'System Online' : 'Offline',
            color: online ? const Color(0xFF00FF88) : Colors.redAccent,
            pulse: online ? _pulseController.value : 0,
          ),
        ),
      ],
    );
  }

  // ── Controls Row ────────────────────────────────────────────────────────────
  Widget _buildControlsRow() {
    return Row(
      children: [
        Expanded(
          child: _GlassCard(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Master Switch',
                        style: GoogleFonts.lato(
                            fontSize: 11,
                            color: Colors.white38,
                            letterSpacing: 0.8)),
                    Text(_deviceEnabled ? 'ENABLED' : 'DISABLED',
                        style: GoogleFonts.lato(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: _deviceEnabled
                              ? const Color(0xFF00FF88)
                              : Colors.redAccent,
                        )),
                  ],
                ),
                Transform.scale(
                  scale: 0.85,
                  child: Switch(
                    value: _deviceEnabled,
                    onChanged: _isUpdating
                        ? null
                        : (v) {
                            setState(() => _deviceEnabled = v);
                            _update({'device_enabled': v});
                          },
                    activeColor: const Color(0xFF00FF88),
                    inactiveThumbColor: Colors.redAccent,
                    inactiveTrackColor: Colors.redAccent.withOpacity(0.3),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _GlassCard(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Mode',
                        style: GoogleFonts.lato(
                            fontSize: 11,
                            color: Colors.white38,
                            letterSpacing: 0.8)),
                    Text(_mode.toUpperCase(),
                        style: GoogleFonts.lato(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: _mode == 'auto'
                              ? const Color(0xFF00D4FF)
                              : Colors.orangeAccent,
                        )),
                  ],
                ),
                Transform.scale(
                  scale: 0.85,
                  child: Switch(
                    value: _mode == 'auto',
                    onChanged: _isUpdating
                        ? null
                        : (v) {
                            final newMode = v ? 'auto' : 'manual';
                            setState(() => _mode = newMode);
                            _update({'mode': newMode});
                          },
                    activeColor: const Color(0xFF00D4FF),
                    inactiveThumbColor: Colors.orangeAccent,
                    inactiveTrackColor: Colors.orangeAccent.withOpacity(0.3),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ── Water Gauge ─────────────────────────────────────────────────────────────
  Widget _buildWaterGauge(int level, bool pumpStatus) {
    return Center(
      child: _GlassCard(
        padding: const EdgeInsets.all(28),
        child: Column(
          children: [
            SizedBox(
              width: 230,
              height: 230,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // Wave fill
                  AnimatedBuilder(
                    animation: _waveController,
                    builder: (_, __) => ClipOval(
                      child: CustomPaint(
                        size: const Size(200, 200),
                        painter: _WavePainter(
                          progress: level / 100.0,
                          animValue: _waveController.value,
                          color: _levelColor(level),
                        ),
                      ),
                    ),
                  ),
                  // Progress ring
                  SizedBox(
                    width: 200,
                    height: 200,
                    child: TweenAnimationBuilder<double>(
                      tween: Tween(begin: 0, end: level / 100.0),
                      duration: const Duration(milliseconds: 800),
                      curve: Curves.easeOutCubic,
                      builder: (_, val, __) => CircularProgressIndicator(
                        value: val,
                        strokeWidth: 7,
                        backgroundColor: Colors.white.withOpacity(0.06),
                        valueColor: AlwaysStoppedAnimation(_levelColor(level)),
                        strokeCap: StrokeCap.round,
                      ),
                    ),
                  ),
                  // Center Text
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TweenAnimationBuilder<int>(
                        tween: IntTween(begin: 0, end: level),
                        duration: const Duration(milliseconds: 800),
                        builder: (_, val, __) => Text('$val%',
                            style: GoogleFonts.lato(
                              fontSize: 56,
                              fontWeight: FontWeight.w900,
                              color: Colors.white,
                              height: 1,
                            )),
                      ),
                      const SizedBox(height: 4),
                      Text('WATER LEVEL',
                          style: GoogleFonts.lato(
                            fontSize: 10,
                            color: Colors.white38,
                            letterSpacing: 2,
                          )),
                      if (pumpStatus) ...[
                        const SizedBox(height: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 3),
                          decoration: BoxDecoration(
                            color: const Color(0xFF00D4FF).withOpacity(0.15),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                                color: const Color(0xFF00D4FF).withOpacity(0.4)),
                          ),
                          child: Text('FILLING',
                              style: GoogleFonts.lato(
                                fontSize: 10,
                                color: const Color(0xFF00D4FF),
                                fontWeight: FontWeight.w700,
                                letterSpacing: 1.5,
                              )),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Warning Banner ──────────────────────────────────────────────────────────
  Widget _buildWarningBanner(int level) {
    return _GlassCard(
      color: Colors.redAccent.withOpacity(0.08),
      borderColor: Colors.redAccent.withOpacity(0.45),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          const Icon(Icons.warning_amber_rounded,
              color: Colors.redAccent, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Low Water Alert',
                    style: GoogleFonts.lato(
                        color: Colors.redAccent,
                        fontWeight: FontWeight.w700,
                        fontSize: 14)),
                Text(
                    level < 10
                        ? 'Critical level! Notification sent.'
                        : 'Pump has started automatically.',
                    style: GoogleFonts.lato(
                        color: Colors.redAccent.withOpacity(0.75),
                        fontSize: 12)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Full Banner ─────────────────────────────────────────────────────────────
  Widget _buildFullBanner() {
    return _GlassCard(
      color: const Color(0xFF00FF88).withOpacity(0.06),
      borderColor: const Color(0xFF00FF88).withOpacity(0.35),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          const Icon(Icons.check_circle_outline_rounded,
              color: Color(0xFF00FF88), size: 22),
          const SizedBox(width: 12),
          Text('Tank is full — pump stopped.',
              style: GoogleFonts.lato(
                  color: const Color(0xFF00FF88),
                  fontWeight: FontWeight.w600,
                  fontSize: 14)),
        ],
      ),
    );
  }

  // ── Stats Row ───────────────────────────────────────────────────────────────
  Widget _buildStatsRow(
      int level, double flowRate, bool pumpStatus, String? updatedAt) {
    return Row(
      children: [
        Expanded(
          child: _StatTile(
            label: 'Pump',
            value: pumpStatus ? 'RUNNING' : 'IDLE',
            icon: Icons.water_drop_outlined,
            valueColor:
                pumpStatus ? const Color(0xFF00D4FF) : Colors.white54,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _StatTile(
            label: 'Flow Rate',
            value: '${flowRate.toStringAsFixed(1)} L/m',
            icon: Icons.speed_rounded,
            valueColor: const Color(0xFF00D4FF),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _StatTile(
            label: 'Updated',
            value: updatedAt != null ? _formatTime(updatedAt) : '—',
            icon: Icons.access_time_rounded,
            valueColor: Colors.white70,
          ),
        ),
      ],
    );
  }

  // ── Pump Button ─────────────────────────────────────────────────────────────
  Widget _buildPumpButton() {
    final isManual = _mode == 'manual';
    return AnimatedOpacity(
      opacity: isManual && _deviceEnabled ? 1.0 : 0.4,
      duration: const Duration(milliseconds: 300),
      child: SizedBox(
        width: double.infinity,
        height: 58,
        child: _isUpdating
            ? const Center(
                child: CircularProgressIndicator(color: Color(0xFF00D4FF)))
            : ElevatedButton.icon(
                onPressed: (isManual && _deviceEnabled && !_isUpdating)
                    ? () {
                        final newState = !_isPumpOn;
                        setState(() => _isPumpOn = newState);
                        _update({'pump_cmd': newState});
                      }
                    : null,
                icon: Icon(
                  _isPumpOn
                      ? Icons.power_settings_new_rounded
                      : Icons.play_arrow_rounded,
                  size: 22,
                ),
                label: Text(
                  _mode == 'auto'
                      ? 'Auto Mode Active'
                      : _isPumpOn
                          ? 'Turn Pump OFF'
                          : 'Turn Pump ON',
                  style: GoogleFonts.lato(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.4,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _isPumpOn
                      ? Colors.redAccent.withOpacity(0.85)
                      : const Color(0xFF00D4FF).withOpacity(0.85),
                  foregroundColor: Colors.white,
                  disabledBackgroundColor:
                      Colors.white.withOpacity(0.07),
                  disabledForegroundColor: Colors.white38,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  elevation: 10,
                  shadowColor: _isPumpOn
                      ? Colors.redAccent.withOpacity(0.5)
                      : const Color(0xFF00D4FF).withOpacity(0.5),
                ),
              ),
      ),
    );
  }

  // ── Activity Log ────────────────────────────────────────────────────────────
  Widget _buildActivityLog() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 12),
          child: Text('Activity Log',
              style: GoogleFonts.lato(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: Colors.white70,
                letterSpacing: 0.5,
              )),
        ),
        _GlassCard(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: _logs.isEmpty
              ? Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text('No activity yet.',
                      style: GoogleFonts.lato(
                          color: Colors.white38, fontSize: 13)),
                )
              : Column(
                  children: _logs.map((log) {
                    final msg = log['message'] as String? ?? '';
                    final time = log['created_at'] as String?;
                    return Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 10),
                      decoration: BoxDecoration(
                        border: Border(
                          bottom: BorderSide(
                              color: Colors.white.withOpacity(0.05)),
                        ),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 6,
                            height: 6,
                            decoration: const BoxDecoration(
                              shape: BoxShape.circle,
                              color: Color(0xFF00D4FF),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(msg,
                                style: GoogleFonts.lato(
                                    color: Colors.white70, fontSize: 13)),
                          ),
                          if (time != null)
                            Text(_formatTime(time),
                                style: GoogleFonts.lato(
                                    color: Colors.white30, fontSize: 11)),
                        ],
                      ),
                    );
                  }).toList(),
                ),
        ),
      ],
    );
  }
}

// ─── Wave Painter ─────────────────────────────────────────────────────────────
class _WavePainter extends CustomPainter {
  final double progress;
  final double animValue;
  final Color color;

  _WavePainter(
      {required this.progress,
      required this.animValue,
      required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final waterY = size.height * (1 - progress);

    final p1 = Paint()
      ..color = color.withOpacity(0.30)
      ..style = PaintingStyle.fill;
    final path1 = Path()..moveTo(0, waterY);
    for (double x = 0; x <= size.width; x++) {
      path1.lineTo(
          x,
          waterY +
              sin((x / size.width * 2 * pi) + (animValue * 2 * pi)) * 9);
    }
    path1
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(path1, p1);

    final p2 = Paint()
      ..color = color.withOpacity(0.50)
      ..style = PaintingStyle.fill;
    final path2 = Path()..moveTo(0, waterY + 5);
    for (double x = 0; x <= size.width; x++) {
      path2.lineTo(
          x,
          waterY +
              5 +
              sin((x / size.width * 2 * pi) +
                      (animValue * 2 * pi) +
                      pi) *
                  6);
    }
    path2
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(path2, p2);
  }

  @override
  bool shouldRepaint(_WavePainter old) => true;
}

// ─── Glass Card ───────────────────────────────────────────────────────────────
class _GlassCard extends StatelessWidget {
  final Widget child;
  final Color? color;
  final Color? borderColor;
  final EdgeInsets? padding;

  const _GlassCard({
    required this.child,
    this.color,
    this.borderColor,
    this.padding,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: padding ?? const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: color ?? Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: borderColor ?? Colors.white.withOpacity(0.09),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.25),
            blurRadius: 20,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: child,
    );
  }
}

// ─── Glass Badge ──────────────────────────────────────────────────────────────
class _GlassBadge extends StatelessWidget {
  final String label;
  final Color color;
  final double pulse;

  const _GlassBadge(
      {required this.label, required this.color, required this.pulse});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08 + pulse * 0.06),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: color,
                boxShadow: [
                  BoxShadow(color: color.withOpacity(0.6), blurRadius: 6)
                ]),
          ),
          const SizedBox(width: 7),
          Text(label,
              style: GoogleFonts.lato(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: color,
                  letterSpacing: 0.3)),
        ],
      ),
    );
  }
}

// ─── Stat Tile ────────────────────────────────────────────────────────────────
class _StatTile extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color valueColor;

  const _StatTile({
    required this.label,
    required this.value,
    required this.icon,
    required this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.04),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.07)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: valueColor, size: 18),
          const SizedBox(height: 8),
          Text(value,
              style: GoogleFonts.lato(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: valueColor,
              )),
          const SizedBox(height: 2),
          Text(label,
              style: GoogleFonts.lato(
                  fontSize: 10,
                  color: Colors.white30,
                  letterSpacing: 0.8)),
        ],
      ),
    );
  }
}
