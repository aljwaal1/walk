import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_background_service_android/flutter_background_service_android.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

const developerEmail = 'fastunlocked2017@gmail.com';

// ─────────────────────────── COLORS (light, vibrant, sport feel) ──
class WC {
  // Backgrounds
  static const Color bg        = Color(0xFFF7FAF7);
  static const Color surface   = Color(0xFFFFFFFF);
  static const Color card      = Color(0xFFFFFFFF);
  static const Color border    = Color(0xFFE6EEE3);

  // Text
  static const Color text      = Color(0xFF152019);
  static const Color muted     = Color(0xFF647266);
  static const Color hint      = Color(0xFFA4B2A1);

  // Brand accents (vibrant sport palette)
  static const Color green     = Color(0xFF22C55E); // primary action / progress
  static const Color teal      = Color(0xFF14B8A6); // secondary accent
  static const Color blue      = Color(0xFF3B82F6); // speed / stats
  static const Color orange    = Color(0xFFFB923C); // streak / motivation
  static const Color amber     = Color(0xFFF59E0B); // gps/status warm
  static const Color violet    = Color(0xFF8B5CF6); // badges

  static const LinearGradient heroGrad = LinearGradient(
    colors: [Color(0xFF16A34A), Color(0xFF0D9488)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient timerGrad = LinearGradient(
    colors: [Color(0xFF15803D), Color(0xFF0F766E)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
}

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const WalkingCompanionApp());
}

// ─────────────────────────── APP ─────────────────────────────────
class WalkingCompanionApp extends StatelessWidget {
  const WalkingCompanionApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'رفيق المشي',
      locale: const Locale('ar'),
      supportedLocales: const [Locale('ar'), Locale('en')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: WC.bg,
        fontFamily: 'sans-serif',
        colorScheme: ColorScheme.fromSeed(
          seedColor: WC.green,
          brightness: Brightness.light,
          primary: WC.green,
          secondary: WC.teal,
          surface: WC.surface,
        ),
        appBarTheme: const AppBarTheme(
          elevation: 0,
          centerTitle: false,
          backgroundColor: WC.bg,
          foregroundColor: WC.text,
          systemOverlayStyle: SystemUiOverlayStyle.dark,
          titleTextStyle: TextStyle(
            color: WC.text,
            fontSize: 20,
            fontWeight: FontWeight.w900,
            letterSpacing: -0.3,
          ),
        ),
        cardTheme: CardThemeData(
          color: WC.card,
          elevation: 0,
          margin: EdgeInsets.zero,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
            side: const BorderSide(color: WC.border),
          ),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            backgroundColor: WC.green,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            padding: const EdgeInsets.symmetric(vertical: 16),
            textStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            foregroundColor: WC.text,
            side: const BorderSide(color: WC.border, width: 1.4),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            padding: const EdgeInsets.symmetric(vertical: 14),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: WC.surface,
          labelStyle: const TextStyle(color: WC.muted),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: WC.border),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: WC.border),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: WC.green, width: 2),
          ),
        ),
        segmentedButtonTheme: SegmentedButtonThemeData(
          style: SegmentedButton.styleFrom(
            backgroundColor: WC.surface,
            selectedBackgroundColor: WC.green,
            selectedForegroundColor: Colors.white,
            foregroundColor: WC.text,
            side: const BorderSide(color: WC.border),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
        navigationBarTheme: NavigationBarThemeData(
          backgroundColor: WC.surface,
          indicatorColor: WC.green.withValues(alpha: 0.16),
          labelTextStyle: WidgetStateProperty.all(
            const TextStyle(fontSize: 11, fontWeight: FontWeight.w800),
          ),
        ),
      ),
      home: const Directionality(
        textDirection: TextDirection.rtl,
        child: WalkingHomeScreen(),
      ),
    );
  }
}

// ─────────────────────────── MODELS ──────────────────────────────
class WalkSession {
  const WalkSession({
    required this.id,
    required this.date,
    required this.targetMinutes,
    required this.durationSeconds,
    required this.distanceMeters,
  });

  final String id;
  final DateTime date;
  final int targetMinutes;
  final int durationSeconds;
  final double distanceMeters;

  double get averageSpeedKmh {
    if (durationSeconds <= 0) return 0;
    return (distanceMeters / 1000) / (durationSeconds / 3600);
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'date': date.toIso8601String(),
      'targetMinutes': targetMinutes,
      'durationSeconds': durationSeconds,
      'distanceMeters': distanceMeters,
    };
  }

  factory WalkSession.fromJson(Map<String, dynamic> map) {
    return WalkSession(
      id: map['id'] as String? ?? DateTime.now().microsecondsSinceEpoch.toString(),
      date: DateTime.tryParse(map['date'] as String? ?? '') ?? DateTime.now(),
      targetMinutes: (map['targetMinutes'] as num?)?.toInt() ?? 10,
      durationSeconds: (map['durationSeconds'] as num?)?.toInt() ?? 0,
      distanceMeters: (map['distanceMeters'] as num?)?.toDouble() ?? 0,
    );
  }
}

