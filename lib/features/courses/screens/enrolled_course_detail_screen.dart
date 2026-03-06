import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:pgme/core/providers/theme_provider.dart';
import 'package:pgme/core/theme/app_theme.dart';
import 'package:pgme/core/utils/responsive_helper.dart';
import 'package:pgme/core/models/series_model.dart';
import 'package:pgme/core/services/dashboard_service.dart';

class EnrolledCourseDetailScreen extends StatefulWidget {
  final String seriesId;
  final bool isSubscribed;
  final String packageType; // 'Theory' or 'Practical'
  final String? packageId;

  const EnrolledCourseDetailScreen({
    super.key,
    required this.seriesId,
    this.isSubscribed = false,
    this.packageType = 'Theory',
    this.packageId,
  });

  @override
  State<EnrolledCourseDetailScreen> createState() =>
      _EnrolledCourseDetailScreenState();
}

class _EnrolledCourseDetailScreenState
    extends State<EnrolledCourseDetailScreen> {
  final DashboardService _dashboardService = DashboardService();
  SeriesModel? _series;
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadSeriesData();
  }

  Future<void> _loadSeriesData() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final series = await _dashboardService.getSeriesDetails(widget.seriesId);

      if (mounted) {
        setState(() {
          _series = series;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final isDark = themeProvider.isDarkMode;
    final isTablet = ResponsiveHelper.isTablet(context);

    // Theme-aware colors
    final backgroundColor = isDark ? AppColors.darkBackground : Colors.white;
    final textColor = isDark ? AppColors.darkTextPrimary : const Color(0xFF000000);
    final secondaryTextColor =
        isDark ? AppColors.darkTextSecondary : const Color(0xFF718BA9);
    final cardGradientStart =
        isDark ? const Color(0xFF1A3A5C) : const Color(0xFFCDE5FF);
    final cardGradientEnd =
        isDark ? const Color(0xFF2D5A9E) : const Color(0xFF8FC6FF);

    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: AppBar(
        backgroundColor: backgroundColor,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: textColor, size: isTablet ? 28 : 24),
          onPressed: () => context.pop(),
        ),
        title: Text(
          _series?.title ?? 'Series Details',
          style: TextStyle(
            fontFamily: 'Poppins',
            fontWeight: FontWeight.w500,
            fontSize: isTablet ? 24 : 20,
            color: textColor,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: Icon(Icons.search, color: textColor, size: isTablet ? 28 : 24),
            onPressed: () {
              // Search functionality
            },
          ),
        ],
      ),
      body: _isLoading
          ? Center(
              child: CircularProgressIndicator(
                color: isDark ? const Color(0xFF00BEFA) : const Color(0xFF2470E4),
              ),
            )
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.error_outline,
                        size: isTablet ? 80 : 64,
                        color: AppColors.error,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Failed to load course',
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: isTablet ? 20 : 16,
                          color: textColor,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _error!,
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: isTablet ? 15 : 12,
                          color: secondaryTextColor,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: _loadSeriesData,
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                )
              : SingleChildScrollView(
                  child: Center(
                    child: ConstrainedBox(
                      constraints: BoxConstraints(maxWidth: ResponsiveHelper.getMaxContentWidth(context)),
                      child: Padding(
                        padding: EdgeInsets.all(isTablet ? 24.0 : 16.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Quick Access Cards - Different content based on purchase status
                            Row(
                              children: [
                                // Video Card - Shows "Watch Lectures" if subscribed, "Watch Demo Video" if not
                                Expanded(
                                  child: _buildQuickAccessCard(
                                    context,
                                    widget.isSubscribed
                                        ? 'Watch\nLectures'
                                        : 'Watch Demo\nVideo',
                                    widget.isSubscribed ? 'Start' : 'Check Out',
                                    'assets/illustrations/1.png',
                                    isDark,
                                    cardGradientStart,
                                    cardGradientEnd,
                                    isTablet: isTablet,
                                    onTap: () {
                                      // Navigate to lecture/modules screen
                                      context.push('/lecture/${widget.seriesId}?subscribed=${widget.isSubscribed}&packageType=${widget.packageType}${widget.packageId != null ? '&packageId=${widget.packageId}' : ''}');
                                    },
                                  ),
                                ),
                                const SizedBox(width: 16),
                                // Second Card - Different based on package type and subscription status
                                Expanded(
                                  child: widget.packageType == 'Practical'
                                      ? _buildQuickAccessCard(
                                          context,
                                          widget.isSubscribed
                                              ? 'Join Live\nSessions'
                                              : 'View Live\nSession',
                                          'Join',
                                          'assets/illustrations/2.png',
                                          isDark,
                                          cardGradientStart,
                                          cardGradientEnd,
                                          isTablet: isTablet,
                                          onTap: () {
                                            // Navigate to series live sessions screen
                                            final seriesName = Uri.encodeComponent(_series?.title ?? '');
                                            context.push('/series-sessions/${widget.seriesId}?seriesName=$seriesName');
                                          },
                                        )
                                      : _buildQuickAccessCard(
                                          context,
                                          widget.isSubscribed
                                              ? 'Read\nNotes'
                                              : 'Free Sample\nPDF',
                                          widget.isSubscribed ? 'Open' : 'View',
                                          'assets/illustrations/2.png',
                                          isDark,
                                          cardGradientStart,
                                          cardGradientEnd,
                                          isTablet: isTablet,
                                          onTap: () {
                                            // Navigate to available notes/documents screen
                                            context.push('/available-notes?seriesId=${widget.seriesId}&subscribed=${widget.isSubscribed}');
                                          },
                                        ),
                                ),
                              ],
                            ),

                            const SizedBox(height: 24),

                            // Series Title
                            Text(
                              _series?.title ?? 'Series Title',
                              style: TextStyle(
                                fontFamily: 'Poppins',
                                fontWeight: FontWeight.w600,
                                fontSize: isTablet ? 24 : 18,
                                color: textColor,
                              ),
                            ),

                            const SizedBox(height: 12),

                            // Description
                            Text(
                              _series?.description ?? 'No description available',
                              style: TextStyle(
                                fontFamily: 'Poppins',
                                fontWeight: FontWeight.w400,
                                fontSize: isTablet ? 17 : 14,
                                height: 1.5,
                                color: secondaryTextColor,
                              ),
                            ),

                            const SizedBox(height: 24),

                            // Series Info Section
                            Text(
                              'What\'s Included',
                              style: TextStyle(
                                fontFamily: 'Poppins',
                                fontWeight: FontWeight.w600,
                                fontSize: isTablet ? 24 : 18,
                                color: textColor,
                              ),
                            ),

                            const SizedBox(height: 16),

                            // Info Items
                            if (_series?.moduleCount != null)
                              _buildInclusionItem(
                                '${_series!.moduleCount} Modules',
                                secondaryTextColor,
                                icon: Icons.folder_outlined,
                                isTablet: isTablet,
                              ),
                            if (_series?.moduleCount != null) const SizedBox(height: 12),
                            if (_series?.totalLectures != null)
                              _buildInclusionItem(
                                '${_series!.totalLectures} Video Lectures',
                                secondaryTextColor,
                                icon: Icons.play_circle_outline,
                                isTablet: isTablet,
                              ),
                            if (_series?.totalLectures != null) const SizedBox(height: 12),
                            if (_series?.totalDocuments != null)
                              _buildInclusionItem(
                                '${_series!.totalDocuments} Study Documents',
                                secondaryTextColor,
                                icon: Icons.description_outlined,
                                isTablet: isTablet,
                              ),
                            if (_series?.totalDocuments != null) const SizedBox(height: 12),
                            if (_series?.totalDurationMinutes != null)
                              _buildInclusionItem(
                                _series!.formattedDuration,
                                secondaryTextColor,
                                icon: Icons.access_time,
                                isTablet: isTablet,
                              ),

                            const SizedBox(height: 100),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
    );
  }

  Widget _buildQuickAccessCard(
    BuildContext context,
    String title,
    String buttonText,
    String imagePath,
    bool isDark,
    Color gradientStart,
    Color gradientEnd, {
    bool showButton = true,
    bool isTablet = false,
    VoidCallback? onTap,
  }) {
    final cardBorderRadius = isTablet ? 18.0 : 12.0;
    final illustrationScale = isTablet ? 1.3 : 1.0;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: isTablet ? 240 : 180,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(cardBorderRadius),
          gradient: LinearGradient(
            begin: const Alignment(-0.5, -0.5),
            end: const Alignment(0.5, 0.5),
            colors: [gradientStart, gradientEnd],
          ),
        ),
        child: Stack(
          children: [
            // Title
            Positioned(
              top: 16,
              left: 16,
              right: 16,
              child: Text(
                title,
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontWeight: FontWeight.w600,
                  fontSize: isTablet ? 20 : 16,
                  color: isDark ? Colors.white : const Color(0xFF000000),
                  height: 1.3,
                ),
              ),
            ),

            // Button
            if (showButton)
              Positioned(
                top: isTablet ? 80 : 60,
                left: 16,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: isDark ? AppColors.darkSurface : Colors.white,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Text(
                    buttonText,
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontWeight: FontWeight.w500,
                      fontSize: isTablet ? 15 : 12,
                      color: isDark
                          ? const Color(0xFF00BEFA)
                          : const Color(0xFF2470E4),
                    ),
                  ),
                ),
              ),

            // Illustration
            Positioned(
              right: 0,
              bottom: 0,
              child: ClipRRect(
                borderRadius: BorderRadius.only(
                  bottomRight: Radius.circular(cardBorderRadius),
                ),
                child: Image.asset(
                  imagePath,
                  width: ((title.contains('PDF') || title.contains('Documents')) ? 123 : 101) * illustrationScale,
                  height: ((title.contains('PDF') || title.contains('Documents')) ? 85 : 78) * illustrationScale,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) {
                    return Container(
                      width: ((title.contains('PDF') || title.contains('Documents')) ? 123 : 101) * illustrationScale,
                      height: ((title.contains('PDF') || title.contains('Documents')) ? 85 : 78) * illustrationScale,
                      decoration: BoxDecoration(
                        color: isDark
                            ? AppColors.darkCardBackground
                            : const Color(0xFFDCEAF7),
                        borderRadius: BorderRadius.only(
                          bottomRight: Radius.circular(cardBorderRadius),
                        ),
                      ),
                      child: Icon(
                        (title.contains('PDF') || title.contains('Documents'))
                            ? Icons.picture_as_pdf
                            : title.contains('Live')
                                ? Icons.live_tv
                                : Icons.play_circle_outline,
                        size: isTablet ? 52 : 40,
                        color: isDark
                            ? const Color(0xFF00BEFA)
                            : const Color(0xFF2470E4),
                      ),
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInclusionItem(String text, Color textColor, {IconData icon = Icons.check_circle_outline, bool isTablet = false}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Icon(
            icon,
            size: isTablet ? 26 : 20,
            color: textColor,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              fontFamily: 'Poppins',
              fontWeight: FontWeight.w400,
              fontSize: isTablet ? 17 : 14,
              height: 1.5,
              color: textColor,
            ),
          ),
        ),
      ],
    );
  }
}
