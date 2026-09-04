import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:open_filex/open_filex.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/utils/toast_utils.dart';
import '../../presentation/widgets/app_update_dialog.dart';

class AppUpdateInfo {
  final String currentVersion;
  final String latestVersion;
  final String tagName;
  final String changelog;
  final String apkDownloadUrl;
  final String apkName;
  final int apkSize;
  final bool hasUpdate;

  const AppUpdateInfo({
    required this.currentVersion,
    required this.latestVersion,
    required this.tagName,
    required this.changelog,
    required this.apkDownloadUrl,
    required this.apkName,
    required this.apkSize,
    required this.hasUpdate,
  });
}

class AppUpdateService {
  static const String _githubRepo = '7830-c/TeleLearn_Mobile_App';
  static const String _prefLastCheckKey = 'ota_last_update_check_epoch';
  static Future<String>? _currentVersionFuture;
  static Future<void>? _checkInFlight;

  /// Check for updates.
  /// - If [manual] is false: runs silently and only once every 24 hours.
  /// - If [manual] is true: checks immediately and notifies the user even if up to date.
  static Future<void> checkForUpdate(BuildContext context,
      {bool manual = false}) async {
    if (_checkInFlight != null) {
      if (manual && context.mounted) {
        ToastUtils.showSnackBar(context, 'Update check already in progress');
      }
      return;
    }

    if (manual && context.mounted) {
      ToastUtils.showSnackBar(
        context,
        'Checking for updates...',
        duration: const Duration(seconds: 2),
      );
    }

    final check = _checkForUpdate(context, manual: manual);
    _checkInFlight = check;
    try {
      await check;
    } finally {
      if (identical(_checkInFlight, check)) {
        _checkInFlight = null;
      }
    }
  }

  static Future<void> _checkForUpdate(BuildContext context,
      {required bool manual}) async {
    try {
      final prefs = await SharedPreferences.getInstance();

      if (!manual) {
        final lastCheckEpoch = prefs.getInt(_prefLastCheckKey) ?? 0;
        final now = DateTime.now();
        final lastCheck = DateTime.fromMillisecondsSinceEpoch(lastCheckEpoch);
        final checkedToday = lastCheckEpoch > 0 &&
            lastCheck.year == now.year &&
            lastCheck.month == now.month &&
            lastCheck.day == now.day;
        if (checkedToday) {
          // Already checked recently; keep the app lightweight and silent
          return;
        }
      }

      final info = await _fetchUpdateInfo();
      if (info == null) return;

      // Failed checks remain eligible for a retry instead of being cached.
      await prefs.setInt(
          _prefLastCheckKey, DateTime.now().millisecondsSinceEpoch);

      if (!context.mounted) return;

      if (info.hasUpdate) {
        if (info.apkDownloadUrl.isEmpty) {
          if (manual) {
            ToastUtils.showSnackBar(
              context,
              'Update v${info.latestVersion} is available, but no APK was found.',
              isError: true,
            );
          }
          return;
        }

        if (manual) {
          ToastUtils.showSnackBar(
            context,
            'Update available: v${info.latestVersion}',
            isSuccess: true,
          );
        }
        showDialog(
          context: context,
          barrierDismissible: true,
          builder: (dialogCtx) => AppUpdateDialog(updateInfo: info),
        );
      } else if (manual) {
        ToastUtils.showSnackBar(
          context,
          'TeleLearn is up to date (v${info.currentVersion})',
          isSuccess: true,
        );
      }
    } catch (e) {
      debugPrint('[AppUpdateService] Check update error: $e');
      if (manual && context.mounted) {
        ToastUtils.showSnackBar(
          context,
          'Could not check for updates. Please try again later.',
          isError: true,
        );
      }
    }
  }

