import 'dart:async';
import 'package:flutter/material.dart';
import '../data/models/course_model.dart';
import '../data/local_db/app_database.dart';
import '../data/services/telegram_import_service.dart';

class CourseProvider extends ChangeNotifier {
  List<CourseModel> _courses = [];
  bool _isLoading = true;
  String _searchQuery = '';
  String _activeUserPhone = '';

  // Cached available channels (fetched once, refresh on demand)
  List<TelegramChannelInfo> _availableChannels = [];
  bool _isLoadingChannels = false;

  // Background sync tracking that persists across navigation
  final Set<int> _syncingChannelIds = {};
  final Map<String, DateTime> _lastMediaRefreshAt = {};
  final Map<String, Future<CourseModel?>> _mediaRefreshes = {};
  Future<void>? _coursesLoadFuture;
  String? _currentSyncStatus;

  List<CourseModel> get courses {
    if (_searchQuery.trim().isEmpty) return _courses;
    return _courses
        .where((c) =>
            c.title.toLowerCase().contains(_searchQuery.toLowerCase()) ||
            (c.description ?? '')
                .toLowerCase()
                .contains(_searchQuery.toLowerCase()))
        .toList();
  }

  bool get isLoading => _isLoading;
  String get searchQuery => _searchQuery;
  List<TelegramChannelInfo> get availableChannels => _availableChannels;
  bool get isLoadingChannels => _isLoadingChannels;
  Set<int> get syncingChannelIds => _syncingChannelIds;
  String? get currentSyncStatus => _currentSyncStatus;

  bool isChannelSyncing(int channelId) =>
      _syncingChannelIds.contains(channelId);

  CourseProvider();

  void setSearchQuery(String query) {
    _searchQuery = query;
    notifyListeners();
  }

  Future<void> loadCourses({String userPhone = ''}) {
    if (_coursesLoadFuture != null) return _coursesLoadFuture!;
    final loadFuture = _loadCourses(userPhone: userPhone);
    _coursesLoadFuture = loadFuture.whenComplete(() {
      if (identical(_coursesLoadFuture, loadFuture)) {
        _coursesLoadFuture = null;
      }
    });
    return _coursesLoadFuture!;
  }

