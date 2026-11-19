import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:intl_phone_field/intl_phone_field.dart';
import 'package:pgme/core_ios/widgets/app_dialog.dart';
import 'package:pgme/features_ios/auth/providers/auth_provider.dart';
import 'package:pgme/core_ios/utils/responsive_helper.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final FocusNode _phoneFocusNode = FocusNode();
  String _completePhoneNumber = '';
  bool _isLoading = false;
  bool _agreedToTerms = false;

  // Dark blue background color
  static const Color _darkBlue = Color(0xFF0000CC);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _phoneFocusNode.unfocus();
    });
  }

  @override
  void dispose() {
    _phoneFocusNode.dispose();
    super.dispose();
  }

  Future<void> _sendOTP() async {
    if (!_agreedToTerms) {
      showAppDialog(context, message: 'Please agree to the Terms and Conditions to continue');
      return;
    }

    if (!(_formKey.currentState?.validate() ?? false)) {
      showAppDialog(context, message: 'Please enter a valid mobile number');
      return;
    }

    setState(() => _isLoading = true);

    try {
      final provider = context.read<AuthProvider>();
      final phoneNumber = _completePhoneNumber.replaceFirst('+', '');

      debugPrint('Sending OTP to: $phoneNumber');
      final success = await provider.sendOTP(phoneNumber);

      if (success && mounted) {
        debugPrint('OTP sent successfully, navigating to verification screen');
        context.push('/otp-verification');
      } else if (mounted) {
        debugPrint('OTP sending failed: success = false');
        showAppDialog(context, message: 'Failed to send OTP. Please try again.');
      }
    } catch (e) {
      debugPrint('OTP sending error: $e');
      if (mounted) {
        showAppDialog(context, message: e.toString().replaceAll('Exception: ', ''));
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.of(context).padding.bottom;
    final keyboardHeight = MediaQuery.of(context).viewInsets.bottom;
    final isKeyboardOpen = keyboardHeight > 0;
    final isTablet = ResponsiveHelper.isTablet(context);
    final isLandscape = ResponsiveHelper.isLandscape(context);

    // Responsive form width: constrained on tablets
    final formMaxWidth = isTablet ? 520.0 : 327.0;

    // On tablet, only shrink header if keyboard would actually cover the button
    // Tablet screens are tall enough that the keyboard rarely covers content
    final screenHeight = MediaQuery.of(context).size.height;
    final keyboardCoversButton = isKeyboardOpen && (screenHeight - keyboardHeight) < (isTablet ? 600 : 450);
    final shouldShrinkHeader = isTablet ? keyboardCoversButton : isKeyboardOpen;

    final headerHeight = shouldShrinkHeader
        ? (isTablet ? 170.0 : 120.0)
        : (isTablet
            ? (isLandscape ? 220.0 : 420.0)
            : 198.0);
    final titleSize = shouldShrinkHeader
        ? (isTablet ? 36.0 : 24.0)
        : (isTablet ? 46.0 : 28.0);
    final subtitleSize = shouldShrinkHeader
        ? (isTablet ? 20.0 : 14.0)
        : (isTablet ? 24.0 : 16.0);
    final inputHeight = isTablet ? 66.0 : 52.0;
    final buttonHeight = isTablet ? 78.0 : 56.0;
    final inputFontSize = isTablet ? 20.0 : 16.0;
    final buttonFontSize = isTablet ? 21.0 : 16.0;

    return Scaffold(
      backgroundColor: _darkBlue,
      resizeToAvoidBottomInset: false,
      body: isLandscape && isTablet
          ? _buildLandscapeLayout(
              formMaxWidth: formMaxWidth,
              titleSize: titleSize,
              subtitleSize: subtitleSize,
              inputHeight: inputHeight,
              buttonHeight: buttonHeight,
              inputFontSize: inputFontSize,
              buttonFontSize: buttonFontSize,
              bottomPadding: bottomPadding,
              keyboardHeight: keyboardHeight,
              isTablet: isTablet,
            )
          : _buildPortraitLayout(
              headerHeight: headerHeight,
              formMaxWidth: formMaxWidth,
              titleSize: titleSize,
              subtitleSize: subtitleSize,
              inputHeight: inputHeight,
              buttonHeight: buttonHeight,
              inputFontSize: inputFontSize,
              buttonFontSize: buttonFontSize,
              bottomPadding: bottomPadding,
              keyboardHeight: keyboardHeight,
              isKeyboardOpen: isKeyboardOpen,
              isTablet: isTablet,
              shouldShrinkHeader: shouldShrinkHeader,
            ),
    );
  }

  /// Landscape layout: side-by-side blue header and white form
  Widget _buildLandscapeLayout({
    required double formMaxWidth,
    required double titleSize,
    required double subtitleSize,
    required double inputHeight,
    required double buttonHeight,
    required double inputFontSize,
    required double buttonFontSize,
    required double bottomPadding,
    required double keyboardHeight,
    required bool isTablet,
  }) {
    return Row(
      children: [
        // Left blue section with illustration + title
        Expanded(
          flex: 4,
          child: SafeArea(
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: _buildLoginIllustration(120),
                  ),
                  Text(
                    'Login',
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
                    'Enter your mobile number to\nreceive an OTP',
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
                  child: _buildFormContent(
                    formMaxWidth: formMaxWidth,
                    inputHeight: inputHeight,
                    buttonHeight: buttonHeight,
                    inputFontSize: inputFontSize,
                    buttonFontSize: buttonFontSize,
                    isTablet: isTablet,
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// Portrait layout: stacked header and form
  Widget _buildPortraitLayout({
    required double headerHeight,
    required double formMaxWidth,
    required double titleSize,
    required double subtitleSize,
    required double inputHeight,
    required double buttonHeight,
    required double inputFontSize,
    required double buttonFontSize,
    required double bottomPadding,
    required double keyboardHeight,
    required bool isKeyboardOpen,
    required bool isTablet,
    required bool shouldShrinkHeader,
  }) {
    return Column(
      children: [
        // Blue header section with illustration + title
        SafeArea(
          bottom: false,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            height: headerHeight,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Login illustration - only on tablet when keyboard is closed
                if (isTablet && !shouldShrinkHeader)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 20),
                    child: _buildLoginIllustration(140),
                  ),
                Text(
                  'Login',
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
                  'Enter your mobile number to\nreceive an OTP',
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
        ),

        // White bottom container with rounded top corners
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
                padding: EdgeInsets.fromLTRB(isTablet ? 32 : 24, isTablet ? 52 : 40, isTablet ? 32 : 24, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    _buildFormContent(
                      formMaxWidth: formMaxWidth,
                      inputHeight: inputHeight,
                      buttonHeight: buttonHeight,
                      inputFontSize: inputFontSize,
                      buttonFontSize: buttonFontSize,
                      isTablet: isTablet,
                    ),

                    const Spacer(),

                    // Bottom padding to account for keyboard
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

  /// Login illustration: person avatar with lock badge (tablet only)
  Widget _buildLoginIllustration(double size) {
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
          // Main circle with person icon
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
              Icons.person_outline_rounded,
              size: size * 0.42,
              color: Colors.white.withValues(alpha: 0.9),
            ),
          ),
          // Lock badge (bottom-right)
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
                Icons.lock_rounded,
                size: size * 0.16,
                color: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Shared form content (input + button)
  Widget _buildFormContent({
    required double formMaxWidth,
    required double inputHeight,
    required double buttonHeight,
    required double inputFontSize,
    required double buttonFontSize,
    required bool isTablet,
  }) {
    final labelSize = isTablet ? 18.0 : 14.0;
    final hintSize = isTablet ? 17.0 : 14.0;
    final inputRadius = isTablet ? 28.0 : 24.0;
    final buttonRadius = isTablet ? 32.0 : 28.0;
    final inputPaddingH = isTablet ? 22.0 : 16.0;
    final inputPaddingV = isTablet ? 18.0 : 14.0;
    final labelInputGap = isTablet ? 16.0 : 12.0;
    final inputButtonGap = isTablet ? 32.0 : 24.0;

    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: formMaxWidth),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Mobile Number label
          Text(
            'Mobile Number',
            style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: labelSize,
              fontWeight: FontWeight.w500,
              color: const Color(0xFF78828A),
            ),
          ),

          SizedBox(height: labelInputGap),

          // Mobile Number Input
          Form(
            key: _formKey,
            child: IntlPhoneField(
              focusNode: _phoneFocusNode,
              initialCountryCode: 'IN',
              disableLengthCheck: false,
              invalidNumberMessage: 'Invalid mobile number',
              keyboardType: TextInputType.phone,
              textInputAction: TextInputAction.done,
              autofocus: false,
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: inputFontSize,
                fontWeight: FontWeight.w400,
                color: const Color(0xFF333333),
              ),
              dropdownTextStyle: TextStyle(
                fontFamily: 'Poppins',
                fontSize: inputFontSize,
                fontWeight: FontWeight.w400,
                color: const Color(0xFF333333),
              ),
              flagsButtonPadding: const EdgeInsets.only(left: 8),
              decoration: InputDecoration(
                hintText: 'Enter your mobile number',
                hintStyle: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: hintSize,
                  fontWeight: FontWeight.w400,
                  color: const Color(0xFFAAAAAA),
                ),
                filled: true,
                fillColor: const Color(0xFFF6F8FE),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(inputRadius),
                  borderSide: const BorderSide(color: Color(0xFFD0D5DD)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(inputRadius),
                  borderSide: const BorderSide(color: Color(0xFFD0D5DD)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(inputRadius),
                  borderSide: const BorderSide(color: Color(0xFFD0D5DD)),
                ),
                counterText: '',
                contentPadding: EdgeInsets.symmetric(horizontal: inputPaddingH, vertical: inputPaddingV),
              ),
              onChanged: (phone) => _completePhoneNumber = phone.completeNumber,
              onSubmitted: (_) => _sendOTP(),
            ),
          ),

          SizedBox(height: isTablet ? 20.0 : 16.0),

          // Terms and Conditions checkbox
          GestureDetector(
            onTap: () => setState(() => _agreedToTerms = !_agreedToTerms),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                SizedBox(
                  width: isTablet ? 26.0 : 22.0,
                  height: isTablet ? 26.0 : 22.0,
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(isTablet ? 7.0 : 6.0),
                      border: Border.all(
                        color: _agreedToTerms ? _darkBlue : const Color(0xFFD0D5DD),
                        width: 1.5,
                      ),
                      color: _agreedToTerms ? _darkBlue : Colors.transparent,
                    ),
                    child: _agreedToTerms
                        ? Icon(
                            Icons.check,
                            size: isTablet ? 18.0 : 14.0,
                            color: Colors.white,
                          )
                        : null,
                  ),
                ),
                SizedBox(width: isTablet ? 12.0 : 8.0),
                Expanded(
                  child: Text.rich(
                    TextSpan(
                      text: 'I agree to the ',
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: isTablet ? 15.0 : 12.0,
                        fontWeight: FontWeight.w400,
                        color: const Color(0xFF78828A),
                      ),
                      children: [
                        WidgetSpan(
                          alignment: PlaceholderAlignment.baseline,
                          baseline: TextBaseline.alphabetic,
                          child: GestureDetector(
                            onTap: () => context.push('/terms-and-conditions'),
                            child: Text(
                              'Terms and Conditions',
                              style: TextStyle(
                                fontFamily: 'Poppins',
                                fontSize: isTablet ? 15.0 : 12.0,
                                fontWeight: FontWeight.w600,
                                color: _darkBlue,
                                decoration: TextDecoration.underline,
                                decorationColor: _darkBlue,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),

          SizedBox(height: inputButtonGap),

          // Continue with Mobile Number Button
          SizedBox(
            width: double.infinity,
            height: buttonHeight,
            child: ElevatedButton(
              onPressed: _isLoading ? null : _sendOTP,
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
                      'Continue with Mobile Number',
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
        ],
      ),
    );
  }
}
