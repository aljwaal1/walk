import 'dart:async';
import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:video_player/video_player.dart';
import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit_config.dart';
import 'package:ffmpeg_kit_flutter_new/ffprobe_kit.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';

// ═══════════════════════════════════════════════════════════════════════════
// الألوان — هوية داش كام احترافية (أسود/رمادي غامق + أحمر للتسجيل)
// ═══════════════════════════════════════════════════════════════════════════
class DashColors {
  static const bg = Color(0xFF0A0E12);
  static const panel = Color(0xFF14191F);
  static const panelBorder = Color(0xFF232B33);
  static const red = Color(0xFFE53935); // لون التسجيل + الستامب
  static const redDark = Color(0xFFB22A24);
  static const green = Color(0xFF22C55E); // حالة طبيعية / جاهز
  static const amber = Color(0xFFF5A623); // تنبيهات
  static const textDim = Color(0xFF8A95A1);
  static const textBright = Color(0xFFE8ECEF);
}

// ═══════════════════════════════════════════════════════════════════════════
// الإشعارات
// ═══════════════════════════════════════════════════════════════════════════
final FlutterLocalNotificationsPlugin _notifications =
    FlutterLocalNotificationsPlugin();
bool _notifReady = false;

const _recChannelId = 'dashcam_recording';
const _recChannelName = 'حالة التسجيل';
const _recNotifId = 5001;
const _savedChannelId = 'dashcam_saved';
const _savedChannelName = 'تم الحفظ';

Future<void> setupNotifications() async {
  if (_notifReady) return;
  try {
    const android = AndroidInitializationSettings('app_icon');
    await _notifications.initialize(
      const InitializationSettings(android: android),
    );
  } catch (_) {
    try {
      const android = AndroidInitializationSettings('ic_launcher');
      await _notifications.initialize(
        const InitializationSettings(android: android),
      );
    } catch (_) {
      return;
    }
  }

  final plugin = _notifications.resolvePlatformSpecificImplementation<
      AndroidFlutterLocalNotificationsPlugin>();
  if (plugin != null) {
    try {
      await plugin.createNotificationChannel(
        const AndroidNotificationChannel(
          _recChannelId,
          _recChannelName,
          description: 'إشعار ثابت أثناء تسجيل الفيديو',
          importance: Importance.low,
          playSound: false,
          enableVibration: false,
          showBadge: false,
        ),
      );
    } catch (_) {}
    try {
      await plugin.createNotificationChannel(
        const AndroidNotificationChannel(
          _savedChannelId,
          _savedChannelName,
          description: 'إشعار عند حفظ مقطع جديد',
          importance: Importance.defaultImportance,
          playSound: true,
        ),
      );
    } catch (_) {}
    try {
      await plugin.requestNotificationsPermission();
    } catch (_) {}
  }
  _notifReady = true;
}

Future<void> showRecordingNotification() async {
  await setupNotifications();
  if (!_notifReady) return;
  try {
    await _notifications.show(
      _recNotifId,
      '🔴 التسجيل قيد التشغيل',
      'داش كام يسجل الآن في الخلفية',
      const NotificationDetails(
        android: AndroidNotificationDetails(
          _recChannelId,
          _recChannelName,
          channelDescription: 'إشعار ثابت أثناء تسجيل الفيديو',
          importance: Importance.low,
          priority: Priority.low,
          ongoing: true,
          autoCancel: false,
          playSound: false,
          enableVibration: false,
          icon: 'app_icon',
          category: AndroidNotificationCategory.service,
          visibility: NotificationVisibility.public,
          showWhen: false,
        ),
      ),
    );
  } catch (_) {}
}

Future<void> cancelRecordingNotification() async {
  if (!_notifReady) return;
  try {
    await _notifications.cancel(_recNotifId);
  } catch (_) {}
}

