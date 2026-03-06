import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:pgme/core/theme/app_theme.dart';
import 'package:pgme/core/utils/responsive_helper.dart';
import 'package:pgme/core/providers/theme_provider.dart';
import 'package:pgme/core/models/notification_model.dart';
import 'package:pgme/features/notifications/providers/notification_provider.dart';
import 'package:pgme/core/widgets/app_dialog.dart';
import 'package:pgme/core/services/dashboard_service.dart';

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

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  final ScrollController _scrollController = ScrollController();
  final DashboardService _dashboardService = DashboardService();
  bool _isCheckingSession = false;

  @override
  void initState() {
    super.initState();
    _loadNotifications();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _loadNotifications() {
    Future.microtask(() {
      if (mounted) {
        context.read<NotificationProvider>().loadNotifications();
      }
    });
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      context.read<NotificationProvider>().loadMore();
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
          'Notifications',
          style: TextStyle(
            fontFamily: 'Poppins',
            fontWeight: FontWeight.w600,
            fontSize: isTablet ? 24 : 18,
            color: textColor,
          ),
        ),
        centerTitle: true,
      ),
      body: Consumer<NotificationProvider>(
        builder: (context, provider, _) {
          if (provider.isLoading) {
            return const Center(child: CircularProgressIndicator());
          }

          if (provider.error != null) {
            return _buildErrorState(provider, textColor, secondaryTextColor, isTablet);
          }

          if (provider.notifications.isEmpty) {
            return _buildEmptyState(secondaryTextColor, isTablet);
          }

          return RefreshIndicator(
            onRefresh: provider.refresh,
            child: Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: ResponsiveHelper.getMaxContentWidth(context),
                ),
                child: ListView.builder(
                  controller: _scrollController,
                  physics: const AlwaysScrollableScrollPhysics(parent: ClampingScrollPhysics()),
                  padding: EdgeInsets.symmetric(vertical: isTablet ? 12 : 8),
                  itemCount: provider.notifications.length + (provider.isLoadingMore ? 1 : 0),
                  itemBuilder: (context, index) {
                    if (index == provider.notifications.length) {
                      return const Center(
                        child: Padding(
                          padding: EdgeInsets.all(16),
                          child: CircularProgressIndicator(),
                        ),
                      );
                    }

                    final notification = provider.notifications[index];
                    return _NotificationTile(
                      notification: notification,
                      isDark: isDark,
                      isTablet: isTablet,
                      onTap: () => _onNotificationTap(notification, provider),
                      onDismiss: () => _onNotificationDismiss(notification, provider),
                    );
                  },
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildErrorState(
    NotificationProvider provider,
    Color textColor,
    Color secondaryTextColor,
    bool isTablet,
  ) {
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: ResponsiveHelper.getMaxContentWidth(context),
        ),
        child: Padding(
          padding: EdgeInsets.all(isTablet ? 48 : 32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.error_outline,
                size: isTablet ? 80 : 64,
                color: secondaryTextColor,
              ),
              SizedBox(height: isTablet ? 20 : 16),
              Text(
                'Failed to load notifications',
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontWeight: FontWeight.w600,
                  fontSize: isTablet ? 22 : 18,
                  color: textColor,
                ),
              ),
              SizedBox(height: isTablet ? 10 : 8),
              Text(
                provider.error ?? 'Unknown error',
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: isTablet ? 17 : 14,
                  color: secondaryTextColor,
                ),
                textAlign: TextAlign.center,
              ),
              SizedBox(height: isTablet ? 30 : 24),
              ElevatedButton(
                onPressed: () => provider.loadNotifications(),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primaryBlue,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(isTablet ? 16 : 12),
                  ),
                ),
                child: Text(
                  'Retry',
                  style: TextStyle(
                    fontSize: isTablet ? 17 : 14,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState(Color secondaryTextColor, bool isTablet) {
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: ResponsiveHelper.getMaxContentWidth(context),
        ),
        child: Padding(
          padding: EdgeInsets.all(isTablet ? 48 : 32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.notifications_none_outlined,
                size: isTablet ? 100 : 80,
                color: secondaryTextColor,
              ),
              SizedBox(height: isTablet ? 20 : 16),
              Text(
                'No notifications yet',
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontWeight: FontWeight.w600,
                  fontSize: isTablet ? 22 : 18,
                  color: secondaryTextColor,
                ),
              ),
              SizedBox(height: isTablet ? 10 : 8),
              Text(
                'You\'ll see your notifications here',
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
    );
  }

  Future<void> _onNotificationTap(NotificationModel notification, NotificationProvider provider) async {
    if (!notification.isRead) {
      provider.markAsRead(notification.notificationId);
    }

    final url = notification.clickUrl;
    if (url == null || url.isEmpty) return;

    // Session URL → check live status before navigating
    final sessionMatch = RegExp(r'^/session/([^/?]+)').firstMatch(url);
    if (sessionMatch != null) {
      await _handleSessionTap(sessionMatch.group(1)!, url);
      return;
    }

    // Course / subject URL → show detail modal
    if (url.startsWith('/course/') ||
        url.startsWith('/series-detail/') ||
        url.startsWith('/series-sessions/')) {
      _showNotificationDetailSheet(notification, url);
      return;
    }

    // Everything else → navigate directly
    context.push(url);
  }

  Future<void> _handleSessionTap(String sessionId, String url) async {
    if (_isCheckingSession) return;
    setState(() => _isCheckingSession = true);

    // Show a lightweight loading overlay
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final session = await _dashboardService.getSessionDetails(sessionId);
      if (!mounted) return;
      Navigator.of(context).pop(); // dismiss loader

      switch (session.status) {
        case 'completed':
          showAppDialog(
            context,
            title: 'Session Ended',
            message: '"${session.title}" has already ended.',
            type: AppDialogType.info,
          );
        case 'cancelled':
          showAppDialog(
            context,
            title: 'Session Cancelled',
            message: '"${session.title}" has been cancelled.',
            type: AppDialogType.warning,
          );
        default:
          // 'live' or 'scheduled' — open the session page
          context.push(url);
      }
    } catch (_) {
      if (!mounted) return;
      Navigator.of(context).pop(); // dismiss loader
      context.push(url); // fallback: just navigate
    } finally {
      if (mounted) setState(() => _isCheckingSession = false);
    }
  }

  void _showNotificationDetailSheet(NotificationModel notification, String url) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _NotificationDetailSheet(
        notification: notification,
        onView: () {
          Navigator.of(context).pop();
          context.push(url);
        },
      ),
    );
  }

  void _onNotificationDismiss(NotificationModel notification, NotificationProvider provider) {
    // Optimistically remove from local state first
    provider.removeNotificationLocally(notification);

    bool undoClicked = false;
    showAppDialog(
      context,
      message: 'Notification deleted',
      type: AppDialogType.info,
      actionLabel: 'Undo',
      onAction: () {
        undoClicked = true;
        provider.restoreNotification(notification);
      },
    ).then((_) {
      // Dialog closed without undo — now permanently delete from server
      if (!undoClicked) {
        provider.deleteNotificationOnServer(notification.notificationId);
      }
    });
  }
}

