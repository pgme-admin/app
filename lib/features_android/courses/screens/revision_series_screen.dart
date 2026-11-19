import 'dart:io';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:pgme/core_android/providers/theme_provider.dart';
import 'package:pgme/core_android/theme/app_theme.dart';
import 'package:pgme/core_android/widgets/how_to_section.dart';
import 'package:pgme/core_android/services/dashboard_service.dart';
import 'package:pgme/core_android/utils/web_store_launcher.dart';
import 'package:pgme/features_android/purchase/widgets/combo_offer_card.dart';
import 'package:pgme/features_android/purchase/widgets/combo_upgrade_sheet.dart';
import 'package:pgme/core_android/models/series_model.dart';
import 'package:pgme/core_android/models/package_model.dart';
import 'package:pgme/features_android/home/providers/dashboard_provider.dart';
import 'package:pgme/core_android/widgets/shimmer_widgets.dart';
import 'package:pgme/core_android/utils/responsive_helper.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';

class RevisionSeriesScreen extends StatefulWidget {
  final bool isSubscribed;
  final String? packageId;

  const RevisionSeriesScreen({
    super.key,
    this.isSubscribed = false,
    this.packageId,
  });

  @override
  State<RevisionSeriesScreen> createState() => _RevisionSeriesScreenState();
}

