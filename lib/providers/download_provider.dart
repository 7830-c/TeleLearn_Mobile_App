import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import '../data/local_db/app_database.dart';
import '../data/models/course_model.dart';
import '../data/models/download_model.dart';
import '../data/services/local_streaming_server.dart';
import '../data/services/telegram_import_service.dart';

class DownloadTask {
  final String courseId;
  final int itemId;
  final String title;
  final String mediaType; // 'video' or 'note'
  double progress; // 0.0 to 1.0
  bool isDownloading;
  bool isPaused;
  bool isCompleted;
  bool isCancelled;
  String? error;
  int downloadedBytes;
  int totalBytes;
  double speedBytesPerSec;
  int remainingSeconds;
  final CourseModel course;
  final CourseLesson? lesson;
  final CourseNote? note;
  final String userPhone;
  http.Client? currentClient;
  int refreshRetryCount;

  DownloadTask({
    required this.courseId,
    required this.itemId,
    required this.title,
    required this.mediaType,
    required this.course,
    this.lesson,
    this.note,
    required this.userPhone,
    this.progress = 0.0,
    this.isDownloading = true,
    this.isPaused = false,
    this.isCompleted = false,
    this.isCancelled = false,
    this.error,
    this.downloadedBytes = 0,
    this.totalBytes = 0,
    this.speedBytesPerSec = 0.0,
    this.remainingSeconds = 0,
    this.refreshRetryCount = 0,
  });

  String get speedText {
    if (speedBytesPerSec <= 0 || !isDownloading || isPaused) return '';
    if (speedBytesPerSec >= 1024 * 1024) {
      return '${(speedBytesPerSec / (1024 * 1024)).toStringAsFixed(1)} MB/s';
    } else {
      return '${(speedBytesPerSec / 1024).toStringAsFixed(0)} KB/s';
    }
  }

  String get timeRemainingText {
    if (remainingSeconds <= 0 ||
        !isDownloading ||
        isPaused ||
        speedBytesPerSec <= 0) return '';
    if (remainingSeconds < 60) {
      return '${remainingSeconds}s left';
    } else if (remainingSeconds < 3600) {
      final m = remainingSeconds ~/ 60;
      final s = remainingSeconds % 60;
      return s > 0 ? '${m}m ${s}s left' : '${m}m left';
    } else {
      final h = remainingSeconds ~/ 3600;
      final m = (remainingSeconds % 3600) ~/ 60;
      return '${h}h ${m}m left';
    }
  }

  String get downloadStatusSummary {
    if (isPaused) return 'Paused';
    if (!isDownloading) return isCompleted ? 'Completed' : 'Pending';
    final speed = speedText;
    final time = timeRemainingText;
    if (speed.isNotEmpty && time.isNotEmpty) {
      return '$speed • $time';
    } else if (speed.isNotEmpty) {
      return speed;
    }
    return 'Downloading...';
  }
}

class DownloadProvider extends ChangeNotifier {
  List<DownloadModel> _downloads = [];
  final Map<String, DownloadTask> _activeTasks = {};
  final Map<String, DateTime> _lastMediaRefreshAt = {};
  String _activeUserPhone = '';
  bool _isLoading = true;

  List<DownloadModel> get downloads => _downloads;
  List<DownloadModel> get downloadedVideos =>
      _downloads.where((d) => d.isVideo).toList();
  List<DownloadModel> get downloadedNotes =>
      _downloads.where((d) => d.isNote).toList();

  List<DownloadTask> get activeTasks => _activeTasks.values.toList();
  List<DownloadTask> get activeVideoTasks => _activeTasks.values
      .where((t) => t.mediaType == 'video' && !t.isCompleted)
      .toList();
  List<DownloadTask> get activeNoteTasks => _activeTasks.values
      .where((t) => t.mediaType == 'note' && !t.isCompleted)
      .toList();

  int get count =>
      _downloads.length +
      _activeTasks.values.where((t) => !t.isCompleted).length;
  int get videoCount => downloadedVideos.length + activeVideoTasks.length;
  int get noteCount => downloadedNotes.length + activeNoteTasks.length;
  bool get isLoading => _isLoading;

  String _taskKey(String courseId, int itemId, String mediaType) =>
      '${courseId}_${itemId}_$mediaType';

  DownloadTask? getTask(String courseId, int itemId,
      [String mediaType = 'video']) {
    return _activeTasks[_taskKey(courseId, itemId, mediaType)];
  }

  bool isDownloaded(String courseId, int itemId, [String mediaType = 'video']) {
    return _downloads.any((d) =>
        d.courseId == courseId &&
        d.itemId == itemId &&
        d.mediaType == mediaType);
  }

  DownloadModel? getDownloadRecord(String courseId, int itemId,
      [String mediaType = 'video']) {
    return _downloads
        .where((d) =>
            d.courseId == courseId &&
            d.itemId == itemId &&
            d.mediaType == mediaType)
        .firstOrNull;
  }

