import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/toast_utils.dart';
import '../../../data/services/telegram_import_service.dart';
import '../../../providers/course_provider.dart';
import '../../../providers/auth_provider.dart';
import 'course_explorer_screen.dart';

class AddCourseScreen extends StatefulWidget {
  const AddCourseScreen({super.key});

  @override
  State<AddCourseScreen> createState() => _AddCourseScreenState();
}

class _AddCourseScreenState extends State<AddCourseScreen> {
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _customChannelController = TextEditingController();
  List<TelegramChannelInfo> _channels = [];
  bool _isLoading = true;
  final Set<int> _syncingChannelIds = {};
  final Set<int> _syncedChannelIds = {};
  final Set<int> _selectedChannelIds = {};
  bool _isBatchSyncing = false;
  String? _batchStatusMessage;

  @override
  void initState() {
    super.initState();
    _loadChannels();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _customChannelController.dispose();
    super.dispose();
  }

  Future<void> _loadChannels() async {
    final phone = context.read<AuthProvider>().phoneNumber;
    setState(() => _isLoading = true);
    final list = await TelegramImportService.getAvailableChannels(phone);
    if (mounted) {
      setState(() {
        _channels = list;
        _isLoading = false;
      });
    }
  }

  bool _isAlreadyImported(TelegramChannelInfo channel, List<dynamic> existingCourses) {
    if (_syncedChannelIds.contains(channel.id)) return true;
    for (final c in existingCourses) {
      if (c.channelId == channel.id.toString() ||
          c.title.trim().toLowerCase() == channel.name.trim().toLowerCase()) {
        return true;
      }
    }
    return false;
  }

