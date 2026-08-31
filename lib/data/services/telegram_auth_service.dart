import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:t/t.dart' as t;
import 'package:tg/tg.dart' as tg;

import '../../core/constants/app_constants.dart';

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

class _IoSocket extends tg.SocketAbstraction {
  _IoSocket(this._rawSocket) {
    _stream = _rawSocket.asBroadcastStream(
      onCancel: (sub) => sub.cancel(),
    ).handleError((e) {
      debugPrint('[TelegramAuthService Socket notice]: $e');
    });
  }

  final Socket _rawSocket;
  late final Stream<Uint8List> _stream;
  Future<void> _lastSendFuture = Future.value();

  @override
  Stream<Uint8List> get receiver => _stream;

  @override
  Future<void> send(List<int> data) {
    final completer = Completer<void>();
    _lastSendFuture = _lastSendFuture.then((_) async {
      try {
        _rawSocket.add(data);
        await _rawSocket.flush();
        completer.complete();
      } catch (e, st) {
        completer.completeError(e, st);
      }
    }).catchError((e, st) {
      completer.completeError(e, st);
    });
    return completer.future;
  }

  void destroy() {
    try {
      _rawSocket.destroy();
    } catch (_) {}
  }
}

class TelegramAuthService {
  static const int apiId = AppConstants.telegramApiId;
  static const String apiHash = AppConstants.telegramApiHash;

  // Default Telegram Production Data Centers
  static final Map<int, t.DcOption> _dcOptions = {
    1: const t.DcOption(
      ipv6: false,
      mediaOnly: false,
      tcpoOnly: false,
      cdn: false,
      static: false,
      thisPortOnly: false,
      id: 1,
      ipAddress: '149.154.175.50',
      port: 443,
    ),
    2: const t.DcOption(
      ipv6: false,
      mediaOnly: false,
      tcpoOnly: false,
      cdn: false,
      static: false,
      thisPortOnly: false,
      id: 2,
      ipAddress: '149.154.167.50',
      port: 443,
    ),
    3: const t.DcOption(
      ipv6: false,
      mediaOnly: false,
      tcpoOnly: false,
      cdn: false,
      static: false,
      thisPortOnly: false,
      id: 3,
      ipAddress: '149.154.175.100',
      port: 443,
    ),
    4: const t.DcOption(
      ipv6: false,
      mediaOnly: false,
      tcpoOnly: false,
      cdn: false,
      static: false,
      thisPortOnly: false,
      id: 4,
      ipAddress: '149.154.167.91',
      port: 443,
    ),
    5: const t.DcOption(
      ipv6: false,
      mediaOnly: false,
      tcpoOnly: false,
      cdn: false,
      static: false,
      thisPortOnly: false,
      id: 5,
      ipAddress: '91.108.56.130',
      port: 443,
    ),
  };

  // Telegram Alternate IP Endpoints for Failover (Resolves Network Unreachable & Socket Timeouts)
  static final Map<int, List<String>> _dcIps = {
    1: ['149.154.175.50', '149.154.175.53', '149.154.167.40'],
    2: ['149.154.167.50', '149.154.167.51', '149.154.175.10'],
    3: ['149.154.175.100', '149.154.175.101'],
    4: ['149.154.167.91', '149.154.167.92', '149.154.167.90'],
    5: ['91.108.56.130', '91.108.56.165', '91.108.56.146', '91.108.56.100'],
  };


