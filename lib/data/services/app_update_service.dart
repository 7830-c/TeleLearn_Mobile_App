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
  static const int _checkIntervalHours = 24;

  /// Check for updates.
  /// - If [manual] is false: runs silently and only once every 24 hours.
  /// - If [manual] is true: checks immediately and notifies the user even if up to date.
  static Future<void> checkForUpdate(BuildContext context, {bool manual = false}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final nowEpoch = DateTime.now().millisecondsSinceEpoch;

      if (!manual) {
        final lastCheckEpoch = prefs.getInt(_prefLastCheckKey) ?? 0;
        final differenceHours = DateTime.now().difference(DateTime.fromMillisecondsSinceEpoch(lastCheckEpoch)).inHours;
        if (differenceHours < _checkIntervalHours) {
          // Already checked recently; keep the app lightweight and silent
          return;
        }
      }

      final info = await _fetchUpdateInfo();
      // Record successful check time
      await prefs.setInt(_prefLastCheckKey, nowEpoch);

      if (!context.mounted) return;

      if (info != null && info.hasUpdate && info.apkDownloadUrl.isNotEmpty) {
        showDialog(
          context: context,
          barrierDismissible: true,
          builder: (dialogCtx) => AppUpdateDialog(updateInfo: info),
        );
      } else if (manual) {
        final currentVer = info?.currentVersion ?? '1.0.0';
        ToastUtils.showSnackBar(
          context,
          'TeleLearn is up to date (v$currentVer)',
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
      final packageInfo = await PackageInfo.fromPlatform();
      final currentVersion = packageInfo.version; // e.g. "1.0.0"

      final url = Uri.parse('https://api.github.com/repos/$_githubRepo/releases/latest');
      final response = await http.get(
        url,
        headers: {
          'Accept': 'application/vnd.github.v3+json',
          'User-Agent': 'TeleLearn-Mobile-App',
        },
      ).timeout(const Duration(seconds: 8));

      if (response.statusCode != 200) {
        debugPrint('[AppUpdateService] GitHub releases API returned status ${response.statusCode}');
        return null;
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final tagName = (data['tag_name'] as String?)?.trim() ?? '';
      final body = (data['body'] as String?)?.trim() ?? 'Bug fixes and performance improvements.';

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
      final remoteParts = remote.split('.').map((p) => int.tryParse(p.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0).toList();
      final localParts = local.split('.').map((p) => int.tryParse(p.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0).toList();

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
    required void Function(double progress, int downloadedBytes, int totalBytes) onProgress,
  }) async {
    http.Client? client;
    try {
      client = http.Client();
      final request = http.Request('GET', Uri.parse(downloadUrl));
      final response = await client.send(request);

      if (response.statusCode != 200) {
        debugPrint('[AppUpdateService] Download failed with status ${response.statusCode}');
        return false;
      }

      final totalBytes = response.contentLength ?? 0;
      int downloadedBytes = 0;

      final tempDir = await getTemporaryDirectory();
      final filePath = p.join(tempDir.path, 'telelearn_update.apk');
      final file = File(filePath);

      if (file.existsSync()) {
        try {
          file.deleteSync();
        } catch (_) {}
      }

      final sink = file.openWrite();

      await response.stream.listen(
        (chunk) {
          downloadedBytes += chunk.length;
          sink.add(chunk);
          final progress = totalBytes > 0 ? (downloadedBytes / totalBytes) : 0.0;
          onProgress(progress, downloadedBytes, totalBytes);
        },
        cancelOnError: true,
      ).asFuture();

      await sink.flush();
      await sink.close();

      // Launch native Android package installer
      final result = await OpenFilex.open(
        filePath,
        type: 'application/vnd.android.package-archive',
      );

      debugPrint('[AppUpdateService] OpenFilex result: ${result.type} - ${result.message}');
      return result.type == ResultType.done;
    } catch (e) {
      debugPrint('[AppUpdateService] Error downloading/installing APK: $e');
      return false;
    } finally {
      client?.close();
    }
  }
}