  Future<void> loadDownloads(String userPhone) async {
    _activeUserPhone = userPhone;
    _isLoading = true;
    notifyListeners();

    try {
      _downloads =
          await AppDatabase.instance.getAllDownloads(userPhone: userPhone);
    } catch (e) {
      debugPrint('[DownloadProvider] Load error: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  void clearForUser() {
    for (final task in _activeTasks.values) {
      task.isCancelled = true;
      task.currentClient?.close();
    }
    _downloads.clear();
    _activeTasks.clear();
    _lastMediaRefreshAt.clear();
    _activeUserPhone = '';
    notifyListeners();
  }

  /// Start or restart a video download
  Future<void> startDownload({
    required CourseModel course,
    required CourseLesson lesson,
    required String userPhone,
  }) async {
    final key = _taskKey(course.id, lesson.id, 'video');
    if (_activeTasks.containsKey(key) && _activeTasks[key]!.isDownloading) {
      return;
    }

    final task = DownloadTask(
      courseId: course.id,
      itemId: lesson.id,
      title: lesson.title,
      mediaType: 'video',
      course: course,
      lesson: lesson,
      userPhone: userPhone,
      progress: 0.0,
      isDownloading: true,
      totalBytes: lesson.size != null && lesson.size! > 0 ? lesson.size! : 0,
    );
    _activeTasks[key] = task;
    notifyListeners();

    _runVideoDownload(task);
  }

  Future<Directory> _getNotesDirectory(String phone) async {
    final cleanPhone = phone.replaceAll('+', '').replaceAll(' ', '').trim();
    final phoneDir = cleanPhone.isNotEmpty ? cleanPhone : 'guest';

    Directory? baseDir;
    if (Platform.isAndroid) {
      try {
        baseDir = await getExternalStorageDirectory();
      } catch (_) {}
    }
    baseDir ??= await getApplicationDocumentsDirectory();

    final dir = Directory(p.join(baseDir.path, 'downloads', phoneDir, 'notes'));
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }
    return dir;
  }

  Future<Directory> _getVideosDirectory(String phone) async {
    final cleanPhone = phone.replaceAll('+', '').replaceAll(' ', '').trim();
    final phoneDir = cleanPhone.isNotEmpty ? cleanPhone : 'guest';

    Directory? baseDir;
    if (Platform.isAndroid) {
      try {
        baseDir = await getExternalStorageDirectory();
      } catch (_) {}
    }
    baseDir ??= await getApplicationDocumentsDirectory();

    final dir =
        Directory(p.join(baseDir.path, 'downloads', phoneDir, 'videos'));
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }
    return dir;
  }

  Future<void> _runVideoDownload(DownloadTask task) async {
    final key = _taskKey(task.courseId, task.itemId, 'video');
    try {
      final dir = await _getVideosDirectory(task.userPhone);
      final phoneDir =
          task.userPhone.replaceAll('+', '').replaceAll(' ', '').trim();

      final fileName = '${task.courseId}_${task.itemId}.mp4';
      final destinationFile = File(p.join(dir.path, fileName));
      final tempFile = File(p.join(dir.path, '$fileName.download.tmp'));

      // Asynchronously fetch thumbnail in background
      String? localThumbPath;
      if (task.lesson?.thumbnailUrl != null &&
          task.lesson!.thumbnailUrl!.isNotEmpty) {
        _fetchThumbnailInBackground(
          thumbnailUrl: task.lesson!.thumbnailUrl!,
          appDirPath: dir.parent.parent.path,
          phoneDir: phoneDir.isNotEmpty ? phoneDir : 'guest',
          courseId: task.courseId,
          lessonId: task.itemId,
        ).then((path) => localThumbPath = path);
      }

      String remoteUrl = task.lesson?.videoUrl ?? '';
      if (remoteUrl.isEmpty) {
        throw Exception('No stream URL available for this lesson');
      }

      if (remoteUrl.contains('/tg_stream') &&
          LocalStreamingServer.instance.isRunning) {
        remoteUrl =
            LocalStreamingServer.instance.getProxiedStreamUrl(remoteUrl);
      }

      // Preserve /courses/stream/ endpoint with quality=high (Enables exact Range byte-resume & 512KB MTProto pipe)
      if (!remoteUrl.contains('quality=')) {
        remoteUrl +=
            remoteUrl.contains('?') ? '&quality=high' : '?quality=high';
      }
      if (!remoteUrl.contains('is_download=')) {
        remoteUrl +=
            remoteUrl.contains('?') ? '&is_download=1' : '?is_download=1';
      }

      // Execute high-speed direct stream download
      final actualSize = await _executeStreamDownload(
        url: remoteUrl,
        tempFile: tempFile,
        destinationFile: destinationFile,
        task: task,
        estimatedSize: task.totalBytes,
      );

      if (task.isCancelled || task.isPaused) {
        return;
      }

      task.isDownloading = false;
      task.isCompleted = true;
      task.progress = 1.0;

      final downloadModel = DownloadModel(
        userPhone: task.userPhone,
        courseId: task.courseId,
        itemId: task.itemId,
        mediaType: 'video',
        title: task.title,
        localPath: destinationFile.path,
        fileSize: actualSize > 0 ? actualSize : task.totalBytes,
        downloadedAt: DateTime.now(),
        thumbnailPath: localThumbPath,
        thumbnailUrl: task.lesson?.thumbnailUrl,
        durationSeconds: task.lesson?.duration?.toInt() ?? 0,
      );

      await AppDatabase.instance.saveDownload(downloadModel);
      _downloads.removeWhere((d) =>
          d.courseId == task.courseId &&
          d.itemId == task.itemId &&
          d.mediaType == 'video');
      _downloads.insert(0, downloadModel);
      _activeTasks.remove(key);
      notifyListeners();
    } catch (e) {
      if (task.isCancelled || task.isPaused) return;
      debugPrint('[DownloadProvider] Video download failed: $e');
      task.isDownloading = false;
      task.error = e.toString();
      notifyListeners();
      if (task.lesson?.videoUrl?.contains('/tg_stream') == true &&
          task.refreshRetryCount == 0) {
        unawaited(_refreshAndRetryVideoDownload(task));
      }
    }
  }

