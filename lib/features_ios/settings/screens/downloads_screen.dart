import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:pgme/core_ios/providers/theme_provider.dart';
import 'package:pgme/core_ios/theme/app_theme.dart';
import 'package:pgme/core_ios/models/offline_video_model.dart';
import 'package:pgme/core_ios/utils/responsive_helper.dart';
import 'package:pgme/features_ios/courses/providers/download_provider.dart';
import 'package:pgme/core_ios/widgets/app_dialog.dart';

class DownloadsScreen extends StatefulWidget {
  const DownloadsScreen({super.key});

  @override
  State<DownloadsScreen> createState() => _DownloadsScreenState();
}

class _DownloadsScreenState extends State<DownloadsScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Provider.of<DownloadProvider>(context, listen: false).loadDownloads();
    });
  }

  Future<void> _confirmDeleteAll(DownloadProvider provider) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete All Downloads'),
        content: Text(
            'Remove all ${provider.downloadedCount} downloaded videos? This will free up ${provider.formattedTotalStorage} of space.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete All',
                style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await provider.deleteAllDownloads();
      if (mounted) {
        showAppDialog(context, message: 'All downloads deleted', type: AppDialogType.info);
      }
    }
  }

  Future<void> _confirmDelete(
      DownloadProvider provider, OfflineVideoModel video) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Download'),
        content: Text('Remove "${video.title}" from downloads?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child:
                const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await provider.deleteDownload(video.videoId);
      if (mounted) {
        showAppDialog(context, message: '${video.title} deleted', type: AppDialogType.info);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final topPadding = MediaQuery.of(context).padding.top;
    final themeProvider = Provider.of<ThemeProvider>(context);
    final isDark = themeProvider.isDarkMode;
    final isTablet = ResponsiveHelper.isTablet(context);

    final backgroundColor =
        isDark ? AppColors.darkBackground : Colors.white;
    final textColor =
        isDark ? AppColors.darkTextPrimary : const Color(0xFF000000);
    final secondaryTextColor =
        isDark ? AppColors.darkTextSecondary : const Color(0xFF888888);
    final cardColor =
        isDark ? AppColors.darkCardBackground : const Color(0xFFF5F7FA);
    final iconColor =
        isDark ? const Color(0xFF00BEFA) : const Color(0xFF2470E4);

    final hPadding = isTablet ? 24.0 : 16.0;
    final headerIconSize = isTablet ? 30.0 : 24.0;
    final titleFontSize = isTablet ? 24.0 : 20.0;

    return Scaffold(
      backgroundColor: backgroundColor,
      body: Consumer<DownloadProvider>(
        builder: (context, dp, _) {
          final downloads = dp.downloadedVideos;
          final grouped = dp.downloadsBySeriesGroup;
          final activeDownloads = dp.activeDownloads;
          final failedDownloads = dp.failedDownloads;
          // Split paused (background-interrupted) from truly failed
          final pausedIds = failedDownloads.keys.where((id) => dp.isPaused(id)).toList();
          final trulyFailedIds = failedDownloads.keys.where((id) => dp.hasFailed(id)).toList();
          final hasContent = downloads.isNotEmpty ||
              activeDownloads.isNotEmpty ||
              failedDownloads.isNotEmpty;

          return Column(
            children: [
              // Header
              Padding(
                padding: EdgeInsets.only(
                    top: topPadding + (isTablet ? 16 : 12),
                    left: hPadding,
                    right: hPadding,
                    bottom: isTablet ? 16 : 12),
                child: Row(
                  children: [
                    GestureDetector(
                      onTap: () {
                        if (context.canPop()) {
                          context.pop();
                        } else {
                          context.go('/home');
                        }
                      },
                      child: Icon(Icons.arrow_back,
                          size: headerIconSize, color: textColor),
                    ),
                    SizedBox(width: isTablet ? 16 : 12),
                    Expanded(
                      child: Text(
                        'Downloads',
                        style: TextStyle(
                          fontFamily: 'SF Pro Display',
                          fontWeight: FontWeight.w500,
                          fontSize: titleFontSize,
                          letterSpacing: -0.5,
                          color: textColor,
                        ),
                      ),
                    ),
                    if (downloads.isNotEmpty)
                      GestureDetector(
                        onTap: () => _confirmDeleteAll(dp),
                        child: Icon(Icons.delete_outline,
                            size: headerIconSize, color: secondaryTextColor),
                      ),
                  ],
                ),
              ),

              // Content
              Expanded(
                child: !hasContent
                    ? _buildEmptyState(
                        isDark, isTablet, textColor, secondaryTextColor)
                    : RefreshIndicator(
                        onRefresh: () async {
                          await Provider.of<DownloadProvider>(context, listen: false).loadDownloads();
                        },
                        child: SingleChildScrollView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        child: Center(
                          child: ConstrainedBox(
                            constraints: BoxConstraints(
                              maxWidth:
                                  ResponsiveHelper.getMaxContentWidth(context),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // Active downloads section
                                if (activeDownloads.isNotEmpty)
                                  _buildActiveDownloadsSection(
                                    dp: dp,
                                    isDark: isDark,
                                    isTablet: isTablet,
                                    hPadding: hPadding,
                                    cardColor: cardColor,
                                    textColor: textColor,
                                    secondaryTextColor: secondaryTextColor,
                                    iconColor: iconColor,
                                  ),

                                // Paused downloads section (backgrounded)
                                if (pausedIds.isNotEmpty)
                                  _buildPausedDownloadsSection(
                                    dp: dp,
                                    pausedIds: pausedIds,
                                    isDark: isDark,
                                    isTablet: isTablet,
                                    hPadding: hPadding,
                                    cardColor: cardColor,
                                    textColor: textColor,
                                    secondaryTextColor: secondaryTextColor,
                                    iconColor: iconColor,
                                  ),

                                // Failed downloads section (real errors only)
                                if (trulyFailedIds.isNotEmpty)
                                  _buildFailedDownloadsSection(
                                    dp: dp,
                                    failedIds: trulyFailedIds,
                                    isDark: isDark,
                                    isTablet: isTablet,
                                    hPadding: hPadding,
                                    cardColor: cardColor,
                                    textColor: textColor,
                                    secondaryTextColor: secondaryTextColor,
                                    iconColor: iconColor,
                                  ),

                                // Storage summary (only if there are completed downloads)
                                if (downloads.isNotEmpty) ...[
                                  _buildStorageSummary(
                                    dp,
                                    isDark,
                                    isTablet,
                                    hPadding,
                                    cardColor,
                                    textColor,
                                    secondaryTextColor,
                                    iconColor,
                                  ),
                                  SizedBox(height: isTablet ? 24 : 16),

                                  // Grouped video list
                                  ...grouped.entries.map((entry) {
                                    return _buildSeriesGroup(
                                      seriesName: entry.key,
                                      videos: entry.value,
                                      downloadProvider: dp,
                                      isDark: isDark,
                                      isTablet: isTablet,
                                      hPadding: hPadding,
                                      cardColor: cardColor,
                                      textColor: textColor,
                                      secondaryTextColor: secondaryTextColor,
                                      iconColor: iconColor,
                                    );
                                  }),
                                ],

                                SizedBox(height: isTablet ? 48 : 32),
                              ],
                            ),
                          ),
                        ),
                      ),
                      ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildActiveDownloadsSection({
    required DownloadProvider dp,
    required bool isDark,
    required bool isTablet,
    required double hPadding,
    required Color cardColor,
    required Color textColor,
    required Color secondaryTextColor,
    required Color iconColor,
  }) {
    final activeDownloads = dp.activeDownloads;
    final titleSize = isTablet ? 15.0 : 13.0;
    final metaSize = isTablet ? 13.0 : 11.0;
    final cardRadius = isTablet ? 16.0 : 12.0;
    final cardPadding = isTablet ? 14.0 : 10.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.symmetric(
              horizontal: hPadding, vertical: isTablet ? 12 : 8),
          child: Text(
            'Downloading',
            style: TextStyle(
              fontFamily: 'Poppins',
              fontWeight: FontWeight.w600,
              fontSize: isTablet ? 16 : 13,
              letterSpacing: -0.3,
              color: iconColor,
            ),
          ),
        ),
        ...activeDownloads.entries.map((entry) {
          final videoId = entry.key;
          final progress = entry.value;
          final title = dp.getActiveDownloadTitle(videoId) ?? 'Downloading...';
          final pct = (progress * 100).round();

          return Padding(
            padding: EdgeInsets.only(
                left: hPadding, right: hPadding, bottom: isTablet ? 10 : 8),
            child: Container(
              padding: EdgeInsets.all(cardPadding),
              decoration: BoxDecoration(
                color: cardColor,
                borderRadius: BorderRadius.circular(cardRadius),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      // Spinner icon
                      SizedBox(
                        width: isTablet ? 22.0 : 18.0,
                        height: isTablet ? 22.0 : 18.0,
                        child: CircularProgressIndicator(
                          value: progress > 0 ? progress : null,
                          strokeWidth: 2,
                          color: iconColor,
                        ),
                      ),
                      SizedBox(width: isTablet ? 14 : 10),
                      Expanded(
                        child: Text(
                          title,
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            fontWeight: FontWeight.w500,
                            fontSize: titleSize,
                            color: textColor,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        progress > 0 ? '$pct%' : 'Preparing...',
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: metaSize,
                          fontWeight: FontWeight.w500,
                          color: iconColor,
                        ),
                      ),
                      SizedBox(width: isTablet ? 10 : 8),
                      // Cancel button
                      GestureDetector(
                        onTap: () => dp.cancelDownload(videoId),
                        child: Icon(
                          Icons.close,
                          size: isTablet ? 22.0 : 18.0,
                          color: secondaryTextColor,
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: isTablet ? 10 : 8),
                  // Progress bar
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: progress > 0 ? progress : null,
                      backgroundColor: isDark
                          ? Colors.white.withValues(alpha: 0.1)
                          : Colors.black.withValues(alpha: 0.08),
                      color: iconColor,
                      minHeight: isTablet ? 6 : 4,
                    ),
                  ),
                ],
              ),
            ),
          );
        }),
        SizedBox(height: isTablet ? 16 : 12),
      ],
    );
  }

  Widget _buildPausedDownloadsSection({
    required DownloadProvider dp,
    required List<String> pausedIds,
    required bool isDark,
    required bool isTablet,
    required double hPadding,
    required Color cardColor,
    required Color textColor,
    required Color secondaryTextColor,
    required Color iconColor,
  }) {
    final pauseColor = Colors.orange.shade400;
    final titleSize = isTablet ? 15.0 : 13.0;
    final cardRadius = isTablet ? 16.0 : 12.0;
    final cardPadding = isTablet ? 14.0 : 10.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.symmetric(
              horizontal: hPadding, vertical: isTablet ? 12 : 8),
          child: Text(
            'Paused',
            style: TextStyle(
              fontFamily: 'Poppins',
              fontWeight: FontWeight.w600,
              fontSize: isTablet ? 16 : 13,
              letterSpacing: -0.3,
              color: pauseColor,
            ),
          ),
        ),
        ...pausedIds.map((videoId) {
          final title = dp.getActiveDownloadTitle(videoId) ?? 'Unknown video';
          return Padding(
            padding: EdgeInsets.only(
                left: hPadding, right: hPadding, bottom: isTablet ? 10 : 8),
            child: Container(
              padding: EdgeInsets.all(cardPadding),
              decoration: BoxDecoration(
                color: cardColor,
                borderRadius: BorderRadius.circular(cardRadius),
                border: Border.all(
                  color: pauseColor.withValues(alpha: 0.3),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.pause_circle_outline,
                    size: isTablet ? 22.0 : 18.0,
                    color: pauseColor,
                  ),
                  SizedBox(width: isTablet ? 14 : 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            fontWeight: FontWeight.w500,
                            fontSize: titleSize,
                            color: textColor,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Will resume automatically when you return',
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: isTablet ? 12 : 10,
                            color: pauseColor.withValues(alpha: 0.8),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  // Resume now button
                  GestureDetector(
                    onTap: () async {
                      try {
                        await dp.retryDownload(videoId);
                      } catch (_) {}
                    },
                    child: Container(
                      padding: EdgeInsets.symmetric(
                        horizontal: isTablet ? 14 : 10,
                        vertical: isTablet ? 8 : 6,
                      ),
                      decoration: BoxDecoration(
                        color: pauseColor.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(isTablet ? 10 : 8),
                      ),
                      child: Text(
                        'Resume',
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: isTablet ? 13 : 11,
                          fontWeight: FontWeight.w600,
                          color: pauseColor,
                        ),
                      ),
                    ),
                  ),
                  SizedBox(width: isTablet ? 8 : 4),
                  GestureDetector(
                    onTap: () => dp.clearFailure(videoId),
                    child: Padding(
                      padding: EdgeInsets.all(isTablet ? 6.0 : 4.0),
                      child: Icon(
                        Icons.close,
                        size: isTablet ? 20 : 16,
                        color: secondaryTextColor,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        }),
        SizedBox(height: isTablet ? 16 : 12),
      ],
    );
  }

  Widget _buildFailedDownloadsSection({
    required DownloadProvider dp,
    required List<String> failedIds,
    required bool isDark,
    required bool isTablet,
    required double hPadding,
    required Color cardColor,
    required Color textColor,
    required Color secondaryTextColor,
    required Color iconColor,
  }) {
    final failedDownloads = dp.failedDownloads;
    final titleSize = isTablet ? 15.0 : 13.0;
    final metaSize = isTablet ? 13.0 : 11.0;
    final cardRadius = isTablet ? 16.0 : 12.0;
    final cardPadding = isTablet ? 14.0 : 10.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.symmetric(
              horizontal: hPadding, vertical: isTablet ? 12 : 8),
          child: Text(
            'Failed',
            style: TextStyle(
              fontFamily: 'Poppins',
              fontWeight: FontWeight.w600,
              fontSize: isTablet ? 16 : 13,
              letterSpacing: -0.3,
              color: Colors.red.shade400,
            ),
          ),
        ),
        ...failedIds.map((videoId) {
          final errorMsg = failedDownloads[videoId] ?? 'Download failed';
          final title = dp.getActiveDownloadTitle(videoId) ?? 'Unknown video';

          return Padding(
            padding: EdgeInsets.only(
                left: hPadding, right: hPadding, bottom: isTablet ? 10 : 8),
            child: Container(
              padding: EdgeInsets.all(cardPadding),
              decoration: BoxDecoration(
                color: cardColor,
                borderRadius: BorderRadius.circular(cardRadius),
                border: Border.all(
                  color: Colors.red.shade200.withValues(alpha: 0.5),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.error_outline,
                    size: isTablet ? 22.0 : 18.0,
                    color: Colors.red.shade400,
                  ),
                  SizedBox(width: isTablet ? 14 : 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            fontWeight: FontWeight.w500,
                            fontSize: titleSize,
                            color: textColor,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          errorMsg,
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: metaSize,
                            color: Colors.red.shade300,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  // Retry button
                  GestureDetector(
                    onTap: () async {
                      try {
                        await dp.retryDownload(videoId);
                      } catch (_) {}
                    },
                    child: Container(
                      padding: EdgeInsets.symmetric(
                        horizontal: isTablet ? 14 : 10,
                        vertical: isTablet ? 8 : 6,
                      ),
                      decoration: BoxDecoration(
                        color: iconColor.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(isTablet ? 10 : 8),
                      ),
                      child: Text(
                        'Retry',
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: isTablet ? 13 : 11,
                          fontWeight: FontWeight.w600,
                          color: iconColor,
                        ),
                      ),
                    ),
                  ),
                  SizedBox(width: isTablet ? 8 : 4),
                  // Dismiss button
                  GestureDetector(
                    onTap: () => dp.clearFailure(videoId),
                    child: Padding(
                      padding: EdgeInsets.all(isTablet ? 6.0 : 4.0),
                      child: Icon(
                        Icons.close,
                        size: isTablet ? 20 : 16,
                        color: secondaryTextColor,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        }),
        SizedBox(height: isTablet ? 16 : 12),
      ],
    );
  }

  Widget _buildEmptyState(
      bool isDark, bool isTablet, Color textColor, Color secondaryTextColor) {
    return Center(
      child: Padding(
        padding: EdgeInsets.all(isTablet ? 48.0 : 32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.download_for_offline_outlined,
              size: isTablet ? 80 : 64,
              color: secondaryTextColor.withValues(alpha: 0.4),
            ),
            SizedBox(height: isTablet ? 24 : 16),
            Text(
              'No Downloads',
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: isTablet ? 22 : 18,
                fontWeight: FontWeight.w600,
                color: textColor,
              ),
            ),
            SizedBox(height: isTablet ? 12 : 8),
            Text(
              'Download videos from your lectures\nto watch them offline',
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: isTablet ? 16 : 14,
                color: secondaryTextColor,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStorageSummary(
    DownloadProvider provider,
    bool isDark,
    bool isTablet,
    double hPadding,
    Color cardColor,
    Color textColor,
    Color secondaryTextColor,
    Color iconColor,
  ) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: hPadding),
      child: Container(
        width: double.infinity,
        padding: EdgeInsets.all(isTablet ? 20 : 16),
        decoration: BoxDecoration(
          color: cardColor,
          borderRadius: BorderRadius.circular(isTablet ? 16 : 12),
        ),
        child: Row(
          children: [
            Container(
              width: isTablet ? 48 : 40,
              height: isTablet ? 48 : 40,
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(isTablet ? 14 : 10),
              ),
              child: Center(
                child: Icon(
                  Icons.folder_outlined,
                  size: isTablet ? 24 : 20,
                  color: iconColor,
                ),
              ),
            ),
            SizedBox(width: isTablet ? 16 : 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${provider.downloadedCount} ${provider.downloadedCount == 1 ? 'video' : 'videos'} downloaded',
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontWeight: FontWeight.w600,
                      fontSize: isTablet ? 16 : 14,
                      color: textColor,
                    ),
                  ),
                  SizedBox(height: isTablet ? 4 : 2),
                  Text(
                    '${provider.formattedTotalStorage} used',
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: isTablet ? 14 : 12,
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

  Widget _buildSeriesGroup({
    required String seriesName,
    required List<OfflineVideoModel> videos,
    required DownloadProvider downloadProvider,
    required bool isDark,
    required bool isTablet,
    required double hPadding,
    required Color cardColor,
    required Color textColor,
    required Color secondaryTextColor,
    required Color iconColor,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Series header
        Padding(
          padding:
              EdgeInsets.symmetric(horizontal: hPadding, vertical: isTablet ? 12 : 8),
          child: Text(
            seriesName,
            style: TextStyle(
              fontFamily: 'Poppins',
              fontWeight: FontWeight.w600,
              fontSize: isTablet ? 16 : 13,
              letterSpacing: -0.3,
              color: secondaryTextColor,
            ),
          ),
        ),

        // Video cards
        ...videos.map((video) => Padding(
              padding: EdgeInsets.only(
                  left: hPadding, right: hPadding, bottom: isTablet ? 10 : 8),
              child: Dismissible(
                key: Key('download_${video.videoId}'),
                direction: DismissDirection.endToStart,
                background: Container(
                  alignment: Alignment.centerRight,
                  padding: EdgeInsets.only(right: isTablet ? 24 : 16),
                  decoration: BoxDecoration(
                    color: Colors.red.shade400,
                    borderRadius: BorderRadius.circular(isTablet ? 16 : 12),
                  ),
                  child: const Icon(Icons.delete_outline,
                      color: Colors.white, size: 24),
                ),
                confirmDismiss: (_) async {
                  await _confirmDelete(downloadProvider, video);
                  return false;
                },
                child: _buildVideoCard(
                  video: video,
                  downloadProvider: downloadProvider,
                  isDark: isDark,
                  isTablet: isTablet,
                  cardColor: cardColor,
                  textColor: textColor,
                  secondaryTextColor: secondaryTextColor,
                  iconColor: iconColor,
                ),
              ),
            )),
      ],
    );
  }

  Widget _buildVideoCard({
    required OfflineVideoModel video,
    required DownloadProvider downloadProvider,
    required bool isDark,
    required bool isTablet,
    required Color cardColor,
    required Color textColor,
    required Color secondaryTextColor,
    required Color iconColor,
  }) {
    final thumbnailSize = isTablet ? 80.0 : 64.0;
    final titleSize = isTablet ? 15.0 : 13.0;
    final metaSize = isTablet ? 13.0 : 11.0;
    final cardRadius = isTablet ? 16.0 : 12.0;
    final cardPadding = isTablet ? 14.0 : 10.0;

    return GestureDetector(
      onTap: () => context.push('/video/${video.videoId}'),
      child: Container(
        padding: EdgeInsets.all(cardPadding),
        decoration: BoxDecoration(
          color: cardColor,
          borderRadius: BorderRadius.circular(cardRadius),
        ),
        child: Row(
          children: [
            // Thumbnail
            ClipRRect(
              borderRadius: BorderRadius.circular(isTablet ? 12 : 8),
              child: SizedBox(
                width: thumbnailSize * 16 / 9,
                height: thumbnailSize,
                child: video.thumbnailUrl != null
                    ? CachedNetworkImage(
                        imageUrl: video.thumbnailUrl!,
                        fit: BoxFit.cover,
                        placeholder: (_, __) => Container(
                          color: isDark
                              ? AppColors.darkSurface
                              : const Color(0xFFE0E0E0),
                          child: Center(
                            child: Icon(Icons.play_circle_outline,
                                size: isTablet ? 30 : 24,
                                color: secondaryTextColor),
                          ),
                        ),
                        errorWidget: (_, __, ___) => Container(
                          color: isDark
                              ? AppColors.darkSurface
                              : const Color(0xFFE0E0E0),
                          child: Center(
                            child: Icon(Icons.play_circle_outline,
                                size: isTablet ? 30 : 24,
                                color: secondaryTextColor),
                          ),
                        ),
                      )
                    : Container(
                        color: isDark
                            ? AppColors.darkSurface
                            : const Color(0xFFE0E0E0),
                        child: Center(
                          child: Icon(Icons.play_circle_outline,
                              size: isTablet ? 30 : 24,
                              color: secondaryTextColor),
                        ),
                      ),
              ),
            ),

            SizedBox(width: isTablet ? 14 : 10),

            // Video info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    video.title,
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontWeight: FontWeight.w500,
                      fontSize: titleSize,
                      color: textColor,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  SizedBox(height: isTablet ? 6 : 4),
                  if (video.facultyName.isNotEmpty)
                    Text(
                      video.facultyName,
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: metaSize,
                        color: secondaryTextColor,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  SizedBox(height: isTablet ? 4 : 2),
                  Text(
                    '${video.formattedDuration}  •  ${video.formattedFileSize}',
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: metaSize,
                      color: secondaryTextColor.withValues(alpha: 0.7),
                    ),
                  ),
                ],
              ),
            ),

            // Delete button
            GestureDetector(
              onTap: () => _confirmDelete(downloadProvider, video),
              child: Padding(
                padding: EdgeInsets.all(isTablet ? 8.0 : 6.0),
                child: Icon(
                  Icons.delete_outline,
                  size: isTablet ? 22 : 18,
                  color: secondaryTextColor,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
