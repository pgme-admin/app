import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:pgme/core_android/models/live_session_model.dart';
import 'package:pgme/core_android/providers/theme_provider.dart';
import 'package:pgme/core_android/theme/app_theme.dart';
import 'package:pgme/core_android/utils/responsive_helper.dart';
import 'package:pgme/core/widgets/live_label.dart';

class LiveClassBanner extends StatefulWidget {
  final LiveSessionModel session;

  const LiveClassBanner({
    super.key,
    required this.session,
  });

  @override
  State<LiveClassBanner> createState() => _LiveClassBannerState();
}

class _LiveClassBannerState extends State<LiveClassBanner> {
  Timer? _countdownTimer;
  Duration _timeUntilStart = Duration.zero;
  bool _canJoin = false;

  @override
  void initState() {
    super.initState();
    _startCountdown();
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    super.dispose();
  }

  void _startCountdown() {
    _updateTimeUntilStart();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) {
        _updateTimeUntilStart();
      }
    });
  }

  void _updateTimeUntilStart() {
    final now = DateTime.now();
    final startTime = DateTime.parse(widget.session.scheduledStartTime).toLocal();
    setState(() {
      _timeUntilStart = startTime.difference(now);
      _canJoin = widget.session.status == 'live' ||
          (_timeUntilStart.inMinutes <= 10 && _timeUntilStart.inSeconds > 0);
    });
  }

  String _formatScheduledTime() {
    try {
      final startTime = DateTime.parse(widget.session.scheduledStartTime).toLocal();
      final now = DateTime.now();
      if (startTime.year == now.year &&
          startTime.month == now.month &&
          startTime.day == now.day) {
        final hour = startTime.hour;
        final minute = startTime.minute.toString().padLeft(2, '0');
        final period = hour >= 12 ? 'PM' : 'AM';
        final hour12 = hour > 12 ? hour - 12 : (hour == 0 ? 12 : hour);
        return 'Starts Today - $hour12:$minute $period';
      } else {
        final day = startTime.day;
        final month = _getMonthName(startTime.month);
        return 'Starts $month $day';
      }
    } catch (e) {
      return 'Upcoming';
    }
  }

  String _getMonthName(int month) {
    const months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    return months[month - 1];
  }

  void _joinSession() {
    context.push('/session/${widget.session.sessionId}');
  }

  void _viewDetails() {
    context.push('/session/${widget.session.sessionId}');
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final isDark = themeProvider.isDarkMode;
    final isTablet = ResponsiveHelper.isTablet(context);
    final titleSize = isTablet ? 20.0 : 14.0;
    final badgeFontSize = isTablet ? 14.0 : 10.0;
    final timeFontSize = isTablet ? 15.0 : 11.0;
    final buttonFontSize = isTablet ? 15.0 : 11.0;
    final buttonPaddingH = isTablet ? 24.0 : 14.0;
    final buttonPaddingV = isTablet ? 10.0 : 6.0;

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: isTablet ? 24 : 16),
      child: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: ResponsiveHelper.getBannerMaxWidth(context),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Banner image with status badge overlay — strict 16:9
              AspectRatio(
                aspectRatio: 16 / 9,
                child: Container(
                  width: double.infinity,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(isTablet ? 20 : 14),
                    gradient: LinearGradient(
                      begin: const Alignment(-0.85, 0),
                      end: const Alignment(0.85, 0),
                      colors: isDark
                          ? [const Color(0xFF0D2A5C), const Color(0xFF2D5A9E)]
                          : [const Color(0xFF1847A2), const Color(0xFF8EC6FF)],
                      stops: const [0.3469, 0.7087],
                    ),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(isTablet ? 20 : 14),
                    child: Stack(
                      children: [
                        Positioned.fill(
                          child: widget.session.thumbnailUrl != null
                              ? Image.network(
                                  widget.session.thumbnailUrl!,
                                  width: double.infinity,
                                  height: double.infinity,
                                  fit: BoxFit.cover,
                                  errorBuilder: (context, error, stackTrace) {
                                    return Image.asset(
                                      'assets/illustrations/home.png',
                                      width: double.infinity,
                                      height: double.infinity,
                                      fit: BoxFit.cover,
                                    );
                                  },
                                )
                              : Image.asset(
                                  'assets/illustrations/home.png',
                                  width: double.infinity,
                                  height: double.infinity,
                                  fit: BoxFit.cover,
                                  errorBuilder: (context, error, stackTrace) {
                                    return const SizedBox.expand();
                                  },
                                ),
                        ),
                        // Status badge in top-left
                        Positioned(
                          top: isTablet ? 14 : 8,
                          left: isTablet ? 14 : 8,
                          child: LiveLabel(
                            isLive: widget.session.status == 'live',
                            fontSize: badgeFontSize,
                            borderRadius: isTablet ? 8 : 6,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              // Text content + buttons below the image
              Padding(
                padding: EdgeInsets.only(
                  top: isTablet ? 10 : 7,
                  left: 2,
                  right: 2,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.session.title,
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontWeight: FontWeight.w600,
                        fontSize: titleSize,
                        color: isDark ? Colors.white : const Color(0xFF1A1A1A),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    SizedBox(height: isTablet ? 2 : 1),
                    Text(
                      widget.session.status == 'live'
                          ? 'Live Now'
                          : _formatScheduledTime(),
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontWeight: FontWeight.w400,
                        fontSize: timeFontSize,
                        color: isDark ? Colors.white70 : const Color(0xFF666666),
                      ),
                    ),
                    SizedBox(height: isTablet ? 10 : 6),
                    Row(
                      children: [
                        GestureDetector(
                          onTap: _canJoin ? _joinSession : null,
                          child: Container(
                            padding: EdgeInsets.symmetric(
                              horizontal: buttonPaddingH,
                              vertical: buttonPaddingV,
                            ),
                            decoration: BoxDecoration(
                              color: _canJoin
                                  ? (widget.session.status == 'live'
                                      ? Colors.green
                                      : const Color(0xFF2470E4))
                                  : Colors.grey,
                              borderRadius: BorderRadius.circular(isTablet ? 10 : 7),
                            ),
                            child: Text(
                              widget.session.status == 'live' ? 'Join Now' : 'Join Live',
                              style: TextStyle(
                                fontFamily: 'Poppins',
                                fontWeight: FontWeight.w500,
                                fontSize: buttonFontSize,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                        SizedBox(width: isTablet ? 12 : 8),
                        GestureDetector(
                          onTap: _viewDetails,
                          child: Container(
                            padding: EdgeInsets.symmetric(
                              horizontal: buttonPaddingH,
                              vertical: buttonPaddingV,
                            ),
                            decoration: BoxDecoration(
                              color: isDark
                                  ? Colors.white.withValues(alpha: 0.15)
                                  : const Color(0xFFF0F0F0),
                              borderRadius: BorderRadius.circular(isTablet ? 10 : 7),
                            ),
                            child: Text(
                              'View Details',
                              style: TextStyle(
                                fontFamily: 'Poppins',
                                fontWeight: FontWeight.w500,
                                fontSize: buttonFontSize,
                                color: isDark ? Colors.white : AppColors.primaryBlue,
                              ),
                            ),
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
      ),
    );
  }
}