  Future<void> _refreshAndRetryVideoDownload(DownloadTask failedTask) async {
    try {
      final refreshKey = '${failedTask.courseId}_${failedTask.itemId}';
      final lastRefresh = _lastMediaRefreshAt[refreshKey];
      if (lastRefresh != null &&
          DateTime.now().difference(lastRefresh) < const Duration(minutes: 5)) {
        return;
      }
      _lastMediaRefreshAt[refreshKey] = DateTime.now();
      final refreshedLesson =
          await TelegramImportService.refreshLessonFromTelegram(
        phone: failedTask.userPhone,
        channelId: failedTask.course.channelId,
        lessonId: failedTask.itemId,
      );
      if (refreshedLesson == null ||
          refreshedLesson.videoUrl == failedTask.lesson?.videoUrl) return;

      final refreshedModules = failedTask.course.modules.map((module) {
        final lessons = module.lessons
            .map((lesson) =>
                lesson.id == failedTask.itemId ? refreshedLesson : lesson)
            .toList();
        return module.copyWith(lessons: lessons);
      }).toList();
      final refreshedCourse =
          failedTask.course.copyWith(modules: refreshedModules);

      final key = _taskKey(failedTask.courseId, failedTask.itemId, 'video');
      final retryTask = DownloadTask(
        courseId: refreshedCourse.id,
        itemId: failedTask.itemId,
        title: refreshedLesson.title,
        mediaType: 'video',
        course: refreshedCourse,
        lesson: refreshedLesson,
        userPhone: failedTask.userPhone,
        totalBytes: refreshedLesson.size ?? 0,
        refreshRetryCount: failedTask.refreshRetryCount + 1,
      );
      _activeTasks[key] = retryTask;
      notifyListeners();
      await _runVideoDownload(retryTask);
    } catch (refreshError) {
      debugPrint(
          '[DownloadProvider] Course refresh after download failure failed: $refreshError');
    }
  }

  /// Start or restart a note download
  Future<void> startDownloadNote({
    required CourseModel course,
    required CourseNote note,
    required String userPhone,
  }) async {
    final key = _taskKey(course.id, note.id, 'note');
    if (_activeTasks.containsKey(key) && _activeTasks[key]!.isDownloading) {
      return;
    }

    final task = DownloadTask(
      courseId: course.id,
      itemId: note.id,
      title: note.displayName,
      mediaType: 'note',
      course: course,
      note: note,
      userPhone: userPhone,
      progress: 0.0,
      isDownloading: true,
      totalBytes: note.size != null && note.size! > 0 ? note.size! : 3145728,
    );
    _activeTasks[key] = task;
    notifyListeners();

    _runNoteDownload(task);
  }

