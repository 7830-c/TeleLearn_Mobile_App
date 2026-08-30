import 'package:flutter/material.dart';
import '../data/models/bookmark_model.dart';
import '../data/local_db/app_database.dart';

class BookmarkProvider extends ChangeNotifier {
  List<BookmarkItem> _bookmarks = [];
  Set<int> _bookmarkedLessonIds = {};
  String _activeUserPhone = '';
  bool _isLoading = false;

  List<BookmarkItem> get bookmarks => _bookmarks;
  int get count => _bookmarks.length;
  bool get isLoading => _isLoading;

  BookmarkProvider();

  bool isBookmarked(int lessonId) => _bookmarkedLessonIds.contains(lessonId);

  Future<void> loadBookmarks({String userPhone = ''}) async {
    if (userPhone.isNotEmpty) {
      _activeUserPhone = userPhone;
    }
    _isLoading = true;
    notifyListeners();

    try {
      _bookmarks = await AppDatabase.instance.getAllBookmarks(userPhone: _activeUserPhone);
      _bookmarkedLessonIds = _bookmarks.map((b) => b.lessonId).toSet();
    } catch (e) {
      debugPrint('[BookmarkProvider] Error loading bookmarks: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  void clearForUser() {
    _bookmarks.clear();
    _bookmarkedLessonIds.clear();
    _activeUserPhone = '';
    notifyListeners();
  }

  Future<void> toggleBookmark({
    required String courseId,
    required int lessonId,
    required String title,
    String? courseTitle,
    num? duration,
    String userPhone = '',
  }) async {
    final phone = userPhone.isNotEmpty ? userPhone : _activeUserPhone;
    final bool exists = _bookmarkedLessonIds.contains(lessonId);

    // 1. Instant 0ms Optimistic UI update
    if (exists) {
      _bookmarkedLessonIds.remove(lessonId);
      _bookmarks.removeWhere((b) => b.lessonId == lessonId && b.courseId == courseId);
    } else {
      _bookmarkedLessonIds.add(lessonId);
      _bookmarks.insert(
        0,
        BookmarkItem(
          id: DateTime.now().millisecondsSinceEpoch,
          courseId: courseId,
          lessonId: lessonId,
          title: title,
          courseTitle: courseTitle,
          duration: duration,
          createdAt: DateTime.now(),
        ),
      );
    }
    notifyListeners();

    // 2. Persist to SQLite
    try {
      await AppDatabase.instance.toggleBookmark(
        courseId: courseId,
        lessonId: lessonId,
        title: title,
        userPhone: phone,
      );
    } catch (e) {
      debugPrint('[BookmarkProvider] Error persisting bookmark: $e');
      await loadBookmarks(userPhone: phone);
    }
  }

  Future<void> removeBookmark(String courseId, int lessonId, {String userPhone = ''}) async {
    final phone = userPhone.isNotEmpty ? userPhone : _activeUserPhone;
    _bookmarkedLessonIds.remove(lessonId);
    _bookmarks.removeWhere((b) => b.lessonId == lessonId && b.courseId == courseId);
    notifyListeners();

    try {
      await AppDatabase.instance.toggleBookmark(
        courseId: courseId,
        lessonId: lessonId,
        title: '',
        userPhone: phone,
      );
    } catch (e) {
      debugPrint('[BookmarkProvider] Error deleting bookmark: $e');
      await loadBookmarks(userPhone: phone);
    }
  }
}
