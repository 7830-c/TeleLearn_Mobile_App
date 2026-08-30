class DurationFormatter {
  /// Format seconds into "1h 25m", "45 mins", "0 mins"
  static String formatHoursMinutes(num? seconds) {
    if (seconds == null || seconds <= 0 || seconds.isNaN || seconds.isInfinite) {
      return '0 mins';
    }
    final int totalSec = seconds.toInt();
    final int totalMinutes = (totalSec / 60).round();
    final int h = totalMinutes ~/ 60;
    final int m = totalMinutes % 60;

    if (h > 0 && m > 0) return '${h}h ${m}m';
    if (h > 0) return '$h hr${h > 1 ? 's' : ''}';
    return '$m min${m > 1 ? 's' : ''}';
  }

  /// Format seconds into standard video timestamps "03:45" or "1:15:30"
  static String formatTimestamp(num? seconds) {
    if (seconds == null || seconds <= 0 || seconds.isNaN || seconds.isInfinite) {
      return '0:00';
    }
    final int totalSec = seconds.toInt();
    final int hours = totalSec ~/ 3600;
    final int minutes = (totalSec % 3600) ~/ 60;
    final int remainingSeconds = totalSec % 60;

    if (hours > 0) {
      return '$hours:${minutes.toString().padLeft(2, '0')}:${remainingSeconds.toString().padLeft(2, '0')}';
    }
    return '$minutes:${remainingSeconds.toString().padLeft(2, '0')}';
  }

  /// Format file size into human readable "14.2 MB", "1.5 GB", etc.
  static String formatFileSize(num? bytes) {
    if (bytes == null || bytes <= 0) return '0 KB';
    final double kb = bytes / 1024;
    final double mb = kb / 1024;
    final double gb = mb / 1024;

    if (gb >= 1.0) return '${gb.toStringAsFixed(1)} GB';
    if (mb >= 1.0) return '${mb.toStringAsFixed(1)} MB';
    return '${kb.toStringAsFixed(0)} KB';
  }
}
