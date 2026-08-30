import 'dart:io';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:open_filex/open_filex.dart';
import 'package:provider/provider.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/toast_utils.dart';
import '../../../data/models/download_model.dart';
import '../../../providers/course_provider.dart';
import '../../../providers/download_provider.dart';
import '../player/youtube_video_player_screen.dart';
import 'offline_note_viewer_screen.dart';

class DownloadsScreen extends StatefulWidget {
  const DownloadsScreen({super.key});

  @override
  State<DownloadsScreen> createState() => _DownloadsScreenState();
}

class _DownloadsScreenState extends State<DownloadsScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  int _activeTab = 0; // 0 = Videos, 1 = Notes & Documents

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  String _formatFileSize(int bytes) {
    if (bytes <= 0) return '0 KB';
    final mb = bytes / (1024 * 1024);
    if (mb < 1.0) {
      final kb = bytes / 1024;
      return '${kb.toStringAsFixed(0)} KB';
    }
    if (mb < 1000) {
      return '${mb.toStringAsFixed(1)} MB';
    }
    final gb = mb / 1024;
    return '${gb.toStringAsFixed(2)} GB';
  }

  Future<void> _openDownloadedNote(BuildContext context, DownloadModel item) async {
    final file = File(item.localPath);
    if (file.existsSync()) {
      try {
        final result = await OpenFilex.open(item.localPath, type: 'application/pdf');
        if (result.type != ResultType.done) {
          if (context.mounted) {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => OfflineNoteViewerScreen(download: item),
              ),
            );
          }
        }
      } catch (_) {
        if (context.mounted) {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => OfflineNoteViewerScreen(download: item),
            ),
          );
        }
      }
    } else {
      if (context.mounted) {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => OfflineNoteViewerScreen(download: item),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final downloadProvider = context.watch<DownloadProvider>();
    final courseProvider = context.watch<CourseProvider>();

    final allDownloads = downloadProvider.downloads;
    final allVideos = downloadProvider.downloadedVideos;
    final allNotes = downloadProvider.downloadedNotes;
    final activeVideoTasks = downloadProvider.activeVideoTasks;
    final activeNoteTasks = downloadProvider.activeNoteTasks;

    final filteredVideos = _searchQuery.isEmpty
        ? allVideos
        : allVideos.where((d) => d.title.toLowerCase().contains(_searchQuery.toLowerCase())).toList();

    final filteredNotes = _searchQuery.isEmpty
        ? allNotes
        : allNotes.where((d) => d.title.toLowerCase().contains(_searchQuery.toLowerCase())).toList();

    final totalBytes = allDownloads.fold<int>(0, (sum, d) => sum + d.fileSize);

    return Scaffold(
      backgroundColor: isDark ? AppColors.darkBg : AppColors.lightBg,
      body: SafeArea(
        child: Column(
          children: [
            // Top Header
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Offline Downloads',
                            style: GoogleFonts.inter(
                              fontSize: 22,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.5,
                              color: isDark ? Colors.white : const Color(0xFF0F172A),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${allVideos.length + activeVideoTasks.length} Videos • ${allNotes.length + activeNoteTasks.length} Notes',
                            style: GoogleFonts.inter(
                              fontSize: 12,
                              color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                            ),
                          ),
                        ],
                      ),
                      if (allDownloads.isNotEmpty || activeVideoTasks.isNotEmpty || activeNoteTasks.isNotEmpty)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: AppColors.primary.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: AppColors.primary.withValues(alpha: 0.2)),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.sd_storage_rounded, size: 14, color: AppColors.primary),
                              const SizedBox(width: 5),
                              Text(
                                _formatFileSize(totalBytes),
                                style: GoogleFonts.inter(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.primary,
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 14),

                  // Segmented Tabs: Videos / Notes & Documents
                  Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF131D31) : const Color(0xFFE2E8F0),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: InkWell(
                            onTap: () => setState(() => _activeTab = 0),
                            borderRadius: BorderRadius.circular(10),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 150),
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              decoration: BoxDecoration(
                                color: _activeTab == 0
                                    ? (isDark ? const Color(0xFF1E293B) : Colors.white)
                                    : Colors.transparent,
                                borderRadius: BorderRadius.circular(10),
                                boxShadow: _activeTab == 0
                                    ? [
                                        BoxShadow(
                                          color: Colors.black.withValues(alpha: isDark ? 0.25 : 0.05),
                                          blurRadius: 4,
                                        ),
                                      ]
                                    : [],
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.play_circle_filled_rounded,
                                    size: 16,
                                    color: _activeTab == 0 ? AppColors.primary : const Color(0xFF94A3B8),
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    'Videos (${allVideos.length + activeVideoTasks.length})',
                                    style: GoogleFonts.inter(
                                      fontSize: 12,
                                      fontWeight: _activeTab == 0 ? FontWeight.w700 : FontWeight.w500,
                                      color: _activeTab == 0
                                          ? (isDark ? Colors.white : const Color(0xFF0F172A))
                                          : const Color(0xFF94A3B8),
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
                            borderRadius: BorderRadius.circular(10),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 150),
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              decoration: BoxDecoration(
                                color: _activeTab == 1
                                    ? (isDark ? const Color(0xFF1E293B) : Colors.white)
                                    : Colors.transparent,
                                borderRadius: BorderRadius.circular(10),
                                boxShadow: _activeTab == 1
                                    ? [
                                        BoxShadow(
                                          color: Colors.black.withValues(alpha: isDark ? 0.25 : 0.05),
                                          blurRadius: 4,
                                        ),
                                      ]
                                    : [],
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.description_rounded,
                                    size: 16,
                                    color: _activeTab == 1 ? const Color(0xFF10B981) : const Color(0xFF94A3B8),
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    'Notes (${allNotes.length + activeNoteTasks.length})',
                                    style: GoogleFonts.inter(
                                      fontSize: 12,
                                      fontWeight: _activeTab == 1 ? FontWeight.w700 : FontWeight.w500,
                                      color: _activeTab == 1
                                          ? (isDark ? Colors.white : const Color(0xFF0F172A))
                                          : const Color(0xFF94A3B8),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Search Bar
                  if (allDownloads.isNotEmpty || activeVideoTasks.isNotEmpty || activeNoteTasks.isNotEmpty)
                    TextField(
                      controller: _searchController,
                      onChanged: (val) => setState(() => _searchQuery = val.trim()),
                      style: GoogleFonts.inter(fontSize: 13),
                      decoration: InputDecoration(
                        hintText: _activeTab == 0 ? 'Search videos...' : 'Search notes & PDFs...',
                        hintStyle: GoogleFonts.inter(
                          fontSize: 13,
                          color: isDark ? const Color(0xFF64748B) : const Color(0xFF94A3B8),
                        ),
                        prefixIcon: const Icon(Icons.search, size: 18),
                        suffixIcon: _searchQuery.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear, size: 16),
                                onPressed: () {
                                  _searchController.clear();
                                  setState(() => _searchQuery = '');
                                },
                              )
                            : null,
                        filled: true,
                        fillColor: isDark ? const Color(0xFF131D31) : Colors.white,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(
                            color: isDark ? const Color(0xFF22324E) : const Color(0xFFCBD5E1),
                          ),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(
                            color: isDark ? const Color(0xFF22324E) : const Color(0xFFCBD5E1),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),

            // Downloads List View
            Expanded(
              child: _activeTab == 0
                  ? _buildVideosList(
                      context: context,
                      videos: filteredVideos,
                      activeTasks: activeVideoTasks,
                      courseProvider: courseProvider,
                      downloadProvider: downloadProvider,
                      isDark: isDark,
                    )
                  : _buildNotesList(
                      context: context,
                      notes: filteredNotes,
                      activeTasks: activeNoteTasks,
                      courseProvider: courseProvider,
                      downloadProvider: downloadProvider,
                      isDark: isDark,
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildVideosList({
    required BuildContext context,
    required List<DownloadModel> videos,
    required List<DownloadTask> activeTasks,
    required CourseProvider courseProvider,
    required DownloadProvider downloadProvider,
    required bool isDark,
  }) {
    if (videos.isEmpty && activeTasks.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 76,
                height: 76,
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.smart_display_rounded,
                  size: 38,
                  color: isDark ? const Color(0xFF64748B) : const Color(0xFF94A3B8),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                _searchQuery.isNotEmpty ? 'No matching downloaded videos' : 'No offline videos downloaded yet',
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: isDark ? Colors.white : const Color(0xFF0F172A),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _searchQuery.isNotEmpty
                    ? 'Try searching with different keywords.'
                    : 'Tap the Download button on any lecture to watch offline with zero data consumption.',
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(
                  fontSize: 12,
                  height: 1.4,
                  color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      children: [
        // ── IN-PROGRESS VIDEO DOWNLOADS SECTION ──
        if (activeTasks.isNotEmpty) ...[
          Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: const BoxDecoration(
                  color: AppColors.primary,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                'Downloading (${activeTasks.length})',
                style: GoogleFonts.inter(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: isDark ? Colors.white : const Color(0xFF0F172A),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ...activeTasks.map((task) => _buildActiveTaskCard(
                task: task,
                downloadProvider: downloadProvider,
                isDark: isDark,
              )),
          const SizedBox(height: 16),
          if (videos.isNotEmpty) ...[
            Text(
              'Downloaded Videos (${videos.length})',
              style: GoogleFonts.inter(
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: isDark ? Colors.white : const Color(0xFF0F172A),
              ),
            ),
            const SizedBox(height: 10),
          ],
        ],

        // ── COMPLETED VIDEO DOWNLOADS ──
        ...videos.map((item) {
          final course = courseProvider.getCourse(item.courseId);
          final hasLocalThumb = item.thumbnailPath != null && File(item.thumbnailPath!).existsSync();

          return Container(
            margin: const EdgeInsets.only(bottom: 12),
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
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => YouTubeVideoPlayerScreen(
                        courseId: item.courseId,
                        lessonId: item.itemId,
                      ),
                    ),
                  );
                },
                borderRadius: BorderRadius.circular(16),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      // Banner Image Thumbnail
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Container(
                          width: 72,
                          height: 52,
                          decoration: BoxDecoration(
                            color: isDark ? const Color(0xFF1E293B) : const Color(0xFFEEF2FF),
                          ),
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              if (hasLocalThumb)
                                Image.file(File(item.thumbnailPath!), fit: BoxFit.cover)
                              else if (item.thumbnailUrl != null && item.thumbnailUrl!.isNotEmpty)
                                Image.network(item.thumbnailUrl!, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const SizedBox())
                              else
                                Container(
                                  color: AppColors.primary.withValues(alpha: 0.15),
                                  child: const Icon(Icons.videocam_rounded, color: AppColors.primary, size: 24),
                                ),
                              Center(
                                child: Container(
                                  width: 26,
                                  height: 26,
                                  decoration: BoxDecoration(
                                    color: Colors.black.withValues(alpha: 0.6),
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(
                                    Icons.play_arrow_rounded,
                                    color: Colors.white,
                                    size: 16,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              item.title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.inter(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: isDark ? Colors.white : const Color(0xFF0F172A),
                              ),
                            ),
                            const SizedBox(height: 4),
                            if (course != null)
                              Text(
                                course.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: GoogleFonts.inter(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w500,
                                  color: AppColors.primary,
                                ),
                              ),
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF10B981).withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    'Offline Ready',
                                    style: GoogleFonts.inter(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w600,
                                      color: const Color(0xFF10B981),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  _formatFileSize(item.fileSize),
                                  style: GoogleFonts.inter(
                                    fontSize: 11,
                                    color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete_outline_rounded, size: 20, color: Color(0xFFEF4444)),
                        tooltip: 'Delete Video',
                        onPressed: () async {
                          await downloadProvider.deleteDownload(item.courseId, item.itemId, mediaType: 'video');
                          if (context.mounted) {
                            ToastUtils.showSnackBar(context, 'Removed offline video');
                          }
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        }),
      ],
    );
  }

  Widget _buildNotesList({
    required BuildContext context,
    required List<DownloadModel> notes,
    required List<DownloadTask> activeTasks,
    required CourseProvider courseProvider,
    required DownloadProvider downloadProvider,
    required bool isDark,
  }) {
    if (notes.isEmpty && activeTasks.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 76,
                height: 76,
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.menu_book_rounded,
                  size: 38,
                  color: isDark ? const Color(0xFF64748B) : const Color(0xFF94A3B8),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                _searchQuery.isNotEmpty ? 'No matching downloaded notes' : 'No offline notes downloaded yet',
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: isDark ? Colors.white : const Color(0xFF0F172A),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _searchQuery.isNotEmpty
                    ? 'Try searching with different keywords.'
                    : 'Open any course, go to the Notes tab, and tap Download to save and open in your default PDF viewer.',
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(
                  fontSize: 12,
                  height: 1.4,
                  color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      children: [
        // ── IN-PROGRESS NOTE DOWNLOADS SECTION ──
        if (activeTasks.isNotEmpty) ...[
          Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: const BoxDecoration(
                  color: Color(0xFF10B981),
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                'Downloading Notes (${activeTasks.length})',
                style: GoogleFonts.inter(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: isDark ? Colors.white : const Color(0xFF0F172A),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ...activeTasks.map((task) => _buildActiveTaskCard(
                task: task,
                downloadProvider: downloadProvider,
                isDark: isDark,
              )),
          const SizedBox(height: 16),
          if (notes.isNotEmpty) ...[
            Text(
              'Downloaded Notes (${notes.length})',
              style: GoogleFonts.inter(
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: isDark ? Colors.white : const Color(0xFF0F172A),
              ),
            ),
            const SizedBox(height: 10),
          ],
        ],

        // ── COMPLETED NOTES ──
        ...notes.map((item) {
          final course = courseProvider.getCourse(item.courseId);

          return Container(
            margin: const EdgeInsets.only(bottom: 12),
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
                onTap: () => _openDownloadedNote(context, item),
                borderRadius: BorderRadius.circular(16),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      Container(
                        width: 52,
                        height: 52,
                        decoration: BoxDecoration(
                          color: isDark
                              ? const Color(0xFFEF4444).withValues(alpha: 0.15)
                              : const Color(0xFFFEE2E2),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Center(
                          child: Icon(
                            Icons.picture_as_pdf_rounded,
                            color: Color(0xFFEF4444),
                            size: 26,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              item.title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.inter(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: isDark ? Colors.white : const Color(0xFF0F172A),
                              ),
                            ),
                            const SizedBox(height: 4),
                            if (course != null)
                              Text(
                                course.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: GoogleFonts.inter(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w500,
                                  color: AppColors.primary,
                                ),
                              ),
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF10B981).withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    'Tap to Open PDF',
                                    style: GoogleFonts.inter(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w600,
                                      color: const Color(0xFF10B981),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  _formatFileSize(item.fileSize),
                                  style: GoogleFonts.inter(
                                    fontSize: 11,
                                    color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.open_in_new_rounded, size: 20, color: AppColors.primary),
                        tooltip: 'Open in PDF App',
                        onPressed: () => _openDownloadedNote(context, item),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete_outline_rounded, size: 20, color: Color(0xFFEF4444)),
                        tooltip: 'Delete',
                        onPressed: () async {
                          await downloadProvider.deleteDownload(item.courseId, item.itemId, mediaType: 'note');
                          if (context.mounted) {
                            ToastUtils.showSnackBar(context, 'Removed offline note');
                          }
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        }),
      ],
    );
  }

  Widget _buildActiveTaskCard({
    required DownloadTask task,
    required DownloadProvider downloadProvider,
    required bool isDark,
  }) {
    final pct = (task.progress * 100).toInt();
    final isVideo = task.mediaType == 'video';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF131D31) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: task.isPaused
              ? const Color(0xFFF59E0B).withValues(alpha: 0.5)
              : (isDark ? const Color(0xFF22324E) : const Color(0xFFCBD5E1)),
          width: task.isPaused ? 1.5 : 1.0,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.04),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // Icon Indicator
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: isVideo
                      ? AppColors.primary.withValues(alpha: 0.15)
                      : const Color(0xFF10B981).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  isVideo ? Icons.movie_outlined : Icons.picture_as_pdf_outlined,
                  color: isVideo ? AppColors.primary : const Color(0xFF10B981),
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),

              // Title and Course
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      task.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: isDark ? Colors.white : const Color(0xFF0F172A),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      task.course.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                      ),
                    ),
                  ],
                ),
              ),

              // Play / Pause Button
              IconButton(
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                icon: Icon(
                  task.isPaused ? Icons.play_circle_fill_rounded : Icons.pause_circle_filled_rounded,
                  color: task.isPaused ? AppColors.primary : const Color(0xFFF59E0B),
                  size: 32,
                ),
                tooltip: task.isPaused ? 'Resume Download' : 'Pause Download',
                onPressed: () {
                  if (task.isPaused) {
                    downloadProvider.resumeDownload(task.courseId, task.itemId, task.mediaType);
                  } else {
                    downloadProvider.pauseDownload(task.courseId, task.itemId, task.mediaType);
                  }
                },
              ),
              const SizedBox(width: 8),

              // Cancel / Delete Button
              IconButton(
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                icon: const Icon(
                  Icons.close_rounded,
                  color: Color(0xFFEF4444),
                  size: 24,
                ),
                tooltip: 'Cancel Download',
                onPressed: () async {
                  await downloadProvider.cancelDownload(task.courseId, task.itemId, task.mediaType);
                  if (mounted) {
                    ToastUtils.showSnackBar(context, 'Download cancelled');
                  }
                },
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Live Progress Bar
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: task.progress > 0 ? task.progress : null,
              minHeight: 6,
              backgroundColor: isDark ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0),
              valueColor: AlwaysStoppedAnimation<Color>(
                task.isPaused ? const Color(0xFFF59E0B) : (isVideo ? AppColors.primary : const Color(0xFF10B981)),
              ),
            ),
          ),
          const SizedBox(height: 8),

          // Progress status & Byte details
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(
                        color: task.isPaused
                            ? const Color(0xFFF59E0B).withValues(alpha: 0.15)
                            : (isVideo ? AppColors.primary.withValues(alpha: 0.15) : const Color(0xFF10B981).withValues(alpha: 0.15)),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        task.isPaused ? 'Paused' : '$pct%',
                        style: GoogleFonts.inter(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: task.isPaused ? const Color(0xFFF59E0B) : (isVideo ? AppColors.primary : const Color(0xFF10B981)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    if (task.isDownloading && !task.isPaused && task.speedText.isNotEmpty) ...[
                      Text(
                        task.timeRemainingText.isNotEmpty
                            ? '${task.speedText} • ${task.timeRemainingText}'
                            : task.speedText,
                        style: GoogleFonts.inter(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: AppColors.primary,
                        ),
                      ),
                    ],
                    if (task.error != null) ...[
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'Error: ${task.error}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: Colors.redAccent, fontSize: 10),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                task.totalBytes > 0
                    ? '${_formatFileSize(task.downloadedBytes)} / ${_formatFileSize(task.totalBytes)}'
                    : _formatFileSize(task.downloadedBytes),
                style: GoogleFonts.robotoMono(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