class DailyWalkSummary {
  const DailyWalkSummary({
    required this.date,
    required this.durationSeconds,
    required this.distanceMeters,
  });

  final DateTime date;
  final int durationSeconds;
  final double distanceMeters;
}

class BadgeInfo {
  const BadgeInfo(this.title, this.description, this.unlocked, this.icon, this.color);

  final String title;
  final String description;
  final bool unlocked;
  final IconData icon;
  final Color color;
}

// ─────────────────────────── BACKGROUND SERVICE ──────────────────
// Keys used to communicate between the UI and the background isolate
// via SharedPreferences (simple + reliable across process restarts).
class BgKeys {
  static const tracking = 'bg_tracking';
  static const startEpoch = 'bg_start_epoch';
  static const targetMinutes = 'bg_target_minutes';
  static const distanceMeters = 'bg_distance_meters';
  static const lastLat = 'bg_last_lat';
  static const lastLng = 'bg_last_lng';
  static const gpsAccuracy = 'bg_gps_accuracy';
  static const elapsedSeconds = 'bg_elapsed_seconds';
}

Future<void> initializeBackgroundService() async {
  final service = FlutterBackgroundService();

  const channel = AndroidNotificationChannel(
    'walking_companion_tracking',
    'تتبع المشي',
    description: 'إشعار صامت يظهر فقط أثناء جلسة مشي نشطة',
    importance: Importance.low,
    playSound: false,
    enableVibration: false,
    showBadge: false,
  );

  final notifications = FlutterLocalNotificationsPlugin();
  await notifications
      .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
      ?.createNotificationChannel(channel);

  await service.configure(
    androidConfiguration: AndroidConfiguration(
      onStart: onBackgroundServiceStart,
      autoStart: false,
      isForegroundMode: true,
      notificationChannelId: 'walking_companion_tracking',
      initialNotificationTitle: 'رفيق المشي',
      initialNotificationContent: 'جاري تجهيز التتبع...',
      foregroundServiceNotificationId: 5050,
      foregroundServiceTypes: [AndroidForegroundType.location],
    ),
    iosConfiguration: IosConfiguration(
      autoStart: false,
      onForeground: onBackgroundServiceStart,
    ),
  );
}

// Entry point that runs inside the background isolate.
@pragma('vm:entry-point')
void onBackgroundServiceStart(ServiceInstance service) async {
  DartPluginRegistrant.ensureInitialized();

  final prefs = await SharedPreferences.getInstance();
  Position? lastPosition;
  Timer? ticker;
  StreamSubscription<Position>? posSub;

  Future<void> stopAll() async {
    ticker?.cancel();
    await posSub?.cancel();
    posSub = null;
    if (service is AndroidServiceInstance) {
      service.setAsBackgroundService();
    }
  }

  if (service is AndroidServiceInstance) {
    service.on('setAsForeground').listen((event) {
      service.setAsForegroundService();
    });
    service.on('setAsBackground').listen((event) {
      service.setAsBackgroundService();
    });
  }

  service.on('stopService').listen((event) async {
    await stopAll();
    await service.stopSelf();
  });

  service.on('startTracking').listen((event) async {
    final targetMinutes = (event?['targetMinutes'] as num?)?.toInt() ?? 10;
    await prefs.setBool(BgKeys.tracking, true);
    await prefs.setInt(BgKeys.startEpoch, DateTime.now().millisecondsSinceEpoch);
    await prefs.setInt(BgKeys.targetMinutes, targetMinutes);
    await prefs.setDouble(BgKeys.distanceMeters, 0);
    await prefs.setInt(BgKeys.elapsedSeconds, 0);
    lastPosition = null;

    ticker?.cancel();
    ticker = Timer.periodic(const Duration(seconds: 1), (_) async {
      final startEpoch = prefs.getInt(BgKeys.startEpoch) ?? DateTime.now().millisecondsSinceEpoch;
      final elapsed = ((DateTime.now().millisecondsSinceEpoch - startEpoch) / 1000).round();
      await prefs.setInt(BgKeys.elapsedSeconds, elapsed);

      final dist = prefs.getDouble(BgKeys.distanceMeters) ?? 0;
      final mins = elapsed ~/ 60;
      final secs = elapsed % 60;
      final distLabel = dist < 1000 ? '${dist.toStringAsFixed(0)} م' : '${(dist / 1000).toStringAsFixed(2)} كم';

      if (service is AndroidServiceInstance) {
        service.setForegroundNotificationInfo(
          title: '🚶 جاري تتبع المشي',
          content: '${mins.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')} • $distLabel',
        );
      }

      service.invoke('tick', {
        'elapsedSeconds': elapsed,
        'distanceMeters': dist,
      });

      if (elapsed >= targetMinutes * 60) {
        service.invoke('autoComplete', {});
      }
    });

    posSub?.cancel();
    const settings = LocationSettings(accuracy: LocationAccuracy.best, distanceFilter: 3);
    posSub = Geolocator.getPositionStream(locationSettings: settings).listen((position) async {
      final tracking = prefs.getBool(BgKeys.tracking) ?? false;
      if (!tracking) return;
      if (lastPosition != null) {
        final meters = Geolocator.distanceBetween(
          lastPosition!.latitude,
          lastPosition!.longitude,
          position.latitude,
          position.longitude,
        );
        if (meters >= 0 && meters < 80) {
          final current = prefs.getDouble(BgKeys.distanceMeters) ?? 0;
          await prefs.setDouble(BgKeys.distanceMeters, current + meters);
        }
      }
      lastPosition = position;
      await prefs.setDouble(BgKeys.lastLat, position.latitude);
      await prefs.setDouble(BgKeys.lastLng, position.longitude);
      await prefs.setDouble(BgKeys.gpsAccuracy, position.accuracy);
      service.invoke('gpsUpdate', {'accuracy': position.accuracy});
    });
  });

  service.on('stopTracking').listen((event) async {
    await prefs.setBool(BgKeys.tracking, false);
    await stopAll();
  });
}