  Future<void> _runNoteDownload(DownloadTask task) async {
    final key = _taskKey(task.courseId, task.itemId, 'note');
    try {
      final dir = await _getNotesDirectory(task.userPhone);
      final cleanPhone =
          task.userPhone.replaceAll('+', '').replaceAll(' ', '').trim();

      String ext = '.pdf';
      final note = task.note;
      if (note?.fileName != null && note!.fileName!.contains('.')) {
        ext = p.extension(note.fileName!);
      } else if (note?.fileUrl != null && note!.fileUrl!.contains('.')) {
        final urlExt = p.extension(Uri.parse(note.fileUrl!).path);
        if (urlExt.isNotEmpty) ext = urlExt;
      }

      final cleanNoteTitle = (note?.displayName ?? task.title)
          .replaceAll(RegExp(r'[^\w\.\-]'), '_');
      final fileName =
          'course_${task.courseId}_note_${task.itemId}_$cleanNoteTitle$ext';
      final destinationFile = File(p.join(dir.path, fileName));
      final tempFile = File(p.join(dir.path, '$fileName.download.tmp'));

      String? noteContent = note?.text;
      int actualSize = 0;
      bool downloadedFromRemote = false;

      // 1. Try downloading real Telegram file from remote endpoints (Web-Parity)
      final candidateUrls = <String>[];

      if (note?.fileUrl != null && note!.fileUrl!.isNotEmpty) {
        var urlStr = note.fileUrl!;
        if (urlStr.contains('/tg_stream') &&
            LocalStreamingServer.instance.isRunning) {
          urlStr = LocalStreamingServer.instance.getProxiedStreamUrl(urlStr);
        }
        urlStr += urlStr.contains('?') ? '&is_download=1' : '?is_download=1';
        candidateUrls.add(urlStr);
        if (urlStr.contains('/download/')) {
          final sanitized = urlStr.replaceAll(task.userPhone, cleanPhone);
          if (!candidateUrls.contains(sanitized)) candidateUrls.add(sanitized);
        }
      }

      String? lastError;
      for (final url in candidateUrls) {
        if (task.isCancelled || task.isPaused) return;
        try {
          debugPrint('[DownloadProvider] Downloading from remote: $url');
          actualSize = await _executeStreamDownload(
            url: url,
            tempFile: tempFile,
            destinationFile: destinationFile,
            task: task,
            estimatedSize: task.totalBytes,
          );
          if (actualSize > 0) {
            downloadedFromRemote = true;
            break;
          }
        } catch (dlErr) {
          lastError = dlErr.toString();
          debugPrint('[DownloadProvider] Download failed for $url: $dlErr');
        }
      }

      // 2. Handle outcome: Never fake large remote documents
      if (!downloadedFromRemote) {
        if (task.totalBytes > 1024 * 1024 ||
            (task.course.channelId > 0 && task.userPhone.isNotEmpty)) {
          task.isDownloading = false;
          task.isCompleted = false;
          task.error = lastError ??
              'Download failed: unable to fetch file from Telegram server';
          notifyListeners();
          return;
        }

        // Fallback ONLY for local sample notes
        final title = note?.displayName ?? task.title;
        final noteText = note?.text ?? '';
        final bodyBuffer = StringBuffer();
        bodyBuffer.writeln('Study Document: $title');
        bodyBuffer.writeln('Course: ${task.course.title}');
        bodyBuffer.writeln(
            'Saved on: ${DateTime.now().toLocal().toString().split('.')[0]}');
        bodyBuffer.writeln('');
        if (noteText.isNotEmpty) {
          bodyBuffer.writeln('--- Notes & Key Takeaways ---');
          bodyBuffer.writeln(noteText);
        } else {
          bodyBuffer.writeln('--- Study Notes & Concepts ---');
          bodyBuffer.writeln('1. Key Architectural Principles and Insights');
          bodyBuffer.writeln('2. Step-by-Step Implementation Best Practices');
          bodyBuffer.writeln('3. Complete Topic Summary & Review Notes');
        }

        final fullText = bodyBuffer.toString();
        noteContent = fullText;

        if (ext.toLowerCase() == '.pdf') {
          final pdfBytes =
              _buildValidPdfBytes(title, task.course.title, fullText);
          await destinationFile.writeAsBytes(pdfBytes);
          actualSize = destinationFile.lengthSync();
        } else {
          await destinationFile.writeAsString(fullText);
          actualSize = destinationFile.lengthSync();
        }

        task.progress = 1.0;
        task.downloadedBytes = task.totalBytes;
        notifyListeners();
      }

      if (task.isCancelled || task.isPaused) return;

      final recordedSize = actualSize > 100
          ? actualSize
          : (note?.size != null && note!.size! > 0 ? note.size! : 3145728);

      task.isDownloading = false;
      task.isCompleted = true;
      task.progress = 1.0;

      final downloadModel = DownloadModel(
        userPhone: task.userPhone,
        courseId: task.courseId,
        itemId: task.itemId,
        mediaType: 'note',
        title: task.title,
        localPath: destinationFile.path,
        fileSize: recordedSize,
        downloadedAt: DateTime.now(),
        noteContent: noteContent,
      );

      await AppDatabase.instance.saveDownload(downloadModel);
      _downloads.removeWhere((d) =>
          d.courseId == task.courseId &&
          d.itemId == task.itemId &&
          d.mediaType == 'note');
      _downloads.insert(0, downloadModel);
      _activeTasks.remove(key);
      notifyListeners();
    } catch (e) {
      if (task.isCancelled || task.isPaused) return;
      debugPrint('[DownloadProvider] Note download failed: $e');
      task.isDownloading = false;
      task.error = e.toString();
      notifyListeners();
    }
  }

