import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

const developerEmail = 'fastunlocked2017@gmail.com';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const WalkingCompanionApp());
}

class WalkingCompanionApp extends StatelessWidget {
  const WalkingCompanionApp({super.key});

  @override
  Widget build(BuildContext context) {
    const seed = Color(0xFF3E725D);
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
        scaffoldBackgroundColor: const Color(0xFFF5F7F1),
        colorScheme: ColorScheme.fromSeed(
          seedColor: seed,
          brightness: Brightness.light,
          surface: const Color(0xFFFCFDF8),
        ),
        appBarTheme: const AppBarTheme(
          elevation: 0,
          centerTitle: false,
          backgroundColor: Color(0xFFF5F7F1),
          foregroundColor: Color(0xFF203128),
          systemOverlayStyle: SystemUiOverlayStyle.dark,
        ),
        cardTheme: CardThemeData(
          color: const Color(0xFFFCFDF8),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: const BorderSide(color: Color(0xFFE3E9DD)),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: Color(0xFFDCE5D7)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: Color(0xFFDCE5D7)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: seed, width: 1.4),
          ),
        ),
        navigationBarTheme: NavigationBarThemeData(
          indicatorColor: seed.withValues(alpha: 0.14),
          labelTextStyle: WidgetStateProperty.all(
            const TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
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

class WalkingHomeScreen extends StatefulWidget {
  const WalkingHomeScreen({super.key});

  @override
  State<WalkingHomeScreen> createState() => _WalkingHomeScreenState();
}

class _WalkingHomeScreenState extends State<WalkingHomeScreen> {
  static const _storageKey = 'walking_companion_sessions_v1';

  final List<WalkSession> _sessions = [];
  final _noteController = TextEditingController();

  int _tab = 0;
  int _targetMinutes = 10;
  int _elapsedSeconds = 0;
  double _distanceMeters = 0;
  bool _tracking = false;
  bool _loading = true;
  String _gpsStatus = 'جاهز';
  Position? _lastPosition;
  Timer? _timer;
  StreamSubscription<Position>? _positionSubscription;

  @override
  void initState() {
    super.initState();
    _loadSessions();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _positionSubscription?.cancel();
    _noteController.dispose();
    super.dispose();
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
    if (mounted) setState(() => _loading = false);
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
        ? const Center(child: CircularProgressIndicator())
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
                onStop: _stopWalk,
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
        title: const Text(
          'رفيق المشي',
          style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 0),
        ),
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
      _lastPosition = null;
      _gpsStatus = 'جاري التقاط GPS';
    });

    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _elapsedSeconds++);
      if (_elapsedSeconds >= _targetMinutes * 60) {
        _stopWalk(autoCompleted: true);
      }
    });

    const settings = LocationSettings(
      accuracy: LocationAccuracy.best,
      distanceFilter: 3,
    );
    _positionSubscription?.cancel();
    _positionSubscription = Geolocator.getPositionStream(locationSettings: settings).listen(
      (position) {
        if (!_tracking) return;
        if (_lastPosition != null) {
          final meters = Geolocator.distanceBetween(
            _lastPosition!.latitude,
            _lastPosition!.longitude,
            position.latitude,
            position.longitude,
          );
          if (meters >= 0 && meters < 80) {
            _distanceMeters += meters;
          }
        }
        _lastPosition = position;
        if (mounted) {
          setState(() => _gpsStatus = 'دقة الموقع ${position.accuracy.toStringAsFixed(0)} م');
        }
      },
      onError: (_) {
        if (mounted) setState(() => _gpsStatus = 'تعذر قراءة الموقع الآن');
      },
    );
  }

  Future<void> _stopWalk({bool autoCompleted = false}) async {
    if (!_tracking) return;
    _timer?.cancel();
    await _positionSubscription?.cancel();
    _positionSubscription = null;
    final completedSeconds = _elapsedSeconds;
    final completedDistance = _distanceMeters;

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

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 24),
      children: [
        const Text(
          'تحدي اليوم',
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: Color(0xFF203128)),
        ),
        const SizedBox(height: 6),
        Text(
          encouragement(streakDays),
          style: const TextStyle(color: Color(0xFF65746A), height: 1.45),
        ),
        const SizedBox(height: 14),
        _TimerPanel(
          elapsedSeconds: elapsedSeconds,
          targetMinutes: targetMinutes,
          progress: progress,
          tracking: tracking,
        ),
        const SizedBox(height: 12),
        SegmentedButton<int>(
          segments: const [
            ButtonSegment(value: 10, label: Text('10 د')),
            ButtonSegment(value: 20, label: Text('20 د')),
            ButtonSegment(value: 30, label: Text('30 د')),
          ],
          selected: {targetMinutes},
          onSelectionChanged: tracking ? null : (value) => onTargetChanged(value.first),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(child: _MetricTile(title: 'المسافة', value: formatDistance(distanceMeters), color: const Color(0xFF3E725D))),
            const SizedBox(width: 8),
            Expanded(child: _MetricTile(title: 'متوسط السرعة', value: '${averageSpeedKmh.toStringAsFixed(1)} كم/س', color: const Color(0xFF315F72))),
          ],
        ),
        const SizedBox(height: 8),
        _MetricTile(title: 'حالة GPS', value: gpsStatus, color: const Color(0xFF8A6A20)),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: tracking ? onStop : onStart,
          icon: Icon(tracking ? Icons.stop_rounded : Icons.play_arrow_rounded),
          label: Text(tracking ? 'إنهاء وحفظ الجلسة' : 'بدأت المشي'),
        ),
        const SizedBox(height: 8),
        const Text(
          'يفضل فتح خدمة الموقع والخروج لمكان مفتوح لتحسين دقة GPS.',
          style: TextStyle(color: Color(0xFF65746A), height: 1.45),
        ),
      ],
    );
  }
}

