import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:pgme/core_ios/constants/api_constants.dart';
import 'package:pgme/core_ios/models/live_session_model.dart';
import 'package:pgme/core_ios/providers/theme_provider.dart';
import 'package:pgme/core_ios/services/api_service.dart';
import 'package:pgme/core_ios/services/user_service.dart';
import 'package:pgme/core_ios/services/zoom_service.dart';
import 'package:pgme/core_ios/theme/app_theme.dart';
import 'package:pgme/core_ios/widgets/app_dialog.dart';
import 'package:pgme/core_ios/utils/web_store_launcher.dart';

// Enrollment status model
class EnrollmentStatus {
  final bool isEnrolled;
  final String? enrollmentId;
  final String? enrollmentStatus; // 'confirmed', 'waitlisted', 'cancelled'
  final String? enrollmentType; // 'paid', 'free', 'admin_override'
  final bool hasGuaranteedSeat;
  final bool hasPaid;
  final String? enrolledAt;
  final String? purchaseId;

  EnrollmentStatus({
    required this.isEnrolled,
    this.enrollmentId,
    this.enrollmentStatus,
    this.enrollmentType,
    this.hasGuaranteedSeat = false,
    this.hasPaid = false,
    this.enrolledAt,
    this.purchaseId,
  });

  factory EnrollmentStatus.fromJson(Map<String, dynamic> json) {
    return EnrollmentStatus(
      isEnrolled: json['is_enrolled'] ?? false,
      enrollmentId: json['enrollment_id'],
      enrollmentStatus: json['enrollment_status'],
      enrollmentType: json['enrollment_type'],
      hasGuaranteedSeat: json['has_guaranteed_seat'] ?? false,
      hasPaid: json['has_paid'] ?? false,
      enrolledAt: json['enrolled_at'],
      purchaseId: json['purchase_id'],
    );
  }
}

// Capacity info model
class CapacityInfo {
  final int? maxAttendees;
  final int currentAttendees;
  final int availableSpots;
  final bool isFull;
  final String capacityMode;
  final int guaranteedSeatsCount;

  CapacityInfo({
    this.maxAttendees,
    required this.currentAttendees,
    required this.availableSpots,
    required this.isFull,
    required this.capacityMode,
    required this.guaranteedSeatsCount,
  });

  factory CapacityInfo.fromJson(Map<String, dynamic> json) {
    return CapacityInfo(
      maxAttendees: json['max_attendees'],
      currentAttendees: json['current_attendees'] ?? 0,
      availableSpots: json['available_spots'] ?? 0,
      isFull: json['is_full'] ?? false,
      capacityMode: json['capacity_mode'] ?? 'unlimited',
      guaranteedSeatsCount: json['guaranteed_seats_count'] ?? 0,
    );
  }
}

class LiveSessionTestScreen extends StatefulWidget {
  const LiveSessionTestScreen({super.key});

  @override
  State<LiveSessionTestScreen> createState() => _LiveSessionTestScreenState();
}

