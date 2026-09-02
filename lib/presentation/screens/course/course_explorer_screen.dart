import 'dart:io';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:open_filex/open_filex.dart';
import 'package:provider/provider.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/duration_formatter.dart';
import '../../../core/utils/toast_utils.dart';
import '../../../data/models/course_model.dart';
import '../../../providers/course_provider.dart';
import '../../../providers/progress_provider.dart';
import '../../../providers/bookmark_provider.dart';
import '../../../providers/download_provider.dart';
import '../../../providers/auth_provider.dart';
import '../downloads/offline_note_viewer_screen.dart';
import '../player/youtube_video_player_screen.dart';

class CourseExplorerScreen extends StatefulWidget {
  final String courseId;
  final int? initialModuleId;

  const CourseExplorerScreen({
    super.key,
    required this.courseId,
    this.initialModuleId,
  });

  @override
  State<CourseExplorerScreen> createState() => _CourseExplorerScreenState();
}

class _CourseExplorerScreenState extends State<CourseExplorerScreen> {
  int? _activeModuleId;
  int _activeTab = 0; // 0 = Video Lessons, 1 = Notes & Documents

  @override
  void initState() {
    super.initState();
    _activeModuleId = widget.initialModuleId;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<ProgressProvider>().loadCourseProgress(widget.courseId);
    });
  }

  void _showRenameDialog(CourseModule module) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final controller = TextEditingController(text: module.title);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: isDark ? const Color(0xFF131D31) : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          'Rename Module',
          style: GoogleFonts.inter(
            fontWeight: FontWeight.w700,
            fontSize: 16,
            color: isDark ? Colors.white : const Color(0xFF0F172A),
          ),
        ),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: GoogleFonts.inter(fontSize: 14),
          decoration: InputDecoration(
            hintText: 'Enter new module name',
            filled: true,
            fillColor: isDark ? const Color(0xFF0B1120) : const Color(0xFFF8FAFC),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(
                color: isDark ? const Color(0xFF334155) : const Color(0xFFCBD5E1),
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(
              'Cancel',
              style: TextStyle(color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B)),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () async {
              final newTitle = controller.text.trim();
              if (newTitle.isNotEmpty) {
                Navigator.pop(ctx);
                await context.read<CourseProvider>().renameModule(widget.courseId, module.id, newTitle);
                if (mounted) {
                  ToastUtils.showSnackBar(context, 'Module renamed', isSuccess: true);
                }
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  Future<void> _handleDownloadNote(CourseNote note, CourseModel course) async {
    final authPhone = context.read<AuthProvider>().phoneNumber;
    final downloadProvider = context.read<DownloadProvider>();
    final isDl = downloadProvider.isDownloaded(course.id, note.id, 'note');
    if (isDl) {
      final rec = downloadProvider.getDownloadRecord(course.id, note.id, 'note');
      if (rec != null) {
        final file = File(rec.localPath);
        if (file.existsSync()) {
          try {
            final res = await OpenFilex.open(rec.localPath, type: 'application/pdf');
            if (res.type == ResultType.done) return;
          } catch (_) {}
        }
        if (mounted) {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => OfflineNoteViewerScreen(download: rec),
            ),
          );
        }
        return;
      }
    }
    downloadProvider.startDownloadNote(
      course: course,
      note: note,
      userPhone: authPhone,
    );
    ToastUtils.showSnackBar(
      context,
      'Downloading "${note.displayName}"...',
      isSuccess: true,
    );
  }

  Future<void> _handleSync() async {
    ToastUtils.showSnackBar(context, 'Syncing all lectures and notes from Telegram...', isSuccess: true);
    try {
      final phone = context.read<AuthProvider>().phoneNumber;
      final courseProvider = context.read<CourseProvider>();
      await courseProvider.syncCourse(widget.courseId, phone: phone);
      if (mounted) {
        ToastUtils.showSnackBar(context, 'Course fully synchronized with Telegram!', isSuccess: true);
      }
    } catch (e) {
      if (mounted) {
        ToastUtils.showSnackBar(context, 'Sync error: $e', isError: true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final courseProvider = context.watch<CourseProvider>();
    final progressProvider = context.watch<ProgressProvider>();
    final bookmarkProvider = context.watch<BookmarkProvider>();
    final downloadProvider = context.watch<DownloadProvider>();
    final authProvider = context.read<AuthProvider>();

    final course = courseProvider.getCourse(widget.courseId);

    if (course == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Course Explorer')),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 48, color: Colors.grey),
              const SizedBox(height: 12),
              const Text('Course not found'),
              const SizedBox(height: 12),
              ElevatedButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Back to Dashboard'),
              ),
            ],
          ),
        ),
      );
    }

    final CourseModule? currentModule = _activeModuleId != null
        ? course.modules.where((m) => m.id == _activeModuleId).firstOrNull
        : null;

    final isSyncing = courseProvider.isChannelSyncing(course.channelId);

    return PopScope(
      canPop: _activeModuleId == null,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        if (_activeModuleId != null) {
          setState(() => _activeModuleId = null);
        }
      },
      child: Scaffold(
        backgroundColor: isDark ? AppColors.darkBg : AppColors.lightBg,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            if (_activeModuleId != null) {
              setState(() => _activeModuleId = null);
            } else {
              Navigator.pop(context);
            }
          },
        ),
        title: Text(
          _activeModuleId != null ? 'Module View' : course.title,
          style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w700),
        ),
        actions: [
          if (currentModule != null)
            IconButton(
              icon: const Icon(Icons.edit_outlined, size: 20),
              tooltip: 'Rename Module',
              onPressed: () => _showRenameDialog(currentModule),
            ),
          IconButton(
            icon: isSyncing
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.sync_rounded, size: 22),
            tooltip: isSyncing ? 'Syncing...' : 'Sync Full Channel Content',
            onPressed: isSyncing ? null : _handleSync,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Background Syncing Indicator Banner
          if (isSyncing) ...[
            Container(
              margin: const EdgeInsets.only(bottom: 16),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: isDark ? AppColors.primary.withValues(alpha: 0.15) : AppColors.primaryLight.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.primary.withValues(alpha: 0.4)),
              ),
              child: Row(
                children: [
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Synchronizing course with Telegram...',
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: isDark ? Colors.white : const Color(0xFF0F172A),
                          ),
                        ),
                        Text(
                          'Updating video lectures, topics, and reference documents in background.',
                          style: GoogleFonts.inter(
                            fontSize: 10,
                            color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],

          // Header Card
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF131D31) : Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: isDark ? const Color(0xFF22324E) : const Color(0xFFE2E8F0),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.03),
                  blurRadius: 8,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: isDark
                            ? AppColors.primary.withValues(alpha: 0.2)
                            : AppColors.primaryLight.withValues(alpha: 0.6),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Icon(Icons.school_rounded, color: AppColors.primary, size: 26),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            currentModule != null ? currentModule.title : course.title,
                            style: GoogleFonts.inter(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              color: isDark ? Colors.white : const Color(0xFF0F172A),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            currentModule != null
                                ? '${currentModule.lessons.length} Video Lessons • ${DurationFormatter.formatHoursMinutes(currentModule.totalDurationSeconds)} • ${currentModule.notes.length} Notes'
                                : '${course.modules.length} Modules • ${course.totalLessons} Lessons • ${DurationFormatter.formatHoursMinutes(course.totalDurationSeconds)} Total Content',
                            style: GoogleFonts.inter(
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                              color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                if (currentModule != null) ...[
                  const SizedBox(height: 14),
                  const Divider(),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Switch Module:',
                        style: GoogleFonts.inter(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                        ),
                      ),
                      DropdownButton<int>(
                        value: currentModule.id,
                        dropdownColor: isDark ? const Color(0xFF1E293B) : Colors.white,
                        underline: const SizedBox(),
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: isDark ? Colors.white : const Color(0xFF0F172A),
                        ),
                        items: course.modules.map((m) {
                          return DropdownMenuItem<int>(
                            value: m.id,
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 180),
                              child: Text(m.title, overflow: TextOverflow.ellipsis),
                            ),
                          );
                        }).toList(),
                        onChanged: (val) {
                          if (val != null) {
                            setState(() => _activeModuleId = val);
                          }
                        },
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 20),

          // View 1: Module Grid / List
          if (currentModule == null) ...[
            Text(
              'COURSE MODULES (${course.modules.length})',
              style: GoogleFonts.inter(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.5,
                color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
              ),
            ),
            const SizedBox(height: 12),
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: course.modules.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (context, idx) {
                final mod = course.modules[idx];
                final completedCount = mod.lessons.where((l) =>
                    progressProvider.isLessonCompleted(course.id, l.id)).length;
                final completionPct = mod.lessons.isNotEmpty
                    ? ((completedCount / mod.lessons.length) * 100).toInt()
                    : 0;

                return Container(
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF131D31) : Colors.white,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: isDark ? const Color(0xFF22324E) : const Color(0xFFE2E8F0),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.03),
                        blurRadius: 6,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Material(
                    color: Colors.transparent,
                    borderRadius: BorderRadius.circular(18),
                    child: InkWell(
                      onTap: () => setState(() => _activeModuleId = mod.id),
                      borderRadius: BorderRadius.circular(18),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Container(
                                  width: 38,
                                  height: 38,
                                  decoration: BoxDecoration(
                                    color: isDark
                                        ? AppColors.primary.withValues(alpha: 0.2)
                                        : AppColors.primaryLight.withValues(alpha: 0.6),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: const Icon(Icons.folder_open_rounded, color: AppColors.primary, size: 20),
                                ),
                                if (completionPct > 0)
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: completionPct == 100
                                          ? const Color(0xFF059669).withValues(alpha: 0.15)
                                          : AppColors.primary.withValues(alpha: 0.15),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      completionPct == 100 ? 'Completed' : '$completionPct%',
                                      style: GoogleFonts.inter(
                                        fontSize: 10,
                                        fontWeight: FontWeight.w700,
                                        color: completionPct == 100 ? AppColors.accentEmerald : AppColors.primary,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Text(
                              mod.title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.inter(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: isDark ? Colors.white : const Color(0xFF0F172A),
                              ),
                            ),
                            const SizedBox(height: 10),
                            const Divider(),
                            const SizedBox(height: 6),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Row(
                                  children: [
                                    const Icon(Icons.play_circle_outline, size: 14, color: AppColors.primary),
                                    const SizedBox(width: 4),
                                    Text(
                                      '${mod.lessons.length} Lessons',
                                      style: GoogleFonts.inter(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                        color: AppColors.primary,
                                      ),
                                    ),
                                    if (mod.notes.isNotEmpty) ...[
                                      const SizedBox(width: 12),
                                      Icon(Icons.description_outlined,
                                          size: 14,
                                          color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B)),
                                      const SizedBox(width: 4),
                                      Text(
                                        '${mod.notes.length} Notes',
                                        style: GoogleFonts.inter(
                                          fontSize: 11,
                                          color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                                const Icon(Icons.chevron_right, size: 18, color: AppColors.primary),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ] else ...[
            // View 2: Module Drill-down with Tabs (Video Lessons / Notes)
            Row(
              children: [
                Expanded(
                  child: InkWell(
                    onTap: () => setState(() => _activeTab = 0),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(
                        border: Border(
                          bottom: BorderSide(
                            color: _activeTab == 0 ? AppColors.primary : Colors.transparent,
                            width: 2,
                          ),
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.play_circle_filled_rounded,
                            size: 16,
                            color: _activeTab == 0 ? AppColors.primary : (isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B)),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'Video Lessons (${currentModule.lessons.length})',
                            style: GoogleFonts.inter(
                              fontSize: 12,
                              fontWeight: _activeTab == 0 ? FontWeight.w700 : FontWeight.w500,
                              color: _activeTab == 0 ? AppColors.primary : (isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B)),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: InkWell(
                    onTap: () => setState(() => _activeTab = 1),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(
                        border: Border(
                          bottom: BorderSide(
                            color: _activeTab == 1 ? AppColors.primary : Colors.transparent,
                            width: 2,
                          ),
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.description_rounded,
                            size: 16,
                            color: _activeTab == 1 ? AppColors.primary : (isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B)),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'Notes (${currentModule.notes.length})',
                            style: GoogleFonts.inter(
                              fontSize: 12,
                              fontWeight: _activeTab == 1 ? FontWeight.w700 : FontWeight.w500,
                              color: _activeTab == 1 ? AppColors.primary : (isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B)),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Tab Content 1: Video Lessons
            if (_activeTab == 0) ...[
              if (currentModule.lessons.isEmpty)
                Container(
                  padding: const EdgeInsets.all(32),
                  alignment: Alignment.center,
                  child: Text(
                    'No video lessons found in this module.',
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                    ),
                  ),
                )
              else
                ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: currentModule.lessons.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    final lesson = currentModule.lessons[index];
                    final isCompleted = progressProvider.isLessonCompleted(course.id, lesson.id);
                    final isBookmarked = bookmarkProvider.isBookmarked(lesson.id);
                    final savedSec = progressProvider.getLessonProgressSeconds(course.id, lesson.id);
                    final lastWatchedId = progressProvider.getLastWatchedLessonId(course.id);
                    final isLastWatched = (lesson.id == lastWatchedId);
                    final progressPct = progressProvider.getLessonProgressPercent(course.id, lesson.id, lesson.duration?.toInt() ?? 0);
                    final progressFrac = progressProvider.getLessonProgressFraction(course.id, lesson.id, lesson.duration?.toInt() ?? 0);

                    return RepaintBoundary(
                      child: Container(
                        decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF131D31) : Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: isLastWatched
                              ? AppColors.primary
                              : (isDark ? const Color(0xFF22324E) : const Color(0xFFE2E8F0)),
                          width: isLastWatched ? 1.5 : 1,
                        ),
                        boxShadow: isLastWatched
                            ? [
                                BoxShadow(
                                  color: AppColors.primary.withValues(alpha: isDark ? 0.25 : 0.1),
                                  blurRadius: 6,
                                  offset: const Offset(0, 2),
                                ),
                              ]
                            : [],
                      ),
                      child: Material(
                        color: Colors.transparent,
                        borderRadius: BorderRadius.circular(16),
                        child: InkWell(
                          onTap: () {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => YouTubeVideoPlayerScreen(
                                  courseId: course.id,
                                  lessonId: lesson.id,
                                ),
                              ),
                            );
                          },
                          borderRadius: BorderRadius.circular(16),
                          child: Padding(
                            padding: const EdgeInsets.all(14),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    // Play indicator / Index / Completion checkmark
                                    Container(
                                      width: 36,
                                      height: 36,
                                      decoration: BoxDecoration(
                                        color: isCompleted
                                            ? const Color(0xFF059669).withValues(alpha: 0.15)
                                            : (isLastWatched
                                                ? AppColors.primary.withValues(alpha: 0.2)
                                                : (isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9))),
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      child: Center(
                                        child: isCompleted
                                            ? const Icon(Icons.check_circle_rounded, size: 20, color: Color(0xFF059669))
                                            : (isLastWatched || savedSec > 0
                                                ? const Icon(Icons.play_arrow_rounded, size: 20, color: AppColors.primary)
                                                : Text(
                                                    '${index + 1}',
                                                    style: TextStyle(
                                                      fontSize: 12,
                                                      fontWeight: FontWeight.w700,
                                                      color: isDark ? Colors.white70 : const Color(0xFF64748B),
                                                    ),
                                                  )),
                                      ),
                                    ),
                                    const SizedBox(width: 12),

                                    // Title and duration
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              Expanded(
                                                child: Text(
                                                  lesson.title,
                                                  maxLines: 2,
                                                  overflow: TextOverflow.ellipsis,
                                                  style: GoogleFonts.inter(
                                                    fontSize: 13,
                                                    fontWeight: FontWeight.w600,
                                                    color: isDark ? Colors.white : const Color(0xFF0F172A),
                                                  ),
                                                ),
                                              ),
                                              if (isLastWatched) ...[
                                                const SizedBox(width: 6),
                                                Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                  decoration: BoxDecoration(
                                                    color: AppColors.primary,
                                                    borderRadius: BorderRadius.circular(6),
                                                  ),
                                                  child: Row(
                                                    mainAxisSize: MainAxisSize.min,
                                                    children: [
                                                      const Icon(Icons.play_arrow_rounded, size: 10, color: Colors.white),
                                                      const SizedBox(width: 2),
                                                      Text(
                                                        'Last Watched',
                                                        style: GoogleFonts.inter(
                                                          fontSize: 9,
                                                          fontWeight: FontWeight.w800,
                                                          color: Colors.white,
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                              ],
                                            ],
                                          ),
                                          const SizedBox(height: 4),
                                          Row(
                                            children: [
                                              if (lesson.duration != null) ...[
                                                Text(
                                                  DurationFormatter.formatHoursMinutes(lesson.duration),
                                                  style: GoogleFonts.inter(
                                                    fontSize: 11,
                                                    fontWeight: FontWeight.w500,
                                                    color: AppColors.primary,
                                                  ),
                                                ),
                                                const SizedBox(width: 6),
                                              ],
                                              if (isCompleted)
                                                Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                                                  decoration: BoxDecoration(
                                                    color: const Color(0xFF059669).withValues(alpha: 0.12),
                                                    borderRadius: BorderRadius.circular(4),
                                                  ),
                                                  child: Text(
                                                    'Finished',
                                                    style: GoogleFonts.inter(
                                                      fontSize: 10,
                                                      fontWeight: FontWeight.w700,
                                                      color: const Color(0xFF059669),
                                                    ),
                                                  ),
                                                )
                                              else if (progressPct > 0)
                                                Text(
                                                  '• $progressPct% watched',
                                                  style: GoogleFonts.inter(
                                                    fontSize: 10,
                                                    fontWeight: FontWeight.w600,
                                                    color: AppColors.primary,
                                                  ),
                                                ),
                                            ],
                                          ),
                                          if (!isCompleted && progressFrac > 0) ...[
                                            const SizedBox(height: 5),
                                            ClipRRect(
                                              borderRadius: BorderRadius.circular(2),
                                              child: LinearProgressIndicator(
                                                value: progressFrac,
                                                minHeight: 3,
                                                backgroundColor: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
                                                valueColor: const AlwaysStoppedAnimation<Color>(AppColors.primary),
                                              ),
                                            ),
                                          ],
                                        ],
                                      ),
                                    ),

                                    // Download Button
                                    Builder(
                                      builder: (ctx) {
                                        final task = downloadProvider.getTask(course.id, lesson.id);
                                        final isDl = downloadProvider.isDownloaded(course.id, lesson.id);

                                        if (task != null && task.isDownloading) {
                                          return Padding(
                                            padding: const EdgeInsets.symmetric(horizontal: 8),
                                            child: SizedBox(
                                              width: 18,
                                              height: 18,
                                              child: CircularProgressIndicator(
                                                value: task.progress > 0 ? task.progress : null,
                                                strokeWidth: 2,
                                                color: AppColors.primary,
                                              ),
                                            ),
                                          );
                                        } else if (isDl) {
                                          return IconButton(
                                            icon: const Icon(
                                              Icons.download_done_rounded,
                                              color: Color(0xFF10B981),
                                              size: 20,
                                            ),
                                            tooltip: 'Offline Ready',
                                            onPressed: () {
                                              ToastUtils.showSnackBar(context, 'Lecture is available offline');
                                            },
                                          );
                                        } else {
                                          return IconButton(
                                            icon: Icon(
                                              Icons.download_rounded,
                                              color: isDark ? const Color(0xFF64748B) : const Color(0xFF94A3B8),
                                              size: 20,
                                            ),
                                            tooltip: 'Download Offline',
                                            onPressed: () {
                                              downloadProvider.startDownload(
                                                course: course,
                                                lesson: lesson,
                                                userPhone: authProvider.phoneNumber,
                                              );
                                              ToastUtils.showSnackBar(
                                                context,
                                                'Downloading "${lesson.title}"...',
                                                isSuccess: true,
                                              );
                                            },
                                          );
                                        }
                                      },
                                    ),

                                    // Bookmark Toggle Button
                                    IconButton(
                                      icon: Icon(
                                        isBookmarked ? Icons.bookmark_rounded : Icons.bookmark_border_rounded,
                                        color: isBookmarked
                                            ? AppColors.primary
                                            : (isDark ? const Color(0xFF64748B) : const Color(0xFF94A3B8)),
                                        size: 20,
                                      ),
                                      onPressed: () {
                                        bookmarkProvider.toggleBookmark(
                                          courseId: course.id,
                                          lessonId: lesson.id,
                                          title: lesson.title,
                                          courseTitle: course.title,
                                          duration: lesson.duration,
                                        );
                                      },
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                  },
                ),
            ] else ...[
              // Tab Content 2: Notes & Documents
              if (currentModule.notes.isEmpty)
                Container(
                  padding: const EdgeInsets.all(32),
                  alignment: Alignment.center,
                  child: Text(
                    'No study notes or documents in this module.',
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                    ),
                  ),
                )
              else
                ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: currentModule.notes.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    final note = currentModule.notes[index];
                    return Container(
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF131D31) : Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: isDark ? const Color(0xFF22324E) : const Color(0xFFE2E8F0),
                        ),
                      ),
                      child: Material(
                        color: Colors.transparent,
                        borderRadius: BorderRadius.circular(16),
                        child: InkWell(
                          onTap: () => _handleDownloadNote(note, course),
                          borderRadius: BorderRadius.circular(16),
                          child: Padding(
                            padding: const EdgeInsets.all(14),
                            child: Row(
                        children: [
                          Container(
                            width: 38,
                            height: 38,
                            decoration: BoxDecoration(
                              color: isDark
                                  ? const Color(0xFFEF4444).withValues(alpha: 0.15)
                                  : const Color(0xFFFEE2E2),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(Icons.picture_as_pdf_rounded, color: Color(0xFFEF4444), size: 20),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  note.displayName,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: GoogleFonts.inter(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: isDark ? Colors.white : const Color(0xFF0F172A),
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  DurationFormatter.formatFileSize(note.size ?? 3145728),
                                  style: GoogleFonts.inter(
                                    fontSize: 11,
                                    color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Builder(
                            builder: (ctx) {
                              final task = downloadProvider.getTask(course.id, note.id, 'note');
                              final isDl = downloadProvider.isDownloaded(course.id, note.id, 'note');

                              if (task != null && task.isDownloading) {
                                final pct = (task.progress * 100).toInt();
                                return Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF10B981).withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const SizedBox(
                                        width: 12,
                                        height: 12,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: Color(0xFF10B981),
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                      Text(
                                        '$pct%',
                                        style: GoogleFonts.inter(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w700,
                                          color: const Color(0xFF10B981),
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              } else if (task != null && task.error != null) {
                                return IconButton(
                                  icon: const Icon(Icons.error_outline_rounded, size: 20, color: Color(0xFFEF4444)),
                                  tooltip: 'Download error: ${task.error}',
                                  onPressed: () {
                                    ToastUtils.showSnackBar(context, task.error ?? 'Download failed. Please check connection.', isError: true);
                                  },
                                );
                              } else if (isDl) {
                                return IconButton(
                                  icon: const Icon(Icons.open_in_new_rounded, size: 20, color: Color(0xFF10B981)),
                                  tooltip: 'Open offline note',
                                  onPressed: () => _handleDownloadNote(note, course),
                                );
                              } else {
                                return IconButton(
                                  icon: const Icon(Icons.download_rounded, size: 20, color: AppColors.primary),
                                  tooltip: 'Download offline',
                                  onPressed: () => _handleDownloadNote(note, course),
                                );
                              }
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
            ],
          ],
          const SizedBox(height: 40),
        ],
      ),
    ),
  );
  }
}
