import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:pgme/core_ios/providers/theme_provider.dart';
import 'package:pgme/core_ios/theme/app_theme.dart';
import 'package:pgme/core_ios/utils/responsive_helper.dart';
import 'package:pgme/features_ios/courses/providers/enrolled_courses_provider.dart';
import 'package:pgme/core_ios/models/access_record_model.dart';
import 'package:pgme/core_ios/models/progress_model.dart';

class EnrolledCoursesListScreen extends StatefulWidget {
  const EnrolledCoursesListScreen({super.key});

  @override
  State<EnrolledCoursesListScreen> createState() => _EnrolledCoursesListScreenState();
}

class _EnrolledCoursesListScreenState extends State<EnrolledCoursesListScreen> {
  @override
  void initState() {
    super.initState();
    // Load purchases and recent progress on init
    Future.microtask(() {
      if (mounted) {
        final provider = context.read<EnrolledCoursesProvider>();
        provider.loadPurchases();
        provider.loadRecentProgress(); // Load continue watching data
      }
    });
  }

  String _formatDate(String isoDate) {
    try {
      final date = DateTime.parse(isoDate);
      return DateFormat('dd MMM yyyy').format(date);
    } catch (e) {
      return isoDate;
    }
  }

  Color _getExpiryBadgeColor(int daysRemaining) {
    if (daysRemaining < 1) {
      return Colors.red;
    } else if (daysRemaining < 7) {
      return Colors.orange;
    } else {
      return Colors.green;
    }
  }

