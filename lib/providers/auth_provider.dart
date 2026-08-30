import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/constants/app_constants.dart';
import '../data/models/user_model.dart';
import '../data/services/telegram_auth_service.dart';

class AuthProvider extends ChangeNotifier {
  UserSession? _user;
  bool _isLoading = true;
  bool _isSendingOtp = false;
  bool _isVerifying = false;
  String _phoneNumber = '';
  String _phoneCodeHash = '';
  int _authStep = 1; // 1 = Phone, 2 = OTP, 3 = 2FA Password
  String? _errorMessage;

  UserSession? get user => _user;
  bool get isLoading => _isLoading;
  bool get isLoggedIn => _user?.isLoggedIn ?? false;
  String get phoneNumber => _phoneNumber;
  int get authStep => _authStep;
  String? get errorMessage => _errorMessage;
  bool get isSendingOtp => _isSendingOtp;
  bool get isVerifying => _isVerifying;

  AuthProvider() {
    _checkSavedSession();
  }

  Future<void> _checkSavedSession() async {
    _isLoading = true;
    notifyListeners();

    try {
      final prefs = await SharedPreferences.getInstance();
      final phone = prefs.getString(AppConstants.keyUserPhone);
      final isLoggedIn = prefs.getBool(AppConstants.keyIsLoggedIn) ?? false;

      if (isLoggedIn && phone != null && phone.isNotEmpty) {
        _user = UserSession(phone: phone, isLoggedIn: true);
        _phoneNumber = phone;
      }
    } catch (e) {
      debugPrint('[AuthProvider] Session load error: $e');
    }

    _isLoading = false;
    notifyListeners();
  }

  void setPhoneNumber(String phone) {
    _phoneNumber = phone;
    _errorMessage = null;
    notifyListeners();
  }

  void clearError() {
    _errorMessage = null;
    notifyListeners();
  }

  Future<TelegramAuthResult> sendOtpCode(String phone) async {
    _phoneNumber = phone.trim();
    _errorMessage = null;
    _isSendingOtp = true;
    notifyListeners();

    if (_phoneNumber.isEmpty) {
      _isSendingOtp = false;
      final err = TelegramAuthResult(success: false, error: 'Please enter your Telegram phone number');
      _errorMessage = err.error;
      notifyListeners();
      return err;
    }

    final res = await TelegramAuthService.sendCode(_phoneNumber);

    _isSendingOtp = false;

    if (res.success && res.phoneCodeHash != null) {
      _phoneCodeHash = res.phoneCodeHash!;
      _authStep = 2; // Transition to OTP screen
      _errorMessage = null;
    } else {
      _errorMessage = res.error ?? 'Failed to send verification code. Please try again.';
      // Stay on step 1 so user can retry
    }

    notifyListeners();
    return res;
  }

  Future<TelegramAuthResult> verifyOtpCode(String code) async {
    _errorMessage = null;
    _isVerifying = true;
    notifyListeners();

    final res = await TelegramAuthService.verifyCode(
      phone: _phoneNumber,
      code: code,
      phoneCodeHash: _phoneCodeHash,
    );

    _isVerifying = false;

    if (res.success) {
      _user = UserSession(
        phone: _phoneNumber,
        displayName: res.username != null ? '@${res.username}' : 'Learner ${_phoneNumber.substring(_phoneNumber.length >= 4 ? _phoneNumber.length - 4 : 0)}',
        isLoggedIn: true,
      );
      _authStep = 1;

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(AppConstants.keyUserPhone, _phoneNumber);
      await prefs.setBool(AppConstants.keyIsLoggedIn, true);
    } else if (res.requiresPassword) {
      _authStep = 3;
    } else {
      _errorMessage = res.error ?? 'Invalid verification code.';
    }

    notifyListeners();
    return res;
  }

  Future<TelegramAuthResult> verify2FaPassword(String password) async {
    _errorMessage = null;
    _isVerifying = true;
    notifyListeners();

    final res = await TelegramAuthService.verifyPassword(
      phone: _phoneNumber,
      password: password,
    );

    _isVerifying = false;

    if (res.success) {
      _user = UserSession(
        phone: _phoneNumber,
        displayName: res.username != null ? '@${res.username}' : 'Learner',
        isLoggedIn: true,
      );
      _authStep = 1;

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(AppConstants.keyUserPhone, _phoneNumber);
      await prefs.setBool(AppConstants.keyIsLoggedIn, true);
    } else {
      _errorMessage = res.error ?? 'Invalid 2FA password.';
    }

    notifyListeners();
    return res;
  }

  Future<void> loginOfflineDemo() async {
    const demoPhone = '+919876543210';
    _phoneNumber = demoPhone;
    _user = UserSession(
      phone: demoPhone,
      displayName: 'TeleLearn Scholar',
      isLoggedIn: true,
    );
    _authStep = 1;
    _errorMessage = null;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(AppConstants.keyUserPhone, demoPhone);
    await prefs.setBool(AppConstants.keyIsLoggedIn, true);

    notifyListeners();
  }

  void resetAuthStep() {
    _authStep = 1;
    _errorMessage = null;
    notifyListeners();
  }

  Future<void> logout() async {
    _user = null;
    _phoneNumber = '';
    _phoneCodeHash = '';
    _authStep = 1;
    _errorMessage = null;

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(AppConstants.keyUserPhone);
    await prefs.remove(AppConstants.keyIsLoggedIn);

    notifyListeners();
  }
}
