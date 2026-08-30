import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../../core/theme/app_theme.dart';
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
      // Auto-transition: authStep is now 2, clear OTP field for fresh entry
      _otpController.clear();
    }
    // If failed, authProvider.errorMessage is set and displayed automatically
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
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'TELEGRAM LOGIN CODE',
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
                        const SizedBox(height: 6),
                        Text(
                          'Enter the code sent to your Telegram app',
                          textAlign: TextAlign.center,
                          style: GoogleFonts.inter(
                            fontSize: 11,
                            color: textSecondary,
                          ),
                        ),
                        const SizedBox(height: 20),

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
                        const SizedBox(height: 12),
                        Center(
                          child: TextButton.icon(
                            onPressed: authProvider.isSendingOtp ? null : _handleSendOtp,
                            icon: const Icon(Icons.refresh_rounded, size: 16),
                            label: Text(
                              authProvider.isSendingOtp ? 'Resending Code...' : 'Resend Code',
                              style: GoogleFonts.inter(
                                fontSize: 12,
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
