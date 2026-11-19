import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:pgme/core/models/address_model.dart';
import 'package:pgme/core/models/gateway_models.dart';
import 'package:pgme/core/models/workshop_model.dart';
import 'package:pgme/core/providers/theme_provider.dart';
import 'package:pgme/core/services/user_service.dart';
import 'package:pgme/core/services/workshop_service.dart';
import 'package:pgme/core/services/zoom_service.dart';
import 'package:pgme/core/theme/app_theme.dart';
import 'package:pgme/core/utils/responsive_helper.dart';
import 'package:pgme/core/utils/web_store_launcher.dart';
import 'package:pgme/core/widgets/address_bottom_sheet.dart';
import 'package:pgme/core/widgets/app_dialog.dart';
import 'package:pgme/core/widgets/gateway_widget.dart';
import 'package:pgme/core/widgets/live_label.dart';

/// Workshop detail — agenda, per-day join, attendance and certificate.
///
/// Deliberately mirrors SessionDetailsScreen's structure and visual language so
/// the two feel like one product: same header, same card radii and colours,
/// same access-panel states, and the same in-app Zoom join path.
class WorkshopDetailsScreen extends StatefulWidget {
  final String workshopId;

  const WorkshopDetailsScreen({super.key, required this.workshopId});

  @override
  State<WorkshopDetailsScreen> createState() => _WorkshopDetailsScreenState();
}

