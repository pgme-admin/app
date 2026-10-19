import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:pgme/core_ios/models/live_session_model.dart';
import 'package:pgme/core_ios/models/session_access_model.dart';
import 'package:pgme/core_ios/providers/theme_provider.dart';
import 'package:pgme/core_ios/services/dashboard_service.dart';
import 'package:pgme/core_ios/services/session_access_service.dart';
import 'package:pgme/core_ios/theme/app_theme.dart';
import 'package:pgme/core_ios/services/zoom_service.dart';
import 'package:pgme/core_ios/utils/responsive_helper.dart';
import 'package:pgme/core_ios/utils/web_store_launcher.dart';
import 'package:pgme/core_ios/widgets/app_dialog.dart';
import 'package:pgme/core/widgets/live_label.dart';

class SessionDetailsScreen extends StatefulWidget {
  final String sessionId;

  const SessionDetailsScreen({
    super.key,
    required this.sessionId,
  });

  @override
  State<SessionDetailsScreen> createState() => _SessionDetailsScreenState();
}

class _SessionDetailsScreenState extends State<SessionDetailsScreen>
    with WidgetsBindingObserver {
  final DashboardService _dashboardService = DashboardService();
  final SessionAccessService _purchaseService = SessionAccessService();
  final ZoomMeetingService _zoomService = ZoomMeetingService();

  LiveSessionModel? _session;
  SessionAccessStatus? _accessStatus;
  bool _isLoading = true;
  bool _isCheckingAccess = false;
  bool _isPurchasing = false;
  bool _isJoiningZoom = false;
  String? _error;

  // Enrollment state
  Map<String, dynamic>? _enrollmentStatus;
  bool _isEnrolling = false;

  // Upcoming sessions
  List<LiveSessionModel> _upcomingSessions = [];

  // Countdown timer for join button
  Timer? _countdownTimer;
  bool _canJoinNow = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadSessionDetails();
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    // iOS only: refresh access/enrollment when returning from Safari purchase
    if (state == AppLifecycleState.resumed &&
        WebStoreLauncher.awaitingExternalPurchase) {
      WebStoreLauncher.clearAwaitingPurchase();
      _refreshAfterExternalPurchase();
    }
  }

  Future<void> _refreshAfterExternalPurchase() async {
    if (!mounted || _session == null) return;
    await Future.wait([
      _checkAccessStatus(),
      _checkEnrollmentStatus(),
    ]);
  }

  void _startCountdown() {
    _updateCanJoin();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) _updateCanJoin();
    });
  }

  void _updateCanJoin() {
    if (_session == null) return;
    final now = DateTime.now();
    try {
      final startTime = DateTime.parse(_session!.scheduledStartTime).toLocal();
      final diff = startTime.difference(now);
      setState(() {
        _canJoinNow = _session!.status == 'live' ||
            (diff.inMinutes <= 10 && !diff.isNegative);
      });
    } catch (_) {}
  }

  bool get _isEnrolled => _enrollmentStatus?['is_enrolled'] == true;
  bool get _hasAccess => _accessStatus?.hasAccess ?? _session?.isFree ?? true;

  Future<void> _loadSessionDetails() async {
    try {
      setState(() {
        _isLoading = true;
        _error = null;
      });

      final session = await _dashboardService.getSessionDetails(widget.sessionId);

      if (mounted) {
        setState(() {
          _session = session;
          _isLoading = false;
        });

        _startCountdown();

        // Load additional data in parallel
        _checkAccessStatus();
        _checkEnrollmentStatus();
        _loadUpcomingSessions();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString().replaceAll('Exception: ', '');
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _checkAccessStatus() async {
    if (_session == null) return;

    if (_session!.isFree) {
      setState(() {
        _accessStatus = SessionAccessStatus(
          hasAccess: true,
          isFree: true,
          price: 0,
        );
      });
      return;
    }

    try {
      setState(() => _isCheckingAccess = true);
      final accessStatus = await _purchaseService.checkSessionAccess(widget.sessionId);
      if (mounted) {
        setState(() {
          _accessStatus = accessStatus;
          _isCheckingAccess = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isCheckingAccess = false);
    }
  }

  Future<void> _checkEnrollmentStatus() async {
    if (_session == null) return;
    try {
      final status = await _purchaseService.checkEnrollmentStatus(widget.sessionId);
      if (mounted) setState(() => _enrollmentStatus = status);
    } catch (e) {
      debugPrint('Error checking enrollment: $e');
    }
  }

  Future<void> _loadUpcomingSessions() async {
    if (_session?.subjectId == null) return;
    try {
      final sessions = await _dashboardService.getLiveSessions(
        upcomingOnly: true,
        subjectId: _session!.subjectId,
        limit: 5,
      );
      final filtered = sessions.where((s) => s.sessionId != widget.sessionId).toList();
      if (mounted) setState(() => _upcomingSessions = filtered);
    } catch (e) {
      debugPrint('Error loading upcoming sessions: $e');
    }
  }

  Future<void> _enrollForFree() async {
    if (_session == null) return;
    setState(() => _isEnrolling = true);
    try {
      await _purchaseService.enrollInSession(widget.sessionId);
      if (mounted) {
        await Future.wait([
          _checkEnrollmentStatus(),
          _checkAccessStatus(),
        ]);
        showAppDialog(context, message: 'Successfully enrolled!', type: AppDialogType.success);
      }
    } catch (e) {
      if (mounted) _showError('Failed to enroll: $e');
    } finally {
      if (mounted) setState(() => _isEnrolling = false);
    }
  }

  Future<void> _initiatePayment() async {
    if (_session == null) return;

    WebStoreLauncher.openProductPage(
      context,
      productType: 'sessions',
      productId: widget.sessionId,
    );
  }

  void _showError(String message) {
    if (!mounted) return;
    showAppDialog(context, message: message.replaceAll('Exception: ', ''));
  }

  void _showInfo(String message) {
    if (!mounted) return;
    showAppDialog(context, message: message, type: AppDialogType.info);
  }

  Future<void> _launchMeeting() async {
    if (_session == null) return;

    // Re-check access right before joining in case user purchased
    // externally and state is stale.
    if (!_hasAccess && !_isEnrolled) {
      setState(() => _isJoiningZoom = true);
      await Future.wait([
        _checkAccessStatus(),
        _checkEnrollmentStatus(),
      ]);
      if (mounted) setState(() => _isJoiningZoom = false);
    }

    if (!_hasAccess && !_isEnrolled) {
      showAppDialog(context, message: 'Please purchase or enroll in this session to join');
      return;
    }

    try {
      await _purchaseService.joinSession(widget.sessionId);

      if (_session!.platform.toLowerCase() == 'zoom') {
        await _joinZoomInApp();
      } else {
        if (mounted) {
          _showZoomErrorModal(
            ZoomJoinException(
              type: ZoomErrorType.unknown,
              message: 'Only Zoom meetings are supported in-app. Please contact support.',
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        _showZoomErrorModal(
          ZoomJoinException(
            type: ZoomErrorType.unknown,
            message: 'Failed to join meeting: ${e.toString().replaceAll('Exception: ', '')}',
          ),
        );
      }
    }
  }

  Future<void> _joinZoomInApp({bool isRetry = false}) async {
    if (_isJoiningZoom) return;
    setState(() => _isJoiningZoom = true);

    // Safety: force-reset the joining flag after 45 seconds so the UI
    // never stays stuck on the spinner indefinitely.
    Timer? safetyTimer;
    safetyTimer = Timer(const Duration(seconds: 45), () {
      if (mounted && _isJoiningZoom) {
        setState(() => _isJoiningZoom = false);
        _showZoomErrorModal(
          ZoomJoinException(
            type: ZoomErrorType.timeout,
            message: 'Joining the meeting took too long. Please try again.',
          ),
        );
      }
    });

    try {
      await _zoomService.joinMeeting(
        sessionId: widget.sessionId,
        displayName: 'PGME Student',
      );
    } on ZoomJoinException catch (e) {
      // If first attempt fails, reset SDK and retry once
      if (!isRetry) {
        safetyTimer.cancel();
        debugPrint('Zoom join failed, resetting SDK and retrying...');
        await _zoomService.resetSDK();
        if (mounted) {
          setState(() => _isJoiningZoom = false);
          _joinZoomInApp(isRetry: true);
        }
        return;
      }
      if (mounted) {
        _showZoomErrorModal(e);
      }
    } catch (e) {
      // If first attempt fails with unknown error, reset and retry once
      if (!isRetry) {
        safetyTimer.cancel();
        debugPrint('Zoom join error, resetting SDK and retrying...');
        await _zoomService.resetSDK();
        if (mounted) {
          setState(() => _isJoiningZoom = false);
          _joinZoomInApp(isRetry: true);
        }
        return;
      }
      if (mounted) {
        _showZoomErrorModal(
          ZoomJoinException(
            type: ZoomErrorType.unknown,
            message: 'An unexpected error occurred while joining the meeting.',
            technicalDetails: e.toString(),
          ),
        );
      }
    } finally {
      safetyTimer.cancel();
      if (mounted) setState(() => _isJoiningZoom = false);
    }
  }

  void _showZoomErrorModal(ZoomJoinException error) {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (context) => _ZoomErrorDialog(
        error: error,
        onRetry: () {
          Navigator.of(context).pop();
          _joinZoomInApp();
        },
        onCancel: () {
          Navigator.of(context).pop();
        },
      ),
    );
  }

  String _formatPlatformName(String platform) {
    switch (platform.toLowerCase()) {
      case 'zoom':
        return 'Zoom';
      case 'teams':
        return 'Microsoft Teams';
      case 'google_meet':
        return 'Google Meet';
      default:
        return platform;
    }
  }

  String _getStatusText() {
    if (_session == null) return '';
    switch (_session!.status.toLowerCase()) {
      case 'live':
        return 'LIVE NOW';
      case 'scheduled':
        return 'UPCOMING';
      case 'completed':
        return 'COMPLETED';
      case 'cancelled':
        return 'CANCELLED';
      default:
        return _session!.status.toUpperCase();
    }
  }

  Color _getStatusColor(bool isDark) {
    if (_session == null) return Colors.grey;
    switch (_session!.status.toLowerCase()) {
      case 'live':
        return Colors.red;
      case 'scheduled':
        return isDark ? const Color(0xFF00BEFA) : const Color(0xFF2470E4);
      case 'completed':
        return Colors.green;
      case 'cancelled':
        return Colors.grey;
      default:
        return Colors.grey;
    }
  }

  String _formatPrice(num price) {
    return '';
  }

  String _formatSessionDate(String dateStr) {
    try {
      final dt = DateTime.parse(dateStr).toLocal();
      final now = DateTime.now();
      final hour = dt.hour > 12 ? dt.hour - 12 : (dt.hour == 0 ? 12 : dt.hour);
      final minute = dt.minute.toString().padLeft(2, '0');
      final period = dt.hour >= 12 ? 'PM' : 'AM';

      if (dt.year == now.year && dt.month == now.month && dt.day == now.day) {
        return 'Today at $hour:$minute $period';
      }

      final tomorrow = now.add(const Duration(days: 1));
      if (dt.year == tomorrow.year && dt.month == tomorrow.month && dt.day == tomorrow.day) {
        return 'Tomorrow at $hour:$minute $period';
      }

      const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
      return '${months[dt.month - 1]} ${dt.day} at $hour:$minute $period';
    } catch (e) {
      return 'Upcoming';
    }
  }

  @override
  Widget build(BuildContext context) {
    final topPadding = MediaQuery.of(context).padding.top;
    final themeProvider = Provider.of<ThemeProvider>(context);
    final isDark = themeProvider.isDarkMode;
    final backgroundColor = isDark ? AppColors.darkBackground : Colors.white;
    final textColor = isDark ? AppColors.darkTextPrimary : const Color(0xFF000000);
    final secondaryTextColor = isDark ? AppColors.darkTextSecondary : const Color(0xFF666666);
    final cardBgColor = isDark ? AppColors.darkCardBackground : const Color(0xFFE4F4FF);
    final surfaceColor = isDark ? AppColors.darkSurface : Colors.white;
    final iconColor = isDark ? const Color(0xFF00BEFA) : const Color(0xFF2470E4);
    final buttonColor = isDark ? const Color(0xFF0047CF) : const Color(0xFF0000D1);

    return Scaffold(
        backgroundColor: backgroundColor,
        body: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? _buildErrorState(textColor, iconColor)
                : _buildContent(
                    topPadding, isDark, backgroundColor, textColor,
                    secondaryTextColor, cardBgColor, surfaceColor, iconColor, buttonColor,
                  ),
    );
  }

  Widget _buildErrorState(Color textColor, Color iconColor) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.error_outline, size: 64, color: iconColor),
          const SizedBox(height: 16),
          Text(
            _error ?? 'Failed to load session',
            style: TextStyle(color: textColor, fontSize: 16),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          ElevatedButton(onPressed: _loadSessionDetails, child: const Text('Retry')),
        ],
      ),
    );
  }

  Widget _buildContent(
    double topPadding, bool isDark, Color backgroundColor, Color textColor,
    Color secondaryTextColor, Color cardBgColor, Color surfaceColor,
    Color iconColor, Color buttonColor,
  ) {
    final isTablet = ResponsiveHelper.isTablet(context);
    final hPadding = isTablet ? ResponsiveHelper.horizontalPadding(context) : 16.0;
    final isFree = _session?.isFree ?? true;
    final price = _session?.price ?? 0;

    return RefreshIndicator(
      onRefresh: _loadSessionDetails,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: ResponsiveHelper.getMaxContentWidth(context)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              SizedBox(height: topPadding),
              Padding(
                padding: const EdgeInsets.only(top: 16),
                child: Stack(
                  children: [
                    Positioned(
                      left: hPadding,
                      child: GestureDetector(
                        onTap: () {
                          if (context.canPop()) {
                            context.pop();
                          } else {
                            context.go('/home');
                          }
                        },
                        child: SizedBox(
                          width: isTablet ? 30 : 24, height: isTablet ? 30 : 24,
                          child: Icon(Icons.arrow_back, size: isTablet ? 30 : 24, color: textColor),
                        ),
                      ),
                    ),
                    Center(
                      child: Text(
                        'Session Details',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontFamily: 'Poppins', fontWeight: FontWeight.w500,
                          fontSize: isTablet ? 26 : 20, height: 1.0, letterSpacing: -0.5, color: textColor,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 17),

              // Session Info Box
              Padding(
                padding: EdgeInsets.symmetric(horizontal: hPadding),
                child: Container(
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: cardBgColor,
                    borderRadius: BorderRadius.circular(isTablet ? 28 : 20),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Column(
                    children: [
                      // Thumbnail
                      AspectRatio(
                        aspectRatio: 16 / 9,
                        child: _session?.thumbnailUrl != null
                            ? Image.network(
                                _session!.thumbnailUrl!,
                                width: double.infinity, height: double.infinity, fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => _buildThumbnailPlaceholder(surfaceColor, iconColor),
                              )
                            : _buildThumbnailPlaceholder(surfaceColor, iconColor),
                      ),
                      Padding(
                        padding: EdgeInsets.all(isTablet ? 24 : 16),
                        child: Column(
                          children: [
                            Opacity(
                              opacity: 0.5,
                              child: Text(
                                'LIVE SESSION',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontFamily: 'Poppins', fontWeight: FontWeight.w500,
                                  fontSize: isTablet ? 13 : 10, letterSpacing: 0.05, color: textColor,
                                ),
                              ),
                            ),
                            const SizedBox(height: 4),

                            Text(
                              _session?.title ?? 'Loading...',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontFamily: 'Poppins', fontWeight: FontWeight.w500,
                                fontSize: isTablet ? 26 : 20, height: 1.2, letterSpacing: -0.5, color: textColor,
                              ),
                              maxLines: 2, overflow: TextOverflow.ellipsis,
                            ),
                            if (_session?.facultyName != null) ...[
                              const SizedBox(height: 9),

                              // Faculty
                              Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Container(
                                    width: isTablet ? 32 : 24, height: isTablet ? 32 : 24,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: isDark ? AppColors.darkDivider : const Color(0xFFE0E0E0),
                                    ),
                                    child: ClipOval(
                                      child: _session?.facultyPhotoUrl != null
                                          ? Image.network(
                                              _session!.facultyPhotoUrl!,
                                              fit: BoxFit.cover,
                                              errorBuilder: (_, __, ___) => Icon(Icons.person, size: 16, color: secondaryTextColor),
                                            )
                                          : Icon(Icons.person, size: 16, color: secondaryTextColor),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    _session!.facultyName!,
                                    style: TextStyle(
                                      fontFamily: 'Poppins', fontWeight: FontWeight.w400,
                                      fontSize: isTablet ? 17 : 14, color: textColor,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                            const SizedBox(height: 16),

                            // Badges
                            Wrap(
                              spacing: 12, runSpacing: 8,
                              alignment: WrapAlignment.center,
                              children: [
                                if (_session?.status == 'live' || _session?.status == 'scheduled')
                                  LiveLabel(
                                    isLive: _session?.status == 'live',
                                    fontSize: isTablet ? 13 : 10,
                                    borderRadius: 41,
                                    padding: EdgeInsets.symmetric(
                                      horizontal: isTablet ? 16 : 12,
                                      vertical: 6,
                                    ),
                                  )
                                else
                                  _buildBadge(_getStatusText(), _getStatusColor(isDark)),
                                _buildBadge('${_session?.durationMinutes ?? 0} MINUTES', iconColor),
                                if (!isFree)
                                  _buildBadge(
                                    _hasAccess ? 'PURCHASED' : _formatPrice(price),
                                    _hasAccess ? Colors.green : Colors.orange,
                                    icon: _hasAccess ? Icons.check_circle : Icons.lock,
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

              const SizedBox(height: 24),

              // Pricing / Action Section
              _buildPricingSection(isDark, textColor, secondaryTextColor, surfaceColor, iconColor, buttonColor),

              const SizedBox(height: 24),

              // Description
              if (_session?.description != null && _session!.description!.isNotEmpty) ...[
                Padding(
                  padding: EdgeInsets.only(left: hPadding),
                  child: Text(
                    'About This Session',
                    style: TextStyle(
                      fontFamily: 'Poppins', fontWeight: FontWeight.w500,
                      fontSize: isTablet ? 26 : 20, height: 1.0, letterSpacing: -0.5, color: textColor,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: hPadding),
                  child: Container(
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: cardBgColor,
                      borderRadius: BorderRadius.circular(isTablet ? 30 : 24),
                    ),
                    child: Padding(
                      padding: EdgeInsets.all(isTablet ? 28 : 20),
                      child: Text(
                        _session!.description!,
                        style: TextStyle(
                          fontFamily: 'Poppins', fontWeight: FontWeight.w400,
                          fontSize: isTablet ? 17 : 14, height: 1.5, color: textColor,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
              ],

              // Meeting Instructions
              Padding(
                padding: EdgeInsets.only(left: hPadding),
                child: Text(
                  'Meeting Instructions',
                  style: TextStyle(
                    fontFamily: 'Poppins', fontWeight: FontWeight.w500,
                    fontSize: isTablet ? 26 : 20, height: 1.0, letterSpacing: -0.5, color: textColor,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: hPadding),
                child: Container(
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: cardBgColor,
                    borderRadius: BorderRadius.circular(isTablet ? 30 : 24),
                  ),
                  child: Padding(
                    padding: EdgeInsets.all(isTablet ? 28 : 20),
                    child: Column(
                      children: [
                        _buildInstructionItem('Ensure your Student ID is visible in your profile name.', textColor, iconColor),
                        const SizedBox(height: 16),
                        _buildInstructionItem('Mute your microphone upon entry to avoid echo.', textColor, iconColor),
                        const SizedBox(height: 16),
                        _buildInstructionItem('Q&A session will follow the primary content.', textColor, iconColor),
                        const SizedBox(height: 16),
                        _buildInstructionItem('Recording will be available 24 hours after the session.', textColor, iconColor),
                      ],
                    ),
                  ),
                ),
              ),

              // Upcoming Sessions
              if (_upcomingSessions.isNotEmpty) ...[
                const SizedBox(height: 24),
                Padding(
                  padding: EdgeInsets.only(left: hPadding),
                  child: Text(
                    'Upcoming Sessions',
                    style: TextStyle(
                      fontFamily: 'Poppins', fontWeight: FontWeight.w500,
                      fontSize: isTablet ? 26 : 20, height: 1.0, letterSpacing: -0.5, color: textColor,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                ...(_upcomingSessions.map((session) => Padding(
                  padding: EdgeInsets.symmetric(horizontal: hPadding, vertical: 4),
                  child: _buildUpcomingSessionCard(session, isDark, textColor, secondaryTextColor, cardBgColor, iconColor),
                ))),
              ],

              const SizedBox(height: 120),
            ],
          ),
        ),
      ),
      ),
    );
  }

  // ============================================================================
  // SESSION SCHEDULE SECTION
  // ============================================================================

  String _formatFullDateTime(String dateStr) {
    try {
      final dt = DateTime.parse(dateStr).toLocal();
      final now = DateTime.now();
      final hour = dt.hour > 12 ? dt.hour - 12 : (dt.hour == 0 ? 12 : dt.hour);
      final minute = dt.minute.toString().padLeft(2, '0');
      final period = dt.hour >= 12 ? 'PM' : 'AM';
      const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

      String dayLabel;
      if (dt.year == now.year && dt.month == now.month && dt.day == now.day) {
        dayLabel = 'Today';
      } else {
        final tomorrow = now.add(const Duration(days: 1));
        if (dt.year == tomorrow.year && dt.month == tomorrow.month && dt.day == tomorrow.day) {
          dayLabel = 'Tomorrow';
        } else {
          dayLabel = '${months[dt.month - 1]} ${dt.day}, ${dt.year}';
        }
      }
      return '$dayLabel at $hour:$minute $period';
    } catch (e) {
      return 'TBD';
    }
  }

  String _formatTimeOnly(String dateStr) {
    try {
      final dt = DateTime.parse(dateStr).toLocal();
      final hour = dt.hour > 12 ? dt.hour - 12 : (dt.hour == 0 ? 12 : dt.hour);
      final minute = dt.minute.toString().padLeft(2, '0');
      final period = dt.hour >= 12 ? 'PM' : 'AM';
      return '$hour:$minute $period';
    } catch (e) {
      return '';
    }
  }

  Widget _buildScheduleInfo(Color iconColor, Color textColor, Color secondaryTextColor) {
    if (_session == null) return const SizedBox.shrink();

    return Column(
      children: [
        _buildScheduleRow(
          Icons.calendar_today,
          'Date & Time',
          _formatFullDateTime(_session!.scheduledStartTime),
          iconColor, textColor, secondaryTextColor,
        ),
        const SizedBox(height: 12),
        _buildScheduleRow(
          Icons.schedule,
          'Duration',
          '${_session!.durationMinutes} minutes (${_formatTimeOnly(_session!.scheduledStartTime)} - ${_formatTimeOnly(_session!.scheduledEndTime)})',
          iconColor, textColor, secondaryTextColor,
        ),
        const SizedBox(height: 12),
        _buildScheduleRow(
          Icons.videocam,
          'Platform',
          _formatPlatformName(_session!.platform),
          iconColor, textColor, secondaryTextColor,
        ),
      ],
    );
  }

  Widget _buildScheduleRow(
    IconData icon, String label, String value,
    Color iconColor, Color textColor, Color secondaryTextColor,
  ) {
    final isTablet = ResponsiveHelper.isTablet(context);
    return Row(
      children: [
        Icon(icon, size: isTablet ? 26 : 20, color: iconColor),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontFamily: 'Poppins', fontWeight: FontWeight.w400,
                  fontSize: isTablet ? 15 : 12, color: secondaryTextColor,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: TextStyle(
                  fontFamily: 'Poppins', fontWeight: FontWeight.w500,
                  fontSize: isTablet ? 17 : 14, color: textColor,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ============================================================================
  // PRICING SECTION
  // ============================================================================

  Widget _buildPricingSection(
    bool isDark, Color textColor, Color secondaryTextColor,
    Color surfaceColor, Color iconColor, Color buttonColor,
  ) {
    final isTablet = ResponsiveHelper.isTablet(context);
    final hPadding = isTablet ? ResponsiveHelper.horizontalPadding(context) : 16.0;
    final isFree = _session?.isFree ?? true;
    final isUserEnrolled = _isEnrolled;
    final hasUserAccess = _hasAccess;

    String sectionTitle;
    if (isFree) {
      sectionTitle = isUserEnrolled ? 'Session Access' : 'Access';
    } else {
      sectionTitle = hasUserAccess ? 'Session Access' : 'Access';
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.only(left: hPadding),
          child: Text(
            sectionTitle,
            style: TextStyle(
              fontFamily: 'Poppins', fontWeight: FontWeight.w500,
              fontSize: isTablet ? 26 : 20, height: 1.0, letterSpacing: -0.5, color: textColor,
            ),
          ),
        ),
        const SizedBox(height: 12),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: hPadding),
          child: Container(
            width: double.infinity,
            decoration: BoxDecoration(
              color: surfaceColor,
              borderRadius: BorderRadius.circular(isTablet ? 30 : 24),
              boxShadow: isDark
                  ? [BoxShadow(color: Colors.black.withValues(alpha: 0.3), blurRadius: 10, offset: const Offset(0, 6))]
                  : const [
                      BoxShadow(color: Color(0x4D000000), blurRadius: 3, offset: Offset(0, 2)),
                      BoxShadow(color: Color(0x26000000), blurRadius: 10, spreadRadius: 4, offset: Offset(0, 6)),
                    ],
            ),
            child: Padding(
              padding: EdgeInsets.all(isTablet ? 32 : 24),
              child: _buildPricingContent(isDark, textColor, secondaryTextColor, iconColor, buttonColor),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPricingContent(
    bool isDark, Color textColor, Color secondaryTextColor,
    Color iconColor, Color buttonColor,
  ) {
    final isFree = _session?.isFree ?? true;
    final isUserEnrolled = _isEnrolled;
    final hasUserAccess = _hasAccess;

    // Case 1: Free + Enrolled OR Paid + Purchased
    if ((isFree && isUserEnrolled) || (!isFree && hasUserAccess)) {
      return _buildAccessGrantedContent(isDark, textColor, secondaryTextColor, iconColor, buttonColor);
    }

    // Case 2: Free + Not Enrolled
    if (isFree && !isUserEnrolled) {
      return _buildFreeEnrollContent(isDark, textColor, secondaryTextColor, iconColor);
    }

    // Case 3: Paid + Not Purchased
    return _buildPaidContent(isDark, textColor, secondaryTextColor, iconColor);
  }

  Widget _buildAccessGrantedContent(
    bool isDark, Color textColor, Color secondaryTextColor,
    Color iconColor, Color buttonColor,
  ) {
    final isTablet = ResponsiveHelper.isTablet(context);
    final bool isButtonEnabled = _canJoinNow;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.green.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.green.withValues(alpha: 0.3)),
          ),
          child: Row(
            children: [
              Icon(Icons.check_circle, color: Colors.green, size: isTablet ? 30 : 24),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _session?.isFree == true ? "You're Enrolled" : 'Access Granted',
                      style: TextStyle(
                        fontFamily: 'Poppins', fontWeight: FontWeight.w600,
                        fontSize: isTablet ? 17 : 14, color: textColor,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _canJoinNow
                          ? 'Session is ready to join!'
                          : 'You can join when the session starts',
                      style: TextStyle(
                        fontFamily: 'Poppins', fontWeight: FontWeight.w400,
                        fontSize: isTablet ? 15 : 12, color: secondaryTextColor,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        _buildScheduleInfo(iconColor, textColor, secondaryTextColor),
        const SizedBox(height: 24),

        GestureDetector(
          onTap: (isButtonEnabled && !_isJoiningZoom) ? _launchMeeting : null,
          child: Container(
            width: double.infinity,
            height: isTablet ? 60 : 48,
            decoration: BoxDecoration(
              color: _isJoiningZoom
                  ? Colors.grey
                  : (isButtonEnabled ? buttonColor : Colors.grey),
              borderRadius: BorderRadius.circular(isTablet ? 28 : 22),
            ),
            child: Center(
              child: _isJoiningZoom
                  ? SizedBox(
                      width: isTablet ? 30 : 24, height: isTablet ? 30 : 24,
                      child: const CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation<Color>(Colors.white)),
                    )
                  : Text(
                      _canJoinNow ? 'JOIN LIVE' : 'JOIN LIVE (Not Started Yet)',
                      style: TextStyle(
                        fontFamily: 'Poppins', fontWeight: FontWeight.w500,
                        fontSize: isTablet ? 20 : 16, height: 1.11, letterSpacing: 0.09, color: Colors.white,
                      ),
                    ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildFreeEnrollContent(
    bool isDark, Color textColor, Color secondaryTextColor, Color iconColor,
  ) {
    final isTablet = ResponsiveHelper.isTablet(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: iconColor.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: iconColor.withValues(alpha: 0.3)),
          ),
          child: Row(
            children: [
              Icon(Icons.card_giftcard, color: iconColor, size: isTablet ? 30 : 24),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'This session is free!',
                      style: TextStyle(
                        fontFamily: 'Poppins', fontWeight: FontWeight.w600,
                        fontSize: isTablet ? 17 : 14, color: textColor,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Register now to secure your spot',
                      style: TextStyle(
                        fontFamily: 'Poppins', fontWeight: FontWeight.w400,
                        fontSize: isTablet ? 15 : 12, color: secondaryTextColor,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        _buildScheduleInfo(iconColor, textColor, secondaryTextColor),
        const SizedBox(height: 24),

        GestureDetector(
          onTap: _isEnrolling ? null : _enrollForFree,
          child: Container(
            width: double.infinity,
            height: isTablet ? 60 : 48,
            decoration: BoxDecoration(
              color: _isEnrolling ? Colors.grey : Colors.green,
              borderRadius: BorderRadius.circular(isTablet ? 28 : 22),
            ),
            child: Center(
              child: _isEnrolling
                  ? SizedBox(
                      width: isTablet ? 30 : 24, height: isTablet ? 30 : 24,
                      child: const CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation<Color>(Colors.white)),
                    )
                  : Text(
                      'ACCESS FOR FREE',
                      style: TextStyle(
                        fontFamily: 'Poppins', fontWeight: FontWeight.w500,
                        fontSize: isTablet ? 20 : 16, height: 1.11, letterSpacing: 0.09, color: Colors.white,
                      ),
                    ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPaidContent(
    bool isDark, Color textColor, Color secondaryTextColor, Color iconColor,
  ) {
    final isTablet = ResponsiveHelper.isTablet(context);
    final price = _session?.price ?? 0;
    final compareAtPrice = _session?.compareAtPrice ?? _accessStatus?.compareAtPrice;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              _formatPrice(price),
              style: TextStyle(
                fontFamily: 'Poppins', fontWeight: FontWeight.w700,
                fontSize: isTablet ? 36 : 28, color: textColor,
              ),
            ),
            if (compareAtPrice != null && compareAtPrice > price) ...[
              const SizedBox(width: 12),
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  _formatPrice(compareAtPrice),
                  style: TextStyle(
                    fontFamily: 'Poppins', fontWeight: FontWeight.w400,
                    fontSize: isTablet ? 22 : 18, color: secondaryTextColor,
                    decoration: TextDecoration.lineThrough,
                    decorationColor: secondaryTextColor,
                  ),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 8),

        Text(
          'Access this live session',
          style: TextStyle(
            fontFamily: 'Poppins', fontWeight: FontWeight.w400,
            fontSize: isTablet ? 17 : 14, color: secondaryTextColor,
          ),
        ),
        const SizedBox(height: 16),

        _buildScheduleInfo(iconColor, textColor, secondaryTextColor),
        const SizedBox(height: 24),

        GestureDetector(
          onTap: (_isPurchasing || _isCheckingAccess) ? null : _initiatePayment,
          child: Container(
            width: double.infinity,
            height: isTablet ? 60 : 48,
            decoration: BoxDecoration(
              color: (_isPurchasing || _isCheckingAccess) ? Colors.grey : Colors.orange,
              borderRadius: BorderRadius.circular(isTablet ? 28 : 22),
            ),
            child: Center(
              child: (_isPurchasing || _isCheckingAccess)
                  ? SizedBox(
                      width: isTablet ? 30 : 24, height: isTablet ? 30 : 24,
                      child: const CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation<Color>(Colors.white)),
                    )
                  : Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          WebStoreLauncher.shouldUseWebStore ? Icons.open_in_new : Icons.shopping_cart,
                          color: Colors.white, size: 20,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'LEARN MORE',
                          style: TextStyle(
                            fontFamily: 'Poppins', fontWeight: FontWeight.w500,
                            fontSize: isTablet ? 20 : 16, height: 1.11, letterSpacing: 0.09, color: Colors.white,
                          ),
                        ),
                      ],
                    ),
            ),
          ),
        ),
      ],
    );
  }

  // ============================================================================
  // UPCOMING SESSIONS
  // ============================================================================

  Widget _buildUpcomingSessionCard(
    LiveSessionModel session, bool isDark, Color textColor,
    Color secondaryTextColor, Color cardBgColor, Color iconColor,
  ) {
    final isTablet = ResponsiveHelper.isTablet(context);
    return GestureDetector(
      onTap: () => context.push('/session/${session.sessionId}'),
      child: Container(
        padding: EdgeInsets.all(isTablet ? 18 : 12),
        decoration: BoxDecoration(
          color: cardBgColor,
          borderRadius: BorderRadius.circular(isTablet ? 22 : 16),
        ),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(isTablet ? 16 : 12),
              child: session.thumbnailUrl != null
                  ? Image.network(
                      session.thumbnailUrl!,
                      width: isTablet ? 80 : 60, height: isTablet ? 45 : 34, fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => _buildSmallPlaceholder(iconColor),
                    )
                  : _buildSmallPlaceholder(iconColor),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    session.title,
                    style: TextStyle(
                      fontFamily: 'Poppins', fontWeight: FontWeight.w500,
                      fontSize: isTablet ? 17 : 14, color: textColor,
                    ),
                    maxLines: 1, overflow: TextOverflow.ellipsis,
                  ),
                  if (session.facultyName != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      session.facultyName!,
                      style: TextStyle(
                        fontFamily: 'Poppins', fontWeight: FontWeight.w400,
                        fontSize: isTablet ? 15 : 12, color: secondaryTextColor,
                      ),
                    ),
                  ],
                  const SizedBox(height: 2),
                  Text(
                    _formatSessionDate(session.scheduledStartTime),
                    style: TextStyle(
                      fontFamily: 'Poppins', fontWeight: FontWeight.w400,
                      fontSize: isTablet ? 14 : 11, color: iconColor,
                    ),
                  ),
                ],
              ),
            ),
            if (session.isFree)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.green.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text(
                  'FREE',
                  style: TextStyle(
                    fontFamily: 'Poppins', fontWeight: FontWeight.w500,
                    fontSize: 10, color: Colors.green,
                  ),
                ),
              )
            else
              Text(
                _formatPrice(session.price),
                style: TextStyle(
                  fontFamily: 'Poppins', fontWeight: FontWeight.w600,
                  fontSize: 13, color: textColor,
                ),
              ),
          ],
        ),
      ),
    );
  }

  // ============================================================================
  // SHARED WIDGETS
  // ============================================================================

  Widget _buildBadge(String text, Color color, {IconData? icon}) {
    final isTablet = ResponsiveHelper.isTablet(context);
    return Container(
      padding: EdgeInsets.symmetric(horizontal: isTablet ? 16 : 12, vertical: 6),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(41),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null)
            Icon(icon, size: 12, color: Colors.white)
          else
            Container(
              width: isTablet ? 10 : 8, height: isTablet ? 10 : 8,
              decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.white),
            ),
          const SizedBox(width: 6),
          Text(
            text,
            style: TextStyle(
              fontFamily: 'Poppins', fontWeight: FontWeight.w500,
              fontSize: isTablet ? 13 : 10, color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildThumbnailPlaceholder(Color surfaceColor, Color iconColor) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: surfaceColor,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Icon(Icons.play_circle_outline, size: 50, color: iconColor),
    );
  }

  Widget _buildSmallPlaceholder(Color iconColor) {
    final isTablet = ResponsiveHelper.isTablet(context);
    return Container(
      width: isTablet ? 80 : 60, height: isTablet ? 45 : 34,
      decoration: BoxDecoration(
        color: iconColor.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(isTablet ? 16 : 12),
      ),
      child: Icon(Icons.play_circle_outline, size: 28, color: iconColor),
    );
  }

  Widget _buildInstructionItem(String text, Color textColor, Color iconColor) {
    final isTablet = ResponsiveHelper.isTablet(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.check_circle_outline, size: isTablet ? 26 : 20, color: iconColor),
        const SizedBox(width: 12),
        Expanded(
          child: Opacity(
            opacity: 0.7,
            child: Text(
              text,
              style: TextStyle(
                fontFamily: 'Poppins', fontWeight: FontWeight.w500,
                fontSize: isTablet ? 17 : 14, height: 1.43, letterSpacing: -0.5, color: textColor,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Custom error dialog for Zoom SDK failures
class _ZoomErrorDialog extends StatelessWidget {
  final ZoomJoinException error;
  final VoidCallback onRetry;
  final VoidCallback onCancel;

  const _ZoomErrorDialog({
    required this.error,
    required this.onRetry,
    required this.onCancel,
  });

  IconData _getErrorIcon() {
    switch (error.type) {
      case ZoomErrorType.hostNotJoined:
        return Icons.hourglass_empty;
      case ZoomErrorType.networkError:
        return Icons.wifi_off;
      case ZoomErrorType.timeout:
        return Icons.access_time;
      case ZoomErrorType.meetingEnded:
        return Icons.event_busy;
      default:
        return Icons.error_outline;
    }
  }

  Color _getErrorColor() {
    switch (error.type) {
      case ZoomErrorType.hostNotJoined:
        return Colors.orange;
      case ZoomErrorType.networkError:
        return Colors.red;
      case ZoomErrorType.timeout:
        return Colors.amber;
      case ZoomErrorType.meetingEnded:
        return Colors.grey;
      default:
        return AppColors.error;
    }
  }

  String _getErrorTitle() {
    switch (error.type) {
      case ZoomErrorType.hostNotJoined:
        return 'Waiting for Host';
      case ZoomErrorType.networkError:
        return 'Connection Error';
      case ZoomErrorType.timeout:
        return 'Connection Timeout';
      case ZoomErrorType.meetingEnded:
        return 'Meeting Ended';
      case ZoomErrorType.authenticationFailed:
        return 'Authentication Failed';
      case ZoomErrorType.joinFailed:
        return 'Failed to Join';
      default:
        return 'Unable to Join Meeting';
    }
  }

  bool _shouldShowRetry() {
    // Don't show retry for meeting ended
    return error.type != ZoomErrorType.meetingEnded;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isTablet = ResponsiveHelper.isTablet(context);
    final errorColor = _getErrorColor();

    return Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
      ),
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: isDark ? AppColors.darkSurface : Colors.white,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Error Icon
            Container(
              width: isTablet ? 100 : 80,
              height: isTablet ? 100 : 80,
              decoration: BoxDecoration(
                color: errorColor.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                _getErrorIcon(),
                size: isTablet ? 50 : 40,
                color: errorColor,
              ),
            ),
            const SizedBox(height: 20),

            // Error Title
            Text(
              _getErrorTitle(),
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: isTablet ? 26 : 20,
                fontWeight: FontWeight.w600,
                color: isDark ? Colors.white : AppColors.darkTextPrimary,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),

            // Error Message
            Text(
              error.message,
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: isTablet ? 17 : 14,
                color: isDark ? Colors.white70 : Colors.black54,
                height: 1.5,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),

            // Action Buttons
            Row(
              children: [
                // Cancel Button
                Expanded(
                  child: OutlinedButton(
                    onPressed: onCancel,
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      side: BorderSide(
                        color: isDark ? Colors.white30 : Colors.black26,
                      ),
                    ),
                    child: Text(
                      'Cancel',
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: isDark ? Colors.white70 : Colors.black87,
                      ),
                    ),
                  ),
                ),

                if (_shouldShowRetry()) ...[
                  const SizedBox(width: 12),

                  // Retry Button
                  Expanded(
                    child: ElevatedButton(
                      onPressed: onRetry,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: errorColor,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        elevation: 0,
                      ),
                      child: const Text(
                        'Retry',
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}