String dayKey(DateTime date) => '${date.year}-${date.month}-${date.day}';

String formatDuration(int totalSeconds) {
  final minutes = (totalSeconds ~/ 60).toString().padLeft(2, '0');
  final seconds = (totalSeconds % 60).toString().padLeft(2, '0');
  return '$minutes:$seconds';
}

String formatDistance(double meters) {
  if (meters < 1000) return '${meters.toStringAsFixed(0)} م';
  return '${(meters / 1000).toStringAsFixed(2)} كم';
}

String formatDayLabel(DateTime date) {
  const days = ['الأحد', 'الإثنين', 'الثلاثاء', 'الأربعاء', 'الخميس', 'الجمعة', 'السبت'];
  return days[date.weekday % 7];
}

// ─────────────────────────── HOME SCREEN ─────────────────────────
class WalkingHomeScreen extends StatefulWidget {
  const WalkingHomeScreen({super.key});

  @override
  State<WalkingHomeScreen> createState() => _WalkingHomeScreenState();
}

class _WalkingHomeScreenState extends State<WalkingHomeScreen> {
  static const _storageKey = 'walking_companion_sessions_v1';

  final List<WalkSession> _sessions = [];
  final FlutterBackgroundService _service = FlutterBackgroundService();

  int _tab = 0;
  int _targetMinutes = 10;
  int _elapsedSeconds = 0;
  double _distanceMeters = 0;
  bool _tracking = false;
  bool _loading = true;
  bool _serviceReady = false;
  String _gpsStatus = 'جاهز';
  StreamSubscription? _tickSub;
  StreamSubscription? _gpsSub;
  StreamSubscription? _autoCompleteSub;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  @override
  void dispose() {
    _tickSub?.cancel();
    _gpsSub?.cancel();
    _autoCompleteSub?.cancel();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    await _loadSessions();
    await _initService();
    await _resumeIfTrackingInBackground();
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _initService() async {
    try {
      await initializeBackgroundService();
      _serviceReady = true;

      _tickSub = _service.on('tick').listen((event) {
        if (!mounted || event == null) return;
        setState(() {
          _elapsedSeconds = (event['elapsedSeconds'] as num?)?.toInt() ?? _elapsedSeconds;
          _distanceMeters = (event['distanceMeters'] as num?)?.toDouble() ?? _distanceMeters;
        });
      });

      _gpsSub = _service.on('gpsUpdate').listen((event) {
        if (!mounted || event == null) return;
        final acc = (event['accuracy'] as num?)?.toDouble() ?? 0;
        setState(() => _gpsStatus = 'دقة الموقع ${acc.toStringAsFixed(0)} م');
      });

      _autoCompleteSub = _service.on('autoComplete').listen((event) {
        if (!mounted) return;
        _stopWalk(autoCompleted: true);
      });
    } catch (_) {
      _serviceReady = false;
    }
  }

  // If the app process was killed while tracking continued in the
  // background, restore the UI state from SharedPreferences.
  Future<void> _resumeIfTrackingInBackground() async {
    final prefs = await SharedPreferences.getInstance();
    final tracking = prefs.getBool(BgKeys.tracking) ?? false;
    if (!tracking) return;
    setState(() {
      _tracking = true;
      _targetMinutes = prefs.getInt(BgKeys.targetMinutes) ?? 10;
      _elapsedSeconds = prefs.getInt(BgKeys.elapsedSeconds) ?? 0;
      _distanceMeters = prefs.getDouble(BgKeys.distanceMeters) ?? 0;
      _gpsStatus = 'جاري التتبع في الخلفية';
    });
  }

  Future<void> _loadSessions() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_storageKey);
    if (saved != null && saved.isNotEmpty) {
      final decoded = jsonDecode(saved) as List<dynamic>;
      _sessions
        ..clear()
        ..addAll(decoded.map((item) => WalkSession.fromJson(item as Map<String, dynamic>)));
    }
  }

  Future<void> _saveSessions() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_storageKey, jsonEncode(_sessions.map((item) => item.toJson()).toList()));
  }

  List<WalkSession> get _orderedSessions {
    return [..._sessions]..sort((a, b) => b.date.compareTo(a.date));
  }

  List<DailyWalkSummary> get _lastSevenDays {
    final today = DateTime.now();
    return List.generate(7, (index) {
      final day = DateTime(today.year, today.month, today.day).subtract(Duration(days: 6 - index));
      final list = _sessions.where((session) => dayKey(session.date) == dayKey(day)).toList();
      return DailyWalkSummary(
        date: day,
        durationSeconds: list.fold(0, (sum, item) => sum + item.durationSeconds),
        distanceMeters: list.fold(0, (sum, item) => sum + item.distanceMeters),
      );
    });
  }

  int get _streakDays {
    var streak = 0;
    var cursor = DateTime.now();
    while (true) {
      final hasWalk = _sessions.any((session) => dayKey(session.date) == dayKey(cursor));
      if (!hasWalk) break;
      streak++;
      cursor = cursor.subtract(const Duration(days: 1));
    }
    return streak;
  }

  int get _totalMinutes {
    return (_sessions.fold(0, (sum, item) => sum + item.durationSeconds) / 60).round();
  }

  double get _totalDistanceKm {
    return _sessions.fold(0.0, (sum, item) => sum + item.distanceMeters) / 1000;
  }

  double get _averageSpeedKmh {
    if (_elapsedSeconds <= 0) return 0;
    return (_distanceMeters / 1000) / (_elapsedSeconds / 3600);
  }

  double get _progress {
    final total = _targetMinutes * 60;
    if (total <= 0) return 0;
    return (_elapsedSeconds / total).clamp(0, 1);
  }

  @override
  Widget build(BuildContext context) {
    final body = _loading
        ? const Center(child: CircularProgressIndicator(color: WC.green))
        : IndexedStack(
            index: _tab,
            children: [
              _WalkView(
                tracking: _tracking,
                targetMinutes: _targetMinutes,
                elapsedSeconds: _elapsedSeconds,
                distanceMeters: _distanceMeters,
                averageSpeedKmh: _averageSpeedKmh,
                progress: _progress,
                gpsStatus: _gpsStatus,
                streakDays: _streakDays,
                onTargetChanged: (value) => setState(() => _targetMinutes = value),
                onStart: _startWalk,
                onStop: () => _stopWalk(),
              ),
              _StatsView(
                sessions: _orderedSessions,
                weekly: _lastSevenDays,
                totalMinutes: _totalMinutes,
                totalDistanceKm: _totalDistanceKm,
                streakDays: _streakDays,
              ),
              _BadgesView(sessionCount: _sessions.length, streakDays: _streakDays),
              const _DeveloperContactView(),
            ],
          );

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Container(
              width: 32, height: 32,
              decoration: BoxDecoration(
                gradient: WC.heroGrad,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.directions_walk_rounded, color: Colors.white, size: 18),
            ),
            const SizedBox(width: 10),
            const Text('رفيق المشي'),
          ],
        ),
        actions: [
          if (_tracking)
            Padding(
              padding: const EdgeInsets.only(left: 12),
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: WC.green.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 7, height: 7,
                        decoration: const BoxDecoration(color: WC.green, shape: BoxShape.circle),
                      ),
                      const SizedBox(width: 6),
                      const Text('نشط', style: TextStyle(color: WC.green, fontSize: 11, fontWeight: FontWeight.w800)),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
      body: SafeArea(child: body),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (index) => setState(() => _tab = index),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.directions_walk_outlined),
            selectedIcon: Icon(Icons.directions_walk_rounded),
            label: 'المشي',
          ),
          NavigationDestination(
            icon: Icon(Icons.bar_chart_outlined),
            selectedIcon: Icon(Icons.bar_chart_rounded),
            label: 'السجل',
          ),
          NavigationDestination(
            icon: Icon(Icons.emoji_events_outlined),
            selectedIcon: Icon(Icons.emoji_events_rounded),
            label: 'الشارات',
          ),
          NavigationDestination(
            icon: Icon(Icons.mail_outline_rounded),
            selectedIcon: Icon(Icons.mail_rounded),
            label: 'المطور',
          ),
        ],
      ),
    );
  }

  Future<bool> _ensureLocationReady() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      setState(() => _gpsStatus = 'شغل خدمة الموقع من الهاتف');
      return false;
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
      setState(() => _gpsStatus = 'صلاحية الموقع غير مفعلة');
      return false;
    }

    // For continued tracking with the screen locked, Android requires
    // "Allow all the time" background location access. We politely ask;
    // if denied, foreground-only tracking still works while app is open.
    if (permission != LocationPermission.always) {
      final bgStatus = await Permission.locationAlways.status;
      if (!bgStatus.isGranted) {
        await Permission.locationAlways.request();
      }
    }

    // Notification permission needed on Android 13+ for the silent
    // foreground-service notification.
    final notifStatus = await Permission.notification.status;
    if (!notifStatus.isGranted) {
      await Permission.notification.request();
    }

    return true;
  }

  Future<void> _startWalk() async {
    if (_tracking) return;
    final ready = await _ensureLocationReady();
    if (!ready) return;

    setState(() {
      _tracking = true;
      _elapsedSeconds = 0;
      _distanceMeters = 0;
      _gpsStatus = 'جاري التقاط GPS';
    });

    if (_serviceReady) {
      final running = await _service.isRunning();
      if (!running) {
        await _service.startService();
      }
      _service.invoke('startTracking', {'targetMinutes': _targetMinutes});
    }
  }

  Future<void> _stopWalk({bool autoCompleted = false}) async {
    if (!_tracking) return;

    final completedSeconds = _elapsedSeconds;
    final completedDistance = _distanceMeters;

    if (_serviceReady) {
      _service.invoke('stopTracking', {});
      _service.invoke('stopService', {});
    }

    setState(() {
      _tracking = false;
      _gpsStatus = autoCompleted ? 'أحسنت، اكتمل التحدي' : 'تم حفظ الجلسة';
    });

    if (completedSeconds >= 60 || completedDistance >= 20) {
      final session = WalkSession(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        date: DateTime.now(),
        targetMinutes: _targetMinutes,
        durationSeconds: completedSeconds,
        distanceMeters: completedDistance,
      );
      setState(() => _sessions.add(session));
      await _saveSessions();
      await SystemSound.play(SystemSoundType.alert);
    }
  }
}

