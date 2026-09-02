import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/toast_utils.dart';
import '../../../providers/auth_provider.dart';
import '../../../providers/theme_provider.dart';
import '../../widgets/app_layout_scaffold.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _otpController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  @override
  void dispose() {
    _phoneController.dispose();
    _otpController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _navigateToDashboard() {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const AppLayoutScaffold()),
    );
  }

  Future<void> _handleSendOtp() async {
    final phone = _phoneController.text.trim();
    final auth = context.read<AuthProvider>();

    auth.clearError();
    if (phone.isEmpty) {
      auth.setPhoneNumber('');
      return;
    }

    // Auth provider sets isSendingOtp=true and handles the loading state
    final res = await auth.sendOtpCode(phone);

    if (res.success) {
      // Clear OTP field for fresh entry of real Telegram verification code
      _otpController.clear();
      if (mounted) {
        ToastUtils.showSnackBar(context, 'OTP sent to your Telegram app', isSuccess: true);
      }
    } else {
      if (mounted && res.error != null && res.error!.isNotEmpty) {
        ToastUtils.showSnackBar(context, res.error!, isError: true);
      }
    }
  }

  Future<void> _handleVerifyOtp() async {
    final code = _otpController.text.trim();
    final auth = context.read<AuthProvider>();

    auth.clearError();
    if (code.isEmpty) return;

    final res = await auth.verifyOtpCode(code);

    if (res.success) {
      _navigateToDashboard();
    }
  }

  void _showTelegramAppGuidanceDialog() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: isDark ? const Color(0xFF131D31) : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            const Icon(Icons.telegram_rounded, color: Color(0xFF0088CC), size: 28),
            const SizedBox(width: 10),
            Text(
              'Code is in Telegram',
              style: GoogleFonts.inter(
                fontWeight: FontWeight.w700,
                fontSize: 16,
                color: isDark ? Colors.white : const Color(0xFF0F172A),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Telegram does not send SMS to registered numbers. Your 5-digit login code was sent directly inside your Telegram app.\n',
              style: GoogleFonts.inter(
                fontSize: 13,
                height: 1.4,
                color: isDark ? const Color(0xFFCBD5E1) : const Color(0xFF334155),
              ),
            ),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('1. Open your Telegram app on this phone or PC', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  Text('2. Look for the chat named "Telegram" (with blue verified badge)', style: GoogleFonts.inter(fontSize: 12)),
                  const SizedBox(height: 4),
                  Text('3. Copy the 5-digit code and enter it here', style: GoogleFonts.inter(fontSize: 12)),
                ],
              ),
            ),
          ],
        ),
        actions: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Got it, I\'ll check Telegram'),
          ),
        ],
      ),
    );
  }

  Future<void> _handleResendOtp() async {
    final auth = context.read<AuthProvider>();
    final res = await auth.resendOtpCode();
    if (res.success) {
      if (mounted) {
        final dest = auth.deliveryType == 'sms' ? 'SMS' : 'Telegram app';
        ToastUtils.showSnackBar(context, 'New code requested via $dest', isSuccess: true);
      }
    } else if (mounted) {
      if (res.error != null && res.error!.contains('SEND_CODE_UNAVAILABLE')) {
        _showTelegramAppGuidanceDialog();
      } else if (res.error != null && res.error!.isNotEmpty) {
        ToastUtils.showSnackBar(context, res.error!, isError: true);
      }
    }
  }

  Future<void> _handleVerify2Fa() async {
    final pass = _passwordController.text;
    final auth = context.read<AuthProvider>();

    auth.clearError();
    if (pass.isEmpty) return;

    final res = await auth.verify2FaPassword(pass);

    if (res.success) {
      _navigateToDashboard();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final themeProvider = context.watch<ThemeProvider>();
    final authProvider = context.watch<AuthProvider>();

    final cardBg = isDark ? const Color(0xFF131D31) : Colors.white;
    final borderColor = isDark ? const Color(0xFF22324E) : const Color(0xFFCBD5E1);
    final inputBg = isDark ? const Color(0xFF0B1120) : const Color(0xFFF8FAFC);
    final textPrimary = isDark ? Colors.white : const Color(0xFF0F172A);
    final textSecondary = isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B);

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0B1120) : const Color(0xFFF1F5F9),
      body: Stack(
        children: [
          // Background Glow Accent
          Positioned(
            top: MediaQuery.of(context).size.height * 0.25 - 120,
            left: MediaQuery.of(context).size.width * 0.5 - 140,
            child: Container(
              width: 280,
              height: 280,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.primary.withValues(alpha: isDark ? 0.12 : 0.08),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.primary.withValues(alpha: isDark ? 0.18 : 0.1),
                    blurRadius: 100,
                    spreadRadius: 40,
                  ),
                ],
              ),
            ),
          ),

          // Top Header Theme Toggle Button
          SafeArea(
            child: Align(
              alignment: Alignment.topRight,
              child: Padding(
                padding: const EdgeInsets.only(top: 14, right: 16),
                child: Material(
                  color: isDark ? const Color(0xFF1E293B) : Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  elevation: 0,
                  child: InkWell(
                    onTap: () => themeProvider.toggleTheme(),
                    borderRadius: BorderRadius.circular(14),
                    child: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: borderColor, width: 1),
                      ),
                      child: Icon(
                        isDark ? Icons.wb_sunny_rounded : Icons.nightlight_round,
                        size: 20,
                        color: isDark ? const Color(0xFFFBBF24) : const Color(0xFF475569),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),

          // Main Center Card
          Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 440),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
                  decoration: BoxDecoration(
                    color: cardBg,
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: borderColor, width: 1),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: isDark ? 0.35 : 0.06),
                        blurRadius: 24,
                        offset: const Offset(0, 10),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Branding Icon
                      Container(
                        width: 58,
                        height: 58,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(18),
                          boxShadow: [
                            BoxShadow(
                              color: AppColors.primary.withValues(alpha: 0.25),
                              blurRadius: 14,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(18),
                          child: Image.asset(
                            'assets/logo.png',
                            width: 58,
                            height: 58,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => Container(
                              color: AppColors.primary,
                              child: const Icon(Icons.send_rounded, color: Colors.white, size: 28),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),

                      // Title: TeleLearn
                      RichText(
                        text: TextSpan(
                          style: GoogleFonts.inter(
                            fontSize: 24,
                            fontWeight: FontWeight.w800,
                            color: textPrimary,
                          ),
                          children: const [
                            TextSpan(text: 'Tele'),
                            TextSpan(
                              text: 'Learn',
                              style: TextStyle(color: AppColors.primary),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'High-speed learning platform synced with your Telegram courses',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          height: 1.4,
                          color: textSecondary,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 24),

                      // Step Indicator Pills
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          _buildStepPill(
                            icon: Icons.phone_android_rounded,
                            label: 'Phone',
                            isActive: authProvider.authStep == 1,
                            isDark: isDark,
                          ),
                          Container(
                            width: 16,
                            height: 2,
                            margin: const EdgeInsets.symmetric(horizontal: 6),
                            color: isDark ? const Color(0xFF334155) : const Color(0xFFCBD5E1),
                          ),
                          _buildStepPill(
                            icon: Icons.vpn_key_rounded,
                            label: 'Code',
                            isActive: authProvider.authStep == 2,
                            isDark: isDark,
                          ),
                          if (authProvider.authStep == 3) ...[
                            Container(
                              width: 16,
                              height: 2,
                              margin: const EdgeInsets.symmetric(horizontal: 6),
                              color: isDark ? const Color(0xFF334155) : const Color(0xFFCBD5E1),
                            ),
                            _buildStepPill(
                              icon: Icons.lock_rounded,
                              label: '2FA',
                              isActive: authProvider.authStep == 3,
                              isDark: isDark,
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 22),

                      // Error Notification Banner
                      if (authProvider.errorMessage != null && authProvider.errorMessage!.isNotEmpty) ...[
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                          decoration: BoxDecoration(
                            color: isDark ? const Color(0xFF450A0A).withValues(alpha: 0.5) : const Color(0xFFFEF2F2),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: isDark ? const Color(0xFF991B1B) : const Color(0xFFFECACA),
                              width: 1,
                            ),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Icon(Icons.error_outline_rounded, color: Color(0xFFDC2626), size: 18),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  authProvider.errorMessage!,
                                  style: GoogleFonts.inter(
                                    fontSize: 12,
                                    color: const Color(0xFFDC2626),
                                    fontWeight: FontWeight.w500,
                                    height: 1.35,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 18),
                      ],

                      // ── STEP 1: Phone Input ──────────────────────────────────
                      if (authProvider.authStep == 1) ...[
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            'TELEGRAM PHONE NUMBER',
                            style: GoogleFonts.inter(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.5,
                              color: isDark ? const Color(0xFFCBD5E1) : const Color(0xFF475569),
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: _phoneController,
                          keyboardType: TextInputType.phone,
                          style: GoogleFonts.inter(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: textPrimary,
                          ),
                          decoration: InputDecoration(
                            hintText: '+91 98XXX XXXXX',
                            hintStyle: GoogleFonts.inter(
                              color: isDark ? const Color(0xFF64748B) : const Color(0xFF94A3B8),
                            ),
                            filled: true,
                            fillColor: inputBg,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: BorderSide(color: borderColor),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: BorderSide(color: borderColor),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: const BorderSide(color: AppColors.primary, width: 2),
                            ),
                          ),
                          onSubmitted: (_) => _handleSendOtp(),
                        ),
                        const SizedBox(height: 6),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            'Include country code (e.g. +91 for India, +1 for US)',
                            style: GoogleFonts.inter(
                              fontSize: 11,
                              color: textSecondary,
                            ),
                          ),
                        ),
                        const SizedBox(height: 20),

                        // Send Login Code Button
                        SizedBox(
                          width: double.infinity,
                          height: 48,
                          child: ElevatedButton(
                            onPressed: authProvider.isSendingOtp ? null : _handleSendOtp,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.primary,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                              elevation: 0,
                            ),
                            child: authProvider.isSendingOtp
                                ? Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      const SizedBox(
                                        width: 18,
                                        height: 18,
                                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                      ),
                                      const SizedBox(width: 10),
                                      Text(
                                        'Sending OTP...',
                                        style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600),
                                      ),
                                    ],
                                  )
                                : Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Text(
                                        'Send Login Code',
                                        style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600),
                                      ),
                                      const SizedBox(width: 8),
                                      const Icon(Icons.arrow_forward_rounded, size: 16),
                                    ],
                                  ),
                          ),
                        ),
                      ],

                      // ── STEP 2: OTP Verification ─────────────────────────────
                      if (authProvider.authStep == 2) ...[
                        // Notice Banner: Where did Telegram send the code?
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: authProvider.deliveryType == 'sms'
                                ? (isDark ? const Color(0xFF064E3B).withValues(alpha: 0.5) : const Color(0xFFECFDF5))
                                : (isDark ? const Color(0xFF1E3A8A).withValues(alpha: 0.4) : const Color(0xFFEFF6FF)),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: authProvider.deliveryType == 'sms'
                                  ? (isDark ? const Color(0xFF059669) : const Color(0xFFA7F3D0))
                                  : (isDark ? const Color(0xFF2563EB) : const Color(0xFFBFDBFE)),
                              width: 1.5,
                            ),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(
                                authProvider.deliveryType == 'sms'
                                    ? Icons.sms_rounded
                                    : Icons.telegram_rounded,
                                color: authProvider.deliveryType == 'sms'
                                    ? const Color(0xFF10B981)
                                    : const Color(0xFF3B82F6),
                                size: 24,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      authProvider.deliveryType == 'sms'
                                          ? 'Code sent via SMS'
                                          : 'Check your Telegram App!',
                                      style: GoogleFonts.inter(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w700,
                                        color: authProvider.deliveryType == 'sms'
                                            ? (isDark ? const Color(0xFF6EE7B7) : const Color(0xFF065F46))
                                            : (isDark ? const Color(0xFF93C5FD) : const Color(0xFF1E40AF)),
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      authProvider.deliveryType == 'sms'
                                          ? 'Telegram sent the verification code as an SMS to ${authProvider.phoneNumber}. Check your phone Messages app.'
                                          : 'Telegram does NOT send SMS if you already use Telegram. Open the official Telegram app on your phone to find the code in the "Telegram" service chat.',
                                      style: GoogleFonts.inter(
                                        fontSize: 11.5,
                                        height: 1.4,
                                        fontWeight: FontWeight.w500,
                                        color: isDark ? const Color(0xFFE2E8F0) : const Color(0xFF334155),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 18),

                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'ENTER LOGIN CODE',
                              style: GoogleFonts.inter(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.5,
                                color: isDark ? const Color(0xFFCBD5E1) : const Color(0xFF475569),
                              ),
                            ),
                            InkWell(
                              onTap: () {
                                authProvider.resetAuthStep();
                                _otpController.clear();
                              },
                              child: Text(
                                'Change Phone',
                                style: GoogleFonts.inter(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.primary,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: _otpController,
                          keyboardType: TextInputType.number,
                          textAlign: TextAlign.center,
                          maxLength: 6,
                          style: GoogleFonts.inter(
                            fontSize: 22,
                            letterSpacing: 6,
                            fontWeight: FontWeight.w700,
                            color: textPrimary,
                          ),
                          decoration: InputDecoration(
                            counterText: '',
                            hintText: '•••••',
                            hintStyle: TextStyle(
                              letterSpacing: 6,
                              fontSize: 20,
                              color: isDark ? const Color(0xFF64748B) : const Color(0xFF94A3B8),
                            ),
                            filled: true,
                            fillColor: inputBg,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: BorderSide(color: borderColor),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: BorderSide(color: borderColor),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: const BorderSide(color: AppColors.primary, width: 2),
                            ),
                          ),
                          onSubmitted: (_) => _handleVerifyOtp(),
                        ),
                        const SizedBox(height: 16),

                        // Verify & Enter Dashboard Button
                        SizedBox(
                          width: double.infinity,
                          height: 48,
                          child: ElevatedButton(
                            onPressed: authProvider.isVerifying ? null : _handleVerifyOtp,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.primary,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                              elevation: 0,
                            ),
                            child: authProvider.isVerifying
                                ? Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      const SizedBox(
                                        width: 18,
                                        height: 18,
                                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                      ),
                                      const SizedBox(width: 10),
                                      Text(
                                        'Verifying...',
                                        style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600),
                                      ),
                                    ],
                                  )
                                : Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Text(
                                        'Verify & Enter Dashboard',
                                        style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600),
                                      ),
                                      const SizedBox(width: 8),
                                      const Icon(Icons.check_circle_outline_rounded, size: 18),
                                    ],
                                  ),
                          ),
                        ),
                        const SizedBox(height: 14),

                        // Secondary action: Resend or Send via SMS
                        Center(
                          child: TextButton.icon(
                            onPressed: authProvider.isSendingOtp ? null : _handleResendOtp,
                            icon: Icon(
                              authProvider.deliveryType == 'app' ? Icons.sms_outlined : Icons.refresh_rounded,
                              size: 16,
                            ),
                            label: Text(
                              authProvider.isSendingOtp
                                  ? 'Requesting Code...'
                                  : (authProvider.deliveryType == 'app' ? 'Didn\'t get it? Send via SMS' : 'Resend Code via SMS'),
                              style: GoogleFonts.inter(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                      ],

                      // ── STEP 3: 2FA Password ─────────────────────────────────
                      if (authProvider.authStep == 3) ...[
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            'TWO-STEP VERIFICATION PASSWORD',
                            style: GoogleFonts.inter(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.5,
                              color: isDark ? const Color(0xFFCBD5E1) : const Color(0xFF475569),
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: _passwordController,
                          obscureText: true,
                          style: GoogleFonts.inter(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: textPrimary,
                          ),
                          decoration: InputDecoration(
                            hintText: 'Enter your Telegram 2FA password',
                            hintStyle: GoogleFonts.inter(
                              color: isDark ? const Color(0xFF64748B) : const Color(0xFF94A3B8),
                            ),
                            filled: true,
                            fillColor: inputBg,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: BorderSide(color: borderColor),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: BorderSide(color: borderColor),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: const BorderSide(color: AppColors.primary, width: 2),
                            ),
                          ),
                          onSubmitted: (_) => _handleVerify2Fa(),
                        ),
                        const SizedBox(height: 20),

                        // Unlock Workspace Button
                        SizedBox(
                          width: double.infinity,
                          height: 48,
                          child: ElevatedButton(
                            onPressed: authProvider.isVerifying ? null : _handleVerify2Fa,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.primary,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                              elevation: 0,
                            ),
                            child: authProvider.isVerifying
                                ? Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      const SizedBox(
                                        width: 18,
                                        height: 18,
                                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                      ),
                                      const SizedBox(width: 10),
                                      Text(
                                        'Authenticating...',
                                        style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600),
                                      ),
                                    ],
                                  )
                                : Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      const Icon(Icons.lock_outline_rounded, size: 18),
                                      const SizedBox(width: 8),
                                      Text(
                                        'Unlock Workspace',
                                        style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600),
                                      ),
                                    ],
                                  ),
                          ),
                        ),
                      ],

                      const SizedBox(height: 24),

                      // Footer Security Badge
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.verified_user_rounded, color: Color(0xFF10B981), size: 16),
                          const SizedBox(width: 6),
                          Text(
                            'Encrypted Telegram MTProto Session',
                            style: GoogleFonts.inter(
                              fontSize: 11,
                              color: textSecondary,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStepPill({
    required IconData icon,
    required String label,
    required bool isActive,
    required bool isDark,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: isActive
            ? AppColors.primary
            : (isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 13,
            color: isActive ? Colors.white : (isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B)),
          ),
          const SizedBox(width: 5),
          Text(
            label,
            style: GoogleFonts.inter(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: isActive ? Colors.white : (isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B)),
            ),
          ),
        ],
      ),
    );
  }
}