  /// Determine the best initial Telegram DC based on country code or saved session
  static Future<int> getBestInitialDc(String phone) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedDc = prefs.getInt('tg_last_dc');
      if (savedDc != null && savedDc >= 1 && savedDc <= 5) {
        return savedDc;
      }
    } catch (_) {}

    final clean = _normalizePhone(phone);
    // Asia / India / Southeast Asia -> DC 5 (Singapore)
    if (clean.startsWith('+91') ||
        clean.startsWith('+62') ||
        clean.startsWith('+60') ||
        clean.startsWith('+65') ||
        clean.startsWith('+84') ||
        clean.startsWith('+66') ||
        clean.startsWith('+63') ||
        clean.startsWith('+81') ||
        clean.startsWith('+82') ||
        clean.startsWith('+86') ||
        clean.startsWith('+977') ||
        clean.startsWith('+92') ||
        clean.startsWith('+880') ||
        clean.startsWith('+94')) {
      return 5;
    }

    // North & South America -> DC 1 (Miami)
    if (clean.startsWith('+1') ||
        clean.startsWith('+52') ||
        clean.startsWith('+55') ||
        clean.startsWith('+54') ||
        clean.startsWith('+57') ||
        clean.startsWith('+56') ||
        clean.startsWith('+51')) {
      return 1;
    }

    // Europe & Middle East default -> DC 2 / 4 (Amsterdam)
    return 2;
  }

  /// Send verification code directly via Telegram MTProto Authorization Protocol
  static Future<TelegramAuthResult> sendCode(String phone) async {
    final cleanPhone = _normalizePhone(phone);
    if (cleanPhone.isEmpty || cleanPhone.length < 8) {
      return TelegramAuthResult(
        success: false,
        error: 'Please enter a valid Telegram phone number with country code (e.g. +91 98XXX XXXXX)',
      );
    }

    try {
      final initialDc = await getBestInitialDc(cleanPhone);
      _currentDcId = initialDc;
      debugPrint('[TelegramAuthService] Initiating direct Telegram MTProto session for $cleanPhone on DC $_currentDcId (api_id: $apiId)');

      // Get or establish MTProto client on optimal DC
      final client = await getClient(dcId: _currentDcId);

      debugPrint('[TelegramAuthService] Sending MTProto auth.sendCode on DC $_currentDcId...');
      final sendRes = await client.auth.sendCode(
        phoneNumber: cleanPhone,
        apiId: apiId,
        apiHash: apiHash,
        settings: const t.CodeSettings(
          allowFlashcall: false,
          currentNumber: false,
          allowAppHash: false,
          allowMissedCall: false,
          allowFirebase: false,
          unknownNumber: false,
        ),
      );

      // Handle DC Migration if account is on another Data Center
      if (sendRes.error != null && _isMigrateError(sendRes.error!.errorMessage)) {
        final targetDc = _extractDcFromMigrateError(sendRes.error!.errorMessage);
        debugPrint('[TelegramAuthService] Telegram requires DC migration to DC $targetDc');

        final migratedClient = await getClient(dcId: targetDc, forceNew: true);
        final migratedRes = await migratedClient.auth.sendCode(
          phoneNumber: cleanPhone,
          apiId: apiId,
          apiHash: apiHash,
          settings: const t.CodeSettings(
            allowFlashcall: false,
            currentNumber: false,
            allowAppHash: false,
            allowMissedCall: false,
            allowFirebase: false,
            unknownNumber: false,
          ),
        );

        return _processSendCodeResult(migratedRes, cleanPhone);
      }

      return _processSendCodeResult(sendRes, cleanPhone);
    } catch (e) {
      debugPrint('[TelegramAuthService] MTProto sendCode exception: $e');
      return TelegramAuthResult(
        success: false,
        error: _mapErrorMessage(e.toString()),
      );
    }
  }

  static TelegramAuthResult _processSendCodeResult(t.Result<t.AuthSentCodeBase> res, String phone) {
    if (res.result is t.AuthSentCode) {
      final sentCode = res.result as t.AuthSentCode;
      debugPrint('[TelegramAuthService] OTP successfully sent by Telegram! Hash: ${sentCode.phoneCodeHash}');
      return TelegramAuthResult(
        success: true,
        phoneCodeHash: sentCode.phoneCodeHash,
      );
    }

    if (res.error != null) {
      debugPrint('[TelegramAuthService] Telegram error: ${res.error!.errorCode} - ${res.error!.errorMessage}');
      return TelegramAuthResult(
        success: false,
        error: _mapRpcError(res.error!.errorMessage),
      );
    }

    return TelegramAuthResult(
      success: false,
      error: 'Failed to send verification code. Please check your number and try again.',
    );
  }

  /// Verify verification code directly via Telegram MTProto API
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

    try {
      debugPrint('[TelegramAuthService] Verifying OTP $cleanCode for $cleanPhone (hash: $phoneCodeHash)');
      final client = await getClient(dcId: _currentDcId);

      final signInRes = await client.auth.signIn(
        phoneNumber: cleanPhone,
        phoneCodeHash: phoneCodeHash,
        phoneCode: cleanCode,
      );

      // Handle DC Migration if necessary
      if (signInRes.error != null && _isMigrateError(signInRes.error!.errorMessage)) {
        final targetDc = _extractDcFromMigrateError(signInRes.error!.errorMessage);
        debugPrint('[TelegramAuthService] Migration needed on signIn to DC $targetDc');
        final migratedClient = await getClient(dcId: targetDc, forceNew: true);
        final migratedRes = await migratedClient.auth.signIn(
          phoneNumber: cleanPhone,
          phoneCodeHash: phoneCodeHash,
          phoneCode: cleanCode,
        );
        return _processSignInResult(migratedRes, cleanPhone);
      }

      return _processSignInResult(signInRes, cleanPhone);
    } catch (e) {
      debugPrint('[TelegramAuthService] MTProto verifyCode error: $e');
      return TelegramAuthResult(
        success: false,
        error: _mapErrorMessage(e.toString()),
      );
    }
  }

  static TelegramAuthResult _processSignInResult(t.Result<t.AuthAuthorizationBase> res, String phone) {
    if (res.result is t.AuthAuthorization) {
      final auth = res.result as t.AuthAuthorization;
      int? userId;
      String? username;

      if (auth.user is t.User) {
        final u = auth.user as t.User;
        userId = u.id;
        username = u.username ?? u.firstName;
      }

      debugPrint('[TelegramAuthService] Successfully logged in! User: $userId ($username)');
      return TelegramAuthResult(
        success: true,
        userId: userId ?? phone.hashCode.abs(),
        username: username ?? phone.replaceAll('+', ''),
      );
    }

    if (res.error != null) {
      final err = res.error!.errorMessage;
      debugPrint('[TelegramAuthService] SignIn error: ${res.error!.errorCode} - $err');

      if (err.contains('SESSION_PASSWORD_NEEDED')) {
        return TelegramAuthResult(
          success: false,
          requiresPassword: true,
        );
      }

      return TelegramAuthResult(
        success: false,
        error: _mapRpcError(err),
      );
    }

    return TelegramAuthResult(
      success: false,
      error: 'Verification failed. Please check the code and try again.',
    );
  }

  /// Verify 2FA Cloud Password directly via Telegram MTProto SRP protocol
  static Future<TelegramAuthResult> verifyPassword({
    required String phone,
    required String password,
  }) async {
    final cleanPhone = _normalizePhone(phone);
    if (password.isEmpty) {
      return TelegramAuthResult(success: false, error: 'Please enter your Telegram 2FA cloud password');
    }

    try {
      debugPrint('[TelegramAuthService] Verifying 2FA password for $cleanPhone');
      final client = await getClient(dcId: _currentDcId);

      final pwdResult = await client.account.getPassword();
      if (pwdResult.result is! t.AccountPassword) {
        return TelegramAuthResult(
          success: false,
          error: 'Could not fetch 2FA password parameters from Telegram.',
        );
      }

      final accountPassword = pwdResult.result as t.AccountPassword;
      final srp = await tg.check2FA(accountPassword, password);

      final checkRes = await client.auth.checkPassword(password: srp);

      return _processSignInResult(checkRes, cleanPhone);
    } catch (e) {
      debugPrint('[TelegramAuthService] 2FA verify error: $e');
      return TelegramAuthResult(
        success: false,
        error: _mapErrorMessage(e.toString()),
      );
    }
  }

  static final Map<int, tg.Client> _clientsByDc = {};
  static final Map<int, Future<tg.Client>> _clientFuturesByDc = {};
  static final Map<int, _IoSocket> _socketsByDc = {};
  static int _currentDcId = 2;

  static Future<int> getMasterDcId() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedDc = prefs.getInt('tg_last_dc');
      if (savedDc != null && savedDc >= 1 && savedDc <= 5) {
        _currentDcId = savedDc;
        return savedDc;
      }
    } catch (_) {}
    return _currentDcId;
  }

  /// Download file chunk directly from Telegram MTProto on specified DC
  static Future<Uint8List?> downloadFileChunk({
    required int dcId,
    required int docId,
    required int accessHash,
    required Uint8List fileReference,
    required int offset,
    required int limit,
  }) async {
    try {
      final masterDc = await getMasterDcId();
      final targetDc = (dcId >= 1 && dcId <= 5) ? dcId : masterDc;
      final client = await getClient(dcId: targetDc);
      final location = t.InputDocumentFileLocation(
        id: docId,
        accessHash: accessHash,
        fileReference: fileReference,
        thumbSize: '',
      );

      final res = await client.upload.getFile(
        precise: true,
        cdnSupported: false,
        location: location,
        offset: offset,
        limit: limit,
      );

      if (res.result is t.UploadFile) {
        final uploadFile = res.result as t.UploadFile;
        return Uint8List.fromList(uploadFile.bytes);
      }

      if (res.error != null) {
        final err = res.error!.errorMessage;
        debugPrint('[TelegramAuthService] getFile error on DC $targetDc: ${res.error!.errorCode} - $err');

        if (_isMigrateError(err)) {
          final migratedDc = _extractDcFromMigrateError(err);
          debugPrint('[TelegramAuthService] File requires migration to DC $migratedDc');
          return downloadFileChunk(
            dcId: migratedDc,
            docId: docId,
            accessHash: accessHash,
            fileReference: fileReference,
            offset: offset,
            limit: limit,
          );
        }
      }
    } catch (e) {
      debugPrint('[TelegramAuthService] downloadFileChunk exception: $e');
      final masterDc = await getMasterDcId();
      final targetDc = (dcId >= 1 && dcId <= 5) ? dcId : masterDc;
      _clientsByDc.remove(targetDc);
      _socketsByDc.remove(targetDc)?.destroy();
    }
    return null;
  }

  /// Establish or retrieve existing MTProto client connection to specified DC
  static Future<tg.Client> getClient({int? dcId, bool forceNew = false}) async {
    final masterDc = await getMasterDcId();
    final targetDc = dcId ?? masterDc;

    if (!forceNew) {
      if (_clientsByDc.containsKey(targetDc)) {
        return _clientsByDc[targetDc]!;
      }
      if (_clientFuturesByDc.containsKey(targetDc)) {
        return await _clientFuturesByDc[targetDc]!;
      }
    }

    final future = _doConnectClient(targetDc: targetDc, masterDc: masterDc, forceNew: forceNew);
    _clientFuturesByDc[targetDc] = future;
    try {
      final client = await future;
      _clientsByDc[targetDc] = client;
      return client;
    } finally {
      _clientFuturesByDc.remove(targetDc);
    }
  }

  static Future<tg.Client> _doConnectClient({
    required int targetDc,
    required int masterDc,
    required bool forceNew,
  }) async {
    // Close previous socket for this specific DC if forcing new
    if (forceNew && _socketsByDc.containsKey(targetDc)) {
      _socketsByDc[targetDc]?.destroy();
      _socketsByDc.remove(targetDc);
      _clientsByDc.remove(targetDc);
    }

    final dc = _dcOptions[targetDc] ?? _dcOptions[2]!;
    final candidateIps = _dcIps[targetDc] ?? [dc.ipAddress];
    final candidatePorts = [443, 80, 5222];

    Socket? rawSocket;
    Object? lastErr;

    for (final ip in candidateIps) {
      for (final port in candidatePorts) {
        try {
          debugPrint('[TelegramAuthService] Connecting to DC $targetDc at $ip:$port (master: $masterDc)...');
          rawSocket = await Socket.connect(
            ip,
            port,
            timeout: const Duration(seconds: 4),
          );
          break;
        } catch (e) {
          lastErr = e;
        }
      }
      if (rawSocket != null) break;
    }

    if (rawSocket == null) {
      throw Exception('Failed to connect to Telegram DC $targetDc across all endpoints: $lastErr');
    }

    final socket = _IoSocket(rawSocket);
    _socketsByDc[targetDc] = socket;

    final obfuscation = tg.Obfuscation.random(false, targetDc);
    final idGenerator = tg.MessageIdGenerator();

    await socket.send(obfuscation.preamble);

    // Check for cached AuthKey for this DC
    tg.AuthorizationKey? authKey = await _loadCachedAuthKey(targetDc);

    if (authKey == null) {
      debugPrint('[TelegramAuthService] Performing MTProto DH exchange for DC $targetDc...');
      authKey = await tg.Client.authorize(
        socket,
        obfuscation,
        idGenerator,
      );
      await _saveCachedAuthKey(targetDc, authKey);
      debugPrint('[TelegramAuthService] New AuthKey established for DC $targetDc: ${authKey.id}');
    } else {
      debugPrint('[TelegramAuthService] Reusing cached AuthKey for DC $targetDc: ${authKey.id}');
    }

    final client = tg.Client(
      socket: socket,
      obfuscation: obfuscation,
      authorizationKey: authKey,
      idGenerator: idGenerator,
    );

    try {
      final cfg = await client.initConnection<t.Config>(
        apiId: apiId,
        deviceModel: 'TeleLearn App',
        systemVersion: 'Android 14',
        appVersion: '1.0.0',
        systemLangCode: 'en',
        langPack: '',
        langCode: 'en',
        query: const t.HelpGetConfig(),
      );

      if (cfg.result != null) {
        for (final item in cfg.result!.dcOptions) {
          if (item is t.DcOption && !item.ipv6 && !item.mediaOnly && !item.cdn) {
            _dcOptions.putIfAbsent(item.id, () => item);
          }
        }
      }
    } catch (e) {
      debugPrint('[TelegramAuthService] initConnection note: $e');
    }

    _clientsByDc[targetDc] = client;

    // If connecting to a secondary DC while user is authenticated on master DC, transfer authorization
    if (targetDc != masterDc) {
      try {
        final masterClient = await getClient(dcId: masterDc);
        final exported = await masterClient.auth.exportAuthorization(dcId: targetDc);
        if (exported.result is t.AuthExportedAuthorization) {
          final exp = exported.result as t.AuthExportedAuthorization;
          await client.auth.importAuthorization(
            id: exp.id,
            bytes: Uint8List.fromList(exp.bytes),
          );
          debugPrint('[TelegramAuthService] Auth exported from master DC $masterDc to target DC $targetDc');
        }
      } catch (e) {
        debugPrint('[TelegramAuthService] Export auth note: $e');
      }
    }

    return client;
  }

  static Future<tg.AuthorizationKey?> _loadCachedAuthKey(int dcId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final keyJson = prefs.getString('tg_auth_key_dc_$dcId');
      if (keyJson != null && keyJson.isNotEmpty) {
        final map = jsonDecode(keyJson) as Map<String, dynamic>;
        return tg.AuthorizationKey.fromJson(map);
      }
    } catch (e) {
      debugPrint('[TelegramAuthService] Failed to load cached auth key: $e');
    }
    return null;
  }

  static Future<void> _saveCachedAuthKey(int dcId, tg.AuthorizationKey authKey) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('tg_auth_key_dc_$dcId', jsonEncode(authKey.toJson()));
      await prefs.setInt('tg_last_dc', dcId);
    } catch (e) {
      debugPrint('[TelegramAuthService] Failed to save cached auth key: $e');
    }
  }

  static bool isMigrateError(String error) {
    return error.contains('MIGRATE_');
  }

  static int extractDcFromMigrateError(String error) {
    return _extractDcFromMigrateError(error);
  }

  static bool _isMigrateError(String error) {
    return error.startsWith('PHONE_MIGRATE_') ||
        error.startsWith('NETWORK_MIGRATE_') ||
        error.startsWith('USER_MIGRATE_');
  }

  static int _extractDcFromMigrateError(String error) {
    final parts = error.split('_');
    if (parts.isNotEmpty) {
      final last = parts.last;
      final parsed = int.tryParse(last);
      if (parsed != null && parsed >= 1 && parsed <= 5) {
        return parsed;
      }
    }
    return 2;
  }

  static String _mapRpcError(String rpcError) {
    if (rpcError.contains('PHONE_NUMBER_INVALID')) {
      return 'The phone number is invalid. Please ensure the country code is included (e.g. +91...)';
    }
    if (rpcError.contains('PHONE_NUMBER_UNOCCUPIED')) {
      return 'This phone number is not registered on Telegram yet.';
    }
    if (rpcError.contains('PHONE_NUMBER_BANNED')) {
      return 'This phone number has been banned by Telegram.';
    }
    if (rpcError.contains('PHONE_CODE_INVALID')) {
      return 'Invalid verification code. Please check and try again.';
    }
    if (rpcError.contains('PHONE_CODE_EXPIRED')) {
      return 'Verification code has expired. Please request a new code.';
    }
    if (rpcError.contains('PASSWORD_HASH_INVALID')) {
      return 'Incorrect 2FA cloud password. Please try again.';
    }
    if (rpcError.startsWith('FLOOD_WAIT_')) {
      final seconds = rpcError.replaceFirst('FLOOD_WAIT_', '');
      return 'Too many login attempts. Please wait $seconds seconds before trying again.';
    }
    if (rpcError.contains('API_ID_INVALID')) {
      return 'Telegram API ID or Hash is invalid.';
    }
    return 'Telegram Error: $rpcError';
  }

  static String _mapErrorMessage(String error) {
    if (error.contains('SocketException') || error.contains('Connection refused') || error.contains('timed out')) {
      return 'Could not connect to Telegram MTProto servers. Please check your internet connection.';
    }
    if (error.contains('HandshakeException')) {
      return 'Secure connection to Telegram servers failed. Please retry.';
    }
    return error;
  }

  static String _normalizePhone(String phone) {
    var p = phone.trim().replaceAll(' ', '').replaceAll('-', '');
    if (!p.startsWith('+') && p.isNotEmpty) {
      p = '+$p';
    }
    return p;
  }
}

