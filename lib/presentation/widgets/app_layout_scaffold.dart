import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/theme/app_theme.dart';
import '../../providers/theme_provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/course_provider.dart';
import '../../providers/progress_provider.dart';
import '../../providers/bookmark_provider.dart';
import '../../providers/download_provider.dart';
import '../screens/dashboard/dashboard_screen.dart';
import '../screens/course/add_course_screen.dart';
import '../screens/downloads/downloads_screen.dart';
import '../screens/bookmarks/bookmarks_screen.dart';
import '../screens/auth/login_screen.dart';
import '../../data/services/app_update_service.dart';

class AppLayoutScaffold extends StatefulWidget {
  final int initialTabIndex;

  const AppLayoutScaffold({
    super.key,
    this.initialTabIndex = 0,
  });

  @override
  State<AppLayoutScaffold> createState() => _AppLayoutScaffoldState();
}

class _AppLayoutScaffoldState extends State<AppLayoutScaffold> {
  late int _currentIndex;
  int _lastSeenDownloadCount = 0;
  int _lastSeenBookmarkCount = 0;

  final List<Widget> _pages = const [
    DashboardScreen(),
    AddCourseScreen(),
    DownloadsScreen(),
    BookmarksScreen(),
  ];

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialTabIndex;
    _loadSeenBadgeState();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final phone = context.read<AuthProvider>().phoneNumber;
      if (phone.isNotEmpty) {
        context.read<CourseProvider>().loadCourses(userPhone: phone);
        context.read<ProgressProvider>().loadProgressMetrics(userPhone: phone);
        context.read<BookmarkProvider>().loadBookmarks(userPhone: phone);
        context.read<DownloadProvider>().loadDownloads(phone);
      }
      // Check for updates (rate-limited to max once per 24 hours)
      AppUpdateService.checkForUpdate(context, manual: false);
    });
  }

  Future<void> _loadSeenBadgeState() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (mounted) {
        setState(() {
          _lastSeenDownloadCount = prefs.getInt('last_seen_dl_count') ?? 0;
          _lastSeenBookmarkCount = prefs.getInt('last_seen_bm_count') ?? 0;
        });
      }
    } catch (_) {}
  }

  Future<void> _onTabSelected(int index) async {
    final dlCount = context.read<DownloadProvider>().downloads.length;
    final bmCount = context.read<BookmarkProvider>().bookmarks.length;

    setState(() {
      _currentIndex = index;
      if (index == 0) {
        final phone = context.read<AuthProvider>().phoneNumber;
        if (phone.isNotEmpty) {
          context.read<ProgressProvider>().loadProgressMetrics(userPhone: phone);
        }
      } else if (index == 1) {
        final phone = context.read<AuthProvider>().phoneNumber;
        if (phone.isNotEmpty) {
          context.read<CourseProvider>().loadAvailableChannels(phone: phone);
        }
      } else if (index == 2) {
        _lastSeenDownloadCount = dlCount;
      } else if (index == 3) {
        _lastSeenBookmarkCount = bmCount;
      }
    });

    try {
      final prefs = await SharedPreferences.getInstance();
      if (index == 2) {
        await prefs.setInt('last_seen_dl_count', dlCount);
      } else if (index == 3) {
        await prefs.setInt('last_seen_bm_count', bmCount);
      }
    } catch (_) {}
  }

  void _showLogoutDialog() {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: isDark ? const Color(0xFF131D31) : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          'Log Out',
          style: GoogleFonts.inter(
            fontWeight: FontWeight.w700,
            fontSize: 16,
            color: isDark ? Colors.white : const Color(0xFF0F172A),
          ),
        ),
        content: Text(
          'Are you sure you want to log out of TeleLearn?',
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
              context.read<CourseProvider>().clearForUser();
              context.read<ProgressProvider>().clearForUser();
              context.read<BookmarkProvider>().clearForUser();
              context.read<DownloadProvider>().clearForUser();
              await context.read<AuthProvider>().logout();
              if (mounted) {
                Navigator.of(context).pushAndRemoveUntil(
                  MaterialPageRoute(builder: (_) => const LoginScreen()),
                  (route) => false,
                );
              }
            },
            child: const Text('Log Out'),
          ),
        ],
      ),
    );
  }

  void _showUserProfileSheet(BuildContext context, String phone, bool isDark) {
    showModalBottomSheet(
      context: context,
      backgroundColor: isDark ? const Color(0xFF131D31) : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF334155) : const Color(0xFFCBD5E1),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 20),
              const CircleAvatar(
                radius: 28,
                backgroundColor: AppColors.primary,
                child: Icon(Icons.person_rounded, size: 30, color: Colors.white),
              ),
              const SizedBox(height: 12),
              Text(
                phone.isNotEmpty ? phone : 'Telegram User',
                style: GoogleFonts.inter(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: isDark ? Colors.white : const Color(0xFF0F172A),
                ),
              ),
              const SizedBox(height: 4),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.verified_user_rounded, color: Color(0xFF10B981), size: 14),
                  const SizedBox(width: 5),
                  Text(
                    'Active Telegram MTProto Session',
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      color: const Color(0xFF10B981),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              const Divider(),
              const SizedBox(height: 8),

              // Check for Updates Tile
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.system_update_rounded, color: AppColors.primary, size: 20),
                ),
                title: Text(
                  'Check for Updates',
                  style: GoogleFonts.inter(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                    color: isDark ? Colors.white : const Color(0xFF0F172A),
                  ),
                ),
                subtitle: Text(
                  'Check GitHub Releases for new updates',
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                  ),
                ),
                trailing: const Icon(Icons.chevron_right_rounded, size: 20),
                onTap: () {
                  Navigator.pop(ctx);
                  AppUpdateService.checkForUpdate(context, manual: true);
                },
              ),
              const SizedBox(height: 6),
              const Divider(),
              const SizedBox(height: 6),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEF4444).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.logout_rounded, color: Color(0xFFEF4444), size: 20),
                ),
                title: Text(
                  'Log Out of TeleLearn',
                  style: GoogleFonts.inter(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                    color: const Color(0xFFEF4444),
                  ),
                ),
                subtitle: Text(
                  'End local session and return to login',
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                  ),
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  _showLogoutDialog();
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final themeProvider = context.watch<ThemeProvider>();
    final authProvider = context.watch<AuthProvider>();
    final bookmarkCount = context.watch<BookmarkProvider>().count;
    final downloadCount = context.watch<DownloadProvider>().count;

    final userPhone = authProvider.phoneNumber.isNotEmpty
        ? authProvider.phoneNumber
        : 'Learner';

    return Scaffold(
      backgroundColor: isDark ? AppColors.darkBg : AppColors.lightBg,
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(60),
        child: Container(
          decoration: BoxDecoration(
            color: isDark
                ? const Color(0xFF0B1120).withValues(alpha: 0.95)
                : Colors.white.withValues(alpha: 0.95),
            border: Border(
              bottom: BorderSide(
                color: isDark ? const Color(0xFF22324E) : const Color(0xFFE2E8F0),
                width: 1,
              ),
            ),
          ),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // Brand Logo & Title
                  Expanded(
                    child: InkWell(
                      onTap: () => _onTabSelected(0),
                      borderRadius: BorderRadius.circular(12),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: Image.asset(
                              'assets/logo.png',
                              width: 32,
                              height: 32,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => Container(
                                width: 32,
                                height: 32,
                                decoration: BoxDecoration(
                                  color: AppColors.primary,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: const Icon(
                                  Icons.send_rounded,
                                  color: Colors.white,
                                  size: 16,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Flexible(
                            child: RichText(
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              text: TextSpan(
                                style: GoogleFonts.inter(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: -0.5,
                                  color: isDark ? Colors.white : const Color(0xFF0F172A),
                                ),
                                children: const [
                                  TextSpan(text: 'Tele'),
                                  TextSpan(
                                    text: 'Learn',
                                    style: TextStyle(color: AppColors.primary),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  // Actions: Theme toggle & User Profile Icon Button (NO phone number on bar)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Theme Switcher Button
                      IconButton(
                        onPressed: () => themeProvider.toggleTheme(),
                        icon: Icon(
                          themeProvider.isDarkMode ? Icons.wb_sunny_outlined : Icons.nightlight_round,
                          size: 18,
                          color: themeProvider.isDarkMode ? const Color(0xFFFBBF24) : const Color(0xFF475569),
                        ),
                        tooltip: 'Toggle Theme',
                        style: IconButton.styleFrom(
                          backgroundColor: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                            side: BorderSide(
                              color: isDark ? const Color(0xFF334155) : const Color(0xFFCBD5E1),
                              width: 1,
                            ),
                          ),
                          padding: const EdgeInsets.all(8),
                          minimumSize: const Size(36, 36),
                        ),
                      ),
                      const SizedBox(width: 8),

                      // Profile Icon Button
                      IconButton(
                        onPressed: () => _showUserProfileSheet(context, userPhone, isDark),
                        icon: const Icon(Icons.person_rounded, size: 18, color: AppColors.primary),
                        tooltip: 'Profile & Account',
                        style: IconButton.styleFrom(
                          backgroundColor: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                            side: BorderSide(
                              color: isDark ? const Color(0xFF334155) : const Color(0xFFCBD5E1),
                              width: 1,
                            ),
                          ),
                          padding: const EdgeInsets.all(8),
                          minimumSize: const Size(36, 36),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
      body: IndexedStack(
        index: _currentIndex,
        children: _pages,
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: isDark
              ? const Color(0xFF0B1120).withValues(alpha: 0.95)
              : Colors.white.withValues(alpha: 0.95),
          border: Border(
            top: BorderSide(
              color: isDark ? const Color(0xFF22324E) : const Color(0xFFE2E8F0),
              width: 1,
            ),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.05),
              blurRadius: 10,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildNavItem(
                  index: 0,
                  icon: Icons.dashboard_rounded,
                  label: 'Dashboard',
                  isSelected: _currentIndex == 0,
                  isDark: isDark,
                ),
                _buildNavItem(
                  index: 1,
                  icon: Icons.add_circle_outline_rounded,
                  label: 'Add Course',
                  isSelected: _currentIndex == 1,
                  isDark: isDark,
                ),
                _buildNavItem(
                  index: 2,
                  icon: Icons.download_done_rounded,
                  label: 'Downloads',
                  badgeCount: (_currentIndex == 2 || downloadCount <= _lastSeenDownloadCount)
                      ? null
                      : (downloadCount - _lastSeenDownloadCount),
                  isSelected: _currentIndex == 2,
                  isDark: isDark,
                ),
                _buildNavItem(
                  index: 3,
                  icon: Icons.bookmark_border_rounded,
                  selectedIcon: Icons.bookmark_rounded,
                  label: 'Bookmarks',
                  badgeCount: (_currentIndex == 3 || bookmarkCount <= _lastSeenBookmarkCount)
                      ? null
                      : (bookmarkCount - _lastSeenBookmarkCount),
                  isSelected: _currentIndex == 3,
                  isDark: isDark,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNavItem({
    required int index,
    required IconData icon,
    IconData? selectedIcon,
    required String label,
    int? badgeCount,
    required bool isSelected,
    required bool isDark,
  }) {
    const activeColor = AppColors.primary;
    final inactiveColor = isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B);

    return InkWell(
      onTap: () => _onTabSelected(index),
      borderRadius: BorderRadius.circular(12),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected
              ? (isDark ? AppColors.primary.withValues(alpha: 0.15) : AppColors.primaryLight.withValues(alpha: 0.5))
              : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                Icon(
                  isSelected ? (selectedIcon ?? icon) : icon,
                  size: 22,
                  color: isSelected ? activeColor : inactiveColor,
                ),
                if (badgeCount != null && badgeCount > 0)
                  Positioned(
                    right: -8,
                    top: -4,
                    child: Container(
                      padding: const EdgeInsets.all(3),
                      decoration: const BoxDecoration(
                        color: AppColors.primary,
                        shape: BoxShape.circle,
                      ),
                      constraints: const BoxConstraints(minWidth: 14, minHeight: 14),
                      child: Text(
                        '$badgeCount',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 8,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 3),
            Text(
              label,
              style: GoogleFonts.inter(
                fontSize: 10,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                color: isSelected ? activeColor : inactiveColor,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
