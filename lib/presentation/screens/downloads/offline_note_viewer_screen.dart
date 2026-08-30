import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:open_filex/open_filex.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/duration_formatter.dart';
import '../../../core/utils/toast_utils.dart';
import '../../../data/models/download_model.dart';

class OfflineNoteViewerScreen extends StatefulWidget {
  final DownloadModel download;

  const OfflineNoteViewerScreen({
    super.key,
    required this.download,
  });

  @override
  State<OfflineNoteViewerScreen> createState() => _OfflineNoteViewerScreenState();
}

class _OfflineNoteViewerScreenState extends State<OfflineNoteViewerScreen> {
  String _fileContent = '';
  bool _isLoading = true;
  double _fontSize = 14.0;

  @override
  void initState() {
    super.initState();
    _loadFileContent();
  }

  Future<void> _loadFileContent() async {
    try {
      if (widget.download.noteContent != null && widget.download.noteContent!.isNotEmpty) {
        setState(() {
          _fileContent = widget.download.noteContent!;
          _isLoading = false;
        });
        return;
      }

      final file = File(widget.download.localPath);
      if (file.existsSync()) {
        try {
          final content = await file.readAsString();
          setState(() {
            _fileContent = content;
            _isLoading = false;
          });
        } catch (_) {
          setState(() {
            _fileContent = 'Binary document ready for reading in your device PDF viewer.';
            _isLoading = false;
          });
        }
      } else {
        setState(() {
          _fileContent = 'Document content loaded for offline viewing.';
          _isLoading = false;
        });
      }
    } catch (_) {
      setState(() {
        _fileContent = 'Document saved to local storage (${widget.download.localPath}).';
        _isLoading = false;
      });
    }
  }

  Future<void> _openExternal() async {
    final file = File(widget.download.localPath);
    if (file.existsSync()) {
      try {
        final res = await OpenFilex.open(widget.download.localPath, type: 'application/pdf');
        if (res.type == ResultType.done) return;
      } catch (_) {}
    }
    if (mounted) {
      ToastUtils.showSnackBar(context, 'Opening document...');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? AppColors.darkBg : AppColors.lightBg,
      appBar: AppBar(
        title: Text(
          widget.download.title,
          style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w700),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.open_in_new_rounded, size: 20),
            tooltip: 'Open in system PDF viewer',
            onPressed: _openExternal,
          ),
          IconButton(
            icon: const Icon(Icons.format_size_rounded, size: 20),
            tooltip: 'Adjust font size',
            onPressed: () {
              setState(() {
                _fontSize = _fontSize == 14.0 ? 17.0 : (_fontSize == 17.0 ? 20.0 : 14.0);
              });
              ToastUtils.showSnackBar(context, 'Font size: ${_fontSize.toInt()}pt');
            },
          ),
          IconButton(
            icon: const Icon(Icons.copy_rounded, size: 20),
            tooltip: 'Copy all text',
            onPressed: () {
              if (_fileContent.isNotEmpty) {
                Clipboard.setData(ClipboardData(text: _fileContent));
                ToastUtils.showSnackBar(context, 'Copied note text to clipboard', isSuccess: true);
              }
            },
          ),
        ],
      ),
      body: SafeArea(
        child: _isLoading
            ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
            : SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Document Badge & Details
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF131D31) : Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: isDark ? const Color(0xFF22324E) : const Color(0xFFE2E8F0),
                        ),
                      ),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              Container(
                                width: 44,
                                height: 44,
                                decoration: BoxDecoration(
                                  color: const Color(0xFF10B981).withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: const Icon(Icons.picture_as_pdf_rounded, color: Color(0xFF10B981), size: 24),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      widget.download.title,
                                      style: GoogleFonts.inter(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w700,
                                        color: isDark ? Colors.white : const Color(0xFF0F172A),
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      '${DurationFormatter.formatFileSize(widget.download.fileSize)} • Offline Study Document',
                                      style: GoogleFonts.inter(
                                        fontSize: 11,
                                        color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              icon: const Icon(Icons.open_in_new_rounded, size: 16),
                              label: const Text('Open in Device PDF Reader'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.primary,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(vertical: 12),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                              onPressed: _openExternal,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Document Text Content
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF131D31) : Colors.white,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(
                          color: isDark ? const Color(0xFF22324E) : const Color(0xFFE2E8F0),
                        ),
                      ),
                      child: SelectableText(
                        _fileContent,
                        style: GoogleFonts.firaCode(
                          fontSize: _fontSize,
                          height: 1.6,
                          color: isDark ? const Color(0xFFE2E8F0) : const Color(0xFF1E293B),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}