// ─────────────────────────── WALK VIEW ───────────────────────────
class _WalkView extends StatelessWidget {
  const _WalkView({
    required this.tracking,
    required this.targetMinutes,
    required this.elapsedSeconds,
    required this.distanceMeters,
    required this.averageSpeedKmh,
    required this.progress,
    required this.gpsStatus,
    required this.streakDays,
    required this.onTargetChanged,
    required this.onStart,
    required this.onStop,
  });

  final bool tracking;
  final int targetMinutes;
  final int elapsedSeconds;
  final double distanceMeters;
  final double averageSpeedKmh;
  final double progress;
  final String gpsStatus;
  final int streakDays;
  final ValueChanged<int> onTargetChanged;
  final VoidCallback onStart;
  final VoidCallback onStop;

  static const List<int> _presets = [5, 10, 15, 20, 30, 45];

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      children: [
        Container(
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            gradient: WC.timerGrad,
            borderRadius: BorderRadius.circular(26),
            boxShadow: [
              BoxShadow(color: WC.green.withValues(alpha: 0.25), blurRadius: 24, offset: const Offset(0, 10)),
            ],
          ),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          tracking ? Icons.satellite_alt_rounded : Icons.gps_fixed_rounded,
                          size: 14, color: Colors.white,
                        ),
                        const SizedBox(width: 6),
                        Text(gpsStatus, style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700)),
                      ],
                    ),
                  ),
                  if (streakDays > 0)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: WC.orange.withValues(alpha: 0.85),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.local_fire_department_rounded, size: 14, color: Colors.white),
                          const SizedBox(width: 4),
                          Text('$streakDays', style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w900)),
                        ],
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 22),
              SizedBox(
                width: 220, height: 220,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    SizedBox(
                      width: 220, height: 220,
                      child: CircularProgressIndicator(
                        value: progress == 0 ? null : progress,
                        strokeWidth: 12,
                        backgroundColor: Colors.white.withValues(alpha: 0.18),
                        valueColor: const AlwaysStoppedAnimation(Colors.white),
                      ),
                    ),
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          formatDuration(elapsedSeconds),
                          style: const TextStyle(color: Colors.white, fontSize: 40, fontWeight: FontWeight.w900, letterSpacing: 1),
                        ),
                        const SizedBox(height: 4),
                        Text('الهدف: $targetMinutes دقيقة', style: const TextStyle(color: Colors.white70, fontSize: 13)),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 22),
              Row(
                children: [
                  Expanded(child: _heroStat(Icons.route_rounded, formatDistance(distanceMeters), 'المسافة')),
                  Container(width: 1, height: 36, color: Colors.white24),
                  Expanded(child: _heroStat(Icons.speed_rounded, '${averageSpeedKmh.toStringAsFixed(1)} كم/س', 'السرعة')),
                ],
              ),
            ],
          ),
        ),

        const SizedBox(height: 18),

        if (!tracking) ...[
          const Text('اختر هدف الوقت', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: WC.text)),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8, runSpacing: 8,
            children: _presets.map((minutes) {
              final selected = minutes == targetMinutes;
              return GestureDetector(
                onTap: () => onTargetChanged(minutes),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                  decoration: BoxDecoration(
                    color: selected ? WC.green : WC.surface,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: selected ? WC.green : WC.border, width: 1.4),
                  ),
                  child: Text(
                    '$minutes د',
                    style: TextStyle(
                      color: selected ? Colors.white : WC.text,
                      fontWeight: FontWeight.w800,
                      fontSize: 14,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 22),
        ],

        SizedBox(
          width: double.infinity,
          child: tracking
              ? FilledButton.icon(
                  onPressed: onStop,
                  style: FilledButton.styleFrom(backgroundColor: WC.orange),
                  icon: const Icon(Icons.stop_circle_rounded),
                  label: const Text('إيقاف الجلسة وحفظها', style: TextStyle(fontSize: 15)),
                )
              : FilledButton.icon(
                  onPressed: onStart,
                  icon: const Icon(Icons.play_circle_fill_rounded),
                  label: const Text('ابدأ المشي الآن', style: TextStyle(fontSize: 15)),
                ),
        ),

        const SizedBox(height: 18),

        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: WC.blue.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: WC.blue.withValues(alpha: 0.18)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.info_rounded, color: WC.blue, size: 18),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'يستمر التتبع حتى عند قفل الشاشة بفضل إشعار صامت بسيط يطلبه نظام أندرويد. لن تسمع له صوتاً أو رنيناً.',
                  style: TextStyle(color: WC.muted, fontSize: 12, height: 1.5),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _heroStat(IconData icon, String value, String label) {
    return Column(
      children: [
        Icon(icon, color: Colors.white, size: 20),
        const SizedBox(height: 6),
        Text(value, style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w900)),
        const SizedBox(height: 2),
        Text(label, style: const TextStyle(color: Colors.white70, fontSize: 11)),
      ],
    );
  }
}

