import 'package:flutter_test/flutter_test.dart';
import 'package:telelearn/core/utils/duration_formatter.dart';
import 'package:telelearn/data/models/course_model.dart';
import 'package:telelearn/data/models/progress_model.dart';
import 'package:telelearn/data/models/bookmark_model.dart';
import 'package:telelearn/data/local_db/default_courses_data.dart';
import 'package:telelearn/data/services/local_streaming_server.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('DurationFormatter utilities format correctly', () {
    expect(DurationFormatter.formatHoursMinutes(3600), '1 hr');
    expect(DurationFormatter.formatHoursMinutes(7200), '2 hrs');
    expect(DurationFormatter.formatHoursMinutes(5100), '1h 25m');
    expect(DurationFormatter.formatHoursMinutes(1500), '25 mins');
    expect(DurationFormatter.formatHoursMinutes(0), '0 mins');
    expect(DurationFormatter.formatHoursMinutes(null), '0 mins');

    expect(DurationFormatter.formatTimestamp(65), '1:05');
    expect(DurationFormatter.formatTimestamp(3665), '1:01:05');
    expect(DurationFormatter.formatTimestamp(0), '0:00');
    expect(DurationFormatter.formatTimestamp(null), '0:00');

    expect(DurationFormatter.formatFileSize(1024 * 1024 * 50), '50.0 MB');
    expect(DurationFormatter.formatFileSize(1024 * 1024 * 1024 * 2), '2.0 GB');
  });

  test('CourseModel serialization & default data', () {
    final courses = DefaultCoursesData.getInitialCourses();
    expect(courses.isNotEmpty, isTrue);
    expect(courses.length, 3);

    final firstCourse = courses.first;
    expect(firstCourse.modules.isNotEmpty, isTrue);
    expect(firstCourse.totalLessons > 0, isTrue);
    expect(firstCourse.totalDurationSeconds > 0, isTrue);

    final map = firstCourse.toMap();
    final reconstructed = CourseModel.fromMap(map);
    expect(reconstructed.id, firstCourse.id);
    expect(reconstructed.title, firstCourse.title);
    expect(reconstructed.modules.length, firstCourse.modules.length);
  });

  test('LessonProgress calculation & Bookmark serialization', () {
    final prog = LessonProgress(
      id: 1,
      courseId: '1',
      lessonId: 101,
      progressSeconds: 900,
      durationSeconds: 1000,
      isCompleted: true,
      lastWatchedAt: DateTime.now(),
    );
    expect(prog.completionPercentage, 90.0);

    final bookmark = BookmarkItem(
      id: 1,
      courseId: '1',
      lessonId: 101,
      title: 'Flutter Architecture',
      createdAt: DateTime.now(),
    );
    final bMap = bookmark.toMap();
    final reconstructedBookmark = BookmarkItem.fromMap(bMap);
    expect(reconstructedBookmark.lessonId, 101);
    expect(reconstructedBookmark.title, 'Flutter Architecture');
  });

  test('LocalStreamingServer URL generation', () async {
    const remoteUrl = 'https://example.com/video.mp4';
    await LocalStreamingServer.instance.start();
    final proxied = LocalStreamingServer.instance.getProxiedStreamUrl(remoteUrl, quality: 'high');
    expect(proxied.contains('http://127.0.0.1:'), isTrue);
    expect(proxied.contains('quality=high'), isTrue);
    await LocalStreamingServer.instance.stop();
  });
}
