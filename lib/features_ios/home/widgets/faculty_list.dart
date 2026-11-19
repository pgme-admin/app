import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:pgme/core_ios/models/faculty_model.dart';
import 'package:pgme/core_ios/providers/theme_provider.dart';
import 'package:pgme/core_ios/theme/app_theme.dart';
import 'package:pgme/core_ios/utils/responsive_helper.dart';

class FacultyList extends StatelessWidget {
  final List<FacultyModel> faculty;
  final bool isLoading;
  final String? error;
  final VoidCallback? onRetry;

  const FacultyList({
    super.key,
    required this.faculty,
    this.isLoading = false,
    this.error,
    this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final isDark = themeProvider.isDarkMode;
    final textColor = isDark ? AppColors.darkTextPrimary : const Color(0xFF000000);
    final secondaryTextColor =
        isDark ? AppColors.darkTextSecondary : AppColors.textSecondary;
    final cardBgColor = isDark ? AppColors.darkCardBackground : const Color(0xFFFFFFFF);
    final isTablet = ResponsiveHelper.isTablet(context);

    final sectionTitleSize = isTablet ? 30.0 : 20.0;
    final hPadding = isTablet ? 24.0 : 16.0;

    // On tablet: calculate card width to fit exactly 3 cards on screen
    final screenWidth = MediaQuery.of(context).size.width;
    final double cardWidth;
    final double cardHeight;
    final double photoSize;
    if (isTablet) {
      final availableWidth = screenWidth - (hPadding * 2); // subtract list padding
      final cardGap = 20.0;
      cardWidth = (availableWidth - (cardGap * 2)) / 3; // 3 cards, 2 gaps
      cardHeight = cardWidth * 1.15; // proportional cards
      photoSize = cardWidth * 0.65; // big photo relative to card
    } else {
      cardWidth = ResponsiveHelper.facultyCardWidth(context);
      cardHeight = ResponsiveHelper.facultyCardHeight(context);
      photoSize = ResponsiveHelper.facultyPhotoSize(context);
    }
    final listHeight = cardHeight + 12;

    return Column(
      children: [
        // Section Header
        Padding(
          padding: EdgeInsets.symmetric(horizontal: hPadding),
          child: Text(
            'Your Faculty',
            style: TextStyle(
              fontFamily: 'Poppins',
              fontWeight: FontWeight.w600,
              fontSize: sectionTitleSize,
              color: textColor,
            ),
          ),
        ),
        SizedBox(height: isTablet ? 24 : 16),

        // Faculty Cards
        SizedBox(
          height: listHeight,
          child: faculty.isEmpty
              ? Center(
                  child: Text(
                    'No faculty members available',
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: isTablet ? 16 : 14,
                      color: secondaryTextColor,
                    ),
                  ),
                )
              : ListView.builder(
                  scrollDirection: Axis.horizontal,
                  padding: EdgeInsets.symmetric(horizontal: hPadding),
                  itemCount: faculty.length,
                  itemBuilder: (context, index) {
                    final member = faculty[index];
                    return _buildFacultyCard(
                      member,
                      isDark,
                      textColor,
                      cardBgColor,
                      cardWidth,
                      cardHeight,
                      photoSize,
                      isTablet,
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildFacultyCard(
    FacultyModel member,
    bool isDark,
    Color textColor,
    Color cardBgColor,
    double cardWidth,
    double cardHeight,
    double photoSize,
    bool isTablet,
  ) {
    final nameSize = isTablet ? 18.0 : 12.0;
    final photoHeight = photoSize; // Perfect circle

    return Container(
      width: cardWidth,
      height: cardHeight,
      margin: EdgeInsets.only(right: isTablet ? 20 : 12),
      decoration: BoxDecoration(
        color: cardBgColor,
        borderRadius: BorderRadius.circular(isTablet ? 18 : 8),
        border: Border.all(
          color: isDark ? AppColors.darkDivider : const Color(0xFF000080),
          width: 1,
        ),
      ),
      child: Column(
        children: [
          SizedBox(height: isTablet ? 20 : 14),

          // Faculty Photo
          ClipRRect(
            borderRadius: BorderRadius.circular(isTablet ? 12 : 8),
            child: member.photoUrl != null && member.photoUrl!.isNotEmpty
                ? CachedNetworkImage(
                    imageUrl: member.photoUrl!,
                    width: photoSize,
                    height: photoHeight,
                    fit: BoxFit.cover,
                    placeholder: (context, url) => Container(
                      width: photoSize,
                      height: photoHeight,
                      decoration: BoxDecoration(
                        color: isDark ? AppColors.darkSurface : const Color(0xFFE0E0E0),
                        borderRadius: BorderRadius.circular(isTablet ? 12 : 8),
                      ),
                      child: const Center(
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                    errorWidget: (context, url, error) => Container(
                      width: photoSize,
                      height: photoHeight,
                      decoration: BoxDecoration(
                        color: isDark ? AppColors.darkSurface : const Color(0xFFE0E0E0),
                        borderRadius: BorderRadius.circular(isTablet ? 12 : 8),
                      ),
                      child: Icon(
                        Icons.person,
                        size: isTablet ? 56 : 40,
                        color: isDark
                            ? AppColors.darkTextTertiary
                            : const Color(0xFF999999),
                      ),
                    ),
                  )
                : Image.asset(
                    'assets/illustrations/doc.png',
                    width: photoSize,
                    height: photoHeight,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) {
                      return Container(
                        width: photoSize,
                        height: photoHeight,
                        decoration: BoxDecoration(
                          color:
                              isDark ? AppColors.darkSurface : const Color(0xFFE0E0E0),
                          borderRadius: BorderRadius.circular(isTablet ? 12 : 8),
                        ),
                        child: Icon(
                          Icons.person,
                          size: isTablet ? 56 : 40,
                          color: isDark
                              ? AppColors.darkTextTertiary
                              : const Color(0xFF999999),
                        ),
                      );
                    },
                  ),
          ),

          SizedBox(height: isTablet ? 20 : 8),

          // Name
          Padding(
            padding: EdgeInsets.fromLTRB(
              isTablet ? 14 : 8,
              0,
              isTablet ? 14 : 8,
              isTablet ? 12 : 0,
            ),
            child: Text(
              member.name,
              style: TextStyle(
                fontFamily: 'Poppins',
                fontWeight: FontWeight.w500,
                fontSize: nameSize,
                color: textColor,
              ),
              textAlign: TextAlign.center,
              maxLines: isTablet ? 2 : 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

class _FacultyDetailSheet extends StatelessWidget {
  final FacultyModel faculty;
  final bool isDark;

  const _FacultyDetailSheet({
    required this.faculty,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final backgroundColor = isDark ? AppColors.darkCardBackground : Colors.white;
    final textColor = isDark ? AppColors.darkTextPrimary : const Color(0xFF000000);
    final secondaryTextColor = isDark ? AppColors.darkTextSecondary : AppColors.textSecondary;
    final isTablet = ResponsiveHelper.isTablet(context);

    final titleSize = isTablet ? 24.0 : 18.0;
    final nameSize = isTablet ? 32.0 : 22.0;
    final specSize = isTablet ? 20.0 : 14.0;
    final photoSize = isTablet ? 170.0 : 120.0;
    final aboutTitleSize = isTablet ? 22.0 : 16.0;
    final aboutBodySize = isTablet ? 18.0 : 14.0;

    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: isTablet ? ResponsiveHelper.getMaxContentWidth(context) + 48 : double.infinity,
        ),
        child: Container(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.75,
          ),
          decoration: BoxDecoration(
            color: backgroundColor,
            borderRadius: BorderRadius.vertical(top: Radius.circular(isTablet ? 32 : 24)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Handle bar
              Container(
                margin: EdgeInsets.only(top: isTablet ? 16 : 12),
                width: isTablet ? 50 : 40,
                height: isTablet ? 5 : 4,
                decoration: BoxDecoration(
                  color: secondaryTextColor.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),

              // Header with close button
              Padding(
                padding: EdgeInsets.fromLTRB(isTablet ? 32 : 20, isTablet ? 20 : 16, isTablet ? 24 : 12, 0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Faculty Profile',
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontWeight: FontWeight.w600,
                        fontSize: titleSize,
                        color: textColor,
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: Icon(
                        Icons.close,
                        color: secondaryTextColor,
                        size: isTablet ? 30 : 24,
                      ),
                    ),
                  ],
                ),
              ),

              // Divider
              Divider(
                height: 16,
                color: secondaryTextColor.withValues(alpha: 0.2),
              ),

              // Content
              Flexible(
                child: SingleChildScrollView(
                  padding: EdgeInsets.fromLTRB(isTablet ? 32 : 20, isTablet ? 12 : 8, isTablet ? 32 : 20, isTablet ? 32 : 20),
                  child: Column(
                    children: [
                      // Faculty Photo
                      Container(
                        width: photoSize,
                        height: photoSize,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(isTablet ? 16 : 12),
                          border: Border.all(
                            color: AppColors.primaryBlue.withValues(alpha: 0.3),
                            width: 3,
                          ),
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(isTablet ? 13 : 9),
                          child: faculty.photoUrl != null && faculty.photoUrl!.isNotEmpty
                              ? CachedNetworkImage(
                                  imageUrl: faculty.photoUrl!,
                                  width: photoSize,
                                  height: photoSize,
                                  fit: BoxFit.cover,
                                  placeholder: (context, url) => Container(
                                    color: isDark ? AppColors.darkSurface : const Color(0xFFE0E0E0),
                                    child: const Center(
                                      child: CircularProgressIndicator(strokeWidth: 2),
                                    ),
                                  ),
                                  errorWidget: (context, url, error) => Container(
                                    color: isDark ? AppColors.darkSurface : const Color(0xFFE0E0E0),
                                    child: Icon(
                                      Icons.person,
                                      size: isTablet ? 60 : 50,
                                      color: isDark ? AppColors.darkTextTertiary : const Color(0xFF999999),
                                    ),
                                  ),
                                )
                              : Container(
                                  color: isDark ? AppColors.darkSurface : const Color(0xFFE0E0E0),
                                  child: Icon(
                                    Icons.person,
                                    size: isTablet ? 60 : 50,
                                    color: isDark ? AppColors.darkTextTertiary : const Color(0xFF999999),
                                  ),
                                ),
                        ),
                      ),

                      SizedBox(height: isTablet ? 24 : 16),

                      // Name
                      Text(
                        faculty.name,
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          fontWeight: FontWeight.w600,
                          fontSize: nameSize,
                          color: textColor,
                        ),
                        textAlign: TextAlign.center,
                      ),

                      SizedBox(height: isTablet ? 8 : 4),

                      // Specialization
                      if (faculty.specialization.isNotEmpty)
                        Text(
                          faculty.specialization,
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            fontWeight: FontWeight.w500,
                            fontSize: specSize,
                            color: AppColors.primaryBlue,
                          ),
                          textAlign: TextAlign.center,
                        ),

                      SizedBox(height: isTablet ? 28 : 20),

                      // Info Cards Row
                      Row(
                        children: [
                          // Experience
                          if (faculty.experienceYears != null)
                            Expanded(
                              child: _buildInfoCard(
                                icon: Icons.work_outline,
                                label: 'Experience',
                                value: '${faculty.experienceYears} years',
                                isDark: isDark,
                                textColor: textColor,
                                secondaryTextColor: secondaryTextColor,
                                isTablet: isTablet,
                              ),
                            ),
                          if (faculty.experienceYears != null && faculty.qualifications != null)
                            SizedBox(width: isTablet ? 18 : 12),
                          // Qualifications
                          if (faculty.qualifications != null)
                            Expanded(
                              child: _buildInfoCard(
                                icon: Icons.school_outlined,
                                label: 'Qualification',
                                value: faculty.qualifications!,
                                isDark: isDark,
                                textColor: textColor,
                                secondaryTextColor: secondaryTextColor,
                                isTablet: isTablet,
                              ),
                            ),
                        ],
                      ),

                      // Bio Section
                      if (faculty.bio != null && faculty.bio!.isNotEmpty) ...[
                        SizedBox(height: isTablet ? 32 : 24),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            'About',
                            style: TextStyle(
                              fontFamily: 'Poppins',
                              fontWeight: FontWeight.w600,
                              fontSize: aboutTitleSize,
                              color: textColor,
                            ),
                          ),
                        ),
                        SizedBox(height: isTablet ? 12 : 8),
                        Container(
                          width: double.infinity,
                          padding: EdgeInsets.all(isTablet ? 24 : 16),
                          decoration: BoxDecoration(
                            color: isDark ? AppColors.darkSurface : const Color(0xFFF5F5F5),
                            borderRadius: BorderRadius.circular(isTablet ? 18 : 12),
                          ),
                          child: Text(
                            faculty.bio!,
                            style: TextStyle(
                              fontFamily: 'Poppins',
                              fontWeight: FontWeight.w400,
                              fontSize: aboutBodySize,
                              color: secondaryTextColor,
                              height: 1.5,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),

              // Bottom safe area
              SizedBox(height: MediaQuery.of(context).padding.bottom + 8),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInfoCard({
    required IconData icon,
    required String label,
    required String value,
    required bool isDark,
    required Color textColor,
    required Color secondaryTextColor,
    required bool isTablet,
  }) {
    return Container(
      padding: EdgeInsets.all(isTablet ? 22 : 12),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface : const Color(0xFFF5F5F5),
        borderRadius: BorderRadius.circular(isTablet ? 18 : 12),
      ),
      child: Column(
        children: [
          Icon(
            icon,
            color: AppColors.primaryBlue,
            size: isTablet ? 34 : 24,
          ),
          SizedBox(height: isTablet ? 12 : 8),
          Text(
            label,
            style: TextStyle(
              fontFamily: 'Poppins',
              fontWeight: FontWeight.w400,
              fontSize: isTablet ? 16 : 12,
              color: secondaryTextColor,
            ),
          ),
          SizedBox(height: isTablet ? 6 : 4),
          Text(
            value,
            style: TextStyle(
              fontFamily: 'Poppins',
              fontWeight: FontWeight.w600,
              fontSize: isTablet ? 18 : 14,
              color: textColor,
            ),
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}
