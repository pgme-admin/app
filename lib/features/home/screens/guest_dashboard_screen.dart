import 'dart:io';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'package:pgme/core/providers/theme_provider.dart';
import 'package:pgme/core/theme/app_theme.dart';
import 'package:pgme/core/widgets/app_dialog.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:pgme/features/auth/providers/auth_provider.dart';
import 'package:pgme/features/home/providers/dashboard_provider.dart';
import 'package:pgme/features/home/widgets/live_class_carousel.dart';
import 'package:pgme/features/home/widgets/faculty_list.dart';
import 'package:pgme/features/home/widgets/home_sections_list.dart';
import 'package:pgme/core/utils/responsive_helper.dart';

class GuestDashboardScreen extends StatefulWidget {
  const GuestDashboardScreen({super.key});

  @override
  State<GuestDashboardScreen> createState() => _GuestDashboardScreenState();
}

class _GuestDashboardScreenState extends State<GuestDashboardScreen> {
  /// Get display name (first name only) from AuthProvider
  String _getDisplayName(AuthProvider authProvider) {
    final fullName = authProvider.user?.name;
    if (fullName == null || fullName.isEmpty) {
      return 'User';
    }
    // Return first name only
    final firstName = fullName.split(' ').first;
    return firstName.isNotEmpty ? firstName : 'User';
  }

