import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
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
  final String? deliveryType; // 'app', 'sms', 'call'

  TelegramAuthResult({
    required this.success,
    this.requiresPassword = false,
    this.phoneCodeHash,
    this.error,
    this.userId,
    this.username,
    this.deliveryType,
  });
}

class _IoSocket extends tg.SocketAbstraction {
  _IoSocket(this._rawSocket, {this.onDisconnected}) {
    _rawSocket.listen(
      (data) {
        if (!_isDestroyed && !_controller.isClosed) {
          _controller.add(data);
        }
      },
      onError: (e) {
        debugPrint('[TelegramAuthService Socket notice]: $e');
        destroy();
        onDisconnected?.call();
      },
      onDone: () {
        destroy();
        onDisconnected?.call();
      },
      cancelOnError: true,
    );
  }

  final Socket _rawSocket;
  final VoidCallback? onDisconnected;
  final StreamController<Uint8List> _controller = StreamController<Uint8List>.broadcast();
  Future<void> _lastSendFuture = Future.value();
  bool _isDestroyed = false;

  bool get isAlive => !_isDestroyed;

  @override
  Stream<Uint8List> get receiver => _controller.stream;

  @override
  Future<void> send(List<int> data) {
    if (_isDestroyed) {
      return Future.error(const SocketException('Socket is closed'));
    }
    final completer = Completer<void>();
    _lastSendFuture = _lastSendFuture.then((_) async {
      try {
        if (_isDestroyed) {
          throw const SocketException('Socket is closed');
        }
        _rawSocket.add(data);
        await _rawSocket.flush();
        completer.complete();
      } catch (e, st) {
        destroy();
        onDisconnected?.call();
        completer.completeError(e, st);
      }
    }).catchError((e, st) {
      destroy();
      onDisconnected?.call();
      completer.completeError(e, st);
    });
    return completer.future;
  }

  void destroy() {
    if (_isDestroyed) return;
    _isDestroyed = true;
    try {
      if (!_controller.isClosed) {
        _controller.close();
      }
    } catch (_) {}
    try {
      _rawSocket.destroy();
    } catch (_) {}
  }
}

class TelegramAuthService {
  static int _credentialIndex = 0;

  static int get apiId {
    const pool = AppConstants.telegramApiCredentialsPool;
    return pool[_credentialIndex % pool.length]['apiId'] as int;
  }

  static String get apiHash {
    const pool = AppConstants.telegramApiCredentialsPool;
    return pool[_credentialIndex % pool.length]['apiHash'] as String;
  }

