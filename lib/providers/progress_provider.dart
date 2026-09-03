import 'package:flutter/material.dart';
import '../data/models/progress_model.dart';
import '../data/local_db/app_database.dart';

class ProgressProvider extends ChangeNotifier {
  StudyMetrics _metrics = StudyMetrics.empty();
  ContinueWatchingItem? _continueWatching;
  final Map<String, List<LessonProgress>> _courseProgressMap = {};
  String _activeUserPhone = '';
  bool _isLoading = false;

  StudyMetrics get metrics => _metrics;
  ContinueWatchingItem? get continueWatching => _continueWatching;
  bool get isLoading => _isLoading;

  ProgressProvider();

  Future<void> loadProgressMetrics({String userPhone = ''}) async {
    if (userPhone.isNotEmpty) {
      _activeUserPhone = userPhone;
    }
    _isLoading = true;
    notifyListeners();

    try {
      final m = await AppDatabase.instance.getStudyMetrics(userPhone: _activeUserPhone);
      final cw = await AppDatabase.instance.getContinueWatching(userPhone: _activeUserPhone);
      _metrics = m;
      _continueWatching = cw;
    } catch (e) {
      debugPrint('[ProgressProvider] Error loading metrics: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  void clearForUser() {
    _metrics = StudyMetrics.empty();
    _continueWatching = null;
    _courseProgressMap.clear();
    _activeUserPhone = '';
    notifyListeners();
  }

  Future<List<LessonProgress>> loadCourseProgress(String courseId, {String userPhone = ''}) async {
    final phone = userPhone.isNotEmpty ? userPhone : _activeUserPhone;
    try {
      final list = await AppDatabase.instance.getCourseProgress(courseId, userPhone: phone);
      _courseProgressMap[courseId] = list;
      notifyListeners();
      return list;
    } catch (e) {
      debugPrint('[ProgressProvider] Error loading course progress: $e');
      return [];
    }
  }

  Future<void> loadMultipleCoursesProgress(List<String> courseIds, {String userPhone = ''}) async {
    if (courseIds.isEmpty) return;
    final phone = userPhone.isNotEmpty ? userPhone : _activeUserPhone;
    try {
      for (final cid in courseIds) {
        final list = await AppDatabase.instance.getCourseProgress(cid, userPhone: phone);
        _courseProgressMap[cid] = list;
      }
      notifyListeners();
    } catch (e) {
      debugPrint('[ProgressProvider] Error loading multiple course progress: $e');
    }
  }

  List<LessonProgress> getCachedCourseProgress(String courseId) {
    return _courseProgressMap[courseId] ?? [];
  }

  bool isLessonCompleted(String courseId, int lessonId) {
    final list = _courseProgressMap[courseId] ?? [];
    return list.any((p) => p.lessonId == lessonId && p.isCompleted);
  }

  int getLessonProgressSeconds(String courseId, int lessonId) {
    final list = _courseProgressMap[courseId] ?? [];
    final item = list.where((p) => p.lessonId == lessonId).firstOrNull;
    return item?.progressSeconds ?? 0;
  }

  double getLessonProgressFraction(String courseId, int lessonId, [int durationSeconds = 0]) {
    final list = _courseProgressMap[courseId] ?? [];
    final item = list.where((p) => p.lessonId == lessonId).firstOrNull;
    if (item == null) return 0.0;
    if (item.isCompleted) return 1.0;
    final dur = durationSeconds > 0 ? durationSeconds : item.durationSeconds;
    if (dur <= 0) return 0.0;
    return (item.progressSeconds / dur).clamp(0.0, 1.0);
  }

  int getLessonProgressPercent(String courseId, int lessonId, [int durationSeconds = 0]) {
    final fraction = getLessonProgressFraction(courseId, lessonId, durationSeconds);
    return (fraction * 100).toInt();
  }

  int getCourseCompletedCount(String courseId) {
    final list = _courseProgressMap[courseId] ?? [];
    return list.where((p) => p.isCompleted).length;
  }

  double getCourseCompletionPercentage(String courseId, int totalLessons) {
    if (totalLessons <= 0) return 0.0;
    final list = _courseProgressMap[courseId] ?? [];
    final completedCount = list.where((p) => p.isCompleted).length;
    final pct = (completedCount / totalLessons) * 100.0;
    return pct.clamp(0.0, 100.0);
  }

  int? getLastWatchedLessonId(String courseId) {
    final list = _courseProgressMap[courseId] ?? [];
    if (list.isEmpty) return null;
    final sorted = List<LessonProgress>.from(list)..sort((a, b) => b.lastWatchedAt.compareTo(a.lastWatchedAt));
    return sorted.firstOrNull?.lessonId;
  }

  Future<void> saveProgress({
    required String courseId,
    required int lessonId,
    required int progressSeconds,
    required int durationSeconds,
    bool? isCompleted,
    int deltaSeconds = 0,
    String userPhone = '',
  }) async {
    final phone = userPhone.isNotEmpty ? userPhone : _activeUserPhone;

    // Optimistic local update
    final currentList = List<LessonProgress>.from(_courseProgressMap[courseId] ?? []);
    final existingIdx = currentList.indexWhere((p) => p.lessonId == lessonId);
    final existingItem = existingIdx >= 0 ? currentList[existingIdx] : null;
    final isDone = isCompleted ?? ((existingItem?.isCompleted ?? false) || (durationSeconds > 0 && progressSeconds >= durationSeconds * 0.9));
    final updatedItem = LessonProgress(
      courseId: courseId,
      lessonId: lessonId,
      progressSeconds: progressSeconds,
      durationSeconds: durationSeconds,
      isCompleted: isDone,
      lastWatchedAt: DateTime.now(),
    );

    if (existingIdx >= 0) {
      currentList[existingIdx] = updatedItem;
    } else {
      currentList.add(updatedItem);
    }
    _courseProgressMap[courseId] = currentList;
    notifyListeners();

    await AppDatabase.instance.saveLessonProgress(
      courseId: courseId,
      lessonId: lessonId,
      progressSeconds: progressSeconds,
      durationSeconds: durationSeconds,
      isCompleted: isCompleted,
      deltaSeconds: deltaSeconds,
      userPhone: phone,
    );

    // Refresh course progress cache & metrics
    await loadCourseProgress(courseId, userPhone: phone);
    await loadProgressMetrics(userPhone: phone);
  }

  /// Lightweight progress save for periodic timer during playback.
  /// Does optimistic local update + SQLite write WITHOUT reloading
  /// course progress or metrics (avoids 3x cascading rebuilds every 5s).
  Future<void> saveProgressQuiet({
    required String courseId,
    required int lessonId,
    required int progressSeconds,
    required int durationSeconds,
    bool? isCompleted,
    int deltaSeconds = 0,
    String userPhone = '',
  }) async {
    final phone = userPhone.isNotEmpty ? userPhone : _activeUserPhone;

    // Optimistic local update (single notifyListeners)
    final currentList = List<LessonProgress>.from(_courseProgressMap[courseId] ?? []);
    final existingIdx = currentList.indexWhere((p) => p.lessonId == lessonId);
    final existingItem = existingIdx >= 0 ? currentList[existingIdx] : null;
    final isDone = isCompleted ?? ((existingItem?.isCompleted ?? false) || (durationSeconds > 0 && progressSeconds >= durationSeconds * 0.9));
    final updatedItem = LessonProgress(
      courseId: courseId,
      lessonId: lessonId,
      progressSeconds: progressSeconds,
      durationSeconds: durationSeconds,
      isCompleted: isDone,
      lastWatchedAt: DateTime.now(),
    );

    if (existingIdx >= 0) {
      currentList[existingIdx] = updatedItem;
    } else {
      currentList.add(updatedItem);
    }
    _courseProgressMap[courseId] = currentList;

    // Persist silently to SQLite without triggering UI rebuild cascades every 5s
    await AppDatabase.instance.saveLessonProgress(
      courseId: courseId,
      lessonId: lessonId,
      progressSeconds: progressSeconds,
      durationSeconds: durationSeconds,
      isCompleted: isCompleted,
      deltaSeconds: deltaSeconds,
      userPhone: phone,
    );
  }

  Future<void> toggleLessonCompleted({
    required String courseId,
    required int lessonId,
    required int durationSeconds,
    String userPhone = '',
  }) async {
    final phone = userPhone.isNotEmpty ? userPhone : _activeUserPhone;
    final currentlyCompleted = isLessonCompleted(courseId, lessonId);
    final targetState = !currentlyCompleted;

    // Optimistic local update
    final currentList = List<LessonProgress>.from(_courseProgressMap[courseId] ?? []);
    final existingIdx = currentList.indexWhere((p) => p.lessonId == lessonId);
    final updatedItem = LessonProgress(
      courseId: courseId,
      lessonId: lessonId,
      progressSeconds: targetState ? durationSeconds : 0,
      durationSeconds: durationSeconds,
      isCompleted: targetState,
      lastWatchedAt: DateTime.now(),
    );

    if (existingIdx >= 0) {
      currentList[existingIdx] = updatedItem;
    } else {
      currentList.add(updatedItem);
    }
    _courseProgressMap[courseId] = currentList;
    notifyListeners();

    await AppDatabase.instance.saveLessonProgress(
      courseId: courseId,
      lessonId: lessonId,
      progressSeconds: targetState ? durationSeconds : 0,
      durationSeconds: durationSeconds,
      isCompleted: targetState,
      userPhone: phone,
    );

    await loadCourseProgress(courseId, userPhone: phone);
    await loadProgressMetrics(userPhone: phone);
  }
}