// ─────────────────────────── STATS VIEW ──────────────────────────
class _StatsView extends StatelessWidget {
  const _StatsView({
    required this.sessions,
    required this.weekly,
    required this.totalMinutes,
    required this.totalDistanceKm,
    required this.streakDays,
  });

  final List<WalkSession> sessions;
  final List<DailyWalkSummary> weekly;
  final int totalMinutes;
  final double totalDistanceKm;
  final int streakDays;

  @override
  Widget build(BuildContext context) {
    final maxSeconds = weekly.fold<int>(1, (max, day) => day.durationSeconds > max ? day.durationSeconds : max);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      children: [
        Row(children: [
          Expanded(child: _statCard('إجمالي الدقائق', '$totalMinutes', Icons.timer_rounded, WC.green)),
          const SizedBox(width: 10),
          Expanded(child: _statCard('المسافة الكلية', '${totalDistanceKm.toStringAsFixed(1)} كم', Icons.route_rounded, WC.blue)),
          const SizedBox(width: 10),
          Expanded(child: _statCard('التتابع', '$streakDays يوم', Icons.local_fire_department_rounded, WC.orange)),
        ]),

        const SizedBox(height: 22),

        const Text('آخر 7 أيام', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: WC.text)),
        const SizedBox(height: 14),

        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: WC.card,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: WC.border),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: weekly.map((day) {
              final heightFactor = day.durationSeconds / maxSeconds;
              final hasWalk = day.durationSeconds > 0;
              return Expanded(
                child: Column(
                  children: [
                    Text(
                      hasWalk ? formatDuration(day.durationSeconds) : '-',
                      style: TextStyle(fontSize: 9, color: hasWalk ? WC.green : WC.hint, fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 6),
                    Container(
                      height: 90,
                      alignment: Alignment.bottomCenter,
                      child: FractionallySizedBox(
                        heightFactor: hasWalk ? heightFactor.clamp(0.08, 1.0) : 0.04,
                        child: Container(
                          width: 18,
                          decoration: BoxDecoration(
                            gradient: hasWalk
                                ? const LinearGradient(colors: [WC.green, WC.teal], begin: Alignment.bottomCenter, end: Alignment.topCenter)
                                : null,
                            color: hasWalk ? null : WC.border,
                            borderRadius: BorderRadius.circular(6),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(formatDayLabel(day.date), style: const TextStyle(fontSize: 10, color: WC.muted)),
                  ],
                ),
              );
            }).toList(),
          ),
        ),

        const SizedBox(height: 24),

        const Text('سجل الجلسات', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: WC.text)),
        const SizedBox(height: 12),

        if (sessions.isEmpty)
          Container(
            padding: const EdgeInsets.all(28),
            decoration: BoxDecoration(
              color: WC.card,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: WC.border),
            ),
            child: Column(
              children: [
                Icon(Icons.directions_walk_rounded, size: 44, color: WC.green.withValues(alpha: 0.4)),
                const SizedBox(height: 12),
                const Text('لا توجد جلسات بعد', style: TextStyle(fontWeight: FontWeight.w800)),
                const SizedBox(height: 4),
                const Text('ابدأ أول مشي لك من تبويب المشي', style: TextStyle(color: WC.muted, fontSize: 12)),
              ],
            ),
          )
        else
          ...sessions.map((session) => _sessionTile(session)),
      ],
    );
  }

  Widget _statCard(String title, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: WC.card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: WC.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(height: 8),
          Text(value, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: color)),
          Text(title, style: const TextStyle(color: WC.muted, fontSize: 10)),
        ],
      ),
    );
  }

  Widget _sessionTile(WalkSession session) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: WC.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: WC.border),
      ),
      child: Row(
        children: [
          Container(
            width: 40, height: 40,
            decoration: BoxDecoration(
              color: WC.green.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.directions_walk_rounded, color: WC.green, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${session.date.year}/${session.date.month}/${session.date.day} • ${formatDayLabel(session.date)}',
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
                ),
                const SizedBox(height: 2),
                Text(
                  '${formatDuration(session.durationSeconds)} • ${formatDistance(session.distanceMeters)} • ${session.averageSpeedKmh.toStringAsFixed(1)} كم/س',
                  style: const TextStyle(color: WC.muted, fontSize: 11),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────── BADGES VIEW ─────────────────────────
class _BadgesView extends StatelessWidget {
  const _BadgesView({required this.sessionCount, required this.streakDays});

  final int sessionCount;
  final int streakDays;

  @override
  Widget build(BuildContext context) {
    final badges = <BadgeInfo>[
      BadgeInfo('الخطوة الأولى', 'أكمل أول جلسة مشي', sessionCount >= 1, Icons.flag_circle_rounded, WC.green),
      BadgeInfo('خمس جلسات', 'أكمل 5 جلسات مشي', sessionCount >= 5, Icons.looks_5_rounded, WC.blue),
      BadgeInfo('عشر جلسات', 'أكمل 10 جلسات مشي', sessionCount >= 10, Icons.looks_one_rounded, WC.violet),
      BadgeInfo('25 جلسة', 'أكمل 25 جلسة مشي', sessionCount >= 25, Icons.military_tech_rounded, WC.amber),
      BadgeInfo('3 أيام متتالية', 'حافظ على التتابع 3 أيام', streakDays >= 3, Icons.local_fire_department_rounded, WC.orange),
      BadgeInfo('7 أيام متتالية', 'حافظ على التتابع أسبوعاً كاملاً', streakDays >= 7, Icons.whatshot_rounded, WC.orange),
      BadgeInfo('14 يوماً متتالياً', 'أسبوعان من الالتزام', streakDays >= 14, Icons.bolt_rounded, WC.amber),
      BadgeInfo('30 يوماً متتالياً', 'شهر كامل من المشي اليومي', streakDays >= 30, Icons.workspace_premium_rounded, WC.violet),
    ];

    final unlockedCount = badges.where((badge) => badge.unlocked).length;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: WC.heroGrad,
            borderRadius: BorderRadius.circular(22),
          ),
          child: Row(
            children: [
              const Icon(Icons.emoji_events_rounded, color: Colors.white, size: 38),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('$unlockedCount من ${badges.length} شارة',
                      style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w900)),
                    const SizedBox(height: 4),
                    const Text('استمر بالمشي لفتح المزيد', style: TextStyle(color: Colors.white70, fontSize: 12)),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: badges.length,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 0.95,
          ),
          itemBuilder: (context, index) {
            final badge = badges[index];
            return Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: badge.unlocked ? WC.card : WC.surface,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: badge.unlocked ? badge.color.withValues(alpha: 0.3) : WC.border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 44, height: 44,
                    decoration: BoxDecoration(
                      color: badge.unlocked ? badge.color.withValues(alpha: 0.14) : WC.hint.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(
                      badge.icon,
                      color: badge.unlocked ? badge.color : WC.hint,
                      size: 22,
                    ),
                  ),
                  const Spacer(),
                  Text(badge.title,
                    style: TextStyle(
                      fontWeight: FontWeight.w800, fontSize: 13,
                      color: badge.unlocked ? WC.text : WC.hint,
                    )),
                  const SizedBox(height: 3),
                  Text(badge.description,
                    style: TextStyle(fontSize: 10, color: badge.unlocked ? WC.muted : WC.hint, height: 1.3)),
                ],
              ),
            );
          },
        ),
      ],
    );
  }
}

