import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:pgme/core_ios/providers/theme_provider.dart';
import 'package:pgme/core_ios/theme/app_theme.dart';
import 'package:pgme/core_ios/models/live_session_model.dart';
import 'package:pgme/core_ios/services/dashboard_service.dart';
import 'package:pgme/core_ios/utils/responsive_helper.dart';
import 'package:pgme/core/widgets/live_label.dart';

class SeriesSessionsScreen extends StatefulWidget {
  final String seriesId;
  final String? seriesName;

  const SeriesSessionsScreen({
    super.key,
    required this.seriesId,
    this.seriesName,
  });

  @override
  State<SeriesSessionsScreen> createState() => _SeriesSessionsScreenState();
}

class _SeriesSessionsScreenState extends State<SeriesSessionsScreen> {
  final DashboardService _dashboardService = DashboardService();
  List<LiveSessionModel> _sessions = [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadSessions();
  }

  Future<void> _loadSessions() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final sessions = await _dashboardService.getLiveSessionsBySeries(widget.seriesId);

      if (mounted) {
        setState(() {
          _sessions = sessions;
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

  String _formatDateTime(String isoString) {
    try {
      final dateTime = DateTime.parse(isoString).toLocal();
      final months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
      final hour = dateTime.hour > 12 ? dateTime.hour - 12 : dateTime.hour;
      final period = dateTime.hour >= 12 ? 'PM' : 'AM';
      return '${dateTime.day} ${months[dateTime.month - 1]} ${dateTime.year}, ${hour == 0 ? 12 : hour}:${dateTime.minute.toString().padLeft(2, '0')} $period';
    } catch (e) {
      return isoString;
    }
  }

  String _getStatusLabel(String status) {
    switch (status) {
      case 'scheduled':
        return 'Upcoming';
      case 'live':
        return 'Live Now';
      case 'completed':
        return 'Completed';
      case 'cancelled':
        return 'Cancelled';
      default:
        return status;
    }
  }

  Color _getStatusColor(String status, bool isDark) {
    switch (status) {
      case 'scheduled':
        return isDark ? const Color(0xFF00BEFA) : const Color(0xFF2470E4);
      case 'live':
        return Colors.green;
      case 'completed':
        return isDark ? AppColors.darkTextSecondary : AppColors.textSecondary;
      case 'cancelled':
        return AppColors.error;
      default:
        return isDark ? AppColors.darkTextSecondary : AppColors.textSecondary;
    }
  }

  @override
  Widget build(BuildContext context) {
    final topPadding = MediaQuery.of(context).padding.top;
    final themeProvider = Provider.of<ThemeProvider>(context);
    final isDark = themeProvider.isDarkMode;
    final isTablet = ResponsiveHelper.isTablet(context);
    final hPadding = isTablet ? ResponsiveHelper.horizontalPadding(context) : 16.0;

    final backgroundColor = isDark ? AppColors.darkBackground : Colors.white;
    final textColor = isDark ? AppColors.darkTextPrimary : const Color(0xFF000000);
    final secondaryTextColor = isDark ? AppColors.darkTextSecondary : const Color(0xFF666666);
    final cardBgColor = isDark ? AppColors.darkCardBackground : Colors.white;
    final iconColor = isDark ? const Color(0xFF00BEFA) : const Color(0xFF2470E4);

    return Scaffold(
      backgroundColor: backgroundColor,
      body: Column(
        children: [
          // Header
          Padding(
            padding: EdgeInsets.only(top: topPadding + 12, left: hPadding, right: hPadding),
            child: Row(
              children: [
                GestureDetector(
                  onTap: () => context.pop(),
                  child: Icon(
                    Icons.arrow_back,
                    size: isTablet ? 30 : 24,
                    color: textColor,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Text(
                    'Live Sessions',
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontWeight: FontWeight.w500,
                      fontSize: isTablet ? 26 : 20,
                      color: textColor,
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 8),

          // Series name subtitle
          if (widget.seriesName != null)
            Padding(
              padding: EdgeInsets.symmetric(horizontal: hPadding),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  widget.seriesName!,
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontWeight: FontWeight.w400,
                    fontSize: isTablet ? 18 : 14,
                    color: secondaryTextColor,
                  ),
                ),
              ),
            ),

          const SizedBox(height: 16),

          // Content
          Expanded(
            child: _isLoading
                ? Center(
                    child: CircularProgressIndicator(color: iconColor),
                  )
                : _error != null
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.error_outline, size: 48, color: secondaryTextColor),
                            const SizedBox(height: 16),
                            Text(
                              'Failed to load sessions',
                              style: TextStyle(
                                fontFamily: 'Poppins',
                                fontSize: isTablet ? 20 : 16,
                                color: textColor,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              _error!.replaceAll('Exception: ', ''),
                              style: TextStyle(
                                fontFamily: 'Poppins',
                                fontSize: isTablet ? 15 : 12,
                                color: secondaryTextColor,
                              ),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 16),
                            ElevatedButton(
                              onPressed: _loadSessions,
                              style: ElevatedButton.styleFrom(backgroundColor: iconColor),
                              child: const Text('Retry'),
                            ),
                          ],
                        ),
                      )
                    : _sessions.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.videocam_off_outlined, size: 48, color: secondaryTextColor),
                                const SizedBox(height: 16),
                                Text(
                                  'No live sessions available',
                                  style: TextStyle(
                                    fontFamily: 'Poppins',
                                    fontSize: isTablet ? 20 : 16,
                                    color: textColor,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  'Check back later for upcoming sessions',
                                  style: TextStyle(
                                    fontFamily: 'Poppins',
                                    fontSize: isTablet ? 17 : 14,
                                    color: secondaryTextColor,
                                  ),
                                ),
                              ],
                            ),
                          )
                        : RefreshIndicator(
                            onRefresh: _loadSessions,
                            child: Center(
                              child: ConstrainedBox(
                                constraints: BoxConstraints(maxWidth: ResponsiveHelper.getMaxContentWidth(context)),
                                child: ListView.builder(
                                  physics: const AlwaysScrollableScrollPhysics(parent: ClampingScrollPhysics()),
                                  padding: EdgeInsets.symmetric(horizontal: hPadding),
                                  itemCount: _sessions.length,
                                  itemBuilder: (context, index) {
                                    final session = _sessions[index];
                                    return _buildSessionCard(
                                      session,
                                      isDark: isDark,
                                      textColor: textColor,
                                      secondaryTextColor: secondaryTextColor,
                                      cardBgColor: cardBgColor,
                                      iconColor: iconColor,
                                    );
                                  },
                                ),
                              ),
                            ),
                          ),
          ),
        ],
      ),
    );
  }

  Widget _buildSessionCard(
    LiveSessionModel session, {
    required bool isDark,
    required Color textColor,
    required Color secondaryTextColor,
    required Color cardBgColor,
    required Color iconColor,
  }) {
    final isTablet = ResponsiveHelper.isTablet(context);
    final statusColor = _getStatusColor(session.status, isDark);

    return GestureDetector(
      onTap: () {
        // Navigate to session details
        context.push('/session/${session.sessionId}');
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 16),
        decoration: BoxDecoration(
          color: cardBgColor,
          borderRadius: BorderRadius.circular(isTablet ? 22 : 16),
          boxShadow: isDark
              ? [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.3),
                    blurRadius: 8,
                    offset: const Offset(0, 4),
                  ),
                ]
              : [
                  const BoxShadow(
                    color: Color(0x1A000000),
                    blurRadius: 8,
                    offset: Offset(0, 2),
                  ),
                ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Thumbnail
            ClipRRect(
              borderRadius: BorderRadius.vertical(top: Radius.circular(isTablet ? 22 : 16)),
              child: Stack(
                children: [
                  AspectRatio(
                    aspectRatio: 16 / 9,
                    child: session.thumbnailUrl != null
                        ? Image.network(
                            session.thumbnailUrl!,
                            width: double.infinity,
                            height: double.infinity,
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) {
                              return Container(
                                color: isDark ? AppColors.darkSurface : const Color(0xFFE0E0E0),
                                child: Icon(
                                  Icons.videocam_outlined,
                                  size: 48,
                                  color: secondaryTextColor,
                                ),
                              );
                            },
                          )
                        : Container(
                            color: isDark ? AppColors.darkSurface : const Color(0xFFE0E0E0),
                            child: Icon(
                              Icons.videocam_outlined,
                              size: 48,
                              color: secondaryTextColor,
                            ),
                          ),
                  ),
                  // Status badge
                  Positioned(
                    top: 12,
                    left: 12,
                    child: (session.status == 'live' || session.status == 'scheduled')
                        ? LiveLabel(
                            isLive: session.status == 'live',
                            fontSize: isTablet ? 13 : 11,
                            borderRadius: 12,
                          )
                        : Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: statusColor,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              _getStatusLabel(session.status),
                              style: TextStyle(
                                fontFamily: 'Poppins',
                                fontSize: isTablet ? 14 : 11,
                                fontWeight: FontWeight.w500,
                                color: Colors.white,
                              ),
                            ),
                          ),
                  ),
                ],
              ),
            ),

            // Content
            Padding(
              padding: EdgeInsets.all(isTablet ? 22 : 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Title
                  Text(
                    session.title,
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontWeight: FontWeight.w600,
                      fontSize: isTablet ? 20 : 16,
                      color: textColor,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),

                  const SizedBox(height: 8),

                  // Date and time
                  Row(
                    children: [
                      Icon(
                        Icons.calendar_today_outlined,
                        size: isTablet ? 18 : 14,
                        color: iconColor,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        _formatDateTime(session.scheduledStartTime),
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: isTablet ? 15 : 12,
                          color: secondaryTextColor,
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 6),

                  // Duration
                  Row(
                    children: [
                      Icon(
                        Icons.access_time,
                        size: isTablet ? 18 : 14,
                        color: iconColor,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '${session.durationMinutes} mins',
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: isTablet ? 15 : 12,
                          color: secondaryTextColor,
                        ),
                      ),
                    ],
                  ),

                  if (session.facultyName != null) ...[
                    const SizedBox(height: 12),
                    // Faculty info
                    Row(
                      children: [
                        CircleAvatar(
                          radius: isTablet ? 20 : 14,
                          backgroundColor: isDark ? AppColors.darkSurface : const Color(0xFFE0E0E0),
                          backgroundImage: session.facultyPhotoUrl != null
                              ? NetworkImage(session.facultyPhotoUrl!)
                              : null,
                          child: session.facultyPhotoUrl == null
                              ? Icon(
                                  Icons.person,
                                  size: isTablet ? 20 : 14,
                                  color: secondaryTextColor,
                                )
                              : null,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            session.facultyName!,
                            style: TextStyle(
                              fontFamily: 'Poppins',
                              fontSize: isTablet ? 15 : 12,
                              fontWeight: FontWeight.w500,
                              color: textColor,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
