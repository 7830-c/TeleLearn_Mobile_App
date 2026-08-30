import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class TelegramAuthResult {
  final bool success;
  final bool requiresPassword;
  final String? phoneCodeHash;
  final String? error;
  final int? userId;
  final String? username;

  TelegramAuthResult({
    required this.success,
    this.requiresPassword = false,
    this.phoneCodeHash,
    this.error,
    this.userId,
    this.username,
  });
}

class TelegramAuthService {
  static const List<String> apiBases = [
    'https://telelearn.onrender.com/api',
    'http://10.0.2.2:8000/api',
    'http://127.0.0.1:8000/api',
  ];

  /// Per-base timeout: try each server for 20s before moving to next.
  /// Total worst-case: 3 × 20s = 60s.
  static const _perBaseTimeout = Duration(seconds: 20);

  static Future<TelegramAuthResult> sendCode(String phone) async {
    final cleanPhone = _normalizePhone(phone);
    if (cleanPhone.isEmpty) {
      return TelegramAuthResult(success: false, error: 'Please enter your Telegram phone number');
    }

    String lastError = '';

    for (final base in apiBases) {
      try {
        final url = Uri.parse('$base/auth/send-code');
        final response = await http
            .post(
              url,
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode({'phone': cleanPhone}),
            )
            .timeout(_perBaseTimeout);

        final data = jsonDecode(response.body);
        if (response.statusCode == 200 && data['phone_code_hash'] != null) {
          return TelegramAuthResult(
            success: true,
            phoneCodeHash: data['phone_code_hash'].toString(),
          );
        } else if (response.statusCode >= 400) {
          final detail = data['detail'] ?? 'Failed to send OTP. Verify your phone number with country code (e.g. +91...).';
          // Server responded with an error — don't try other bases for 4xx client errors
          if (response.statusCode < 500) {
            return TelegramAuthResult(success: false, error: detail.toString());
          }
          lastError = detail.toString();
        }
      } on TimeoutException {
        debugPrint('[TelegramAuthService] sendCode timeout on $base');
        lastError = 'Server is taking too long to respond. Trying next server...';
        continue; // Move to next base immediately
      } catch (e) {
        debugPrint('[TelegramAuthService] sendCode error on $base: $e');
        lastError = 'Connection failed. Check your internet connection.';
        continue;
      }
    }

    return TelegramAuthResult(
      success: false,
      error: lastError.isNotEmpty
          ? lastError
          : 'Could not connect to Telegram server. Please verify your connection & country code (e.g. +91...).',
    );
  }

  static Future<TelegramAuthResult> verifyCode({
    required String phone,
    required String code,
    required String phoneCodeHash,
  }) async {
    final cleanPhone = _normalizePhone(phone);
    final cleanCode = code.trim();

    if (cleanCode.isEmpty) {
      return TelegramAuthResult(success: false, error: 'Please enter the verification code');
    }

    String lastError = '';

    for (final base in apiBases) {
      try {
        final url = Uri.parse('$base/auth/verify-code');
        final response = await http
            .post(
              url,
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode({
                'phone': cleanPhone,
                'code': cleanCode,
                'phone_code_hash': phoneCodeHash,
              }),
            )
            .timeout(_perBaseTimeout);

        final data = jsonDecode(response.body);
        if (response.statusCode == 200) {
          if (data['success'] == true) {
            return TelegramAuthResult(
              success: true,
              userId: data['user_id'] is int ? data['user_id'] : int.tryParse('${data['user_id']}'),
              username: data['username']?.toString(),
            );
          } else if (data['requires_password'] == true) {
            return TelegramAuthResult(success: false, requiresPassword: true);
          }
        } else if (response.statusCode >= 400) {
          final detail = data['detail'] ?? 'Invalid verification code. Please check and try again.';
          if (response.statusCode < 500) {
            return TelegramAuthResult(success: false, error: detail.toString());
          }
          lastError = detail.toString();
        }
      } on TimeoutException {
        debugPrint('[TelegramAuthService] verifyCode timeout on $base');
        lastError = 'Server timeout. Please retry.';
        continue;
      } catch (e) {
        debugPrint('[TelegramAuthService] verifyCode error on $base: $e');
        lastError = 'Connection failed. Check your internet.';
        continue;
      }
    }

    return TelegramAuthResult(
      success: false,
      error: lastError.isNotEmpty ? lastError : 'Invalid verification code or network timeout.',
    );
  }

  static Future<TelegramAuthResult> verifyPassword({
    required String phone,
    required String password,
  }) async {
    final cleanPhone = _normalizePhone(phone);
    if (password.isEmpty) {
      return TelegramAuthResult(success: false, error: 'Please enter your Telegram 2FA cloud password');
    }

    String lastError = '';

    for (final base in apiBases) {
      try {
        final url = Uri.parse('$base/auth/verify-password');
        final response = await http
            .post(
              url,
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode({
                'phone': cleanPhone,
                'password': password,
              }),
            )
            .timeout(_perBaseTimeout);

        final data = jsonDecode(response.body);
        if (response.statusCode == 200 && data['success'] == true) {
          return TelegramAuthResult(
            success: true,
            userId: data['user_id'] is int ? data['user_id'] : int.tryParse('${data['user_id']}'),
            username: data['username']?.toString(),
          );
        } else if (response.statusCode >= 400) {
          final detail = data['detail'] ?? 'Invalid 2FA password.';
          if (response.statusCode < 500) {
            return TelegramAuthResult(success: false, error: detail.toString());
          }
          lastError = detail.toString();
        }
      } on TimeoutException {
        debugPrint('[TelegramAuthService] verifyPassword timeout on $base');
        lastError = 'Server timeout. Please retry.';
        continue;
      } catch (e) {
        debugPrint('[TelegramAuthService] verifyPassword error on $base: $e');
        lastError = 'Connection failed.';
        continue;
      }
    }

    return TelegramAuthResult(
      success: false,
      error: lastError.isNotEmpty ? lastError : 'Invalid 2FA password or connection failed.',
    );
  }

  static String _normalizePhone(String phone) {
    var p = phone.trim().replaceAll(' ', '').replaceAll('-', '');
    if (!p.startsWith('+') && p.isNotEmpty) {
      p = '+$p';
    }
    return p;
  }
}