Future<void> showSavedNotification(String fileName) async {
  await setupNotifications();
  if (!_notifReady) return;
  try {
    await _notifications.show(
      DateTime.now().millisecondsSinceEpoch.remainder(100000),
      '✅ تم حفظ المقطع',
      fileName,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          _savedChannelId,
          _savedChannelName,
          channelDescription: 'إشعار عند حفظ مقطع جديد',
          importance: Importance.defaultImportance,
          priority: Priority.defaultPriority,
          icon: 'app_icon',
        ),
      ),
    );
  } catch (_) {}
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await setupNotifications();
  // تسجيل خطوط النظام مرة واحدة — مطلوب لـ FFmpeg drawtext على أندرويد
  try {
    await FFmpegKitConfig.setFontDirectoryList(['/system/fonts'], null);
  } catch (_) {}
  runApp(const DashCamApp());
}

class DashCamApp extends StatelessWidget {
  const DashCamApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'داش كام بدون صوت',
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: DashColors.bg,
        colorScheme: const ColorScheme.dark(
          primary: DashColors.red,
          secondary: DashColors.green,
          surface: DashColors.panel,
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: DashColors.bg,
          foregroundColor: DashColors.textBright,
          elevation: 0,
        ),
      ),
      home: const DashCamHomePage(),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// نموذج التسجيل
// ═══════════════════════════════════════════════════════════════════════════
class RecordingItem {
  const RecordingItem({
    required this.file,
    required this.modified,
    required this.size,
  });
  final File file;
  final DateTime modified;
  final int size;
}

enum ProcessingState { idle, encoding }

/// قراءة سرعة واحدة مع الزمن النسبي منذ بداية التسجيل (بالثواني)
class _SpeedSample {
  const _SpeedSample({required this.atSeconds, required this.kmh});
  final double atSeconds;
  final double kmh;
}

class DashCamHomePage extends StatefulWidget {
  const DashCamHomePage({super.key});

  @override
  State<DashCamHomePage> createState() => _DashCamHomePageState();
}

