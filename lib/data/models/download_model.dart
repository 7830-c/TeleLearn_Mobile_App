class DownloadModel {
  final int? id;
  final String userPhone;
  final String courseId;
  final int itemId; // lessonId for video, noteId for note
  final String mediaType; // 'video' or 'note'
  final String title;
  final String localPath;
  final int fileSize;
  final DateTime downloadedAt;
  final String? thumbnailUrl;
  final String? thumbnailPath;
  final int durationSeconds;
  final String? noteContent;

  DownloadModel({
    this.id,
    required this.userPhone,
    required this.courseId,
    required this.itemId,
    required this.mediaType,
    required this.title,
    required this.localPath,
    required this.fileSize,
    required this.downloadedAt,
    this.thumbnailUrl,
    this.thumbnailPath,
    this.durationSeconds = 0,
    this.noteContent,
  });

  bool get isVideo => mediaType == 'video';
  bool get isNote => mediaType == 'note';

  // Compatibility getter
  int get lessonId => itemId;

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'user_phone': userPhone,
      'course_id': courseId,
      'item_id': itemId,
      'media_type': mediaType,
      'title': title,
      'local_path': localPath,
      'file_size': fileSize,
      'downloaded_at': downloadedAt.toIso8601String(),
      'thumbnail_url': thumbnailUrl,
      'thumbnail_path': thumbnailPath,
      'duration_seconds': durationSeconds,
      'note_content': noteContent,
    };
  }

  factory DownloadModel.fromMap(Map<String, dynamic> map) {
    final rawItemId = map['item_id'] ?? map['lesson_id'] ?? 0;
    final int parsedItemId = rawItemId is int ? rawItemId : (int.tryParse('$rawItemId') ?? 0);
    
    // Explicit mediaType or fallback to path
    String type = map['media_type']?.toString() ?? '';
    if (type.isEmpty) {
      final path = map['local_path']?.toString() ?? '';
      if (path.endsWith('.pdf') || path.endsWith('.txt') || path.endsWith('.md') || path.endsWith('.doc') || path.endsWith('.docx') || path.contains('/notes/')) {
        type = 'note';
      } else {
        type = 'video';
      }
    }

    return DownloadModel(
      id: map['id'] as int?,
      userPhone: map['user_phone'] ?? '',
      courseId: map['course_id'] ?? '',
      itemId: parsedItemId,
      mediaType: type,
      title: map['title'] ?? 'Downloaded Item',
      localPath: map['local_path'] ?? '',
      fileSize: map['file_size'] is int ? map['file_size'] : (int.tryParse('${map['file_size']}') ?? 0),
      downloadedAt: DateTime.tryParse('${map['downloaded_at']}') ?? DateTime.now(),
      thumbnailUrl: map['thumbnail_url'],
      thumbnailPath: map['thumbnail_path'],
      durationSeconds: map['duration_seconds'] is int ? map['duration_seconds'] : (int.tryParse('${map['duration_seconds']}') ?? 0),
      noteContent: map['note_content'],
    );
  }
}