// ─────────────────────────── DEVELOPER CONTACT VIEW ──────────────
class _DeveloperContactView extends StatefulWidget {
  const _DeveloperContactView();

  @override
  State<_DeveloperContactView> createState() => _DeveloperContactViewState();
}

class _DeveloperContactViewState extends State<_DeveloperContactView> {
  final _nameController = TextEditingController();
  final _noteController = TextEditingController();

  @override
  void dispose() {
    _nameController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  String _messageBody() {
    final name = _nameController.text.trim();
    final note = _noteController.text.trim();
    return 'اسم المرسل: ${name.isEmpty ? 'غير مذكور' : name}\n\nالملاحظة:\n${note.isEmpty ? 'لم يتم كتابة ملاحظة.' : note}\n\nالتطبيق: رفيق المشي';
  }

  Future<void> _sendEmail() async {
    final uri = Uri(
      scheme: 'mailto',
      path: developerEmail,
      queryParameters: {
        'subject': 'ملاحظة على تطبيق رفيق المشي',
        'body': _messageBody(),
      },
    );
    try {
      final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!opened) await _copyMessage();
    } catch (_) {
      await _copyMessage();
    }
  }

  Future<void> _copyMessage() async {
    await Clipboard.setData(ClipboardData(text: 'إلى: $developerEmail\n\n${_messageBody()}'));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('تم نسخ الرسالة والبريد'),
        backgroundColor: WC.text,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 32),
      children: [
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            gradient: WC.heroGrad,
            borderRadius: BorderRadius.circular(24),
          ),
          child: Column(
            children: [
              Container(
                width: 70, height: 70,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Icon(Icons.code_rounded, color: Colors.white, size: 34),
              ),
              const SizedBox(height: 16),
              const Text('تواصل مع المطور', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w900)),
              const SizedBox(height: 6),
              const Text(
                'لديك ملاحظة أو اقتراح لتحسين التطبيق؟\nأرسل رسالة مباشرة',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white70, fontSize: 13, height: 1.6),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),

        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: WC.card,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: WC.border),
          ),
          child: Row(
            children: [
              Container(
                width: 42, height: 42,
                decoration: BoxDecoration(
                  color: WC.blue.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: const Icon(Icons.email_rounded, color: WC.blue, size: 20),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('البريد الإلكتروني', style: TextStyle(color: WC.muted, fontSize: 11)),
                    SizedBox(height: 2),
                    Text(developerEmail, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                  ],
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 16),

        TextField(
          controller: _nameController,
          decoration: const InputDecoration(labelText: 'اسمك (اختياري)', prefixIcon: Icon(Icons.person_rounded)),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _noteController,
          minLines: 4,
          maxLines: 8,
          decoration: const InputDecoration(
            labelText: 'رسالتك أو ملاحظتك',
            alignLabelWithHint: true,
            prefixIcon: Icon(Icons.edit_note_rounded),
          ),
        ),

        const SizedBox(height: 14),
        FilledButton.icon(
          onPressed: _sendEmail,
          icon: const Icon(Icons.send_rounded),
          label: const Text('إرسال بريد إلكتروني'),
        ),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          onPressed: _copyMessage,
          icon: const Icon(Icons.copy_rounded, size: 18),
          label: const Text('نسخ الرسالة فقط'),
        ),

        const SizedBox(height: 24),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: WC.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: WC.border),
          ),
          child: const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Icon(Icons.info_outline_rounded, color: WC.muted, size: 16),
                SizedBox(width: 8),
                Text('عن التطبيق', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
              ]),
              SizedBox(height: 8),
              Text(
                'رفيق المشي v2.0\nتتبع GPS حتى مع قفل الشاشة • إحصائيات أسبوعية • شارات تحفيزية • يعمل بدون إنترنت',
                style: TextStyle(color: WC.muted, fontSize: 12, height: 1.6),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