  Future<void> _loadCourses({String userPhone = ''}) async {
    if (userPhone.isNotEmpty) {
      _activeUserPhone = userPhone;
    }
    _isLoading = true;
    notifyListeners();

    try {
      _courses =
          await AppDatabase.instance.getAllCourses(userPhone: _activeUserPhone);
    } catch (e) {
      debugPrint('[CourseProvider] Error loading courses: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Load Telegram channels once, and only re-fetch if forceRefresh is true
  Future<void> loadAvailableChannels(
      {required String phone, bool forceRefresh = false}) async {
    if (_availableChannels.isNotEmpty && !forceRefresh) {
      return;
    }

    _isLoadingChannels = true;
    notifyListeners();

    try {
      final list = await TelegramImportService.getAvailableChannels(phone);
      _availableChannels = list;
    } catch (e) {
      debugPrint('[CourseProvider] Error fetching channels: $e');
    } finally {
      _isLoadingChannels = false;
      notifyListeners();
    }
  }

  void clearForUser() {
    _courses.clear();
    _availableChannels.clear();
    _syncingChannelIds.clear();
    _activeUserPhone = '';
    _searchQuery = '';
    _lastMediaRefreshAt.clear();
    _mediaRefreshes.clear();
    notifyListeners();
  }

  Future<CourseModel?> refreshCourseForMediaFailure(
      String courseId, int lessonId,
      {required String phone}) async {
    final refreshKey = '${courseId}_$lessonId';
    final activeRefresh = _mediaRefreshes[refreshKey];
    if (activeRefresh != null) return activeRefresh;
    final lastRefresh = _lastMediaRefreshAt[refreshKey];
    if (lastRefresh != null &&
        DateTime.now().difference(lastRefresh) < const Duration(minutes: 5)) {
      return getCourse(courseId);
    }
    _lastMediaRefreshAt[refreshKey] = DateTime.now();
    final refresh = _refreshLessonAfterMediaFailure(courseId, lessonId, phone);
    _mediaRefreshes[refreshKey] = refresh;
    try {
      return await refresh;
    } finally {
      _mediaRefreshes.remove(refreshKey);
    }
  }

  Future<CourseModel?> _refreshLessonAfterMediaFailure(
      String courseId, int lessonId, String phone) async {
    final course = getCourse(courseId);
    if (course == null) return null;
    final lesson = await TelegramImportService.refreshLessonFromTelegram(
      phone: phone,
      channelId: course.channelId,
      lessonId: lessonId,
    );
    if (lesson == null) return course;

    final updatedCourse = course.copyWith(
      modules: course.modules
          .map((module) => module.copyWith(
                lessons: module.lessons
                    .map((item) => item.id == lessonId ? lesson : item)
                    .toList(),
              ))
          .toList(),
    );
    final index = _courses.indexWhere((item) => item.id == courseId);
    if (index >= 0) _courses[index] = updatedCourse;
    unawaited(
        AppDatabase.instance.insertCourse(updatedCourse, userPhone: phone));
    notifyListeners();
    return updatedCourse;
  }

  Future<CourseModel?> refreshModule(String courseId, int moduleId,
      {required String phone}) async {
    final course = getCourse(courseId);
    final module =
        course?.modules.where((item) => item.id == moduleId).firstOrNull;
    if (course == null || module == null) return course;

    final refreshedData = await TelegramImportService.refreshModuleFromTelegram(
      phone: phone,
      channelId: course.channelId,
      moduleId: moduleId,
    );
    if (refreshedData == null) return course;
    final refreshedModule = module.copyWith(
      lessons: refreshedData.lessons,
      notes: refreshedData.notes,
    );

    final updatedCourse = course.copyWith(
      modules: course.modules
          .map((item) => item.id == moduleId ? refreshedModule : item)
          .toList(),
    );
    final index = _courses.indexWhere((item) => item.id == courseId);
    if (index >= 0) _courses[index] = updatedCourse;
    unawaited(
        AppDatabase.instance.insertCourse(updatedCourse, userPhone: phone));
    notifyListeners();
    return updatedCourse;
  }

  CourseModel? getCourse(String courseId) {
    return _courses.where((c) => c.id == courseId).firstOrNull;
  }

  Future<void> renameModule(
      String courseId, int moduleId, String newTitle) async {
    final title = newTitle.trim();
    if (title.isEmpty) return;

    // 1. Optimistic update
    final course = _courses.where((c) => c.id == courseId).firstOrNull;
    if (course != null) {
      for (final m in course.modules) {
        if (m.id == moduleId) {
          m.title = title;
          break;
        }
      }
      notifyListeners();
    }

    // 2. Persist to SQLite
    await AppDatabase.instance.updateModuleTitle(courseId, moduleId, title);
    await loadCourses(userPhone: _activeUserPhone);
  }

  Future<void> togglePinModule(String courseId, int moduleId) async {
    // 1. Optimistic in-memory update
    final course = getCourse(courseId);
    if (course != null) {
      for (final m in course.modules) {
        if (m.id == moduleId) {
          m.isPinned = !m.isPinned;
          break;
        }
      }
      notifyListeners();
    }

    // 2. Persist to SQLite
    await AppDatabase.instance.toggleModulePinned(courseId, moduleId);
    await loadCourses(userPhone: _activeUserPhone);
  }

  Future<void> deleteCourse(String courseId) async {
    _courses.removeWhere((c) => c.id == courseId);
    notifyListeners();

    await AppDatabase.instance.deleteCourse(courseId);
    await loadCourses(userPhone: _activeUserPhone);
  }

  // Sequential synchronization queue lock to ensure low memory load and smooth 60 FPS UI
  Future<void> _syncQueueLock = Future.value();

  Future<CourseModel> importChannel(TelegramChannelInfo channel,
      {required String phone}) async {
    _syncingChannelIds.add(channel.id);
    _currentSyncStatus = 'Queued "${channel.name}"...';
    notifyListeners();

    final completer = Completer<CourseModel>();
    _syncQueueLock = _syncQueueLock.then((_) async {
      try {
        _currentSyncStatus = 'Syncing "${channel.name}"...';
        notifyListeners();

        final newCourse = await TelegramImportService.syncCourseFromTelegram(
          phone: phone,
          channelId: channel.id,
          accessHash: channel.accessHash,
          channelName: channel.name,
          onProgress: (fetched, total) {
            _currentSyncStatus =
                'Importing "${channel.name}" ($fetched${total != null ? '/$total' : ''})...';
            notifyListeners();
          },
        );

        // Instant in-memory update avoids full SQLite read/jsonDecode freeze
        final idx = _courses.indexWhere((c) => c.id == newCourse.id);
        if (idx >= 0) {
          _courses[idx] = newCourse;
        } else {
          _courses.insert(0, newCourse);
        }
        notifyListeners();

        // Persist to SQLite in background
        unawaited(
            AppDatabase.instance.insertCourse(newCourse, userPhone: phone));
        completer.complete(newCourse);
      } catch (e, st) {
        completer.completeError(e, st);
      } finally {
        _syncingChannelIds.remove(channel.id);
        _currentSyncStatus = null;
        notifyListeners();
      }
    }).catchError((e, st) {
      if (!completer.isCompleted) completer.completeError(e, st);
    });

    return completer.future;
  }

  Future<CourseModel> syncCourse(String courseId,
      {required String phone}) async {
    final existing = getCourse(courseId);
    final channelId = existing?.channelId ?? int.tryParse(courseId) ?? 0;

    _syncingChannelIds.add(channelId);
    _currentSyncStatus = 'Queued "${existing?.title ?? 'Course'}"...';
    notifyListeners();

    final completer = Completer<CourseModel>();
    _syncQueueLock = _syncQueueLock.then((_) async {
      try {
        _currentSyncStatus = 'Refreshing "${existing?.title ?? 'Course'}"...';
        notifyListeners();

        final updatedCourse =
            await TelegramImportService.syncCourseFromTelegram(
          phone: phone,
          channelId: channelId,
          channelName: existing?.title,
          onProgress: (fetched, total) {
            _currentSyncStatus =
                'Refreshing "${existing?.title ?? 'Course'}" ($fetched${total != null ? '/$total' : ''})...';
            notifyListeners();
          },
        );

        // Safe Guard: Only update if new sync returned real modules, or if existing is empty
        if (updatedCourse.modules.isNotEmpty &&
            updatedCourse.modules
                .any((m) => m.lessons.isNotEmpty || m.notes.isNotEmpty)) {
          final idx = _courses.indexWhere((c) => c.id == updatedCourse.id);
          if (idx >= 0) {
            _courses[idx] = updatedCourse;
          } else {
            _courses.insert(0, updatedCourse);
          }
          notifyListeners();

          // Persist to SQLite in background
          unawaited(AppDatabase.instance
              .insertCourse(updatedCourse, userPhone: phone));
          completer.complete(updatedCourse);
        } else {
          completer.complete(existing ?? updatedCourse);
        }
      } catch (e, st) {
        if (existing != null) {
          completer.complete(existing);
        } else {
          completer.completeError(e, st);
        }
      } finally {
        _syncingChannelIds.remove(channelId);
        _currentSyncStatus = null;
        notifyListeners();
      }
    }).catchError((e, st) {
      if (!completer.isCompleted) {
        if (existing != null) {
          completer.complete(existing);
        } else {
          completer.completeError(e, st);
        }
      }
    });

    return completer.future;
  }
}
