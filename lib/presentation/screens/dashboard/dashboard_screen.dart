import 'dart:math';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/utils/duration_formatter.dart';
import '../../../core/utils/toast_utils.dart';
import '../../../data/models/course_model.dart';
import '../../../providers/auth_provider.dart';
import '../../../providers/course_provider.dart';
import '../../../providers/progress_provider.dart';
import '../../../providers/bookmark_provider.dart';
import '../../../providers/download_provider.dart';
import '../../widgets/analytics_card.dart';
import '../../widgets/course_card.dart';
import '../course/course_explorer_screen.dart';
import '../course/add_course_screen.dart';
import '../player/youtube_video_player_screen.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final TextEditingController _searchController = TextEditingController();
  late String _learnerTitle;

  @override
  void initState() {
    super.initState();
    const titles = AppConstants.learnerTitles;
    _learnerTitle = titles[Random().nextInt(titles.length)];
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  String _getGreeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good morning';
    if (hour < 18) return 'Good afternoon';
    return 'Good evening';
  }

  Future<void> _handleRefresh() async {
    final authPhone = context.read<AuthProvider>().phoneNumber;
    final courseProvider = context.read<CourseProvider>();
    final progressProvider = context.read<ProgressProvider>();

    await Future.wait([
      courseProvider.loadCourses(userPhone: authPhone),
      progressProvider.loadProgressMetrics(userPhone: authPhone),
      context.read<BookmarkProvider>().loadBookmarks(userPhone: authPhone),
      context.read<DownloadProvider>().loadDownloads(authPhone),
    ]);

    final courseIds = courseProvider.courses.map((c) => c.id).toList();
    if (courseIds.isNotEmpty) {
      await progressProvider.loadMultipleCoursesProgress(courseIds, userPhone: authPhone);
    }

    if (mounted) {
      ToastUtils.showSnackBar(context, 'Dashboard updated', isSuccess: true);
    }
  }

  Future<void> _handleSyncCourse(CourseModel course) async {
    final authPhone = context.read<AuthProvider>().phoneNumber;
    ToastUtils.showSnackBar(context, 'Syncing "${course.title}" from Telegram...', isSuccess: true);
    try {
      await context.read<CourseProvider>().syncCourse(course.id, phone: authPhone);
      if (mounted) {
        ToastUtils.showSnackBar(context, 'Successfully synchronized "${course.title}" with Telegram!', isSuccess: true);
      }
    } catch (e) {
      if (mounted) {
        ToastUtils.showSnackBar(context, 'Failed to sync course: $e', isError: true);
      }
    }
  }

  void _handleDeleteCourse(String courseId, String title) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: isDark ? const Color(0xFF131D31) : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          'Delete Course',
          style: GoogleFonts.inter(
            fontWeight: FontWeight.w700,
            fontSize: 16,
            color: isDark ? Colors.white : const Color(0xFF0F172A),
          ),
        ),
        content: Text(
          'Are you sure you want to remove "$title"? All local progress and bookmarks for this course will be deleted.',
          style: GoogleFonts.inter(
            fontSize: 13,
            color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
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
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () async {
              Navigator.pop(ctx);
              await context.read<CourseProvider>().deleteCourse(courseId);
              if (mounted) {
                ToastUtils.showSnackBar(context, 'Course removed', isSuccess: true);
              }
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final courseProvider = context.watch<CourseProvider>();
    final progressProvider = context.watch<ProgressProvider>();
    final bookmarkProvider = context.watch<BookmarkProvider>();

    final courses = courseProvider.courses;
    final metrics = progressProvider.metrics;
    final continueWatching = progressProvider.continueWatching;

    return RefreshIndicator(
      onRefresh: _handleRefresh,
      color: AppColors.primary,
      backgroundColor: isDark ? const Color(0xFF131D31) : Colors.white,
      child: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
        children: [
          // 1. Welcome Banner
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF131D31) : Colors.white,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: isDark ? const Color(0xFF22324E) : const Color(0xFFE2E8F0),
                width: 1,
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
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: isDark
                            ? AppColors.primary.withValues(alpha: 0.2)
                            : AppColors.primaryLight.withValues(alpha: 0.6),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: isDark
                              ? AppColors.primary.withValues(alpha: 0.4)
                              : AppColors.primaryLight,
                        ),
                      ),
                      child: Text(
                        'STUDY WORKSPACE',
                        style: GoogleFonts.inter(
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.5,
                          color: AppColors.primary,
                        ),
                      ),
                    ),
                    Row(
                      children: [
                        IconButton(
                          onPressed: _handleRefresh,
                          icon: const Icon(Icons.refresh, size: 18),
                          tooltip: 'Refresh Dashboard',
                          style: IconButton.styleFrom(
                            backgroundColor: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            padding: const EdgeInsets.all(6),
                            minimumSize: const Size(34, 34),
                          ),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton.icon(
                          onPressed: () {
                            Navigator.of(context).push(
                              MaterialPageRoute(builder: (_) => const AddCourseScreen()),
                            );
                          },
                          icon: const Icon(Icons.add, size: 16),
                          label: Text(
                            'Import',
                            style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            foregroundColor: Colors.white,
                            elevation: 0,
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            minimumSize: const Size(34, 34),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                RichText(
                  text: TextSpan(
                    style: GoogleFonts.inter(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.5,
                      color: isDark ? Colors.white : const Color(0xFF0F172A),
                    ),
                    children: [
                      TextSpan(text: '${_getGreeting()}, '),
                      TextSpan(
                        text: _learnerTitle,
                        style: const TextStyle(color: AppColors.primary),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Track your daily study streak, resume lectures, and explore offline courses.',
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    height: 1.4,
                    color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // 2. Study Analytics Grid
          Text(
            'STUDY PROGRESS OVERVIEW',
            style: GoogleFonts.inter(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
              color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
            ),
          ),
          const SizedBox(height: 12),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            childAspectRatio: 2.1,
            children: [
              AnalyticsCard(
                label: 'Total Hours',
                value: metrics.totalHours.toStringAsFixed(1),
                unit: 'hrs',
                icon: Icons.access_time_filled_rounded,
                iconColor: AppColors.primary,
                iconBgColor: isDark
                    ? AppColors.primary.withValues(alpha: 0.2)
                    : AppColors.primaryLight.withValues(alpha: 0.6),
              ),
              AnalyticsCard(
                label: 'Today',
                value: metrics.hoursToday.toStringAsFixed(1),
                unit: 'hrs',
                icon: Icons.today_rounded,
                iconColor: AppColors.accentSky,
                iconBgColor: isDark
                    ? AppColors.accentSky.withValues(alpha: 0.2)
                    : const Color(0xFFE0F2FE),
              ),
              AnalyticsCard(
                label: 'Daily Streak',
                value: '${metrics.streakDays}',
                unit: 'days',
                icon: Icons.local_fire_department_rounded,
                iconColor: const Color(0xFFF97316),
                iconBgColor: isDark
                    ? const Color(0xFFF97316).withValues(alpha: 0.2)
                    : const Color(0xFFFFEDD5),
              ),
              AnalyticsCard(
                label: 'Saved Bookmarks',
                value: '${bookmarkProvider.count}',
                unit: 'items',
                icon: Icons.bookmark_rounded,
                iconColor: AppColors.accentEmerald,
                iconBgColor: isDark
                    ? AppColors.accentEmerald.withValues(alpha: 0.2)
                    : const Color(0xFFD1FAE5),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // 3. Continue Watching Shelf (if available)
          if (continueWatching != null) ...[
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'CONTINUE WATCHING',
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.5,
                    color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                  ),
                ),
                Text(
                  '${continueWatching.completionPercentage.toInt()}% Watched',
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: AppColors.primary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF131D31) : Colors.white,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: isDark ? const Color(0xFF22324E) : const Color(0xFFE2E8F0),
                  width: 1,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: isDark ? 0.25 : 0.04),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Material(
                color: Colors.transparent,
                borderRadius: BorderRadius.circular(20),
                child: InkWell(
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => YouTubeVideoPlayerScreen(
                          courseId: continueWatching.courseId,
                          lessonId: continueWatching.lessonId,
                          autoPlay: true,
                          fromDashboard: true,
                        ),
                      ),
                    );
                  },
                  borderRadius: BorderRadius.circular(20),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        // Thumbnail or Play Icon Container
                        Container(
                          width: 64,
                          height: 64,
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [AppColors.primary, Color(0xFF1D4ED8)],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: const Icon(
                            Icons.play_arrow_rounded,
                            color: Colors.white,
                            size: 32,
                          ),
                        ),
                        const SizedBox(width: 14),

                        // Title and Progress info
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                continueWatching.courseTitle,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: GoogleFonts.inter(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.primary,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                continueWatching.lessonTitle,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: GoogleFonts.inter(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                  color: isDark ? Colors.white : const Color(0xFF0F172A),
                                ),
                              ),
                              const SizedBox(height: 8),

                              // Progress bar
                              ClipRRect(
                                borderRadius: BorderRadius.circular(999),
                                child: LinearProgressIndicator(
                                  value: (continueWatching.completionPercentage / 100.0).clamp(0.0, 1.0),
                                  minHeight: 4,
                                  backgroundColor: isDark ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0),
                                  valueColor: const AlwaysStoppedAnimation<Color>(AppColors.primary),
                                ),
                              ),
                              const SizedBox(height: 6),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    'Resumes at ${DurationFormatter.formatTimestamp(continueWatching.progressSeconds)}',
                                    style: GoogleFonts.inter(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w500,
                                      color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                                    ),
                                  ),
                                  Text(
                                    DurationFormatter.formatTimestamp(continueWatching.durationSeconds),
                                    style: GoogleFonts.inter(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w500,
                                      color: isDark ? const Color(0xFF64748B) : const Color(0xFF94A3B8),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 24),
          ],

          // 4. Course Catalog Header & Search
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'MY COURSES (${courses.length})',
                style: GoogleFonts.inter(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.5,
                  color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Search Bar
          TextField(
            controller: _searchController,
            onChanged: (val) => courseProvider.setSearchQuery(val),
            style: GoogleFonts.inter(fontSize: 13),
            decoration: InputDecoration(
              hintText: 'Search your courses...',
              prefixIcon: const Icon(Icons.search, size: 18),
              suffixIcon: _searchController.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear, size: 16),
                      onPressed: () {
                        _searchController.clear();
                        courseProvider.setSearchQuery('');
                      },
                    )
                  : null,
              filled: true,
              fillColor: isDark ? const Color(0xFF131D31) : Colors.white,
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(
                  color: isDark ? const Color(0xFF22324E) : const Color(0xFFE2E8F0),
                ),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(
                  color: isDark ? const Color(0xFF22324E) : const Color(0xFFE2E8F0),
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Courses List
          if (courses.isEmpty)
            Container(
              padding: const EdgeInsets.all(32),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF131D31) : Colors.white,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: isDark ? const Color(0xFF22324E) : const Color(0xFFE2E8F0),
                ),
              ),
              child: Column(
                children: [
                  Icon(
                    Icons.school_outlined,
                    size: 48,
                    color: isDark ? const Color(0xFF64748B) : const Color(0xFF94A3B8),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'No Courses Found',
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: isDark ? Colors.white : const Color(0xFF0F172A),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Import a Telegram channel or forum group to start learning.',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                    ),
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const AddCourseScreen()),
                      );
                    },
                    icon: const Icon(Icons.add, size: 16),
                    label: const Text('Import Course'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ],
              ),
            )
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: courses.length,
              separatorBuilder: (_, __) => const SizedBox(height: 14),
              itemBuilder: (context, index) {
                final course = courses[index];
                return CourseCard(
                  course: course,
                  gradientIndex: index,
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => CourseExplorerScreen(courseId: course.id),
                      ),
                    );
                  },
                  onDelete: () => _handleDeleteCourse(course.id, course.title),
                  onSync: () => _handleSyncCourse(course),
                );
              },
            ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}
