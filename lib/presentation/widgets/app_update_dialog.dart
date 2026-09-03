import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/theme/app_theme.dart';
import '../../data/services/app_update_service.dart';

class AppUpdateDialog extends StatefulWidget {
  final AppUpdateInfo updateInfo;

  const AppUpdateDialog({super.key, required this.updateInfo});

  @override
  State<AppUpdateDialog> createState() => _AppUpdateDialogState();
}

class _AppUpdateDialogState extends State<AppUpdateDialog> {
  bool _isDownloading = false;
  double _progress = 0.0;
  int _downloadedBytes = 0;
  int _totalBytes = 0;
  String? _errorMessage;

  String _formatBytes(int bytes) {
    if (bytes <= 0) return '0 MB';
    final mb = bytes / (1024 * 1024);
    return '${mb.toStringAsFixed(1)} MB';
  }

  Future<void> _startDownload() async {
    setState(() {
      _isDownloading = true;
      _errorMessage = null;
      _progress = 0.0;
    });

    final success = await AppUpdateService.downloadAndInstallApk(
      downloadUrl: widget.updateInfo.apkDownloadUrl,
      onProgress: (progress, downloaded, total) {
        if (mounted) {
          setState(() {
            _progress = progress;
            _downloadedBytes = downloaded;
            _totalBytes = total > 0 ? total : widget.updateInfo.apkSize;
          });
        }
      },
    );

    if (mounted) {
      if (!success) {
        setState(() {
          _isDownloading = false;
          _errorMessage = 'Download or installation failed. Please try again.';
        });
      } else {
        Navigator.of(context).pop();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final info = widget.updateInfo;

    return PopScope(
      canPop: !_isDownloading,
      child: Dialog(
        backgroundColor: isDark ? const Color(0xFF131D31) : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header Icon & Title
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [AppColors.primary, Color(0xFF2563EB)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: const Icon(
                      Icons.system_update_rounded,
                      color: Colors.white,
                      size: 26,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Update Available',
                          style: GoogleFonts.inter(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: isDark ? Colors.white : const Color(0xFF0F172A),
                          ),
                        ),
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: isDark ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                'v${info.currentVersion}',
                                style: GoogleFonts.inter(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                                ),
                              ),
                            ),
                            const Padding(
                              padding: EdgeInsets.symmetric(horizontal: 6),
                              child: Icon(Icons.arrow_forward_rounded, size: 12, color: AppColors.primary),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: AppColors.primary.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                'v${info.latestVersion}',
                                style: GoogleFonts.inter(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.primary,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // Changelog Container
              Text(
                "WHAT'S NEW",
                style: GoogleFonts.inter(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.5,
                  color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                ),
              ),
              const SizedBox(height: 8),
              Container(
                constraints: const BoxConstraints(maxHeight: 160),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF0B1120) : const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: isDark ? const Color(0xFF22324E) : const Color(0xFFE2E8F0),
                  ),
                ),
                child: SingleChildScrollView(
                  child: Text(
                    info.changelog.isNotEmpty ? info.changelog : 'General improvements and bug fixes.',
                    style: GoogleFonts.inter(
                      fontSize: 12.5,
                      height: 1.5,
                      color: isDark ? const Color(0xFFE2E8F0) : const Color(0xFF334155),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 14),

              // Size or Download Progress
              if (!_isDownloading) ...[
                if (info.apkSize > 0)
                  Align(
                    alignment: Alignment.centerRight,
                    child: Text(
                      'Download Size: ${_formatBytes(info.apkSize)}',
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                      ),
                    ),
                  ),
                if (_errorMessage != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    _errorMessage!,
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFFEF4444),
                    ),
                  ),
                ],
                const SizedBox(height: 20),

                // Action Buttons
                Row(
                  children: [
                    Expanded(
                      child: TextButton(
                        onPressed: () => Navigator.of(context).pop(),
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 13),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        child: Text(
                          'Later',
                          style: GoogleFonts.inter(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: ElevatedButton.icon(
                        onPressed: _startDownload,
                        icon: const Icon(Icons.download_rounded, size: 18),
                        label: Text(
                          'Update Now',
                          style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w700),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 13),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    ),
                  ],
                ),
              ] else ...[
                // Downloading State
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: LinearProgressIndicator(
                    value: _progress > 0 ? _progress : null,
                    minHeight: 8,
                    backgroundColor: isDark ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0),
                    valueColor: const AlwaysStoppedAnimation<Color>(AppColors.primary),
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      _progress >= 1.0 ? 'Preparing installation...' : 'Downloading update...',
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: isDark ? Colors.white : const Color(0xFF0F172A),
                      ),
                    ),
                    Text(
                      _totalBytes > 0
                          ? '${(_progress * 100).toInt()}% (${_formatBytes(_downloadedBytes)} / ${_formatBytes(_totalBytes)})'
                          : '${(_progress * 100).toInt()}%',
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: AppColors.primary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  'The Android installer will open automatically once the download completes.',
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
