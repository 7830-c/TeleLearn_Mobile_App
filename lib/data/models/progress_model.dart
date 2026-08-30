class LessonProgress {
  final int id;
  final String courseId;
  final int lessonId;
  final int progressSeconds;
  final int durationSeconds;
  final bool isCompleted;
  final DateTime lastWatchedAt;

  LessonProgress({
    this.id = 0,
    required this.courseId,
    required this.lessonId,
    required this.progressSeconds,
    required this.durationSeconds,
    required this.isCompleted,
    required this.lastWatchedAt,
  });

  double get completionPercentage {
    if (durationSeconds <= 0) return isCompleted ? 100.0 : 0.0;
    final pct = (progressSeconds / durationSeconds) * 100.0;
    return pct.clamp(0.0, 100.0);
  }

  Map<String, dynamic> toMap() {
    return {
      'course_id': courseId,
      'lesson_id': lessonId,
      'progress_seconds': progressSeconds,
      'duration_seconds': durationSeconds,
      'is_completed': isCompleted ? 1 : 0,
      'last_watched_at': lastWatchedAt.toIso8601String(),
    };
  }

  factory LessonProgress.fromMap(Map<String, dynamic> map) {
    return LessonProgress(
      id: map['id'] is int ? map['id'] : int.tryParse(map['id']?.toString() ?? '0') ?? 0,
      courseId: map['course_id']?.toString() ?? '',
      lessonId: map['lesson_id'] is int
          ? map['lesson_id']
          : int.tryParse(map['lesson_id']?.toString() ?? '0') ?? 0,
      progressSeconds: map['progress_seconds'] is int
          ? map['progress_seconds']
          : int.tryParse(map['progress_seconds']?.toString() ?? '0') ?? 0,
      durationSeconds: map['duration_seconds'] is int
          ? map['duration_seconds']
          : int.tryParse(map['duration_seconds']?.toString() ?? '0') ?? 0,
      isCompleted: (map['is_completed'] == 1 || map['is_completed'] == true),
      lastWatchedAt: map['last_watched_at'] != null
          ? DateTime.tryParse(map['last_watched_at'].toString()) ?? DateTime.now()
          : DateTime.now(),
    );
  }
}

class StudyLog {
  final int id;
  final DateTime date;
  final int secondsStudied;

  StudyLog({
    required this.id,
    required this.date,
    required this.secondsStudied,
  });

  Map<String, dynamic> toMap() {
    return {
      'date': "${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}",
      'seconds_studied': secondsStudied,
    };
  }

  factory StudyLog.fromMap(Map<String, dynamic> map) {
    return StudyLog(
      id: map['id'] is int ? map['id'] : int.tryParse(map['id']?.toString() ?? '0') ?? 0,
      date: map['date'] != null
          ? DateTime.tryParse(map['date'].toString()) ?? DateTime.now()
          : DateTime.now(),
      secondsStudied: map['seconds_studied'] is int
          ? map['seconds_studied']
          : int.tryParse(map['seconds_studied']?.toString() ?? '0') ?? 0,
    );
  }
}

class StudyMetrics {
  final double totalHours;
  final double hoursToday;
  final int streakDays;

  StudyMetrics({
    required this.totalHours,
    required this.hoursToday,
    required this.streakDays,
  });

  factory StudyMetrics.empty() {
    return StudyMetrics(totalHours: 0.0, hoursToday: 0.0, streakDays: 0);
  }
}

class ContinueWatchingItem {
  final String courseId;
  final String courseTitle;
  final int lessonId;
  final String lessonTitle;
  final int progressSeconds;
  final int durationSeconds;
  final String? thumbnailUrl;
  final String? videoUrl;

  ContinueWatchingItem({
    required this.courseId,
    required this.courseTitle,
    required this.lessonId,
    required this.lessonTitle,
    required this.progressSeconds,
    required this.durationSeconds,
    this.thumbnailUrl,
    this.videoUrl,
  });

  double get completionPercentage {
    if (durationSeconds <= 0) return 0.0;
    return ((progressSeconds / durationSeconds) * 100.0).clamp(0.0, 100.0);
  }
}
