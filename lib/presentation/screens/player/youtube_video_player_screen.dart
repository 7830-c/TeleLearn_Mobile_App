import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:open_filex/open_filex.dart';
import 'package:provider/provider.dart';
import 'package:video_player/video_player.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/duration_formatter.dart';
import '../../../core/utils/toast_utils.dart';
import '../../../data/models/course_model.dart';
import '../../../data/services/local_streaming_server.dart';
import '../../../providers/course_provider.dart';
import '../../../providers/progress_provider.dart';
import '../../../providers/bookmark_provider.dart';
import '../../../providers/download_provider.dart';
import '../../../providers/auth_provider.dart';
import '../downloads/offline_note_viewer_screen.dart';
import '../course/course_explorer_screen.dart';

class YouTubeVideoPlayerScreen extends StatefulWidget {
  final String courseId;
  final int lessonId;
  final bool autoPlay;
  final bool fromDashboard;

  const YouTubeVideoPlayerScreen({
    super.key,
    required this.courseId,
    required this.lessonId,
    this.autoPlay = true,
    this.fromDashboard = false,
  });

  @override
  State<YouTubeVideoPlayerScreen> createState() => _YouTubeVideoPlayerScreenState();
}

class _YouTubeVideoPlayerScreenState extends State<YouTubeVideoPlayerScreen>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  late String _currentCourseId;
  late int _currentLessonId;
  bool _isUserInitiatedSwitch = false;
  bool _isInitialStandby = false;
  bool _hasMarkedCompleted = false;

  VideoPlayerController? _controller;

  // Independent Lag-Free ValueNotifiers (Zero-Rebuild UI Architecture)
  final ValueNotifier<bool> _showControlsNotifier = ValueNotifier<bool>(true);
  final ValueNotifier<bool> _bufferingNotifier = ValueNotifier<bool>(false);
  final ValueNotifier<double> _dragPositionNotifier = ValueNotifier<double>(-1.0); // <0 = not dragging
  final ValueNotifier<bool> _leftSeekRippleNotifier = ValueNotifier<bool>(false);
  final ValueNotifier<bool> _rightSeekRippleNotifier = ValueNotifier<bool>(false);
  final ValueNotifier<bool> _speedBoostNotifier = ValueNotifier<bool>(false);
  final ValueNotifier<bool> _isPlayingNotifier = ValueNotifier<bool>(false);

  // Controls Visibility & Buffering State via ValueNotifiers
  bool get _showControls => _showControlsNotifier.value;
  set _showControls(bool val) => _showControlsNotifier.value = val;

  bool get _isBuffering => _bufferingNotifier.value;
  set _isBuffering(bool val) => _bufferingNotifier.value = val;

  bool get _isDraggingScrubber => _dragPositionNotifier.value >= 0;

  String? _errorMessage;

  Timer? _controlsTimer;
  Timer? _progressSaveTimer;
  double _playbackSpeed = 1.0;
  Timer? _hudDismissTimer;
  bool _isSeeking = false;

  // Pinch-to-Zoom Controller
  final TransformationController _zoomController = TransformationController();
  bool _isZoomed = false;

  // Screen Lock & Settings
  bool _isScreenLocked = false;
  bool _isFullscreen = false;
  final bool _isLooping = false;
  int _playerInitSession = 0; // Generation token for instant switching cancellation

  // Content Tabs
  int _activeDrawerTab = 0; // 0 = Course Playlist, 1 = Lesson Notes
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _currentCourseId = widget.courseId;
    _currentLessonId = widget.lessonId;
    _isInitialStandby = !widget.autoPlay;
    if (widget.autoPlay) {
      _initializePlayer(autoPlay: true);
    } else {
      _bufferingNotifier.value = false;
      _showControlsNotifier.value = true;
    }
  }

  void _startPlaybackFromStandby() {
    setState(() {
      _isInitialStandby = false;
    });
    _initializePlayer(autoPlay: true);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_controller != null && _controller!.value.isInitialized) {
      _precacheCurrentThumbnail();
    }
  }

  void _precacheCurrentThumbnail() {
    try {
      final course = context.read<CourseProvider>().getCourse(_currentCourseId);
      if (course != null) {
        for (final m in course.modules) {
          for (final l in m.lessons) {
            if (l.id == _currentLessonId && l.thumbnailUrl != null && l.thumbnailUrl!.isNotEmpty) {
              precacheImage(NetworkImage(l.thumbnailUrl!), context);
              return;
            }
          }
        }
      }
    } catch (_) {}
  }

  bool _isAppBackgrounded = false;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
      _isAppBackgrounded = true;
      _saveCurrentProgress();
      _controller?.pause();
    } else if (state == AppLifecycleState.resumed) {
      _isAppBackgrounded = false;
    }
  }

  @override
  void deactivate() {
    _saveCurrentProgress();
    _controller?.pause();
    LocalStreamingServer.abortPreviousStreams();
    super.deactivate();
  }

  @override
  void dispose() {
    _playerInitSession++;
    LocalStreamingServer.abortPreviousStreams();
    WidgetsBinding.instance.removeObserver(this);
    _controlsTimer?.cancel();
    _progressSaveTimer?.cancel();
    _hudDismissTimer?.cancel();
    _saveCurrentProgress();
    _controller?.pause();
    _controller?.removeListener(_onPlayerStateChanged);
    _controller?.dispose();
    _zoomController.dispose();
    _scrollController.dispose();
    _showControlsNotifier.dispose();
    _bufferingNotifier.dispose();
    _dragPositionNotifier.dispose();
    _leftSeekRippleNotifier.dispose();
    _rightSeekRippleNotifier.dispose();
    _speedBoostNotifier.dispose();
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
    super.dispose();
  }

  void _resetControlsTimer() {
    _controlsTimer?.cancel();
    if (!_isScreenLocked && (_controller?.value.isPlaying ?? false) && !_isDraggingScrubber) {
      _controlsTimer = Timer(const Duration(seconds: 4), () {
        if (mounted && !_isDraggingScrubber) {
          _showControlsNotifier.value = false;
        }
      });
    }
  }

  Future<void> _initializePlayer({bool autoPlay = true}) async {
    final sessionId = ++_playerInitSession;
    LocalStreamingServer.abortPreviousStreams();

    // Instantly halt and detach old controller/stream
    _controller?.pause();
    _controller?.removeListener(_onPlayerStateChanged);
    _progressSaveTimer?.cancel();
    final oldController = _controller;
    _controller = null;
    oldController?.dispose();

    setState(() {
      _isBuffering = true;
      _errorMessage = null;
      _lastRecordedPositionSec = 0;
    });

    final courseProvider = context.read<CourseProvider>();
    final progressProvider = context.read<ProgressProvider>();
    final downloadProvider = context.read<DownloadProvider>();
    final authProvider = context.read<AuthProvider>();

    final course = courseProvider.getCourse(_currentCourseId);
    if (course == null) {
      if (sessionId == _playerInitSession && mounted) {
        setState(() => _errorMessage = 'Course not found');
      }
      return;
    }

    CourseLesson? lesson;
    for (final mod in course.modules) {
      for (final l in mod.lessons) {
        if (l.id == _currentLessonId) {
          lesson = l;
          break;
        }
      }
      if (lesson != null) break;
    }

    String rawVideoUrl = lesson?.videoUrl ??
        'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/BigBuckBunny.mp4';
    if (rawVideoUrl.contains('/courses/stream/') && !rawVideoUrl.contains('quality=')) {
      rawVideoUrl += rawVideoUrl.contains('?') ? '&quality=high' : '?quality=high';
    }

    final downloadRecord = downloadProvider.getDownloadRecord(_currentCourseId, _currentLessonId, 'video');

    VideoPlayerController? newController;
    try {
      final cachedProgress = progressProvider.getCachedCourseProgress(_currentCourseId);
      if (cachedProgress.isEmpty) {
        await progressProvider.loadCourseProgress(_currentCourseId, userPhone: authProvider.phoneNumber);
      } else {
        unawaited(progressProvider.loadCourseProgress(_currentCourseId, userPhone: authProvider.phoneNumber));
      }

      if (sessionId != _playerInitSession || !mounted) return;

      if (downloadRecord != null && File(downloadRecord.localPath).existsSync()) {
        newController = VideoPlayerController.file(
          File(downloadRecord.localPath),
          videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
        );
      } else {
        final streamingServer = LocalStreamingServer.instance;
        final streamUrl = streamingServer.isRunning
            ? streamingServer.getProxiedStreamUrl(rawVideoUrl)
            : rawVideoUrl;

        newController = VideoPlayerController.networkUrl(
          Uri.parse(streamUrl),
          videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
          httpHeaders: const {
            'User-Agent': 'Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/128.0.0.0 Mobile Safari/537.36',
            'Accept': '*/*',
            'Accept-Encoding': 'identity',
            'Connection': 'keep-alive',
          },
        );
      }

      await newController.initialize();

      // Check if session changed while initializing (user switched to another video or left screen)
      if (sessionId != _playerInitSession || !mounted) {
        await newController.pause();
        newController.dispose();
        return;
      }

      _controller = newController;

      // Only seek if user has real saved progress (> 2 seconds), avoiding redundant network seeks on startup
      final savedSec = progressProvider.getLessonProgressSeconds(
        _currentCourseId,
        _currentLessonId,
      );

      if (savedSec > 2 && savedSec < (newController.value.duration.inSeconds - 3)) {
        await newController.seekTo(Duration(seconds: savedSec));
      }

      if (_isAppBackgrounded || sessionId != _playerInitSession || !mounted) {
        await newController.pause();
        newController.dispose();
        if (_controller == newController) _controller = null;
        return;
      }

      final bool shouldPlay = !_isAppBackgrounded && (autoPlay || widget.autoPlay || _isUserInitiatedSwitch);
      await Future.wait([
        newController.setPlaybackSpeed(_playbackSpeed),
        newController.setLooping(_isLooping),
        if (shouldPlay) newController.play() else newController.pause(),
      ]);

      if (_isAppBackgrounded || sessionId != _playerInitSession || !mounted) {
        await newController.pause();
        newController.dispose();
        if (_controller == newController) _controller = null;
        return;
      }

      newController.addListener(_onPlayerStateChanged);
      _isPlayingNotifier.value = shouldPlay;

      setState(() {
        _isBuffering = false;
        _isSeeking = false;
        _isInitialStandby = false;
        if (!shouldPlay) {
          _showControls = true;
        }
      });

      _precacheCurrentThumbnail();
      _startProgressSaveTimer();
      if (shouldPlay) {
        _resetControlsTimer();
      }
    } catch (e) {
      if (newController != null) {
        try {
          newController.pause();
          newController.dispose();
        } catch (_) {}
        if (_controller == newController) _controller = null;
      }
      debugPrint('[YouTubePlayer] Initialization error: $e');
      if (sessionId == _playerInitSession && mounted) {
        setState(() {
          _isBuffering = false;
          _isSeeking = false;
          _errorMessage = 'Failed to load video stream. Tap to retry.';
        });
      }
    }
  }

  void _onPlayerStateChanged() {
    if (!mounted || _controller == null) return;

    final val = _controller!.value;
    if (_isSeeking && (!val.isBuffering || val.isPlaying)) {
      _isSeeking = false;
    }
    if (val.isPlaying != _isPlayingNotifier.value) {
      _isPlayingNotifier.value = val.isPlaying;
    }
    if (val.isBuffering != _bufferingNotifier.value) {
      if (val.isPlaying && !_bufferingNotifier.value) {
        // Video is actively playing smoothly, ignore transient background buffer top-up
      } else {
        _bufferingNotifier.value = val.isBuffering;
      }
    }

    // Auto-save and mark completed ONCE if reached 90%
    if (!_hasMarkedCompleted && val.position.inSeconds > 0 && val.duration.inSeconds > 0) {
      if (val.position.inSeconds >= (val.duration.inSeconds * 0.90)) {
        _hasMarkedCompleted = true;
        final progressProvider = context.read<ProgressProvider>();
        if (!progressProvider.isLessonCompleted(_currentCourseId, _currentLessonId)) {
          progressProvider.saveProgress(
            courseId: _currentCourseId,
            lessonId: _currentLessonId,
            progressSeconds: val.position.inSeconds,
            durationSeconds: val.duration.inSeconds,
            isCompleted: true,
          );
        }
      }
    }
  }

  void _startProgressSaveTimer() {
    _progressSaveTimer?.cancel();
    _progressSaveTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      _saveCurrentProgress();
    });
  }

  int _lastRecordedPositionSec = 0;

  void _saveCurrentProgress() {
    if (_controller == null || !_controller!.value.isInitialized) return;
    final pos = _controller!.value.position.inSeconds;
    final dur = _controller!.value.duration.inSeconds;
    if (dur > 0) {
      int delta = 0;
      if (pos > _lastRecordedPositionSec) {
        delta = pos - _lastRecordedPositionSec;
        if (delta > 30) delta = 5; // Graceful bound for seeking
      }
      _lastRecordedPositionSec = pos;
      final authPhone = context.read<AuthProvider>().phoneNumber;
      context.read<ProgressProvider>().saveProgressQuiet(
        courseId: _currentCourseId,
        lessonId: _currentLessonId,
        progressSeconds: pos,
        durationSeconds: dur,
        deltaSeconds: delta,
        userPhone: authPhone,
      );
    }
  }

  void _togglePlayPause() {
    if (_isInitialStandby) {
      _startPlaybackFromStandby();
      return;
    }
    if (_controller == null || !_controller!.value.isInitialized) return;
    if (_controller!.value.isPlaying) {
      _controller!.pause();
      _isPlayingNotifier.value = false;
      _controlsTimer?.cancel();
    } else {
      _controller!.play();
      _isPlayingNotifier.value = true;
      _resetControlsTimer();
    }
  }

  void _onDoubleTapLeft() {
    if (_isScreenLocked || _controller == null || !_controller!.value.isInitialized) return;
    _isSeeking = true;
    _bufferingNotifier.value = true;
    final newPos = _controller!.value.position - const Duration(seconds: 10);
    _controller!.seekTo(newPos < Duration.zero ? Duration.zero : newPos).then((_) {
      if (mounted) {
        _controller?.play();
        _isSeeking = false;
      }
    });
    _triggerSeekFeedback(isForward: false);
  }

  void _onDoubleTapRight() {
    if (_isScreenLocked || _controller == null || !_controller!.value.isInitialized) return;
    _isSeeking = true;
    _bufferingNotifier.value = true;
    final maxDur = _controller!.value.duration;
    final newPos = _controller!.value.position + const Duration(seconds: 10);
    _controller!.seekTo(newPos > maxDur ? maxDur : newPos).then((_) {
      if (mounted) {
        _controller?.play();
        _isSeeking = false;
      }
    });
    _triggerSeekFeedback(isForward: true);
  }

  void _triggerSeekFeedback({required bool isForward}) {
    HapticFeedback.lightImpact();
    if (isForward) {
      _rightSeekRippleNotifier.value = true;
    } else {
      _leftSeekRippleNotifier.value = true;
    }

    _hudDismissTimer?.cancel();
    _hudDismissTimer = Timer(const Duration(milliseconds: 700), () {
      if (mounted) {
        _leftSeekRippleNotifier.value = false;
        _rightSeekRippleNotifier.value = false;
      }
    });
  }

  void _onLongPressStart(LongPressStartDetails details) {
    if (_controller == null || !_controller!.value.isInitialized) return;
    HapticFeedback.mediumImpact();
    _speedBoostNotifier.value = true;
    _controller!.setPlaybackSpeed(2.0);
  }

  void _onLongPressEnd(LongPressEndDetails details) {
    if (_controller == null || !_controller!.value.isInitialized) return;
    _speedBoostNotifier.value = false;
    _controller!.setPlaybackSpeed(_playbackSpeed);
  }

  bool _isLandscapeLeft = true;

  void _flipLandscapeOrientation() {
    _isLandscapeLeft = !_isLandscapeLeft;
    SystemChrome.setPreferredOrientations([
      _isLandscapeLeft ? DeviceOrientation.landscapeLeft : DeviceOrientation.landscapeRight,
    ]);
  }

  void _toggleFullscreen() {
    setState(() {
      _isFullscreen = !_isFullscreen;
    });

    if (_isFullscreen) {
      SystemChrome.setPreferredOrientations([
        _isLandscapeLeft ? DeviceOrientation.landscapeLeft : DeviceOrientation.landscapeRight,
      ]);
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    } else {
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.portraitUp,
      ]);
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    }
    _resetControlsTimer();
  }

  void _setPlaybackSpeed(double speed) {
    setState(() => _playbackSpeed = speed);
    _controller?.setPlaybackSpeed(speed);
  }

  void _showSpeedSelectionModal() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    const allSpeeds = [0.25, 0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0, 2.25, 2.5, 2.75, 3.0];

    showModalBottomSheet(
      context: context,
      backgroundColor: isDark ? const Color(0xFF131D31) : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Drag Handle
              Center(
                child: Container(
                  margin: const EdgeInsets.only(top: 10, bottom: 6),
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: isDark ? Colors.white24 : Colors.black12,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 6, 20, 12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Playback Speed',
                      style: GoogleFonts.inter(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: isDark ? Colors.white : const Color(0xFF0F172A),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.bolt_rounded, size: 14, color: AppColors.primary),
                          const SizedBox(width: 3),
                          Text(
                            '${_playbackSpeed == 1.0 ? '1' : _playbackSpeed}x Active',
                            style: GoogleFonts.inter(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: AppColors.primary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              // All Speeds Horizontal Scrollable Chips (0.25x - 3.0x)
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: allSpeeds.map((spd) {
                    final isSel = (_playbackSpeed == spd);
                    String chipLabel = '${spd == 1.0 ? '1.0' : spd}x';
                    if (spd == 1.0) chipLabel = '1.0x (Normal)';
                    return Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text(chipLabel),
                        selected: isSel,
                        onSelected: (selected) {
                          if (selected) {
                            _setPlaybackSpeed(spd);
                            Navigator.pop(ctx);
                          }
                        },
                        selectedColor: AppColors.primary,
                        labelStyle: TextStyle(
                          color: isSel ? Colors.white : (isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B)),
                          fontWeight: isSel ? FontWeight.w800 : FontWeight.w600,
                          fontSize: 12,
                        ),
                        backgroundColor: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                          side: BorderSide(
                            color: isSel
                                ? AppColors.primary
                                : (isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0)),
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _toggleInitialLoadingPause() {
    if (_isInitialStandby) {
      _startPlaybackFromStandby();
    } else {
      _playerInitSession++;
      LocalStreamingServer.abortPreviousStreams();
      _controller?.pause();
      setState(() {
        _isInitialStandby = true;
        _isBuffering = false;
      });
    }
  }

  void _exitPlayerScreen([CourseModule? currentModule]) {
    _saveCurrentProgress();
    final c = _controller;
    _controller = null;
    c?.pause();
    c?.removeListener(_onPlayerStateChanged);
    c?.dispose();
    LocalStreamingServer.abortPreviousStreams();

    if (widget.fromDashboard) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => CourseExplorerScreen(
            courseId: _currentCourseId,
            initialModuleId: currentModule?.id,
          ),
        ),
      );
    } else {
      Navigator.of(context).pop();
    }
  }

  void _switchLesson(int newLessonId) {
    if (newLessonId == _currentLessonId) return;
    _saveCurrentProgress();
    _playerInitSession++;
    _hasMarkedCompleted = false;
    LocalStreamingServer.abortPreviousStreams();
    _controller?.pause();
    _controller?.removeListener(_onPlayerStateChanged);
    _progressSaveTimer?.cancel();
    setState(() {
      _currentLessonId = newLessonId;
      _lastRecordedPositionSec = 0;
      _isUserInitiatedSwitch = true;
      _isInitialStandby = false;
    });
    _initializePlayer(autoPlay: true);
  }

  Future<void> _handleNoteAction(CourseModel course, CourseNote note) async {
    final authPhone = context.read<AuthProvider>().phoneNumber;
    final downloadProvider = context.read<DownloadProvider>();
    final isDl = downloadProvider.isDownloaded(course.id, note.id, 'note');

    if (isDl) {
      final rec = downloadProvider.getDownloadRecord(course.id, note.id, 'note');
      if (rec != null) {
        final file = File(rec.localPath);
        if (file.existsSync()) {
          try {
            final res = await OpenFilex.open(rec.localPath, type: 'application/pdf');
            if (res.type == ResultType.done) return;
          } catch (_) {}
        }
        if (mounted) {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => OfflineNoteViewerScreen(download: rec),
            ),
          );
        }
        return;
      }
    }

    downloadProvider.startDownloadNote(
      course: course,
      note: note,
      userPhone: authPhone,
    );
    ToastUtils.showSnackBar(
      context,
      'Downloading "${note.displayName}"...',
      isSuccess: true,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final course = context.read<CourseProvider>().getCourse(_currentCourseId);
    final progressProvider = context.read<ProgressProvider>();
    final bookmarkProvider = context.read<BookmarkProvider>();
    final authProvider = context.read<AuthProvider>();

    if (course == null) {
      return const Scaffold(body: Center(child: Text('Course not found')));
    }

    CourseLesson? currentLesson;
    CourseModule? currentModule;
    for (final mod in course.modules) {
      for (final les in mod.lessons) {
        if (les.id == _currentLessonId) {
          currentLesson = les;
          currentModule = mod;
          break;
        }
      }
      if (currentLesson != null) break;
    }

    if (currentLesson == null && course.modules.isNotEmpty) {
      for (final mod in course.modules) {
        if (mod.lessons.isNotEmpty) {
          currentLesson = mod.lessons.first;
          currentModule = mod;
          break;
        }
      }
    }
    final isBookmarked = bookmarkProvider.isBookmarked(_currentLessonId);
    final isCompleted = progressProvider.isLessonCompleted(_currentCourseId, _currentLessonId);

    // Calculate Aspect Ratio Widget with Pinch-to-Zoom
    Widget videoWidget;
    final bool isReady = _controller != null && _controller!.value.isInitialized;

    if (isReady) {
      videoWidget = Stack(
        fit: StackFit.expand,
        children: [
          Center(
            child: RepaintBoundary(
              child: AspectRatio(
                aspectRatio: (_controller!.value.aspectRatio > 0)
                    ? _controller!.value.aspectRatio
                    : (16 / 9),
                child: VideoPlayer(_controller!),
              ),
            ),
          ),
          if (!_controller!.value.isPlaying && !_isBuffering && !_showControls)
            Center(
              child: Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.black.withValues(alpha: 0.55),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.3)),
                ),
                child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 36),
              ),
            ),
        ],
      );
    } else {
      videoWidget = Stack(
        fit: StackFit.expand,
        children: [
          Container(
            color: Colors.black,
          ),
          Center(
            child: _errorMessage != null
                ? Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.error_outline_rounded, color: Colors.redAccent, size: 36),
                      const SizedBox(height: 8),
                      Text(
                        _errorMessage!,
                        style: const TextStyle(color: Colors.white, fontSize: 12),
                      ),
                      const SizedBox(height: 10),
                      ElevatedButton(
                        onPressed: () => _initializePlayer(autoPlay: true),
                        child: const Text('Retry'),
                      ),
                    ],
                  )
                : (_isInitialStandby
                    ? Material(
                        color: Colors.transparent,
                        shape: const CircleBorder(),
                        child: InkWell(
                          customBorder: const CircleBorder(),
                          onTap: _startPlaybackFromStandby,
                          child: Container(
                            width: 64,
                            height: 64,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: AppColors.primary.withValues(alpha: 0.92),
                              boxShadow: [
                                BoxShadow(
                                  color: AppColors.primary.withValues(alpha: 0.5),
                                  blurRadius: 20,
                                  spreadRadius: 3,
                                ),
                              ],
                            ),
                            child: const Center(
                              child: Icon(
                                Icons.play_arrow_rounded,
                                color: Colors.white,
                                size: 38,
                              ),
                            ),
                          ),
                        ),
                      )
                    : Material(
                        color: Colors.transparent,
                        shape: const CircleBorder(),
                        child: InkWell(
                          customBorder: const CircleBorder(),
                          onTap: _toggleInitialLoadingPause,
                          child: Container(
                            width: 60,
                            height: 60,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.black.withValues(alpha: 0.65),
                              border: Border.all(color: Colors.white.withValues(alpha: 0.25)),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.4),
                                  blurRadius: 16,
                                ),
                              ],
                            ),
                            child: const Stack(
                              alignment: Alignment.center,
                              children: [
                                SizedBox(
                                  width: 44,
                                  height: 44,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 3,
                                    valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF2563EB)),
                                  ),
                                ),
                                Icon(
                                  Icons.pause_rounded,
                                  color: Colors.white,
                                  size: 22,
                                ),
                              ],
                            ),
                          ),
                        ),
                      )),
          ),
        ],
      );
    }

    final isFullscreen = _isFullscreen;
    final totalDurationMs = (_controller?.value.duration.inMilliseconds.toDouble() ?? 1.0);

    // Sub-Module Progress calculations
    final moduleLessons = currentModule?.lessons ?? [];
    final totalModuleLessonsCount = moduleLessons.length;
    final completedModuleLessonsCount = moduleLessons.where((l) => progressProvider.isLessonCompleted(_currentCourseId, l.id)).length;
    final moduleCompletionPct = totalModuleLessonsCount > 0
        ? ((completedModuleLessonsCount / totalModuleLessonsCount) * 100).toInt()
        : 0;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        if (isFullscreen) {
          _toggleFullscreen();
          return;
        }
        _exitPlayerScreen(currentModule);
      },
      child: Scaffold(
        backgroundColor: isDark ? AppColors.darkBg : AppColors.lightBg,
        body: SafeArea(
          top: !isFullscreen,
          bottom: !isFullscreen,
          child: Column(
            children: [
              // ── MODERN CURVED VIDEO PLAYER BOX ──────────────────────────────────────
              Padding(
                padding: isFullscreen
                    ? EdgeInsets.zero
                    : const EdgeInsets.fromLTRB(10, 4, 10, 8),
                child: Container(
                  height: isFullscreen
                      ? MediaQuery.of(context).size.height
                      : 230,
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: Colors.black,
                    borderRadius: BorderRadius.circular(isFullscreen ? 0 : 12),
                    boxShadow: isFullscreen
                        ? null
                        : [
                            BoxShadow(
                              color: isDark
                                  ? Colors.black.withValues(alpha: 0.5)
                                  : const Color(0xFF0F172A).withValues(alpha: 0.18),
                              blurRadius: 14,
                              offset: const Offset(0, 6),
                            ),
                          ],
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () {
                      if (_isInitialStandby) {
                        _startPlaybackFromStandby();
                        return;
                      }
                      _showControlsNotifier.value = !_showControlsNotifier.value;
                      if (_showControlsNotifier.value && !_isScreenLocked) {
                        _resetControlsTimer();
                      }
                    },
                    onDoubleTapDown: (details) {
                      if (_isScreenLocked) return;
                      final screenWidth = MediaQuery.of(context).size.width;
                      if (details.localPosition.dx < screenWidth / 2) {
                        _onDoubleTapLeft();
                      } else {
                        _onDoubleTapRight();
                      }
                    },
                    onLongPressStart: (details) {
                      if (_isScreenLocked) return;
                      _onLongPressStart(details);
                    },
                    onLongPressEnd: (details) {
                      if (_isScreenLocked) return;
                      _onLongPressEnd(details);
                    },
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        videoWidget,

                        // Reset Zoom Floating Badge
                        if (_isZoomed)
                          Positioned(
                            top: 14,
                            left: 14,
                            child: GestureDetector(
                              onTap: () {
                                _zoomController.value = Matrix4.identity();
                                setState(() => _isZoomed = false);
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                decoration: BoxDecoration(
                                  color: Colors.black.withValues(alpha: 0.75),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: Colors.white.withValues(alpha: 0.25)),
                                ),
                                child: const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.zoom_out_map_rounded, color: Colors.white, size: 14),
                                    SizedBox(width: 4),
                                    Text('Reset Zoom', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700)),
                                  ],
                                ),
                              ),
                            ),
                          ),

                        // Left 10s Double Tap Ripple Feedback
                        ValueListenableBuilder<bool>(
                          valueListenable: _leftSeekRippleNotifier,
                          builder: (context, showLeftRipple, _) {
                            if (!showLeftRipple) return const SizedBox.shrink();
                            return Positioned(
                              left: 0,
                              top: 0,
                              bottom: 0,
                              width: 140,
                              child: Container(
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.15),
                                  borderRadius: const BorderRadius.horizontal(right: Radius.circular(120)),
                                ),
                                child: const Center(
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.fast_rewind_rounded, color: Colors.white, size: 36),
                                      SizedBox(height: 4),
                                      Text('-10s', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          },
                        ),

                        // Right 10s Double Tap Ripple Feedback
                        ValueListenableBuilder<bool>(
                          valueListenable: _rightSeekRippleNotifier,
                          builder: (context, showRightRipple, _) {
                            if (!showRightRipple) return const SizedBox.shrink();
                            return Positioned(
                              right: 0,
                              top: 0,
                              bottom: 0,
                              width: 140,
                              child: Container(
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.15),
                                  borderRadius: const BorderRadius.horizontal(left: Radius.circular(120)),
                                ),
                                child: const Center(
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.fast_forward_rounded, color: Colors.white, size: 36),
                                      SizedBox(height: 4),
                                      Text('+10s', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          },
                        ),

                        // 2X Speed Boost Top Banner
                        ValueListenableBuilder<bool>(
                          valueListenable: _speedBoostNotifier,
                          builder: (context, isSpeedBoost, _) {
                            if (!isSpeedBoost) return const SizedBox.shrink();
                            return Positioned(
                              top: 16,
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                                decoration: BoxDecoration(
                                  color: Colors.black.withValues(alpha: 0.8),
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(color: Colors.white.withValues(alpha: 0.3)),
                                ),
                                child: const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.bolt_rounded, color: Color(0xFFFBBF24), size: 16),
                                    SizedBox(width: 4),
                                    Text(
                                      '2X SPEED',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w800,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),

                        // Buffering Spinner (only when actively buffering)
                        ValueListenableBuilder<bool>(
                          valueListenable: _bufferingNotifier,
                          builder: (context, isBuffering, _) {
                            if (!isBuffering || !(_controller?.value.isInitialized ?? false)) {
                              return const SizedBox.shrink();
                            }
                            return Container(
                              width: 44,
                              height: 44,
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.5),
                                shape: BoxShape.circle,
                              ),
                              padding: const EdgeInsets.all(8),
                              child: const CircularProgressIndicator(
                                strokeWidth: 3,
                                valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF2563EB)),
                              ),
                            );
                          },
                        ),

                        // ── MODERN CONTROLS OVERLAY (Isolated Zero-Rebuild Architecture) ──
                        ValueListenableBuilder<bool>(
                          valueListenable: _showControlsNotifier,
                          builder: (context, showControls, _) {
                            if (!showControls || (!(_controller?.value.isInitialized ?? false) && !_isInitialStandby)) {
                              return const SizedBox.shrink();
                            }
                            return Stack(
                              fit: StackFit.expand,
                              children: [
                                // Dark gradient background layer (tap to dismiss controls instantly)
                                GestureDetector(
                                  behavior: HitTestBehavior.opaque,
                                  onTap: () {
                                    _showControlsNotifier.value = false;
                                  },
                                  child: Container(
                                    decoration: const BoxDecoration(
                                      gradient: LinearGradient(
                                        colors: [Colors.black87, Colors.transparent, Colors.black87],
                                        begin: Alignment.topCenter,
                                        end: Alignment.bottomCenter,
                                      ),
                                    ),
                                  ),
                                ),

                          // Top Bar
                          Positioned(
                            top: 0,
                            left: 0,
                            right: 0,
                            child: SafeArea(
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                child: Row(
                                  children: [
                                    IconButton(
                                      icon: const Icon(Icons.keyboard_arrow_down, color: Colors.white, size: 28),
                                      onPressed: () {
                                        if (isFullscreen) {
                                          _toggleFullscreen();
                                        } else {
                                          _exitPlayerScreen(currentModule);
                                        }
                                      },
                                    ),
                                    const SizedBox(width: 4),
                                    Expanded(
                                      child: Text(
                                        currentLesson?.title ?? 'Video Player',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: GoogleFonts.inter(
                                          color: Colors.white,
                                          fontWeight: FontWeight.w700,
                                          fontSize: 13,
                                        ),
                                      ),
                                    ),
                                    if (isFullscreen)
                                      IconButton(
                                        icon: const Icon(Icons.screen_rotation_rounded, color: Colors.white, size: 20),
                                        tooltip: 'Flip Landscape Direction',
                                        onPressed: _flipLandscapeOrientation,
                                      ),
                                    IconButton(
                                      icon: Icon(
                                        _isScreenLocked ? Icons.lock_rounded : Icons.lock_open_rounded,
                                        color: _isScreenLocked ? AppColors.accentAmber : Colors.white,
                                        size: 20,
                                      ),
                                      onPressed: () {
                                        setState(() => _isScreenLocked = !_isScreenLocked);
                                        _resetControlsTimer();
                                      },
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),

                          // Center Quick Controls (Replay 10, Glowing Blue Play/Pause, Forward 10)
                          if (!_isScreenLocked && !_isInitialStandby)
                            Center(
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  // Replay 10s Button
                                  Container(
                                    width: 44,
                                    height: 44,
                                    decoration: BoxDecoration(
                                      color: Colors.black.withValues(alpha: 0.45),
                                      shape: BoxShape.circle,
                                      border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
                                    ),
                                    child: IconButton(
                                      padding: EdgeInsets.zero,
                                      icon: const Icon(Icons.replay_10_rounded, color: Colors.white, size: 24),
                                      onPressed: _onDoubleTapLeft,
                                    ),
                                  ),
                                  const SizedBox(width: 24),

                                  // Glowing Large Play / Pause
                                  Container(
                                    width: 64,
                                    height: 64,
                                    decoration: BoxDecoration(
                                      gradient: const LinearGradient(
                                        colors: [Color(0xFF3B82F6), Color(0xFF1D4ED8)],
                                        begin: Alignment.topLeft,
                                        end: Alignment.bottomRight,
                                      ),
                                      shape: BoxShape.circle,
                                      boxShadow: [
                                        BoxShadow(
                                          color: const Color(0xFF2563EB).withValues(alpha: 0.5),
                                          blurRadius: 22,
                                          spreadRadius: 2,
                                        ),
                                      ],
                                    ),
                                    child: ValueListenableBuilder<bool>(
                                       valueListenable: _isPlayingNotifier,
                                       builder: (context, isPlaying, _) {
                                         return ValueListenableBuilder<bool>(
                                           valueListenable: _bufferingNotifier,
                                           builder: (context, isBuffering, _) {
                                             final bool showSpin = isBuffering || _isSeeking;
                                             return IconButton(
                                               padding: EdgeInsets.zero,
                                               icon: showSpin
                                                   ? const SizedBox(
                                                       width: 28,
                                                       height: 28,
                                                       child: CircularProgressIndicator(strokeWidth: 3, color: Colors.white),
                                                     )
                                                   : Icon(
                                                       isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                                                       color: Colors.white,
                                                       size: 38,
                                                     ),
                                               onPressed: showSpin ? null : _togglePlayPause,
                                             );
                                           },
                                         );
                                       },
                                     ),
                                  ),
                                  const SizedBox(width: 24),

                                  // Forward 10s Button
                                  Container(
                                    width: 44,
                                    height: 44,
                                    decoration: BoxDecoration(
                                      color: Colors.black.withValues(alpha: 0.45),
                                      shape: BoxShape.circle,
                                      border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
                                    ),
                                    child: IconButton(
                                      padding: EdgeInsets.zero,
                                      icon: const Icon(Icons.forward_10_rounded, color: Colors.white, size: 24),
                                      onPressed: _onDoubleTapRight,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          // Bottom Scrubber Bar & Controls Row
                          if (!_isScreenLocked && !_isInitialStandby && _controller != null)
                            Positioned(
                              bottom: 0,
                              left: 0,
                              right: 0,
                              child: ValueListenableBuilder<VideoPlayerValue>(
                                valueListenable: _controller!,
                                builder: (context, playerVal, _) {
                                  return ValueListenableBuilder<double>(
                                    valueListenable: _dragPositionNotifier,
                                    builder: (context, dragPos, _) {
                                      final bool isDragging = dragPos >= 0;
                                      final double livePosMs = isDragging
                                          ? dragPos
                                          : playerVal.position.inMilliseconds.toDouble();
                                      final double liveDurMs = playerVal.duration.inMilliseconds.toDouble();
                                      final double validMax = liveDurMs > 0 ? liveDurMs : 1.0;
                                      final double liveSliderVal = livePosMs.clamp(0.0, validMax);

                                      return Container(
                                        padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
                                        child: Column(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            // Drag Position Floating Indicator
                                            if (isDragging)
                                              Container(
                                                margin: const EdgeInsets.only(bottom: 4),
                                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                                decoration: BoxDecoration(
                                                  color: Colors.black.withValues(alpha: 0.85),
                                                  borderRadius: BorderRadius.circular(12),
                                                  border: Border.all(color: AppColors.primary.withValues(alpha: 0.6)),
                                                ),
                                                child: Text(
                                                  '${DurationFormatter.formatTimestamp((dragPos / 1000).toInt())}  /  ${DurationFormatter.formatTimestamp((liveDurMs / 1000).toInt())}',
                                                  style: GoogleFonts.robotoMono(
                                                    color: Colors.white,
                                                    fontSize: 11,
                                                    fontWeight: FontWeight.w700,
                                                  ),
                                                ),
                                              ),

                                            // Scrub Slider (120 FPS Butter Smooth, Zero Rebuilds)
                                            SliderTheme(
                                              data: SliderTheme.of(context).copyWith(
                                                trackHeight: 3.5,
                                                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6.5),
                                                activeTrackColor: const Color(0xFF2563EB),
                                                inactiveTrackColor: Colors.white.withValues(alpha: 0.25),
                                                thumbColor: Colors.white,
                                                overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
                                              ),
                                              child: Slider(
                                                value: liveSliderVal,
                                                min: 0.0,
                                                max: validMax,
                                                onChangeStart: (val) {
                                                  _dragPositionNotifier.value = val;
                                                  _controlsTimer?.cancel();
                                                },
                                                onChanged: (val) {
                                                  _dragPositionNotifier.value = val;
                                                },
                                                onChangeEnd: (val) async {
                                                  _dragPositionNotifier.value = -1.0;
                                                  if (_controller != null && _controller!.value.isInitialized) {
                                                    await _controller!.seekTo(Duration(milliseconds: val.toInt()));
                                                    await _controller!.play();
                                                  }
                                                  _resetControlsTimer();
                                                },
                                              ),
                                            ),

                                            // Bottom Controls Row
                                            Row(
                                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                              children: [
                                                // Monospace Timestamps (Smooth 60 FPS real-time update)
                                                RichText(
                                                  text: TextSpan(
                                                    style: GoogleFonts.robotoMono(fontSize: 12, fontWeight: FontWeight.w600),
                                                    children: [
                                                      TextSpan(
                                                        text: DurationFormatter.formatTimestamp((livePosMs / 1000).toInt()),
                                                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800),
                                                      ),
                                                      TextSpan(
                                                        text: ' / ${DurationFormatter.formatTimestamp((liveDurMs / 1000).toInt())}',
                                                        style: TextStyle(color: Colors.white.withValues(alpha: 0.65)),
                                                      ),
                                                    ],
                                                  ),
                                                ),

                                                // Right: Speed Capsule [ 1.5x ⚡ ] + Fullscreen Button
                                                Row(
                                                  mainAxisSize: MainAxisSize.min,
                                                  children: [
                                                    // Speed Selector Capsule Button
                                                    InkWell(
                                                      onTap: _showSpeedSelectionModal,
                                                      borderRadius: BorderRadius.circular(16),
                                                      child: Container(
                                                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                                        decoration: BoxDecoration(
                                                          color: const Color(0xFF1E293B).withValues(alpha: 0.85),
                                                          borderRadius: BorderRadius.circular(16),
                                                          border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
                                                        ),
                                                        child: Row(
                                                          mainAxisSize: MainAxisSize.min,
                                                          children: [
                                                            const Icon(Icons.bolt_rounded, size: 14, color: Colors.white),
                                                            const SizedBox(width: 4),
                                                            Text(
                                                              '${_playbackSpeed == 1.0 ? '1' : _playbackSpeed}x',
                                                              style: GoogleFonts.inter(
                                                                color: Colors.white,
                                                                fontSize: 11,
                                                                fontWeight: FontWeight.w800,
                                                              ),
                                                            ),
                                                          ],
                                                        ),
                                                      ),
                                                    ),
                                                    const SizedBox(width: 10),
                                                    // Fullscreen Button
                                                    Container(
                                                      width: 34,
                                                      height: 34,
                                                      decoration: BoxDecoration(
                                                        color: Colors.black.withValues(alpha: 0.4),
                                                        shape: BoxShape.circle,
                                                      ),
                                                      child: IconButton(
                                                        padding: EdgeInsets.zero,
                                                        icon: Icon(
                                                          isFullscreen ? Icons.fullscreen_exit_rounded : Icons.fullscreen_rounded,
                                                          color: Colors.white,
                                                          size: 22,
                                                        ),
                                                        onPressed: _toggleFullscreen,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ],
                                            ),
                                          ],
                                        ),
                                      );
                                    },
                                  );
                                },
                              ),
                            ),
                              ],
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              // ── DETAILS, ACTION BAR & PLAYLIST / NOTES SECTION ─────────────────────
              if (!isFullscreen)
                Expanded(
                  child: ListView(
                    controller: _scrollController,
                    padding: const EdgeInsets.all(16),
                    children: [
                      // Lecture Title & Info Card
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: isDark ? const Color(0xFF131D31) : Colors.white,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: isDark ? const Color(0xFF22324E) : const Color(0xFFE2E8F0),
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.03),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: isDark ? AppColors.primary.withValues(alpha: 0.2) : AppColors.primaryLight.withValues(alpha: 0.6),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    currentModule?.title ?? 'Module',
                                    style: GoogleFonts.inter(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w700,
                                      color: AppColors.primary,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                if (isCompleted)
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF059669).withValues(alpha: 0.15),
                                      borderRadius: BorderRadius.circular(6),
                                      border: Border.all(color: const Color(0xFF059669).withValues(alpha: 0.3)),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const Icon(Icons.check_circle_rounded, size: 12, color: Color(0xFF059669)),
                                        const SizedBox(width: 4),
                                        Text(
                                          'Finished',
                                          style: GoogleFonts.inter(
                                            fontSize: 10,
                                            fontWeight: FontWeight.w700,
                                            color: const Color(0xFF059669),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text(
                              currentLesson?.title ?? 'Lesson',
                              style: GoogleFonts.inter(
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                                color: isDark ? Colors.white : const Color(0xFF0F172A),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '${course.title} • ${DurationFormatter.formatTimestamp(currentLesson?.duration?.toInt() ?? 0)}',
                              style: GoogleFonts.inter(
                                fontSize: 11,
                                color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                              ),
                            ),
                            const SizedBox(height: 14),

                            // ── 3 Action Buttons in 1 Row (Web Parity: Mark Done, Save, Download) ──
                            Row(
                              children: [
                                // 1. Mark Done / Finished Button
                                Expanded(
                                  child: ElevatedButton.icon(
                                    onPressed: () {
                                      if (currentLesson != null) {
                                        final authPhone = context.read<AuthProvider>().phoneNumber;
                                        final dur = (totalDurationMs / 1000).toInt();
                                        final effectiveDur = dur > 0 ? dur : (currentLesson.duration?.toInt() ?? 60);
                                        progressProvider.toggleLessonCompleted(
                                          courseId: course.id,
                                          lessonId: currentLesson.id,
                                          durationSeconds: effectiveDur > 0 ? effectiveDur : 60,
                                          userPhone: authPhone,
                                        );
                                        setState(() {});
                                        ToastUtils.showSnackBar(
                                          context,
                                          !isCompleted ? 'Marked as completed!' : 'Marked as uncompleted',
                                          isSuccess: !isCompleted,
                                        );
                                      }
                                    },
                                    icon: Icon(
                                      isCompleted ? Icons.check_circle_rounded : Icons.check_circle_outline_rounded,
                                      size: 16,
                                    ),
                                    label: Text(
                                      isCompleted ? 'Finished' : 'Mark Done',
                                      style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w700),
                                    ),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: isCompleted
                                          ? const Color(0xFF059669)
                                          : (isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9)),
                                      foregroundColor: isCompleted
                                          ? Colors.white
                                          : (isDark ? Colors.white : const Color(0xFF0F172A)),
                                      elevation: 0,
                                      padding: const EdgeInsets.symmetric(vertical: 10),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(12),
                                        side: BorderSide(
                                          color: isCompleted
                                              ? const Color(0xFF059669)
                                              : (isDark ? const Color(0xFF334155) : const Color(0xFFCBD5E1)),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),

                                // 2. Bookmark / Save Button
                                Expanded(
                                  child: ElevatedButton.icon(
                                    onPressed: () {
                                      if (currentLesson != null) {
                                        bookmarkProvider.toggleBookmark(
                                          courseId: course.id,
                                          lessonId: currentLesson.id,
                                          title: currentLesson.title,
                                          courseTitle: course.title,
                                          duration: currentLesson.duration,
                                        );
                                        ToastUtils.showSnackBar(
                                          context,
                                          isBookmarked ? 'Removed from bookmarks' : 'Added to bookmarks',
                                          isSuccess: !isBookmarked,
                                        );
                                      }
                                    },
                                    icon: Icon(
                                      isBookmarked ? Icons.bookmark_rounded : Icons.bookmark_border_rounded,
                                      size: 16,
                                    ),
                                    label: Text(
                                      isBookmarked ? 'Saved' : 'Bookmark',
                                      style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w700),
                                    ),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: isBookmarked
                                          ? AppColors.primary
                                          : (isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9)),
                                      foregroundColor: isBookmarked
                                          ? Colors.white
                                          : (isDark ? Colors.white : const Color(0xFF0F172A)),
                                      elevation: 0,
                                      padding: const EdgeInsets.symmetric(vertical: 10),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(12),
                                        side: BorderSide(
                                          color: isBookmarked
                                              ? AppColors.primary
                                              : (isDark ? const Color(0xFF334155) : const Color(0xFFCBD5E1)),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),

                                // 3. Download Button
                                Expanded(
                                  child: Consumer<DownloadProvider>(
                                    builder: (ctx, dlProvider, _) {
                                      final task = dlProvider.getTask(course.id, _currentLessonId, 'video');
                                      final isDownloaded = dlProvider.isDownloaded(course.id, _currentLessonId, 'video');

                                      if (task != null && task.isDownloading) {
                                        return Container(
                                          padding: const EdgeInsets.symmetric(vertical: 9),
                                          decoration: BoxDecoration(
                                            color: AppColors.primary.withValues(alpha: 0.15),
                                            borderRadius: BorderRadius.circular(12),
                                            border: Border.all(color: AppColors.primary.withValues(alpha: 0.4)),
                                          ),
                                          child: Row(
                                            mainAxisAlignment: MainAxisAlignment.center,
                                            children: [
                                              SizedBox(
                                                width: 12,
                                                height: 12,
                                                child: CircularProgressIndicator(
                                                  value: task.progress > 0 ? task.progress : null,
                                                  strokeWidth: 2,
                                                  color: AppColors.primary,
                                                ),
                                              ),
                                              const SizedBox(width: 6),
                                              Text(
                                                '${(task.progress * 100).toInt()}%',
                                                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.primary),
                                              ),
                                            ],
                                          ),
                                        );
                                      } else if (isDownloaded) {
                                        return ElevatedButton.icon(
                                          onPressed: () {
                                            ToastUtils.showSnackBar(context, 'This lecture is saved for offline watching');
                                          },
                                          icon: const Icon(Icons.download_done_rounded, size: 16),
                                          label: Text(
                                            'Offline',
                                            style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w700),
                                          ),
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: const Color(0xFF059669),
                                            foregroundColor: Colors.white,
                                            elevation: 0,
                                            padding: const EdgeInsets.symmetric(vertical: 10),
                                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                          ),
                                        );
                                      } else {
                                        return ElevatedButton.icon(
                                          onPressed: () {
                                            if (currentLesson != null) {
                                              dlProvider.startDownload(
                                                course: course,
                                                lesson: currentLesson,
                                                userPhone: authProvider.phoneNumber,
                                              );
                                              ToastUtils.showSnackBar(
                                                context,
                                                'Downloading "${currentLesson.title}"...',
                                                isSuccess: true,
                                              );
                                            }
                                          },
                                          icon: const Icon(Icons.download_rounded, size: 16),
                                          label: Text(
                                            'Download',
                                            style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w700),
                                          ),
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: AppColors.primary,
                                            foregroundColor: Colors.white,
                                            elevation: 0,
                                            padding: const EdgeInsets.symmetric(vertical: 10),
                                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                          ),
                                        );
                                      }
                                    },
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Tabs: Course Playlist / Lesson Notes
                      Row(
                        children: [
                          Expanded(
                            child: InkWell(
                              onTap: () => setState(() => _activeDrawerTab = 0),
                              child: Container(
                                padding: const EdgeInsets.symmetric(vertical: 10),
                                decoration: BoxDecoration(
                                  border: Border(
                                    bottom: BorderSide(
                                      color: _activeDrawerTab == 0 ? AppColors.primary : Colors.transparent,
                                      width: 2,
                                    ),
                                  ),
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      Icons.playlist_play_rounded,
                                      size: 18,
                                      color: _activeDrawerTab == 0 ? AppColors.primary : (isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B)),
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      'Course Playlist',
                                      style: GoogleFonts.inter(
                                        fontSize: 12,
                                        fontWeight: _activeDrawerTab == 0 ? FontWeight.w700 : FontWeight.w500,
                                        color: _activeDrawerTab == 0 ? AppColors.primary : (isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B)),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          Expanded(
                            child: InkWell(
                              onTap: () => setState(() => _activeDrawerTab = 1),
                              child: Container(
                                padding: const EdgeInsets.symmetric(vertical: 10),
                                decoration: BoxDecoration(
                                  border: Border(
                                    bottom: BorderSide(
                                      color: _activeDrawerTab == 1 ? AppColors.primary : Colors.transparent,
                                      width: 2,
                                    ),
                                  ),
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      Icons.description_outlined,
                                      size: 16,
                                      color: _activeDrawerTab == 1 ? AppColors.primary : (isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B)),
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      'Lesson Notes (${currentModule?.notes.length ?? 0})',
                                      style: GoogleFonts.inter(
                                        fontSize: 12,
                                        fontWeight: _activeDrawerTab == 1 ? FontWeight.w700 : FontWeight.w500,
                                        color: _activeDrawerTab == 1 ? AppColors.primary : (isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B)),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),

                      // Tab 1: Course Playlist Queue
                      if (_activeDrawerTab == 0) ...[
                        // ── Sub-Module Progress Header Banner (Web Parity) ──
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: isDark ? const Color(0xFF1E293B).withValues(alpha: 0.6) : AppColors.primaryLight.withValues(alpha: 0.4),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: isDark ? const Color(0xFF334155) : const Color(0xFFCBD5E1),
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    'Module Progress',
                                    style: GoogleFonts.inter(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                      color: isDark ? Colors.white : const Color(0xFF0F172A),
                                    ),
                                  ),
                                  Text(
                                    '$completedModuleLessonsCount / $totalModuleLessonsCount ($moduleCompletionPct%)',
                                    style: GoogleFonts.inter(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                      color: AppColors.primary,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              ClipRRect(
                                borderRadius: BorderRadius.circular(4),
                                child: LinearProgressIndicator(
                                  value: totalModuleLessonsCount > 0
                                      ? completedModuleLessonsCount / totalModuleLessonsCount
                                      : 0.0,
                                  backgroundColor: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
                                  valueColor: const AlwaysStoppedAnimation<Color>(AppColors.primary),
                                  minHeight: 6,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),

                        // Playlist Lessons List
                        RepaintBoundary(
                          child: Column(
                            children: [
                              for (int idx = 0; idx < (currentModule?.lessons.length ?? 0); idx++) ...[
                                Builder(
                                  builder: (_) {
                                    final l = currentModule!.lessons[idx];
                                    final isCurrent = l.id == _currentLessonId;
                                    final isDone = progressProvider.isLessonCompleted(_currentCourseId, l.id);
                                    final isLastWatched = progressProvider.continueWatching?.lessonId == l.id;
                                    final progressPct = progressProvider.getLessonProgressPercent(_currentCourseId, l.id, l.duration?.toInt() ?? 0);
                                    final progressFrac = progressProvider.getLessonProgressFraction(_currentCourseId, l.id, l.duration?.toInt() ?? 0);

                                    return RepaintBoundary(
                                      child: Container(
                                        decoration: BoxDecoration(
                                          color: isCurrent
                                              ? (isDark ? AppColors.primary.withValues(alpha: 0.18) : AppColors.primaryLight.withValues(alpha: 0.6))
                                              : (isDark ? const Color(0xFF131D31) : Colors.white),
                                          borderRadius: BorderRadius.circular(14),
                                          border: Border.all(
                                            color: isCurrent
                                                ? AppColors.primary
                                                : (isDark ? const Color(0xFF22324E) : const Color(0xFFE2E8F0)),
                                          ),
                                        ),
                                        child: ListTile(
                                          dense: true,
                                          onTap: () => _switchLesson(l.id),
                                          leading: Container(
                                            width: 30,
                                            height: 30,
                                            decoration: BoxDecoration(
                                              color: isCurrent
                                                  ? AppColors.primary
                                                  : (isDone
                                                      ? const Color(0xFF059669).withValues(alpha: 0.15)
                                                      : (isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9))),
                                              borderRadius: BorderRadius.circular(8),
                                            ),
                                            child: Center(
                                              child: isDone
                                                  ? const Icon(Icons.check_rounded, size: 16, color: Color(0xFF059669))
                                                  : Text(
                                                      '${idx + 1}',
                                                      style: TextStyle(
                                                        fontSize: 11,
                                                        fontWeight: FontWeight.w700,
                                                        color: isCurrent ? Colors.white : (isDark ? Colors.white70 : Colors.black87),
                                                      ),
                                                    ),
                                            ),
                                          ),
                                          title: Text(
                                            l.title,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: GoogleFonts.inter(
                                              fontSize: 13,
                                              fontWeight: isCurrent ? FontWeight.w700 : FontWeight.w500,
                                              color: isCurrent
                                                  ? AppColors.primary
                                                  : (isDark ? Colors.white : const Color(0xFF0F172A)),
                                            ),
                                          ),
                                          subtitle: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              const SizedBox(height: 2),
                                              Row(
                                                children: [
                                                  Text(
                                                    DurationFormatter.formatTimestamp(l.duration?.toInt() ?? 0),
                                                    style: GoogleFonts.inter(fontSize: 11, color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B)),
                                                  ),
                                                  if (isDone) ...[
                                                    const SizedBox(width: 6),
                                                    Text(
                                                      '• Finished',
                                                      style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w700, color: const Color(0xFF059669)),
                                                    ),
                                                  ] else if (progressPct > 0) ...[
                                                    const SizedBox(width: 6),
                                                    Text(
                                                      '• $progressPct% watched',
                                                      style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w600, color: AppColors.primary),
                                                    ),
                                                  ],
                                                  if (isLastWatched && !isCurrent) ...[
                                                    const SizedBox(width: 8),
                                                    Container(
                                                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                                      decoration: BoxDecoration(
                                                        color: AppColors.primary.withValues(alpha: 0.15),
                                                        borderRadius: BorderRadius.circular(4),
                                                      ),
                                                      child: const Text(
                                                        '▶ Resume',
                                                        style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: AppColors.primary),
                                                      ),
                                                    ),
                                                  ],
                                                ],
                                              ),
                                              if (!isDone && progressFrac > 0) ...[
                                                const SizedBox(height: 4),
                                                ClipRRect(
                                                  borderRadius: BorderRadius.circular(2),
                                                  child: LinearProgressIndicator(
                                                    value: progressFrac,
                                                    minHeight: 2.5,
                                                    backgroundColor: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
                                                    valueColor: const AlwaysStoppedAnimation<Color>(AppColors.primary),
                                                  ),
                                                ),
                                              ],
                                            ],
                                          ),
                                          trailing: isCurrent
                                              ? Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                  decoration: BoxDecoration(
                                                    color: AppColors.primary,
                                                    borderRadius: BorderRadius.circular(6),
                                                  ),
                                                  child: const Text(
                                                    'PLAYING',
                                                    style: TextStyle(fontSize: 9, fontWeight: FontWeight.w800, color: Colors.white),
                                                  ),
                                                )
                                              : null,
                                        ),
                                      ),
                                    );
                                  },
                                ),
                                if (idx < (currentModule?.lessons.length ?? 0) - 1) const SizedBox(height: 8),
                              ],
                            ],
                          ),
                        ),
                      ] else ...[
                        // Tab 2: Lesson Notes
                        if ((currentModule?.notes.isEmpty ?? true))
                          Container(
                            padding: const EdgeInsets.all(32),
                            alignment: Alignment.center,
                            child: Text(
                              'No notes attached to this module.',
                              style: GoogleFonts.inter(
                                fontSize: 12,
                                color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                              ),
                            ),
                          )
                        else
                          Column(
                            children: [
                              for (int idx = 0; idx < currentModule!.notes.length; idx++) ...[
                                Consumer<DownloadProvider>(
                                  builder: (_, dlProvider, __) {
                                    final note = currentModule!.notes[idx];
                                    final task = dlProvider.getTask(course.id, note.id, 'note');
                                    final isDl = dlProvider.isDownloaded(course.id, note.id, 'note');

                                    return Container(
                                      decoration: BoxDecoration(
                                        color: isDark ? const Color(0xFF131D31) : Colors.white,
                                        borderRadius: BorderRadius.circular(14),
                                        border: Border.all(
                                          color: isDark ? const Color(0xFF22324E) : const Color(0xFFE2E8F0),
                                        ),
                                      ),
                                      child: Material(
                                        color: Colors.transparent,
                                        borderRadius: BorderRadius.circular(14),
                                        child: InkWell(
                                          onTap: () => _handleNoteAction(course, note),
                                          borderRadius: BorderRadius.circular(14),
                                          child: Padding(
                                            padding: const EdgeInsets.all(12),
                                            child: Row(
                                              children: [
                                                const Icon(Icons.picture_as_pdf_rounded, color: Color(0xFFEF4444), size: 22),
                                                const SizedBox(width: 10),
                                                Expanded(
                                                  child: Column(
                                                    crossAxisAlignment: CrossAxisAlignment.start,
                                                    children: [
                                                      Text(
                                                        note.displayName,
                                                        maxLines: 1,
                                                        overflow: TextOverflow.ellipsis,
                                                        style: GoogleFonts.inter(
                                                          fontSize: 12,
                                                          fontWeight: FontWeight.w600,
                                                          color: isDark ? Colors.white : const Color(0xFF0F172A),
                                                        ),
                                                      ),
                                                      Text(
                                                        DurationFormatter.formatFileSize(note.size ?? 25000000),
                                                        style: GoogleFonts.inter(fontSize: 10, color: Colors.grey),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                                if (task != null && task.isDownloading) ...[
                                                  Builder(
                                                    builder: (_) {
                                                      final pct = (task.progress * 100).toInt();
                                                      return Container(
                                                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                                                        decoration: BoxDecoration(
                                                          color: const Color(0xFF10B981).withValues(alpha: 0.15),
                                                          borderRadius: BorderRadius.circular(6),
                                                        ),
                                                        child: Row(
                                                          mainAxisSize: MainAxisSize.min,
                                                          children: [
                                                            const SizedBox(
                                                              width: 10,
                                                              height: 10,
                                                              child: CircularProgressIndicator(
                                                                strokeWidth: 1.5,
                                                                color: Color(0xFF10B981),
                                                              ),
                                                            ),
                                                            const SizedBox(width: 5),
                                                            Text(
                                                              '$pct%',
                                                              style: GoogleFonts.inter(
                                                                fontSize: 10,
                                                                fontWeight: FontWeight.w700,
                                                                color: const Color(0xFF10B981),
                                                              ),
                                                            ),
                                                          ],
                                                        ),
                                                      );
                                                    },
                                                  ),
                                                ] else if (task != null && task.error != null) ...[
                                                  IconButton(
                                                    icon: const Icon(Icons.error_outline_rounded, size: 18, color: Color(0xFFEF4444)),
                                                    tooltip: 'Download error: ${task.error}',
                                                    onPressed: () {
                                                      ToastUtils.showSnackBar(context, task.error ?? 'Download failed. Please check connection.', isError: true);
                                                    },
                                                  ),
                                                ] else if (isDl) ...[
                                                  IconButton(
                                                    icon: const Icon(Icons.open_in_new_rounded, size: 18, color: Color(0xFF10B981)),
                                                    tooltip: 'Open in PDF Viewer',
                                                    onPressed: () => _handleNoteAction(course, note),
                                                  ),
                                                ] else
                                                  IconButton(
                                                    icon: const Icon(Icons.download_rounded, size: 18, color: AppColors.primary),
                                                    tooltip: 'Download offline',
                                                    onPressed: () => _handleNoteAction(course, note),
                                                  ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ),
                                    );
                                  },
                                ),
                                if (idx < currentModule.notes.length - 1) const SizedBox(height: 8),
                              ],
                            ],
                          ),
                      ],
                      const SizedBox(height: 32),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
