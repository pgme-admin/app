import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:pgme/core_ios/providers/theme_provider.dart';
import 'package:pgme/core_ios/theme/app_theme.dart';
import 'package:pgme/core_ios/utils/responsive_helper.dart';
import 'package:pgme/features_ios/home/providers/dashboard_provider.dart';

class SuccessScreen extends StatefulWidget {
  const SuccessScreen({super.key});

  @override
  State<SuccessScreen> createState() => _SuccessScreenState();
}

class _SuccessScreenState extends State<SuccessScreen> {
  @override
  void initState() {
    super.initState();
    // Refresh dashboard in the background so the home screen reflects the new
    // purchase immediately when the user taps "Continue to Dashboard".
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        context.read<DashboardProvider>().refresh();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.of(context).padding.bottom;
    final screenHeight = MediaQuery.of(context).size.height;
    final themeProvider = Provider.of<ThemeProvider>(context);
    final isDark = themeProvider.isDarkMode;
    final isTablet = ResponsiveHelper.isTablet(context);

    // Theme-aware colors
    final backgroundColor = isDark ? AppColors.darkBackground : Colors.white;
    final textColor = isDark ? AppColors.darkTextPrimary : const Color(0xFF000000);
    final cardBgColor = isDark ? AppColors.darkCardBackground : AppColors.cardBackground;
    final buttonColor = isDark ? const Color(0xFF0047CF) : AppColors.primaryBlue;
    final iconColor = isDark ? const Color(0xFF00BEFA) : AppColors.success;

    // Responsive sizes
    final illustrationSize = isTablet ? 580.0 : screenHeight * 0.45;
    final titleSize = isTablet ? 38.0 : 28.0;
    final subtitleSize = isTablet ? 18.0 : 15.0;
    final buttonWidth = isTablet ? 500.0 : 325.0;
    final buttonHeight = isTablet ? 68.0 : 50.0;
    final buttonFontSize = isTablet ? 21.0 : 15.0;
    final hPadding = isTablet ? 40.0 : 28.0;

    return PopScope(
      canPop: false,
      child: Scaffold(
      backgroundColor: backgroundColor,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: isTablet ? 600 : double.infinity),
            child: Column(
              children: [
                const Spacer(flex: 1),

                // Congratulations Illustration
                Image.asset(
                  'assets/illustrations/cong.png',
                  width: illustrationSize,
                  height: illustrationSize,
                  fit: BoxFit.contain,
                  errorBuilder: (context, error, stackTrace) {
                    return Container(
                      width: illustrationSize,
                      height: illustrationSize,
                      decoration: BoxDecoration(
                        color: cardBgColor,
                        borderRadius: BorderRadius.circular(isTablet ? 30 : 24),
                      ),
                      child: Center(
                        child: Icon(
                          Icons.check_circle_outline,
                          size: isTablet ? 120 : 80,
                          color: iconColor,
                        ),
                      ),
                    );
                  },
                ),

                Transform.translate(
                  offset: Offset(0, isTablet ? -110 : -80),
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: hPadding),
                    child: Column(
                      children: [
                        // Title - Congratulations
                        Text(
                          'Congratulations!',
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: titleSize,
                            fontWeight: FontWeight.w700,
                            color: textColor,
                            height: 1.2,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        SizedBox(height: isTablet ? 14 : 10),
                        // Description text
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          child: Text(
                            'Thank you for the purchase! Your package is now active. Start exploring your courses right away.',
                            style: TextStyle(
                              fontFamily: 'Poppins',
                              fontSize: subtitleSize,
                              fontWeight: FontWeight.w400,
                              color: textColor.withValues(alpha: 0.55),
                              height: 1.5,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                const Spacer(flex: 2),

                // Continue to Dashboard Button
                GestureDetector(
                  onTap: () {
                    context.go('/home?subscribed=true');
                  },
                  child: Container(
                    width: buttonWidth,
                    height: buttonHeight,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: buttonColor,
                      borderRadius: BorderRadius.circular(50),
                    ),
                    child: Center(
                      child: Text(
                        'Continue to Dashboard',
                        style: TextStyle(
                          fontFamily: 'Sora',
                          fontSize: buttonFontSize,
                          fontWeight: FontWeight.w600,
                          height: 1.0,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ),

                SizedBox(height: bottomPadding + (isTablet ? 32 : 24)),
              ],
            ),
          ),
        ),
      ),
      ),
    );
  }
}
