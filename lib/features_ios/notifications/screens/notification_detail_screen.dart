import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:pgme/core_ios/theme/app_theme.dart';
import 'package:pgme/core_ios/utils/responsive_helper.dart';
import 'package:pgme/core_ios/providers/theme_provider.dart';
import 'package:pgme/core_ios/models/notification_model.dart';

String _formatTimeAgo(DateTime dateTime) {
  final now = DateTime.now();
  final difference = now.difference(dateTime);

  if (difference.inSeconds < 60) {
    return 'Just now';
  } else if (difference.inMinutes < 60) {
    final minutes = difference.inMinutes;
    return '$minutes ${minutes == 1 ? 'minute' : 'minutes'} ago';
  } else if (difference.inHours < 24) {
    final hours = difference.inHours;
    return '$hours ${hours == 1 ? 'hour' : 'hours'} ago';
  } else if (difference.inDays < 7) {
    final days = difference.inDays;
    return '$days ${days == 1 ? 'day' : 'days'} ago';
  } else if (difference.inDays < 30) {
    final weeks = (difference.inDays / 7).floor();
    return '$weeks ${weeks == 1 ? 'week' : 'weeks'} ago';
  } else if (difference.inDays < 365) {
    final months = (difference.inDays / 30).floor();
    return '$months ${months == 1 ? 'month' : 'months'} ago';
  } else {
    final years = (difference.inDays / 365).floor();
    return '$years ${years == 1 ? 'year' : 'years'} ago';
  }
}

class NotificationDetailScreen extends StatelessWidget {
  final NotificationModel notification;

  const NotificationDetailScreen({super.key, required this.notification});

  Future<void> _handleCta(BuildContext context) async {
    final url = notification.clickUrl;
    if (url == null || url.isEmpty) return;

    if (notification.isExternalUrl) {
      final uri = Uri.tryParse(url);
      if (uri != null && await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    } else {
      context.go(url);
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final isDark = themeProvider.isDarkMode;
    final backgroundColor = isDark ? AppColors.darkBackground : Colors.white;
    final textColor = isDark ? AppColors.darkTextPrimary : const Color(0xFF000000);
    final secondaryTextColor = isDark ? AppColors.darkTextSecondary : AppColors.textSecondary;
    final isTablet = ResponsiveHelper.isTablet(context);
    final hasImage = notification.imageUrl != null && notification.imageUrl!.isNotEmpty;
    final hasAction = notification.clickUrl != null && notification.clickUrl!.isNotEmpty;

    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: AppBar(
        backgroundColor: backgroundColor,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: textColor),
          onPressed: () => context.pop(),
        ),
        title: Text(
          'Notification',
          style: TextStyle(
            fontFamily: 'Poppins',
            fontWeight: FontWeight.w600,
            fontSize: isTablet ? 24 : 18,
            color: textColor,
          ),
        ),
        centerTitle: true,
      ),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: EdgeInsets.symmetric(
                horizontal: isTablet ? 32 : 20,
                vertical: isTablet ? 24 : 16,
              ),
              child: Center(
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: ResponsiveHelper.getMaxContentWidth(context),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (hasImage) ...[
                        ClipRRect(
                          borderRadius: BorderRadius.circular(isTablet ? 16 : 12),
                          child: Image.network(
                            notification.imageUrl!,
                            width: double.infinity,
                            fit: BoxFit.cover,
                            loadingBuilder: (context, child, progress) {
                              if (progress == null) return child;
                              return Container(
                                width: double.infinity,
                                height: isTablet ? 260 : 200,
                                decoration: BoxDecoration(
                                  color: isDark ? AppColors.darkSurface : const Color(0xFFF5F5F5),
                                  borderRadius: BorderRadius.circular(isTablet ? 16 : 12),
                                ),
                                child: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
                              );
                            },
                            errorBuilder: (context, error, stackTrace) {
                              return const SizedBox.shrink();
                            },
                          ),
                        ),
                        SizedBox(height: isTablet ? 24 : 20),
                      ],
                      Text(
                        notification.title,
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          fontWeight: FontWeight.w700,
                          fontSize: isTablet ? 26 : 22,
                          color: textColor,
                          height: 1.3,
                        ),
                      ),
                      SizedBox(height: isTablet ? 10 : 8),
                      Text(
                        _formatTimeAgo(notification.sentAt),
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          fontWeight: FontWeight.w400,
                          fontSize: isTablet ? 15 : 13,
                          color: secondaryTextColor.withValues(alpha: 0.7),
                        ),
                      ),
                      SizedBox(height: isTablet ? 24 : 20),
                      Divider(
                        color: isDark ? AppColors.darkDivider : AppColors.divider,
                        height: 1,
                      ),
                      SizedBox(height: isTablet ? 24 : 20),
                      Text(
                        notification.message,
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          fontWeight: FontWeight.w400,
                          fontSize: isTablet ? 17 : 15,
                          color: secondaryTextColor,
                          height: 1.7,
                        ),
                      ),
                      SizedBox(height: hasAction ? 100 : 32),
                    ],
                  ),
                ),
              ),
            ),
          ),
          if (hasAction)
            Container(
              padding: EdgeInsets.fromLTRB(
                isTablet ? 32 : 20,
                12,
                isTablet ? 32 : 20,
                MediaQuery.of(context).padding.bottom + 16,
              ),
              decoration: BoxDecoration(
                color: backgroundColor,
                border: Border(
                  top: BorderSide(
                    color: isDark ? AppColors.darkDivider : AppColors.divider,
                    width: 1,
                  ),
                ),
              ),
              child: Center(
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: ResponsiveHelper.getMaxContentWidth(context),
                  ),
                  child: SizedBox(
                    width: double.infinity,
                    height: isTablet ? 56 : 50,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: AppColors.blueGradient,
                        borderRadius: BorderRadius.circular(30),
                      ),
                      child: TextButton.icon(
                        onPressed: () => _handleCta(context),
                        icon: Icon(
                          notification.isExternalUrl
                              ? Icons.open_in_new_rounded
                              : Icons.arrow_forward_rounded,
                          color: Colors.white,
                          size: isTablet ? 22 : 20,
                        ),
                        label: Text(
                          notification.isExternalUrl ? 'Open Link' : 'View',
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: isTablet ? 17 : 15,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                        ),
                        style: TextButton.styleFrom(
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(30),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
