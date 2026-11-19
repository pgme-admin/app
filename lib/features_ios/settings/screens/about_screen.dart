import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:pgme/core_ios/providers/theme_provider.dart';
import 'package:pgme/core_ios/theme/app_theme.dart';
import 'package:pgme/core_ios/utils/responsive_helper.dart';

class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  static const String _version = '2.0.3';
  static const String _buildNumber = '10';

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final isDark = themeProvider.isDarkMode;
    final isTablet = ResponsiveHelper.isTablet(context);

    // Theme-aware colors
    final backgroundColor = isDark ? AppColors.darkBackground : Colors.white;
    final cardColor = isDark ? AppColors.darkCardBackground : const Color(0xFFF5F5F5);
    final textColor = isDark ? AppColors.darkTextPrimary : const Color(0xFF000000);
    final secondaryTextColor = isDark ? AppColors.darkTextSecondary : const Color(0xFF888888);
    final accentColor = isDark ? const Color(0xFF90CAF9) : const Color(0xFF0000D1);

    final hPadding = isTablet ? ResponsiveHelper.horizontalPadding(context) : 16.0;

    return Scaffold(
      backgroundColor: backgroundColor,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Padding(
              padding: EdgeInsets.all(isTablet ? 20 : 16),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () => context.pop(),
                    child: Container(
                      width: isTablet ? 54 : 44,
                      height: isTablet ? 54 : 44,
                      decoration: BoxDecoration(
                        color: cardColor,
                        borderRadius: BorderRadius.circular(isTablet ? 16 : 12),
                      ),
                      child: Center(
                        child: Icon(
                          Icons.arrow_back_ios_new,
                          size: isTablet ? 22 : 18,
                          color: textColor,
                        ),
                      ),
                    ),
                  ),
                  SizedBox(width: isTablet ? 20 : 16),
                  Text(
                    'About',
                    style: TextStyle(
                      fontFamily: 'SF Pro Display',
                      fontWeight: FontWeight.w600,
                      fontSize: isTablet ? 25 : 20,
                      color: textColor,
                    ),
                  ),
                ],
              ),
            ),

            Expanded(
              child: SingleChildScrollView(
                padding: EdgeInsets.symmetric(horizontal: hPadding),
                child: Center(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: ResponsiveHelper.getMaxContentWidth(context)),
                    child: Column(
                      children: [
                        SizedBox(height: isTablet ? 20 : 16),

                        // App Logo and Info
                        Container(
                          width: double.infinity,
                          padding: EdgeInsets.all(isTablet ? 30 : 24),
                          decoration: BoxDecoration(
                            color: isDark
                                ? const Color(0xFF1A1A4D)
                                : const Color(0xFF0000D1).withValues(alpha: 0.05),
                            borderRadius: BorderRadius.circular(isTablet ? 21 : 16),
                            border: Border.all(
                              color: isDark
                                  ? const Color(0xFF3D3D8C)
                                  : const Color(0xFF0000D1).withValues(alpha: 0.2),
                            ),
                          ),
                          child: Column(
                            children: [
                              // Logo
                              Image.asset(
                                'assets/illustrations/logo2.png',
                                width: isTablet ? 150 : 120,
                                height: isTablet ? 50 : 40,
                                errorBuilder: (context, error, stackTrace) {
                                  return Container(
                                    width: isTablet ? 150 : 120,
                                    height: isTablet ? 50 : 40,
                                    decoration: BoxDecoration(
                                      color: accentColor.withValues(alpha: 0.1),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Center(
                                      child: Text(
                                        'PGME',
                                        style: TextStyle(
                                          fontFamily: 'SF Pro Display',
                                          fontWeight: FontWeight.w700,
                                          fontSize: isTablet ? 30 : 24,
                                          color: accentColor,
                                        ),
                                      ),
                                    ),
                                  );
                                },
                              ),
                              SizedBox(height: isTablet ? 20 : 16),
                              Text(
                                'PGME',
                                style: TextStyle(
                                  fontFamily: 'SF Pro Display',
                                  fontWeight: FontWeight.w700,
                                  fontSize: isTablet ? 30 : 24,
                                  color: textColor,
                                ),
                              ),
                              SizedBox(height: isTablet ? 6 : 4),
                              Text(
                                'Postgraduate Medical Education',
                                style: TextStyle(
                                  fontFamily: 'SF Pro Display',
                                  fontSize: isTablet ? 17 : 14,
                                  color: secondaryTextColor,
                                ),
                              ),
                              SizedBox(height: isTablet ? 16 : 12),
                              Container(
                                padding: EdgeInsets.symmetric(horizontal: isTablet ? 16 : 12, vertical: isTablet ? 8 : 6),
                                decoration: BoxDecoration(
                                  color: accentColor.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Text(
                                  'Version $_version (${_buildNumber.isNotEmpty ? _buildNumber : "1"})',
                                  style: TextStyle(
                                    fontFamily: 'SF Pro Display',
                                    fontWeight: FontWeight.w500,
                                    fontSize: isTablet ? 16 : 13,
                                    color: accentColor,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),

                        SizedBox(height: isTablet ? 30 : 24),

                        // About Description
                        Text(
                          'About PGME',
                          style: TextStyle(
                            fontFamily: 'SF Pro Display',
                            fontWeight: FontWeight.w500,
                            fontSize: isTablet ? 20 : 16,
                            letterSpacing: -0.5,
                            color: textColor,
                          ),
                        ),
                        SizedBox(height: isTablet ? 16 : 12),

                        Container(
                          width: double.infinity,
                          padding: EdgeInsets.all(isTablet ? 20 : 16),
                          decoration: BoxDecoration(
                            color: cardColor,
                            borderRadius: BorderRadius.circular(isTablet ? 16 : 12),
                          ),
                          child: Text(
                            'PGME provides specialized postgraduate residency courses featuring high-yield theory revision packages and national level online mock practical Examinations. Tailored for MD/DNB residents and faculty, the curriculum focuses on core concept mastery and clinical skill evaluation. The platform offers interactive live sessions and recorded lectures, empowering candidates to strengthen both theoretical and practical aspects of medical training.',
                            style: TextStyle(
                              fontFamily: 'SF Pro Display',
                              fontSize: isTablet ? 17 : 14,
                              height: 1.6,
                              color: secondaryTextColor,
                            ),
                          ),
                        ),

                        SizedBox(height: isTablet ? 30 : 24),

                        // Key Offerings
                        Text(
                          'What We Offer',
                          style: TextStyle(
                            fontFamily: 'SF Pro Display',
                            fontWeight: FontWeight.w500,
                            fontSize: isTablet ? 20 : 16,
                            letterSpacing: -0.5,
                            color: textColor,
                          ),
                        ),
                        SizedBox(height: isTablet ? 16 : 12),

                        _buildFeatureItem(
                          icon: Icons.book_outlined,
                          title: 'Theory Revision Packages',
                          subtitle: 'High-yield content for core concepts',
                          cardColor: cardColor,
                          iconBgColor: isDark ? const Color(0xFF1A1A4D) : const Color(0xFFE3F2FD),
                          iconColor: isDark ? const Color(0xFF90CAF9) : const Color(0xFF1976D2),
                          textColor: textColor,
                          secondaryTextColor: secondaryTextColor,
                          isTablet: isTablet,
                        ),
                        SizedBox(height: isTablet ? 10 : 8),

                        _buildFeatureItem(
                          icon: Icons.assignment_outlined,
                          title: 'Mock Practical Exams',
                          subtitle: 'National level clinical evaluation',
                          cardColor: cardColor,
                          iconBgColor: isDark ? const Color(0xFF1A4D1A) : const Color(0xFFE8F5E9),
                          iconColor: Colors.green,
                          textColor: textColor,
                          secondaryTextColor: secondaryTextColor,
                          isTablet: isTablet,
                        ),
                        SizedBox(height: isTablet ? 10 : 8),

                        _buildFeatureItem(
                          icon: Icons.live_tv_outlined,
                          title: 'Interactive Live Sessions',
                          subtitle: 'Real-time learning with expert faculty',
                          cardColor: cardColor,
                          iconBgColor: isDark ? const Color(0xFF4D1A1A) : const Color(0xFFFFEBEE),
                          iconColor: Colors.red,
                          textColor: textColor,
                          secondaryTextColor: secondaryTextColor,
                          isTablet: isTablet,
                        ),
                        SizedBox(height: isTablet ? 10 : 8),

                        _buildFeatureItem(
                          icon: Icons.play_circle_outline,
                          title: 'Recorded Lectures',
                          subtitle: 'Learn at your own pace, anytime',
                          cardColor: cardColor,
                          iconBgColor: isDark ? const Color(0xFF4D4D1A) : const Color(0xFFFFF8E1),
                          iconColor: Colors.orange,
                          textColor: textColor,
                          secondaryTextColor: secondaryTextColor,
                          isTablet: isTablet,
                        ),
                        SizedBox(height: isTablet ? 10 : 8),

                        _buildFeatureItem(
                          icon: Icons.school_outlined,
                          title: 'For MD/DNB Residents',
                          subtitle: 'Curriculum designed by experts',
                          cardColor: cardColor,
                          iconBgColor: isDark ? const Color(0xFF2D1A4D) : const Color(0xFFF3E5F5),
                          iconColor: Colors.purple,
                          textColor: textColor,
                          secondaryTextColor: secondaryTextColor,
                          isTablet: isTablet,
                        ),

                        SizedBox(height: isTablet ? 30 : 24),

                        // Legal Links
                        Text(
                          'Legal',
                          style: TextStyle(
                            fontFamily: 'SF Pro Display',
                            fontWeight: FontWeight.w500,
                            fontSize: isTablet ? 20 : 16,
                            letterSpacing: -0.5,
                            color: textColor,
                          ),
                        ),
                        SizedBox(height: isTablet ? 16 : 12),

                        _buildLinkItem(
                          icon: Icons.description_outlined,
                          title: 'Terms of Service',
                          cardColor: cardColor,
                          textColor: textColor,
                          secondaryTextColor: secondaryTextColor,
                          onTap: () => context.push('/terms-and-conditions'),
                          isTablet: isTablet,
                        ),
                        SizedBox(height: isTablet ? 10 : 8),

                        _buildLinkItem(
                          icon: Icons.privacy_tip_outlined,
                          title: 'Privacy Policy',
                          cardColor: cardColor,
                          textColor: textColor,
                          secondaryTextColor: secondaryTextColor,
                          onTap: () => context.push('/privacy-policy'),
                          isTablet: isTablet,
                        ),
                        // Refund policy link hidden on iOS

                        SizedBox(height: isTablet ? 30 : 24),

                        // Copyright
                        Text(
                          '\u00A9 ${DateTime.now().year} PGME MEDICAL EDUCATION LLP. All rights reserved.',
                          style: TextStyle(
                            fontFamily: 'SF Pro Display',
                            fontSize: isTablet ? 15 : 12,
                            color: secondaryTextColor,
                          ),
                          textAlign: TextAlign.center,
                        ),

                        SizedBox(height: isTablet ? 40 : 32),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFeatureItem({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color cardColor,
    required Color iconBgColor,
    required Color iconColor,
    required Color textColor,
    required Color secondaryTextColor,
    bool isTablet = false,
  }) {
    return Container(
      padding: EdgeInsets.all(isTablet ? 18 : 14),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(isTablet ? 16 : 12),
      ),
      child: Row(
        children: [
          Container(
            width: isTablet ? 55 : 44,
            height: isTablet ? 55 : 44,
            decoration: BoxDecoration(
              color: iconBgColor,
              borderRadius: BorderRadius.circular(isTablet ? 16 : 12),
            ),
            child: Center(
              child: Icon(
                icon,
                size: isTablet ? 27 : 22,
                color: iconColor,
              ),
            ),
          ),
          SizedBox(width: isTablet ? 18 : 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontWeight: FontWeight.w600,
                    fontSize: isTablet ? 17 : 14,
                    color: textColor,
                  ),
                ),
                SizedBox(height: isTablet ? 3 : 2),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontWeight: FontWeight.w400,
                    fontSize: isTablet ? 15 : 12,
                    color: secondaryTextColor,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLinkItem({
    required IconData icon,
    required String title,
    required Color cardColor,
    required Color textColor,
    required Color secondaryTextColor,
    required VoidCallback onTap,
    bool isTablet = false,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.all(isTablet ? 18 : 14),
        decoration: BoxDecoration(
          color: cardColor,
          borderRadius: BorderRadius.circular(isTablet ? 16 : 12),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              size: isTablet ? 27 : 22,
              color: secondaryTextColor,
            ),
            SizedBox(width: isTablet ? 18 : 14),
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontWeight: FontWeight.w500,
                  fontSize: isTablet ? 17 : 14,
                  color: textColor,
                ),
              ),
            ),
            Icon(
              Icons.arrow_forward_ios,
              size: isTablet ? 20 : 16,
              color: secondaryTextColor,
            ),
          ],
        ),
      ),
    );
  }
}