  @override
  Widget build(BuildContext context) {
    final topPadding = MediaQuery.of(context).padding.top;
    final themeProvider = Provider.of<ThemeProvider>(context);
    final isDark = themeProvider.isDarkMode;
    final isTablet = ResponsiveHelper.isTablet(context);
    final isLandscape = ResponsiveHelper.isLandscape(context);

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
        builder: (context, authProvider, provider, _) {
          final userName = _getDisplayName(authProvider);

          return RefreshIndicator(
            onRefresh: provider.refresh,
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(parent: ClampingScrollPhysics()),
              child: Center(
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: isTablet && isLandscape ? 900 : double.infinity,
                  ),
                  child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header Section
                  Padding(
                    padding: EdgeInsets.only(top: topPadding + 20, left: hPadding, right: hPadding),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          maxWidth: ResponsiveHelper.getMaxContentWidth(context),
                        ),
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
                    ),
                  ),

                  SizedBox(height: isTablet ? 40 : 25),

                  // Live Class Carousel (auto-sliding with multiple sessions and banners)
                  if (provider.upcomingSessions.isNotEmpty || provider.banners.isNotEmpty)
                    LiveClassCarousel(
                      sessions: provider.upcomingSessions,
                      banners: provider.banners,
                    ),

                  if (provider.upcomingSessions.isNotEmpty || provider.banners.isNotEmpty) SizedBox(height: isTablet ? 36.0 : 24.0),

                  // Subject Section (if available)
                  if (provider.primarySubject != null)
                    Padding(
                      padding: EdgeInsets.symmetric(horizontal: isTablet ? 24.0 : 16.0),
                      child: Center(
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                            maxWidth: ResponsiveHelper.getMaxContentWidth(context),
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
                                width: double.infinity,
                                padding: EdgeInsets.symmetric(
                                  horizontal: isTablet ? 28.0 : 16.0,
                                  vertical: isTablet ? 18.0 : 12.0,
                                ),
                                decoration: BoxDecoration(
                                  color: isDark
                                      ? AppColors.darkCardBackground
                                      : const Color(0xFFE3F2FD),
                                  borderRadius: BorderRadius.circular(isTablet ? 28.0 : 20.0),
                                ),
                                child: Center(
                                  child: Text(
                                    provider.primarySubject!.subjectName,
                                    style: TextStyle(
                                      fontFamily: 'Poppins',
                                      fontWeight: FontWeight.w500,
                                      fontSize: isTablet ? 22.0 : 16.0,
                                      color: AppColors.primaryBlue,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),

                  if (provider.primarySubject != null) SizedBox(height: isTablet ? 36.0 : 24.0),

                  // What We Offer Section (guest users - no purchase)
                  // Only show Theory and Practical package types
                  if (provider.hasActivePurchase == false && provider.packageTypes.any((t) => t.name == 'Theory' || t.name == 'Practical'))
                    _buildWhatWeOfferSection(context, provider, isDark, textColor, isTablet),

                  if (provider.hasActivePurchase == false && provider.packageTypes.any((t) => t.name == 'Theory' || t.name == 'Practical'))
                    SizedBox(height: isTablet ? 36.0 : 24.0),

                  // Books Section
                  _buildBooksSection(context, isDark, textColor, isTablet),

                  SizedBox(height: isTablet ? 36.0 : 24.0),

                  // Dynamic Home Sections (from backend)
                  if (provider.homeSections.isNotEmpty)
                    HomeSectionsList(
                      sections: provider.homeSections,
                    ),

                  // Faculty List
                  FacultyList(
                    faculty: provider.facultyList,
                    isLoading: provider.isLoadingFaculty,
                    error: provider.facultyError,
                    onRetry: provider.retryFaculty,
                  ),

                  SizedBox(height: isTablet ? 120.0 : 100.0), // Space for bottom nav
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

  Widget _buildBooksSection(BuildContext context, bool isDark, Color textColor, bool isTablet) {
    final cardHeight = ResponsiveHelper.orderBookCardHeight(context);
    final hPad = isTablet ? ResponsiveHelper.horizontalPadding(context) : 16.0;

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: hPad),
      child: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: ResponsiveHelper.getMaxContentWidth(context),
          ),
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
                    Icon(
                      Icons.arrow_forward_ios_rounded,
                      size: isTablet ? 22 : 16,
                      color: Colors.white.withValues(alpha: 0.6),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildWhatWeOfferSection(
    BuildContext context,
    DashboardProvider provider,
    bool isDark,
    Color textColor,
    bool isTablet,
  ) {
    // Filter to only show Theory and Practical package types
    final filteredTypes = provider.packageTypes
        .where((t) => t.name == 'Theory' || t.name == 'Practical')
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Section Header
        Padding(
          padding: EdgeInsets.symmetric(horizontal: isTablet ? 24.0 : 16.0),
          child: Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: ResponsiveHelper.getMaxContentWidth(context),
              ),
              child: Text(
                'What We Offer',
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontWeight: FontWeight.w600,
                  fontSize: isTablet ? 28.0 : 20.0,
                  color: textColor,
                ),
              ),
            ),
          ),
        ),
        SizedBox(height: isTablet ? 24.0 : 16.0),

        // Package Type Cards
        if (isTablet)
          // Tablet: show cards side by side, no scrolling
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 24.0),
            child: Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: ResponsiveHelper.getMaxContentWidth(context),
                ),
                child: IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (int i = 0; i < filteredTypes.length; i++) ...[
                        if (i > 0) const SizedBox(width: 20),
                        Expanded(
                          child: _buildPackageTypeCard(
                            filteredTypes[i], isDark, textColor, isTablet,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          )
        else
          // Phone: horizontal scroll
          LayoutBuilder(
            builder: (context, constraints) {
              final screenHeight = MediaQuery.of(context).size.height;
              final cardHeight = screenHeight * 0.42;

              return SizedBox(
                height: cardHeight,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16.0),
                  itemCount: filteredTypes.length,
                  itemBuilder: (context, index) {
                    final packageType = filteredTypes[index];
                    final isLast = index == filteredTypes.length - 1;
                    return Padding(
                      padding: EdgeInsets.only(right: isLast ? 0 : 16.0),
                      child: SizedBox(
                        width: MediaQuery.of(context).size.width * 0.75,
                        child: _buildPackageTypeCard(packageType, isDark, textColor, isTablet),
                      ),
                    );
                  },
                ),
              );
            },
          ),
      ],
    );
  }

  Widget _buildPackageTypeCard(packageType, bool isDark, Color textColor, bool isTablet) {
    final cardBgColor = isDark ? AppColors.darkCardBackground : Colors.white;
    final secondaryTextColor = isDark ? AppColors.darkTextSecondary : const Color(0xFF666666);

    final playBtnSize = isTablet ? 80.0 : 64.0;
    final playIconSize = isTablet ? 48.0 : 40.0;
    final cardRadius = isTablet ? 24.0 : 16.0;
    final contentPadding = isTablet ? 24.0 : 16.0;
    final titleSize = isTablet ? 24.0 : 18.0;
    final descSize = isTablet ? 17.0 : 13.0;
    final buttonHeight = isTablet ? 56.0 : 44.0;
    final buttonFontSize = isTablet ? 18.0 : 15.0;
    final buttonRadius = isTablet ? 16.0 : 12.0;

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(cardRadius),
        color: cardBgColor,
        boxShadow: [
          BoxShadow(
            color: isDark ? Colors.black.withValues(alpha: 0.3) : Colors.black.withValues(alpha: 0.08),
            blurRadius: isTablet ? 16 : 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Trailer Video Thumbnail with Play Button
          GestureDetector(
            onTap: packageType.trailerVideoUrl != null
                ? () {
                    context.push(
                      '/trailer-video',
                      extra: {
                        'videoUrl': packageType.trailerVideoUrl,
                        'videoTitle': '${packageType.name} - Trailer',
                      },
                    );
                  }
                : null,
            child: ClipRRect(
              borderRadius: BorderRadius.vertical(top: Radius.circular(cardRadius)),
              child: AspectRatio(
                aspectRatio: 16 / 9,
                child: packageType.thumbnailUrl != null
                    ? Stack(
                        fit: StackFit.expand,
                        children: [
                          // Video thumbnail
                          CachedNetworkImage(
                            imageUrl: packageType.thumbnailUrl!,
                            fit: BoxFit.cover,
                            placeholder: (context, url) => Container(
                              color: isDark ? AppColors.darkSurface : const Color(0xFFF5F5F5),
                              child: const Center(
                                child: CircularProgressIndicator(
                                  valueColor: AlwaysStoppedAnimation<Color>(AppColors.primaryBlue),
                                ),
                              ),
                            ),
                            errorWidget: (context, url, error) => Container(
                              color: isDark ? AppColors.darkSurface : const Color(0xFFF5F5F5),
                              child: Center(
                                child: Icon(
                                  Icons.broken_image,
                                  color: Colors.white54,
                                  size: isTablet ? 60 : 48,
                                ),
                              ),
                            ),
                          ),
                          // Play button overlay (only if trailer URL exists)
                          if (packageType.trailerVideoUrl != null)
                            Center(
                              child: Container(
                                width: playBtnSize,
                                height: playBtnSize,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: Colors.black.withValues(alpha: 0.7),
                                  border: Border.all(
                                    color: Colors.white,
                                    width: isTablet ? 4 : 3,
                                  ),
                                ),
                                child: Icon(
                                  Icons.play_arrow,
                                  size: playIconSize,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                        ],
                      )
                    : Container(
                        color: isDark ? AppColors.darkSurface : const Color(0xFFF5F5F5),
                        child: Center(
                          child: Container(
                            width: playBtnSize,
                            height: playBtnSize,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: secondaryTextColor,
                                width: isTablet ? 3 : 2,
                              ),
                            ),
                            child: Icon(
                              Icons.play_arrow,
                              size: playIconSize,
                              color: secondaryTextColor,
                            ),
                          ),
                        ),
                      ),
              ),
            ),
          ),

          // Content Section
          Padding(
            padding: EdgeInsets.all(contentPadding),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // Package Type Name
                Text(
                  packageType.name ?? 'Package',
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontWeight: FontWeight.w600,
                    fontSize: titleSize,
                    color: textColor,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                SizedBox(height: isTablet ? 12.0 : 8.0),

                // Package Description
                Text(
                  packageType.description ?? 'Explore our comprehensive courses designed to help you succeed.',
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontWeight: FontWeight.w400,
                    fontSize: descSize,
                    height: 1.5,
                    color: secondaryTextColor,
                  ),
                  maxLines: 4,
                  overflow: TextOverflow.ellipsis,
                ),

                SizedBox(height: isTablet ? 18.0 : 12.0),

                // View Package Button
                GestureDetector(
                  onTap: () {
                    final route = packageType.name == 'Practical'
                        ? '/practical-series'
                        : '/revision-series';
                    context.go(route);
                  },
                  child: Container(
                    width: double.infinity,
                    height: buttonHeight,
                    decoration: BoxDecoration(
                      color: AppColors.primaryBlue,
                      borderRadius: BorderRadius.circular(buttonRadius),
                    ),
                    child: Center(
                      child: Text(
                        'View Packages',
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          fontWeight: FontWeight.w600,
                          fontSize: buttonFontSize,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SubjectPickerSheet extends StatefulWidget {
  final bool isDark;
  final DashboardProvider provider;

  const _SubjectPickerSheet({
    required this.isDark,
    required this.provider,
  });

  @override
  State<_SubjectPickerSheet> createState() => _SubjectPickerSheetState();
}

class _SubjectPickerSheetState extends State<_SubjectPickerSheet> {
  String? _selectedSubjectId;

  Future<void> _onSubjectTap(subject) async {
    final isCurrentlySelected = widget.provider.primarySubject?.subjectId == subject.subjectId;
    if (isCurrentlySelected) return;

    setState(() {
      _selectedSubjectId = subject.subjectId;
    });

    final success = await widget.provider.changePrimarySubject(subject);

    if (mounted) {
      Navigator.pop(context);
      if (success) {
        showAppDialog(context, message: 'Subject changed to ${subject.name}', type: AppDialogType.success);
      } else {
        showAppDialog(context, message: 'Failed to change subject');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = widget.isDark;
    final provider = widget.provider;
    final isTablet = ResponsiveHelper.isTablet(context);
    final backgroundColor = isDark ? AppColors.darkCardBackground : Colors.white;
    final textColor = isDark ? AppColors.darkTextPrimary : const Color(0xFF000000);
    final secondaryTextColor = isDark ? AppColors.darkTextSecondary : AppColors.textSecondary;

    final sheetRadius = isTablet ? 32.0 : 24.0;
    final headerPadding = isTablet ? 28.0 : 20.0;
    final titleSize = isTablet ? 26.0 : 20.0;
    final closeIconSize = isTablet ? 30.0 : 24.0;
    final itemIconSize = isTablet ? 64.0 : 48.0;
    final itemIconRadius = isTablet ? 18.0 : 12.0;
    final itemNameSize = isTablet ? 20.0 : 16.0;
    final itemPaddingH = isTablet ? 28.0 : 20.0;
    final itemPaddingV = isTablet ? 16.0 : 12.0;
    final itemGap = isTablet ? 20.0 : 16.0;
    final trailingSize = isTablet ? 30.0 : 24.0;
    final handleWidth = isTablet ? 56.0 : 40.0;

    return Align(
      alignment: Alignment.bottomCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.7,
          maxWidth: isTablet ? 600.0 : double.infinity,
        ),
        child: Container(
          margin: isTablet ? const EdgeInsets.only(bottom: 24) : EdgeInsets.zero,
          decoration: BoxDecoration(
            color: backgroundColor,
            borderRadius: isTablet
                ? BorderRadius.circular(sheetRadius)
                : BorderRadius.vertical(top: Radius.circular(sheetRadius)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Handle bar
              Container(
                margin: EdgeInsets.only(top: isTablet ? 16 : 12),
                width: handleWidth,
                height: isTablet ? 5 : 4,
                decoration: BoxDecoration(
                  color: secondaryTextColor.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(3),
                ),
              ),

              // Header
              Padding(
                padding: EdgeInsets.all(headerPadding),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Select Subject',
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontWeight: FontWeight.w600,
                        fontSize: titleSize,
                        color: textColor,
                      ),
                    ),
                    GestureDetector(
                      onTap: _selectedSubjectId != null ? null : () => Navigator.pop(context),
                      child: Icon(
                        Icons.close,
                        color: _selectedSubjectId != null
                            ? secondaryTextColor.withValues(alpha: 0.3)
                            : secondaryTextColor,
                        size: closeIconSize,
                      ),
                    ),
                  ],
                ),
              ),

              // Divider
              Divider(
                height: 1,
                color: secondaryTextColor.withValues(alpha: 0.2),
              ),

              // Content
              Flexible(
                child: ListenableBuilder(
                  listenable: provider,
                  builder: (context, _) {
                    if (provider.isLoadingAllSubjects) {
                      return const Center(
                        child: Padding(
                          padding: EdgeInsets.all(40),
                          child: CircularProgressIndicator(),
                        ),
                      );
                    }

                    if (provider.allSubjects.isEmpty) {
                      return Center(
                        child: Padding(
                          padding: const EdgeInsets.all(40),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.school_outlined,
                                size: isTablet ? 64 : 48,
                                color: secondaryTextColor,
                              ),
                              SizedBox(height: isTablet ? 18 : 12),
                              Text(
                                'No subjects available',
                                style: TextStyle(
                                  fontFamily: 'Poppins',
                                  fontSize: isTablet ? 20 : 16,
                                  color: secondaryTextColor,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }

                    return ListView.builder(
                      shrinkWrap: true,
                      padding: EdgeInsets.symmetric(vertical: isTablet ? 12 : 8),
                      itemCount: provider.allSubjects.length,
                      itemBuilder: (context, index) {
                        final subject = provider.allSubjects[index];
                        final isCurrentlySelected = provider.primarySubject?.subjectId == subject.subjectId;
                        final isBeingSelected = _selectedSubjectId == subject.subjectId;
                        final isDisabled = _selectedSubjectId != null && !isBeingSelected;

                        return Material(
                          color: Colors.transparent,
                          child: InkWell(
                            onTap: (_selectedSubjectId != null || isCurrentlySelected)
                                ? null
                                : () => _onSubjectTap(subject),
                            splashColor: AppColors.primaryBlue.withValues(alpha: 0.1),
                            highlightColor: AppColors.primaryBlue.withValues(alpha: 0.05),
                            child: Opacity(
                              opacity: isDisabled ? 0.4 : 1.0,
                              child: Padding(
                                padding: EdgeInsets.symmetric(horizontal: itemPaddingH, vertical: itemPaddingV),
                                child: Row(
                                  children: [
                                    // Icon container
                                    Container(
                                      width: itemIconSize,
                                      height: itemIconSize,
                                      decoration: BoxDecoration(
                                        color: isCurrentlySelected || isBeingSelected
                                            ? AppColors.primaryBlue.withValues(alpha: 0.1)
                                            : (isDark ? AppColors.darkSurface : const Color(0xFFF5F5F5)),
                                        borderRadius: BorderRadius.circular(itemIconRadius),
                                        border: isBeingSelected
                                            ? Border.all(color: AppColors.primaryBlue, width: isTablet ? 3 : 2)
                                            : null,
                                      ),
                                      child: subject.iconUrl != null && subject.iconUrl!.isNotEmpty
                                          ? ClipRRect(
                                              borderRadius: BorderRadius.circular(itemIconRadius - 2),
                                              child: Image.network(
                                                subject.iconUrl!,
                                                fit: BoxFit.cover,
                                                errorBuilder: (_, __, ___) => Icon(
                                                  Icons.school_outlined,
                                                  size: isTablet ? 32 : 24,
                                                  color: isCurrentlySelected || isBeingSelected
                                                      ? AppColors.primaryBlue
                                                      : secondaryTextColor,
                                                ),
                                              ),
                                            )
                                          : Icon(
                                              Icons.school_outlined,
                                              size: isTablet ? 32 : 24,
                                              color: isCurrentlySelected || isBeingSelected
                                                  ? AppColors.primaryBlue
                                                  : secondaryTextColor,
                                            ),
                                    ),
                                    SizedBox(width: itemGap),

                                    // Subject name
                                    Expanded(
                                      child: Text(
                                        subject.name,
                                        style: TextStyle(
                                          fontFamily: 'Poppins',
                                          fontWeight: isCurrentlySelected || isBeingSelected
                                              ? FontWeight.w600
                                              : FontWeight.w500,
                                          fontSize: itemNameSize,
                                          color: isCurrentlySelected || isBeingSelected
                                              ? AppColors.primaryBlue
                                              : textColor,
                                        ),
                                      ),
                                    ),

                                    // Trailing indicator
                                    if (isBeingSelected)
                                      SizedBox(
                                        width: trailingSize,
                                        height: trailingSize,
                                        child: const CircularProgressIndicator(
                                          strokeWidth: 2,
                                          valueColor: AlwaysStoppedAnimation<Color>(AppColors.primaryBlue),
                                        ),
                                      )
                                    else if (isCurrentlySelected)
                                      Icon(
                                        Icons.check_circle,
                                        color: AppColors.primaryBlue,
                                        size: trailingSize,
                                      )
                                    else
                                      Icon(
                                        Icons.arrow_forward_ios,
                                        color: secondaryTextColor.withValues(alpha: 0.5),
                                        size: isTablet ? 20 : 16,
                                      ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    );
                  },
                ),
              ),

              // Bottom padding to clear the floating nav bar
              SizedBox(height: MediaQuery.of(context).padding.bottom + (isTablet ? 100 : 90)),
            ],
          ),
        ),
      ),
    );
  }
}
