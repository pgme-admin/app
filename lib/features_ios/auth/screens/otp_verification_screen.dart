import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:pgme/core_ios/theme/app_theme.dart';
import 'package:pgme/core_ios/widgets/app_dialog.dart';
import 'package:pgme/core_ios/widgets/otp_input.dart';
import 'package:pgme/features_ios/auth/providers/auth_provider.dart';
import 'package:pgme/core_ios/utils/responsive_helper.dart';

class OTPVerificationScreen extends StatefulWidget {
  const OTPVerificationScreen({super.key});

  @override
  State<OTPVerificationScreen> createState() => _OTPVerificationScreenState();
}

class _OTPVerificationScreenState extends State<OTPVerificationScreen> {
  String _otp = '';
  bool _isLoading = false;

  // Colors
  static const Color _darkBlue = Color(0xFF0000C8);

  Future<void> _verifyOTP() async {
    if (_otp.length != 4) {
      showAppDialog(context, message: 'Please enter the complete OTP');
      return;
    }

    // Guard against double-submission — e.g. SMS auto-read and Pinput's own
    // onCompleted both firing for the same code. _isLoading otherwise only
    // disables the button, not other callers of this method.
    if (_isLoading) return;

    setState(() => _isLoading = true);

    try {
      final provider = context.read<AuthProvider>();
      final success = await provider.verifyOTP(_otp);

      if (success && mounted) {
        debugPrint('=== OTP Verification Success ===');
        debugPrint('hasMultipleSessions: ${provider.hasMultipleSessions}');
        debugPrint('onboardingCompleted: ${provider.onboardingCompleted}');

        if (!provider.onboardingCompleted) {
          debugPrint('Navigating to: /data-collection');
          context.go('/data-collection');
        } else if (provider.hasMultipleSessions) {
          debugPrint('Navigating to: /multiple-logins');
          context.go('/multiple-logins');
        } else {
          debugPrint('Navigating to: /home');
          context.go('/home');
        }
      }
    } catch (e) {
      if (mounted) {
        showAppDialog(context, message: e.toString().replaceAll('Exception: ', ''));
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _onOTPChanged(String otp) {
    setState(() => _otp = otp);
  }

  void _onOTPCompleted(String otp) {
    setState(() => _otp = otp);
    if (otp.length == 4) {
      _verifyOTP();
    }
  }

  void _resendOTP() {
    // Go back to login screen to resend OTP
    context.pop();
  }

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.of(context).padding.bottom;
    final keyboardHeight = MediaQuery.of(context).viewInsets.bottom;
    final isKeyboardOpen = keyboardHeight > 0;
    final isTablet = ResponsiveHelper.isTablet(context);
    final isLandscape = ResponsiveHelper.isLandscape(context);

    // Smart keyboard detection for tablet
    final screenHeight = MediaQuery.of(context).size.height;
    final keyboardCoversContent = isKeyboardOpen && (screenHeight - keyboardHeight) < (isTablet ? 600 : 450);
    final shouldShrinkHeader = isTablet ? keyboardCoversContent : isKeyboardOpen;

    // Responsive sizes
    final titleSize = isTablet ? 46.0 : 24.0;
    final subtitleSize = isTablet ? 22.0 : 14.0;
    final buttonMaxWidth = isTablet ? 520.0 : 327.0;
    final buttonHeight = isTablet ? 78.0 : 56.0;
    final buttonFontSize = isTablet ? 21.0 : 16.0;
    final buttonRadius = isTablet ? 32.0 : 24.0;
    final backButtonSize = isTablet ? 64.0 : 48.0;
    final backIconSize = isTablet ? 32.0 : 24.0;
    final resendFontSize = isTablet ? 20.0 : 16.0;

    // OTP box sizes
    final otpBoxSize = isTablet ? 76.0 : 56.0;
    final otpFontSize = isTablet ? 32.0 : 24.0;
    final otpSpacing = isTablet ? 24.0 : 16.0;
    final otpBorderRadius = isTablet ? 28.0 : 24.0;

    // Header sizes for tablet portrait
    final headerHeight = shouldShrinkHeader
        ? (isTablet ? 170.0 : 0.0)
        : (isTablet ? 420.0 : 0.0);

    if (isTablet) {
      return Scaffold(
        backgroundColor: _darkBlue,
        resizeToAvoidBottomInset: false,
        body: isLandscape
            ? _buildLandscapeLayout(
                titleSize: titleSize,
                subtitleSize: subtitleSize,
                buttonMaxWidth: buttonMaxWidth,
                buttonHeight: buttonHeight,
                buttonFontSize: buttonFontSize,
                buttonRadius: buttonRadius,
                backButtonSize: backButtonSize,
                backIconSize: backIconSize,
                resendFontSize: resendFontSize,
                otpBoxSize: otpBoxSize,
                otpFontSize: otpFontSize,
                otpSpacing: otpSpacing,
                otpBorderRadius: otpBorderRadius,
                bottomPadding: bottomPadding,
                keyboardHeight: keyboardHeight,
              )
            : _buildTabletPortraitLayout(
                headerHeight: headerHeight,
                shouldShrinkHeader: shouldShrinkHeader,
                titleSize: titleSize,
                subtitleSize: subtitleSize,
                buttonMaxWidth: buttonMaxWidth,
                buttonHeight: buttonHeight,
                buttonFontSize: buttonFontSize,
                buttonRadius: buttonRadius,
                backButtonSize: backButtonSize,
                backIconSize: backIconSize,
                resendFontSize: resendFontSize,
                otpBoxSize: otpBoxSize,
                otpFontSize: otpFontSize,
                otpSpacing: otpSpacing,
                otpBorderRadius: otpBorderRadius,
                bottomPadding: bottomPadding,
                keyboardHeight: keyboardHeight,
              ),
      );
    }

    // Mobile layout (unchanged)
    return Scaffold(
      backgroundColor: Colors.white,
      resizeToAvoidBottomInset: false,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(height: isLandscape ? 8 : 12),

              // Back button
              _buildBackButton(backButtonSize, backIconSize),

              SizedBox(height: isLandscape ? 20 : 32),

              // Enter OTP title
              Center(
                child: Text(
                  'Enter OTP',
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: titleSize,
                    fontWeight: FontWeight.w700,
                    height: 1.33,
                    letterSpacing: 0.12,
                    color: Colors.black,
                  ),
                ),
              ),

              const SizedBox(height: 8),

              // Subtitle
              Center(
                child: Text(
                  'We have just sent you 4 digit code via your\nmobile number',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: subtitleSize,
                    fontWeight: FontWeight.w500,
                    height: 1.57,
                    letterSpacing: 0.07,
                    color: const Color(0xFF78828A),
                  ),
                ),
              ),

              SizedBox(height: isLandscape ? 20 : 32),

              // OTP Input
              Center(
                child: OTPInput(
                  length: 4,
                  onChanged: _onOTPChanged,
                  onCompleted: _onOTPCompleted,
                ),
              ),

              SizedBox(height: isLandscape ? 20 : 32),

              // Continue button
              _buildContinueButton(
                buttonMaxWidth: buttonMaxWidth,
                buttonHeight: buttonHeight,
                buttonFontSize: buttonFontSize,
                buttonRadius: buttonRadius,
                isTablet: false,
              ),

              const SizedBox(height: 24),

              // Resend code
              _buildResendRow(resendFontSize),

              if (!isLandscape) const Spacer(),

              // Bottom padding for keyboard
              SizedBox(height: keyboardHeight > 0 ? keyboardHeight + 16 : bottomPadding + 24),
            ],
          ),
        ),
      ),
    );
  }

  /// Tablet portrait: blue header with illustration + white form below
  Widget _buildTabletPortraitLayout({
    required double headerHeight,
    required bool shouldShrinkHeader,
    required double titleSize,
    required double subtitleSize,
    required double buttonMaxWidth,
    required double buttonHeight,
    required double buttonFontSize,
    required double buttonRadius,
    required double backButtonSize,
    required double backIconSize,
    required double resendFontSize,
    required double otpBoxSize,
    required double otpFontSize,
    required double otpSpacing,
    required double otpBorderRadius,
    required double bottomPadding,
    required double keyboardHeight,
  }) {
    return Column(
      children: [
        // Blue header with illustration
        SafeArea(
          bottom: false,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            height: headerHeight,
            clipBehavior: Clip.hardEdge,
            decoration: const BoxDecoration(),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 16),
                  // Back button (white on blue)
                  _buildBackButton(backButtonSize, backIconSize, onBlue: true),
                  const Spacer(),
                  // Illustration
                  if (!shouldShrinkHeader)
                    Center(
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 20),
                        child: _buildOTPIllustration(140),
                      ),
                    ),
                  Center(
                    child: Text(
                      'Enter OTP',
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: shouldShrinkHeader ? 36.0 : titleSize,
                        fontWeight: FontWeight.w700,
                        height: 1.14,
                        letterSpacing: 0.14,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  if (!shouldShrinkHeader) ...[
                    const SizedBox(height: 8),
                    Center(
                      child: Text(
                        'We have just sent you 4 digit code via your\nmobile number',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: subtitleSize,
                          fontWeight: FontWeight.w500,
                          height: 1.5,
                          letterSpacing: 0.08,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
        ),

        // White form section
        Expanded(
          child: Container(
            width: double.infinity,
            decoration: const BoxDecoration(
              color: Color(0xFFFEFEFE),
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(30),
                topRight: Radius.circular(30),
              ),
            ),
            child: Center(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(32, 52, 32, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    // OTP Input
                    OTPInput(
                      length: 4,
                      onChanged: _onOTPChanged,
                      onCompleted: _onOTPCompleted,
                      boxSize: otpBoxSize,
                      fontSize: otpFontSize,
                      spacing: otpSpacing,
                      borderRadius: otpBorderRadius,
                    ),

                    const SizedBox(height: 40),

                    // Continue button
                    _buildContinueButton(
                      buttonMaxWidth: buttonMaxWidth,
                      buttonHeight: buttonHeight,
                      buttonFontSize: buttonFontSize,
                      buttonRadius: buttonRadius,
                      isTablet: true,
                    ),

                    const SizedBox(height: 32),

                    // Resend code
                    _buildResendRow(resendFontSize),

                    const Spacer(),

                    // Bottom padding for keyboard
                    SizedBox(height: keyboardHeight > 0 ? keyboardHeight + 16 : bottomPadding + 24),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// Tablet landscape: side-by-side blue header and white form
  Widget _buildLandscapeLayout({
    required double titleSize,
    required double subtitleSize,
    required double buttonMaxWidth,
    required double buttonHeight,
    required double buttonFontSize,
    required double buttonRadius,
    required double backButtonSize,
    required double backIconSize,
    required double resendFontSize,
    required double otpBoxSize,
    required double otpFontSize,
    required double otpSpacing,
    required double otpBorderRadius,
    required double bottomPadding,
    required double keyboardHeight,
  }) {
    return Row(
      children: [
        // Left blue section with illustration + title
        Expanded(
          flex: 4,
          child: SafeArea(
            child: Stack(
              children: [
                // Back button top-left
                Positioned(
                  top: 16,
                  left: 32,
                  child: _buildBackButton(backButtonSize, backIconSize, onBlue: true),
                ),
                // Center content
                Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(bottom: 16),
                        child: _buildOTPIllustration(120),
                      ),
                      Text(
                        'Enter OTP',
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: titleSize,
                          fontWeight: FontWeight.w700,
                          height: 1.14,
                          letterSpacing: 0.14,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'We have just sent you 4 digit code\nvia your mobile number',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: subtitleSize,
                          fontWeight: FontWeight.w500,
                          height: 1.5,
                          letterSpacing: 0.08,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        // Right white form section
        Expanded(
          flex: 5,
          child: Container(
            decoration: const BoxDecoration(
              color: Color(0xFFFEFEFE),
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(30),
                bottomLeft: Radius.circular(30),
              ),
            ),
            child: SafeArea(
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // OTP Input
                      OTPInput(
                        length: 4,
                        onChanged: _onOTPChanged,
                        onCompleted: _onOTPCompleted,
                        boxSize: otpBoxSize,
                        fontSize: otpFontSize,
                        spacing: otpSpacing,
                        borderRadius: otpBorderRadius,
                      ),

                      const SizedBox(height: 40),

                      // Continue button
                      _buildContinueButton(
                        buttonMaxWidth: buttonMaxWidth,
                        buttonHeight: buttonHeight,
                        buttonFontSize: buttonFontSize,
                        buttonRadius: buttonRadius,
                        isTablet: true,
                      ),

                      const SizedBox(height: 32),

                      // Resend code
                      _buildResendRow(resendFontSize),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// OTP illustration: shield with checkmark badge (tablet only)
  Widget _buildOTPIllustration(double size) {
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Outer glow ring
          Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.12),
                width: 1.5,
              ),
            ),
          ),
          // Main circle with shield icon
          Container(
            width: size * 0.72,
            height: size * 0.72,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white.withValues(alpha: 0.15),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.25),
                width: 2,
              ),
            ),
            child: Icon(
              Icons.shield_outlined,
              size: size * 0.42,
              color: Colors.white.withValues(alpha: 0.9),
            ),
          ),
          // Checkmark badge (bottom-right)
          Positioned(
            right: size * 0.12,
            bottom: size * 0.10,
            child: Container(
              width: size * 0.30,
              height: size * 0.30,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFF00C2FF),
                border: Border.all(
                  color: const Color(0xFF0000CC),
                  width: 2.5,
                ),
              ),
              child: Icon(
                Icons.check_rounded,
                size: size * 0.16,
                color: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Back button widget
  Widget _buildBackButton(double size, double iconSize, {bool onBlue = false}) {
    return GestureDetector(
      onTap: () => context.pop(),
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: onBlue
              ? Colors.white.withValues(alpha: 0.15)
              : Colors.black.withValues(alpha: 0.08),
          shape: BoxShape.circle,
        ),
        child: Center(
          child: Icon(
            Icons.arrow_back,
            size: iconSize,
            color: onBlue ? Colors.white : Colors.black,
          ),
        ),
      ),
    );
  }

  /// Continue button widget
  Widget _buildContinueButton({
    required double buttonMaxWidth,
    required double buttonHeight,
    required double buttonFontSize,
    required double buttonRadius,
    required bool isTablet,
  }) {
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: buttonMaxWidth),
        child: SizedBox(
          width: double.infinity,
          height: buttonHeight,
          child: ElevatedButton(
            onPressed: _isLoading ? null : _verifyOTP,
            style: ElevatedButton.styleFrom(
              backgroundColor: _darkBlue,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(buttonRadius),
              ),
              elevation: 0,
              padding: EdgeInsets.zero,
              alignment: Alignment.center,
            ),
            child: _isLoading
                ? SizedBox(
                    width: isTablet ? 28.0 : 24.0,
                    height: isTablet ? 28.0 : 24.0,
                    child: const CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  )
                : Text(
                    'Continue',
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: buttonFontSize,
                      fontWeight: FontWeight.w600,
                      height: 1.0,
                      letterSpacing: 0.08,
                      color: Colors.white,
                    ),
                  ),
          ),
        ),
      ),
    );
  }

  /// Resend code row
  Widget _buildResendRow(double fontSize) {
    return Center(
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            "Didn't receive code? ",
            style: TextStyle(
              fontFamily: 'PlusJakartaSans',
              fontSize: fontSize,
              fontWeight: FontWeight.w600,
              height: 1.5,
              letterSpacing: 0.08,
              color: Colors.black,
            ),
          ),
          GestureDetector(
            onTap: _resendOTP,
            child: Text(
              'Resend Code',
              style: TextStyle(
                fontFamily: 'PlusJakartaSans',
                fontSize: fontSize,
                fontWeight: FontWeight.w600,
                height: 1.5,
                letterSpacing: 0.08,
                color: AppColors.primaryBlue,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
