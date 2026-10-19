import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:pgme/core_ios/providers/theme_provider.dart';
import 'package:pgme/core_ios/theme/app_theme.dart';
import 'package:pgme/core_ios/utils/responsive_helper.dart';
import 'package:pgme/core_ios/services/dashboard_service.dart';
import 'package:pgme/core_ios/utils/web_store_launcher.dart';
import 'package:pgme/core_ios/models/series_model.dart';
import 'package:pgme/core_ios/models/module_model.dart';
import 'package:pgme/core_ios/models/series_document_model.dart';

class CourseDetailScreen extends StatefulWidget {
  final String seriesId;

  const CourseDetailScreen({
    super.key,
    required this.seriesId,
  });

  @override
  State<CourseDetailScreen> createState() => _CourseDetailScreenState();
}

class _CourseDetailScreenState extends State<CourseDetailScreen>
    with WidgetsBindingObserver {
  final DashboardService _dashboardService = DashboardService();

  SeriesModel? _series;
  List<ModuleModel> _modules = [];
  List<SeriesDocumentModel> _documents = [];

  bool _isLoading = true;
  String? _error;

  // Track which modules are expanded
  Set<String> _expandedModules = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadSeriesData();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed &&
        WebStoreLauncher.awaitingExternalPurchase) {
      WebStoreLauncher.clearAwaitingPurchase();
      _loadSeriesData();
    }
  }

  Future<void> _loadSeriesData() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      // Fetch all data in parallel
      final results = await Future.wait([
        _dashboardService.getSeriesDetails(widget.seriesId),
        _dashboardService.getSeriesModules(widget.seriesId),
        _dashboardService.getSeriesDocuments(widget.seriesId),
      ]);

      if (mounted) {
        setState(() {
          _series = results[0] as SeriesModel;
          _modules = results[1] as List<ModuleModel>;
          _documents = results[2] as List<SeriesDocumentModel>;
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
    final secondaryTextColor = isDark ? AppColors.darkTextSecondary : const Color(0xFF718BA9);
    final cardColor = isDark ? AppColors.darkSurface : const Color(0xFFF5F9FF);
    final iconColor = isDark ? const Color(0xFF00BEFA) : const Color(0xFF2470E4);

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
          _series?.title ?? 'Anatomy Course',
          style: TextStyle(
            fontFamily: 'Poppins',
            fontWeight: FontWeight.w600,
            fontSize: isTablet ? 20 : 16,
            color: textColor,
          ),
        ),
        // actions: [
        //   IconButton(
        //     icon: Icon(Icons.more_horiz, color: textColor, size: isTablet ? 28 : 24),
        //     onPressed: () {},
        //   ),
        // ],
      ),
      body: _isLoading
          ? Center(child: CircularProgressIndicator(color: iconColor))
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.error_outline, size: isTablet ? 64 : 48, color: secondaryTextColor),
                      const SizedBox(height: 16),
                      Text(
                        'Failed to load course',
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: isTablet ? 20 : 16,
                          color: textColor,
                        ),
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: _loadSeriesData,
                        style: ElevatedButton.styleFrom(backgroundColor: iconColor),
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _loadSeriesData,
                  child: SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: BoxConstraints(maxWidth: ResponsiveHelper.getMaxContentWidth(context)),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Video Banner
                          _buildVideoBanner(iconColor, isTablet),

                          Padding(
                            padding: EdgeInsets.all(isTablet ? 24 : 16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // Video Title - Show first video or series title
                                Text(
                                  _getFirstVideoTitle() ?? _series?.title ?? 'Video Title',
                                  style: TextStyle(
                                    fontFamily: 'Poppins',
                                    fontWeight: FontWeight.w600,
                                    fontSize: isTablet ? 20 : 16,
                                    color: textColor,
                                  ),
                                ),
                                const SizedBox(height: 8),

                                // Description
                                Text(
                                  _series?.description ?? 'No description available',
                                  style: TextStyle(
                                    fontFamily: 'Poppins',
                                    fontSize: isTablet ? 17 : 14,
                                    height: 1.5,
                                    color: secondaryTextColor,
                                  ),
                                ),
                                const SizedBox(height: 24),

                                // Notes section
                                if (_documents.isNotEmpty) ...[
                                  Text(
                                    'Notes for this chapter',
                                    style: TextStyle(
                                      fontFamily: 'Poppins',
                                      fontWeight: FontWeight.w600,
                                      fontSize: isTablet ? 20 : 16,
                                      color: textColor,
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  ..._documents.map((doc) => _buildDocumentCard(
                                        doc,
                                        cardColor,
                                        textColor,
                                        secondaryTextColor,
                                        iconColor,
                                        isTablet,
                                      )),
                                  const SizedBox(height: 24),
                                ],

                                // Modules section
                                ..._modules.map((module) => _buildModuleCard(
                                      module,
                                      cardColor,
                                      textColor,
                                      secondaryTextColor,
                                      iconColor,
                                      isTablet,
                                    )),

                                // Enroll button
                                const SizedBox(height: 24),
                                SizedBox(
                                  width: double.infinity,
                                  child: ElevatedButton(
                                    onPressed: () {
                                      WebStoreLauncher.openProductPage(context, productType: 'packages', productId: '');
                                    },
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: iconColor,
                                      padding: EdgeInsets.symmetric(vertical: isTablet ? 20 : 16),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(isTablet ? 18 : 12),
                                      ),
                                    ),
                                    child: Text(
                                      'Learn More',
                                      style: TextStyle(
                                        fontFamily: 'Poppins',
                                        fontWeight: FontWeight.w600,
                                        fontSize: isTablet ? 20 : 16,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 24),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                ),
    );
  }

  // Helper method to get first video title
  String? _getFirstVideoTitle() {
    if (_modules.isEmpty) return null;
    for (var module in _modules) {
      if (module.videos.isNotEmpty) {
        return module.videos.first.title;
      }
    }
    return null;
  }

  // Helper method to get first video
  ModuleVideoModel? _getFirstVideo() {
    if (_modules.isEmpty) return null;
    for (var module in _modules) {
      if (module.videos.isNotEmpty) {
        return module.videos.first;
      }
    }
    return null;
  }

  Widget _buildVideoBanner(Color iconColor, bool isTablet) {
    final firstVideo = _getFirstVideo();

    return Container(
      width: double.infinity,
      height: isTablet ? 300 : 200,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            iconColor.withOpacity(0.3),
            iconColor.withOpacity(0.1),
          ],
        ),
      ),
      child: Stack(
        children: [
          // Placeholder for video thumbnail
          Center(
            child: Icon(
              Icons.play_circle_filled,
              size: isTablet ? 80 : 64,
              color: Colors.white,
            ),
          ),
          // Video info overlay
          Positioned(
            bottom: 16,
            left: 16,
            right: 16,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  firstVideo?.title ?? _series?.title ?? 'Video Title',
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontWeight: FontWeight.w600,
                    fontSize: isTablet ? 24 : 18,
                    color: Colors.white,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  firstVideo?.facultyName ?? 'Faculty',
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: isTablet ? 17 : 14,
                    color: Colors.white.withOpacity(0.9),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDocumentCard(
    SeriesDocumentModel doc,
    Color cardColor,
    Color textColor,
    Color secondaryTextColor,
    Color iconColor,
    bool isTablet,
  ) {
    final containerSize = isTablet ? 60.0 : 48.0;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: EdgeInsets.all(isTablet ? 20 : 16),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(isTablet ? 16 : 12),
      ),
      child: Row(
        children: [
          // PDF icon placeholder
          Container(
            width: containerSize,
            height: containerSize,
            decoration: BoxDecoration(
              color: iconColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(Icons.description, color: iconColor, size: isTablet ? 30 : 24),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  doc.title,
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontWeight: FontWeight.w500,
                    fontSize: isTablet ? 17 : 14,
                    color: textColor,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  doc.description ?? '',
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: isTablet ? 15 : 12,
                    color: secondaryTextColor,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildModuleCard(
    ModuleModel module,
    Color cardColor,
    Color textColor,
    Color secondaryTextColor,
    Color iconColor,
    bool isTablet,
  ) {
    final isExpanded = _expandedModules.contains(module.moduleId);

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(isTablet ? 12 : 8),
      ),
      child: Column(
        children: [
          // Module header
          InkWell(
            onTap: () {
              setState(() {
                if (isExpanded) {
                  _expandedModules.remove(module.moduleId);
                } else {
                  _expandedModules.add(module.moduleId);
                }
              });
            },
            borderRadius: BorderRadius.circular(isTablet ? 12 : 8),
            child: Padding(
              padding: EdgeInsets.all(isTablet ? 20 : 16),
              child: Row(
                children: [
                  // Lock icon
                  Container(
                    padding: EdgeInsets.all(isTablet ? 12 : 8),
                    decoration: BoxDecoration(
                      color: iconColor.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(isTablet ? 12 : 8),
                    ),
                    child: Icon(Icons.lock, color: iconColor, size: isTablet ? 26 : 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          module.name,
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            fontWeight: FontWeight.w600,
                            fontSize: isTablet ? 17 : 14,
                            color: textColor,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${module.lessonCount} lessons  •  ${module.completedLessons}/${module.lessonCount} complete',
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: isTablet ? 15 : 12,
                            color: secondaryTextColor,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    isExpanded ? Icons.expand_less : Icons.expand_more,
                    color: textColor,
                  ),
                ],
              ),
            ),
          ),

          // Module videos
          if (isExpanded) ...[
            const Divider(height: 1),
            ...module.videos.map((video) => _buildVideoItem(
                  video,
                  textColor,
                  secondaryTextColor,
                  iconColor,
                  isTablet,
                )),
          ],
        ],
      ),
    );
  }

  Widget _buildVideoItem(
    ModuleVideoModel video,
    Color textColor,
    Color secondaryTextColor,
    Color iconColor,
    bool isTablet,
  ) {
    final completionIconSize = isTablet ? 40.0 : 32.0;
    final innerIconSize = isTablet ? 22.0 : 18.0;

    // Priority: upcoming > locked > completed > default
    final IconData statusIcon;
    final Color statusIconColor;
    final Color statusBgColor;
    final bool tappable;
    final String? subtitle;

    if (video.isUpcoming) {
      statusIcon = Icons.schedule;
      statusIconColor = Colors.orange.shade700;
      statusBgColor = Colors.orange.shade100.withOpacity(0.6);
      tappable = false;
      subtitle = video.formattedReleaseDate != null
          ? 'Available ${video.formattedReleaseDate}'
          : 'Coming soon';
    } else if (video.isLocked) {
      statusIcon = Icons.lock;
      statusIconColor = secondaryTextColor;
      statusBgColor = secondaryTextColor.withOpacity(0.1);
      tappable = false;
      subtitle = null;
    } else if (video.isCompleted) {
      statusIcon = Icons.check;
      statusIconColor = Colors.green;
      statusBgColor = Colors.green.withOpacity(0.1);
      tappable = true;
      subtitle = null;
    } else {
      statusIcon = Icons.play_arrow;
      statusIconColor = iconColor;
      statusBgColor = iconColor.withOpacity(0.1);
      tappable = true;
      subtitle = null;
    }

    return InkWell(
      onTap: tappable ? () => context.push('/video/${video.videoId}') : null,
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: isTablet ? 22 : 16, vertical: 12),
        child: Row(
          children: [
            Container(
              width: completionIconSize,
              height: completionIconSize,
              decoration: BoxDecoration(
                color: statusBgColor,
                shape: BoxShape.circle,
              ),
              child: Icon(statusIcon, color: statusIconColor, size: innerIconSize),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    video.title,
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontWeight: FontWeight.w500,
                      fontSize: isTablet ? 17 : 14,
                      color: video.isUpcoming || video.isLocked
                          ? secondaryTextColor
                          : textColor,
                    ),
                  ),
                  const SizedBox(height: 4),
                  if (subtitle != null)
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: isTablet ? 13 : 11,
                        color: video.isUpcoming
                            ? Colors.orange.shade700
                            : secondaryTextColor,
                      ),
                    )
                  else
                    Row(
                      children: [
                        Icon(Icons.access_time, size: isTablet ? 15 : 12, color: secondaryTextColor),
                        const SizedBox(width: 4),
                        Text(
                          video.formattedDuration,
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: isTablet ? 15 : 12,
                            color: secondaryTextColor,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Icon(Icons.person, size: isTablet ? 15 : 12, color: secondaryTextColor),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            video.facultyName,
                            style: TextStyle(
                              fontFamily: 'Poppins',
                              fontSize: isTablet ? 15 : 12,
                              color: secondaryTextColor,
                            ),
                            overflow: TextOverflow.ellipsis,
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
}
