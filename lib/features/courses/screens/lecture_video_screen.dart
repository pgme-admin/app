import 'dart:io';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:pgme/core/providers/theme_provider.dart';
import 'package:pgme/core/theme/app_theme.dart';
import 'package:pgme/core/services/dashboard_service.dart';
import 'package:pgme/core/utils/web_store_launcher.dart';
import 'package:pgme/core/models/series_model.dart';
import 'package:pgme/core/models/package_model.dart';
import 'package:pgme/features/courses/providers/download_provider.dart';
import 'package:pgme/core/models/module_model.dart';
import 'package:pgme/core/widgets/shimmer_widgets.dart';
import 'package:pgme/core/utils/responsive_helper.dart';
import 'package:pgme/core/widgets/app_dialog.dart';
import 'package:cached_network_image/cached_network_image.dart';

class LectureVideoScreen extends StatefulWidget {
  final String courseId; // This is actually seriesId from route
  final bool isSubscribed;
  final String packageType; // 'Theory' or 'Practical'
  final String? packageId;

  const LectureVideoScreen({
    super.key,
    required this.courseId,
    this.isSubscribed = false,
    this.packageType = 'Theory',
    this.packageId,
  });

  @override
  State<LectureVideoScreen> createState() => _LectureVideoScreenState();
}

class _LectureVideoScreenState extends State<LectureVideoScreen> with TickerProviderStateMixin {
  final DashboardService _dashboardService = DashboardService();

  SeriesModel? _series;
  List<ModuleModel> _modules = [];
  String? _trailerVideoUrl;
  String? _packageThumbnailUrl;
  bool _isLoading = true;
  String? _error;

  Map<String, bool> _expandedModules = {};

