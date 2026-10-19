
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'package:pgme/core_ios/providers/theme_provider.dart';
import 'package:pgme/core_ios/theme/app_theme.dart';

import 'package:pgme/core_ios/widgets/how_to_section.dart';
import 'package:pgme/features_ios/auth/providers/auth_provider.dart';
import 'package:pgme/features_ios/home/providers/dashboard_provider.dart';
import 'package:pgme/features_ios/home/widgets/live_class_carousel.dart';
import 'package:pgme/features_ios/home/widgets/for_you_section.dart';
import 'package:pgme/features_ios/home/widgets/faculty_list.dart';
import 'package:pgme/features_ios/home/widgets/home_sections_list.dart';
import 'package:pgme/core_ios/utils/responsive_helper.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  /// Get display name (first name only)
  String _getDisplayName(AuthProvider authProvider) {
    final fullName = authProvider.user?.name;
    if (fullName == null || fullName.isEmpty) {
      return 'User';
    }
    // Return first name only
    final firstName = fullName.split(' ').first;
    return firstName.isNotEmpty ? firstName : 'User';
  }

  /// Build Books Section — two side-by-side cards
  Widget _buildBooksSection(bool isDark, Color textColor, bool isTablet) {
    final cardHeight = ResponsiveHelper.orderBookCardHeight(context);
    final hPad = isTablet ? ResponsiveHelper.horizontalPadding(context) : 16.0;

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: hPad),
      child: GestureDetector(
            onTap: () => context.push('/your-notes'),
            child: Container(
              width: double.infinity,
              height: cardHeight,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(isTablet ? 24 : 14),
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: isDark
                      ? [const Color(0xFF1A3A2E), const Color(0xFF0D2A1C)]
                      : [const Color(0xFF00875A), const Color(0xFF00C853)],
                ),
              ),
              child: Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: isTablet ? 24 : 16,
                  vertical: isTablet ? 20 : 14,
                ),
                child: Row(
                  children: [
                    Container(
                      width: isTablet ? 52 : 40,
                      height: isTablet ? 52 : 40,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(isTablet ? 14 : 10),
                      ),
                      child: Icon(
                        Icons.menu_book_rounded,
                        size: isTablet ? 28 : 22,
                        color: Colors.white,
                      ),
                    ),
                    SizedBox(width: isTablet ? 16 : 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            'E-Books',
                            style: TextStyle(
                              fontFamily: 'Poppins',
                              fontWeight: FontWeight.w600,
                              fontSize: isTablet ? 22 : 16,
                              color: Colors.white,
                            ),
                          ),
                          SizedBox(height: isTablet ? 4 : 2),
                          Text(
                            'Browse study materials',
                            style: TextStyle(
                              fontFamily: 'Poppins',
                              fontWeight: FontWeight.w400,
                              fontSize: isTablet ? 15 : 12,
                              color: Colors.white.withValues(alpha: 0.7),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final topPadding = MediaQuery.of(context).padding.top;
    final themeProvider = Provider.of<ThemeProvider>(context);
    final isDark = themeProvider.isDarkMode;
    final isTablet = ResponsiveHelper.isTablet(context);

    // Theme-aware colors
    final backgroundColor = isDark ? AppColors.darkBackground : Colors.white;
    final textColor = isDark ? AppColors.darkTextPrimary : const Color(0xFF000000);

    // Responsive sizes
    final actionBtnSize = ResponsiveHelper.actionButtonSize(context);
    final greetingFontSize = isTablet ? 30.0 : 20.0;
    final subtitleFontSize = isTablet ? 18.0 : 13.0;
    final hPadding = isTablet ? ResponsiveHelper.horizontalPadding(context) : 16.0;

    return Scaffold(
      backgroundColor: backgroundColor,
      body: Consumer2<AuthProvider, DashboardProvider>(
        builder: (context, authProvider, dashboardProvider, _) {
          final userName = _getDisplayName(authProvider);

          return RefreshIndicator(
            onRefresh: dashboardProvider.refresh,
            displacement: 40,
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(
                parent: ClampingScrollPhysics(),
              ),
              child: Center(
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: ResponsiveHelper.getMaxContentWidth(context),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Header Section
                      Padding(
                        padding: EdgeInsets.only(top: topPadding + 20, left: hPadding, right: hPadding),
                        child: Row(
                              children: [
                                // Profile Icon
                                GestureDetector(
                                  onTap: () => context.push('/profile'),
                                  child: Icon(
                                    Icons.person_outline_rounded,
                                    size: isTablet ? 34 : 28,
                                    color: isDark ? AppColors.darkTextSecondary : const Color(0xFF555555),
                                  ),
                                ),
                                SizedBox(width: isTablet ? 16 : 10),
                                // Greeting
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Hello, $userName!',
                                        style: TextStyle(
                                          fontFamily: 'Poppins',
                                          fontWeight: FontWeight.w600,
                                          fontSize: greetingFontSize,
                                          height: 1.2,
                                          letterSpacing: -0.3,
                                          color: textColor,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        'What do you want to learn today?',
                                        style: TextStyle(
                                          fontFamily: 'Poppins',
                                          fontWeight: FontWeight.w400,
                                          fontSize: subtitleFontSize,
                                          height: 1.3,
                                          color: isDark ? AppColors.darkTextTertiary : const Color(0xFF999999),
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 12),
                                // Theme toggle
                                GestureDetector(
                                  onTap: () => themeProvider.toggleDarkMode(),
                                  child: Container(
                                    width: isTablet ? 66 : 54,
                                    height: isTablet ? 30 : 26,
                                    decoration: BoxDecoration(
                                      color: isDark
                                          ? const Color(0xFF1A1A2E)
                                          : const Color(0xFFE4F4FF),
                                      borderRadius: BorderRadius.circular(44),
                                      border: Border.all(
                                        color: isDark
                                            ? const Color(0xFF00BEFA).withValues(alpha: 0.3)
                                            : const Color(0xFF0000C8).withValues(alpha: 0.15),
                                        width: 1.5,
                                      ),
                                    ),
                                    child: AnimatedAlign(
                                      duration: const Duration(milliseconds: 200),
                                      alignment: isDark ? Alignment.centerRight : Alignment.centerLeft,
                                      child: Container(
                                        width: isTablet ? 24 : 20,
                                        height: isTablet ? 24 : 20,
                                        margin: const EdgeInsets.symmetric(horizontal: 2),
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          color: isDark ? const Color(0xFF00BEFA) : const Color(0xFF0000C8),
                                        ),
                                        child: Icon(
                                          isDark ? Icons.dark_mode_rounded : Icons.light_mode_rounded,
                                          size: isTablet ? 15 : 13,
                                          color: Colors.white,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                GestureDetector(
                                  onTap: () => context.push('/notifications'),
                                  child: Container(
                                    width: actionBtnSize,
                                    height: actionBtnSize,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: isDark ? AppColors.darkSurface : const Color(0xFFF5F5F5),
                                    ),
                                    child: Center(
                                      child: Icon(
                                        Icons.notifications_outlined,
                                        size: isTablet ? 34 : 22,
                                        color: isDark ? AppColors.darkTextSecondary : const Color(0xFF555555),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                      ),

                      SizedBox(height: isTablet ? 40 : 25),

                      // Live Class Carousel (auto-sliding with multiple sessions and banners)
                      if (dashboardProvider.banners.isNotEmpty)
                        LiveClassCarousel(
                          sessions: const [], // Disabled: live sessions now shown via banners
                          banners: dashboardProvider.banners,
                        ),

                      if (dashboardProvider.banners.isNotEmpty)
                        SizedBox(height: isTablet ? 36 : 24),

                      // Subject Section (if available)
                      if (dashboardProvider.primarySubject != null)
                        Padding(
                          padding: EdgeInsets.symmetric(
                            horizontal: isTablet ? ResponsiveHelper.horizontalPadding(context) : 16,
                          ),
                          child: Column(
                                children: [
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(
                                        'Subject',
                                        style: TextStyle(
                                          fontFamily: 'Poppins',
                                          fontWeight: FontWeight.w600,
                                          fontSize: isTablet ? 28.0 : 20.0,
                                          color: textColor,
                                        ),
                                      ),
                                      GestureDetector(
                                        onTap: () => context.push('/subject-selection'),
                                        child: Text(
                                          'Browse All Subjects',
                                          style: TextStyle(
                                            fontFamily: 'Poppins',
                                            fontWeight: FontWeight.w400,
                                            fontSize: isTablet ? 18.0 : 14.0,
                                            color: isDark ? AppColors.darkTextSecondary : AppColors.textSecondary,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  SizedBox(height: isTablet ? 18.0 : 12.0),
                                  Container(
                                    padding: EdgeInsets.symmetric(
                                      horizontal: isTablet ? 28 : 16,
                                      vertical: isTablet ? 14 : 8,
                                    ),
                                    decoration: BoxDecoration(
                                      color: isDark
                                          ? AppColors.darkCardBackground
                                          : const Color(0xFFE3F2FD),
                                      borderRadius: BorderRadius.circular(isTablet ? 28 : 20),
                                    ),
                                    child: Text(
                                      dashboardProvider.primarySubject!.subjectName,
                                      style: TextStyle(
                                        fontFamily: 'Poppins',
                                        fontWeight: FontWeight.w500,
                                        fontSize: isTablet ? 22 : 14,
                                        color: textColor,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                        ),

                      if (dashboardProvider.primarySubject != null) SizedBox(height: isTablet ? 36 : 24),

                      // Content Coming Soon (when subject has no packages)
                      if (!dashboardProvider.isLoadingContent &&
                          dashboardProvider.packages.isEmpty &&
                          dashboardProvider.primarySubject != null)
                        Padding(
                          padding: EdgeInsets.symmetric(
                            horizontal: isTablet ? ResponsiveHelper.horizontalPadding(context) : 16,
                          ),
                          child: Container(
                                width: double.infinity,
                                padding: EdgeInsets.symmetric(
                                  vertical: isTablet ? 48 : 36,
                                  horizontal: isTablet ? 32 : 24,
                                ),
                                decoration: BoxDecoration(
                                  color: isDark
                                      ? AppColors.darkCardBackground
                                      : const Color(0xFFF5F8FF),
                                  borderRadius: BorderRadius.circular(isTablet ? 24 : 16),
                                ),
                                child: Column(
                                  children: [
                                    Icon(
                                      Icons.auto_awesome_rounded,
                                      size: isTablet ? 56 : 44,
                                      color: isDark ? const Color(0xFF00BEFA) : const Color(0xFF0000C8),
                                    ),
                                    SizedBox(height: isTablet ? 16 : 12),
                                    Text(
                                      'We will be live soon',
                                      style: TextStyle(
                                        fontFamily: 'Poppins',
                                        fontWeight: FontWeight.w600,
                                        fontSize: isTablet ? 22 : 17,
                                        color: textColor,
                                      ),
                                    ),
                                    SizedBox(height: isTablet ? 14 : 10),
                                    GestureDetector(
                                      onTap: () => context.push('/careers'),
                                      child: Text.rich(
                                        TextSpan(
                                          text: 'You can ',
                                          style: TextStyle(
                                            fontFamily: 'Poppins',
                                            fontWeight: FontWeight.w400,
                                            fontSize: isTablet ? 16 : 13,
                                            color: isDark ? AppColors.darkTextSecondary : const Color(0xFF666666),
                                          ),
                                          children: [
                                            TextSpan(
                                              text: 'Join the PGME Team',
                                              style: TextStyle(
                                                fontFamily: 'Poppins',
                                                fontWeight: FontWeight.w600,
                                                fontSize: isTablet ? 16 : 13,
                                                color: isDark ? const Color(0xFF00BEFA) : const Color(0xFF0000C8),
                                                decoration: TextDecoration.underline,
                                                decorationColor: isDark ? const Color(0xFF00BEFA) : const Color(0xFF0000C8),
                                              ),
                                            ),
                                          ],
                                        ),
                                        textAlign: TextAlign.center,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                        ),

                      if (!dashboardProvider.isLoadingContent &&
                          dashboardProvider.packages.isEmpty &&
                          dashboardProvider.primarySubject != null)
                        SizedBox(height: isTablet ? 36 : 24),

                      // For You Section (enrolled users)
                      if (dashboardProvider.hasActivePurchase == true &&
                          dashboardProvider.packages.isNotEmpty)
                        ForYouSection(
                          lastWatched: dashboardProvider.lastWatchedVideo,
                          isLoading: dashboardProvider.isLoadingContent,
                          error: dashboardProvider.contentError,
                          onRetry: dashboardProvider.retryContent,
                          hasTheorySubscription: dashboardProvider.hasTheorySubscription,
                          hasPracticalSubscription: dashboardProvider.hasPracticalSubscription,
                        ),

                      if (dashboardProvider.hasActivePurchase == true &&
                          dashboardProvider.packages.isNotEmpty)
                        SizedBox(height: isTablet ? 36 : 24),

                      // Books Section (E-Books + Physical Copies)
                      _buildBooksSection(isDark, textColor, isTablet),

                      SizedBox(height: isTablet ? 36 : 24),

                      // Dynamic Home Sections (from backend)
                      if (dashboardProvider.homeSections.isNotEmpty)
                        HomeSectionsList(
                          sections: dashboardProvider.homeSections,
                        ),

                      // Faculty List
                      FacultyList(
                        faculty: dashboardProvider.facultyList,
                        isLoading: dashboardProvider.isLoadingFaculty,
                        error: dashboardProvider.facultyError,
                        onRetry: dashboardProvider.retryFaculty,
                      ),

                      const HowToSection(screen: 'home'),
                      const SizedBox(height: 100), // Space for bottom nav
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