class _NotificationTile extends StatelessWidget {
  final NotificationModel notification;
  final bool isDark;
  final bool isTablet;
  final VoidCallback onTap;
  final VoidCallback onDismiss;

  const _NotificationTile({
    required this.notification,
    required this.isDark,
    required this.isTablet,
    required this.onTap,
    required this.onDismiss,
  });

  IconData _getNotificationIcon() {
    switch (notification.notificationType) {
      case 'push':
        return Icons.notifications_active_outlined;
      case 'email':
        return Icons.email_outlined;
      case 'sms':
        return Icons.message_outlined;
      case 'in_app':
      default:
        return Icons.info_outline;
    }
  }

  @override
  Widget build(BuildContext context) {
    final textColor = isDark ? AppColors.darkTextPrimary : const Color(0xFF000000);
    final secondaryTextColor = isDark ? AppColors.darkTextSecondary : AppColors.textSecondary;
    final backgroundColor = isDark ? AppColors.darkCardBackground : Colors.white;
    final unreadBackground = isDark
        ? AppColors.primaryBlue.withValues(alpha: 0.1)
        : AppColors.primaryBlue.withValues(alpha: 0.05);

    return Dismissible(
      key: Key(notification.notificationId),
      direction: DismissDirection.endToStart,
      onDismissed: (_) => onDismiss(),
      background: Container(
        color: AppColors.error,
        alignment: Alignment.centerRight,
        padding: EdgeInsets.only(right: isTablet ? 28 : 20),
        child: Icon(
          Icons.delete_outline,
          color: Colors.white,
          size: isTablet ? 28 : 24,
        ),
      ),
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: EdgeInsets.symmetric(
            horizontal: isTablet ? 24 : 16,
            vertical: isTablet ? 16 : 12,
          ),
          color: notification.isRead ? backgroundColor : unreadBackground,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Icon
              Container(
                width: isTablet ? 60 : 44,
                height: isTablet ? 60 : 44,
                decoration: BoxDecoration(
                  color: isDark
                      ? AppColors.darkSurface
                      : const Color(0xFFF5F5F5),
                  borderRadius: BorderRadius.circular(isTablet ? 16 : 12),
                ),
                child: Icon(
                  _getNotificationIcon(),
                  size: isTablet ? 28 : 22,
                  color: notification.isRead ? secondaryTextColor : AppColors.primaryBlue,
                ),
              ),
              SizedBox(width: isTablet ? 16 : 12),

              // Content
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            notification.title,
                            style: TextStyle(
                              fontFamily: 'Poppins',
                              fontWeight: notification.isRead ? FontWeight.w500 : FontWeight.w600,
                              fontSize: isTablet ? 19 : 15,
                              color: textColor,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (!notification.isRead)
                          Container(
                            width: isTablet ? 10 : 8,
                            height: isTablet ? 10 : 8,
                            decoration: const BoxDecoration(
                              shape: BoxShape.circle,
                              color: AppColors.primaryBlue,
                            ),
                          ),
                      ],
                    ),
                    SizedBox(height: isTablet ? 6 : 4),
                    Text(
                      notification.message,
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontWeight: FontWeight.w400,
                        fontSize: isTablet ? 16 : 13,
                        color: secondaryTextColor,
                        height: 1.4,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    SizedBox(height: isTablet ? 8 : 6),
                    Text(
                      _formatTimeAgo(notification.sentAt),
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontWeight: FontWeight.w400,
                        fontSize: isTablet ? 15 : 12,
                        color: secondaryTextColor.withValues(alpha: 0.7),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Notification Detail Bottom Sheet ────────────────────────────────────────

class _NotificationDetailSheet extends StatelessWidget {
  final NotificationModel notification;
  final VoidCallback onView;

  const _NotificationDetailSheet({
    required this.notification,
    required this.onView,
  });

  IconData _icon() {
    switch (notification.notificationType) {
      case 'push':
        return Icons.notifications_active_outlined;
      case 'email':
        return Icons.email_outlined;
      case 'sms':
        return Icons.message_outlined;
      case 'in_app':
      default:
        return Icons.info_outline_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardColor = isDark ? AppColors.darkSurface : Colors.white;
    final textColor = isDark ? AppColors.darkTextPrimary : const Color(0xFF000000);
    final secondaryTextColor = isDark ? AppColors.darkTextSecondary : AppColors.textSecondary;
    final isTablet = ResponsiveHelper.isTablet(context);

    return Container(
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.fromLTRB(
        isTablet ? 32 : 24,
        16,
        isTablet ? 32 : 24,
        MediaQuery.of(context).viewInsets.bottom + (isTablet ? 40 : 32),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Handle bar
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: isDark ? AppColors.darkDivider : AppColors.divider,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          SizedBox(height: isTablet ? 28 : 20),

          // Icon + title row
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: isTablet ? 56 : 48,
                height: isTablet ? 56 : 48,
                decoration: BoxDecoration(
                  color: AppColors.primaryBlue.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(isTablet ? 16 : 14),
                ),
                child: Icon(
                  _icon(),
                  size: isTablet ? 28 : 24,
                  color: AppColors.primaryBlue,
                ),
              ),
              SizedBox(width: isTablet ? 16 : 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      notification.title,
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontWeight: FontWeight.w600,
                        fontSize: isTablet ? 20 : 16,
                        color: textColor,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _formatTimeAgo(notification.sentAt),
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: isTablet ? 14 : 12,
                        color: secondaryTextColor.withValues(alpha: 0.7),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          SizedBox(height: isTablet ? 20 : 16),

          // Divider
          Divider(color: isDark ? AppColors.darkDivider : AppColors.divider, height: 1),
          SizedBox(height: isTablet ? 20 : 16),

          // Full message
          Text(
            notification.message,
            style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: isTablet ? 16 : 14,
              color: secondaryTextColor,
              height: 1.6,
            ),
          ),
          SizedBox(height: isTablet ? 32 : 24),

          // View button
          SizedBox(
            width: double.infinity,
            height: 50,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: AppColors.blueGradient,
                borderRadius: BorderRadius.circular(30),
              ),
              child: TextButton(
                onPressed: onView,
                style: TextButton.styleFrom(
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(30),
                  ),
                ),
                child: Text(
                  'View',
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: isTablet ? 17 : 15,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ),
          SizedBox(height: isTablet ? 12 : 10),

          // Close button
          SizedBox(
            width: double.infinity,
            height: 50,
            child: OutlinedButton(
              onPressed: () => Navigator.of(context).pop(),
              style: OutlinedButton.styleFrom(
                foregroundColor: secondaryTextColor,
                side: BorderSide(
                  color: isDark ? AppColors.darkDivider : AppColors.divider,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(30),
                ),
              ),
              child: Text(
                'Close',
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: isTablet ? 17 : 15,
                  fontWeight: FontWeight.w500,
                  color: secondaryTextColor,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