  /// Builds a 100% compliant standard PDF 1.4 document from text
  List<int> _buildValidPdfBytes(
      String title, String courseTitle, String content) {
    final bytes = <int>[];
    final offsets = <int>[];

    void writeString(String s) {
      bytes.addAll(utf8.encode(s));
    }

    // 0. PDF Header
    writeString('%PDF-1.4\r\n%âãÏÓ\r\n');

    // 1. Catalog Object (Object 1)
    offsets.add(bytes.length);
    writeString('1 0 obj\r\n<< /Type /Catalog /Pages 2 0 R >>\r\nendobj\r\n');

    // 2. Pages Parent (Object 2)
    offsets.add(bytes.length);
    writeString(
        '2 0 obj\r\n<< /Type /Pages /Kids [3 0 R] /Count 1 >>\r\nendobj\r\n');

    // Prepare text content stream
    final cleanTitle = title.replaceAll(RegExp(r'[\\()]'), '');
    final cleanCourse = courseTitle.replaceAll(RegExp(r'[\\()]'), '');
    final rawLines = content.split('\n');

    final streamContent = StringBuffer();
    streamContent.writeln('BT');
    streamContent.writeln('/F1 18 Tf');
    streamContent.writeln('50 740 Td');
    streamContent.writeln('($cleanTitle) Tj');

    streamContent.writeln('/F1 11 Tf');
    streamContent.writeln('0 -24 Td');
    streamContent.writeln('(Course: $cleanCourse) Tj');

    streamContent.writeln('/F1 10 Tf');
    streamContent.writeln('0 -18 Td');
    streamContent.writeln('(TeleLearn Offline Study Document) Tj');

    streamContent.writeln('0 -20 Td');
    streamContent.writeln(
        '-------------------------------------------------------------------------------- Tj');

    streamContent.writeln('/F1 11 Tf');
    streamContent.writeln('0 -22 Td');

    int lineCount = 0;
    for (final rawLine in rawLines) {
      if (lineCount >= 42) break;
      final line = rawLine.replaceAll(RegExp(r'[\\()]'), '').trim();
      if (line.isEmpty) {
        streamContent.writeln('0 -14 Td');
        lineCount++;
      } else {
        for (int c = 0; c < line.length; c += 68) {
          if (lineCount >= 42) break;
          final end = (c + 68 < line.length ? c + 68 : line.length);
          final chunk = line.substring(c, end);
          streamContent.writeln('($chunk) Tj');
          streamContent.writeln('0 -14 Td');
          lineCount++;
        }
      }
    }

    streamContent.writeln('ET');

    final streamStr = streamContent.toString();
    final streamBytes = utf8.encode(streamStr);

    // 3. Page Object (Object 3)
    offsets.add(bytes.length);
    writeString(
        '3 0 obj\r\n<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Contents 4 0 R /Resources << /Font << /F1 5 0 R >> >> >>\r\nendobj\r\n');

    // 4. Content Stream (Object 4)
    offsets.add(bytes.length);
    writeString('4 0 obj\r\n<< /Length ${streamBytes.length} >>\r\nstream\r\n');
    bytes.addAll(streamBytes);
    writeString('\r\nendstream\r\nendobj\r\n');

    // 5. Font Object (Object 5)
    offsets.add(bytes.length);
    writeString(
        '5 0 obj\r\n<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica /Encoding /WinAnsiEncoding >>\r\nendobj\r\n');

    // 6. XRef Table with exact 20-byte entries per ISO standard
    final xrefOffset = bytes.length;
    writeString('xref\r\n0 6\r\n');
    writeString('0000000000 65535 f \r\n');
    for (final offset in offsets) {
      writeString('${offset.toString().padLeft(10, '0')} 00000 n \r\n');
    }

    writeString(
        'trailer\r\n<< /Size 6 /Root 1 0 R >>\r\nstartxref\r\n$xrefOffset\r\n%%EOF\r\n');

    return bytes;
  }

  /// Pause an active download
  void pauseDownload(String courseId, int itemId,
      [String mediaType = 'video']) {
    final key = _taskKey(courseId, itemId, mediaType);
    final task = _activeTasks[key];
    if (task != null && task.isDownloading) {
      task.isPaused = true;
      task.isDownloading = false;
      task.currentClient?.close();
      notifyListeners();
    }
  }

  /// Resume a paused download
  void resumeDownload(String courseId, int itemId,
      [String mediaType = 'video']) {
    final key = _taskKey(courseId, itemId, mediaType);
    final task = _activeTasks[key];
    if (task != null && task.isPaused) {
      task.isPaused = false;
      task.isDownloading = true;
      task.error = null;
      notifyListeners();

      if (mediaType == 'video') {
        _runVideoDownload(task);
      } else {
        _runNoteDownload(task);
      }
    }
  }