class _DashCamHomePageState extends State<DashCamHomePage>
    with WidgetsBindingObserver {
  final DateFormat _stampFormat = DateFormat('yyyy-MM-dd  HH:mm:ss');
  final DateFormat _fileFormat = DateFormat('yyyyMMdd_HHmmss');
  final DateFormat _listFormat = DateFormat('yyyy-MM-dd  HH:mm');

  List<CameraDescription> _cameras = const [];
  CameraController? _controller;
  int _cameraIndex = 0;
  bool _initializing = true;
  bool _isRecording = false;
  bool _switchingCamera = false;
  String? _error;
  Timer? _clockTimer;
  Timer? _segmentTimer;
  DateTime _now = DateTime.now();
  double? _speedKmh;
  StreamSubscription<Position>? _positionSub;
  List<RecordingItem> _recordings = const [];
  int _segmentMinutes = 3;
  int _keepCount = 30;

  // معالجة FFmpeg
  ProcessingState _processing = ProcessingState.idle;
  int _queueLength = 0;

  // سجل قراءات السرعة أثناء التسجيل الحالي — يُستخدم لرسم سرعة متحركة
  // فعلية داخل الفيديو بدل قيمة ثابتة واحدة.
  DateTime? _recordingStartedAt;
  final List<_SpeedSample> _speedLog = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _boot();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _clockTimer?.cancel();
    _segmentTimer?.cancel();
    _positionSub?.cancel();
    _controller?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      if (_isRecording) {
        _stopRecording();
      }
    }
  }

  Future<void> _boot() async {
    _clockTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });

    try {
      _cameras = await availableCameras();
      if (_cameras.isEmpty) {
        setState(() {
          _error = 'لم يتم العثور على كاميرا في هذا الجهاز';
          _initializing = false;
        });
        return;
      }
      _cameraIndex = _preferredBackCameraIndex();
      await _initCamera();
      await _startLocation();
      await _loadRecordings();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'تعذر تشغيل الكاميرا: $e';
        _initializing = false;
      });
    }
  }

  int _preferredBackCameraIndex() {
    final index =
        _cameras.indexWhere((c) => c.lensDirection == CameraLensDirection.back);
    return index >= 0 ? index : 0;
  }

  Future<void> _initCamera() async {
    setState(() {
      _initializing = true;
      _error = null;
    });

    final old = _controller;
    _controller = null;
    await old?.dispose();

    final controller = CameraController(
      _cameras[_cameraIndex],
      ResolutionPreset.high,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.yuv420,
    );

    await controller.initialize();
    if (!mounted) {
      await controller.dispose();
      return;
    }

    setState(() {
      _controller = controller;
      _initializing = false;
    });
  }

  Future<Directory> _recordingsDir() async {
    final dir = await getApplicationDocumentsDirectory();
    final folder = Directory('${dir.path}/dashcam_recordings');
    if (!await folder.exists()) await folder.create(recursive: true);
    return folder;
  }

  Future<Directory> _tempDir() async {
    final dir = await getApplicationDocumentsDirectory();
    final folder = Directory('${dir.path}/dashcam_tmp');
    if (!await folder.exists()) await folder.create(recursive: true);
    return folder;
  }

  Future<void> _loadRecordings() async {
    final dir = await _recordingsDir();
    final files = await dir
        .list()
        .where((e) => e is File && e.path.toLowerCase().endsWith('.mp4'))
        .cast<File>()
        .toList();

    final items = <RecordingItem>[];
    for (final file in files) {
      try {
        final stat = await file.stat();
        items.add(RecordingItem(file: file, modified: stat.modified, size: stat.size));
      } catch (_) {}
    }
    items.sort((a, b) => b.modified.compareTo(a.modified));
    if (mounted) setState(() => _recordings = items);
  }

  Future<void> _cleanupOldRecordings() async {
    await _loadRecordings();
    final extra = _recordings.skip(_keepCount).toList();
    for (final item in extra) {
      try {
        if (await item.file.exists()) await item.file.delete();
      } catch (_) {}
    }
    await _loadRecordings();
  }

  Future<void> _startLocation() async {
    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return;
      }
      const settings = LocationSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        distanceFilter: 0,
      );
      _positionSub =
          Geolocator.getPositionStream(locationSettings: settings).listen((pos) {
        final speed = (pos.speed * 3.6).clamp(0, 399).toDouble();
        if (mounted) setState(() => _speedKmh = speed);

        // أثناء التسجيل نسجّل كل قراءة مع زمنها النسبي لبناء سرعة متحركة
        // فعلية داخل الفيديو لاحقاً، بدل قيمة ثابتة واحدة.
        if (_isRecording && _recordingStartedAt != null) {
          final elapsed =
              DateTime.now().difference(_recordingStartedAt!).inMilliseconds /
                  1000.0;
          _speedLog.add(_SpeedSample(atSeconds: elapsed, kmh: speed));
        }
      });
    } catch (_) {}
  }

  Future<void> _startRecording() async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized || _isRecording) {
      return;
    }
    try {
      await controller.startVideoRecording();
      if (!mounted) return;
      _speedLog.clear();
      _recordingStartedAt = DateTime.now();
      setState(() => _isRecording = true);
      await showRecordingNotification();
      _segmentTimer?.cancel();
      _segmentTimer = Timer(Duration(minutes: _segmentMinutes), _restartSegment);
    } catch (e) {
      if (!mounted) return;
      _showSnack('تعذر بدء التسجيل');
    }
  }

  Future<void> _restartSegment() async {
    if (!_isRecording) return;
    await _stopRecording(startAgain: true);
  }

  Future<void> _stopRecording({bool startAgain = false}) async {
    final controller = _controller;
    if (controller == null || !_isRecording) return;
    _segmentTimer?.cancel();
    try {
      final raw = await controller.stopVideoRecording();
      if (mounted) setState(() => _isRecording = false);
      await cancelRecordingNotification();

      // ننسخ سجل السرعة لهذا المقطع قبل أن يُصفَّر عند بدء التسجيل التالي
      final speedSnapshot = List<_SpeedSample>.from(_speedLog);

      // معالجة الفيديو بـ FFmpeg لحرق الستامب — تعمل بالخلفية بدون حجب الواجهة
      unawaited(_processAndSave(File(raw.path), speedSnapshot));

      await _cleanupOldRecordings();
      if (startAgain && mounted) await _startRecording();
    } catch (_) {
      if (mounted) setState(() => _isRecording = false);
      await cancelRecordingNotification();
    }
  }

  /// تجد أول خط متاح فعلياً على الجهاز من قائمة بدائل معروفة.
  /// هذا ضروري لأن DroidSansMono غير موجود على أندرويد الحديث،
  /// واسم الخط المتاح يختلف بين الشركات المصنّعة والإصدارات.
  Future<String> _findAvailableFont() async {
    const candidates = [
      '/system/fonts/RobotoMono-Regular.ttf',
      '/system/fonts/DroidSansMono.ttf',
      '/system/fonts/Roboto-Regular.ttf',
      '/system/fonts/NotoSans-Regular.ttf',
      '/system/fonts/DroidSans.ttf',
    ];
    for (final path in candidates) {
      if (await File(path).exists()) return path;
    }
    // لم يوجد أي خط من القائمة — نترك الأمر لـ fontconfig يختار تلقائياً
    return '';
  }

  /// يبني ملف أوامر sendcmd يُحدّث نص السرعة فعلياً كل ثانية بالقيمة
  /// الحقيقية المُسجَّلة من GPS أثناء التصوير، بدل قيمة ثابتة واحدة.
  /// كل سطر يعيد تهيئة drawtext الثاني (مخصص للسرعة فقط) عند ثانية محددة.
  String _buildSpeedCommandScript(List<_SpeedSample> samples, double durationSeconds) {
    if (samples.isEmpty) {
      return "0.0 [enter] drawtext@speed reinit 'text=GPS --';";
    }

    // نأخذ أقرب قراءة فعلية لكل ثانية كاملة من مدة الفيديو، بدل كل القراءات
    // الخام (قد تكون كثيفة جداً) — هذا يبقي ملف الأوامر صغيراً وسلساً.
    final lines = <String>[];
    final totalSeconds = durationSeconds.ceil().clamp(1, 36000);

    for (var second = 0; second <= totalSeconds; second++) {
      // أقرب عينة لهذه الثانية
      _SpeedSample closest = samples.first;
      double bestDiff = (samples.first.atSeconds - second).abs();
      for (final s in samples) {
        final diff = (s.atSeconds - second).abs();
        if (diff < bestDiff) {
          bestDiff = diff;
          closest = s;
        }
      }
      final speedText = 'GPS ${closest.kmh.round()} km/h';
      lines.add("$second.0 [enter] drawtext@speed reinit 'text=$speedText';");
    }
    return lines.join('\n');
  }

  /// يحرق الستامب (تاريخ/وقت متحرك + سرعة فعلية متحركة) داخل الفيديو
  /// عبر FFmpeg — طبقتان من drawtext: واحدة للتاريخ/الوقت (تتحرك تلقائياً
  /// عبر %{localtime})، وأخرى مخصصة للسرعة تُحدَّث عبر sendcmd بالقيم
  /// الحقيقية المُسجَّلة من GPS في كل ثانية فعلية من زمن القيادة.
  Future<void> _processAndSave(File rawFile, List<_SpeedSample> speedSamples) async {
    setState(() {
      _processing = ProcessingState.encoding;
      _queueLength++;
    });

    File? cmdFile;
    try {
      final dir = await _recordingsDir();
      final name = 'dashcam_${_fileFormat.format(DateTime.now())}.mp4';
      final outputPath = '${dir.path}/$name';

      // مدة الفيديو الفعلية — نحتاجها لمعرفة كم ثانية نولّد لها أوامر سرعة
      double durationSeconds = 0;
      try {
        final probeSession =
            await FFprobeKit.getMediaInformation(rawFile.path);
        final info = await probeSession.getMediaInformation();
        final durationStr = info?.getDuration();
        if (durationStr != null) {
          durationSeconds = double.tryParse(durationStr) ?? 0;
        }
      } catch (_) {}
      if (durationSeconds <= 0) {
        // تقدير احتياطي من مدة الجلسة المُسجَّلة محلياً
        durationSeconds = speedSamples.isEmpty
            ? _segmentMinutes * 60.0
            : speedSamples.last.atSeconds;
      }

      // ملف أوامر السرعة المتحركة
      final tmp = await _tempDir();
      cmdFile = File('${tmp.path}/speedcmd_${DateTime.now().millisecondsSinceEpoch}.txt');
      await cmdFile.writeAsString(
        _buildSpeedCommandScript(speedSamples, durationSeconds),
      );

      final fontPath = await _findAvailableFont();
      final fontPart = fontPath.isEmpty ? '' : 'fontfile=$fontPath:';

      // طبقة 1: التاريخ والوقت — يتحرك تلقائياً عبر localtime مع كل فريم
      // نستخدم فاصلاً (-) بدل (:) داخل صيغة الوقت لتفادي تعارضها مع
      // فاصل معاملات drawtext نفسه — هذه الصيغة مختبرة وتعمل بثبات.
      final dateTimeFilter = "drawtext="
          "$fontPart"
          "text='%{localtime\\:%Y-%m-%d %H-%M-%S}':"
          "fontsize=22:"
          "fontcolor=0xE53935:"
          "borderw=2:"
          "bordercolor=black@0.8:"
          "x=14:"
          "y=h-th-14";

      // طبقة 2: السرعة — نص منفصل بجانب التاريخ، يُحدَّث بـ sendcmd
      final initialSpeed = speedSamples.isEmpty
          ? 'GPS --'
          : 'GPS ${speedSamples.first.kmh.round()} km/h';
      final speedFilter = "drawtext@speed="
          "$fontPart"
          "text='$initialSpeed':"
          "fontsize=22:"
          "fontcolor=0xE53935:"
          "borderw=2:"
          "bordercolor=black@0.8:"
          "x=w-tw-14:"
          "y=h-th-14";

      final sendcmdFilter = "sendcmd=f=${cmdFile.path}";

      // ترتيب السلسلة: التاريخ أولاً، ثم sendcmd يتحكم بطبقة السرعة الثانية
      final filterChain =
          '$dateTimeFilter,$sendcmdFilter,$speedFilter';

      final cmd =
          '-y -i "${rawFile.path}" -vf "$filterChain" -c:v libx264 -preset ultrafast '
          '-crf 23 -pix_fmt yuv420p -an "$outputPath"';

      final session = await FFmpegKit.execute(cmd);
      final returnCode = await session.getReturnCode();

      if (ReturnCode.isSuccess(returnCode)) {
        try {
          await rawFile.delete();
        } catch (_) {}
        await showSavedNotification(name);
      } else {
        // فشلت المعالجة — نحاول مرة أخرى بدون السرعة المتحركة (أبسط فلتر)
        // كحل وسط قبل التنازل الكامل للنسخة الخام.
        final fallbackFilter = "drawtext="
            "$fontPart"
            "text='%{localtime\\:%Y-%m-%d %H-%M-%S}  $initialSpeed':"
            "fontsize=22:fontcolor=0xE53935:borderw=2:bordercolor=black@0.8:"
            "x=14:y=h-th-14";
        final fallbackCmd =
            '-y -i "${rawFile.path}" -vf "$fallbackFilter" -c:v libx264 '
            '-preset ultrafast -crf 23 -pix_fmt yuv420p -an "$outputPath"';
        final fallbackSession = await FFmpegKit.execute(fallbackCmd);
        final fallbackCode = await fallbackSession.getReturnCode();

        if (ReturnCode.isSuccess(fallbackCode)) {
          try {
            await rawFile.delete();
          } catch (_) {}
          await showSavedNotification(name);
        } else {
          // فشل كل شيء — نحفظ النسخة الخام بدل ما نخسر التسجيل بالكامل
          try {
            await rawFile.copy(outputPath);
            await rawFile.delete();
          } catch (_) {}
          await showSavedNotification('$name (بدون ستامب — تحقق من الفيديو)');
        }
      }
    } catch (_) {
      // أي خطأ غير متوقع — نحاول حفظ الخام كحد أدنى
      try {
        final dir = await _recordingsDir();
        final fallbackName =
            'dashcam_${_fileFormat.format(DateTime.now())}_raw.mp4';
        await rawFile.copy('${dir.path}/$fallbackName');
        await rawFile.delete();
      } catch (_) {}
    } finally {
      try {
        if (cmdFile != null && await cmdFile.exists()) await cmdFile.delete();
      } catch (_) {}
      if (mounted) {
        setState(() {
          _queueLength = (_queueLength - 1).clamp(0, 999);
          if (_queueLength == 0) _processing = ProcessingState.idle;
        });
      }
      await _loadRecordings();
    }
  }

  Future<void> _switchCamera() async {
    if (_cameras.length < 2 || _switchingCamera || _isRecording) return;
    setState(() => _switchingCamera = true);
    try {
      _cameraIndex = (_cameraIndex + 1) % _cameras.length;
      await _initCamera();
    } finally {
      if (mounted) setState(() => _switchingCamera = false);
    }
  }

  void _showSnack(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  String _sizeLabel(int bytes) {
    final mb = bytes / (1024 * 1024);
    return '${mb.toStringAsFixed(mb >= 100 ? 0 : 1)} MB';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: DashColors.bg,
      body: SafeArea(
        child: Column(
          children: [
            _buildTopBar(),
            Expanded(child: _buildCameraArea()),
            _buildBottomPanel(),
          ],
        ),
      ),
    );
  }

  // ── الشريط العلوي ──
  Widget _buildTopBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: const BoxDecoration(
        color: DashColors.panel,
        border: Border(bottom: BorderSide(color: DashColors.panelBorder)),
      ),
      child: Row(
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _isRecording ? DashColors.red : DashColors.textDim,
              boxShadow: _isRecording
                  ? [BoxShadow(color: DashColors.red.withValues(alpha: 0.6), blurRadius: 8)]
                  : null,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            _isRecording ? 'جاري التسجيل' : 'جاهز',
            style: TextStyle(
              color: _isRecording ? DashColors.red : DashColors.textDim,
              fontWeight: FontWeight.w800,
              fontSize: 13,
            ),
          ),
          const Spacer(),
          if (_processing == ProcessingState.encoding) ...[
            const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 2, color: DashColors.amber),
            ),
            const SizedBox(width: 6),
            Text(
              'معالجة الستامب${_queueLength > 1 ? ' ($_queueLength)' : ''}',
              style: const TextStyle(color: DashColors.amber, fontSize: 12, fontWeight: FontWeight.w700),
            ),
            const SizedBox(width: 12),
          ],
          IconButton(
            tooltip: 'تبديل الكاميرا',
            onPressed: _switchCamera,
            icon: const Icon(Icons.cameraswitch_rounded, color: DashColors.textBright, size: 22),
          ),
          IconButton(
            tooltip: 'الإعدادات',
            onPressed: _openSettings,
            icon: const Icon(Icons.tune_rounded, color: DashColors.textBright, size: 22),
          ),
        ],
      ),
    );
  }

  // ── منطقة المعاينة الحية ──
  Widget _buildCameraArea() {
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.videocam_off_rounded, color: DashColors.red, size: 48),
              const SizedBox(height: 12),
              Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: DashColors.textBright)),
              const SizedBox(height: 16),
              FilledButton(onPressed: _boot, child: const Text('إعادة المحاولة')),
            ],
          ),
        ),
      );
    }

    if (_initializing || _controller == null || !_controller!.value.isInitialized) {
      return const Center(child: CircularProgressIndicator(color: DashColors.red));
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        ClipRect(
          child: FittedBox(
            fit: BoxFit.cover,
            child: SizedBox(
              width: _controller!.value.previewSize?.height ?? 1,
              height: _controller!.value.previewSize?.width ?? 1,
              child: CameraPreview(_controller!),
            ),
          ),
        ),
        // معاينة الستامب على الشاشة الحية (يطابق ما سيُحرق داخل الفيديو)
        Positioned(
          left: 14,
          bottom: 14,
          child: _LiveStampPreview(
            text:
                '${_stampFormat.format(_now)}  |  ${_speedKmh == null ? "GPS --" : "GPS ${_speedKmh!.round()} km/h"}',
          ),
        ),
        if (_switchingCamera)
          Container(
            color: Colors.black54,
            child: const Center(child: CircularProgressIndicator(color: DashColors.red)),
          ),
      ],
    );
  }

  // ── اللوحة السفلية ──
  Widget _buildBottomPanel() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 18),
      decoration: const BoxDecoration(
        color: DashColors.panel,
        border: Border(top: BorderSide(color: DashColors.panelBorder)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _SmallIconButton(
            icon: Icons.video_library_rounded,
            label: 'المقاطع${_recordings.isNotEmpty ? " (${_recordings.length})" : ""}',
            onTap: _openGallery,
          ),
          GestureDetector(
            onTap: _isRecording ? _stopRecording : _startRecording,
            child: Container(
              width: 76,
              height: 76,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _isRecording ? DashColors.red : Colors.transparent,
                border: Border.all(color: DashColors.red, width: 4),
              ),
              child: Center(
                child: _isRecording
                    ? Container(
                        width: 26,
                        height: 26,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(6),
                        ),
                      )
                    : Container(
                        width: 58,
                        height: 58,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: DashColors.red,
                        ),
                      ),
              ),
            ),
          ),
          _SmallIconButton(
            icon: Icons.info_outline_rounded,
            label: 'حول',
            onTap: _openAbout,
          ),
        ],
      ),
    );
  }

  // ── الإعدادات ──
  void _openSettings() {
    showModalBottomSheet(
      context: context,
      backgroundColor: DashColors.panel,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => StatefulBuilder(
        builder: (context, setSheetState) => Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('الإعدادات',
                  style: TextStyle(color: DashColors.textBright, fontSize: 18, fontWeight: FontWeight.w900)),
              const SizedBox(height: 18),
              Text('مدة كل مقطع: $_segmentMinutes دقيقة',
                  style: const TextStyle(color: DashColors.textBright, fontWeight: FontWeight.w700)),
              Slider(
                value: _segmentMinutes.toDouble(),
                min: 1,
                max: 10,
                divisions: 9,
                activeColor: DashColors.red,
                inactiveColor: DashColors.panelBorder,
                label: '$_segmentMinutes',
                onChanged: (v) {
                  setSheetState(() => _segmentMinutes = v.round());
                  setState(() {});
                },
              ),
              const SizedBox(height: 8),
              Text('عدد المقاطع المحتفظ بها: $_keepCount',
                  style: const TextStyle(color: DashColors.textBright, fontWeight: FontWeight.w700)),
              Slider(
                value: _keepCount.toDouble(),
                min: 5,
                max: 100,
                divisions: 19,
                activeColor: DashColors.red,
                inactiveColor: DashColors.panelBorder,
                label: '$_keepCount',
                onChanged: (v) {
                  setSheetState(() => _keepCount = v.round());
                  setState(() {});
                },
              ),
              const SizedBox(height: 12),
              const Text(
                'الفيديوهات الزائدة عن هذا العدد تُحذف تلقائياً (الأقدم أولاً) للحفاظ على مساحة التخزين.',
                style: TextStyle(color: DashColors.textDim, fontSize: 12),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _openAbout() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: DashColors.panel,
        title: const Text('داش كام بدون صوت', style: TextStyle(color: DashColors.textBright)),
        content: const Text(
          'تسجيل فيديو مستمر بدون صوت، مع طباعة التاريخ والوقت والسرعة فعلياً داخل الفيديو المحفوظ.\n\nالإصدار 1.1.0',
          style: TextStyle(color: DashColors.textDim),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('إغلاق')),
        ],
      ),
    );
  }

  // ── المعرض ──
  Future<void> _openGallery() async {
    await _loadRecordings();
    if (!mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _GalleryPage(
          recordings: _recordings,
          listFormat: _listFormat,
          sizeLabel: _sizeLabel,
          onDelete: (item) async {
            try {
              await item.file.delete();
            } catch (_) {}
            await _loadRecordings();
          },
          onShare: (item) => SharePlus.instance.share(
            ShareParams(files: [XFile(item.file.path)], text: 'مقطع داش كام'),
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// معاينة الستامب الحية فوق الكاميرا — خط أحمر صغير أسفل الشاشة
// ═══════════════════════════════════════════════════════════════════════════
class _LiveStampPreview extends StatelessWidget {
  const _LiveStampPreview({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: DashColors.red,
          fontSize: 12,
          fontWeight: FontWeight.w700,
          fontFamily: 'monospace',
          letterSpacing: 0.2,
          shadows: [Shadow(color: Colors.black, blurRadius: 3)],
        ),
      ),
    );
  }
}

class _SmallIconButton extends StatelessWidget {
  const _SmallIconButton({required this.icon, required this.label, required this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: DashColors.textBright, size: 24),
            const SizedBox(height: 4),
            Text(label, style: const TextStyle(color: DashColors.textDim, fontSize: 11)),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// صفحة المعرض — قائمة المقاطع المحفوظة
// ═══════════════════════════════════════════════════════════════════════════
class _GalleryPage extends StatefulWidget {
  const _GalleryPage({
    required this.recordings,
    required this.listFormat,
    required this.sizeLabel,
    required this.onDelete,
    required this.onShare,
  });

  final List<RecordingItem> recordings;
  final DateFormat listFormat;
  final String Function(int) sizeLabel;
  final Future<void> Function(RecordingItem) onDelete;
  final void Function(RecordingItem) onShare;

  @override
  State<_GalleryPage> createState() => _GalleryPageState();
}

class _GalleryPageState extends State<_GalleryPage> {
  late List<RecordingItem> _items;

  @override
  void initState() {
    super.initState();
    _items = widget.recordings;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: DashColors.bg,
      appBar: AppBar(title: const Text('المقاطع المحفوظة')),
      body: _items.isEmpty
          ? const Center(
              child: Text('لا توجد مقاطع محفوظة بعد', style: TextStyle(color: DashColors.textDim)),
            )
          : ListView.separated(
              padding: const EdgeInsets.all(14),
              itemCount: _items.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (context, i) {
                final item = _items[i];
                return Container(
                  decoration: BoxDecoration(
                    color: DashColors.panel,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: DashColors.panelBorder),
                  ),
                  child: ListTile(
                    leading: const CircleAvatar(
                      backgroundColor: DashColors.bg,
                      child: Icon(Icons.movie_rounded, color: DashColors.red),
                    ),
                    title: Text(
                      widget.listFormat.format(item.modified),
                      style: const TextStyle(color: DashColors.textBright, fontWeight: FontWeight.w700),
                    ),
                    subtitle: Text(
                      widget.sizeLabel(item.size),
                      style: const TextStyle(color: DashColors.textDim),
                    ),
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => _PlayerPage(file: item.file)),
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.share_rounded, color: DashColors.textDim),
                          onPressed: () => widget.onShare(item),
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete_rounded, color: DashColors.red),
                          onPressed: () async {
                            final confirm = await showDialog<bool>(
                              context: context,
                              builder: (_) => AlertDialog(
                                backgroundColor: DashColors.panel,
                                title: const Text('حذف المقطع؟', style: TextStyle(color: DashColors.textBright)),
                                content: const Text('لا يمكن التراجع عن هذا الإجراء.',
                                    style: TextStyle(color: DashColors.textDim)),
                                actions: [
                                  TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('إلغاء')),
                                  TextButton(
                                    onPressed: () => Navigator.pop(context, true),
                                    child: const Text('حذف', style: TextStyle(color: DashColors.red)),
                                  ),
                                ],
                              ),
                            );
                            if (confirm == true) {
                              await widget.onDelete(item);
                              setState(() => _items.removeWhere((e) => e.file.path == item.file.path));
                            }
                          },
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// مشغّل الفيديو
// ═══════════════════════════════════════════════════════════════════════════
class _PlayerPage extends StatefulWidget {
  const _PlayerPage({required this.file});
  final File file;

  @override
  State<_PlayerPage> createState() => _PlayerPageState();
}

class _PlayerPageState extends State<_PlayerPage> {
  late final VideoPlayerController _controller;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.file(widget.file)
      ..initialize().then((_) {
        if (mounted) setState(() => _ready = true);
        _controller.play();
      });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(backgroundColor: Colors.black, foregroundColor: Colors.white),
      body: Center(
        child: _ready
            ? AspectRatio(
                aspectRatio: _controller.value.aspectRatio,
                child: VideoPlayer(_controller),
              )
            : const CircularProgressIndicator(color: DashColors.red),
      ),
      floatingActionButton: _ready
          ? FloatingActionButton(
              backgroundColor: DashColors.red,
              onPressed: () => setState(() {
                _controller.value.isPlaying ? _controller.pause() : _controller.play();
              }),
              child: Icon(_controller.value.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded),
            )
          : null,
    );
  }
}