class _RevisionSeriesScreenState extends State<RevisionSeriesScreen>
    with WidgetsBindingObserver {
  final DashboardService _dashboardService = DashboardService();
  List<SeriesModel> _series = [];
  PackageModel? _theoryPackage;
  bool _isLoading = true;
  String? _error;
  String? _activePackageId;

  // null = landing page, 'lectures' or 'documents' = series list
  String? _contentMode;

  @override
  void initState() {
    super.initState();
    if (Platform.isIOS) WidgetsBinding.instance.addObserver(this);
    _initializeAndLoad();
  }

  @override
  void dispose() {
    if (Platform.isIOS) WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed &&
        WebStoreLauncher.awaitingExternalPurchase) {
      WebStoreLauncher.clearAwaitingPurchase();
      _initializeAndLoad();
    }
  }

  Future<void> _initializeAndLoad() async {
    if (widget.packageId != null) {
      _activePackageId = widget.packageId;
      await _loadData();
    } else {
      await _findAndLoadTheoryPackage();
    }
  }

  Future<void> _findAndLoadTheoryPackage() async {
    try {
      setState(() {
        _isLoading = true;
        _error = null;
      });

      final dashboardProvider = Provider.of<DashboardProvider>(context, listen: false);
      final primarySubjectId = dashboardProvider.primarySubject?.subjectId;

      final packages = await _dashboardService.getPackages(
        subjectId: primarySubjectId,
      );

      if (packages.isEmpty) {
        setState(() {
          _error = 'no_content';
          _isLoading = false;
        });
        return;
      }

      final theoryPackage = packages.firstWhere(
        (pkg) => pkg.name.toLowerCase().contains('theory'),
        orElse: () => packages.first,
      );

      _activePackageId = theoryPackage.packageId;
      _theoryPackage = theoryPackage;

      await _loadData();
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _loadData() async {
    if (_activePackageId == null) {
      setState(() {
        _error = 'No package ID available';
        _isLoading = false;
      });
      return;
    }

    try {
      setState(() {
        _isLoading = true;
        _error = null;
      });

      // Also try to find the package model from DashboardProvider if we don't have it
      if (_theoryPackage == null) {
        final dashboardProvider = Provider.of<DashboardProvider>(context, listen: false);
        final pkgs = dashboardProvider.packages;
        try {
          _theoryPackage = pkgs.firstWhere(
            (p) => p.packageId == _activePackageId,
          );
        } catch (_) {
          // Not found in provider, that's ok
        }
      }

      final result = await _dashboardService.getPackageSeries(_activePackageId!);

      setState(() {
        _series = result.series;
        // Update revoked status from fresh backend check
        if (_theoryPackage != null && result.accessRevoked != _theoryPackage!.accessRevoked) {
          _theoryPackage = _theoryPackage!.copyWith(accessRevoked: result.accessRevoked);
        }
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  void _showEnrollmentPopup() async {
    final themeProvider = Provider.of<ThemeProvider>(context, listen: false);
    final isDark = themeProvider.isDarkMode;

    final shouldEnroll = await showDialog<bool>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.5),
      builder: (dialogContext) => _buildEnrollmentDialog(dialogContext, isDark),
    );

    if (shouldEnroll == true && mounted) {
      if (WebStoreLauncher.shouldUseWebStore) {
        WebStoreLauncher.openProductPage(context, productType: 'packages', productId: _activePackageId ?? '');
      } else {
        context.push('/package-access?packageId=$_activePackageId&packageType=Theory');
      }
    }
  }

  /// Open the credited combo checkout chosen from the purchase popup.
  void _takeComboOffer(Map<String, dynamic> offer) {
    final comboId = (offer['combo'] as Map<String, dynamic>?)?['package_id']?.toString();
    if (comboId == null) return;
    showComboUpgradeSheet(context, comboPackageId: comboId, quote: offer).then((done) {
      if (done == true && mounted) _initializeAndLoad();
    });
  }

  Widget _buildEnrollmentDialog(BuildContext dialogContext, bool isDark) {
    final isTablet = ResponsiveHelper.isTablet(context);
    final dialogBgColor = isDark ? AppColors.darkSurface : Colors.white;
    final textColor = isDark ? AppColors.darkTextPrimary : const Color(0xFF000000);
    final secondaryTextColor = isDark ? AppColors.darkTextSecondary : const Color(0xFF666666);
    final boxBgColor = isDark ? AppColors.darkCardBackground : const Color(0xFFF5F5F5);
    final iconColor = isDark ? const Color(0xFF00BEFA) : const Color(0xFF2470E4);
    final buttonColor = isDark ? const Color(0xFF0047CF) : const Color(0xFF0000D1);

    final packageName = _theoryPackage?.name ?? 'the Package';
    final packageDescription = _theoryPackage?.description ?? 'Unlock all content and get access to comprehensive study materials.';
    final packageFeatures = _theoryPackage?.features ?? ['Access to all content'];
    final priceValue = _theoryPackage?.displayPrice ?? 0;
    final priceFormatted = Platform.isIOS ? '' : '₹${priceValue.toString().replaceAllMapped(RegExp(r'(\d)(?=(\d{3})+(?!\d))'), (m) => '${m[1]},')}';
    final durationDays = _theoryPackage?.durationDays ?? 0;
    final durationText = durationDays >= 365
        ? '/ ${durationDays ~/ 365} ${(durationDays ~/ 365) == 1 ? 'year' : 'years'}'
        : durationDays >= 30
            ? '/ ${durationDays ~/ 30} ${(durationDays ~/ 30) == 1 ? 'month' : 'months'}'
            : durationDays > 0
                ? '/ $durationDays ${durationDays == 1 ? 'day' : 'days'}'
                : '';

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
      child: Container(
        width: isTablet ? 480 : 356,
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height - 80,
        ),
        decoration: BoxDecoration(
          color: dialogBgColor,
          borderRadius: BorderRadius.circular(isTablet ? 28 : 20.8),
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Align(
                alignment: Alignment.topRight,
                child: Padding(
                  padding: const EdgeInsets.only(top: 12, right: 12),
                  child: GestureDetector(
                    onTap: () => Navigator.of(dialogContext).pop(false),
                    child: Icon(Icons.close, size: 24, color: secondaryTextColor),
                  ),
                ),
              ),
              Image.asset(
                'assets/illustrations/enroll.png',
                width: isTablet ? 240 : 180,
                height: isTablet ? 160 : 120,
                fit: BoxFit.contain,
                errorBuilder: (context, error, stackTrace) {
                  return Container(
                    width: isTablet ? 240 : 180,
                    height: isTablet ? 160 : 120,
                    decoration: BoxDecoration(
                      color: isDark ? AppColors.darkCardBackground : const Color(0xFFDCEAF7),
                      borderRadius: BorderRadius.circular(isTablet ? 16 : 12),
                    ),
                    child: Icon(Icons.school_outlined, size: isTablet ? 80 : 60, color: iconColor),
                  );
                },
              ),
              const SizedBox(height: 16),
              Text(
                Platform.isIOS ? 'View $packageName' : 'Get $packageName',
                style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w600, fontSize: isTablet ? 26 : 20, color: textColor),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Text(
                  packageDescription,
                  style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w400, fontSize: isTablet ? 17 : 14, height: 1.4, color: secondaryTextColor),
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(height: 20),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(color: boxBgColor, borderRadius: BorderRadius.circular(12)),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (int i = 0; i < packageFeatures.length; i++) ...[
                        if (i > 0) const SizedBox(height: 8),
                        _buildFeatureCheckItem(packageFeatures[i], textColor, iconColor),
                      ],
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Text(priceFormatted, style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700, fontSize: isTablet ? 30 : 24, color: textColor)),
                          if (durationText.isNotEmpty) ...[
                            const SizedBox(width: 8),
                            Text(durationText, style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w400, fontSize: 12, color: secondaryTextColor)),
                          ],
                        ],
                      ),
                      const SizedBox(height: 16),
                      if (_activePackageId != null)
                        ComboOfferSection(
                          packageId: _activePackageId!,
                          isPurchased: _theoryPackage?.isPurchased ?? false,
                          isDark: isDark,
                          isTablet: isTablet,
                          onTake: (offer) {
                            Navigator.of(dialogContext).pop(false);
                            _takeComboOffer(offer);
                          },
                        ),
                      SizedBox(
                        width: double.infinity,
                        height: isTablet ? 52 : 40,
                        child: ElevatedButton(
                          onPressed: () => Navigator.of(dialogContext).pop(true),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: buttonColor,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
                            elevation: 0,
                          ),
                          child: Text(Platform.isIOS ? 'Learn More' : 'Enroll Now', style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w500, fontSize: isTablet ? 19 : 16, color: Colors.white)),
                        ),
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        width: double.infinity,
                        height: isTablet ? 52 : 40,
                        child: OutlinedButton(
                          onPressed: () => Navigator.of(dialogContext).pop(false),
                          style: OutlinedButton.styleFrom(
                            side: BorderSide(color: buttonColor, width: 1),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
                          ),
                          child: Text('See All Packages', style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w500, fontSize: isTablet ? 19 : 16, color: buttonColor)),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const HowToSection(screen: 'theory'),
              const SizedBox(height: 100),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFeatureCheckItem(String text, Color textColor, Color iconColor) {
    final isTablet = ResponsiveHelper.isTablet(context);
    return Row(
      children: [
        Icon(Icons.check_circle, size: isTablet ? 22 : 18, color: iconColor),
        const SizedBox(width: 8),
        Expanded(
          child: Text(text, style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w400, fontSize: isTablet ? 16 : 13, color: textColor)),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final topPadding = MediaQuery.of(context).padding.top;
    final themeProvider = Provider.of<ThemeProvider>(context);
    final isDark = themeProvider.isDarkMode;
    final isTablet = ResponsiveHelper.isTablet(context);
    final hPadding = isTablet ? ResponsiveHelper.horizontalPadding(context) : 16.0;

    final dashboardProvider = Provider.of<DashboardProvider>(context);
    // Use the active theory package's purchase status when available,
    // otherwise fall back to type-level subscription check
    final isSubscribed = _theoryPackage?.isPurchased ?? (dashboardProvider.hasTheorySubscription || widget.isSubscribed);

    final backgroundColor = isDark ? AppColors.darkBackground : Colors.white;
    final textColor = isDark ? AppColors.darkTextPrimary : const Color(0xFF000000);
    final secondaryTextColor = isDark ? AppColors.darkTextSecondary : const Color(0xFF666666);
    final iconColor = isDark ? const Color(0xFF00BEFA) : const Color(0xFF2470E4);
    final cardBgColor = isDark ? AppColors.darkCardBackground : const Color(0xFFDCEAF7);

    final isOnLanding = _contentMode == null;
    final title = isOnLanding
        ? 'Theory Packages'
        : _contentMode == 'lectures'
            ? 'Video Lectures'
            : 'Study Notes';

    return BackButtonListener(
      onBackButtonPressed: () async {
        if (_contentMode != null) {
          setState(() => _contentMode = null);
          return true;
        }
        // On landing page — navigate to home
        if (mounted) {
          context.go('/home');
        }
        return true;
      },
      child: PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) {
            if (_contentMode != null) {
              setState(() => _contentMode = null);
            } else {
              context.go('/home');
            }
          }
        },
        child: Scaffold(
        backgroundColor: backgroundColor,
        body: Column(
          children: [
            // App bar area
            Padding(
              padding: EdgeInsets.only(top: topPadding + 12, left: hPadding, right: hPadding, bottom: 12),
              child: Row(
                children: [
                  // Back arrow
                  GestureDetector(
                    onTap: () {
                      if (isOnLanding) {
                        context.go('/home');
                      } else {
                        setState(() => _contentMode = null);
                      }
                    },
                    child: Padding(
                      padding: const EdgeInsets.only(right: 12),
                      child: Icon(Icons.arrow_back_rounded, size: isTablet ? 30 : 24, color: textColor),
                    ),
                  ),
                  // Title
                  Expanded(
                    child: Text(
                      title,
                      textAlign: TextAlign.left,
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontWeight: FontWeight.w600,
                        fontSize: isTablet ? 26 : 20,
                        letterSpacing: -0.3,
                        color: textColor,
                      ),
                    ),
                  ),
                  // // Menu icon (only on landing)
                  // if (isOnLanding)
                  //   GestureDetector(
                  //     onTap: () {},
                  //     child: Icon(Icons.more_horiz, size: isTablet ? 30 : 24, color: textColor),
                  //   ),
                ],
              ),
            ),

            // Revoked banner
            if (_theoryPackage?.accessRevoked == true)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                color: const Color(0xFFE53935).withValues(alpha: 0.1),
                child: Row(
                  children: [
                    const Icon(Icons.block, size: 18, color: Color(0xFFE53935)),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Your access to this package has been revoked. Contact support for assistance.',
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: isDark ? const Color(0xFFEF9A9A) : const Color(0xFFB71C1C),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

            // Content
            Expanded(
              child: RefreshIndicator(
                onRefresh: _initializeAndLoad,
                child: _isLoading
                  ? _buildLoadingShimmer(isDark)
                  : _error == 'no_content'
                      ? _buildComingSoonView(isDark, textColor, secondaryTextColor)
                      : _error != null
                          ? _buildErrorView(textColor, secondaryTextColor, iconColor)
                          : isOnLanding
                              ? _buildLandingView(isDark, textColor, secondaryTextColor, iconColor, cardBgColor, isSubscribed)
                              : _buildSeriesListView(isDark, textColor, secondaryTextColor, iconColor, cardBgColor, isSubscribed),
              ),
            ),
          ],
        ),
      ),
      ),
    );
  }

  // ── Landing View ──────────────────────────────────────────────────────

  Widget _buildLandingView(
    bool isDark,
    Color textColor,
    Color secondaryTextColor,
    Color iconColor,
    Color cardBgColor,
    bool isSubscribed,
  ) {
    final isTablet = ResponsiveHelper.isTablet(context);
    final hPadding = isTablet ? ResponsiveHelper.horizontalPadding(context) : 16.0;
    final gradientStart = isDark ? const Color(0xFF1A3A5C) : const Color(0xFFCDE5FF);
    final gradientEnd = isDark ? const Color(0xFF2D5A9E) : const Color(0xFF8FC6FF);

    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.only(bottom: 100),
      child: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: ResponsiveHelper.getMaxContentWidth(context)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 8),

              // Option cards — dynamic layout based on available content
              if (_getTotalLectures() > 0 || _getTotalDocuments() > 0)
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: hPadding),
                  child: Builder(builder: (_) {
                    final cards = <Widget>[];
                    if (_getTotalLectures() > 0) {
                      cards.add(_buildOptionCard(
                        title: 'Watch\nVideo Lectures',
                        subtitle: '${_getTotalLectures()} Lectures',
                        icon: Icons.play_circle_outline_rounded,
                        imagePath: 'assets/illustrations/1.png',
                        isDark: isDark,
                        gradientStart: gradientStart,
                        gradientEnd: gradientEnd,
                        onTap: () => setState(() => _contentMode = 'lectures'),
                      ));
                    }
                    if (_getTotalDocuments() > 0) {
                      cards.add(_buildOptionCard(
                        title: 'Read\nNotes',
                        subtitle: '${_getTotalDocuments()} Notes',
                        icon: Icons.description_outlined,
                        imagePath: 'assets/illustrations/2.png',
                        isDark: isDark,
                        gradientStart: gradientStart,
                        gradientEnd: gradientEnd,
                        onTap: () => setState(() => _contentMode = 'documents'),
                      ));
                    }
                    if (cards.length == 1) return cards[0];
                    return Row(
                      children: [
                        Expanded(child: cards[0]),
                        SizedBox(width: isTablet ? 20 : 14),
                        Expanded(child: cards[1]),
                      ],
                    );
                  }),
                ),

              const SizedBox(height: 28),

              // Package info section
              _buildPackageInfoSection(isDark, textColor, secondaryTextColor, iconColor, cardBgColor, isSubscribed),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildOptionCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required String imagePath,
    String? imageUrl,
    required bool isDark,
    required Color gradientStart,
    required Color gradientEnd,
    required VoidCallback onTap,
  }) {
    final isTablet = ResponsiveHelper.isTablet(context);
    final cardHeight = isTablet ? 280.0 : 180.0;
    final cardRadius = isTablet ? 22.0 : 16.0;
    final cardPadding = isTablet ? 24.0 : 16.0;
    final titleSize = isTablet ? 22.0 : 16.0;
    final subtitleSize = isTablet ? 15.0 : 11.0;
    final pillPaddingH = isTablet ? 14.0 : 10.0;
    final pillPaddingV = isTablet ? 6.0 : 4.0;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        height: cardHeight,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(cardRadius),
          gradient: LinearGradient(
            begin: const Alignment(-0.5, -0.5),
            end: const Alignment(0.5, 0.5),
            colors: [gradientStart, gradientEnd],
          ),
        ),
        child: Stack(
          children: [
            Padding(
              padding: EdgeInsets.all(cardPadding),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontWeight: FontWeight.w600,
                      fontSize: titleSize,
                      color: isDark ? Colors.white : const Color(0xFF000000),
                      height: 1.3,
                    ),
                  ),
                  SizedBox(height: isTablet ? 10 : 6),
                  Container(
                    padding: EdgeInsets.symmetric(horizontal: pillPaddingH, vertical: pillPaddingV),
                    decoration: BoxDecoration(
                      color: isDark ? AppColors.darkSurface : Colors.white,
                      borderRadius: BorderRadius.circular(isTablet ? 16 : 12),
                    ),
                    child: Text(
                      subtitle,
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontWeight: FontWeight.w500,
                        fontSize: subtitleSize,
                        color: isDark ? const Color(0xFF00BEFA) : const Color(0xFF2470E4),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // Illustration
            Positioned(
              right: 0,
              bottom: 0,
              child: ClipRRect(
                borderRadius: BorderRadius.only(bottomRight: Radius.circular(cardRadius)),
                child: imageUrl != null
                    ? Image.network(
                        imageUrl,
                        width: isTablet ? 200 : 110,
                        height: isTablet ? 160 : 80,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) {
                          return Image.asset(
                            imagePath,
                            width: isTablet ? 200 : 110,
                            height: isTablet ? 160 : 80,
                            fit: BoxFit.cover,
                          );
                        },
                      )
                    : Image.asset(
                        imagePath,
                        width: isTablet ? 200 : 110,
                        height: isTablet ? 160 : 80,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) {
                          return Container(
                            width: isTablet ? 200 : 110,
                            height: isTablet ? 160 : 80,
                            decoration: BoxDecoration(
                              color: isDark ? AppColors.darkCardBackground : const Color(0xFFDCEAF7),
                              borderRadius: BorderRadius.only(bottomRight: Radius.circular(cardRadius)),
                            ),
                            child: Icon(
                              icon,
                              size: isTablet ? 48 : 36,
                              color: isDark ? const Color(0xFF00BEFA) : const Color(0xFF2470E4),
                            ),
                          );
                        },
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _colorToHex(Color color) {
    final r = (color.r * 255.0).round().clamp(0, 255);
    final g = (color.g * 255.0).round().clamp(0, 255);
    final b = (color.b * 255.0).round().clamp(0, 255);
    return '#${r.toRadixString(16).padLeft(2, '0')}${g.toRadixString(16).padLeft(2, '0')}${b.toRadixString(16).padLeft(2, '0')}';
  }

  Widget _buildPackageInfoSection(
    bool isDark,
    Color textColor,
    Color secondaryTextColor,
    Color iconColor,
    Color cardBgColor,
    bool isSubscribed,
  ) {
    final isTablet = ResponsiveHelper.isTablet(context);
    final hPadding = isTablet ? ResponsiveHelper.horizontalPadding(context) : 16.0;
    final pkg = _theoryPackage;
    final totalLectures = _getTotalLectures();
    final totalDocs = _getTotalDocuments();
    final totalDuration = _getTotalDuration();

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: hPadding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Package name
          Text(
            pkg?.name ?? 'Theory Package',
            style: TextStyle(
              fontFamily: 'Poppins',
              fontWeight: FontWeight.w600,
              fontSize: isTablet ? 24 : 18,
              color: textColor,
            ),
          ),
          if (pkg != null && pkg.hasRichDescription) ...[
            const SizedBox(height: 8),
            HtmlWidget(
              pkg.richDescription!,
              textStyle: TextStyle(
                fontFamily: 'Poppins',
                fontSize: isTablet ? 17 : 14,
                fontWeight: FontWeight.w400,
                color: secondaryTextColor,
                height: 1.5,
              ),
              customStylesBuilder: (element) {
                switch (element.localName) {
                  case 'h1':
                    return {'font-size': '${isTablet ? 24 : 20}px', 'font-weight': '700', 'color': '${_colorToHex(textColor)}', 'margin': '16px 0 8px 0'};
                  case 'h2':
                    return {'font-size': '${isTablet ? 20 : 17}px', 'font-weight': '600', 'color': '${_colorToHex(textColor)}', 'margin': '14px 0 6px 0'};
                  case 'h3':
                    return {'font-size': '${isTablet ? 18 : 15}px', 'font-weight': '600', 'color': '${_colorToHex(textColor)}', 'margin': '12px 0 4px 0'};
                  case 'li':
                    return {'margin': '4px 0'};
                }
                return null;
              },
            ),
          ] else if (pkg?.description != null && pkg!.description!.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              pkg.description!,
              style: TextStyle(
                fontFamily: 'Poppins',
                fontWeight: FontWeight.w400,
                fontSize: isTablet ? 17 : 14,
                height: 1.5,
                color: secondaryTextColor,
              ),
            ),
          ],

          const SizedBox(height: 20),

          // Stats row
          Container(
            padding: EdgeInsets.all(isTablet ? 22 : 16),
            decoration: BoxDecoration(
              color: cardBgColor,
              borderRadius: BorderRadius.circular(isTablet ? 22 : 16),
            ),
            child: Row(
              children: [
                _buildStatItem(
                  icon: Icons.folder_outlined,
                  value: '${_series.length}',
                  label: 'Series',
                  iconColor: iconColor,
                  textColor: textColor,
                  secondaryColor: secondaryTextColor,
                ),
                _buildStatDivider(isDark),
                _buildStatItem(
                  icon: Icons.play_circle_outline,
                  value: '$totalLectures',
                  label: 'Lectures',
                  iconColor: iconColor,
                  textColor: textColor,
                  secondaryColor: secondaryTextColor,
                ),
                _buildStatDivider(isDark),
                _buildStatItem(
                  icon: Icons.description_outlined,
                  value: '$totalDocs',
                  label: 'Notes',
                  iconColor: iconColor,
                  textColor: textColor,
                  secondaryColor: secondaryTextColor,
                ),
                if (totalDuration.isNotEmpty) ...[
                  _buildStatDivider(isDark),
                  _buildStatItem(
                    icon: Icons.access_time_rounded,
                    value: totalDuration,
                    label: 'Duration',
                    iconColor: iconColor,
                    textColor: textColor,
                    secondaryColor: secondaryTextColor,
                  ),
                ],
              ],
            ),
          ),

          const SizedBox(height: 20),

          // Enroll / Enrolled button
          _buildEnrollButton(isDark, isTablet, isSubscribed: isSubscribed),
          const SizedBox(height: 20),

          // What's included / Features (only when no rich description)
          if (!(pkg != null && pkg.hasRichDescription) && pkg?.features != null && pkg!.features!.isNotEmpty) ...[
            Text(
              "What's Included",
              style: TextStyle(
                fontFamily: 'Poppins',
                fontWeight: FontWeight.w600,
                fontSize: isTablet ? 20 : 16,
                color: textColor,
              ),
            ),
            const SizedBox(height: 12),
            ...pkg.features!.map((feature) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Text(
                    feature,
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontWeight: FontWeight.w400,
                      fontSize: isTablet ? 17 : 14,
                      height: 1.4,
                      color: textColor,
                    ),
                  ),
                )),
            const SizedBox(height: 16),
          ],

          // // Series overview
          // Text(
          //   'Series',
          //   style: TextStyle(
          //     fontFamily: 'Poppins',
          //     fontWeight: FontWeight.w600,
          //     fontSize: isTablet ? 20 : 16,
          //     color: textColor,
          //   ),
          // ),
          // const SizedBox(height: 12),
          // ..._series.map((s) => _buildSeriesPreviewTile(s, isDark, textColor, secondaryTextColor, iconColor)),
        ],
      ),
    );
  }

  Widget _buildEnrollButton(bool isDark, bool isTablet, {required bool isSubscribed}) {
    final buttonHeight = isTablet ? 56.0 : 48.0;
    final buttonRadius = isTablet ? 24.0 : 20.0;
    final fontSize = isTablet ? 18.0 : 16.0;

    if (isSubscribed) {
      final enrolledColor = isDark ? const Color(0xFF2E7D32) : const Color(0xFF388E3C);
      return SizedBox(
        width: double.infinity,
        height: buttonHeight,
        child: ElevatedButton.icon(
          onPressed: () {
            setState(() => _contentMode = 'lectures');
          },
          icon: Icon(Icons.check_circle_outline, size: isTablet ? 22 : 20, color: Colors.white),
          label: Text(
            'Enrolled',
            style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: fontSize,
              fontWeight: FontWeight.w600,
              color: Colors.white,
            ),
          ),
          style: ElevatedButton.styleFrom(
            backgroundColor: enrolledColor,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(buttonRadius),
            ),
            elevation: 0,
          ),
        ),
      );
    }

    final buttonColor = isDark ? const Color(0xFF0047CF) : const Color(0xFF0000D1);
    return SizedBox(
      width: double.infinity,
      height: buttonHeight,
      child: ElevatedButton(
        onPressed: () {
          if (WebStoreLauncher.shouldUseWebStore) {
            WebStoreLauncher.openProductPage(context, productType: 'packages', productId: _activePackageId ?? '');
          } else {
            context.push('/package-access?packageId=$_activePackageId&packageType=Theory');
          }
        },
        style: ElevatedButton.styleFrom(
          backgroundColor: buttonColor,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(buttonRadius),
          ),
          elevation: 0,
        ),
        child: Text(
          Platform.isIOS ? 'Learn More' : 'Enroll Now',
          style: TextStyle(
            fontFamily: 'Poppins',
            fontSize: fontSize,
            fontWeight: FontWeight.w600,
            color: Colors.white,
          ),
        ),
      ),
    );
  }

  Widget _buildStatItem({
    required IconData icon,
    required String value,
    required String label,
    required Color iconColor,
    required Color textColor,
    required Color secondaryColor,
  }) {
    final isTablet = ResponsiveHelper.isTablet(context);
    return Expanded(
      child: Column(
        children: [
          Icon(icon, size: isTablet ? 26 : 20, color: iconColor),
          const SizedBox(height: 6),
          Text(
            value,
            style: TextStyle(
              fontFamily: 'Poppins',
              fontWeight: FontWeight.w600,
              fontSize: isTablet ? 20 : 16,
              color: textColor,
            ),
          ),
          Text(
            label,
            style: TextStyle(
              fontFamily: 'Poppins',
              fontWeight: FontWeight.w400,
              fontSize: isTablet ? 14 : 11,
              color: secondaryColor,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatDivider(bool isDark) {
    final isTablet = ResponsiveHelper.isTablet(context);
    return Container(
      width: 1,
      height: isTablet ? 52 : 40,
      color: isDark ? Colors.white.withValues(alpha: 0.1) : Colors.black.withValues(alpha: 0.1),
    );
  }

  Widget _buildSeriesPreviewTile(
    SeriesModel series,
    bool isDark,
    Color textColor,
    Color secondaryTextColor,
    Color iconColor,
  ) {
    final isTablet = ResponsiveHelper.isTablet(context);
    final tileMargin = isTablet ? 14.0 : 10.0;
    final tilePaddingH = isTablet ? 20.0 : 14.0;
    final tilePaddingV = isTablet ? 16.0 : 12.0;
    final iconBoxSize = isTablet ? 52.0 : 36.0;
    final iconBoxRadius = isTablet ? 14.0 : 10.0;

    return Container(
      margin: EdgeInsets.only(bottom: tileMargin),
      padding: EdgeInsets.symmetric(horizontal: tilePaddingH, vertical: tilePaddingV),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface : const Color(0xFFF8F9FA),
        borderRadius: BorderRadius.circular(isTablet ? 16 : 12),
        border: Border.all(
          color: isDark ? Colors.white.withValues(alpha: 0.06) : Colors.black.withValues(alpha: 0.06),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: iconBoxSize,
            height: iconBoxSize,
            decoration: BoxDecoration(
              color: isDark ? AppColors.darkCardBackground : const Color(0xFFE8F0FE),
              borderRadius: BorderRadius.circular(iconBoxRadius),
            ),
            child: Center(
                    child: Icon(Icons.menu_book_rounded, size: isTablet ? 26 : 18, color: iconColor),
                  ),
          ),
          SizedBox(width: isTablet ? 16 : 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  series.title,
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontWeight: FontWeight.w500,
                    fontSize: isTablet ? 16 : 13,
                    color: textColor,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                SizedBox(height: isTablet ? 4 : 2),
                Text(
                  () {
                    final lec = series.totalLectures ?? 0;
                    final doc = series.totalDocuments ?? 0;
                    if (lec > 0 && doc > 0) return '$lec lectures · $doc docs';
                    if (lec > 0) return '$lec lectures';
                    if (doc > 0) return '$doc docs';
                    if (series.documentsComingSoon) return series.documentsReleaseAt != null ? 'Coming ${_formatReleaseDate(series.documentsReleaseAt!)}' : 'Coming soon';
                    return '';
                  }(),
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
          if (series.isLocked)
            Icon(Icons.lock_rounded, size: isTablet ? 22 : 16, color: secondaryTextColor),
        ],
      ),
    );
  }

  // ── Series List View ──────────────────────────────────────────────────

  Widget _buildSeriesListView(
    bool isDark,
    Color textColor,
    Color secondaryTextColor,
    Color iconColor,
    Color cardBgColor,
    bool isSubscribed,
  ) {
    final isTablet = ResponsiveHelper.isTablet(context);
    final hPadding = isTablet ? ResponsiveHelper.horizontalPadding(context) : 16.0;

    if (_series.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.video_library_outlined, size: isTablet ? 64 : 48, color: textColor.withValues(alpha: 0.5)),
            SizedBox(height: isTablet ? 20 : 16),
            Text(
              'Series Coming Soon',
              style: TextStyle(fontFamily: 'Poppins', fontSize: isTablet ? 20 : 16, fontWeight: FontWeight.w600, color: textColor),
            ),
          ],
        ),
      );
    }

    // Hide series with no content in the active mode
    final isDocMode = _contentMode == 'documents';
    final filteredSeries = isDocMode
        ? _series.where((s) => (s.totalDocuments ?? 0) > 0 || s.documentsComingSoon).toList()
        : _series.where((s) => (s.totalLectures ?? 0) > 0).toList();

    if (filteredSeries.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.description_outlined, size: isTablet ? 64 : 48, color: textColor.withValues(alpha: 0.5)),
            SizedBox(height: isTablet ? 20 : 16),
            Text(
              'No Documents Available',
              style: TextStyle(fontFamily: 'Poppins', fontSize: isTablet ? 20 : 16, fontWeight: FontWeight.w600, color: textColor),
            ),
          ],
        ),
      );
    }

    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: ResponsiveHelper.getMaxContentWidth(context)),
        child: ListView.builder(
          padding: EdgeInsets.symmetric(horizontal: hPadding).copyWith(bottom: 100),
          itemCount: filteredSeries.length,
          itemBuilder: (context, index) {
            final series = filteredSeries[index];
            final isItemLocked = series.isLocked;

            return GestureDetector(
              onTap: () {
                if (isItemLocked) {
                  _showEnrollmentPopup();
                } else {
                  final seriesId = series.seriesId;
                  if (seriesId.isEmpty) return;

                  if (_contentMode == 'lectures') {
                    context.push('/lecture/$seriesId?subscribed=$isSubscribed&packageType=Theory&packageId=$_activePackageId');
                  } else {
                    context.push('/available-notes?seriesId=$seriesId&subscribed=$isSubscribed');
                  }
                }
              },
              child: _buildSeriesCard(
                series,
                isDark: isDark,
                textColor: textColor,
                cardBgColor: cardBgColor,
                iconColor: iconColor,
                isLocked: isItemLocked,
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildSeriesCard(
    SeriesModel series, {
    required bool isDark,
    required Color textColor,
    required Color cardBgColor,
    required Color iconColor,
    required bool isLocked,
  }) {
    final isTablet = ResponsiveHelper.isTablet(context);
    final isLectureMode = _contentMode == 'lectures';

    final cardMargin = isTablet ? 18.0 : 14.0;
    final cardPadding = isTablet ? 24.0 : 18.0;
    final iconBoxSize = isTablet ? 60.0 : 44.0;
    final iconBoxRadius = isTablet ? 16.0 : 12.0;
    final contentIconSize = isTablet ? 30.0 : 22.0;
    final lockBoxSize = isTablet ? 42.0 : 32.0;
    final contentGap = isTablet ? 18.0 : 14.0;

    return Container(
      margin: EdgeInsets.only(bottom: cardMargin),
      decoration: BoxDecoration(
        color: cardBgColor,
        borderRadius: BorderRadius.circular(isTablet ? 22 : 16),
      ),
      child: Padding(
        padding: EdgeInsets.all(cardPadding),
        child: Row(
          children: [
            // Icon / Thumbnail
            Container(
              width: iconBoxSize,
              height: iconBoxSize,
              decoration: BoxDecoration(
                color: isDark ? AppColors.darkSurface : Colors.white,
                borderRadius: BorderRadius.circular(iconBoxRadius),
              ),
              child: Center(
                      child: Icon(
                        isLectureMode ? Icons.play_circle_outline_rounded : Icons.description_outlined,
                        size: contentIconSize,
                        color: iconColor,
                      ),
                    ),
            ),
            SizedBox(width: contentGap),
            // Content
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    series.title,
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontWeight: FontWeight.w600,
                      fontSize: isTablet ? 18 : 14,
                      height: 1.3,
                      color: textColor,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  SizedBox(height: isTablet ? 6 : 4),
                  if (isLectureMode && (series.totalLectures ?? 0) > 0)
                    Text(
                      '${series.totalLectures} Lectures${series.formattedDuration != 'N/A' ? ' · ${series.formattedDuration}' : ''}',
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontWeight: FontWeight.w400,
                        fontSize: isTablet ? 15 : 12,
                        color: textColor.withValues(alpha: 0.5),
                      ),
                    )
                  else if ((series.totalDocuments ?? 0) > 0)
                    Text(
                      '${series.totalDocuments} Documents',
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontWeight: FontWeight.w400,
                        fontSize: isTablet ? 15 : 12,
                        color: textColor.withValues(alpha: 0.5),
                      ),
                    )
                  else if (series.documentsComingSoon)
                    Text(
                      series.documentsReleaseAt != null
                          ? 'Coming ${_formatReleaseDate(series.documentsReleaseAt!)}'
                          : 'Coming Soon',
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontWeight: FontWeight.w400,
                        fontStyle: FontStyle.italic,
                        fontSize: isTablet ? 15 : 12,
                        color: textColor.withValues(alpha: 0.4),
                      ),
                    ),
                ],
              ),
            ),
            // Lock icon for locked series
            if (isLocked) ...[
              SizedBox(width: isTablet ? 12 : 8),
              Container(
                width: lockBoxSize,
                height: lockBoxSize,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isDark ? AppColors.darkSurface : Colors.white,
                ),
                child: Center(child: Icon(Icons.lock_rounded, size: isTablet ? 22 : 16, color: iconColor)),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ── Loading Shimmer ──────────────────────────────────────────────────────

  Widget _buildLoadingShimmer(bool isDark) {
    final isTablet = ResponsiveHelper.isTablet(context);
    final hPad = isTablet ? 24.0 : 16.0;
    final cardHeight = isTablet ? 180.0 : 120.0;
    final radius = isTablet ? 18.0 : 12.0;

    // Show different shimmer based on current view mode
    if (_contentMode == 'lectures' || _contentMode == 'documents') {
      // Series list shimmer
      return ShimmerWidgets.seriesListShimmer(isDark: isDark);
    } else if (_activePackageId != null) {
      // Package detail shimmer (when viewing a specific package)
      return SingleChildScrollView(
        padding: EdgeInsets.all(hPad),
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: ResponsiveHelper.getMaxContentWidth(context)),
            child: Column(
              children: [
                // Two option cards
                Row(
                  children: [
                    Expanded(
                      child: ShimmerWidgets.container(
                        width: double.infinity,
                        height: cardHeight,
                        borderRadius: radius,
                        isDark: isDark,
                      ),
                    ),
                    SizedBox(width: isTablet ? 20 : 16),
                    Expanded(
                      child: ShimmerWidgets.container(
                        width: double.infinity,
                        height: cardHeight,
                        borderRadius: radius,
                        isDark: isDark,
                      ),
                    ),
                  ],
                ),
                SizedBox(height: isTablet ? 32 : 24),
                // Package info shimmer
                ShimmerWidgets.container(
                  width: double.infinity,
                  height: isTablet ? 260 : 200,
                  borderRadius: radius,
                  isDark: isDark,
                ),
                SizedBox(height: isTablet ? 20 : 16),
                ShimmerWidgets.container(
                  width: double.infinity,
                  height: isTablet ? 200 : 150,
                  borderRadius: radius,
                  isDark: isDark,
                ),
              ],
            ),
          ),
        ),
      );
    } else {
      // Landing page shimmer (packages grid)
      return SingleChildScrollView(
        padding: EdgeInsets.only(bottom: isTablet ? 120 : 100),
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: ResponsiveHelper.getMaxContentWidth(context)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header section
                Padding(
                  padding: EdgeInsets.all(hPad),
                  child: ShimmerWidgets.container(
                    width: isTablet ? 200 : 150,
                    height: isTablet ? 30 : 24,
                    borderRadius: isTablet ? 6 : 4,
                    isDark: isDark,
                  ),
                ),
                // Package grid shimmer
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: hPad),
                  child: GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      crossAxisSpacing: isTablet ? 18 : 12,
                      mainAxisSpacing: isTablet ? 18 : 12,
                      childAspectRatio: 0.75,
                    ),
                    itemCount: 4,
                    itemBuilder: (context, index) => ShimmerWidgets.gridItemShimmer(isDark: isDark),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }
  }

  // ── Coming Soon View ──────────────────────────────────────────────────

  Widget _buildComingSoonView(bool isDark, Color textColor, Color secondaryTextColor) {
    final isTablet = ResponsiveHelper.isTablet(context);
    return Center(
      child: Padding(
        padding: EdgeInsets.all(isTablet ? 32.0 : 24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.auto_awesome_rounded,
              size: isTablet ? 64 : 52,
              color: isDark ? const Color(0xFF00BEFA) : const Color(0xFF0000C8),
            ),
            SizedBox(height: isTablet ? 20 : 16),
            Text(
              'Content Coming Soon',
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: isTablet ? 22 : 18,
                fontWeight: FontWeight.w600,
                color: textColor,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Error View ────────────────────────────────────────────────────────

  Widget _buildErrorView(Color textColor, Color secondaryTextColor, Color iconColor) {
    final isTablet = ResponsiveHelper.isTablet(context);
    return Center(
      child: Padding(
        padding: EdgeInsets.all(isTablet ? 32.0 : 16.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: isTablet ? 64 : 48, color: textColor.withValues(alpha: 0.5)),
            SizedBox(height: isTablet ? 20 : 16),
            Text(
              'Failed to load data',
              style: TextStyle(fontFamily: 'Poppins', fontSize: isTablet ? 20 : 16, fontWeight: FontWeight.w600, color: textColor),
            ),
            SizedBox(height: isTablet ? 12 : 8),
            Text(
              _error!.replaceAll('Exception: ', ''),
              style: TextStyle(fontFamily: 'Poppins', fontSize: isTablet ? 17 : 14, color: secondaryTextColor),
              textAlign: TextAlign.center,
            ),
            SizedBox(height: isTablet ? 20 : 16),
            ElevatedButton(
              onPressed: _loadData,
              style: ElevatedButton.styleFrom(backgroundColor: iconColor),
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }

  // ── Helpers ───────────────────────────────────────────────────────────

  String _formatReleaseDate(String isoDate) {
    try {
      final date = DateTime.parse(isoDate);
      final months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
      return '${months[date.month - 1]} ${date.day}, ${date.year}';
    } catch (_) {
      return 'Soon';
    }
  }

  int _getTotalLectures() {
    int total = 0;
    for (final s in _series) {
      total += s.totalLectures ?? 0;
    }
    return total;
  }

  int _getTotalDocuments() {
    int total = 0;
    for (final s in _series) {
      total += s.totalDocuments ?? 0;
    }
    return total;
  }

  String _getTotalDuration() {
    int totalMinutes = 0;
    for (final s in _series) {
      totalMinutes += s.totalDurationMinutes ?? 0;
    }
    if (totalMinutes == 0) return '';
    final hours = totalMinutes ~/ 60;
    final mins = totalMinutes % 60;
    if (hours > 0) return '${hours}h${mins > 0 ? ' ${mins}m' : ''}';
    return '${mins}m';
  }

}
