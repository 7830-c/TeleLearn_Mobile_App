import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:telelearn/data/local_db/default_courses_data.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test('Database CRUD, Progress, Bookmarks, and Study Streak Test', () async {
    final db = await databaseFactory.openDatabase(inMemoryDatabasePath);

    // 1. Create tables
    await db.execute('''
      CREATE TABLE courses (
        id TEXT PRIMARY KEY,
        channel_id INTEGER NOT NULL,
        title TEXT NOT NULL,
        description TEXT,
        data TEXT NOT NULL,
        created_at TEXT NOT NULL,
        last_accessed_at TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE progress (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        course_id TEXT NOT NULL,
        lesson_id INTEGER NOT NULL,
        progress_seconds INTEGER NOT NULL DEFAULT 0,
        duration_seconds INTEGER NOT NULL DEFAULT 0,
        is_completed INTEGER NOT NULL DEFAULT 0,
        last_watched_at TEXT NOT NULL,
        UNIQUE(course_id, lesson_id) ON CONFLICT REPLACE
      )
    ''');

    await db.execute('''
      CREATE TABLE study_logs (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        date TEXT UNIQUE NOT NULL,
        seconds_studied INTEGER NOT NULL DEFAULT 0
      )
    ''');

    await db.execute('''
      CREATE TABLE bookmarks (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        course_id TEXT NOT NULL,
        lesson_id INTEGER NOT NULL,
        title TEXT NOT NULL,
        created_at TEXT NOT NULL,
        UNIQUE(course_id, lesson_id) ON CONFLICT REPLACE
      )
    ''');

    // 2. Insert default courses
    final defaultCourses = DefaultCoursesData.getInitialCourses();
    for (final course in defaultCourses) {
      await db.insert('courses', course.toMap());
    }

    final coursesResult = await db.query('courses');
    expect(coursesResult.length, 3);

    // 3. Test Progress Tracking & Auto-completion
    const courseId = '1';
    const lessonId = 1001;
    const duration = 1420;

    await db.insert('progress', {
      'course_id': courseId,
      'lesson_id': lessonId,
      'progress_seconds': 600,
      'duration_seconds': duration,
      'is_completed': 0,
      'last_watched_at': DateTime.now().toIso8601String(),
    });

    var progressRes = await db.query(
      'progress',
      where: 'course_id = ? AND lesson_id = ?',
      whereArgs: [courseId, lessonId],
    );
    expect(progressRes.isNotEmpty, isTrue);
    expect(progressRes.first['progress_seconds'], 600);
    expect(progressRes.first['is_completed'], 0);

    // Save 92% completion
    await db.insert('progress', {
      'course_id': courseId,
      'lesson_id': lessonId,
      'progress_seconds': 1350,
      'duration_seconds': duration,
      'is_completed': 1,
      'last_watched_at': DateTime.now().toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);

    progressRes = await db.query(
      'progress',
      where: 'course_id = ? AND lesson_id = ?',
      whereArgs: [courseId, lessonId],
    );
    expect(progressRes.first['is_completed'], 1);

    // 4. Test Bookmarks Add, Query & Remove
    await db.insert('bookmarks', {
      'course_id': courseId,
      'lesson_id': lessonId,
      'title': 'Test Lesson',
      'created_at': DateTime.now().toIso8601String(),
    });

    var bookmarksRes = await db.query('bookmarks');
    expect(bookmarksRes.length, 1);
    expect(bookmarksRes.first['lesson_id'], lessonId);

    await db.delete('bookmarks', where: 'course_id = ? AND lesson_id = ?', whereArgs: [courseId, lessonId]);
    bookmarksRes = await db.query('bookmarks');
    expect(bookmarksRes.isEmpty, isTrue);

    // 5. Test Study Log & Consecutive Streak Calculation
    final today = DateTime.now();
    final todayStr = "${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}";
    final yesterday = today.subtract(const Duration(days: 1));
    final yesterdayStr = "${yesterday.year}-${yesterday.month.toString().padLeft(2, '0')}-${yesterday.day.toString().padLeft(2, '0')}";
    final twoDaysAgo = today.subtract(const Duration(days: 2));
    final twoDaysAgoStr = "${twoDaysAgo.year}-${twoDaysAgo.month.toString().padLeft(2, '0')}-${twoDaysAgo.day.toString().padLeft(2, '0')}";

    await db.insert('study_logs', {'date': todayStr, 'seconds_studied': 3600});
    await db.insert('study_logs', {'date': yesterdayStr, 'seconds_studied': 1800});
    await db.insert('study_logs', {'date': twoDaysAgoStr, 'seconds_studied': 2400});

    final totalHoursRes = await db.rawQuery('SELECT SUM(seconds_studied) as total FROM study_logs');
    final totalSec = (totalHoursRes.first['total'] as num).toInt();
    expect(totalSec, 7800);

    final logs = await db.query('study_logs', orderBy: 'date DESC');
    final activeDates = logs.map((l) => l['date'].toString()).toSet();

    int streak = 0;
    DateTime checkDate = DateTime(today.year, today.month, today.day);
    while (true) {
      final dateKey = "${checkDate.year}-${checkDate.month.toString().padLeft(2, '0')}-${checkDate.day.toString().padLeft(2, '0')}";
      if (activeDates.contains(dateKey)) {
        streak++;
        checkDate = checkDate.subtract(const Duration(days: 1));
      } else {
        break;
      }
    }
    expect(streak, 3);

    await db.close();
  });
}
