import 'dart:io';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'package:pgme/core/providers/theme_provider.dart';
import 'package:pgme/core/theme/app_theme.dart';

import 'package:pgme/features/auth/providers/auth_provider.dart';
import 'package:pgme/features/home/providers/dashboard_provider.dart';
import 'package:pgme/features/home/widgets/live_class_carousel.dart';
import 'package:pgme/features/home/widgets/for_you_section.dart';
import 'package:pgme/features/home/widgets/faculty_list.dart';
import 'package:pgme/features/home/widgets/home_sections_list.dart';
import 'package:pgme/core/utils/responsive_helper.dart';

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

  /// Workshops entry — same full-width gradient tile as the e-books card, in
  /// the brand blue so the two read as siblings rather than competing CTAs.
  Widget _buildWorkshopsSection(bool isDark, Color textColor, bool isTablet) {
    final cardHeight = ResponsiveHelper.orderBookCardHeight(context);
    final hPad = isTablet ? ResponsiveHelper.horizontalPadding(context) : 16.0;

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: hPad),
      child: GestureDetector(
        onTap: () => context.push('/workshops'),
        child: Container(
          width: double.infinity,
          height: cardHeight,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(isTablet ? 24 : 14),
            // The design-system gradient, so this reads as the same family as
            // the rest of the app rather than a one-off blue.
            gradient: isDark
                ? const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFF10294F), Color(0xFF0A1B33)],
                  )
                : AppColors.blueGradient,
          ),
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: isTablet ? 24 : 16,
              vertical: isTablet ? 20 : 14,
            ),
            child: Row(
              children: [
                Container(
                  width: isTablet ? 58 : 44,
                  height: isTablet ? 58 : 44,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(isTablet ? 16 : 12),
                  ),
                  child: Icon(
                    Icons.calendar_month_rounded,
                    size: isTablet ? 32 : 26,
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
                        'Workshops',
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          fontWeight: FontWeight.w600,
                          fontSize: isTablet ? 22 : 16,
                          color: Colors.white,
                        ),
                      ),
                      SizedBox(height: isTablet ? 4 : 2),
                      Text(
                        'Multi-day live programmes',
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          fontWeight: FontWeight.w400,
                          fontSize: isTablet ? 15 : 12,
                          color: Colors.white.withValues(alpha: 0.75),
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.arrow_forward_ios_rounded,
                  size: isTablet ? 20 : 16,
                  color: Colors.white.withValues(alpha: 0.8),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Browse-all entry point for the package catalogue.
  ///
  /// The Theory and Practical tiles above only cover the two types the
  /// dashboard knows how to render, so any other type an admin creates —
  /// Combos in particular — had no route to it: `/all-packages` was reachable
  /// only from a dialog buried behind those tiles. This surfaces it directly.
  ///
  /// Deliberately tonal rather than another filled gradient: stacked directly
  /// above the Workshops tile, a second gradient would read as a competing
  /// CTA instead of a browse affordance.
  Widget _buildAllPackagesSection(bool isDark, Color textColor, bool isTablet) {
    final hPad = isTablet ? ResponsiveHelper.horizontalPadding(context) : 16.0;
    final accent = isDark ? AppColors.secondaryBlue : AppColors.primaryBlue;

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: hPad),
      child: GestureDetector(
        onTap: () => context.push('/all-packages'),
        child: Container(
          width: double.infinity,
          decoration: BoxDecoration(
            color: isDark ? AppColors.darkCardBackground : AppColors.cardBackground,
            borderRadius: BorderRadius.circular(isTablet ? 24 : 14),
            border: Border.all(
              color: accent.withValues(alpha: isDark ? 0.35 : 0.18),
              width: isTablet ? 1.5 : 1,
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
                  width: isTablet ? 58 : 44,
                  height: isTablet ? 58 : 44,
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: isDark ? 0.22 : 0.10),
                    borderRadius: BorderRadius.circular(isTablet ? 16 : 12),
                  ),
                  child: Icon(
                    Icons.grid_view_rounded,
                    size: isTablet ? 32 : 26,
                    color: accent,
                  ),
                ),
                SizedBox(width: isTablet ? 16 : 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        'All Packages',
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          fontWeight: FontWeight.w600,
                          fontSize: isTablet ? 22 : 16,
                          color: textColor,
                        ),
                      ),
                      SizedBox(height: isTablet ? 4 : 2),
                      Text(
                        'Theory, Practical & Combos',
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          fontWeight: FontWeight.w400,
                          fontSize: isTablet ? 15 : 12,
                          color: isDark
                              ? AppColors.darkTextSecondary
                              : AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.arrow_forward_ios_rounded,
                  size: isTablet ? 20 : 16,
                  color: accent,
                ),
              ],
            ),
          ),
        ),
      ),
    );
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
                      width: isTablet ? 58 : 44,
                      height: isTablet ? 58 : 44,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(isTablet ? 16 : 12),
                      ),
                      child: Icon(
                        Icons.menu_book_rounded,
                        size: isTablet ? 32 : 26,
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
                            Platform.isIOS ? 'E-Books' : 'Buy E-Books',
                            style: TextStyle(
                              fontFamily: 'Poppins',
                              fontWeight: FontWeight.w600,
                              fontSize: isTablet ? 22 : 16,
                              color: Colors.white,
                            ),
                          ),
                          SizedBox(height: isTablet ? 4 : 2),
                          Text(
                            Platform.isIOS ? 'Browse study materials' : 'Browse and purchase study materials',
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
                                    size: isTablet ? 38 : 30,
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
                                        size: isTablet ? 38 : 26,
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

                      // Full package catalogue — shown to everyone, since the
                      // Theory/Practical tiles above are gated on a purchase
                      // and never list Combos.
                      _buildAllPackagesSection(isDark, textColor, isTablet),

                      SizedBox(height: isTablet ? 36 : 24),

                      // Workshops (multi-day live programmes)
                      _buildWorkshopsSection(isDark, textColor, isTablet),

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