class _LiveSessionTestScreenState extends State<LiveSessionTestScreen>
    with WidgetsBindingObserver {
  final ApiService _apiService = ApiService();
  final UserService _userService = UserService();
  final ZoomMeetingService _zoomService = ZoomMeetingService();

  List<LiveSessionModel> _allSessions = [];
  Map<String, EnrollmentStatus> _enrollmentStatuses = {};
  Map<String, CapacityInfo> _capacityInfo = {};
  bool _isLoading = true;
  bool _isJoining = false;
  bool _isProcessingPayment = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadSessions();
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
      _loadSessions();
    }
  }

  Future<void> _loadSessions() async {
    debugPrint('[TEST] Loading live sessions');
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      // Fetch all sessions
      final response = await _apiService.dio.get(
        ApiConstants.liveSessions,
        queryParameters: {'limit': 50},
      );

      if (response.statusCode == 200 && response.data['success'] == true) {
        final sessionsData = response.data['data']['sessions'] as List;
        debugPrint('[TEST] Fetched ${sessionsData.length} sessions');

        // Debug: Log first session's raw data to check fields
        if (sessionsData.isNotEmpty) {
          final firstSession = sessionsData.first;
          debugPrint('[TEST] First session raw data:');
          debugPrint('[TEST] - title: ${firstSession['title']}');
          debugPrint('[TEST] - is_free: ${firstSession['is_free']}');
          debugPrint('[TEST] - price: ${firstSession['price']}');
          debugPrint('[TEST] - enrollment_mode: ${firstSession['enrollment_mode']}');
        }

        final sessions = sessionsData
            .map((json) => LiveSessionModel.fromJson(json))
            .toList();

        // Debug: Log parsed first session
        if (sessions.isNotEmpty) {
          final firstParsed = sessions.first;
          debugPrint('[TEST] First session after parsing:');
          debugPrint('[TEST] - title: ${firstParsed.title}');
          debugPrint('[TEST] - isFree: ${firstParsed.isFree}');
          debugPrint('[TEST] - price: ${firstParsed.price}');
          debugPrint('[TEST] - enrollmentMode: ${firstParsed.enrollmentMode}');
        }

        setState(() {
          _allSessions = sessions;
          _isLoading = false;
        });

        // Load enrollment status and capacity for each session
        // Add delay to avoid rate limiting on free tier backend
        for (var i = 0; i < sessions.length; i++) {
          final session = sessions[i];

          // Add 200ms delay between requests to avoid 429 errors
          if (i > 0) {
            await Future.delayed(const Duration(milliseconds: 200));
          }

          _loadEnrollmentStatus(session.sessionId);

          if (session.capacityMode == 'limited') {
            await Future.delayed(const Duration(milliseconds: 100));
            _loadCapacityInfo(session.sessionId);
          }
        }
      } else {
        throw Exception('Failed to load sessions');
      }
    } catch (e) {
      debugPrint('[TEST] Error loading sessions: $e');
      setState(() {
        _error = e.toString().replaceAll('Exception: ', '');
        _isLoading = false;
      });
    }
  }

  Future<void> _loadEnrollmentStatus(String sessionId) async {
    debugPrint('[TEST] Checking enrollment status for: $sessionId');
    try {
      final response = await _apiService.dio.get(
        ApiConstants.sessionEnrollmentStatus(sessionId),
      );

      if (response.statusCode == 200 && response.data['success'] == true) {
        final status = EnrollmentStatus.fromJson(response.data['data']);
        setState(() {
          _enrollmentStatuses[sessionId] = status;
        });
        debugPrint('[TEST] Enrollment status: ${status.isEnrolled}');
      }
    } catch (e) {
      debugPrint('[TEST] Error checking enrollment: $e');
    }
  }

  Future<void> _loadCapacityInfo(String sessionId) async {
    try {
      final response = await _apiService.dio.get(
        ApiConstants.sessionCapacity(sessionId),
      );

      if (response.statusCode == 200 && response.data['success'] == true) {
        final capacity = CapacityInfo.fromJson(response.data['data']);
        setState(() {
          _capacityInfo[sessionId] = capacity;
        });
      }
    } catch (e) {
      debugPrint('[TEST] Error loading capacity: $e');
    }
  }

  Future<void> _enrollInSession(LiveSessionModel session) async {
    debugPrint('[TEST] Enrolling in session: ${session.title}');

    // Check enrollment mode
    final enrollmentMode = session.enrollmentMode ?? 'open';

    if (enrollmentMode == 'disabled') {
      if (mounted) {
        showAppDialog(context, message: 'This session is private and not open for enrollment');
      }
      return;
    }

    if (enrollmentMode == 'open') {
      // For open sessions, no enrollment needed - just join
      if (mounted) {
        showAppDialog(context, message: 'This is an open session - no enrollment needed, just join!', type: AppDialogType.info);
      }
      return;
    }

    // This method should only be called for FREE enrollment-required sessions
    // Paid sessions have their own "Buy Session" button
    if (!session.isFree) {
      debugPrint('[TEST] ERROR: _enrollInSession called for paid session - use Buy button instead');
      return;
    }

    // Free session - direct enrollment
    try {
      final response = await _apiService.dio.post(
        ApiConstants.sessionEnroll(session.sessionId),
      );

      if (response.statusCode == 200 && response.data['success'] == true) {
        debugPrint('[TEST] Enrolled successfully');

        // Reload enrollment status
        await _loadEnrollmentStatus(session.sessionId);

        if (mounted) {
          showAppDialog(context, message: 'Successfully enrolled in ${session.title}', type: AppDialogType.success);
        }
      }
    } catch (e) {
      debugPrint('[TEST] Error enrolling: $e');
      if (mounted) {
        final errorMsg = e.toString().replaceAll('Exception: ', '');
        showAppDialog(context, message: errorMsg);
      }
    }
  }

  Future<void> _initiatePayment(LiveSessionModel session) async {
    WebStoreLauncher.openProductPage(
      context,
      productType: 'sessions',
      productId: session.sessionId,
    );
  }

  void _showError(String message) {
    if (!mounted) return;
    showAppDialog(context, message: message);
  }

  void _showSuccess(String message) {
    if (!mounted) return;
    showAppDialog(context, message: message, type: AppDialogType.success);
  }

  void _showInfo(String message) {
    if (!mounted) return;
    showAppDialog(context, message: message, type: AppDialogType.info);
  }

  bool _canJoinSession(LiveSessionModel session) {
    final now = DateTime.now();
    final startTime = DateTime.parse(session.scheduledStartTime).toLocal();
    final endTime = DateTime.parse(session.scheduledEndTime).toLocal();

    // Can join 10 minutes before start time
    final joinTime = startTime.subtract(const Duration(minutes: 10));

    final canJoin = now.isAfter(joinTime) &&
                    now.isBefore(endTime) &&
                    (session.status == 'scheduled' || session.status == 'live');

    return canJoin;
  }

  bool _shouldShowEnrollButton(LiveSessionModel session) {
    final enrollmentMode = session.enrollmentMode ?? 'open';

    // Don't show enroll button for open or disabled sessions
    if (enrollmentMode == 'open' || enrollmentMode == 'disabled') {
      return false;
    }

    // Show enroll button if not enrolled
    final status = _enrollmentStatuses[session.sessionId];
    return status == null || !status.isEnrolled;
  }

  bool _canShowJoinButton(LiveSessionModel session) {
    final enrollmentMode = session.enrollmentMode ?? 'open';

    // For open sessions, always show join button (if timing is right)
    if (enrollmentMode == 'open') {
      return true;
    }

    // For enrollment-required sessions, only show if enrolled
    final status = _enrollmentStatuses[session.sessionId];
    return status != null && status.isEnrolled;
  }

  Future<void> _joinSession(LiveSessionModel session) async {
    if (_isJoining) return;

    debugPrint('');
    debugPrint('═══════════════════════════════════════════════════════════');
    debugPrint('[TEST] Attempting to join session: ${session.title}');
    debugPrint('[TEST] Session ID: ${session.sessionId}');
    debugPrint('[TEST] Enrollment Mode: ${session.enrollmentMode ?? 'open'}');
    debugPrint('[TEST] Is Free: ${session.isFree}');
    debugPrint('[TEST] Price: ₹${session.price}');

    final enrollmentStatus = _enrollmentStatuses[session.sessionId];
    debugPrint('[TEST] Enrollment Status: ${enrollmentStatus?.isEnrolled ?? false}');
    debugPrint('[TEST] Has Paid: ${enrollmentStatus?.hasPaid ?? false}');
    debugPrint('═══════════════════════════════════════════════════════════');

    // Check enrollment requirement
    final enrollmentMode = session.enrollmentMode ?? 'open';
    if (enrollmentMode == 'enrollment_required') {
      final status = _enrollmentStatuses[session.sessionId];
      if (status == null || !status.isEnrolled) {
        if (mounted) {
          showAppDialog(context, message: 'You must enroll in this session first');
        }
        return;
      }
    }

    // Check payment for paid sessions
    if (!session.isFree) {
      final status = _enrollmentStatuses[session.sessionId];
      if (status == null || !status.hasPaid) {
        if (mounted) {
          showAppDialog(context, message: 'Payment required for this session');
        }
        return;
      }
    }

    setState(() {
      _isJoining = true;
    });

    try {
      final user = await _userService.getProfile();
      debugPrint('[TEST] User: ${user.name}');

      // Join meeting using Zoom service
      await _zoomService.joinMeeting(
        sessionId: session.sessionId,
        displayName: user.name ?? 'Guest',
      );

      debugPrint('[TEST] Successfully joined session');

      if (mounted) {
        showAppDialog(context, message: 'Joined session successfully', type: AppDialogType.success);
      }
    } catch (e) {
      debugPrint('[TEST] Error joining session: $e');
      if (mounted) {
        showAppDialog(context, message: 'Failed to join: ${e.toString().replaceAll('Exception: ', '')}');
      }
    } finally {
      if (mounted) {
        setState(() {
          _isJoining = false;
        });
      }
    }
  }

  String _formatDateTime(String dateTimeStr) {
    try {
      final dateTime = DateTime.parse(dateTimeStr).toLocal();
      return DateFormat('MMM dd, yyyy - hh:mm a').format(dateTime);
    } catch (e) {
      return dateTimeStr;
    }
  }

  String _getSessionStatusText(LiveSessionModel session) {
    final now = DateTime.now();
    final startTime = DateTime.parse(session.scheduledStartTime).toLocal();
    final endTime = DateTime.parse(session.scheduledEndTime).toLocal();
    final joinTime = startTime.subtract(const Duration(minutes: 10));

    if (now.isBefore(joinTime)) {
      final difference = startTime.difference(now);
      if (difference.inHours > 24) {
        return 'Starts in ${difference.inDays} days';
      } else if (difference.inHours > 0) {
        return 'Starts in ${difference.inHours} hours';
      } else {
        return 'Starts in ${difference.inMinutes} mins';
      }
    } else if (now.isAfter(endTime)) {
      return 'Ended';
    } else if (session.status == 'live') {
      return 'LIVE NOW';
    } else {
      return 'Starting soon';
    }
  }

  Color _getStatusColor(LiveSessionModel session) {
    final now = DateTime.now();
    final startTime = DateTime.parse(session.scheduledStartTime).toLocal();
    final endTime = DateTime.parse(session.scheduledEndTime).toLocal();

    if (now.isAfter(endTime) || session.status == 'completed') {
      return Colors.grey;
    } else if (session.status == 'live') {
      return Colors.red;
    } else if (now.isBefore(startTime)) {
      return Colors.blue;
    } else {
      return Colors.orange;
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final isDark = themeProvider.isDarkMode;

    final backgroundColor = isDark ? AppColors.darkBackground : Colors.white;
    final cardColor = isDark ? AppColors.darkCardBackground : const Color(0xFFE4F4FF);
    final textColor = isDark ? AppColors.darkTextPrimary : const Color(0xFF000000);
    final secondaryTextColor = isDark ? AppColors.darkTextSecondary : const Color(0xFF888888);

    // Filter enrolled sessions
    final enrolledSessions = _allSessions.where((session) {
      final status = _enrollmentStatuses[session.sessionId];
      return status != null && status.isEnrolled;
    }).toList();

    final otherSessions = _allSessions.where((session) {
      final status = _enrollmentStatuses[session.sessionId];
      return status == null || !status.isEnrolled;
    }).toList();

    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: AppBar(
        title: const Text('Live Session Test'),
        backgroundColor: isDark ? AppColors.darkCardBackground : AppColors.primaryBlue,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadSessions,
          ),
        ],
      ),
      body: Stack(
        children: [
          _isLoading
              ? const Center(child: CircularProgressIndicator())
              : _error != null
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.error_outline, size: 48, color: secondaryTextColor),
                            const SizedBox(height: 16),
                            Text(
                              'Error loading sessions',
                              style: TextStyle(fontSize: 16, color: textColor),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              _error!,
                              style: TextStyle(fontSize: 14, color: secondaryTextColor),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 24),
                            ElevatedButton(
                              onPressed: _loadSessions,
                              child: const Text('Retry'),
                            ),
                          ],
                        ),
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: _loadSessions,
                      child: SingleChildScrollView(
                        physics: const AlwaysScrollableScrollPhysics(parent: ClampingScrollPhysics()),
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Info banner
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: isDark ? const Color(0xFF1A4D1A) : const Color(0xFFE8F5E9),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Row(
                                children: [
                                  Icon(Icons.info_outline, color: Colors.green[700], size: 20),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      'Test screen with full enrollment system integration',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: isDark ? Colors.green[200] : Colors.green[900],
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),

                            const SizedBox(height: 24),

                            // Enrolled Sessions Section
                            if (enrolledSessions.isNotEmpty) ...[
                              Text(
                            'Enrolled Sessions (${enrolledSessions.length})',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: textColor,
                            ),
                          ),
                          const SizedBox(height: 12),
                          ...enrolledSessions.map((session) => _buildSessionCard(
                            session: session,
                            cardColor: cardColor,
                            textColor: textColor,
                            secondaryTextColor: secondaryTextColor,
                          )),
                          const SizedBox(height: 24),
                        ],

                        // All Sessions Section
                        Text(
                          'All Available Sessions (${otherSessions.length})',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: textColor,
                          ),
                        ),
                        const SizedBox(height: 12),

                        if (otherSessions.isEmpty)
                          Center(
                            child: Padding(
                              padding: const EdgeInsets.all(32),
                              child: Text(
                                'No sessions available',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: secondaryTextColor,
                                ),
                              ),
                            ),
                          )
                        else
                          ...otherSessions.map((session) => _buildSessionCard(
                            session: session,
                            cardColor: cardColor,
                            textColor: textColor,
                            secondaryTextColor: secondaryTextColor,
                          )),
                      ],
                    ),
                  ),
                ),

          // Loading overlay when processing payment
          if (_isProcessingPayment)
            Container(
              color: Colors.black.withValues(alpha: 0.5),
              child: const Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircularProgressIndicator(
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                    SizedBox(height: 16),
                    Text(
                      'Processing payment...',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSessionCard({
    required LiveSessionModel session,
    required Color cardColor,
    required Color textColor,
    required Color secondaryTextColor,
  }) {
    final canJoin = _canJoinSession(session);
    final statusText = _getSessionStatusText(session);
    final statusColor = _getStatusColor(session);
    final enrollmentStatus = _enrollmentStatuses[session.sessionId];
    final capacityInfo = _capacityInfo[session.sessionId];
    final enrollmentMode = session.enrollmentMode ?? 'open';

    return Card(
      color: cardColor,
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Title and Status Badge
            Row(
              children: [
                Expanded(
                  child: Text(
                    session.title,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: textColor,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: statusColor),
                  ),
                  child: Text(
                    statusText,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: statusColor,
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 8),

            // Enrollment Mode Badge
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: enrollmentMode == 'open'
                        ? Colors.green.withValues(alpha: 0.2)
                        : Colors.orange.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    enrollmentMode == 'open' ? 'Open Session' : 'Enrollment Required',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: enrollmentMode == 'open' ? Colors.green[700] : Colors.orange[700],
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                // Enrollment Status Badge
                if (enrollmentStatus != null && enrollmentStatus.isEnrolled)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.green.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.check_circle, size: 12, color: Colors.green[700]),
                        const SizedBox(width: 4),
                        Text(
                          'Enrolled',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: Colors.green[700],
                          ),
                        ),
                      ],
                    ),
                  ),
                // Guaranteed Seat Badge
                if (enrollmentStatus != null && enrollmentStatus.hasGuaranteedSeat)
                  Container(
                    margin: const EdgeInsets.only(left: 4),
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.amber.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.star, size: 12, color: Colors.amber[700]),
                        const SizedBox(width: 4),
                        Text(
                          'Guaranteed Seat',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: Colors.amber[800],
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),

            const SizedBox(height: 8),

            // Faculty
            if (session.facultyName != null)
              Row(
                children: [
                  Icon(Icons.person_outline, size: 16, color: secondaryTextColor),
                  const SizedBox(width: 4),
                  Text(
                    session.facultyName!,
                    style: TextStyle(fontSize: 13, color: secondaryTextColor),
                  ),
                ],
              ),

            const SizedBox(height: 4),

            // Time
            Row(
              children: [
                Icon(Icons.access_time, size: 16, color: secondaryTextColor),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    _formatDateTime(session.scheduledStartTime),
                    style: TextStyle(fontSize: 13, color: secondaryTextColor),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 4),

            // Duration, Price, and Capacity
            Row(
              children: [
                Icon(Icons.timer_outlined, size: 16, color: secondaryTextColor),
                const SizedBox(width: 4),
                Text(
                  '${session.durationMinutes} mins',
                  style: TextStyle(fontSize: 13, color: secondaryTextColor),
                ),
                const SizedBox(width: 16),
                if (session.isFree) ...[
                  Icon(
                    Icons.check_circle,
                    size: 16,
                    color: secondaryTextColor,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'Free',
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.green,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
                // Capacity Info
                if (capacityInfo != null) ...[
                  const SizedBox(width: 16),
                  Icon(Icons.people_outline, size: 16, color: secondaryTextColor),
                  const SizedBox(width: 4),
                  Text(
                    '${capacityInfo.currentAttendees}/${capacityInfo.maxAttendees ?? '∞'}',
                    style: TextStyle(
                      fontSize: 13,
                      color: capacityInfo.isFull ? Colors.red : secondaryTextColor,
                      fontWeight: capacityInfo.isFull ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                ],
              ],
            ),

            const SizedBox(height: 12),

            // Action Buttons
            Row(
              children: [
                // Get Access Button (for paid sessions that are not enrolled)
                if (_shouldShowEnrollButton(session) && !session.isFree)
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () => _initiatePayment(session),
                      icon: Icon(WebStoreLauncher.shouldUseWebStore ? Icons.open_in_new : Icons.shopping_cart, size: 20),
                      label: const Text('Learn More'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.orange,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),

                // Enroll Button (for FREE enrollment-required sessions)
                if (_shouldShowEnrollButton(session) && session.isFree)
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _enrollInSession(session),
                      icon: const Icon(Icons.add_circle_outline, size: 20),
                      label: const Text('Access Free'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.green,
                        side: const BorderSide(color: Colors.green),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),

                // Join Button (for enrolled sessions or open sessions)
                if (_canShowJoinButton(session)) ...[
                  if (_shouldShowEnrollButton(session)) const SizedBox(width: 8),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: canJoin && !_isJoining
                          ? () => _joinSession(session)
                          : null,
                      icon: _isJoining
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.video_call, size: 20),
                      label: Text(_isJoining ? 'Joining...' : 'Join Session'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: canJoin ? Colors.green : Colors.grey,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                ],
              ],
            ),

            // Debug info
            const SizedBox(height: 8),
            Text(
              'ID: ${session.sessionId.substring(0, 8)}... | Mode: $enrollmentMode | ${session.isFree ? 'FREE' : 'PAID'}',
              style: TextStyle(
                fontSize: 10,
                color: secondaryTextColor.withValues(alpha: 0.6),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