  @override
  Widget build(BuildContext context) {
    final topPadding = MediaQuery.of(context).padding.top;
    final themeProvider = Provider.of<ThemeProvider>(context);
    final isDark = themeProvider.isDarkMode;
    final isTablet = ResponsiveHelper.isTablet(context);
    final hPadding = isTablet ? ResponsiveHelper.horizontalPadding(context) : 23.0;

    // Theme-aware colors
    final backgroundColor = isDark ? AppColors.darkBackground : Colors.white;
    final textColor = isDark ? AppColors.darkTextPrimary : const Color(0xFF000000);
    final secondaryTextColor = isDark ? AppColors.darkTextSecondary : const Color(0xFF718BA9);
    final cardColor = isDark ? AppColors.darkSurface : Colors.white;
    final borderColor = isDark ? AppColors.darkDivider : const Color(0xFFE5E5E5);

    return Scaffold(
      backgroundColor: backgroundColor,
      body: Consumer<EnrolledCoursesProvider>(
        builder: (context, provider, _) {
          return RefreshIndicator(
            onRefresh: () async {
              await provider.refreshPurchases();
              await provider.loadRecentProgress();
            },
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(parent: ClampingScrollPhysics()),
              child: Center(
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: ResponsiveHelper.getMaxContentWidth(context)),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Header Section
                      Padding(
                        padding: EdgeInsets.only(top: topPadding + 16, left: hPadding, right: hPadding),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'My Courses',
                              style: TextStyle(
                                fontFamily: 'Poppins',
                                fontWeight: FontWeight.w600,
                                fontSize: isTablet ? 32 : 24,
                                letterSpacing: -0.5,
                                color: textColor,
                              ),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 24),

                      // Continue Watching Section
                      if (provider.continueWatchingList.isNotEmpty) ...[
                        Padding(
                          padding: EdgeInsets.only(left: hPadding),
                          child: Text(
                            'Continue Watching',
                            style: TextStyle(
                              fontFamily: 'Poppins',
                              fontWeight: FontWeight.w600,
                              fontSize: isTablet ? 24 : 18,
                              letterSpacing: -0.5,
                              color: textColor,
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        SizedBox(
                          height: isTablet ? 240 : 180,
                          child: ListView.builder(
                            scrollDirection: Axis.horizontal,
                            padding: EdgeInsets.symmetric(horizontal: hPadding),
                            itemCount: provider.continueWatchingList.length,
                            itemBuilder: (context, index) {
                              final progress = provider.continueWatchingList[index];
                              return _buildContinueWatchingCard(
                                progress,
                                textColor,
                                secondaryTextColor,
                                cardColor,
                                borderColor,
                                isTablet,
                              );
                            },
                          ),
                        ),
                        const SizedBox(height: 32),
                      ],

                      // Enrolled Courses Section
                      Padding(
                        padding: EdgeInsets.only(left: hPadding, right: hPadding),
                        child: Text(
                          'Enrolled Courses',
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            fontWeight: FontWeight.w600,
                            fontSize: isTablet ? 24 : 18,
                            letterSpacing: -0.5,
                            color: textColor,
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Loading State
                      if (provider.isLoadingPurchases) ...[
                        const Center(
                          child: Padding(
                            padding: EdgeInsets.all(32.0),
                            child: CircularProgressIndicator(),
                          ),
                        ),
                      ]
                      // Error State
                      else if (provider.purchasesError != null) ...[
                        Center(
                          child: Padding(
                            padding: const EdgeInsets.all(32.0),
                            child: Column(
                              children: [
                                Icon(
                                  Icons.error_outline,
                                  size: isTablet ? 64 : 48,
                                  color: secondaryTextColor,
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  provider.purchasesError!,
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontFamily: 'Poppins',
                                    fontSize: isTablet ? 17 : 14,
                                    color: secondaryTextColor,
                                  ),
                                ),
                                const SizedBox(height: 16),
                                ElevatedButton(
                                  onPressed: provider.retryPurchases,
                                  child: const Text('Retry'),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ]
                      // Empty State
                      else if (provider.purchases.isEmpty) ...[
                        Center(
                          child: Padding(
                            padding: const EdgeInsets.all(32.0),
                            child: Column(
                              children: [
                                Icon(
                                  Icons.school_outlined,
                                  size: isTablet ? 80 : 64,
                                  color: secondaryTextColor,
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  'No enrolled courses yet',
                                  style: TextStyle(
                                    fontFamily: 'Poppins',
                                    fontWeight: FontWeight.w600,
                                    fontSize: isTablet ? 22 : 18,
                                    color: textColor,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  'Explore packages to get started.',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontFamily: 'Poppins',
                                    fontSize: isTablet ? 17 : 14,
                                    color: secondaryTextColor,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ]
                      // Purchases List
                      else ...[
                        ListView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          padding: EdgeInsets.symmetric(horizontal: hPadding),
                          itemCount: provider.purchases.length,
                          itemBuilder: (context, index) {
                            final purchase = provider.purchases[index];
                            return _buildPurchaseCard(
                              purchase,
                              textColor,
                              secondaryTextColor,
                              cardColor,
                              borderColor,
                              isTablet,
                            );
                          },
                        ),
                      ],

                      SizedBox(height: isTablet ? 120 : 32),
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

  Widget _buildContinueWatchingCard(
    ProgressModel progress,
    Color textColor,
    Color secondaryTextColor,
    Color cardColor,
    Color borderColor,
    bool isTablet,
  ) {
    return GestureDetector(
      onTap: () {
        context.push('/video/${progress.lecture.lectureId}?resume=${progress.lastWatchedPositionSeconds}');
      },
      child: Container(
        width: isTablet ? 380 : 280,
        margin: const EdgeInsets.only(right: 16),
        decoration: BoxDecoration(
          color: cardColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: borderColor, width: 1),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Thumbnail with progress overlay
            Stack(
              children: [
                ClipRRect(
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
                  child: progress.lecture.thumbnailUrl != null
                      ? Image.network(
                          progress.lecture.thumbnailUrl!,
                          width: double.infinity,
                          height: isTablet ? 140.0 : 100.0,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) => Container(
                            height: isTablet ? 140.0 : 100.0,
                            color: borderColor,
                            child: Icon(Icons.play_circle_outline, size: 48, color: secondaryTextColor),
                          ),
                        )
                      : Container(
                          height: isTablet ? 140.0 : 100.0,
                          color: borderColor,
                          child: Icon(Icons.play_circle_outline, size: 48, color: secondaryTextColor),
                        ),
                ),
                // Progress bar overlay
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  child: LinearProgressIndicator(
                    value: progress.completionPercentage / 100,
                    backgroundColor: Colors.grey.withOpacity(0.3),
                    valueColor: const AlwaysStoppedAnimation<Color>(AppColors.secondaryBlue),
                    minHeight: isTablet ? 6 : 4,
                  ),
                ),
              ],
            ),
            // Content
            Padding(
              padding: EdgeInsets.all(isTablet ? 16 : 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    progress.lecture.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontWeight: FontWeight.w600,
                      fontSize: isTablet ? 18 : 14,
                      color: textColor,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '${progress.completionPercentage}% complete',
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: isTablet ? 15 : 12,
                          color: secondaryTextColor,
                        ),
                      ),
                      Text(
                        progress.formattedTimeRemaining,
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: isTablet ? 15 : 12,
                          fontWeight: FontWeight.w500,
                          color: AppColors.secondaryBlue,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPurchaseCard(
    AccessRecordModel purchase,
    Color textColor,
    Color secondaryTextColor,
    Color cardColor,
    Color borderColor,
    bool isTablet,
  ) {
    return GestureDetector(
      onTap: () {
        final packageType = purchase.package.type?.toLowerCase() ?? '';
        if (packageType == 'theory') {
          context.push('/revision-series?subscribed=${purchase.isActive}&packageId=${purchase.package.packageId}');
        } else if (packageType == 'practical') {
          context.push('/practical-series?subscribed=${purchase.isActive}&packageId=${purchase.package.packageId}');
        }
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 16),
        decoration: BoxDecoration(
          color: cardColor,
          borderRadius: BorderRadius.circular(isTablet ? 18 : 12),
          border: Border.all(color: borderColor, width: 1),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Thumbnail
            AspectRatio(
              aspectRatio: 16 / 9,
              child: ClipRRect(
                borderRadius: BorderRadius.vertical(top: Radius.circular(isTablet ? 18 : 12)),
                child: purchase.package.thumbnailUrl != null
                    ? Image.network(
                        purchase.package.thumbnailUrl!,
                        width: double.infinity,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) => Container(
                          color: borderColor,
                          child: Icon(Icons.book_outlined, size: isTablet ? 80 : 64, color: secondaryTextColor),
                        ),
                      )
                    : Container(
                        color: borderColor,
                        child: Icon(Icons.book_outlined, size: isTablet ? 80 : 64, color: secondaryTextColor),
                      ),
              ),
            ),
            // Content
            Padding(
              padding: EdgeInsets.all(isTablet ? 22 : 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Title and badges
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          purchase.package.name,
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            fontWeight: FontWeight.w600,
                            fontSize: isTablet ? 20 : 16,
                            color: textColor,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      // Type badge
                      if (purchase.package.type != null)
                        Container(
                          padding: EdgeInsets.symmetric(horizontal: isTablet ? 10 : 8, vertical: isTablet ? 5 : 4),
                          decoration: BoxDecoration(
                            color: AppColors.secondaryBlue.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            purchase.package.type!,
                            style: TextStyle(
                              fontFamily: 'Poppins',
                              fontSize: isTablet ? 13 : 10,
                              fontWeight: FontWeight.w600,
                              color: AppColors.secondaryBlue,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  // Price and expiry
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      // Price hidden on iOS
                      // Status and expiry badge
                      Container(
                        padding: EdgeInsets.symmetric(horizontal: isTablet ? 16 : 12, vertical: isTablet ? 8 : 6),
                        decoration: BoxDecoration(
                          color: _getExpiryBadgeColor(purchase.daysRemaining).withOpacity(0.1),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: _getExpiryBadgeColor(purchase.daysRemaining),
                            width: 1,
                          ),
                        ),
                        child: Text(
                          purchase.isActive
                              ? '${purchase.daysRemaining} days left'
                              : 'Expired',
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: isTablet ? 15 : 12,
                            fontWeight: FontWeight.w600,
                            color: _getExpiryBadgeColor(purchase.daysRemaining),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Expires on ${_formatDate(purchase.expiresAt)}',
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: isTablet ? 15 : 12,
                      color: secondaryTextColor,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