class _TimerPanel extends StatelessWidget {
  const _TimerPanel({
    required this.elapsedSeconds,
    required this.targetMinutes,
    required this.progress,
    required this.tracking,
  });

  final int elapsedSeconds;
  final int targetMinutes;
  final double progress;
  final bool tracking;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF203128),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            tracking ? 'الجلسة تعمل الآن' : 'جاهز للمشي',
            style: const TextStyle(color: Color(0xFFD2E1D8), fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          Text(
            formatDuration(elapsedSeconds),
            style: const TextStyle(color: Colors.white, fontSize: 42, fontWeight: FontWeight.w900, height: 1.05),
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 9,
              backgroundColor: Colors.white.withValues(alpha: 0.16),
              valueColor: const AlwaysStoppedAnimation(Color(0xFFAECFAE)),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'الهدف $targetMinutes دقيقة',
            style: const TextStyle(color: Color(0xFFD2E1D8)),
          ),
        ],
      ),
    );
  }
}

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
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 24),
      children: [
        const Text(
          'السجل والإحصائيات',
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: Color(0xFF203128)),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(child: _MetricTile(title: 'الدقائق', value: '$totalMinutes د', color: const Color(0xFF3E725D))),
            const SizedBox(width: 8),
            Expanded(child: _MetricTile(title: 'المسافة', value: '${totalDistanceKm.toStringAsFixed(2)} كم', color: const Color(0xFF315F72))),
          ],
        ),
        const SizedBox(height: 8),
        _MetricTile(title: 'الأيام المتتالية', value: '$streakDays يوم', color: const Color(0xFF8A6A20)),
        const SizedBox(height: 16),
        _WeeklyChart(title: 'آخر 7 أيام - مدة المشي', summaries: weekly, showDistance: false),
        const SizedBox(height: 12),
        _WeeklyChart(title: 'آخر 7 أيام - المسافة', summaries: weekly, showDistance: true),
        const SizedBox(height: 16),
        const Text(
          'آخر الجلسات',
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900, color: Color(0xFF203128)),
        ),
        const SizedBox(height: 8),
        if (sessions.isEmpty)
          const _EmptyState(title: 'لا توجد جلسات بعد', subtitle: 'ابدأ أول تحدي مشي لتظهر الإحصائيات هنا.')
        else
          ...sessions.take(10).map((session) => _SessionTile(session: session)),
      ],
    );
  }
}

