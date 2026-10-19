import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:pgme/core_ios/theme/app_theme.dart';
import 'package:pgme/core_ios/utils/responsive_helper.dart';
import 'package:pgme/core_ios/widgets/app_dialog.dart';
import 'package:pgme/features_ios/onboarding/providers/onboarding_provider.dart';
import 'package:pgme/features_ios/auth/providers/auth_provider.dart';

class CongratulationsScreen extends StatefulWidget {
  const CongratulationsScreen({super.key});

  @override
  State<CongratulationsScreen> createState() => _CongratulationsScreenState();
}

class _CongratulationsScreenState extends State<CongratulationsScreen> {
  bool _isCompleting = false;

  Future<void> _completeToDashboard() async {
    if (_isCompleting) return;

    setState(() => _isCompleting = true);

    try {
      final onboardingProvider = context.read<OnboardingProvider>();
      final authProvider = context.read<AuthProvider>();

      // Mark onboarding as complete
      await onboardingProvider.completeOnboarding();

      // Update auth provider state
      if (authProvider.user != null) {
        // Refresh user data to get updated onboarding status
        await authProvider.checkAuthStatus();
      }

      if (mounted) {
        // Clear navigation stack and go to home
        context.go('/home');
      }
    } catch (e) {
      setState(() => _isCompleting = false);

      if (mounted) {
        showAppDialog(context, message: e.toString().replaceAll('Exception: ', ''), actionLabel: 'Try Again', onAction: _completeToDashboard);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final selectedSubject = context.read<OnboardingProvider>().selectedSubject;
    final isTablet = ResponsiveHelper.isTablet(context);

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: ResponsiveHelper.getMaxContentWidth(context),
            ),
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: isTablet ? 48 : 24),
              child: Column(
                children: [
                  const Spacer(),

                  // Success Icon/Illustration
                  Container(
                    width: isTablet ? 280 : 200,
                    height: isTablet ? 280 : 200,
                    decoration: BoxDecoration(
                      color: AppColors.success.withOpacity(0.1),
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: Icon(
                        Icons.check_circle_rounded,
                        size: isTablet ? 170 : 120,
                        color: AppColors.success,
                      ),
                    ),
                  ),

                  SizedBox(height: isTablet ? 50 : 40),

                  // Congratulations Title
                  Text(
                    'Congratulations!',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: isTablet ? 48 : 36,
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFF000000),
                    ),
                  ),

                  SizedBox(height: isTablet ? 20 : 16),

                  // Success Message
                  Text(
                    selectedSubject != null
                        ? 'You\'ve successfully selected ${selectedSubject.name} as your primary subject!'
                        : 'Your profile setup is complete!',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: isTablet ? 22 : 18,
                      fontWeight: FontWeight.w400,
                      color: AppColors.textSecondary,
                      height: 1.4,
                    ),
                  ),

                  SizedBox(height: isTablet ? 20 : 16),

                  // Welcome message
                  Text(
                    'Welcome to PGME!\nLet\'s start your learning journey.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: isTablet ? 20 : 16,
                      fontWeight: FontWeight.w500,
                      color: AppColors.textPrimary,
                      height: 1.4,
                    ),
                  ),

                  const Spacer(),

                  // Continue to Dashboard Button
                  SizedBox(
                    width: double.infinity,
                    height: isTablet ? 68 : 54,
                    child: ElevatedButton(
                      onPressed: _isCompleting ? null : _completeToDashboard,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primaryBlue,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(isTablet ? 28 : 22),
                        ),
                        elevation: 0,
                      ),
                      child: _isCompleting
                          ? SizedBox(
                              width: isTablet ? 28 : 20,
                              height: isTablet ? 28 : 20,
                              child: const CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                              ),
                            )
                          : Text(
                              'Continue to Dashboard',
                              style: TextStyle(
                                fontSize: isTablet ? 20 : 16,
                                fontWeight: FontWeight.w600,
                                color: Colors.white,
                              ),
                            ),
                    ),
                  ),

                  SizedBox(height: isTablet ? 40 : 32),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