  /// Cancel and delete an active or paused download
  Future<void> cancelDownload(String courseId, int itemId,
      [String mediaType = 'video']) async {
    final key = _taskKey(courseId, itemId, mediaType);
    final task = _activeTasks[key];
    if (task != null) {
      task.isCancelled = true;
      task.isDownloading = false;
      task.currentClient?.close();

      try {
        final appDir = await getApplicationDocumentsDirectory();
        final phoneDir = task.userPhone.replaceAll('+', '').replaceAll(' ', '');
        final folder = mediaType == 'video' ? 'videos' : 'notes';
        final ext = mediaType == 'video' ? '.mp4' : '.pdf';
        final fileName = mediaType == 'video'
            ? '${courseId}_$itemId$ext'
            : 'note_${courseId}_$itemId$ext';
        final file =
            File(p.join(appDir.path, 'downloads', phoneDir, folder, fileName));
        if (file.existsSync()) await file.delete();

        final tempFile = File(p.join(appDir.path, 'downloads', phoneDir, folder,
            '$fileName.download.tmp'));
        if (tempFile.existsSync()) await tempFile.delete();
      } catch (_) {}

      _activeTasks.remove(key);
      notifyListeners();
    }
  }

  /// Resilient Resumable High-Speed Download Engine (Supports Pause/Resume & Network Switches)
  /// Uses dual-stream parallel downloading for large files (>5MB) to increase throughput.
  Future<int> _executeStreamDownload({
    required String url,
    required File tempFile,
    required File destinationFile,
    required DownloadTask task,
    int estimatedSize = 0,
  }) async {
    final uri = Uri.parse(url);
    int totalBytes = estimatedSize;

    // Standard high-speed browser headers (Matches Web Browser Speed)
    const browserHeaders = {
      'User-Agent':
          'TeleLearnDownloader/2.0 (Linux; Android 10; K) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/128.0.0.0 Mobile Safari/537.36',
      'Accept': '*/*',
      'Accept-Encoding': 'identity',
      'Connection': 'keep-alive',
    };

    // Discover total file size via url parameters or small Range probe if unknown
    if (totalBytes <= 0) {
      if (uri.queryParameters.containsKey('size')) {
        final qSize = int.tryParse(uri.queryParameters['size'] ?? '');
        if (qSize != null && qSize > 0) {
          totalBytes = qSize;
        }
      }

      if (totalBytes <= 0) {
        try {
          final probeClient = http.Client();
          final probeReq = http.Request('GET', uri);
          probeReq.headers.addAll(browserHeaders);
          probeReq.headers['range'] = 'bytes=0-0';
          final probeRes = await probeClient
              .send(probeReq)
              .timeout(const Duration(seconds: 10));
          if (probeRes.statusCode == 206) {
            final contentRange = probeRes.headers['content-range'] ?? '';
            final totalMatch = RegExp(r'/(\d+)').firstMatch(contentRange);
            if (totalMatch != null) {
              totalBytes = int.parse(totalMatch.group(1)!);
            }
          } else if (probeRes.statusCode == 200 &&
              (probeRes.contentLength ?? 0) > 0) {
            totalBytes = probeRes.contentLength!;
          }
          await probeRes.stream.drain();
          probeClient.close();
        } catch (_) {}
      }
    }
    if (totalBytes > 0) {
      task.totalBytes = totalBytes;
    }

    // Use dual-stream parallel download for large files with known size (Remote only)
    const int parallelThreshold = 5 * 1024 * 1024; // 5 MB
    final int existingBytes = tempFile.existsSync() ? tempFile.lengthSync() : 0;
    final isLocalServer = uri.host == '127.0.0.1' || uri.host == 'localhost';
    if (!isLocalServer &&
        totalBytes > parallelThreshold &&
        existingBytes == 0) {
      try {
        final result = await _executeDualStreamDownload(
          uri: uri,
          headers: browserHeaders,
          totalBytes: totalBytes,
          tempFile: tempFile,
          destinationFile: destinationFile,
          task: task,
        );
        if (result > 0) return result;
        if (task.isCancelled || task.isPaused) return 0;
      } catch (e) {
        debugPrint(
            '[DownloadProvider] Dual-stream failed, falling back to single-stream: $e');
        if (task.isCancelled || task.isPaused) return 0;
      }
    }

    return _executeSingleStreamDownload(
      uri: uri,
      headers: browserHeaders,
      totalBytes: totalBytes,
      tempFile: tempFile,
      destinationFile: destinationFile,
      task: task,
    );
  }

