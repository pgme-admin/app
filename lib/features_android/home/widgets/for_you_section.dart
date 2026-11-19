import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:pgme/core_android/models/video_model.dart';
import 'package:pgme/core_android/providers/theme_provider.dart';
import 'package:pgme/core_android/theme/app_theme.dart';
import 'package:pgme/core_android/utils/responsive_helper.dart';

class ForYouSection extends StatelessWidget {
  final VideoModel? lastWatched;
  final bool isLoading;
  final String? error;
  final VoidCallback? onRetry;
  final bool hasTheorySubscription;
  final bool hasPracticalSubscription;

  const ForYouSection({
    super.key,
    this.lastWatched,
    this.isLoading = false,
    this.error,
    this.onRetry,
    this.hasTheorySubscription = false,
    this.hasPracticalSubscription = false,
  });

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final isDark = themeProvider.isDarkMode;
    final textColor = isDark ? AppColors.darkTextPrimary : const Color(0xFF000000);
    final isTablet = ResponsiveHelper.isTablet(context);

    final sectionTitleSize = isTablet ? 30.0 : 20.0;
    final hPadding = isTablet ? ResponsiveHelper.horizontalPadding(context) : 16.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Section Header
        Padding(
          padding: EdgeInsets.symmetric(horizontal: hPadding),
          child: Text(
            'For You',
            style: TextStyle(
              fontFamily: 'Poppins',
              fontWeight: FontWeight.w600,
              fontSize: sectionTitleSize,
              color: textColor,
            ),
          ),
        ),
        SizedBox(height: isTablet ? 24 : 16),

