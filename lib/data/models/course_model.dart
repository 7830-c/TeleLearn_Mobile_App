import 'dart:convert';

class CourseModel {
  final String id;
  final int channelId;
  final String title;
  final String? description;
  final List<CourseModule> modules;
  final DateTime? createdAt;
  final DateTime? lastAccessedAt;

  CourseModel({
    required this.id,
    required this.channelId,
    required this.title,
    this.description,
    required this.modules,
    this.createdAt,
    this.lastAccessedAt,
  });

  int get totalLessons =>
      modules.fold(0, (sum, mod) => sum + mod.lessons.length);

  int get totalNotes =>
      modules.fold(0, (sum, mod) => sum + mod.notes.length);

  num get totalDurationSeconds => modules.fold(
      0,
      (sum, mod) =>
          sum +
          mod.lessons.fold(0, (lSum, les) => lSum + (les.duration ?? 0)));

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'channel_id': channelId,
      'title': title,
      'description': description,
      'data': jsonEncode({
        'title': title,
        'channel_id': channelId,
        'description': description,
        'modules': modules.map((m) => m.toMap()).toList(),
      }),
      'created_at': createdAt?.toIso8601String() ?? DateTime.now().toIso8601String(),
      'last_accessed_at': lastAccessedAt?.toIso8601String(),
    };
  }

  factory CourseModel.fromMap(Map<String, dynamic> map) {
    List<CourseModule> parsedModules = [];
    if (map['data'] != null) {
      try {
        final decoded = jsonDecode(map['data'] as String);
        if (decoded['modules'] != null) {
          parsedModules = (decoded['modules'] as List)
              .map((m) => CourseModule.fromMap(m as Map<String, dynamic>))
              .toList();
        }
      } catch (_) {}
    }

    return CourseModel(
      id: map['id']?.toString() ?? '1',
      channelId: map['channel_id'] is int
          ? map['channel_id']
          : int.tryParse(map['channel_id']?.toString() ?? '0') ?? 0,
      title: map['title'] ?? 'Untitled Course',
      description: map['description'],
      modules: parsedModules,
      createdAt: map['created_at'] != null
          ? DateTime.tryParse(map['created_at'].toString())
          : null,
      lastAccessedAt: map['last_accessed_at'] != null
          ? DateTime.tryParse(map['last_accessed_at'].toString())
          : null,
    );
  }

  CourseModel copyWith({
    String? id,
    int? channelId,
    String? title,
    String? description,
    List<CourseModule>? modules,
    DateTime? createdAt,
    DateTime? lastAccessedAt,
  }) {
    return CourseModel(
      id: id ?? this.id,
      channelId: channelId ?? this.channelId,
      title: title ?? this.title,
      description: description ?? this.description,
      modules: modules ?? this.modules,
      createdAt: createdAt ?? this.createdAt,
      lastAccessedAt: lastAccessedAt ?? this.lastAccessedAt,
    );
  }
}

class CourseModule {
  final int id;
  String title;
  final List<CourseLesson> lessons;
  final List<CourseNote> notes;

  CourseModule({
    required this.id,
    required this.title,
    required this.lessons,
    required this.notes,
  });

  num get totalDurationSeconds =>
      lessons.fold(0, (sum, les) => sum + (les.duration ?? 0));

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'lessons': lessons.map((l) => l.toMap()).toList(),
      'notes': notes.map((n) => n.toMap()).toList(),
    };
  }

  factory CourseModule.fromMap(Map<String, dynamic> map) {
    return CourseModule(
      id: map['id'] is int ? map['id'] : int.tryParse(map['id']?.toString() ?? '0') ?? 0,
      title: map['title'] ?? 'General Module',
      lessons: (map['lessons'] as List? ?? [])
          .map((l) => CourseLesson.fromMap(l as Map<String, dynamic>))
          .toList(),
      notes: (map['notes'] as List? ?? [])
          .map((n) => CourseNote.fromMap(n as Map<String, dynamic>))
          .toList(),
    );
  }
}

class CourseLesson {
  final int id;
  final String title;
  final num? duration;
  final int? size;
  final String? mimeType;
  final String? videoUrl;
  final String? thumbnailUrl;
  final String? summary;

  CourseLesson({
    required this.id,
    required this.title,
    this.duration,
    this.size,
    this.mimeType,
    this.videoUrl,
    this.thumbnailUrl,
    this.summary,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'duration': duration,
      'size': size,
      'mime_type': mimeType,
      'video_url': videoUrl,
      'thumbnail_url': thumbnailUrl,
      'summary': summary,
    };
  }

  factory CourseLesson.fromMap(Map<String, dynamic> map) {
    return CourseLesson(
      id: map['id'] is int ? map['id'] : int.tryParse(map['id']?.toString() ?? '0') ?? 0,
      title: map['title'] ?? 'Untitled Lesson',
      duration: map['duration'] as num?,
      size: map['size'] as int?,
      mimeType: map['mime_type'],
      videoUrl: map['video_url'],
      thumbnailUrl: map['thumbnail_url'],
      summary: map['summary'],
    );
  }
}

class CourseNote {
  final int id;
  final String? title;
  final String? text;
  final String? fileName;
  final int? size;
  final String? fileUrl;

  CourseNote({
    required this.id,
    this.title,
    this.text,
    this.fileName,
    this.size,
    this.fileUrl,
  });

  String get displayName => fileName ?? title ?? text ?? 'Study Document';

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'text': text,
      'file_name': fileName,
      'size': size,
      'file_url': fileUrl,
    };
  }

  factory CourseNote.fromMap(Map<String, dynamic> map) {
    return CourseNote(
      id: map['id'] is int ? map['id'] : int.tryParse(map['id']?.toString() ?? '0') ?? 0,
      title: map['title'],
      text: map['text'],
      fileName: map['file_name'],
      size: map['size'] as int?,
      fileUrl: map['file_url'],
    );
  }
}