  @override
  void initState() {
    super.initState();
    _loadData();
    // Ensure download provider is initialized and set up failure callback
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final dp = Provider.of<DownloadProvider>(context, listen: false);
      dp.loadDownloads();
      dp.onDownloadFailed = _onDownloadFailed;
      dp.onStorageFull = _onStorageFull;
    });
  }

  @override
  void dispose() {
    // Clear callbacks to avoid calling into a disposed widget
    try {
      final dp = Provider.of<DownloadProvider>(context, listen: false);
      if (dp.onDownloadFailed == _onDownloadFailed) {
        dp.onDownloadFailed = null;
      }
      if (dp.onStorageFull == _onStorageFull) {
        dp.onStorageFull = null;
      }
    } catch (_) {}
    super.dispose();
  }

  /// Called by the provider when a download fails (even in background)
  void _onDownloadFailed(DownloadFailureInfo failure) {
    if (!mounted) return;
    _showRetryDialog(failure.videoId, failure.title, failure.errorMessage);
  }

  /// Called by the provider when device storage is too low
  void _onStorageFull(String freeSpace) {
    if (!mounted) return;
    showAppDialog(
      context,
      title: 'Storage Full',
      message: 'Your device storage is almost full ($freeSpace free). '
          'Please free up space to download videos.',
      type: AppDialogType.warning,
      buttonText: 'OK',
    );
  }

  /// Show a prominent retry dialog for a failed download
  void _showRetryDialog(String videoId, String title, String errorMessage) {
    if (!mounted) return;
    showAppDialog(
      context,
      title: 'Download Failed',
      message: '$title\n\n$errorMessage',
      type: AppDialogType.error,
      actionLabel: 'Retry Download',
      onAction: () => _retryDownload(videoId),
    );
  }

  /// Download a video via the global DownloadProvider
  Future<void> _handleDownload(ModuleVideoModel video, ModuleModel module) async {
    final provider = Provider.of<DownloadProvider>(context, listen: false);
    if (provider.isDownloading(video.videoId) || provider.isDownloaded(video.videoId)) return;

    // startDownload does NOT throw — it uses the onDownloadFailed callback
    await provider.startDownload(
      videoId: video.videoId,
      title: video.title,
      facultyName: video.facultyName,
      durationSeconds: video.durationSeconds,
      moduleName: module.name,
      seriesName: _series?.title,
    );

    if (!mounted) return;

    // Check result after completion
    if (provider.isDownloaded(video.videoId)) {
      showAppDialog(context, message: 'Video downloaded successfully', type: AppDialogType.success);
    }
    // If failed, the onDownloadFailed callback already showed the retry dialog
  }

  /// Retry a failed download
  Future<void> _retryDownload(String videoId) async {
    final provider = Provider.of<DownloadProvider>(context, listen: false);
    // retryDownload does NOT throw — uses the same callback mechanism
    await provider.retryDownload(videoId);

    if (!mounted) return;

    if (provider.isDownloaded(videoId)) {
      showAppDialog(context, message: 'Video downloaded successfully', type: AppDialogType.success);
    }
    // If failed again, the onDownloadFailed callback will show retry dialog
  }

  void _handleBack() {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/home');
    }
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      // Fetch series details, modules, and package details in parallel
      final futures = <Future>[
        _dashboardService.getSeriesDetails(widget.courseId),
        _dashboardService.getSeriesModules(widget.courseId),
      ];

      // Also fetch package details if packageId is available (for trailer/thumbnail)
      if (widget.packageId != null && widget.packageId!.isNotEmpty) {
        futures.add(_dashboardService.getPackageDetails(widget.packageId!));
      }

      final results = await Future.wait(futures);

      if (mounted) {
        final packageDetails = results.length > 2 ? results[2] as PackageModel? : null;

        setState(() {
          _series = results[0] as SeriesModel;
          _modules = results[1] as List<ModuleModel>;
          _trailerVideoUrl = packageDetails?.trailerVideoUrl;
          _packageThumbnailUrl = packageDetails?.thumbnailUrl;
          _isLoading = false;

          // Initialize expanded state - expand first module by default
          if (_modules.isNotEmpty) {
            _expandedModules[_modules[0].moduleId] = true;
          }
        });
        // Download status is now managed by DownloadProvider
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
    final topPadding = MediaQuery.of(context).padding.top;
    final themeProvider = Provider.of<ThemeProvider>(context);
    final isDark = themeProvider.isDarkMode;
    final isTablet = ResponsiveHelper.isTablet(context);

    // Theme-aware colors
    final backgroundColor = isDark ? AppColors.darkBackground : Colors.white;
    final textColor = isDark ? AppColors.darkTextPrimary : const Color(0xFF000000);
    final secondaryTextColor = isDark ? AppColors.darkTextSecondary : const Color(0xFF718BA9);
    final cardBgColor = isDark ? AppColors.darkCardBackground : Colors.white;
    final iconColor = isDark ? const Color(0xFF00BEFA) : const Color(0xFF2470E4);
    final buttonColor = isDark ? const Color(0xFF0047CF) : const Color(0xFF0000D1);
    final lessonAccessibleBg = isDark ? const Color(0xFF1A3A5C) : const Color(0xFFE4F4FF);
    final lessonLockedBg = isDark ? AppColors.darkCardBackground : const Color(0xFFEFEFF8);

    // Responsive sizes
    final hPadding = isTablet ? 24.0 : 16.0;
    final headerIconSize = isTablet ? 30.0 : 24.0;
    final titleFontSize = isTablet ? 24.0 : 20.0;
    final bannerHeight = isTablet ? 320.0 : 242.0;
    final videoTitleSize = isTablet ? 22.0 : 18.0;
    final descFontSize = isTablet ? 17.0 : 14.0;
    final enrollBtnHeight = isTablet ? 68.0 : 54.0;
    final enrollFontSize = isTablet ? 19.0 : 16.0;
    final enrollBtnRadius = isTablet ? 28.0 : 22.0;
    final moduleGap = isTablet ? 12.0 : 7.0;
    final sectionGap = isTablet ? 28.0 : 23.0;

    return Scaffold(
      backgroundColor: backgroundColor,
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              child: Center(
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: ResponsiveHelper.getMaxContentWidth(context),
                  ),
                  child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header
                  Padding(
                    padding: EdgeInsets.only(top: topPadding + (isTablet ? 16 : 12), left: hPadding, right: hPadding),
                    child: Row(
                      children: [
                        GestureDetector(
                          onTap: _handleBack,
                          child: SizedBox(
                            width: headerIconSize,
                            height: headerIconSize,
                            child: Icon(
                              Icons.arrow_back,
                              size: headerIconSize,
                              color: textColor,
                            ),
                          ),
                        ),
                        SizedBox(width: isTablet ? 16 : 12),
                        Expanded(
                          child: Text(
                            _series?.title ?? 'Course',
                            textAlign: TextAlign.left,
                            style: TextStyle(
                              fontFamily: 'SF Pro Display',
                              fontWeight: FontWeight.w500,
                              fontSize: titleFontSize,
                              height: 1.0,
                              letterSpacing: -0.5,
                              color: textColor,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        // GestureDetector(
                        //   onTap: () {
                        //     // More options
                        //   },
                        //   child: SizedBox(
                        //     width: headerIconSize,
                        //     height: headerIconSize,
                        //     child: Icon(
                        //       Icons.more_horiz,
                        //       size: headerIconSize,
                        //       color: textColor,
                        //     ),
                        //   ),
                        // ),
                      ],
                    ),
                  ),

                  SizedBox(height: sectionGap),

                  // Course Banner Image with Trailer Play Button
                  GestureDetector(
                    onTap: _trailerVideoUrl != null
                        ? () {
                            context.push(
                              '/trailer-video',
                              extra: {
                                'videoUrl': _trailerVideoUrl,
                                'videoTitle': '${_series?.title ?? 'Course'} - Trailer',
                              },
                            );
                          }
                        : null,
                    child: ClipRRect(
                      borderRadius: isTablet ? BorderRadius.circular(16) : BorderRadius.zero,
                      child: Padding(
                        padding: EdgeInsets.symmetric(horizontal: isTablet ? hPadding : 0),
                        child: SizedBox(
                          width: double.infinity,
                          height: bannerHeight,
                          child: ClipRRect(
                            borderRadius: isTablet ? BorderRadius.circular(16) : BorderRadius.zero,
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                // Thumbnail: prefer package thumbnail, then series thumbnail, then fallback
                                _buildBannerImage(
                                  bannerHeight: bannerHeight,
                                  isDark: isDark,
                                  isTablet: isTablet,
                                  secondaryTextColor: secondaryTextColor,
                                ),
                                // Play button overlay (only if trailer exists)
                                if (_trailerVideoUrl != null)
                                  Center(
                                    child: Container(
                                      width: isTablet ? 72 : 56,
                                      height: isTablet ? 72 : 56,
                                      decoration: BoxDecoration(
                                        color: Colors.white.withValues(alpha: 0.9),
                                        shape: BoxShape.circle,
                                        boxShadow: [
                                          BoxShadow(
                                            color: Colors.black.withValues(alpha: 0.2),
                                            blurRadius: 8,
                                            offset: const Offset(0, 2),
                                          ),
                                        ],
                                      ),
                                      child: Icon(
                                        Icons.play_arrow_rounded,
                                        size: isTablet ? 40 : 32,
                                        color: const Color(0xFF2470E4),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),

                  SizedBox(height: sectionGap),

                  // Video Title
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: isTablet ? hPadding + 4 : 17),
                    child: Text(
                      _getFirstVideoTitle() ?? _series?.title ?? 'Video Title',
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontWeight: FontWeight.w500,
                        fontSize: videoTitleSize,
                        height: 1.0,
                        letterSpacing: -0.5,
                        color: textColor,
                      ),
                    ),
                  ),

                  SizedBox(height: isTablet ? 16 : 13),

                  // Description
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: isTablet ? hPadding + 4 : 17),
                    child: Text(
                      _series?.description ?? 'Course description',
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontWeight: FontWeight.w500,
                        fontSize: descFontSize,
                        height: 1.43,
                        letterSpacing: -0.5,
                        color: secondaryTextColor,
                      ),
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),

                  SizedBox(height: isTablet ? 24 : 16),

                  // Dynamic Modules List
                  if (_isLoading)
                    Padding(
                      padding: EdgeInsets.all(hPadding),
                      child: Column(
                        children: List.generate(4, (index) => ShimmerWidgets.listItemShimmer(isDark: isDark)),
                      ),
                    )
                  else if (_error != null)
                    Center(
                      child: Padding(
                        padding: EdgeInsets.all(isTablet ? 48.0 : 32.0),
                        child: Column(
                          children: [
                            Icon(Icons.error_outline, size: isTablet ? 60 : 48, color: secondaryTextColor),
                            SizedBox(height: isTablet ? 20 : 16),
                            Text('Failed to load modules', style: TextStyle(
                              color: textColor,
                              fontSize: isTablet ? 18 : 14,
                              fontFamily: 'Poppins',
                            )),
                            SizedBox(height: isTablet ? 20 : 16),
                            ElevatedButton(
                              onPressed: _loadData,
                              child: const Text('Retry'),
                            ),
                          ],
                        ),
                      ),
                    )
                  else if (_modules.isEmpty)
                    Center(
                      child: Padding(
                        padding: EdgeInsets.all(isTablet ? 48.0 : 32.0),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.video_library_outlined,
                              size: isTablet ? 64 : 48,
                              color: secondaryTextColor.withValues(alpha: 0.5),
                            ),
                            SizedBox(height: isTablet ? 20 : 16),
                            Text(
                              'Content Coming Soon',
                              style: TextStyle(
                                fontFamily: 'Poppins',
                                fontSize: isTablet ? 20 : 16,
                                fontWeight: FontWeight.w600,
                                color: textColor,
                              ),
                            ),
                            SizedBox(height: isTablet ? 10 : 8),
                            Text(
                              'We\'re preparing the lessons for this series.\nThey\'ll be available shortly!',
                              style: TextStyle(
                                fontFamily: 'Poppins',
                                fontSize: isTablet ? 16 : 13,
                                color: secondaryTextColor,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      ),
                    )
                  else
                    ..._modules.asMap().entries.map((entry) {
                      final index = entry.key;
                      final module = entry.value;
                      final isExpanded = _expandedModules[module.moduleId] ?? false;

                      return Padding(
                        padding: EdgeInsets.only(left: hPadding, right: hPadding, bottom: index < _modules.length - 1 ? moduleGap : 0),
                        child: _buildModuleCard(
                          module: module,
                          isExpanded: isExpanded,
                          isDark: isDark,
                          isTablet: isTablet,
                          textColor: textColor,
                          secondaryTextColor: secondaryTextColor,
                          cardBgColor: cardBgColor,
                          iconColor: iconColor,
                          lessonAccessibleBg: lessonAccessibleBg,
                          lessonLockedBg: lessonLockedBg,
                          onTap: () {
                            setState(() {
                              _expandedModules[module.moduleId] = !isExpanded;
                            });
                          },
                        ),
                      );
                    }).toList(),

                  SizedBox(height: isTablet ? 32 : 24),

                  // Enroll Now Button - Only show for unsubscribed users
                  if (!widget.isSubscribed)
                    Padding(
                      padding: EdgeInsets.symmetric(horizontal: hPadding),
                      child: SizedBox(
                        width: double.infinity,
                        height: enrollBtnHeight,
                        child: ElevatedButton(
                          onPressed: () {
                            if (WebStoreLauncher.shouldUseWebStore) {
                              WebStoreLauncher.openProductPage(context, productType: 'packages', productId: widget.packageId ?? '');
                            } else {
                              final params = <String>['packageType=${widget.packageType}'];
                              if (widget.packageId != null) params.add('packageId=${widget.packageId}');
                              context.push('/package-access?${params.join('&')}');
                            }
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: buttonColor,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(enrollBtnRadius),
                            ),
                            elevation: 0,
                          ),
                          child: Text(
                            Platform.isIOS ? 'Learn More' : 'Enroll Now',
                            style: TextStyle(
                              fontFamily: 'Poppins',
                              fontSize: enrollFontSize,
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ),

                  SizedBox(height: isTablet ? 120 : 100), // Space for nav bar
                ],
              ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Build the banner image with fallback: package thumbnail > series thumbnail > asset > icon
  Widget _buildBannerImage({
    required double bannerHeight,
    required bool isDark,
    required bool isTablet,
    required Color secondaryTextColor,
  }) {
    // Prefer package thumbnail, then series thumbnail
    final thumbnailUrl = _packageThumbnailUrl ?? _series?.thumbnailUrl;

    if (thumbnailUrl != null) {
      return CachedNetworkImage(
        imageUrl: thumbnailUrl,
        width: double.infinity,
        height: bannerHeight,
        fit: BoxFit.cover,
        placeholder: (context, url) => Container(
          color: isDark ? AppColors.darkSurface : const Color(0xFFE0E0E0),
          child: Center(
            child: CircularProgressIndicator(
              color: isDark ? Colors.white54 : Colors.black26,
              strokeWidth: 2,
            ),
          ),
        ),
        errorWidget: (context, url, error) => Image.asset(
          'assets/illustrations/course.png',
          width: double.infinity,
          height: bannerHeight,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) => _buildBannerPlaceholder(
            bannerHeight: bannerHeight,
            isDark: isDark,
            isTablet: isTablet,
            secondaryTextColor: secondaryTextColor,
          ),
        ),
      );
    }

    return Image.asset(
      'assets/illustrations/course.png',
      width: double.infinity,
      height: bannerHeight,
      fit: BoxFit.cover,
      errorBuilder: (context, error, stackTrace) => _buildBannerPlaceholder(
        bannerHeight: bannerHeight,
        isDark: isDark,
        isTablet: isTablet,
        secondaryTextColor: secondaryTextColor,
      ),
    );
  }

  Widget _buildBannerPlaceholder({
    required double bannerHeight,
    required bool isDark,
    required bool isTablet,
    required Color secondaryTextColor,
  }) {
    return Container(
      width: double.infinity,
      height: bannerHeight,
      color: isDark ? AppColors.darkSurface : const Color(0xFFE0E0E0),
      child: Center(
        child: Icon(
          Icons.image_outlined,
          size: isTablet ? 80 : 60,
          color: secondaryTextColor,
        ),
      ),
    );
  }

  Widget _buildLessonItem({
    required bool isAccessible,
    required bool isWatched,
    required String title,
    required String instructor,
    String? instructorPhotoUrl,
    required bool isDark,
    required bool isTablet,
    required Color textColor,
    required Color iconColor,
    required Color lessonAccessibleBg,
    required Color lessonLockedBg,
    VoidCallback? onTap,
    bool isDownloaded = false,
    bool isFailed = false,
    bool isPaused = false,
    double? downloadProgress,
    VoidCallback? onDownload,
    VoidCallback? onRetry,
    VoidCallback? onCancel,
  }) {
    final secondaryColor = isDark ? AppColors.darkTextSecondary : const Color(0xFF666666);
    final lockBgColor = isDark ? AppColors.darkCardBackground : const Color(0xFFDCEAF7);

    final lessonHeight = isTablet ? 80.0 : 60.0;
    final iconContainerSize = isTablet ? 42.0 : 32.0;
    final iconSize = isTablet ? 24.0 : 18.0;
    final lockSize = isTablet ? 22.0 : 16.0;
    final titleSize = isTablet ? 16.0 : 13.0;
    final metaSize = isTablet ? 14.0 : 11.0;
    final avatarSize = isTablet ? 26.0 : 18.0;
    final itemRadius = isTablet ? 16.0 : 12.0;
    final itemHPadding = isTablet ? 16.0 : 12.0;
    final downloadIconSize = isTablet ? 28.0 : 22.0;

    // Determine which icon to show
    IconData iconData;
    if (!isAccessible) {
      iconData = Icons.lock;
    } else if (isWatched) {
      iconData = Icons.check;
    } else {
      iconData = Icons.play_circle_outline;
    }

    // Determine download status text and color
    String? downloadStatusText;
    Color? downloadStatusColor;
    IconData? downloadStatusIcon;
    VoidCallback? downloadStatusTap;

    if (isAccessible && onDownload != null) {
      if (downloadProgress != null) {
        final pct = (downloadProgress * 100).round();
        downloadStatusText = downloadProgress > 0 ? 'Downloading $pct%' : 'Preparing...';
        downloadStatusColor = iconColor;
        downloadStatusIcon = Icons.downloading;
      } else if (isPaused) {
        downloadStatusText = 'Paused - will resume';
        downloadStatusColor = Colors.orange.shade400;
        downloadStatusIcon = Icons.pause_circle_outline;
        downloadStatusTap = onRetry;
      } else if (isFailed) {
        downloadStatusText = 'Failed - Tap to retry';
        downloadStatusColor = Colors.red.shade400;
        downloadStatusIcon = Icons.error_outline;
        downloadStatusTap = onRetry;
      } else if (isDownloaded) {
        downloadStatusText = 'Downloaded';
        downloadStatusColor = AppColors.success;
        downloadStatusIcon = Icons.download_done;
      }
    }

    // Show download button only when not downloaded and not downloading
    final showDownloadButton = isAccessible &&
        onDownload != null &&
        downloadProgress == null &&
        !isFailed &&
        !isPaused &&
        !isDownloaded;

    // Show retry icon button on the right side when failed or paused
    final showRetryButton = (isFailed || isPaused) && onRetry != null;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        constraints: BoxConstraints(minHeight: lessonHeight),
        padding: EdgeInsets.symmetric(vertical: isTablet ? 10 : 8),
        decoration: BoxDecoration(
          color: isAccessible ? lessonAccessibleBg : lessonLockedBg,
          borderRadius: BorderRadius.circular(itemRadius),
        ),
        child: Row(
          children: [
            SizedBox(width: itemHPadding),
            // Icon - Check for watched, Play for accessible unwatched, Lock for locked
            Container(
              width: iconContainerSize,
              height: iconContainerSize,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isAccessible ? iconColor : lockBgColor,
              ),
              child: Center(
                child: Icon(
                  iconData,
                  size: !isAccessible ? lockSize : iconSize,
                  color: isAccessible ? Colors.white : iconColor,
                ),
              ),
            ),
            SizedBox(width: itemHPadding),
            // Lesson details
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontWeight: FontWeight.w500,
                      fontSize: titleSize,
                      height: 1.0,
                      color: textColor,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  SizedBox(height: isTablet ? 6 : 4),
                  Row(
                    children: [
                      // Doctor avatar - use faculty photo if available, fallback to placeholder
                      ClipRRect(
                        borderRadius: BorderRadius.circular(avatarSize / 2),
                        child: instructorPhotoUrl != null && instructorPhotoUrl.isNotEmpty
                            ? CachedNetworkImage(
                                imageUrl: instructorPhotoUrl,
                                width: avatarSize,
                                height: avatarSize,
                                fit: BoxFit.cover,
                                placeholder: (context, url) => Image.asset(
                                  'assets/illustrations/doc.png',
                                  width: avatarSize,
                                  height: avatarSize,
                                  fit: BoxFit.cover,
                                ),
                                errorWidget: (context, url, error) => Image.asset(
                                  'assets/illustrations/doc.png',
                                  width: avatarSize,
                                  height: avatarSize,
                                  fit: BoxFit.cover,
                                ),
                              )
                            : Image.asset(
                                'assets/illustrations/doc.png',
                                width: avatarSize,
                                height: avatarSize,
                                fit: BoxFit.cover,
                                errorBuilder: (context, error, stackTrace) {
                                  return Container(
                                    width: avatarSize,
                                    height: avatarSize,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: isDark ? AppColors.darkDivider : const Color(0xFFE0E0E0),
                                    ),
                                  );
                                },
                              ),
                      ),
                      SizedBox(width: isTablet ? 6 : 4),
                      Expanded(
                        child: Text(
                          instructor,
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            fontWeight: FontWeight.w400,
                            fontSize: metaSize,
                            color: secondaryColor,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  // Download status label
                  if (downloadStatusText != null) ...[
                    SizedBox(height: isTablet ? 6 : 4),
                    GestureDetector(
                      onTap: downloadStatusTap,
                      child: Row(
                        children: [
                          if (downloadProgress != null && downloadProgress > 0)
                            // Small progress indicator for downloading state
                            SizedBox(
                              width: isTablet ? 18.0 : 14.0,
                              height: isTablet ? 18.0 : 14.0,
                              child: CircularProgressIndicator(
                                value: downloadProgress,
                                strokeWidth: 1.5,
                                color: downloadStatusColor,
                              ),
                            )
                          else
                            Icon(
                              downloadStatusIcon,
                              size: isTablet ? 18.0 : 14.0,
                              color: downloadStatusColor,
                            ),
                          SizedBox(width: isTablet ? 6 : 4),
                          Text(
                            downloadStatusText,
                            style: TextStyle(
                              fontFamily: 'Poppins',
                              fontWeight: FontWeight.w500,
                              fontSize: isTablet ? 13.0 : 10.0,
                              color: downloadStatusColor,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
            // Cancel button when downloading
            if (downloadProgress != null && onCancel != null)
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: onCancel,
                child: Container(
                  width: isTablet ? 44 : 38,
                  height: isTablet ? 44 : 38,
                  alignment: Alignment.center,
                  child: Icon(
                    Icons.close,
                    size: downloadIconSize,
                    color: secondaryColor,
                  ),
                ),
              )
            // Retry button when failed or paused
            else if (showRetryButton)
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: onRetry,
                child: Container(
                  width: isTablet ? 44 : 38,
                  height: isTablet ? 44 : 38,
                  alignment: Alignment.center,
                  child: Icon(
                    isFailed ? Icons.refresh : Icons.play_arrow,
                    size: downloadIconSize + 2,
                    color: isFailed ? Colors.red.shade400 : Colors.orange.shade400,
                  ),
                ),
              )
            // Download button (only when not downloading/downloaded/failed)
            else if (showDownloadButton)
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: onDownload,
                child: Container(
                  width: isTablet ? 44 : 38,
                  height: isTablet ? 44 : 38,
                  alignment: Alignment.center,
                  child: Icon(
                    Icons.download_outlined,
                    size: downloadIconSize,
                    color: secondaryColor,
                  ),
                ),
              ),
            SizedBox(width: isTablet ? 4 : 2),
          ],
        ),
      ),
    );
  }

  Widget _buildModuleCard({
    required ModuleModel module,
    required bool isExpanded,
    required VoidCallback onTap,
    required bool isDark,
    required bool isTablet,
    required Color textColor,
    required Color secondaryTextColor,
    required Color cardBgColor,
    required Color iconColor,
    required Color lessonAccessibleBg,
    required Color lessonLockedBg,
  }) {
    final videoCount = module.videos.length;
    final completedCount = module.completedLessons;

    final cardRadius = isTablet ? 16.0 : 12.0;
    final headerPadding = isTablet ? 20.0 : 16.0;
    final moduleNameSize = isTablet ? 15.0 : 12.0;
    final moduleMetaSize = isTablet ? 14.0 : 11.0;
    final arrowSize = isTablet ? 30.0 : 24.0;
    final lessonPaddingH = isTablet ? 18.0 : 14.0;
    final lessonGap = isTablet ? 10.0 : 8.0;
    final lessonBottomPad = isTablet ? 20.0 : 16.0;

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: cardBgColor,
        borderRadius: BorderRadius.circular(cardRadius),
        boxShadow: isDark
            ? [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.3),
                  blurRadius: isTablet ? 12 : 8,
                  offset: const Offset(0, 4),
                ),
              ]
            : [
                BoxShadow(
                  color: const Color(0x4D000000),
                  blurRadius: isTablet ? 4 : 3,
                  offset: const Offset(0, 1),
                ),
                BoxShadow(
                  color: const Color(0x26000000),
                  blurRadius: isTablet ? 12 : 8,
                  spreadRadius: isTablet ? 4 : 3,
                  offset: const Offset(0, 4),
                ),
              ],
      ),
      child: AnimatedSize(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
        child: Column(
          children: [
            // Module Header
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onTap,
              child: Container(
                padding: EdgeInsets.symmetric(horizontal: headerPadding, vertical: headerPadding),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            module.name.toUpperCase(),
                            style: TextStyle(
                              fontFamily: 'Poppins',
                              fontWeight: FontWeight.w600,
                              fontSize: moduleNameSize,
                              height: 1.0,
                              letterSpacing: -0.3,
                              color: textColor,
                            ),
                          ),
                          SizedBox(height: isTablet ? 8 : 6),
                          Text(
                            '$videoCount ${videoCount == 1 ? 'lesson' : 'lessons'}  •  $completedCount/$videoCount complete',
                            style: TextStyle(
                              fontFamily: 'Poppins',
                              fontWeight: FontWeight.w400,
                              fontSize: moduleMetaSize,
                              height: 1.0,
                              color: textColor.withValues(alpha: 0.5),
                            ),
                          ),
                        ],
                      ),
                    ),
                    AnimatedRotation(
                      turns: isExpanded ? 0.5 : 0,
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.easeInOut,
                      child: Icon(
                        Icons.keyboard_arrow_down,
                        size: arrowSize,
                        color: secondaryTextColor,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Videos list
            AnimatedCrossFade(
              firstChild: module.videos.isEmpty
                  ? Padding(
                      padding: EdgeInsets.symmetric(horizontal: lessonPaddingH, vertical: isTablet ? 20 : 16),
                      child: Row(
                        children: [
                          Icon(
                            Icons.upcoming_outlined,
                            size: isTablet ? 22 : 18,
                            color: iconColor.withValues(alpha: 0.6),
                          ),
                          SizedBox(width: isTablet ? 12 : 10),
                          Expanded(
                            child: Text(
                              'Lecture will be live soon',
                              style: TextStyle(
                                fontFamily: 'Poppins',
                                fontSize: isTablet ? 14 : 12,
                                fontWeight: FontWeight.w400,
                                fontStyle: FontStyle.italic,
                                color: secondaryTextColor,
                              ),
                            ),
                          ),
                        ],
                      ),
                    )
                  : Column(
                children: [
                  ...module.videos.asMap().entries.map((entry) {
                    final index = entry.key;
                    final video = entry.value;

                    // Access logic: Free videos are always accessible, paid videos require subscription
                    final isAccessible = video.isFree || widget.isSubscribed;

                    // Check if video has been watched
                    final isWatched = video.isCompleted;

                    return Padding(
                      padding: EdgeInsets.only(
                        left: lessonPaddingH,
                        right: lessonPaddingH,
                        bottom: index < module.videos.length - 1 ? lessonGap : lessonBottomPad,
                      ),
                      child: Builder(
                        builder: (context) {
                          final dp = context.watch<DownloadProvider>();
                          return _buildLessonItem(
                            isAccessible: isAccessible,
                            isWatched: isWatched,
                            title: video.title,
                            instructor: video.facultyName,
                            instructorPhotoUrl: video.facultyPhotoUrl,
                            isDark: isDark,
                            isTablet: isTablet,
                            textColor: textColor,
                            iconColor: iconColor,
                            lessonAccessibleBg: lessonAccessibleBg,
                            lessonLockedBg: lessonLockedBg,
                            onTap: isAccessible ? () => context.push('/video/${video.videoId}') : null,
                            isDownloaded: dp.isDownloaded(video.videoId),
                            isFailed: dp.hasFailed(video.videoId),
                            isPaused: dp.isPaused(video.videoId),
                            downloadProgress: dp.getProgress(video.videoId),
                            onDownload: isAccessible ? () => _handleDownload(video, module) : null,
                            onRetry: () => _retryDownload(video.videoId),
                            onCancel: () => Provider.of<DownloadProvider>(context, listen: false).cancelDownload(video.videoId),
                          );
                        },
                      ),
                    );
                  }).toList(),
                ],
              ),
              secondChild: const SizedBox.shrink(),
              crossFadeState: isExpanded
                  ? CrossFadeState.showFirst
                  : CrossFadeState.showSecond,
              duration: const Duration(milliseconds: 300),
              sizeCurve: Curves.easeInOut,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildModule({
    required String title,
    required String lessons,
    required String progress,
    required bool isExpanded,
    required VoidCallback onTap,
    required bool isLocked,
    required bool isDark,
    bool isTablet = false,
    required Color textColor,
    required Color cardBgColor,
    required Color iconColor,
    required Color secondaryTextColor,
    required Color lessonAccessibleBg,
    required Color lessonLockedBg,
  }) {
    final lockBgColor = isDark ? AppColors.darkCardBackground : const Color(0xFFDCEAF7);

    return Padding(
      padding: const EdgeInsets.only(left: 16),
      child: Container(
        width: 361,
        decoration: BoxDecoration(
          color: cardBgColor,
          borderRadius: BorderRadius.circular(12),
          boxShadow: isDark
              ? [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.3),
                    blurRadius: 8,
                    offset: const Offset(0, 4),
                  ),
                ]
              : const [
                  BoxShadow(
                    color: Color(0x4D000000),
                    blurRadius: 3,
                    offset: Offset(0, 1),
                  ),
                  BoxShadow(
                    color: Color(0x26000000),
                    blurRadius: 8,
                    spreadRadius: 3,
                    offset: Offset(0, 4),
                  ),
                ],
        ),
        child: AnimatedSize(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
          child: Column(
            children: [
              GestureDetector(
                onTap: onTap,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                  child: Row(
                    children: [
                      // Lock/Unlock icon based on state
                      if (isLocked)
                        Container(
                          width: 28,
                          height: 28,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: lockBgColor,
                          ),
                          child: Center(
                            child: Icon(
                              Icons.lock,
                              size: 14,
                              color: iconColor,
                            ),
                          ),
                        ),
                      if (isLocked) const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              title,
                              style: TextStyle(
                                fontFamily: 'Poppins',
                                fontWeight: FontWeight.w600,
                                fontSize: 12,
                                height: 1.0,
                                letterSpacing: -0.3,
                                color: textColor,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              '$lessons   •   $progress',
                              style: TextStyle(
                                fontFamily: 'Poppins',
                                fontWeight: FontWeight.w400,
                                fontSize: 11,
                                height: 1.0,
                                color: textColor.withValues(alpha: 0.5),
                              ),
                            ),
                          ],
                        ),
                      ),
                      AnimatedRotation(
                        turns: isExpanded ? 0.5 : 0,
                        duration: const Duration(milliseconds: 300),
                        curve: Curves.easeInOut,
                        child: Icon(
                          Icons.keyboard_arrow_down,
                          size: 24,
                          color: secondaryTextColor,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              // Show lessons when expanded with animation
              AnimatedCrossFade(
                firstChild: Column(
                  children: [
                    _buildLessonItem(
                      isAccessible: !isLocked,
                      isWatched: false,
                      title: 'Introduction to Valvular Structures',
                      instructor: 'Dr. Aviraj',
                      isDark: isDark,
                      isTablet: isTablet,
                      textColor: textColor,
                      iconColor: iconColor,
                      lessonAccessibleBg: lessonAccessibleBg,
                      lessonLockedBg: lessonLockedBg,
                      onTap: isLocked ? null : () => context.push('/video/2'),
                    ),
                    const SizedBox(height: 8),
                    _buildLessonItem(
                      isAccessible: !isLocked,
                      isWatched: false,
                      title: 'Introduction to Valvular Structures',
                      instructor: 'Dr. Aviraj',
                      isDark: isDark,
                      isTablet: isTablet,
                      textColor: textColor,
                      iconColor: iconColor,
                      lessonAccessibleBg: lessonAccessibleBg,
                      lessonLockedBg: lessonLockedBg,
                      onTap: isLocked ? null : () => context.push('/video/3'),
                    ),
                    const SizedBox(height: 8),
                    _buildLessonItem(
                      isAccessible: !isLocked,
                      isWatched: false,
                      title: 'Introduction to Valvular Structures',
                      instructor: 'Dr. Aviraj',
                      isDark: isDark,
                      isTablet: isTablet,
                      textColor: textColor,
                      iconColor: iconColor,
                      lessonAccessibleBg: lessonAccessibleBg,
                      lessonLockedBg: lessonLockedBg,
                      onTap: isLocked ? null : () => context.push('/video/4'),
                    ),
                    const SizedBox(height: 16),
                  ],
                ),
                secondChild: const SizedBox.shrink(),
                crossFadeState: isExpanded
                    ? CrossFadeState.showFirst
                    : CrossFadeState.showSecond,
                duration: const Duration(milliseconds: 300),
                sizeCurve: Curves.easeInOut,
              ),
            ],
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
}
