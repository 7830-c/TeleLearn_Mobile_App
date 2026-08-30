class BookmarkItem {
  final int id;
  final String courseId;
  final int lessonId;
  final String title;
  final String? courseTitle;
  final num? duration;
  final DateTime createdAt;

  BookmarkItem({
    required this.id,
    required this.courseId,
    required this.lessonId,
    required this.title,
    this.courseTitle,
    this.duration,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'course_id': courseId,
      'lesson_id': lessonId,
      'title': title,
      'created_at': createdAt.toIso8601String(),
    };
  }

  factory BookmarkItem.fromMap(Map<String, dynamic> map, {String? courseTitle, num? duration}) {
    return BookmarkItem(
      id: map['id'] is int ? map['id'] : int.tryParse(map['id']?.toString() ?? '0') ?? 0,
      courseId: map['course_id']?.toString() ?? '',
      lessonId: map['lesson_id'] is int
          ? map['lesson_id']
          : int.tryParse(map['lesson_id']?.toString() ?? '0') ?? 0,
      title: map['title'] ?? 'Untitled Bookmark',
      courseTitle: courseTitle,
      duration: duration,
      createdAt: map['created_at'] != null
          ? DateTime.tryParse(map['created_at'].toString()) ?? DateTime.now()
          : DateTime.now(),
    );
  }
}

class UserSession {
  final String phone;
  final String? displayName;
  final String? avatarUrl;
  final bool isLoggedIn;

  UserSession({
    required this.phone,
    this.displayName,
    this.avatarUrl,
    required this.isLoggedIn,
  });

  factory UserSession.guest() {
    return UserSession(
      phone: '+1 (555) 019-2834',
      displayName: 'Alex Carter',
      isLoggedIn: true,
    );
  }
}