  /// Dual-stream parallel download: splits the file into 2 concurrent Range streams.
  Future<int> _executeDualStreamDownload({
    required Uri uri,
    required Map<String, String> headers,
    required int totalBytes,
    required File tempFile,
    required File destinationFile,
    required DownloadTask task,
  }) async {
    final int midpoint = totalBytes ~/ 2;
    final part1File = File('${tempFile.path}.part1');
    final part2File = File('${tempFile.path}.part2');

    int part1Bytes = 0;
    int part2Bytes = 0;
    DateTime lastUiUpdate = DateTime.now();
    DateTime lastSpeedTime = DateTime.now();
    int bytesAtLastSpeed = 0;

    void updateProgress() {
      final totalReceived = part1Bytes + part2Bytes;
      task.downloadedBytes = totalReceived;

      final now = DateTime.now();
      final elapsedMs = now.difference(lastSpeedTime).inMilliseconds;
      if (elapsedMs >= 500) {
        final deltaBytes = totalReceived - bytesAtLastSpeed;
        final double currentSpeed = (deltaBytes / (elapsedMs / 1000.0));
        task.speedBytesPerSec = task.speedBytesPerSec == 0.0
            ? currentSpeed
            : (task.speedBytesPerSec * 0.35 + currentSpeed * 0.65);
        if (task.speedBytesPerSec > 0 && totalBytes > totalReceived) {
          task.remainingSeconds =
              ((totalBytes - totalReceived) / task.speedBytesPerSec).round();
        }
        lastSpeedTime = now;
        bytesAtLastSpeed = totalReceived;
      }

      if (now.difference(lastUiUpdate).inMilliseconds > 500 ||
          totalReceived >= totalBytes) {
        lastUiUpdate = now;
        task.progress = (totalReceived / totalBytes).clamp(0.0, 1.0);
        notifyListeners();
      }
    }

    Future<int> downloadRange(int start, int end, File outputFile) async {
      final client = http.Client();
      try {
        final req = http.Request('GET', uri);
        req.headers.addAll(headers);
        req.headers['range'] = 'bytes=$start-$end';
        final response =
            await client.send(req).timeout(const Duration(seconds: 25));
        if (response.statusCode >= 400) {
          throw Exception('HTTP ${response.statusCode} for range $start-$end');
        }
        if (response.statusCode != 206) {
          throw Exception('Server did not honor range request for $start-$end');
        }

        final sink = outputFile.openWrite(mode: FileMode.write);
        int written = 0;
        await for (final chunk in response.stream) {
          if (task.isCancelled || task.isPaused) {
            await sink.flush();
            await sink.close();
            client.close();
            return 0;
          }
          sink.add(chunk);
          written += chunk.length;
          if (start == 0) {
            part1Bytes = written;
          } else {
            part2Bytes = written;
          }
          updateProgress();
        }
        await sink.flush();
        await sink.close();
        return written;
      } finally {
        client.close();
      }
    }

    final results = await Future.wait([
      downloadRange(0, midpoint - 1, part1File),
      downloadRange(midpoint, totalBytes - 1, part2File),
    ]);

    if (task.isCancelled || task.isPaused) return 0;

    if (results[0] <= 0 || results[1] <= 0) {
      try {
        if (part1File.existsSync()) await part1File.delete();
      } catch (_) {}
      try {
        if (part2File.existsSync()) await part2File.delete();
      } catch (_) {}
      throw Exception(
          'Dual-stream download incomplete: part1=${results[0]}, part2=${results[1]}');
    }

    final sink = destinationFile.openWrite(mode: FileMode.write);
    await sink.addStream(part1File.openRead());
    await sink.addStream(part2File.openRead());
    await sink.flush();
    await sink.close();

    try {
      if (part1File.existsSync()) await part1File.delete();
    } catch (_) {}
    try {
      if (part2File.existsSync()) await part2File.delete();
    } catch (_) {}

    return destinationFile.lengthSync();
  }

