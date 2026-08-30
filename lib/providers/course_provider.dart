import 'package:flutter/material.dart';
import '../data/models/course_model.dart';
import '../data/local_db/app_database.dart';
import '../data/services/telegram_import_service.dart';

class CourseProvider extends ChangeNotifier {
  List<CourseModel> _courses = [];
  bool _isLoading = true;
  String _searchQuery = '';
  String _activeUserPhone = '';

  List<CourseModel> get courses {
    if (_searchQuery.trim().isEmpty) return _courses;
    return _courses.where((c) =>
        c.title.toLowerCase().contains(_searchQuery.toLowerCase()) ||
        (c.description ?? '').toLowerCase().contains(_searchQuery.toLowerCase())).toList();
  }

  bool get isLoading => _isLoading;
  String get searchQuery => _searchQuery;

  CourseProvider();

  void setSearchQuery(String query) {
    _searchQuery = query;
    notifyListeners();
  }

  Future<void> loadCourses({String userPhone = ''}) async {
    if (userPhone.isNotEmpty) {
      _activeUserPhone = userPhone;
    }
    _isLoading = true;
    notifyListeners();

    try {
      _courses = await AppDatabase.instance.getAllCourses(userPhone: _activeUserPhone);
    } catch (e) {
      debugPrint('[CourseProvider] Error loading courses: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  void clearForUser() {
    _courses.clear();
    _activeUserPhone = '';
    _searchQuery = '';
    notifyListeners();
  }

  CourseModel? getCourse(String courseId) {
    return _courses.where((c) => c.id == courseId).firstOrNull;
  }

  Future<void> renameModule(String courseId, int moduleId, String newTitle) async {
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

  Future<void> deleteCourse(String courseId) async {
    _courses.removeWhere((c) => c.id == courseId);
    notifyListeners();

    await AppDatabase.instance.deleteCourse(courseId);
    await loadCourses(userPhone: _activeUserPhone);
  }

  Future<CourseModel> importChannel(TelegramChannelInfo channel, {required String phone}) async {
    final newCourse = await TelegramImportService.syncCourseFromTelegram(
      phone: phone,
      channelId: channel.id,
    );
    await AppDatabase.instance.insertCourse(newCourse, userPhone: phone);
    await loadCourses(userPhone: phone);
    return newCourse;
  }
}