        // Content - Responsive layout
        Padding(
          padding: EdgeInsets.symmetric(horizontal: hPadding),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final availableWidth = constraints.maxWidth;
              final gap = isTablet ? 14.0 : 9.0;
              // Left card takes ~49% of available width, right column takes ~51%
              final resumeCardWidth = (availableWidth - gap) * 0.49;
              final rightColumnWidth = (availableWidth - gap) * 0.51;

              final resumeCardHeight = ResponsiveHelper.forYouCardHeight(context);
              final smallCardHeight = ResponsiveHelper.forYouSmallCardHeight(context);
              final smallCardHeight2 = smallCardHeight - 2;

              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Resume Card (Left - Tall)
                  _buildResumeCard(context, isDark, textColor, lastWatched, resumeCardWidth, resumeCardHeight, isTablet),
                  SizedBox(width: gap),

                  // Right Column - Theory and Practical
                  SizedBox(
                    width: rightColumnWidth,
                    child: Column(
                      children: [
                        _buildTheoryCard(context, isDark, textColor, rightColumnWidth, smallCardHeight, isTablet),
                        SizedBox(height: isTablet ? 14 : 9),
                        _buildPracticalCard(context, isDark, textColor, rightColumnWidth, smallCardHeight2, isTablet),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildResumeCard(BuildContext context, bool isDark, Color textColor, VideoModel? video, double cardWidth, double cardHeight, bool isTablet) {
    final labelSize = isTablet ? 17.0 : 12.0;
    final titleSize = isTablet ? 26.0 : 18.0;
    final subtitleSize = isTablet ? 19.0 : 14.0;
    final timeSize = isTablet ? 19.0 : 14.0;
    final playBtnSize = isTablet ? 50.0 : 32.0;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: video != null
          ? () => context.push('/video/${video.videoId}?resume=${video.positionSeconds}')
          : null,
      child: Container(
      width: cardWidth,
      height: cardHeight,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(isTablet ? 26 : 18),
        gradient: LinearGradient(
          begin: const Alignment(-0.5, -0.5),
          end: const Alignment(0.5, 0.5),
          colors: isDark
              ? [const Color(0xFF1A3A5C), const Color(0xFF2D5A9E)]
              : [const Color(0xFFCDE5FF), const Color(0xFF8FC6FF)],
        ),
      ),
      child: Stack(
        children: [
          Padding(
            padding: EdgeInsets.all(isTablet ? 26 : 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'RESUME',
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontWeight: FontWeight.w500,
                    fontSize: labelSize,
                    color:
                        isDark ? AppColors.darkTextSecondary : const Color(0xFF666666),
                  ),
                ),
                SizedBox(height: isTablet ? 24 : 16),
                Text(
                  'Continue where\nyou left off',
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontWeight: FontWeight.w600,
                    fontSize: titleSize,
                    height: 1.3,
                    color: isDark ? Colors.white : const Color(0xFF000000),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  video?.title ?? 'No recent videos',
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontWeight: FontWeight.w400,
                    fontSize: subtitleSize,
                    height: 1.3,
                    color: isDark ? const Color(0xFF00BEFA) : AppColors.primaryBlue,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          // Play button and time
          Positioned(
            bottom: isTablet ? 26 : 16,
            left: isTablet ? 26 : 16,
            child: Text(
              video != null ? '${video.remainingMinutes} Min Left' : '--',
              style: TextStyle(
                fontFamily: 'Poppins',
                fontWeight: FontWeight.w500,
                fontSize: timeSize,
                color: isDark ? Colors.white : const Color(0xFF000000),
              ),
            ),
          ),
          Positioned(
            bottom: isTablet ? 22 : 12,
            right: isTablet ? 26 : 16,
            child: _buildPlayButton(isDark, playBtnSize),
          ),
        ],
      ),
      ),
    );
  }

  Widget _buildTheoryCard(BuildContext context, bool isDark, Color textColor, double cardWidth, double cardHeight, bool isTablet) {
    final isLocked = !hasTheorySubscription;
    final labelSize = isTablet ? 17.0 : 12.0;
    final titleSize = isTablet ? 22.0 : 16.0;
    final imageWidth = isTablet ? 160.0 : 101.0;
    final imageHeight = isTablet ? 130.0 : 78.0;
    final btnSize = isTablet ? 48.0 : 32.0;

    return GestureDetector(
      onTap: () {
        // Navigate to theory/revision series with actual subscription status
        context.push('/revision-series?subscribed=$hasTheorySubscription');
      },
      child: Container(
        width: cardWidth,
        height: cardHeight,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(isTablet ? 22 : 12),
          gradient: LinearGradient(
            begin: const Alignment(-0.5, -0.5),
            end: const Alignment(0.8, 0.8),
            colors: isDark
                ? [const Color(0xFF1A3A5C), const Color(0xFF2D5A9E)]
                : [const Color(0xFFCDE5FF), const Color(0xFF8FC6FF)],
            stops: const [0.1132, 0.9348],
          ),
        ),
        child: Stack(
          children: [
            // Image
            Positioned(
              right: 0,
              bottom: 0,
              child: ClipRRect(
                borderRadius: BorderRadius.only(
                  bottomRight: Radius.circular(isTablet ? 22 : 13),
                ),
                child: Image.asset(
                  'assets/illustrations/1.png',
                  width: imageWidth,
                  height: imageHeight,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) {
                    return SizedBox(width: imageWidth, height: imageHeight);
                  },
                ),
              ),
            ),
            // Content
            Padding(
              padding: EdgeInsets.all(isTablet ? 24 : 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'THEORY',
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontWeight: FontWeight.w500,
                      fontSize: labelSize,
                      color: isDark
                          ? AppColors.darkTextSecondary
                          : const Color(0xFF666666),
                    ),
                  ),
                  SizedBox(height: isTablet ? 14 : 8),
                  Text(
                    'View Classes',
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontWeight: FontWeight.w600,
                      fontSize: titleSize,
                      color: isDark ? Colors.white : const Color(0xFF000000),
                    ),
                  ),
                ],
              ),
            ),
            // Play button or lock button based on subscription
            Positioned(
              bottom: isTablet ? 20 : 12,
              right: isTablet ? 20 : 12,
              child: isLocked ? _buildLockButton(isDark, btnSize) : _buildPlayButton(isDark, btnSize),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPracticalCard(BuildContext context, bool isDark, Color textColor, double cardWidth, double cardHeight, bool isTablet) {
    final isLocked = !hasPracticalSubscription;
    final labelSize = isTablet ? 17.0 : 12.0;
    final titleSize = isTablet ? 22.0 : 16.0;
    final imageWidth = isTablet ? 180.0 : 123.0;
    final imageHeight = isTablet ? 135.0 : 85.0;
    final btnSize = isTablet ? 48.0 : 32.0;

    return GestureDetector(
      onTap: () {
        // Navigate to practical series with actual subscription status
        context.push('/practical-series?subscribed=$hasPracticalSubscription');
      },
      child: Container(
        width: cardWidth,
        height: cardHeight,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(isTablet ? 22 : 12),
          gradient: LinearGradient(
            begin: const Alignment(-0.5, -0.5),
            end: const Alignment(0.8, 0.8),
            colors: isDark
                ? [const Color(0xFF1A3A5C), const Color(0xFF2D5A9E)]
                : [const Color(0xFFCDE5FF), const Color(0xFF8EC6FF)],
            stops: const [0.0689, 0.899],
          ),
        ),
        child: Stack(
          children: [
            // Image
            Positioned(
              right: 0,
              bottom: 0,
              child: ClipRRect(
                borderRadius: BorderRadius.only(
                  bottomRight: Radius.circular(isTablet ? 22 : 14),
                ),
                child: Image.asset(
                  'assets/illustrations/2.png',
                  width: imageWidth,
                  height: imageHeight,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) {
                    return SizedBox(width: imageWidth, height: imageHeight);
                  },
                ),
              ),
            ),
            // Content
            Padding(
              padding: EdgeInsets.all(isTablet ? 24 : 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'PRACTICAL',
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontWeight: FontWeight.w500,
                      fontSize: labelSize,
                      color: isDark
                          ? AppColors.darkTextSecondary
                          : const Color(0xFF666666),
                    ),
                  ),
                  SizedBox(height: isTablet ? 14 : 8),
                  Text(
                    'View Classes',
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontWeight: FontWeight.w600,
                      fontSize: titleSize,
                      color: isDark ? Colors.white : const Color(0xFF000000),
                    ),
                  ),
                ],
              ),
            ),
            // Play button or lock button based on subscription
            Positioned(
              bottom: isTablet ? 20 : 12,
              right: isTablet ? 20 : 12,
              child: isLocked ? _buildLockButton(isDark, btnSize) : _buildPlayButton(isDark, btnSize),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPlayButton(bool isDark, double size) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface : Colors.white,
        shape: BoxShape.circle,
        border: Border.all(
          color: isDark ? AppColors.darkTextSecondary : const Color(0xFF000000),
          width: 1.5,
        ),
      ),
      child: Center(
        child: Icon(
          Icons.play_arrow,
          size: size * 0.56,
          color: isDark ? Colors.white : const Color(0xFF000000),
        ),
      ),
    );
  }

  Widget _buildLockButton(bool isDark, double size) {
    final iconColor = isDark ? const Color(0xFF00BEFA) : const Color(0xFF2470E4);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface : Colors.white,
        shape: BoxShape.circle,
        border: Border.all(
          color: isDark ? AppColors.darkTextSecondary : const Color(0xFF000000),
          width: 1.5,
        ),
      ),
      child: Center(
        child: Icon(
          Icons.lock,
          size: size * 0.5,
          color: iconColor,
        ),
      ),
    );
  }
}
