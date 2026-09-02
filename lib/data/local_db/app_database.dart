import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../models/course_model.dart';
import '../models/progress_model.dart';
import '../models/bookmark_model.dart';
import '../models/download_model.dart';

class AppDatabase {
  static final AppDatabase instance = AppDatabase._init();
  static Database? _database;

  AppDatabase._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('telelearn_local.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    if (!kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    }

    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);

    return await openDatabase(
      path,
      version: 3,
      onCreate: _createDB,
      onUpgrade: _onUpgrade,
    );
  }

  Future _createDB(Database db, int version) async {
    // 1. Courses table
    await db.execute('''
      CREATE TABLE courses (
        id TEXT PRIMARY KEY,
        user_phone TEXT NOT NULL DEFAULT '',
        channel_id INTEGER NOT NULL,
        title TEXT NOT NULL,
        description TEXT,
        data TEXT NOT NULL,
        created_at TEXT NOT NULL,
        last_accessed_at TEXT
      )
    ''');

    // 2. Progress table
    await db.execute('''
      CREATE TABLE progress (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        user_phone TEXT NOT NULL DEFAULT '',
        course_id TEXT NOT NULL,
        lesson_id INTEGER NOT NULL,
        progress_seconds INTEGER NOT NULL,
        duration_seconds INTEGER NOT NULL,
        is_completed INTEGER NOT NULL,
        last_watched_at TEXT NOT NULL,
        UNIQUE(user_phone, course_id, lesson_id) ON CONFLICT REPLACE
      )
    ''');

    // 3. Study logs table
    await db.execute('''
      CREATE TABLE study_logs (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        user_phone TEXT NOT NULL DEFAULT '',
        date TEXT NOT NULL,
        seconds_studied INTEGER NOT NULL,
        UNIQUE(user_phone, date) ON CONFLICT REPLACE
      )
    ''');

    // 4. Bookmarks table
    await db.execute('''
      CREATE TABLE bookmarks (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        user_phone TEXT NOT NULL DEFAULT '',
        course_id TEXT NOT NULL,
        lesson_id INTEGER NOT NULL,
        title TEXT NOT NULL,
        created_at TEXT NOT NULL,
        UNIQUE(user_phone, course_id, lesson_id) ON CONFLICT REPLACE
      )
    ''');

    // 5. Users table
    await db.execute('''
      CREATE TABLE users (
        phone TEXT PRIMARY KEY,
        display_name TEXT,
        is_logged_in INTEGER NOT NULL DEFAULT 1
      )
    ''');

    // 6. Downloads table (strictly isolated by media_type and item_id)
    await db.execute('''
      CREATE TABLE downloads (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        user_phone TEXT NOT NULL DEFAULT '',
        course_id TEXT NOT NULL,
        item_id INTEGER NOT NULL,
        media_type TEXT NOT NULL DEFAULT 'video',
        title TEXT NOT NULL,
        local_path TEXT NOT NULL,
        file_size INTEGER NOT NULL DEFAULT 0,
        downloaded_at TEXT NOT NULL,
        thumbnail_url TEXT,
        thumbnail_path TEXT,
        duration_seconds INTEGER DEFAULT 0,
        note_content TEXT,
        UNIQUE(user_phone, course_id, item_id, media_type) ON CONFLICT REPLACE
      )
    ''');

    // Performance Indexes for sub-millisecond dashboard loading
    await db.execute('CREATE INDEX IF NOT EXISTS idx_courses_phone ON courses(user_phone)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_progress_phone_course ON progress(user_phone, course_id)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_study_logs_phone_date ON study_logs(user_phone, date)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_bookmarks_phone ON bookmarks(user_phone)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_downloads_phone_type ON downloads(user_phone, media_type)');
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 3) {
      try {
        await db.execute('DROP TABLE IF EXISTS downloads');
      } catch (_) {}
      try {
        await db.execute('''
          CREATE TABLE IF NOT EXISTS downloads (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            user_phone TEXT NOT NULL DEFAULT '',
            course_id TEXT NOT NULL,
            item_id INTEGER NOT NULL,
            media_type TEXT NOT NULL DEFAULT 'video',
            title TEXT NOT NULL,
            local_path TEXT NOT NULL,
            file_size INTEGER NOT NULL DEFAULT 0,
            downloaded_at TEXT NOT NULL,
            thumbnail_url TEXT,
            thumbnail_path TEXT,
            duration_seconds INTEGER DEFAULT 0,
            note_content TEXT,
            UNIQUE(user_phone, course_id, item_id, media_type) ON CONFLICT REPLACE
          )
        ''');
      } catch (_) {}
    }
    try {
      await db.execute('CREATE INDEX IF NOT EXISTS idx_courses_phone ON courses(user_phone)');
      await db.execute('CREATE INDEX IF NOT EXISTS idx_progress_phone_course ON progress(user_phone, course_id)');
      await db.execute('CREATE INDEX IF NOT EXISTS idx_study_logs_phone_date ON study_logs(user_phone, date)');
      await db.execute('CREATE INDEX IF NOT EXISTS idx_bookmarks_phone ON bookmarks(user_phone)');
      await db.execute('CREATE INDEX IF NOT EXISTS idx_downloads_phone_type ON downloads(user_phone, media_type)');
    } catch (_) {}
  }

  // ── Courses CRUD ──────────────────────────────────────────────
  Future<List<CourseModel>> getAllCourses({String userPhone = ''}) async {
    final db = await database;
    final List<Map<String, dynamic>> results;
    if (userPhone.isNotEmpty) {
      results = await db.query(
        'courses',
        where: 'user_phone = ?',
        whereArgs: [userPhone],
        orderBy: 'last_accessed_at DESC, created_at DESC',
      );
    } else {
      results = await db.query('courses', where: 'user_phone = ?', whereArgs: [''], orderBy: 'last_accessed_at DESC, created_at DESC');
    }
    // Deserialize in background isolate — jsonDecode of multi-MB course data
    // blocks the main thread for 500ms+ per course, causing ANR on app startup
    return compute(_coursesFromMaps, results);
  }

  /// Top-level function for compute() — runs jsonDecode for all courses off the main thread
  static List<CourseModel> _coursesFromMaps(List<Map<String, dynamic>> maps) {
    return maps.map((map) => CourseModel.fromMap(map)).toList();
  }

  Future<CourseModel?> getCourseById(String id) async {
    final db = await database;
    final results = await db.query('courses', where: 'id = ?', whereArgs: [id]);
    if (results.isNotEmpty) {
      return CourseModel.fromMap(results.first);
    }
    return null;
  }

  Future<void> insertCourse(CourseModel course, {String userPhone = ''}) async {
    // Pre-compute the heavy jsonEncode in a background isolate to avoid
    // blocking the UI thread (courses with 500+ lessons produce multi-MB JSON strings)
    final map = await compute(_courseToMap, course);
    if (userPhone.isNotEmpty) {
      map['user_phone'] = userPhone;
    }
    final db = await database;
    await db.insert(
      'courses',
      map,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Top-level function for compute() — runs course.toMap() (which includes jsonEncode)
  /// in a background isolate so the main UI thread stays free for 60fps rendering.
  static Map<String, dynamic> _courseToMap(CourseModel course) {
    return course.toMap();
  }

  Future<void> updateCourse(CourseModel course, {String userPhone = ''}) async {
    final map = await compute(_courseToMap, course);
    if (userPhone.isNotEmpty) {
      map['user_phone'] = userPhone;
    }
    final db = await database;
    await db.update(
      'courses',
      map,
      where: 'id = ?',
      whereArgs: [course.id],
    );
  }

  Future<void> deleteCourse(String id) async {
    final db = await database;
    await db.delete('courses', where: 'id = ?', whereArgs: [id]);
    await db.delete('progress', where: 'course_id = ?', whereArgs: [id]);
    await db.delete('bookmarks', where: 'course_id = ?', whereArgs: [id]);
    await db.delete('downloads', where: 'course_id = ?', whereArgs: [id]);
  }

  Future<void> updateModuleTitle(String courseId, int moduleId, String newTitle) async {
    final course = await getCourseById(courseId);
    if (course == null) return;

    for (final mod in course.modules) {
      if (mod.id == moduleId) {
        mod.title = newTitle;
        break;
      }
    }

    await updateCourse(course);
  }

  // ── Progress & Study Analytics ─────────────────────────────────
  Future<void> saveLessonProgress({
    required String courseId,
    required int lessonId,
    required int progressSeconds,
    required int durationSeconds,
    bool? isCompleted,
    int deltaSeconds = 0,
    String userPhone = '',
  }) async {
    final db = await database;
    final now = DateTime.now();

    final bool completed = isCompleted ?? (durationSeconds > 0 && (progressSeconds / durationSeconds >= 0.90));

    await db.insert(
      'progress',
      {
        'user_phone': userPhone,
        'course_id': courseId,
        'lesson_id': lessonId,
        'progress_seconds': progressSeconds,
        'duration_seconds': durationSeconds,
        'is_completed': completed ? 1 : 0,
        'last_watched_at': now.toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );

    // Update last_accessed_at on course
    await db.update(
      'courses',
      {'last_accessed_at': now.toIso8601String()},
      where: 'id = ?',
      whereArgs: [courseId],
    );

    // Add study time to study_logs if delta > 0
    if (deltaSeconds > 0) {
      final dateStr = "${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}";
      final existing = await db.query(
        'study_logs',
        where: 'date = ? AND user_phone = ?',
        whereArgs: [dateStr, userPhone],
      );

      if (existing.isNotEmpty) {
        final currentSec = existing.first['seconds_studied'] as int? ?? 0;
        await db.update(
          'study_logs',
          {'seconds_studied': currentSec + deltaSeconds},
          where: 'id = ?',
          whereArgs: [existing.first['id']],
        );
      } else {
        await db.insert(
          'study_logs',
          {
            'user_phone': userPhone,
            'date': dateStr,
            'seconds_studied': deltaSeconds,
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    }
  }

  Future<List<LessonProgress>> getCourseProgress(String courseId, {String userPhone = ''}) async {
    final db = await database;
    final List<Map<String, dynamic>> results;
    if (userPhone.isNotEmpty) {
      results = await db.query(
        'progress',
        where: 'course_id = ? AND user_phone = ?',
        whereArgs: [courseId, userPhone],
      );
    } else {
      results = await db.query('progress', where: 'course_id = ?', whereArgs: [courseId]);
    }
    return results.map((map) => LessonProgress.fromMap(map)).toList();
  }

  Future<List<LessonProgress>> getAllProgress({String userPhone = ''}) async {
    final db = await database;
    final List<Map<String, dynamic>> results;
    if (userPhone.isNotEmpty) {
      results = await db.query(
        'progress',
        where: 'user_phone = ?',
        whereArgs: [userPhone],
        orderBy: 'last_watched_at DESC',
      );
    } else {
      results = await db.query('progress', orderBy: 'last_watched_at DESC');
    }
    return results.map((map) => LessonProgress.fromMap(map)).toList();
  }

  Future<Map<String, int>> getWeeklyStudyLogs({String userPhone = ''}) async {
    final db = await database;
    final now = DateTime.now();
    final Map<String, int> weeklyLogs = {};

    for (int i = 6; i >= 0; i--) {
      final d = now.subtract(Duration(days: i));
      final dateStr = "${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}";
      weeklyLogs[dateStr] = 0;
    }

    final List<Map<String, dynamic>> results;
    if (userPhone.isNotEmpty) {
      results = await db.query(
        'study_logs',
        where: 'user_phone = ?',
        whereArgs: [userPhone],
        orderBy: 'date DESC',
        limit: 14,
      );
    } else {
      results = await db.query('study_logs', orderBy: 'date DESC', limit: 14);
    }

    for (final row in results) {
      final date = row['date'] as String;
      final sec = row['seconds_studied'] as int;
      if (weeklyLogs.containsKey(date)) {
        weeklyLogs[date] = sec;
      }
    }

    return weeklyLogs;
  }

  Future<int> getCurrentStreakDays({String userPhone = ''}) async {
    final db = await database;
    final List<Map<String, dynamic>> logs;
    if (userPhone.isNotEmpty) {
      logs = await db.query(
        'study_logs',
        where: 'seconds_studied > 0 AND user_phone = ?',
        whereArgs: [userPhone],
        orderBy: 'date DESC',
      );
    } else {
      logs = await db.query(
        'study_logs',
        where: 'seconds_studied > 0',
        orderBy: 'date DESC',
      );
    }

    if (logs.isEmpty) return 0;

    int streak = 0;
    final today = DateTime.now();
    DateTime checkDate = DateTime(today.year, today.month, today.day);

    final logDates = logs.map((l) => l['date'] as String).toSet();

    final todayStr = "${checkDate.year}-${checkDate.month.toString().padLeft(2, '0')}-${checkDate.day.toString().padLeft(2, '0')}";
    if (!logDates.contains(todayStr)) {
      checkDate = checkDate.subtract(const Duration(days: 1));
    }

    while (true) {
      final dStr = "${checkDate.year}-${checkDate.month.toString().padLeft(2, '0')}-${checkDate.day.toString().padLeft(2, '0')}";
      if (logDates.contains(dStr)) {
        streak++;
        checkDate = checkDate.subtract(const Duration(days: 1));
      } else {
        break;
      }
    }

    return streak;
  }

  // ── Bookmarks CRUD ─────────────────────────────────────────────
  Future<List<BookmarkItem>> getAllBookmarks({String userPhone = ''}) async {
    final db = await database;
    final List<Map<String, dynamic>> results;
    if (userPhone.isNotEmpty) {
      results = await db.query(
        'bookmarks',
        where: 'user_phone = ?',
        whereArgs: [userPhone],
        orderBy: 'created_at DESC',
      );
    } else {
      results = await db.query('bookmarks', where: 'user_phone = ?', whereArgs: [''], orderBy: 'created_at DESC');
    }
    return results.map((map) => BookmarkItem.fromMap(map)).toList();
  }

  Future<void> toggleBookmark({
    required String courseId,
    required int lessonId,
    required String title,
    String userPhone = '',
  }) async {
    final db = await database;
    final existing = await db.query(
      'bookmarks',
      where: 'course_id = ? AND lesson_id = ? AND user_phone = ?',
      whereArgs: [courseId, lessonId, userPhone],
    );

    if (existing.isNotEmpty) {
      await db.delete(
        'bookmarks',
        where: 'id = ?',
        whereArgs: [existing.first['id']],
      );
    } else {
      await db.insert(
        'bookmarks',
        {
          'user_phone': userPhone,
          'course_id': courseId,
          'lesson_id': lessonId,
          'title': title,
          'created_at': DateTime.now().toIso8601String(),
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
  }

  Future<bool> isBookmarked(String courseId, int lessonId, {String userPhone = ''}) async {
    final db = await database;
    final results = await db.query(
      'bookmarks',
      where: 'course_id = ? AND lesson_id = ? AND user_phone = ?',
      whereArgs: [courseId, lessonId, userPhone],
    );
    return results.isNotEmpty;
  }

  // ── Downloads CRUD ─────────────────────────────────────────────
  Future<List<DownloadModel>> getAllDownloads({String userPhone = ''}) async {
    final db = await database;
    final List<Map<String, dynamic>> results;
    if (userPhone.isNotEmpty) {
      results = await db.query(
        'downloads',
        where: 'user_phone = ?',
        whereArgs: [userPhone],
        orderBy: 'downloaded_at DESC',
      );
    } else {
      results = await db.query('downloads', where: 'user_phone = ?', whereArgs: [''], orderBy: 'downloaded_at DESC');
    }
    return results.map((map) => DownloadModel.fromMap(map)).toList();
  }

  Future<DownloadModel?> getDownload(String courseId, int itemId, {String mediaType = 'video', String userPhone = ''}) async {
    final db = await database;
    final results = await db.query(
      'downloads',
      where: 'course_id = ? AND item_id = ? AND media_type = ? AND user_phone = ?',
      whereArgs: [courseId, itemId, mediaType, userPhone],
    );
    if (results.isNotEmpty) {
      return DownloadModel.fromMap(results.first);
    }
    return null;
  }

  Future<void> saveDownload(DownloadModel download) async {
    final db = await database;
    await db.insert(
      'downloads',
      download.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> deleteDownload(String courseId, int itemId, {String mediaType = 'video', String userPhone = ''}) async {
    final db = await database;
    if (userPhone.isNotEmpty) {
      await db.delete(
        'downloads',
        where: 'course_id = ? AND item_id = ? AND media_type = ? AND user_phone = ?',
        whereArgs: [courseId, itemId, mediaType, userPhone],
      );
    } else {
      await db.delete(
        'downloads',
        where: 'course_id = ? AND item_id = ? AND media_type = ?',
        whereArgs: [courseId, itemId, mediaType],
      );
    }
  }

  Future<StudyMetrics> getStudyMetrics({String userPhone = ''}) async {
    final db = await database;

    // Total hours studied
    final List<Map<String, dynamic>> sumResult;
    if (userPhone.isNotEmpty) {
      sumResult = await db.rawQuery(
        'SELECT SUM(seconds_studied) as total_seconds FROM study_logs WHERE user_phone = ?',
        [userPhone],
      );
    } else {
      sumResult = await db.rawQuery('SELECT SUM(seconds_studied) as total_seconds FROM study_logs WHERE user_phone = ?', ['']);
    }

    final totalSeconds = (sumResult.first['total_seconds'] as num?)?.toDouble() ?? 0.0;
    final totalHours = totalSeconds / 3600.0;

    final today = DateTime.now();
    final todayStr = "${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}";
    final todayResult = await db.query(
      'study_logs',
      where: 'date = ? AND user_phone = ?',
      whereArgs: [todayStr, userPhone],
    );
    final todaySec = todayResult.isNotEmpty ? (todayResult.first['seconds_studied'] as int? ?? 0) : 0;
    final hoursToday = todaySec / 3600.0;

    // Streak
    final streakDays = await getCurrentStreakDays(userPhone: userPhone);

    return StudyMetrics(
      totalHours: totalHours,
      hoursToday: hoursToday,
      streakDays: streakDays,
    );
  }

  Future<ContinueWatchingItem?> getContinueWatching({String userPhone = ''}) async {
    final db = await database;
    final List<Map<String, dynamic>> latestProgress;
    if (userPhone.isNotEmpty) {
      latestProgress = await db.query(
        'progress',
        where: 'is_completed = 0 AND progress_seconds > 0 AND user_phone = ?',
        whereArgs: [userPhone],
        orderBy: 'last_watched_at DESC',
        limit: 1,
      );
    } else {
      latestProgress = await db.query(
        'progress',
        where: 'is_completed = 0 AND progress_seconds > 0 AND user_phone = ?',
        whereArgs: [''],
        orderBy: 'last_watched_at DESC',
        limit: 1,
      );
    }

    if (latestProgress.isEmpty) return null;

    final progressRow = latestProgress.first;
    final courseId = progressRow['course_id'] as String;
    final lessonId = progressRow['lesson_id'] as int;

    final course = await getCourseById(courseId);
    if (course == null) return null;

    CourseLesson? lesson;

    for (final mod in course.modules) {
      for (final l in mod.lessons) {
        if (l.id == lessonId) {
          lesson = l;
          break;
        }
      }
      if (lesson != null) break;
    }

    if (lesson == null) return null;

    return ContinueWatchingItem(
      courseId: courseId,
      courseTitle: course.title,
      lessonId: lessonId,
      lessonTitle: lesson.title,
      progressSeconds: progressRow['progress_seconds'] as int,
      durationSeconds: progressRow['duration_seconds'] as int,
      thumbnailUrl: lesson.thumbnailUrl,
      videoUrl: lesson.videoUrl,
    );
  }
}