class _WeeklyChart extends StatelessWidget {
  const _WeeklyChart({
    required this.title,
    required this.summaries,
    required this.showDistance,
  });

  final String title;
  final List<DailyWalkSummary> summaries;
  final bool showDistance;

  @override
  Widget build(BuildContext context) {
    final maxValue = summaries
        .map((item) => showDistance ? item.distanceMeters : item.durationSeconds / 60)
        .fold<double>(0, (largest, value) => max(largest, value).toDouble());
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.w900, color: Color(0xFF203128))),
            const SizedBox(height: 14),
            SizedBox(
              height: 160,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: summaries.map((item) {
                  final value = showDistance ? item.distanceMeters : item.durationSeconds / 60;
                  final heightFactor = maxValue <= 0 ? 0.04 : (value / maxValue).clamp(0.04, 1.0);
                  return Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 3),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          Text(
                            showDistance ? '${(item.distanceMeters / 1000).toStringAsFixed(1)}' : '${(item.durationSeconds / 60).round()}',
                            style: const TextStyle(fontSize: 10, color: Color(0xFF65746A), fontWeight: FontWeight.w800),
                          ),
                          const SizedBox(height: 5),
                          Expanded(
                            child: Align(
                              alignment: Alignment.bottomCenter,
                              child: FractionallySizedBox(
                                heightFactor: heightFactor,
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: showDistance ? const Color(0xFF315F72) : const Color(0xFF3E725D),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(shortDay(item.date), style: const TextStyle(fontSize: 11, color: Color(0xFF65746A))),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BadgesView extends StatelessWidget {
  const _BadgesView({
    required this.sessionCount,
    required this.streakDays,
  });

  final int sessionCount;
  final int streakDays;

  @override
  Widget build(BuildContext context) {
    final badges = [
      BadgeInfo('أول مشي', 'أكمل أول جلسة مشي.', sessionCount >= 1),
      BadgeInfo('3 أيام', 'حافظ على الحركة 3 أيام.', streakDays >= 3),
      BadgeInfo('7 أيام', 'أسبوع مشي كامل.', streakDays >= 7),
      BadgeInfo('30 يوم', 'بطل التحدي الشهري.', streakDays >= 30),
    ];
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 24),
      children: [
        const Text(
          'الشارات',
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: Color(0xFF203128)),
        ),
        const SizedBox(height: 6),
        const Text(
          'الشارات تظهر كأهداف تحفيزية. في النسخة القادمة سنجعلها تفتح تلقائيًا حسب إنجازك.',
          style: TextStyle(color: Color(0xFF65746A), height: 1.45),
        ),
        const SizedBox(height: 14),
        ...badges.map((badge) => Card(
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: badge.unlocked ? const Color(0xFFE7F0E3) : const Color(0xFFEAEDE8),
                  foregroundColor: badge.unlocked ? const Color(0xFF3E725D) : const Color(0xFF8A9688),
                  child: Icon(badge.unlocked ? Icons.emoji_events_rounded : Icons.lock_outline_rounded),
                ),
                title: Text(badge.title, style: const TextStyle(fontWeight: FontWeight.w900)),
                subtitle: Text(badge.description),
                trailing: Text(
                  badge.unlocked ? 'مفتوحة' : 'قريبًا',
                  style: TextStyle(
                    color: badge.unlocked ? const Color(0xFF3E725D) : const Color(0xFF8A9688),
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            )),
      ],
    );
  }
}

class BadgeInfo {
  const BadgeInfo(this.title, this.description, this.unlocked);

  final String title;
  final String description;
  final bool unlocked;
}

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

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 24),
      children: [
        const Text(
          'مراسلة المطور',
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: Color(0xFF203128)),
        ),
        const SizedBox(height: 6),
        const Text(
          'أرسل اقتراحًا أو مشكلة ظهرت معك أثناء استخدام التطبيق.',
          style: TextStyle(color: Color(0xFF65746A), height: 1.45),
        ),
        const SizedBox(height: 14),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: SelectableText(
              developerEmail,
              style: const TextStyle(fontWeight: FontWeight.w900, color: Color(0xFF203128)),
            ),
          ),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _nameController,
          decoration: const InputDecoration(labelText: 'اسمك اختياري', prefixIcon: Icon(Icons.person_outline_rounded)),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _noteController,
          maxLines: 6,
          decoration: const InputDecoration(
            labelText: 'اكتب الملاحظة',
            alignLabelWithHint: true,
            prefixIcon: Icon(Icons.edit_note_rounded),
          ),
        ),
        const SizedBox(height: 14),
        FilledButton.icon(
          onPressed: _sendEmail,
          icon: const Icon(Icons.send_rounded),
          label: const Text('إرسال عبر الإيميل'),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: _copyMessage,
          icon: const Icon(Icons.copy_rounded),
          label: const Text('نسخ الرسالة'),
        ),
      ],
    );
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
      const SnackBar(content: Text('تم نسخ الرسالة والبريد')),
    );
  }
}