class _WorkshopDetailsScreenState extends State<WorkshopDetailsScreen>
    with WidgetsBindingObserver {
  final WorkshopService _workshopService = WorkshopService();
  final ZoomMeetingService _zoomService = ZoomMeetingService();

  WorkshopModel? _workshop;
  WorkshopCapacityModel? _capacity;
  WorkshopCertificateStatusModel? _certificateStatus;
  List<WorkshopRecordingModel> _recordings = [];

  bool _isLoading = true;
  String? _error;
  bool _isEnrolling = false;
  bool _isPurchasing = false;
  bool _isClaimingCertificate = false;
  String? _joiningSessionId;

  /// Re-renders the per-day countdowns without refetching.
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    if (Platform.isIOS) WidgetsBinding.instance.addObserver(this);
    _load();
    _ticker = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    if (Platform.isIOS) WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    // iOS buys through the web store, so refresh on return from Safari.
    if (state == AppLifecycleState.resumed &&
        WebStoreLauncher.awaitingExternalPurchase) {
      WebStoreLauncher.clearAwaitingPurchase();
      _load();
    }
  }

  // ==========================================================================
  // Data
  // ==========================================================================

  Future<void> _load() async {
    try {
      if (mounted) setState(() => _error = null);
      final workshop = await _workshopService.getWorkshopDetails(widget.workshopId);
      if (!mounted) return;
      setState(() {
        _workshop = workshop;
        _isLoading = false;
      });

      // Secondary data — a failure here must not blank the page.
      _workshopService.getCapacity(widget.workshopId).then((c) {
        if (mounted) setState(() => _capacity = c);
      });
      _workshopService.getRecordings(widget.workshopId).then((r) {
        if (mounted) setState(() => _recordings = r);
      });
      if (workshop.certificateEnabled && workshop.isEnrolled) {
        _workshopService.getCertificateStatus(widget.workshopId).then((s) {
          if (mounted) setState(() => _certificateStatus = s);
        });
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

  // ==========================================================================
  // Actions
  // ==========================================================================

  Future<void> _enrollForFree() async {
    setState(() => _isEnrolling = true);
    try {
      final result = await _workshopService.enroll(widget.workshopId);
      await _load();
      if (mounted) {
        final waitlisted = result['waitlisted'] == true;
        showAppDialog(
          context,
          message: result['message']?.toString() ??
              (waitlisted
                  ? "You're on the waitlist. We'll notify you if a seat opens up."
                  : 'Successfully registered!'),
          type: waitlisted ? AppDialogType.info : AppDialogType.success,
        );
      }
    } catch (e) {
      if (mounted) {
        showAppDialog(context,
            message: e.toString().replaceAll('Exception: ', ''));
      }
    } finally {
      if (mounted) setState(() => _isEnrolling = false);
    }
  }

  Future<void> _cancelRegistration() async {
    setState(() => _isEnrolling = true);
    try {
      await _workshopService.cancelEnrollment(widget.workshopId);
      await _load();
      if (mounted) {
        showAppDialog(context,
            message: 'Registration cancelled', type: AppDialogType.info);
      }
    } catch (e) {
      if (mounted) {
        showAppDialog(context,
            message: e.toString().replaceAll('Exception: ', ''));
      }
    } finally {
      if (mounted) setState(() => _isEnrolling = false);
    }
  }

  Future<void> _initiatePayment() async {
    final workshop = _workshop;
    if (workshop == null) return;

    // iOS: buy on the web store to stay clear of the IAP requirement.
    if (WebStoreLauncher.shouldUseWebStore) {
      WebStoreLauncher.openProductPage(
        context,
        productType: 'workshops',
        productId: widget.workshopId,
      );
      return;
    }

    Address? savedAddress;
    try {
      final user = await UserService().getProfile();
      if (user.billingAddress != null && user.billingAddress!.isNotEmpty) {
        savedAddress = Address.fromJson(user.billingAddress!);
      }
    } catch (_) {
      // No saved address is fine — the sheet collects one.
    }

    if (!mounted) return;

    final addressResult = await showAddressSheet(
      context,
      initialAddress: savedAddress,
      couponPurchaseType: 'workshop',
      couponProductId: widget.workshopId,
    );
    if (addressResult == null || !mounted) return;

    final billingAddress = addressResult['billing'] as Address;
    final couponCode = addressResult['coupon_code'] as String?;
    final termsAccepted = addressResult['terms_accepted'] as bool?;

    setState(() => _isPurchasing = true);
    try {
      final paymentSession = await _workshopService.initSession(
        widget.workshopId,
        billingAddress: billingAddress.toJson(),
        couponCode: couponCode,
        termsAccepted: termsAccepted,
      );

      if (!mounted) return;

      final result =
          await Navigator.of(context, rootNavigator: true).push<GatewayResponse>(
        MaterialPageRoute(
          builder: (ctx) => GatewayWidget(
            paymentSession: paymentSession,
            onPaymentComplete: (response) => Navigator.pop(ctx, response),
            onCancel: () => Navigator.pop(ctx),
          ),
          fullscreenDialog: true,
        ),
      );

      if (result == null || !mounted) return;

      if (result.isSuccess) {
        final verification = await _workshopService.confirmSession(
          workshopId: widget.workshopId,
          paymentSessionId: result.paymentSessionId!,
          paymentId: result.paymentId!,
          signature: result.signature,
        );
        await _load();
        if (mounted) {
          showAppDialog(
            context,
            message: verification.success
                ? "Payment successful! You're registered for every day."
                : 'Verification failed. Please contact support.',
            type: verification.success
                ? AppDialogType.success
                : AppDialogType.error,
          );
        }
      } else if (result.isFailed) {
        showAppDialog(context,
            message: 'Payment failed: ${result.errorMessage ?? "Unknown error"}');
      } else if (result.isCancelled) {
        showAppDialog(context,
            message: 'Payment cancelled', type: AppDialogType.info);
      }
    } catch (e) {
      if (mounted) {
        showAppDialog(context,
            message: e.toString().replaceAll('Exception: ', ''));
      }
    } finally {
      if (mounted) setState(() => _isPurchasing = false);
    }
  }

  /// Join one day. Registers attendance server-side, then opens the Zoom SDK
  /// in-app — the same path a standalone live session uses, because a day *is*
  /// a live session.
  Future<void> _joinDay(WorkshopDayModel day) async {
    if (_joiningSessionId != null) return;
    setState(() => _joiningSessionId = day.sessionId);

    try {
      await _workshopService.joinDay(day.sessionId);

      if ((_workshop?.platform ?? 'zoom').toLowerCase() != 'zoom') {
        if (mounted) {
          showAppDialog(context,
              message:
                  'Only Zoom meetings are supported in-app. Please contact support.');
        }
        return;
      }

      await _zoomService.joinMeeting(
        sessionId: day.sessionId,
        displayName: 'PGME Student',
      );

      // Reflect the new attendance mark.
      if (mounted) await _load();
    } on ZoomJoinException catch (e) {
      if (mounted) showAppDialog(context, message: e.message);
    } catch (e) {
      if (mounted) {
        showAppDialog(context,
            message: e.toString().replaceAll('Exception: ', ''));
      }
    } finally {
      if (mounted) setState(() => _joiningSessionId = null);
    }
  }

  Future<void> _claimCertificate() async {
    setState(() => _isClaimingCertificate = true);
    try {
      final result = await _workshopService.claimCertificate(widget.workshopId);
      final url = result['url'] as String?;
      if (url != null) {
        final uri = Uri.parse(url);
        if (await canLaunchUrl(uri)) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
        }
      }
      final status =
          await _workshopService.getCertificateStatus(widget.workshopId);
      if (mounted) setState(() => _certificateStatus = status);
    } catch (e) {
      if (mounted) {
        showAppDialog(context,
            message: e.toString().replaceAll('Exception: ', ''));
      }
    } finally {
      if (mounted) setState(() => _isClaimingCertificate = false);
    }
  }

  Future<void> _openRecording(WorkshopRecordingModel rec) async {
    final url = rec.videoUrl;
    if (url == null) return;
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  // ==========================================================================
  // Formatting
  // ==========================================================================

  static const _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  String _formatTime(String iso) {
    try {
      final dt = DateTime.parse(iso).toLocal();
      final hour = dt.hour > 12 ? dt.hour - 12 : (dt.hour == 0 ? 12 : dt.hour);
      final minute = dt.minute.toString().padLeft(2, '0');
      return '$hour:$minute ${dt.hour >= 12 ? 'PM' : 'AM'}';
    } catch (_) {
      return '';
    }
  }

  String _formatDayHeading(String iso) {
    try {
      final dt = DateTime.parse(iso).toLocal();
      const week = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
      return '${week[dt.weekday - 1]}, ${_months[dt.month - 1]} ${dt.day}';
    } catch (_) {
      return '';
    }
  }

  String _dateRange() {
    final w = _workshop;
    if (w == null) return '';
    try {
      final s = DateTime.parse(w.startDate).toLocal();
      final e = DateTime.parse(w.endDate).toLocal();
      if (s.year == e.year && s.month == e.month && s.day == e.day) {
        return '${_months[s.month - 1]} ${s.day}, ${s.year}';
      }
      if (s.month == e.month && s.year == e.year) {
        return '${s.day}–${e.day} ${_months[s.month - 1]} ${s.year}';
      }
      return '${_months[s.month - 1]} ${s.day} – ${_months[e.month - 1]} ${e.day}, ${e.year}';
    } catch (_) {
      return '';
    }
  }

  /// "2d 4h" / "12m" until [iso]; null once it has passed.
  String? _countdown(String? iso) {
    if (iso == null) return null;
    try {
      final diff = DateTime.parse(iso).toLocal().difference(DateTime.now());
      if (diff.isNegative) return null;
      final d = diff.inDays;
      final h = diff.inHours % 24;
      final m = diff.inMinutes % 60;
      if (d > 0) return '${d}d ${h}h';
      if (h > 0) return '${h}h ${m}m';
      return '${m}m';
    } catch (_) {
      return null;
    }
  }

  String _formatPrice(num price) {
    if (Platform.isIOS) return '';
    return '₹${price.toInt().toString().replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]},')}';
  }

  // ==========================================================================
  // Build
  // ==========================================================================

  @override
  Widget build(BuildContext context) {
    final topPadding = MediaQuery.of(context).padding.top;
    final isDark = Provider.of<ThemeProvider>(context).isDarkMode;

    final backgroundColor = isDark ? AppColors.darkBackground : AppColors.background;
    final textColor = isDark ? AppColors.darkTextPrimary : AppColors.textPrimary;
    final secondaryTextColor =
        isDark ? AppColors.darkTextSecondary : AppColors.textSecondary;
    final cardBgColor =
        isDark ? AppColors.darkCardBackground : const Color(0xFFE4F4FF);
    final surfaceColor = isDark ? AppColors.darkSurface : Colors.white;
    final iconColor = isDark ? AppColors.secondaryBlue : AppColors.primaryBlue;
    final buttonColor = isDark ? const Color(0xFF0047CF) : AppColors.primaryBlue;

    return Scaffold(
      backgroundColor: backgroundColor,
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _buildErrorState(textColor, iconColor)
              : _buildContent(topPadding, isDark, textColor, secondaryTextColor,
                  cardBgColor, surfaceColor, iconColor, buttonColor),
    );
  }

  Widget _buildErrorState(Color textColor, Color iconColor) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 64, color: iconColor),
            const SizedBox(height: 16),
            Text(_error ?? 'Failed to load workshop',
                textAlign: TextAlign.center,
                style: TextStyle(color: textColor, fontSize: 16)),
            const SizedBox(height: 16),
            ElevatedButton(onPressed: _load, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }

  Widget _buildContent(
    double topPadding, bool isDark, Color textColor, Color secondaryTextColor,
    Color cardBgColor, Color surfaceColor, Color iconColor, Color buttonColor,
  ) {
    final w = _workshop!;
    final isTablet = ResponsiveHelper.isTablet(context);
    final hPadding =
        isTablet ? ResponsiveHelper.horizontalPadding(context) : 16.0;

    return RefreshIndicator(
      onRefresh: _load,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(
                maxWidth: ResponsiveHelper.getMaxContentWidth(context)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(height: topPadding),
                // Header
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
                            width: isTablet ? 30 : 24,
                            height: isTablet ? 30 : 24,
                            child: Icon(Icons.arrow_back,
                                size: isTablet ? 30 : 24, color: textColor),
                          ),
                        ),
                      ),
                      Center(
                        child: Text(
                          'Workshop Details',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            fontWeight: FontWeight.w500,
                            fontSize: isTablet ? 26 : 20,
                            height: 1.0,
                            letterSpacing: -0.5,
                            color: textColor,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 17),

                // Hero card
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
                        AspectRatio(
                          aspectRatio: 16 / 9,
                          child: w.thumbnailUrl != null
                              ? Image.network(
                                  w.thumbnailUrl!,
                                  width: double.infinity,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) =>
                                      _thumbnailPlaceholder(surfaceColor, iconColor),
                                )
                              : _thumbnailPlaceholder(surfaceColor, iconColor),
                        ),
                        Padding(
                          padding: EdgeInsets.all(isTablet ? 24 : 16),
                          child: Column(
                            children: [
                              Opacity(
                                opacity: 0.5,
                                child: Text(
                                  'WORKSHOP',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontFamily: 'Poppins',
                                    fontWeight: FontWeight.w500,
                                    fontSize: isTablet ? 13 : 10,
                                    letterSpacing: 0.05,
                                    color: textColor,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                w.title,
                                textAlign: TextAlign.center,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontFamily: 'Poppins',
                                  fontWeight: FontWeight.w500,
                                  fontSize: isTablet ? 26 : 20,
                                  height: 1.2,
                                  letterSpacing: -0.5,
                                  color: textColor,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                _dateRange(),
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontFamily: 'Poppins',
                                  fontWeight: FontWeight.w400,
                                  fontSize: isTablet ? 16 : 13,
                                  color: secondaryTextColor,
                                ),
                              ),
                              const SizedBox(height: 14),
                              // One quiet meta line instead of a row of loud
                              // pills. Price lives in the access card below, so
                              // it isn't repeated here.
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                alignment: WrapAlignment.center,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                children: [
                                  // A status pill only when it actually says
                                  // something — live now, ended, or cancelled.
                                  if (w.isLive)
                                    LiveLabel(
                                      isLive: true,
                                      fontSize: isTablet ? 13 : 10,
                                      borderRadius: 41,
                                      padding: EdgeInsets.symmetric(
                                          horizontal: isTablet ? 16 : 12,
                                          vertical: 6),
                                    )
                                  else if (w.isCancelled)
                                    _softChip('Cancelled', AppColors.error,
                                        icon: Icons.cancel_outlined)
                                  else if (w.isCompleted)
                                    _softChip('Completed', secondaryTextColor,
                                        icon: Icons.check_circle_outline),
                                  _softChip(
                                      '${w.dayCount} day${w.dayCount == 1 ? '' : 's'}',
                                      iconColor,
                                      icon: Icons.event_repeat),
                                  if (w.totalDurationMinutes > 0)
                                    _softChip(
                                        '${(w.totalDurationMinutes / 60).round()} hours',
                                        iconColor,
                                        icon: Icons.schedule),
                                  if (w.certificateEnabled)
                                    _softChip('Certificate', iconColor,
                                        icon: Icons.workspace_premium_outlined),
                                  if (w.hasAccess)
                                    _softChip('Enrolled', AppColors.success,
                                        icon: Icons.check_circle),
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

                if (w.isCancelled) ...[
                  _sectionCard(
                    hPadding,
                    isTablet,
                    surfaceColor,
                    isDark,
                    Row(
                      children: [
                        Icon(Icons.cancel_outlined, color: AppColors.error, size: 24),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'This workshop has been cancelled. If you paid, our team will be in touch about a refund.',
                            style: TextStyle(
                              fontFamily: 'Poppins',
                              fontWeight: FontWeight.w400,
                              fontSize: isTablet ? 16 : 13,
                              color: textColor,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                ] else ...[
                  // Access / booking panel
                  _buildAccessSection(isDark, textColor, secondaryTextColor,
                      surfaceColor, iconColor, buttonColor),
                  const SizedBox(height: 24),
                ],

                // Brochure — public marketing PDF, shown whether or not the
                // user has enrolled. Opens in the in-app viewer rather than a
                // browser, so it stays inside the app.
                if (w.brochureUrl != null && w.brochureUrl!.isNotEmpty) ...[
                  _sectionTitle('Brochure', hPadding, isTablet, textColor),
                  const SizedBox(height: 12),
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: hPadding),
                    child: GestureDetector(
                      onTap: () => context.pushNamed(
                        'pdf-viewer',
                        queryParameters: {
                          'pdfUrl': w.brochureUrl!,
                          'title': w.brochureFilename ?? 'Brochure',
                        },
                      ),
                      child: Container(
                        width: double.infinity,
                        decoration: BoxDecoration(
                          color: cardBgColor,
                          borderRadius: BorderRadius.circular(isTablet ? 30 : 24),
                        ),
                        child: Padding(
                          padding: EdgeInsets.all(isTablet ? 28 : 20),
                          child: Row(
                            children: [
                              Container(
                                width: isTablet ? 52 : 42,
                                height: isTablet ? 52 : 42,
                                decoration: BoxDecoration(
                                  color: iconColor.withValues(alpha: isDark ? 0.22 : 0.10),
                                  borderRadius: BorderRadius.circular(isTablet ? 16 : 12),
                                ),
                                // Deliberately the filled variant, not
                                // picture_as_pdf_outlined: Flutter tree-shakes
                                // the icon font, so an icon not already in the
                                // shipped release changes
                                // MaterialIcons-Regular.otf and makes the whole
                                // change unpatchable over the air. This one is
                                // already bundled.
                                child: Icon(
                                  Icons.picture_as_pdf,
                                  size: isTablet ? 28 : 22,
                                  color: iconColor,
                                ),
                              ),
                              SizedBox(width: isTablet ? 18 : 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      w.brochureFilename ?? 'Workshop brochure',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontFamily: 'Poppins',
                                        fontWeight: FontWeight.w600,
                                        fontSize: isTablet ? 17 : 14,
                                        color: textColor,
                                      ),
                                    ),
                                    SizedBox(height: isTablet ? 4 : 2),
                                    Text(
                                      'PDF · tap to read',
                                      style: TextStyle(
                                        fontFamily: 'Poppins',
                                        fontWeight: FontWeight.w400,
                                        fontSize: isTablet ? 14 : 12,
                                        color: secondaryTextColor,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Icon(
                                Icons.arrow_forward_ios_rounded,
                                size: isTablet ? 20 : 16,
                                color: iconColor,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                ],

                // Agenda
                _sectionTitle('Day-by-day Agenda', hPadding, isTablet, textColor),
                const SizedBox(height: 12),
                ...w.days.map((day) => Padding(
                      padding: EdgeInsets.symmetric(
                          horizontal: hPadding, vertical: 4),
                      child: _buildDayCard(day, isDark, textColor,
                          secondaryTextColor, cardBgColor, iconColor, buttonColor),
                    )),
                const SizedBox(height: 24),

                // Attendance
                if (w.isEnrolled && w.activeDays.isNotEmpty) ...[
                  _sectionTitle('Your Attendance', hPadding, isTablet, textColor),
                  const SizedBox(height: 12),
                  _buildAttendanceCard(hPadding, isTablet, isDark, textColor,
                      secondaryTextColor, surfaceColor, iconColor),
                  const SizedBox(height: 24),
                ],

                // Certificate
                if (w.certificateEnabled && w.isEnrolled) ...[
                  _sectionTitle('Certificate', hPadding, isTablet, textColor),
                  const SizedBox(height: 12),
                  _buildCertificateCard(hPadding, isTablet, isDark, textColor,
                      secondaryTextColor, surfaceColor, buttonColor),
                  const SizedBox(height: 24),
                ],

                // Recordings
                if (_recordings.isNotEmpty) ...[
                  _sectionTitle('Recordings', hPadding, isTablet, textColor),
                  const SizedBox(height: 12),
                  ..._recordings.map((rec) => Padding(
                        padding: EdgeInsets.symmetric(
                            horizontal: hPadding, vertical: 4),
                        child: _buildRecordingCard(rec, textColor,
                            secondaryTextColor, cardBgColor, iconColor),
                      )),
                  const SizedBox(height: 24),
                ],

                // About
                if (w.description != null && w.description!.isNotEmpty) ...[
                  _sectionTitle(
                      'About This Workshop', hPadding, isTablet, textColor),
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
                          w.description!,
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            fontWeight: FontWeight.w400,
                            fontSize: isTablet ? 17 : 14,
                            height: 1.5,
                            color: textColor,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                ],

                // Faculty
                if (w.faculty.isNotEmpty) ...[
                  _sectionTitle('Faculty', hPadding, isTablet, textColor),
                  const SizedBox(height: 12),
                  ...w.faculty.map((f) => Padding(
                        padding: EdgeInsets.symmetric(
                            horizontal: hPadding, vertical: 4),
                        child: _buildFacultyCard(f, isDark, textColor,
                            secondaryTextColor, cardBgColor),
                      )),
                ],

                const SizedBox(height: 120),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ==========================================================================
  // Sections
  // ==========================================================================

  Widget _sectionTitle(
      String text, double hPadding, bool isTablet, Color textColor) {
    return Padding(
      padding: EdgeInsets.only(left: hPadding),
      child: Text(
        text,
        style: TextStyle(
          fontFamily: 'Poppins',
          fontWeight: FontWeight.w500,
          fontSize: isTablet ? 26 : 20,
          height: 1.0,
          letterSpacing: -0.5,
          color: textColor,
        ),
      ),
    );
  }

  /// The elevated white card the session screen uses for its access panel.
  Widget _sectionCard(double hPadding, bool isTablet, Color surfaceColor,
      bool isDark, Widget child) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: hPadding),
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: surfaceColor,
          borderRadius: BorderRadius.circular(isTablet ? 30 : 24),
          boxShadow: isDark
              ? [
                  BoxShadow(
                      color: Colors.black.withValues(alpha: 0.3),
                      blurRadius: 10,
                      offset: const Offset(0, 6))
                ]
              : const [
                  BoxShadow(
                      color: Color(0x4D000000),
                      blurRadius: 3,
                      offset: Offset(0, 2)),
                  BoxShadow(
                      color: Color(0x26000000),
                      blurRadius: 10,
                      spreadRadius: 4,
                      offset: Offset(0, 6)),
                ],
        ),
        child: Padding(
          padding: EdgeInsets.all(isTablet ? 32 : 24),
          child: child,
        ),
      ),
    );
  }

  Widget _buildAccessSection(bool isDark, Color textColor,
      Color secondaryTextColor, Color surfaceColor, Color iconColor,
      Color buttonColor) {
    final w = _workshop!;
    final isTablet = ResponsiveHelper.isTablet(context);
    final hPadding =
        isTablet ? ResponsiveHelper.horizontalPadding(context) : 16.0;

    String title;
    if (w.hasAccess) {
      title = 'Workshop Access';
    } else if (w.isWaitlisted) {
      title = 'Waitlist';
    } else if (w.isPaid) {
      title = Platform.isIOS ? 'Access' : 'Get Access';
    } else {
      title = Platform.isIOS ? 'Access' : 'Register';
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle(title, hPadding, isTablet, textColor),
        const SizedBox(height: 12),
        _sectionCard(
          hPadding,
          isTablet,
          surfaceColor,
          isDark,
          _buildAccessContent(
              isDark, textColor, secondaryTextColor, iconColor, buttonColor),
        ),
      ],
    );
  }

  Widget _buildAccessContent(bool isDark, Color textColor,
      Color secondaryTextColor, Color iconColor, Color buttonColor) {
    final w = _workshop!;
    final isTablet = ResponsiveHelper.isTablet(context);

    // Enrolled / purchased
    if (w.hasAccess) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _statusBanner(
            Icons.check_circle,
            AppColors.success,
            w.enrollmentType == 'paid' ? 'Booked' : "You're Registered",
            w.isCompleted
                ? 'This workshop has finished. Recordings stay available below.'
                : 'Your place is confirmed for every day. Each day opens 10 minutes before it starts.',
            textColor,
            secondaryTextColor,
            isTablet,
          ),
          const SizedBox(height: 16),
          _infoRow(Icons.calendar_today, 'Dates', _dateRange(), iconColor,
              textColor, secondaryTextColor),
          const SizedBox(height: 12),
          _infoRow(Icons.event_available, 'Days attended',
              '${w.daysAttended} of ${w.activeDays.length}', iconColor,
              textColor, secondaryTextColor),
          if (!w.isPaid &&
              w.status == 'scheduled' &&
              w.enrollmentType != 'paid') ...[
            const SizedBox(height: 20),
            GestureDetector(
              onTap: _isEnrolling ? null : _cancelRegistration,
              child: Center(
                child: Text(
                  'Cancel my registration',
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontWeight: FontWeight.w400,
                    fontSize: isTablet ? 15 : 12,
                    color: secondaryTextColor,
                    decoration: TextDecoration.underline,
                    decorationColor: secondaryTextColor,
                  ),
                ),
              ),
            ),
          ],
        ],
      );
    }

    // Waitlisted
    if (w.isWaitlisted) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _statusBanner(
            Icons.hourglass_top,
            iconColor,
            "You're on the waitlist",
            w.waitlistPosition != null
                ? "You're #${w.waitlistPosition} in line. We'll notify you when a seat opens up."
                : "We'll notify you when a seat opens up.",
            textColor,
            secondaryTextColor,
            isTablet,
          ),
          const SizedBox(height: 20),
          GestureDetector(
            onTap: _isEnrolling ? null : _cancelRegistration,
            child: Center(
              child: Text(
                'Leave the waitlist',
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontWeight: FontWeight.w400,
                  fontSize: isTablet ? 15 : 12,
                  color: secondaryTextColor,
                  decoration: TextDecoration.underline,
                  decorationColor: secondaryTextColor,
                ),
              ),
            ),
          ),
        ],
      );
    }

    // Registration closed
    if (!w.registrationOpen) {
      return _statusBanner(
        Icons.lock_clock,
        AppColors.textTertiary,
        'Registration closed',
        'Registration for this workshop is no longer open.',
        textColor,
        secondaryTextColor,
        isTablet,
      );
    }

    // Sold out with no waitlist
    final full = _capacity?.isFull == true && _capacity?.allowWaitlist != true;
    if (full) {
      return _statusBanner(
        Icons.event_busy,
        AppColors.textTertiary,
        'Sold out',
        'Every seat for this workshop has been taken.',
        textColor,
        secondaryTextColor,
        isTablet,
      );
    }

    final seatsLine = _seatsLine();

    // Paid — buy
    if (w.isPaid) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (!Platform.isIOS)
                Text(
                  _formatPrice(w.price),
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontWeight: FontWeight.w700,
                    fontSize: isTablet ? 36 : 28,
                    color: textColor,
                  ),
                ),
              if (!Platform.isIOS &&
                  w.compareAtPrice != null &&
                  w.compareAtPrice! > w.price) ...[
                const SizedBox(width: 12),
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    _formatPrice(w.compareAtPrice!),
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontWeight: FontWeight.w400,
                      fontSize: isTablet ? 22 : 18,
                      color: secondaryTextColor,
                      decoration: TextDecoration.lineThrough,
                      decorationColor: secondaryTextColor,
                    ),
                  ),
                ),
              ],
            ],
          ),
          if (!Platform.isIOS) const SizedBox(height: 8),
          Text(
            'Covers all ${w.dayCount} days',
            style: TextStyle(
              fontFamily: 'Poppins',
              fontWeight: FontWeight.w400,
              fontSize: isTablet ? 17 : 14,
              color: secondaryTextColor,
            ),
          ),
          const SizedBox(height: 16),
          _infoRow(Icons.calendar_today, 'Dates', _dateRange(), iconColor,
              textColor, secondaryTextColor),
          if (seatsLine != null) ...[
            const SizedBox(height: 12),
            _infoRow(Icons.event_seat, 'Seats', seatsLine, iconColor, textColor,
                secondaryTextColor),
          ],
          const SizedBox(height: 24),
          _primaryButton(
            label: WebStoreLauncher.shouldUseWebStore
                ? 'GET ACCESS'
                : 'BUY NOW - ${_formatPrice(w.price)}',
            color: buttonColor,
            busy: _isPurchasing,
            icon: WebStoreLauncher.shouldUseWebStore
                ? Icons.open_in_new
                : Icons.shopping_cart,
            onTap: _initiatePayment,
            isTablet: isTablet,
          ),
        ],
      );
    }

    // Free — register (or join the waitlist)
    final joiningWaitlist = _capacity?.isFull == true;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _statusBanner(
          Icons.card_giftcard,
          iconColor,
          'This workshop is free!',
          Platform.isIOS
              ? 'Register now to secure your spot'
              : 'Register now — one sign-up covers all ${w.dayCount} days',
          textColor,
          secondaryTextColor,
          isTablet,
        ),
        const SizedBox(height: 16),
        _infoRow(Icons.calendar_today, 'Dates', _dateRange(), iconColor,
            textColor, secondaryTextColor),
        if (seatsLine != null) ...[
          const SizedBox(height: 12),
          _infoRow(Icons.event_seat, 'Seats', seatsLine, iconColor, textColor,
              secondaryTextColor),
        ],
        const SizedBox(height: 24),
        // Every primary action on this screen uses the brand blue — buy,
        // register and join all look like the same class of action.
        _primaryButton(
          label: joiningWaitlist ? 'JOIN WAITLIST' : 'REGISTER FOR FREE',
          color: buttonColor,
          busy: _isEnrolling,
          onTap: _enrollForFree,
          isTablet: isTablet,
        ),
      ],
    );
  }

  String? _seatsLine() {
    final c = _capacity;
    if (c == null || c.isUnlimited) return null;
    final available = c.availableSeats ?? 0;
    if (available > 0) return '$available of ${c.effectiveCapacity} left';
    return c.allowWaitlist ? 'Sold out — waitlist open' : 'Sold out';
  }

  /// One day of the agenda, with its own join affordance.
  Widget _buildDayCard(
    WorkshopDayModel day, bool isDark, Color textColor,
    Color secondaryTextColor, Color cardBgColor, Color iconColor,
    Color buttonColor,
  ) {
    final isTablet = ResponsiveHelper.isTablet(context);
    final w = _workshop!;
    final joining = _joiningSessionId == day.sessionId;
    final opensIn = _countdown(day.joinOpensAt);

    final dim = day.isCancelled || day.isCompleted;

    return Container(
      padding: EdgeInsets.all(isTablet ? 18 : 14),
      decoration: BoxDecoration(
        color: day.isCancelled
            ? (isDark ? AppColors.darkSurface : AppColors.cardBackground)
            : cardBgColor,
        borderRadius: BorderRadius.circular(isTablet ? 22 : 16),
        border: day.isLive
            ? Border.all(color: AppColors.error.withValues(alpha: 0.45), width: 1.5)
            : null,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Numbered rail — makes the sequence scannable at a glance, which a
          // repeated "DAY n" pill above body text does not.
          Container(
            width: isTablet ? 46 : 38,
            height: isTablet ? 46 : 38,
            decoration: BoxDecoration(
              color: dim
                  ? secondaryTextColor.withValues(alpha: 0.12)
                  : iconColor.withValues(alpha: 0.14),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    'DAY',
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontWeight: FontWeight.w600,
                      fontSize: isTablet ? 8 : 7,
                      height: 1.0,
                      letterSpacing: 0.3,
                      color: dim ? secondaryTextColor : iconColor,
                    ),
                  ),
                  Text(
                    '${day.dayNumber}',
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontWeight: FontWeight.w700,
                      fontSize: isTablet ? 18 : 15,
                      height: 1.1,
                      color: dim ? secondaryTextColor : iconColor,
                    ),
                  ),
                ],
              ),
            ),
          ),
          SizedBox(width: isTablet ? 14 : 12),

          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        day.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          fontWeight: FontWeight.w600,
                          fontSize: isTablet ? 18 : 15,
                          height: 1.25,
                          color: dim ? secondaryTextColor : textColor,
                          decoration:
                              day.isCancelled ? TextDecoration.lineThrough : null,
                          decorationColor: secondaryTextColor,
                        ),
                      ),
                    ),
                    if (day.attended) ...[
                      const SizedBox(width: 8),
                      Icon(Icons.check_circle,
                          size: isTablet ? 20 : 17, color: AppColors.success),
                    ],
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  '${_formatDayHeading(day.scheduledStartTime)} · '
                  '${_formatTime(day.scheduledStartTime)} – ${_formatTime(day.scheduledEndTime)}',
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontWeight: FontWeight.w400,
                    fontSize: isTablet ? 14 : 12,
                    color: secondaryTextColor,
                  ),
                ),
                if (day.facultyName != null) ...[
                  const SizedBox(height: 3),
                  Text(
                    day.facultyName!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontWeight: FontWeight.w400,
                      fontSize: isTablet ? 14 : 12,
                      color: secondaryTextColor,
                    ),
                  ),
                ],
                if (day.description != null && day.description!.isNotEmpty) ...[
                  const SizedBox(height: 7),
                  Text(
                    day.description!,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontWeight: FontWeight.w400,
                      fontSize: isTablet ? 14 : 12,
                      height: 1.45,
                      color: secondaryTextColor,
                    ),
                  ),
                ],

                // Status / action. Only a joinable day gets a button; the rest
                // get a quiet chip so nothing looks tappable when it isn't.
                const SizedBox(height: 12),
                if (day.isCancelled)
                  _softChip('Cancelled', AppColors.error)
                else if (day.canJoin)
                  SizedBox(
                    width: double.infinity,
                    child: _primaryButton(
                      label: day.isLive ? 'JOIN NOW' : 'JOIN DAY ${day.dayNumber}',
                      color: buttonColor,
                      busy: joining,
                      icon: Icons.videocam_rounded,
                      onTap: () => _joinDay(day),
                      isTablet: isTablet,
                      compact: true,
                    ),
                  )
                else if (day.isCompleted)
                  _softChip('Ended', secondaryTextColor)
                else if (!w.hasAccess)
                  _softChip(
                    w.isPaid ? 'Book to join' : 'Register to join',
                    secondaryTextColor,
                    icon: Icons.lock_outline,
                  )
                else
                  _softChip(
                    opensIn != null ? 'Opens in $opensIn' : 'Opening soon',
                    iconColor,
                    icon: Icons.schedule,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAttendanceCard(double hPadding, bool isTablet, bool isDark,
      Color textColor, Color secondaryTextColor, Color surfaceColor,
      Color iconColor) {
    final w = _workshop!;
    final total = w.activeDays.length;
    final progress = total == 0 ? 0.0 : (w.daysAttended / total).clamp(0.0, 1.0);

    return _sectionCard(
      hPadding,
      isTablet,
      surfaceColor,
      isDark,
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Days attended',
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontWeight: FontWeight.w500,
                  fontSize: isTablet ? 17 : 14,
                  color: textColor,
                ),
              ),
              Text(
                '${w.daysAttended} / $total',
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontWeight: FontWeight.w600,
                  fontSize: isTablet ? 17 : 14,
                  color: iconColor,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 8,
              backgroundColor: iconColor.withValues(alpha: 0.12),
              valueColor: AlwaysStoppedAnimation<Color>(iconColor),
            ),
          ),
          if (w.certificateEnabled && w.certificateMinDaysAttended != null) ...[
            const SizedBox(height: 10),
            Text(
              'Attend at least ${w.certificateMinDaysAttended} day'
              '${w.certificateMinDaysAttended == 1 ? '' : 's'} to earn a certificate.',
              style: TextStyle(
                fontFamily: 'Poppins',
                fontWeight: FontWeight.w400,
                fontSize: isTablet ? 14 : 11,
                color: secondaryTextColor,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildCertificateCard(double hPadding, bool isTablet, bool isDark,
      Color textColor, Color secondaryTextColor, Color surfaceColor,
      Color buttonColor) {
    final w = _workshop!;
    final status = _certificateStatus;
    final issued = w.certificate != null || status?.issued == true;
    final certNumber =
        w.certificate?.certificateNumber ?? status?.certificate?.certificateNumber;

    String message;
    if (issued) {
      message = 'Certificate issued${certNumber != null ? ' · $certNumber' : ''}';
    } else if (status?.eligible == true) {
      message =
          "You've earned your certificate — attended ${status!.daysAttended} of ${status.totalDays} days.";
    } else if (status?.reason == 'workshop_not_completed') {
      message =
          'Your certificate unlocks once the workshop ends, provided you attend at least ${status!.requiredDays} day${status.requiredDays == 1 ? '' : 's'}.';
    } else if (status?.reason == 'insufficient_attendance') {
      message =
          'You attended ${status!.daysAttended} of ${status.totalDays} days — ${status.requiredDays} are required.';
    } else {
      message =
          'Attend at least ${w.certificateMinDaysAttended ?? w.activeDays.length} day(s) to earn a certificate.';
    }

    final canClaim = issued || status?.eligible == true;

    return _sectionCard(
      hPadding,
      isTablet,
      surfaceColor,
      isDark,
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.workspace_premium,
                  color: canClaim ? buttonColor : secondaryTextColor,
                  size: isTablet ? 30 : 24),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  message,
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontWeight: FontWeight.w400,
                    fontSize: isTablet ? 16 : 13,
                    height: 1.4,
                    color: textColor,
                  ),
                ),
              ),
            ],
          ),
          if (canClaim) ...[
            const SizedBox(height: 20),
            _primaryButton(
              label: issued ? 'DOWNLOAD CERTIFICATE' : 'GET CERTIFICATE',
              color: buttonColor,
              busy: _isClaimingCertificate,
              icon: Icons.download,
              onTap: _claimCertificate,
              isTablet: isTablet,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildRecordingCard(WorkshopRecordingModel rec, Color textColor,
      Color secondaryTextColor, Color cardBgColor, Color iconColor) {
    final isTablet = ResponsiveHelper.isTablet(context);
    return GestureDetector(
      onTap: rec.isPlayable ? () => _openRecording(rec) : null,
      child: Container(
        padding: EdgeInsets.all(isTablet ? 18 : 12),
        decoration: BoxDecoration(
          color: cardBgColor,
          borderRadius: BorderRadius.circular(isTablet ? 22 : 16),
        ),
        child: Row(
          children: [
            Container(
              width: isTablet ? 52 : 42,
              height: isTablet ? 52 : 42,
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                rec.isPlayable ? Icons.play_circle_outline : Icons.lock_outline,
                color: rec.isPlayable ? iconColor : secondaryTextColor,
                size: isTablet ? 28 : 22,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    rec.workshopDay != null
                        ? 'Day ${rec.workshopDay} · ${rec.title}'
                        : rec.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontWeight: FontWeight.w500,
                      fontSize: isTablet ? 17 : 14,
                      color: textColor,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    rec.isLocked
                        ? 'Register to watch'
                        : rec.durationSeconds > 0
                            ? '${(rec.durationSeconds / 60).round()} min'
                            : 'Processing',
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontWeight: FontWeight.w400,
                      fontSize: isTablet ? 14 : 11,
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

  Widget _buildFacultyCard(WorkshopFacultyModel f, bool isDark, Color textColor,
      Color secondaryTextColor, Color cardBgColor) {
    final isTablet = ResponsiveHelper.isTablet(context);
    return Container(
      padding: EdgeInsets.all(isTablet ? 18 : 12),
      decoration: BoxDecoration(
        color: cardBgColor,
        borderRadius: BorderRadius.circular(isTablet ? 22 : 16),
      ),
      child: Row(
        children: [
          Container(
            width: isTablet ? 52 : 44,
            height: isTablet ? 52 : 44,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isDark ? AppColors.darkDivider : AppColors.divider,
            ),
            child: ClipOval(
              child: f.photoUrl != null
                  ? Image.network(
                      f.photoUrl!,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Icon(Icons.person,
                          size: 22, color: secondaryTextColor),
                    )
                  : Icon(Icons.person, size: 22, color: secondaryTextColor),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  f.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontWeight: FontWeight.w500,
                    fontSize: isTablet ? 17 : 14,
                    color: textColor,
                  ),
                ),
                if (f.specialization != null &&
                    f.specialization!.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    f.specialization!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontWeight: FontWeight.w400,
                      fontSize: isTablet ? 14 : 11,
                      color: secondaryTextColor,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ==========================================================================
  // Shared bits
  // ==========================================================================

  Widget _statusBanner(IconData icon, Color color, String title, String subtitle,
      Color textColor, Color secondaryTextColor, bool isTablet) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: isTablet ? 30 : 24),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontWeight: FontWeight.w600,
                    fontSize: isTablet ? 17 : 14,
                    color: textColor,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontWeight: FontWeight.w400,
                    fontSize: isTablet ? 15 : 12,
                    height: 1.35,
                    color: secondaryTextColor,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _infoRow(IconData icon, String label, String value, Color iconColor,
      Color textColor, Color secondaryTextColor) {
    final isTablet = ResponsiveHelper.isTablet(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: isTablet ? 22 : 18, color: iconColor),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontWeight: FontWeight.w400,
                  fontSize: isTablet ? 14 : 11,
                  color: secondaryTextColor,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontWeight: FontWeight.w500,
                  fontSize: isTablet ? 16 : 13,
                  color: textColor,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _primaryButton({
    required String label,
    required Color color,
    required bool busy,
    required VoidCallback onTap,
    required bool isTablet,
    IconData? icon,
    bool compact = false,
  }) {
    final height = compact ? (isTablet ? 46 : 38) : (isTablet ? 60.0 : 48.0);
    return GestureDetector(
      onTap: busy ? null : onTap,
      child: Container(
        width: double.infinity,
        height: height.toDouble(),
        decoration: BoxDecoration(
          color: busy ? AppColors.buttonDisabled : color,
          borderRadius: BorderRadius.circular(isTablet ? 28 : 22),
        ),
        child: Center(
          child: busy
              ? SizedBox(
                  width: isTablet ? 26 : 20,
                  height: isTablet ? 26 : 20,
                  child: const CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                )
              : Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (icon != null) ...[
                      Icon(icon, color: Colors.white, size: 20),
                      const SizedBox(width: 8),
                    ],
                    Text(
                      label,
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontWeight: FontWeight.w500,
                        fontSize: compact
                            ? (isTablet ? 16 : 13)
                            : (isTablet ? 20 : 16),
                        height: 1.11,
                        letterSpacing: 0.09,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }

  /// A quiet, tinted chip — the app's language is soft blue surfaces with
  /// coloured text, not saturated fills. Used for hero metadata and day status
  /// so a row of them reads as one calm line rather than competing badges.
  Widget _softChip(String text, Color color, {IconData? icon}) {
    final isTablet = ResponsiveHelper.isTablet(context);
    return Container(
      padding:
          EdgeInsets.symmetric(horizontal: isTablet ? 14 : 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(41),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: isTablet ? 15 : 13, color: color),
            const SizedBox(width: 5),
          ],
          Text(
            text,
            style: TextStyle(
              fontFamily: 'Poppins',
              fontWeight: FontWeight.w500,
              fontSize: isTablet ? 14 : 11,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _thumbnailPlaceholder(Color surfaceColor, Color iconColor) {
    return Container(
      width: double.infinity,
      color: surfaceColor,
      child: Icon(Icons.calendar_month_outlined, size: 50, color: iconColor),
    );
  }
}
