import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../models/course_model.dart';

class TelegramChannelInfo {
  final int id;
  final String name;
  final bool isChannel;
  final bool isGroup;
  final int memberCount;
  final int messageCount;

  TelegramChannelInfo({
    required this.id,
    required this.name,
    required this.isChannel,
    required this.isGroup,
    this.memberCount = 0,
    this.messageCount = 0,
  });

  factory TelegramChannelInfo.fromMap(Map<String, dynamic> map) {
    return TelegramChannelInfo(
      id: map['id'] is int ? map['id'] : int.parse('${map['id']}'),
      name: map['name'] ?? map['title'] ?? 'Untitled Channel',
      isChannel: map['is_channel'] == true,
      isGroup: map['is_group'] == true,
      memberCount: map['member_count'] ?? map['participants_count'] ?? 0,
      messageCount: map['message_count'] ?? 0,
    );
  }
}

class TelegramImportService {
  static const List<String> apiBases = [
    'https://telelearn.onrender.com/api',
    'http://10.0.2.2:8000/api',
    'http://127.0.0.1:8000/api',
  ];

  /// Fetch user's real Telegram dialogs/channels from backend
  static Future<List<TelegramChannelInfo>> getAvailableChannels(String phone) async {
    if (phone.isEmpty) return [];

    final cleanPhone = Uri.encodeComponent(phone.trim());

    for (final base in apiBases) {
      try {
        final url = Uri.parse('$base/courses/channels?phone=$cleanPhone');
        final res = await http.get(url).timeout(const Duration(seconds: 20));

        if (res.statusCode == 200) {
          final data = jsonDecode(res.body);
          final list = data['channels'] as List<dynamic>? ?? [];
          return list.map((c) => TelegramChannelInfo.fromMap(c as Map<String, dynamic>)).toList();
        }
      } catch (e) {
        debugPrint('[TelegramImportService] getAvailableChannels error on $base: $e');
      }
    }

    return [];
  }

  /// Sync real Telegram channel into course structure
  static Future<CourseModel> syncCourseFromTelegram({
    required String phone,
    required int channelId,
  }) async {
    for (final base in apiBases) {
      try {
        final url = Uri.parse('$base/courses/sync');
        final res = await http
            .post(
              url,
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode({
                'phone': phone.trim(),
                'channel_id': channelId,
              }),
            )
            .timeout(const Duration(seconds: 40));

        if (res.statusCode == 200) {
          final data = jsonDecode(res.body) as Map<String, dynamic>;
          final courseData = data['course'] ?? data;
          return _parseCourseJson(courseData, phone: phone.trim(), baseUrl: base);
        } else {
          final err = jsonDecode(res.body);
          throw Exception(err['detail'] ?? 'Failed to sync channel');
        }
      } catch (e) {
        debugPrint('[TelegramImportService] syncCourse error on $base: $e');
        if (e is Exception && !e.toString().contains('SocketException') && !e.toString().contains('TimeoutException')) {
          rethrow;
        }
      }
    }

    throw Exception('Failed to connect to Telegram backend. Please verify your connection.');
  }

  static CourseModel _parseCourseJson(Map<String, dynamic> json, {required String phone, String baseUrl = 'https://telelearn.onrender.com/api'}) {
    final courseId = json['_id']?.toString() ?? json['id']?.toString() ?? '${json['channel_id']}';
    final channelId = json['channel_id'] is int ? json['channel_id'] : int.parse('${json['channel_id']}');
    final title = json['title'] ?? 'Telegram Course';
    final description = json['description'] ?? 'Course synced from Telegram Channel';

    final cleanPhone = phone.trim().replaceAll('+', '').replaceAll(' ', '');
    final rawModules = json['modules'] as List<dynamic>? ?? [];
    final modules = rawModules.map((m) {
      final modMap = m as Map<String, dynamic>;
      final modId = modMap['id'] is int ? modMap['id'] : int.parse('${modMap['id']}');
      final modTitle = modMap['title'] ?? 'Module $modId';

      final rawLessons = modMap['lessons'] as List<dynamic>? ?? [];
      final List<CourseLesson> lessons = rawLessons.map((l) {
        final lesMap = l as Map<String, dynamic>;
        final lesId = lesMap['id'] is int ? lesMap['id'] as int : int.parse('${lesMap['id']}');
        final fileName = lesMap['file_name'] ?? lesMap['text'] ?? 'Lesson $lesId';
        final duration = lesMap['duration'] is num ? lesMap['duration'] as num : num.tryParse('${lesMap['duration']}') ?? 0;
        final size = lesMap['size'] is int ? lesMap['size'] as int : int.tryParse('${lesMap['size']}') ?? 0;

        // Construct real Telegram streaming URL & thumbnail URL via backend
        final streamUrl = '$baseUrl/courses/stream/$cleanPhone/$channelId/$lesId';
        final thumbUrl = '$baseUrl/courses/thumbnail/$cleanPhone/$channelId/$lesId';

        return CourseLesson(
          id: lesId,
          title: fileName.toString(),
          duration: duration,
          size: size,
          videoUrl: streamUrl,
          thumbnailUrl: thumbUrl,
        );
      }).toList();

      final rawNotes = modMap['notes'] as List<dynamic>? ?? [];
      final List<CourseNote> notes = rawNotes.map((n) {
        final noteMap = n as Map<String, dynamic>;
        final noteId = noteMap['id'] is int ? noteMap['id'] as int : int.parse('${noteMap['id']}');
        final fileName = noteMap['file_name'] ?? noteMap['text'] ?? 'Note $noteId';
        final size = noteMap['size'] is int ? noteMap['size'] as int : int.tryParse('${noteMap['size']}') ?? 0;

        return CourseNote(
          id: noteId,
          title: fileName.toString(),
          fileName: fileName.toString(),
          size: size,
          fileUrl: '$baseUrl/courses/download/$cleanPhone/$channelId/$noteId',
        );
      }).toList();

      return CourseModule(
        id: modId,
        title: modTitle,
        lessons: lessons,
        notes: notes,
      );
    }).toList();

    return CourseModel(
      id: courseId,
      channelId: channelId,
      title: title,
      description: description,
      modules: modules,
      createdAt: DateTime.now(),
    );
  }
}