  static void rotateApiCredentials() {
    _credentialIndex = (_credentialIndex + 1) % AppConstants.telegramApiCredentialsPool.length;
    debugPrint('[TelegramAuthService] Switched to Telegram API credentials pair #$_credentialIndex (api_id: $apiId)');
  }

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
    5: ['91.108.56.165', '91.108.56.130', '91.108.56.146', '91.108.56.100'],
  };


  /// Determine the best initial Telegram DC based on country code
  static int getBestInitialDc(String phone) {
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

    // Europe & Middle East default -> DC 2
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
      final initialDc = getBestInitialDc(cleanPhone);
      _currentDcId = initialDc;
      debugPrint('[TelegramAuthService] Initiating direct Telegram MTProto session for $cleanPhone on DC $_currentDcId (api_id: $apiId)');

      // Get or establish MTProto client on optimal DC
      tg.Client client;
      try {
        client = await getClient(dcId: _currentDcId);
      } catch (e) {
        debugPrint('[TelegramAuthService] Initial connect failed, forcing fresh connection: $e');
        client = await getClient(dcId: _currentDcId, forceNew: true);
      }

      debugPrint('[TelegramAuthService] Sending MTProto auth.sendCode on DC $_currentDcId...');
      t.Result<t.AuthSentCodeBase> sendRes;
      try {
        sendRes = await client.auth.sendCode(
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
      } catch (e) {
        debugPrint('[TelegramAuthService] sendCode socket/client error ($e), retrying with fresh client...');
        client = await getClient(dcId: _currentDcId, forceNew: true);
        sendRes = await client.auth.sendCode(
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
      }

      if (sendRes.error != null) {
        final err = sendRes.error!.errorMessage;
        // Handle dead / expired auth key on existing session
        if (err.contains('AUTH_KEY_UNREGISTERED') ||
            err.contains('AUTH_KEY_INVALID') ||
            err.contains('SESSION_REVOKED') ||
            err.contains('SESSION_EXPIRED')) {
          debugPrint('[TelegramAuthService] AuthKey invalid on sendCode ($err), establishing fresh auth key...');
          client = await getClient(dcId: _currentDcId, forceNew: true);
          sendRes = await client.auth.sendCode(
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
        }

        // Handle API_ID errors by rotating credentials pool automatically
        if (err.contains('API_ID_INVALID') || err.contains('API_ID_PUBLISHED_FLOOD')) {
          debugPrint('[TelegramAuthService] API ID invalid ($err), rotating to fallback Telegram API credentials...');
          rotateApiCredentials();
          final freshClient = await getClient(dcId: _currentDcId, forceNew: true);
          final retryRes = await freshClient.auth.sendCode(
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
          return _processSendCodeResult(retryRes, cleanPhone);
        }

        // Handle DC Migration if account is on another Data Center
        if (_isMigrateError(sendRes.error!.errorMessage)) {
          final targetDc = _extractDcFromMigrateError(sendRes.error!.errorMessage);
          debugPrint('[TelegramAuthService] Telegram requires DC migration to DC $targetDc');
          _currentDcId = targetDc;
          try {
            final prefs = await SharedPreferences.getInstance();
            await prefs.setInt('tg_last_dc', targetDc);
          } catch (_) {}

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
      }

      return _processSendCodeResult(sendRes, cleanPhone);
    } catch (e) {
      debugPrint('[TelegramAuthService] MTProto sendCode exception ($e), attempting credentials rotation...');
      try {
        rotateApiCredentials();
        final freshClient = await getClient(dcId: _currentDcId, forceNew: true);
        final retryRes = await freshClient.auth.sendCode(
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
        return _processSendCodeResult(retryRes, cleanPhone);
      } catch (retryErr) {
        debugPrint('[TelegramAuthService] Failover retry error: $retryErr');
        return TelegramAuthResult(
          success: false,
          error: _mapErrorMessage(e.toString()),
        );
      }
    }
  }

  static TelegramAuthResult _processSendCodeResult(t.Result<t.AuthSentCodeBase> res, String phone) {
    if (res.result is t.AuthSentCode) {
      final sentCode = res.result as t.AuthSentCode;
      String delivery = 'app';
      if (sentCode.type is t.AuthSentCodeTypeSms || sentCode.type is t.AuthSentCodeTypeFragmentSms) {
        delivery = 'sms';
      } else if (sentCode.type is t.AuthSentCodeTypeCall || sentCode.type is t.AuthSentCodeTypeFlashCall || sentCode.type is t.AuthSentCodeTypeMissedCall) {
        delivery = 'call';
      }
      debugPrint('[TelegramAuthService] OTP successfully sent by Telegram! Delivery: $delivery, Hash: ${sentCode.phoneCodeHash}');
      return TelegramAuthResult(
        success: true,
        phoneCodeHash: sentCode.phoneCodeHash,
        deliveryType: delivery,
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

  /// Resend verification code via Telegram (requests SMS fallback)
  static Future<TelegramAuthResult> resendCode({
    required String phone,
    required String phoneCodeHash,
  }) async {
    final cleanPhone = _normalizePhone(phone);
    try {
      final client = await getClient(dcId: _currentDcId);
      final res = await client.auth.resendCode(
        phoneNumber: cleanPhone,
        phoneCodeHash: phoneCodeHash,
      );
      return _processSendCodeResult(res, cleanPhone);
    } catch (e) {
      debugPrint('[TelegramAuthService] resendCode error: $e');
      return TelegramAuthResult(success: false, error: _mapRpcError(e.toString()));
    }
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

      debugPrint('[TelegramAuthService] Successfully logged in! User: $userId ($username) on DC $_currentDcId');
      try {
        SharedPreferences.getInstance().then((prefs) => prefs.setInt('tg_last_dc', _currentDcId));
      } catch (_) {}
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
  static final Set<int> _authorizedDcs = {};
  static final Map<int, int> _docDcMap = {};
  static int _currentDcId = 2;
  static bool _dcLoadedFromPrefs = false;

  static Future<int> getMasterDcId() async {
    if (_dcLoadedFromPrefs && _currentDcId != 0 && _currentDcId != 4) return _currentDcId;
    try {
      final prefs = await SharedPreferences.getInstance();
      final phone = prefs.getString(AppConstants.keyUserPhone) ?? '';
      final savedDc = prefs.getInt('tg_last_dc');

      debugPrint('[TelegramAuthService] 🔍 getMasterDcId check: phone=$phone, savedDc=$savedDc, currentDcId=$_currentDcId');

      if (phone.isNotEmpty) {
        final expectedDc = getBestInitialDc(phone);
        _currentDcId = expectedDc;
        _dcLoadedFromPrefs = true;
        await prefs.setInt('tg_last_dc', expectedDc);
        debugPrint('[TelegramAuthService] 🎯 Master DC resolved from phone $phone -> DC $_currentDcId');
        return _currentDcId;
      }

      if (savedDc != null && savedDc >= 1 && savedDc <= 5 && savedDc != 4) {
        _currentDcId = savedDc;
      } else {
        _currentDcId = 5; // Default for Indian subcontinent
      }
      _dcLoadedFromPrefs = true;
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
    final masterDc = await getMasterDcId();
    final cachedDocDc = _docDcMap[docId];
    final targetDc = (cachedDocDc != null && cachedDocDc >= 1 && cachedDocDc <= 5)
        ? cachedDocDc
        : ((dcId >= 1 && dcId <= 5) ? dcId : masterDc);

    final location = t.InputDocumentFileLocation(
      id: docId,
      accessHash: accessHash,
      fileReference: fileReference,
      thumbSize: '',
    );

    for (int attempt = 0; attempt < 2; attempt++) {
      try {
        final client = await getClient(dcId: targetDc, forceNew: attempt > 0);
        final res = await client.upload.getFile(
          precise: true,
          cdnSupported: false,
          location: location,
          offset: offset,
          limit: limit,
        ).timeout(const Duration(seconds: 25));

        if (res.result is t.UploadFile) {
          final uploadFile = res.result as t.UploadFile;
          return Uint8List.fromList(uploadFile.bytes);
        }

        if (res.error != null) {
          final err = res.error!.errorMessage;
          debugPrint('[TelegramAuthService] getFile error on DC $targetDc: ${res.error!.errorCode} - $err');
          if (_isMigrateError(err)) {
            final migratedDc = _extractDcFromMigrateError(err);
            debugPrint('[TelegramAuthService] 🔄 File requires migration to DC $migratedDc for doc $docId');
            _docDcMap[docId] = migratedDc;
            return downloadFileChunk(
              dcId: migratedDc,
              docId: docId,
              accessHash: accessHash,
              fileReference: fileReference,
              offset: offset,
              limit: limit,
            );
          }
          if (err.contains('AUTH_KEY_UNREGISTERED') ||
              err.contains('AUTH_KEY_INVALID') ||
              err.contains('SESSION_REVOKED') ||
              err.contains('SESSION_EXPIRED')) {
            debugPrint('[TelegramAuthService] AuthKey invalid on DC $targetDc, clearing key');
            _clientsByDc.remove(targetDc);
            _socketsByDc.remove(targetDc)?.destroy();
            _socketsByDc.remove(targetDc);
            _authorizedDcs.remove(targetDc);
            _authKeysByDc.remove(targetDc);
            try {
              final prefs = await SharedPreferences.getInstance();
              await prefs.remove('tg_auth_key_dc_$targetDc');
            } catch (_) {}
          }
        }
      } catch (e) {
        debugPrint('[TelegramAuthService] downloadFileChunk attempt $attempt note on DC $targetDc: $e');
        // Close broken socket so next attempt gets a fresh connection,
        // but KEEP cached authKey so we avoid expensive DH key computation on UI thread
        _clientsByDc.remove(targetDc);
        _socketsByDc.remove(targetDc)?.destroy();
        _socketsByDc.remove(targetDc);
      }
    }
    return null;
  }

  /// Establish or retrieve existing MTProto client connection to specified DC
  static Future<tg.Client> getClient({int? dcId, bool forceNew = false}) async {
    final masterDc = await getMasterDcId();
    final targetDc = dcId ?? masterDc;

    final existingSocket = _socketsByDc[targetDc];
    if (!forceNew && _clientsByDc.containsKey(targetDc) && existingSocket != null && existingSocket.isAlive) {
      return _clientsByDc[targetDc]!;
    }

    // Deduplicate all in-flight connection requests for the same DC to prevent DH handshake CPU storms
    if (_clientFuturesByDc.containsKey(targetDc)) {
      return await _clientFuturesByDc[targetDc]!;
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

  /// Blazing-fast parallel socket racer (Happy Eyeballs / RFC 8305)
  /// Concurrently probes candidate endpoints to connect within 150-300ms without sequential blocking
  static Future<Socket> _connectFastSocket(int targetDc, int masterDc) async {
    final dc = _dcOptions[targetDc] ?? _dcOptions[2]!;
    final candidateIps = _dcIps[targetDc] ?? [dc.ipAddress];

    final completer = Completer<Socket>();

    void handleSuccess(Socket s, String ip, int port) {
      if (!completer.isCompleted) {
        debugPrint('[TelegramAuthService] ⚡ Fast TCP connected to DC $targetDc via $ip:$port');
        completer.complete(s);
      } else {
        try {
          s.destroy();
        } catch (_) {}
      }
    }

    // Launch concurrent parallel connection attempts on HTTPS 443
    for (final ip in candidateIps) {
      Socket.connect(ip, 443, timeout: const Duration(milliseconds: 2500)).then((s) {
        handleSuccess(s, ip, 443);
      }).catchError((e) {
        // If 443 fails for this IP, try HTTP port 80 as fallback
        Socket.connect(ip, 80, timeout: const Duration(milliseconds: 2000)).then((s) {
          handleSuccess(s, ip, 80);
        }).catchError((_) {});
      });
    }

    try {
      return await completer.future.timeout(const Duration(milliseconds: 3500));
    } catch (_) {
      debugPrint('[TelegramAuthService] Fallback direct connect to primary DC $targetDc endpoint...');
      return await Socket.connect(dc.ipAddress, dc.port, timeout: const Duration(seconds: 3));
    }
  }

  static final Map<int, tg.AuthorizationKey> _authKeysByDc = {};

  static Future<tg.AuthorizationKey> _authorizeInIsolate(int targetDc, String ip, int port) async {
    final jsonMap = await Isolate.run<Map<String, dynamic>>(() async {
      final rawSocket = await Socket.connect(ip, port, timeout: const Duration(seconds: 8));
      final socket = _IoSocket(rawSocket);
      final obfuscation = tg.Obfuscation.random(false, targetDc);
      final idGenerator = tg.MessageIdGenerator();
      await socket.send(obfuscation.preamble);
      final key = await tg.Client.authorize(socket, obfuscation, idGenerator);
      socket.destroy();
      return key.toJson();
    });
    return tg.AuthorizationKey.fromJson(jsonMap);
  }

  static Future<tg.Client> _doConnectClient({
    required int targetDc,
    required int masterDc,
    required bool forceNew,
  }) async {
    // Close previous socket if forcing new connection, but NEVER purge the auth key!
    if (forceNew) {
      if (_socketsByDc.containsKey(targetDc)) {
        _socketsByDc[targetDc]?.destroy();
        _socketsByDc.remove(targetDc);
      }
      _clientsByDc.remove(targetDc);
      _authorizedDcs.remove(targetDc);
    }

    // Always check for cached AuthKey for this DC to prevent expensive 4s DH isolate computation
    tg.AuthorizationKey? authKey = await _loadCachedAuthKey(targetDc);

    if (authKey == null) {
      debugPrint('[TelegramAuthService] 🚀 Running MTProto DH exchange in background isolate for DC $targetDc (zero UI lag)...');
      final dc = _dcOptions[targetDc] ?? _dcOptions[2]!;
      final candidateIps = _dcIps[targetDc] ?? [dc.ipAddress];
      final connectIp = candidateIps.first;

      try {
        authKey = await _authorizeInIsolate(targetDc, connectIp, 443);
      } catch (e) {
        debugPrint('[TelegramAuthService] Background DH on 443 note ($e), trying primary endpoint...');
        authKey = await _authorizeInIsolate(targetDc, dc.ipAddress, dc.port);
      }
      await _saveCachedAuthKey(targetDc, authKey);
      debugPrint('[TelegramAuthService] ✅ New AuthKey established for DC $targetDc: ${authKey.id}');
    } else {
      debugPrint('[TelegramAuthService] Reusing cached AuthKey for DC $targetDc: ${authKey.id}');
    }

    final rawSocket = await _connectFastSocket(targetDc, masterDc);

    final socket = _IoSocket(rawSocket, onDisconnected: () {
      _clientsByDc.remove(targetDc);
      _socketsByDc.remove(targetDc);
      _authorizedDcs.remove(targetDc);
    });
    _socketsByDc[targetDc] = socket;

    final obfuscation = tg.Obfuscation.random(false, targetDc);
    final idGenerator = tg.MessageIdGenerator();

    await socket.send(obfuscation.preamble);

    final client = tg.Client(
      socket: socket,
      obfuscation: obfuscation,
      authorizationKey: authKey,
      idGenerator: idGenerator,
    );

    // 1. MUST ALWAYS initialize connection with MTProto on EVERY DC (Master or Secondary)
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
      ).timeout(const Duration(seconds: 10));

      if (cfg.result != null && targetDc == masterDc) {
        for (final item in cfg.result!.dcOptions) {
          if (item is t.DcOption && !item.ipv6 && !item.mediaOnly && !item.cdn) {
            _dcOptions.putIfAbsent(item.id, () => item);
          }
        }
      }
    } catch (e) {
      debugPrint('[TelegramAuthService] initConnection DC $targetDc note: $e');
    }

    _clientsByDc[targetDc] = client;
    debugPrint('[TelegramAuthService] 📡 Connected to DC $targetDc (Master DC: $masterDc)');

    // 2. Transfer auth to secondary DC (Required per MTProto session for downloading files)
    if (targetDc != masterDc) {
      try {
        final masterClient = _clientsByDc[masterDc] ?? await getClient(dcId: masterDc);
        final exported = await masterClient.auth.exportAuthorization(dcId: targetDc).timeout(const Duration(seconds: 15));
        if (exported.result is t.AuthExportedAuthorization) {
          final exp = exported.result as t.AuthExportedAuthorization;
          final impRes = await client.auth.importAuthorization(
            id: exp.id,
            bytes: Uint8List.fromList(exp.bytes),
          ).timeout(const Duration(seconds: 15));
          if (impRes.result is t.AuthAuthorization) {
            _authorizedDcs.add(targetDc);
            debugPrint('[TelegramAuthService] 🔑 Successfully exported & imported auth from Master DC $masterDc to Target DC $targetDc');
          } else {
            debugPrint('[TelegramAuthService] ⚠️ importAuthorization error on DC $targetDc: ${impRes.error?.errorMessage}');
            _authorizedDcs.remove(targetDc);
            _authKeysByDc.remove(targetDc);
            try {
              final prefs = await SharedPreferences.getInstance();
              await prefs.remove('tg_auth_key_dc_$targetDc');
            } catch (_) {}
          }
        } else {
          debugPrint('[TelegramAuthService] ⚠️ exportAuthorization error for DC $targetDc: ${exported.error?.errorMessage}');
        }
      } catch (e) {
        debugPrint('[TelegramAuthService] Export/Import auth note: $e');
      }
    }

    return client;
  }

  /// Expose cached auth key JSON for background isolate workers
  static Future<Map<String, dynamic>?> getCachedAuthKeyJson(int dcId) async {
    final key = await _loadCachedAuthKey(dcId);
    return key?.toJson();
  }

  static Future<tg.AuthorizationKey?> _loadCachedAuthKey(int dcId) async {
    if (_authKeysByDc.containsKey(dcId)) {
      return _authKeysByDc[dcId];
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      final keyJson = prefs.getString('tg_auth_key_dc_$dcId');
      if (keyJson != null && keyJson.isNotEmpty) {
        final map = jsonDecode(keyJson) as Map<String, dynamic>;
        final ak = tg.AuthorizationKey.fromJson(map);
        _authKeysByDc[dcId] = ak;
        return ak;
      }
    } catch (e) {
      debugPrint('[TelegramAuthService] Failed to load cached auth key: $e');
    }
    return null;
  }

  static Future<void> _saveCachedAuthKey(int dcId, tg.AuthorizationKey authKey) async {
    _authKeysByDc[dcId] = authKey;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('tg_auth_key_dc_$dcId', jsonEncode(authKey.toJson()));
      // Note: NEVER overwrite tg_last_dc or _currentDcId here. That is reserved strictly for primary user login DC.
    } catch (e) {
      debugPrint('[TelegramAuthService] Failed to save cached auth key: $e');
    }
  }

  /// Reset all MTProto socket connections, cached clients, and stored auth keys
  static Future<void> reset() async {
    for (final s in _socketsByDc.values) {
      try {
        s.destroy();
      } catch (_) {}
    }
    _socketsByDc.clear();
    _clientsByDc.clear();
    _clientFuturesByDc.clear();
    _authorizedDcs.clear();
    _docDcMap.clear();
    _authKeysByDc.clear();
    _dcLoadedFromPrefs = false;
    try {
      final prefs = await SharedPreferences.getInstance();
      for (int i = 1; i <= 5; i++) {
        await prefs.remove('tg_auth_key_dc_$i');
      }
      await prefs.remove('tg_last_dc');
    } catch (_) {}
    debugPrint('[TelegramAuthService] All MTProto connections and auth keys successfully reset');
  }

  static bool isMigrateError(String error) {
    return error.contains('MIGRATE_');
  }

  static int extractDcFromMigrateError(String error) {
    return _extractDcFromMigrateError(error);
  }

  static bool _isMigrateError(String error) {
    return error.contains('MIGRATE_');
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
    if (rpcError.contains('SEND_CODE_UNAVAILABLE')) {
      return 'SMS delivery is unavailable. Telegram has sent the code directly to your Telegram app. Please open Telegram and check the "Telegram" notification chat.';
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