  Future<void> _handleImport(TelegramChannelInfo channel, {bool navigate = true}) async {
    final phone = context.read<AuthProvider>().phoneNumber;
    setState(() => _syncingChannelIds.add(channel.id));

    try {
      final course = await context.read<CourseProvider>().importChannel(channel, phone: phone);
      if (mounted) {
        setState(() {
          _syncedChannelIds.add(channel.id);
          _syncingChannelIds.remove(channel.id);
          _selectedChannelIds.remove(channel.id);
        });

        ToastUtils.showSnackBar(context, 'Successfully imported "${channel.name}"', isSuccess: true);
        if (navigate) {
          Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => CourseExplorerScreen(courseId: course.id)),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _syncingChannelIds.remove(channel.id));
        ToastUtils.showSnackBar(context, 'Failed to sync channel: $e', isError: true);
      }
    }
  }

  Future<void> _handleBatchImport(List<dynamic> existingCourses) async {
    if (_selectedChannelIds.isEmpty || _isBatchSyncing) return;

    final phone = context.read<AuthProvider>().phoneNumber;
    final toImport = _channels
        .where((c) => _selectedChannelIds.contains(c.id) && !_isAlreadyImported(c, existingCourses))
        .toList();

    if (toImport.isEmpty) {
      ToastUtils.showSnackBar(context, 'All selected courses are already imported');
      setState(() => _selectedChannelIds.clear());
      return;
    }

    setState(() {
      _isBatchSyncing = true;
    });

    int successfulCount = 0;
    for (int i = 0; i < toImport.length; i++) {
      final channel = toImport[i];
      if (!mounted) break;

      setState(() {
        _syncingChannelIds.add(channel.id);
        _batchStatusMessage = 'Syncing (${i + 1}/${toImport.length}): "${channel.name}"...';
      });

      try {
        await context.read<CourseProvider>().importChannel(channel, phone: phone);
        if (mounted) {
          setState(() {
            _syncedChannelIds.add(channel.id);
            _syncingChannelIds.remove(channel.id);
            _selectedChannelIds.remove(channel.id);
          });
          successfulCount++;
        }
      } catch (e) {
        debugPrint('[AddCourseScreen] Failed batch item ${channel.name}: $e');
        if (mounted) {
          setState(() => _syncingChannelIds.remove(channel.id));
        }
      }
    }

    if (mounted) {
      setState(() {
        _isBatchSyncing = false;
        _batchStatusMessage = null;
        _selectedChannelIds.clear();
      });

      ToastUtils.showSnackBar(
        context,
        'Successfully imported $successfulCount course${successfulCount == 1 ? '' : 's'}!',
        isSuccess: true,
      );
    }
  }

  Future<void> _handleCustomImport() async {
    final name = _customChannelController.text.trim();
    if (name.isEmpty) {
      ToastUtils.showSnackBar(context, 'Please enter a channel name or link', isError: true);
      return;
    }

    final customChannel = TelegramChannelInfo(
      id: DateTime.now().millisecondsSinceEpoch,
      name: name,
      isChannel: true,
      isGroup: false,
      memberCount: 5000,
      messageCount: 120,
    );

    await _handleImport(customChannel);
  }

  void _toggleChannelSelection(TelegramChannelInfo channel, bool isImported) {
    if (isImported || _isBatchSyncing) return;
    setState(() {
      if (_selectedChannelIds.contains(channel.id)) {
        _selectedChannelIds.remove(channel.id);
      } else {
        _selectedChannelIds.add(channel.id);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final existingCourses = context.watch<CourseProvider>().courses;

    final query = _searchController.text.trim().toLowerCase();
    final filteredChannels = _channels.where((c) =>
        c.name.toLowerCase().contains(query)).toList();

    final unimportedCount = filteredChannels.where((c) => !_isAlreadyImported(c, existingCourses)).length;

    return Scaffold(
      backgroundColor: isDark ? AppColors.darkBg : AppColors.lightBg,
      bottomNavigationBar: _selectedChannelIds.isNotEmpty
          ? Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF131D31) : Colors.white,
                border: Border(
                  top: BorderSide(
                    color: isDark ? const Color(0xFF22324E) : const Color(0xFFE2E8F0),
                  ),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.08),
                    blurRadius: 10,
                    offset: const Offset(0, -3),
                  ),
                ],
              ),
              child: SafeArea(
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${_selectedChannelIds.length} Channels Selected',
                            style: GoogleFonts.inter(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: isDark ? Colors.white : const Color(0xFF0F172A),
                            ),
                          ),
                          Text(
                            _batchStatusMessage ?? 'Batch import into your courses',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.inter(
                              fontSize: 11,
                              color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    ElevatedButton.icon(
                      onPressed: _isBatchSyncing ? null : () => _handleBatchImport(existingCourses),
                      icon: _isBatchSyncing
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : const Icon(Icons.download_for_offline_rounded, size: 18),
                      label: Text(
                        _isBatchSyncing ? 'Importing...' : 'Import Selected',
                        style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w700),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ],
                ),
              ),
            )
          : null,
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
        children: [
          // Header Banner
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF131D31) : Colors.white,
              borderRadius: BorderRadius.circular(24),
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
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: isDark
                            ? AppColors.primary.withValues(alpha: 0.2)
                            : AppColors.primaryLight.withValues(alpha: 0.6),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.add_to_photos_rounded, color: AppColors.primary, size: 22),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Import Telegram Courses',
                            style: GoogleFonts.inter(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              color: isDark ? Colors.white : const Color(0xFF0F172A),
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Select single or multiple Telegram channels to import video lectures, topics, and notes in batch.',
                            style: GoogleFonts.inter(
                              fontSize: 11,
                              height: 1.4,
                              color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Custom Channel Link / Username Input
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF131D31) : Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: isDark ? const Color(0xFF22324E) : const Color(0xFFE2E8F0),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'IMPORT BY CHANNEL LINK OR USERNAME',
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.5,
                    color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _customChannelController,
                        style: GoogleFonts.inter(fontSize: 13),
                        decoration: InputDecoration(
                          hintText: 'e.g. t.me/my_course or @physics_hub',
                          hintStyle: GoogleFonts.inter(
                            fontSize: 12,
                            color: isDark ? const Color(0xFF64748B) : const Color(0xFF94A3B8),
                          ),
                          prefixIcon: const Icon(Icons.link_rounded, size: 18),
                          filled: true,
                          fillColor: isDark ? const Color(0xFF0B1120) : const Color(0xFFF8FAFC),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(
                              color: isDark ? const Color(0xFF334155) : const Color(0xFFCBD5E1),
                            ),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(
                              color: isDark ? const Color(0xFF334155) : const Color(0xFFCBD5E1),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    ElevatedButton(
                      onPressed: _handleCustomImport,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      ),
                      child: Text(
                        'Sync',
                        style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // Search & Channel List Section
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'YOUR TELEGRAM CHANNELS',
                style: GoogleFonts.inter(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.5,
                  color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                ),
              ),
              Row(
                children: [
                  if (unimportedCount > 0 && !_isBatchSyncing)
                    TextButton(
                      onPressed: () {
                        setState(() {
                          if (_selectedChannelIds.length == unimportedCount) {
                            _selectedChannelIds.clear();
                          } else {
                            _selectedChannelIds.clear();
                            for (final c in filteredChannels) {
                              if (!_isAlreadyImported(c, existingCourses)) {
                                _selectedChannelIds.add(c.id);
                              }
                            }
                          }
                        });
                      },
                      child: Text(
                        _selectedChannelIds.length == unimportedCount ? 'Deselect All' : 'Select All',
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.primary),
                      ),
                    ),
                  IconButton(
                    icon: const Icon(Icons.refresh_rounded, size: 18),
                    tooltip: 'Refresh channels',
                    onPressed: _loadChannels,
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 8),

          // Search Input
          TextField(
            controller: _searchController,
            onChanged: (v) => setState(() {}),
            style: GoogleFonts.inter(fontSize: 13),
            decoration: InputDecoration(
              hintText: 'Search channel name...',
              hintStyle: GoogleFonts.inter(
                fontSize: 12,
                color: isDark ? const Color(0xFF64748B) : const Color(0xFF94A3B8),
              ),
              prefixIcon: const Icon(Icons.search_rounded, size: 18),
              suffixIcon: _searchController.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear, size: 16),
                      onPressed: () {
                        _searchController.clear();
                        setState(() {});
                      },
                    )
                  : null,
              filled: true,
              fillColor: isDark ? const Color(0xFF131D31) : Colors.white,
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(
                  color: isDark ? const Color(0xFF22324E) : const Color(0xFFE2E8F0),
                ),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(
                  color: isDark ? const Color(0xFF22324E) : const Color(0xFFE2E8F0),
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Channels List
          if (_isLoading)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: CircularProgressIndicator(color: AppColors.primary),
              ),
            )
          else if (filteredChannels.isEmpty)
            Container(
              padding: const EdgeInsets.all(32),
              alignment: Alignment.center,
              child: Text(
                'No Telegram channels found.',
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
              itemCount: filteredChannels.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                final channel = filteredChannels[index];
                final isSyncing = _syncingChannelIds.contains(channel.id);
                final isAlreadyImported = _isAlreadyImported(channel, existingCourses);
                final isSelected = _selectedChannelIds.contains(channel.id);

                return Container(
                  decoration: BoxDecoration(
                    color: isSelected
                        ? (isDark ? AppColors.primary.withValues(alpha: 0.15) : AppColors.primaryLight.withValues(alpha: 0.5))
                        : (isDark ? const Color(0xFF131D31) : Colors.white),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: isSelected
                          ? AppColors.primary
                          : (isDark ? const Color(0xFF22324E) : const Color(0xFFE2E8F0)),
                      width: isSelected ? 1.5 : 1.0,
                    ),
                  ),
                  child: Material(
                    color: Colors.transparent,
                    borderRadius: BorderRadius.circular(18),
                    child: InkWell(
                      onTap: () => _toggleChannelSelection(channel, isAlreadyImported),
                      borderRadius: BorderRadius.circular(18),
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Row(
                          children: [
                            // Selection Checkbox for Unimported Channels
                            if (!isAlreadyImported)
                              Padding(
                                padding: const EdgeInsets.only(right: 10),
                                child: Icon(
                                  isSelected ? Icons.check_box_rounded : Icons.check_box_outline_blank_rounded,
                                  color: isSelected ? AppColors.primary : (isDark ? const Color(0xFF64748B) : const Color(0xFF94A3B8)),
                                  size: 22,
                                ),
                              ),

                            Container(
                              width: 38,
                              height: 38,
                              decoration: BoxDecoration(
                                color: isDark
                                    ? AppColors.primary.withValues(alpha: 0.2)
                                    : AppColors.primaryLight.withValues(alpha: 0.6),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Icon(
                                channel.isChannel ? Icons.campaign_rounded : Icons.forum_rounded,
                                color: AppColors.primary,
                                size: 20,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    channel.name,
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
                                    '${channel.isChannel ? "Broadcast Channel" : "Forum Group"} • ${channel.memberCount} members',
                                    style: GoogleFonts.inter(
                                      fontSize: 11,
                                      color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),

                            // Import Status Button / Badge / In-line Spinner
                            if (isAlreadyImported)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF059669).withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: const Color(0xFF059669).withValues(alpha: 0.3)),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(Icons.check_circle_rounded, size: 14, color: Color(0xFF059669)),
                                    const SizedBox(width: 4),
                                    Text(
                                      'Imported',
                                      style: GoogleFonts.inter(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w700,
                                        color: const Color(0xFF059669),
                                      ),
                                    ),
                                  ],
                                ),
                              )
                            else if (isSyncing)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                                decoration: BoxDecoration(
                                  color: AppColors.primary.withValues(alpha: 0.85),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const SizedBox(
                                      width: 12,
                                      height: 12,
                                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      'Syncing...',
                                      style: GoogleFonts.inter(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ],
                                ),
                              )
                            else
                              ElevatedButton(
                                onPressed: _isBatchSyncing ? null : () => _handleImport(channel, navigate: false),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppColors.primary,
                                  foregroundColor: Colors.white,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                                ),
                                child: Text(
                                  'Import',
                                  style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          const SizedBox(height: 60),
        ],
      ),
    );
  }
}