  /// Query the GitHub Releases public API for the latest release
  static Future<AppUpdateInfo?> _fetchUpdateInfo() async {
    try {
      _currentVersionFuture ??=
          PackageInfo.fromPlatform().then((info) => info.version);
      final currentVersion = await _currentVersionFuture!;

      final url = Uri.parse(
          'https://api.github.com/repos/$_githubRepo/releases/latest');
      final response = await http.get(
        url,
        headers: {
          'Accept': 'application/vnd.github.v3+json',
          'User-Agent': 'TeleLearn-Mobile-App',
        },
      ).timeout(const Duration(seconds: 8));

      if (response.statusCode != 200) {
        debugPrint(
            '[AppUpdateService] GitHub releases API returned status ${response.statusCode}');
        return null;
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final tagName = (data['tag_name'] as String?)?.trim() ?? '';
      final body = (data['body'] as String?)?.trim() ??
          'Bug fixes and performance improvements.';

      final latestVersion = tagName.replaceFirst(RegExp(r'^[vV]'), '').trim();
      final hasUpdate = _isVersionGreater(latestVersion, currentVersion);

      // Locate the appropriate APK asset
      String apkUrl = '';
      String apkName = '';
      int apkSize = 0;

      final assets = data['assets'] as List<dynamic>? ?? [];
      for (final a in assets) {
        final name = (a['name'] as String?)?.toLowerCase() ?? '';
        final downloadUrl = (a['browser_download_url'] as String?) ?? '';
        final size = (a['size'] as int?) ?? 0;

        if (name.endsWith('.apk')) {
          // Prefer arm64-v8a if available, otherwise take universal release APK
          if (name.contains('arm64-v8a') || apkUrl.isEmpty) {
            apkUrl = downloadUrl;
            apkName = a['name'] as String? ?? 'app-update.apk';
            apkSize = size;
            if (name.contains('arm64-v8a')) break;
          }
        }
      }

      return AppUpdateInfo(
        currentVersion: currentVersion,
        latestVersion: latestVersion,
        tagName: tagName,
        changelog: body,
        apkDownloadUrl: apkUrl,
        apkName: apkName,
        apkSize: apkSize,
        hasUpdate: hasUpdate,
      );
    } catch (e) {
      debugPrint('[AppUpdateService] Error fetching release info: $e');
      return null;
    }
  }

  /// Compares semantic versions (e.g., "1.1.0" > "1.0.0")
  static bool _isVersionGreater(String remote, String local) {
    try {
      final remoteParts = remote
          .split('.')
          .map((p) => int.tryParse(p.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0)
          .toList();
      final localParts = local
          .split('.')
          .map((p) => int.tryParse(p.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0)
          .toList();

      while (remoteParts.length < 3) {
        remoteParts.add(0);
      }
      while (localParts.length < 3) {
        localParts.add(0);
      }

      for (int i = 0; i < 3; i++) {
        if (remoteParts[i] > localParts[i]) return true;
        if (remoteParts[i] < localParts[i]) return false;
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  /// Download the APK from GitHub and immediately trigger Android's native installer
  static Future<bool> downloadAndInstallApk({
    required String downloadUrl,
    required void Function(double progress, int downloadedBytes, int totalBytes)
        onProgress,
  }) async {
    http.Client? client;
    IOSink? sink;
    File? file;
    try {
      client = http.Client();
      final request = http.Request('GET', Uri.parse(downloadUrl));
      final response =
          await client.send(request).timeout(const Duration(seconds: 15));

      if (response.statusCode != 200) {
        debugPrint(
            '[AppUpdateService] Download failed with status ${response.statusCode}');
        return false;
      }

      final totalBytes = response.contentLength ?? 0;
      int downloadedBytes = 0;

      final tempDir = await getTemporaryDirectory();
      final filePath = p.join(tempDir.path, 'telelearn_update.apk');
      file = File(filePath);

      if (file.existsSync()) {
        try {
          file.deleteSync();
        } catch (_) {}
      }

      sink = file.openWrite();
      final progressClock = Stopwatch()..start();
      onProgress(0.0, 0, totalBytes);

      await for (final chunk
          in response.stream.timeout(const Duration(seconds: 10))) {
        downloadedBytes += chunk.length;
        sink.add(chunk);
        if (progressClock.elapsed >= const Duration(milliseconds: 100) ||
            (totalBytes > 0 && downloadedBytes >= totalBytes)) {
          progressClock.reset();
          final progress = totalBytes > 0
              ? (downloadedBytes / totalBytes).clamp(0.0, 1.0)
              : 0.0;
          onProgress(progress, downloadedBytes, totalBytes);
        }
      }

      await sink.flush();
      await sink.close();
      sink = null;
      if (totalBytes > 0 && downloadedBytes < totalBytes) return false;
      onProgress(1.0, downloadedBytes, totalBytes);

      // Launch native Android package installer
      final result = await OpenFilex.open(
        filePath,
        type: 'application/vnd.android.package-archive',
      );

      debugPrint(
          '[AppUpdateService] OpenFilex result: ${result.type} - ${result.message}');
      return result.type == ResultType.done;
    } catch (e) {
      debugPrint('[AppUpdateService] Error downloading/installing APK: $e');
      await sink?.close();
      try {
        if (file != null && file.existsSync()) await file.delete();
      } catch (_) {}
      return false;
    } finally {
      client?.close();
    }
  }
}