  /// Single-stream download with resume support.
  Future<int> _executeSingleStreamDownload({
    required Uri uri,
    required Map<String, String> headers,
    required int totalBytes,
    required File tempFile,
    required File destinationFile,
    required DownloadTask task,
  }) async {
    int retryCount = 0;
    const int maxRetries = 5;

    while (retryCount < maxRetries) {
      if (task.isCancelled || task.isPaused) return 0;

      final client = http.Client();
      task.currentClient = client;

      try {
        final int existingBytes =
            tempFile.existsSync() ? tempFile.lengthSync() : 0;
        final req = http.Request('GET', uri);
        req.headers.addAll(headers);

        if (existingBytes > 0) {
          req.headers['range'] = 'bytes=$existingBytes-';
        }

        final response =
            await client.send(req).timeout(const Duration(seconds: 45));
        if (response.statusCode >= 400 && response.statusCode != 416) {
          throw Exception('Server returned HTTP ${response.statusCode}');
        }

        if (response.statusCode == 416) {
          if (destinationFile.existsSync()) await destinationFile.delete();
          await tempFile.rename(destinationFile.path);
          return destinationFile.lengthSync();
        }

        final isPartial = response.statusCode == 206;
        final int contentLength = response.contentLength ?? 0;

        if (isPartial) {
          final contentRange = response.headers['content-range'] ?? '';
          final totalMatch = RegExp(r'/(\d+)').firstMatch(contentRange);
          if (totalMatch != null) {
            totalBytes = int.parse(totalMatch.group(1)!);
          } else {
            totalBytes = existingBytes + contentLength;
          }
        } else if (contentLength > 0) {
          totalBytes = contentLength;
        }
        if (totalBytes > 0) {
          task.totalBytes = totalBytes;
        }

        int receivedBytes = isPartial ? existingBytes : 0;
        task.downloadedBytes = receivedBytes;
        if (totalBytes > 0) {
          task.progress = (receivedBytes / totalBytes).clamp(0.0, 1.0);
        }
        notifyListeners();

        final sink = tempFile.openWrite(
            mode: isPartial ? FileMode.append : FileMode.write);
        DateTime lastUiUpdate = DateTime.now();
        DateTime lastSpeedTime = DateTime.now();
        int bytesAtLastSpeed = receivedBytes;

        await for (final chunk in response.stream) {
          if (task.isCancelled || task.isPaused) {
            await sink.flush();
            await sink.close();
            client.close();
            return 0;
          }

          sink.add(chunk);
          receivedBytes += chunk.length;
          task.downloadedBytes = receivedBytes;

          final now = DateTime.now();
          final elapsedMs = now.difference(lastSpeedTime).inMilliseconds;
          if (elapsedMs >= 500) {
            final deltaBytes = receivedBytes - bytesAtLastSpeed;
            final double currentSpeed = (deltaBytes / (elapsedMs / 1000.0));
            task.speedBytesPerSec = task.speedBytesPerSec == 0.0
                ? currentSpeed
                : (task.speedBytesPerSec * 0.35 + currentSpeed * 0.65);
            if (task.speedBytesPerSec > 0 && totalBytes > receivedBytes) {
              task.remainingSeconds =
                  ((totalBytes - receivedBytes) / task.speedBytesPerSec)
                      .round();
            }
            lastSpeedTime = now;
            bytesAtLastSpeed = receivedBytes;
          }

          if (now.difference(lastUiUpdate).inMilliseconds > 500 ||
              receivedBytes >= totalBytes) {
            lastUiUpdate = now;
            if (totalBytes > 0) {
              task.progress = (receivedBytes / totalBytes).clamp(0.0, 1.0);
            }
            notifyListeners();
          }
        }

        await sink.flush();
        await sink.close();

        if (task.isCancelled || task.isPaused) return 0;

        final writtenSize =
            tempFile.existsSync() ? tempFile.lengthSync() : receivedBytes;
        if (writtenSize < 10) {
          throw Exception('Downloaded file is incomplete ($writtenSize bytes)');
        }

        if (destinationFile.existsSync()) {
          await destinationFile.delete();
        }
        await tempFile.rename(destinationFile.path);

        return destinationFile.lengthSync();
      } catch (e) {
        if (task.isCancelled || task.isPaused) return 0;
        retryCount++;
        debugPrint(
            '[DownloadProvider] Network interrupted (attempt $retryCount/$maxRetries): $e. Retrying in ${retryCount * 2}s...');
        if (retryCount >= maxRetries) {
          rethrow;
        }
        await Future.delayed(Duration(seconds: retryCount * 2));
      } finally {
        client.close();
      }
    }
    return 0;
  }

  Future<String?> _fetchThumbnailInBackground({
    required String thumbnailUrl,
    required String appDirPath,
    required String phoneDir,
    required String courseId,
    required int lessonId,
  }) async {
    try {
      final thumbDir =
          Directory(p.join(appDirPath, 'downloads', phoneDir, 'thumbnails'));
      if (!thumbDir.existsSync()) thumbDir.createSync(recursive: true);
      final thumbFile =
          File(p.join(thumbDir.path, 'thumb_${courseId}_$lessonId.jpg'));
      final res = await http
          .get(Uri.parse(thumbnailUrl))
          .timeout(const Duration(seconds: 10));
      if (res.statusCode == 200 && res.bodyBytes.isNotEmpty) {
        await thumbFile.writeAsBytes(res.bodyBytes);
        return thumbFile.path;
      }
    } catch (_) {}
    return null;
  }

  Future<void> deleteDownload(String courseId, int itemId,
      {String mediaType = 'video', String userPhone = ''}) async {
    try {
      final record = getDownloadRecord(courseId, itemId, mediaType);
      if (record != null) {
        final file = File(record.localPath);
        if (file.existsSync()) {
          await file.delete();
        }
        if (record.thumbnailPath != null) {
          final thumb = File(record.thumbnailPath!);
          if (thumb.existsSync()) await thumb.delete();
        }
        await AppDatabase.instance.deleteDownload(
          courseId,
          itemId,
          mediaType: mediaType,
          userPhone: userPhone.isNotEmpty ? userPhone : _activeUserPhone,
        );
        _downloads.removeWhere((d) =>
            d.courseId == courseId &&
            d.itemId == itemId &&
            d.mediaType == mediaType);
        notifyListeners();
      }
    } catch (e) {
      debugPrint('[DownloadProvider] Delete error: $e');
    }
  }
}
