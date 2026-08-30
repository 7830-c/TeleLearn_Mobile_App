import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_theme.dart';
import '../../data/models/course_model.dart';
import '../../providers/progress_provider.dart';

class CourseCard extends StatelessWidget {
  final CourseModel course;
  final int gradientIndex;
  final VoidCallback onTap;
  final VoidCallback onDelete;
  final VoidCallback onSync;

  const CourseCard({
    super.key,
    required this.course,
    required this.gradientIndex,
    required this.onTap,
    required this.onDelete,
    required this.onSync,
  });

  static const List<List<Color>> _webCardGradients = [
    [Color(0xFF2563EB), Color(0xFF4338CA)], // Blue to Indigo
    [Color(0xFF1E293B), Color(0xFF090D16)], // Slate to Deep Black
    [Color(0xFF4F46E5), Color(0xFF1E40AF)], // Indigo to Royal Blue
    [Color(0xFF1D4ED8), Color(0xFF0F172A)], // Blue to Dark Slate
    [Color(0xFF0284C7), Color(0xFF3730A3)], // Sky to Indigo
    [Color(0xFF0F172A), Color(0xFF1E3A8A)], // Slate to Deep Navy
  ];

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final progressProvider = context.watch<ProgressProvider>();

    final completionPct = progressProvider.getCourseCompletionPercentage(
      course.id,
      course.totalLessons,
    );
    final totalNotes = course.modules.fold<int>(0, (sum, m) => sum + m.notes.length);
    final completedCount = progressProvider.getCourseCompletedCount(course.id);

    final gradient = _webCardGradients[gradientIndex % _webCardGradients.length];
    final initialLetter = (course.title.isNotEmpty ? course.title[0] : 'C').toUpperCase();

    return Container(
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
          onTap: onTap,
          borderRadius: BorderRadius.circular(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── CARD HEADER BANNER (Matching Web TeleLearn Portal) ──
              Container(
                height: 110,
                width: double.infinity,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: gradient,
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(19),
                    topRight: Radius.circular(19),
                  ),
                ),
                child: Stack(
                  children: [
                    // Stylized Watermark Initial on Right (Web Parity)
                    Positioned(
                      right: 14,
                      bottom: -10,
                      child: Text(
                        initialLetter,
                        style: GoogleFonts.inter(
                          fontSize: 68,
                          fontWeight: FontWeight.w900,
                          color: Colors.white.withValues(alpha: 0.12),
                          letterSpacing: -2,
                        ),
                      ),
                    ),

                    // Content inside Banner
                    Padding(
                      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          // Top Row: Channel Badge & Action Buttons
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
                                decoration: BoxDecoration(
                                  color: Colors.black.withValues(alpha: 0.35),
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
                                ),
                                child: Text(
                                  'Channel ${course.channelId}',
                                  style: GoogleFonts.inter(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                              Row(
                                children: [
                                  InkWell(
                                    onTap: onSync,
                                    borderRadius: BorderRadius.circular(8),
                                    child: Container(
                                      padding: const EdgeInsets.all(5),
                                      decoration: BoxDecoration(
                                        color: Colors.black.withValues(alpha: 0.3),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: const Icon(Icons.refresh_rounded, size: 15, color: Colors.white),
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  InkWell(
                                    onTap: onDelete,
                                    borderRadius: BorderRadius.circular(8),
                                    child: Container(
                                      padding: const EdgeInsets.all(5),
                                      decoration: BoxDecoration(
                                        color: Colors.black.withValues(alpha: 0.3),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: const Icon(Icons.delete_outline_rounded, size: 15, color: Colors.white),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),

                          // Course Title at bottom of banner
                          Text(
                            course.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.inter(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              // ── CARD BODY STATS & PROGRESS ──
              Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Stats Row (Lectures, Notes, Modules)
                    Row(
                      children: [
                        Text(
                          '${course.totalLessons} Lectures',
                          style: GoogleFonts.inter(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: isDark ? Colors.white : const Color(0xFF0F172A),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '•',
                          style: TextStyle(color: isDark ? const Color(0xFF475569) : const Color(0xFFCBD5E1)),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '$totalNotes Notes',
                          style: GoogleFonts.inter(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '•',
                          style: TextStyle(color: isDark ? const Color(0xFF475569) : const Color(0xFFCBD5E1)),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '${course.modules.length} Modules',
                          style: GoogleFonts.inter(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    // Progress Bar Header
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Course Progress',
                          style: GoogleFonts.inter(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                          ),
                        ),
                        Text(
                          completionPct >= 100
                              ? '$completedCount / ${course.totalLessons} (Completed)'
                              : '$completedCount / ${course.totalLessons} (${completionPct.toInt()}%)',
                          style: GoogleFonts.inter(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: completionPct >= 100 ? const Color(0xFF10B981) : AppColors.primary,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),

                    // Progress Bar
                    ClipRRect(
                      borderRadius: BorderRadius.circular(999),
                      child: LinearProgressIndicator(
                        value: (completionPct / 100.0).clamp(0.0, 1.0),
                        minHeight: 5,
                        backgroundColor: isDark ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0),
                        valueColor: AlwaysStoppedAnimation<Color>(
                          completionPct >= 100 ? const Color(0xFF10B981) : AppColors.primary,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Footer Link: Open Course
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Open Course',
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: AppColors.primary,
                          ),
                        ),
                        const Icon(
                          Icons.chevron_right_rounded,
                          size: 18,
                          color: AppColors.primary,
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
    );
  }
}