class _MetricTile extends StatelessWidget {
  const _MetricTile({
    required this.title,
    required this.value,
    required this.color,
  });

  final String title;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(color: Color(0xFF65746A), fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            Text(value, style: TextStyle(color: color, fontSize: 19, fontWeight: FontWeight.w900)),
          ],
        ),
      ),
    );
  }
}

class _SessionTile extends StatelessWidget {
  const _SessionTile({required this.session});

  final WalkSession session;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: const CircleAvatar(
          backgroundColor: Color(0xFFE7F0E3),
          foregroundColor: Color(0xFF3E725D),
          child: Icon(Icons.directions_walk_rounded),
        ),
        title: Text(formatDate(session.date), style: const TextStyle(fontWeight: FontWeight.w900)),
        subtitle: Text('مدة ${formatDuration(session.durationSeconds)} · سرعة ${session.averageSpeedKmh.toStringAsFixed(1)} كم/س'),
        trailing: Text(formatDistance(session.distanceMeters), style: const TextStyle(fontWeight: FontWeight.w900)),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.title,
    required this.subtitle,
  });

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          children: [
            const Icon(Icons.directions_walk_outlined, size: 34, color: Color(0xFF8A9688)),
            const SizedBox(height: 8),
            Text(title, style: const TextStyle(fontWeight: FontWeight.w900)),
            const SizedBox(height: 4),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Color(0xFF65746A), height: 1.45),
            ),
          ],
        ),
      ),
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

String encouragement(int streak) {
  if (streak >= 30) return 'ممتاز، أنت محافظ على حركة يومية قوية.';
  if (streak >= 7) return 'أسبوع رائع. حافظ على الإيقاع الهادئ.';
  if (streak >= 3) return 'بدأت العادة تثبت. مشي بسيط كل يوم يصنع فرقًا.';
  return 'ابدأ بخطوة خفيفة اليوم. لا تحتاج رياضة قاسية.';
}

String dayKey(DateTime date) {
  final day = DateTime(date.year, date.month, date.day);
  final month = day.month.toString().padLeft(2, '0');
  final d = day.day.toString().padLeft(2, '0');
  return '${day.year}-$month-$d';
}

String formatDuration(int seconds) {
  final minutes = seconds ~/ 60;
  final rem = seconds % 60;
  return '${minutes.toString().padLeft(2, '0')}:${rem.toString().padLeft(2, '0')}';
}

String formatDistance(double meters) {
  if (meters < 1000) return '${meters.toStringAsFixed(0)} م';
  return '${(meters / 1000).toStringAsFixed(2)} كم';
}

String formatDate(DateTime date) {
  final day = date.day.toString().padLeft(2, '0');
  final month = date.month.toString().padLeft(2, '0');
  return '$day/$month/${date.year}';
}

String shortDay(DateTime date) {
  const days = ['أح', 'إث', 'ثل', 'أر', 'خم', 'جم', 'سب'];
  return days[date.weekday % 7];
}
