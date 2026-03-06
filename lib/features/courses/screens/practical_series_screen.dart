import 'dart:io';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:pgme/core/providers/theme_provider.dart';
import 'package:pgme/core/theme/app_theme.dart';
import 'package:pgme/core/services/dashboard_service.dart';
import 'package:pgme/core/utils/web_store_launcher.dart';
import 'package:pgme/core/models/package_model.dart';
import 'package:pgme/core/models/live_session_model.dart';
import 'package:pgme/core/models/series_model.dart';
import 'package:pgme/features/home/providers/dashboard_provider.dart';
import 'package:pgme/core/widgets/shimmer_widgets.dart';
import 'package:pgme/core/utils/responsive_helper.dart';
import 'package:cached_network_image/cached_network_image.dart';

class PracticalSeriesScreen extends StatefulWidget {
  final bool isSubscribed;
  final String? packageId;

  const PracticalSeriesScreen({
    super.key,
    this.isSubscribed = false,
    this.packageId,
  });

  @override
  State<PracticalSeriesScreen> createState() => _PracticalSeriesScreenState();
}

class _PracticalSeriesScreenState extends State<PracticalSeriesScreen>
    with WidgetsBindingObserver {
  final DashboardService _dashboardService = DashboardService();

  List<LiveSessionModel> _liveSessions = [];
  List<PackageModel> _packages = [];
  List<SeriesModel> _series = [];
  PackageModel? _selectedPackage;
  bool _isLoading = true;
  String? _error;

  // null = package details view, 'videos' = series list, 'sessions' = live sessions list
  String? _contentMode;

  @override
  void initState() {
    super.initState();
    if (Platform.isIOS) WidgetsBinding.instance.addObserver(this);
    _loadData();
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
      _loadData();
    }
  }

  Future<void> _loadData() async {
    try {
      setState(() {
        _isLoading = true;
        _error = null;
      });

      final dashboardProvider = Provider.of<DashboardProvider>(context, listen: false);
      final primarySubjectId = dashboardProvider.primarySubject?.subjectId;

      // Fetch live sessions and packages in parallel
      final results = await Future.wait([
        _dashboardService.getLiveSessions(
          subjectId: primarySubjectId,
          upcomingOnly: true,
          limit: 20,
        ),
        _dashboardService.getPackages(
          subjectId: primarySubjectId,
          packageType: 'Practical',
        ),
      ]);

      final sessions = results[0] as List<LiveSessionModel>;
      final packages = results[1] as List<PackageModel>;

      setState(() {
        _liveSessions = sessions;
        _packages = packages;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _selectPackage(PackageModel package) async {
    setState(() {
      _selectedPackage = package;
      _isLoading = true;
      _error = null;
    });

    try {
      final result = await _dashboardService.getPackageSeries(package.packageId);
      setState(() {
        _series = result.series;
        // Update purchase status from fresh backend check
        if (result.isPurchased && !package.isPurchased) {
          _selectedPackage = package.copyWith(isPurchased: true);
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

  void _goBackToList() {
    setState(() {
      _selectedPackage = null;
      _series = [];
      _contentMode = null;
      _error = null;
    });
  }

  void _goBackToPackageDetail() {
    setState(() {
      _contentMode = null;
    });
  }

  void _showEnrollmentPopup() async {
    final themeProvider = Provider.of<ThemeProvider>(context, listen: false);
    final isDark = themeProvider.isDarkMode;

    final shouldEnroll = await showDialog<bool>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.5),
      builder: (dialogContext) => _buildEnrollmentDialog(dialogContext, isDark),
    );

    if (shouldEnroll == true && mounted && _selectedPackage != null) {
      if (WebStoreLauncher.shouldUseWebStore) {
        WebStoreLauncher.openProductPage(context, productType: 'packages', productId: _selectedPackage!.packageId);
      } else {
        context.push('/package-access?packageId=${_selectedPackage!.packageId}&packageType=Practical');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final topPadding = MediaQuery.of(context).padding.top;
    final themeProvider = Provider.of<ThemeProvider>(context);
    final isDark = themeProvider.isDarkMode;
    final isTablet = ResponsiveHelper.isTablet(context);
    final hPadding = isTablet ? ResponsiveHelper.horizontalPadding(context) : 16.0;

    final dashboardProvider = Provider.of<DashboardProvider>(context);
    // Use selected package's purchase status when viewing a specific package,
    // otherwise fall back to type-level subscription check for the landing page
    final isSubscribed = (_selectedPackage?.isPurchased ?? false) || dashboardProvider.hasPracticalSubscription || widget.isSubscribed;

    final backgroundColor = isDark ? AppColors.darkBackground : Colors.white;
    final textColor = isDark ? AppColors.darkTextPrimary : const Color(0xFF000000);
    final secondaryTextColor = isDark ? AppColors.darkTextSecondary : const Color(0xFF666666);
    final iconColor = isDark ? const Color(0xFF00BEFA) : const Color(0xFF2470E4);
    final cardBgColor = isDark ? AppColors.darkCardBackground : const Color(0xFFDCEAF7);

    final isOnLanding = _selectedPackage == null;
    final isOnPackageDetail = _selectedPackage != null && _contentMode == null;

    String title;
    if (isOnLanding) {
      title = 'Practical Series';
    } else if (isOnPackageDetail) {
      title = _selectedPackage!.name;
    } else if (_contentMode == 'videos') {
      title = 'Video Series';
    } else if (_contentMode == 'notes') {
      title = 'Study Notes';
    } else {
      title = 'Live Sessions';
    }

    return BackButtonListener(
      onBackButtonPressed: () async {
        if (_contentMode != null) {
          _goBackToPackageDetail();
          return true;
        } else if (_selectedPackage != null) {
          _goBackToList();
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
          if (didPop) return;
          if (_contentMode != null) {
            _goBackToPackageDetail();
          } else if (_selectedPackage != null) {
            _goBackToList();
          } else {
            context.go('/home');
          }
        },
        child: Scaffold(
        backgroundColor: backgroundColor,
        body: Column(
          children: [
            // App bar
            Padding(
              padding: EdgeInsets.only(top: topPadding + 12, left: hPadding, right: hPadding, bottom: 12),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () {
                      if (isOnLanding) {
                        context.go('/home');
                      } else if (_contentMode != null) {
                        _goBackToPackageDetail();
                      } else {
                        _goBackToList();
                      }
                    },
                    child: Padding(
                      padding: const EdgeInsets.only(right: 12),
                      child: Icon(Icons.arrow_back_rounded, size: isTablet ? 30 : 24, color: textColor),
                    ),
                  ),
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
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  // if (isOnLanding)
                  //   GestureDetector(
                  //     onTap: () {},
                  //     child: Icon(Icons.more_horiz, size: isTablet ? 30 : 24, color: textColor),
                  //   ),
                ],
              ),
            ),

            // Content
            Expanded(
              child: _isLoading
                  ? _buildLoadingShimmer(isDark)
                  : _error != null
                      ? _buildErrorView(textColor, secondaryTextColor, iconColor)
                      : isOnLanding
                          ? _buildPackagesList(isDark, textColor, secondaryTextColor, iconColor)
                          : _contentMode == 'videos'
                              ? _buildSeriesListView(isDark, textColor, secondaryTextColor, iconColor, cardBgColor, isSubscribed)
                              : _contentMode == 'sessions'
                                  ? _buildSessionsListView(isDark, textColor, secondaryTextColor, iconColor)
                                  : _contentMode == 'notes'
                                      ? _buildNotesSeriesListView(isDark, textColor, secondaryTextColor, iconColor, cardBgColor, isSubscribed)
                                      : _buildPackageDetailView(isDark, textColor, secondaryTextColor, iconColor, cardBgColor, isSubscribed),
            ),
          ],
        ),
      ),
      ),
    );
  }

  // ── Packages List View ───────────────────────────────────────────────────

  Widget _buildPackagesList(bool isDark, Color textColor, Color secondaryTextColor, Color iconColor) {
    final isTablet = ResponsiveHelper.isTablet(context);
    final hPadding = isTablet ? ResponsiveHelper.horizontalPadding(context) : 16.0;

    return SingleChildScrollView(
      padding: const EdgeInsets.only(bottom: 100),
      child: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: ResponsiveHelper.getMaxContentWidth(context)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 8),

              // Live Sessions Section
              if (_liveSessions.isNotEmpty) ...[
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: hPadding),
                  child: Text(
                    'Live Sessions',
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontWeight: FontWeight.w600,
                      fontSize: isTablet ? 24 : 18,
                      color: textColor,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  padding: EdgeInsets.symmetric(horizontal: hPadding),
                  itemCount: _liveSessions.length,
                  itemBuilder: (context, index) {
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _buildSessionCard(
                        _liveSessions[index],
                        isDark: isDark,
                        textColor: textColor,
                        secondaryTextColor: secondaryTextColor,
                      ),
                    );
                  },
                ),
                const SizedBox(height: 24),
              ],

              // Practical Packages Section
              if (_packages.isNotEmpty) ...[
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: hPadding),
                  child: Text(
                    'Practical Packages',
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontWeight: FontWeight.w600,
                      fontSize: isTablet ? 24 : 18,
                      color: textColor,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  padding: EdgeInsets.symmetric(horizontal: hPadding),
                  itemCount: _packages.length,
                  itemBuilder: (context, index) {
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _buildPackageCard(
                        _packages[index],
                        isDark: isDark,
                        textColor: textColor,
                        secondaryTextColor: secondaryTextColor,
                        iconColor: iconColor,
                      ),
                    );
                  },
                ),
              ],

              // Empty state
              if (_liveSessions.isEmpty && _packages.isEmpty)
                Center(
                  child: Padding(
                    padding: EdgeInsets.all(isTablet ? 48 : 32),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.science_outlined,
                          size: isTablet ? 80 : 64,
                          color: textColor.withValues(alpha: 0.3),
                        ),
                        const SizedBox(height: 16),
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
                ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Package Detail View (Two Options + Info) ─────────────────────────────

  Widget _buildPackageDetailView(
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

    final totalLectures = _series.fold<int>(0, (sum, s) => sum + (s.totalLectures ?? 0));
    // Count all live sessions since sessions aren't directly linked to packages
    final packageSessions = _liveSessions.length;
    final totalDocuments = _series.fold<int>(0, (sum, s) => sum + (s.totalDocuments ?? 0));

    // Build option cards conditionally based on available content
    final cardGap = isTablet ? 20.0 : 14.0;
    final cards = <Widget>[];
    if (totalLectures > 0) {
      cards.add(_buildOptionCard(
        title: 'Watch\nVideo Lectures',
        subtitle: '$totalLectures Lectures',
        icon: Icons.play_circle_outline_rounded,
        imagePath: 'assets/illustrations/1.png',
        isDark: isDark,
        gradientStart: gradientStart,
        gradientEnd: gradientEnd,
        onTap: () => setState(() => _contentMode = 'videos'),
      ));
    }
    if (packageSessions > 0) {
      cards.add(_buildOptionCard(
        title: 'View\nLive Sessions',
        subtitle: '$packageSessions Sessions',
        icon: Icons.videocam_outlined,
        imagePath: 'assets/illustrations/2.png',
        isDark: isDark,
        gradientStart: gradientStart,
        gradientEnd: gradientEnd,
        onTap: () => setState(() => _contentMode = 'sessions'),
      ));
    }
    if (totalDocuments > 0) {
      cards.add(_buildOptionCard(
        title: 'Read\nNotes',
        subtitle: '$totalDocuments Notes',
        icon: Icons.description_outlined,
        imagePath: 'assets/illustrations/3.png',
        isDark: isDark,
        gradientStart: gradientStart,
        gradientEnd: gradientEnd,
        onTap: () => setState(() => _contentMode = 'notes'),
      ));
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.only(bottom: 100),
      child: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: ResponsiveHelper.getMaxContentWidth(context)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 8),

              // Option cards — conditional layout based on count
              if (cards.isNotEmpty)
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: hPadding),
                  child: _buildOptionCardsLayout(cards, cardGap),
                ),

              const SizedBox(height: 28),

              // Package info section
              _buildPackageInfoSection(
                isDark,
                textColor,
                secondaryTextColor,
                iconColor,
                cardBgColor,
                isSubscribed,
                totalLectures,
                packageSessions,
                totalDocuments,
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Series List View ─────────────────────────────────────────────────────

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
            Icon(Icons.video_library_outlined, size: isTablet ? 60 : 48, color: textColor.withValues(alpha: 0.5)),
            const SizedBox(height: 16),
            Text(
              'Series Coming Soon',
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: isTablet ? 20 : 16,
                fontWeight: FontWeight.w600,
                color: textColor,
              ),
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
          itemCount: _series.length,
          itemBuilder: (context, index) {
            final series = _series[index];
            final isItemLocked = isSubscribed ? false : series.isLocked;

            return GestureDetector(
              onTap: () {
                if (isItemLocked) {
                  _showEnrollmentPopup();
                } else if (series.seriesId.isNotEmpty && _selectedPackage != null) {
                  // Navigate directly to lecture/modules screen instead of series detail
                  context.push(
                    '/lecture/${series.seriesId}?subscribed=$isSubscribed&packageType=Practical&packageId=${_selectedPackage!.packageId}',
                  );
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
    return Container(
      margin: EdgeInsets.only(bottom: isTablet ? 18 : 14),
      decoration: BoxDecoration(
        color: cardBgColor,
        borderRadius: BorderRadius.circular(isTablet ? 22 : 16),
      ),
      child: Padding(
        padding: EdgeInsets.all(isTablet ? 24 : 18),
        child: Row(
          children: [
            Container(
              width: isTablet ? 60 : 44,
              height: isTablet ? 60 : 44,
              decoration: BoxDecoration(
                color: isDark ? AppColors.darkSurface : Colors.white,
                borderRadius: BorderRadius.circular(isTablet ? 16 : 12),
              ),
              clipBehavior: Clip.antiAlias,
              child: series.thumbnailUrl != null
                  ? CachedNetworkImage(
                      imageUrl: series.thumbnailUrl!,
                      fit: BoxFit.cover,
                      width: isTablet ? 60 : 44,
                      height: isTablet ? 60 : 44,
                      placeholder: (context, url) => Center(
                        child: Icon(Icons.play_circle_outline_rounded, size: isTablet ? 30 : 22, color: iconColor),
                      ),
                      errorWidget: (context, url, error) => Center(
                        child: Icon(Icons.play_circle_outline_rounded, size: isTablet ? 30 : 22, color: iconColor),
                      ),
                    )
                  : Center(
                      child: Icon(Icons.play_circle_outline_rounded, size: isTablet ? 30 : 22, color: iconColor),
                    ),
            ),
            SizedBox(width: isTablet ? 18 : 14),
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
                  const SizedBox(height: 4),
                  Text(
                    '${series.totalLectures ?? 0} Lectures${series.formattedDuration != 'N/A' ? ' · ${series.formattedDuration}' : ''}',
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontWeight: FontWeight.w400,
                      fontSize: isTablet ? 15 : 12,
                      color: textColor.withValues(alpha: 0.5),
                    ),
                  ),
                ],
              ),
            ),
            // Lock icon for locked series
            if (isLocked) ...[
              const SizedBox(width: 8),
              Container(
                width: isTablet ? 42 : 32,
                height: isTablet ? 42 : 32,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isDark ? AppColors.darkSurface : Colors.white,
                ),
                child: Center(child: Icon(Icons.lock_rounded, size: isTablet ? 20 : 16, color: iconColor)),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ── Sessions List View ───────────────────────────────────────────────────

  Widget _buildSessionsListView(
    bool isDark,
    Color textColor,
    Color secondaryTextColor,
    Color iconColor,
  ) {
    final isTablet = ResponsiveHelper.isTablet(context);
    final hPadding = isTablet ? ResponsiveHelper.horizontalPadding(context) : 16.0;

    if (_liveSessions.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.videocam_outlined, size: isTablet ? 60 : 48, color: textColor.withValues(alpha: 0.4)),
            const SizedBox(height: 16),
            Text(
              'Sessions Coming Soon',
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: isTablet ? 20 : 16,
                fontWeight: FontWeight.w600,
                color: textColor,
              ),
            ),
          ],
        ),
      );
    }

    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: ResponsiveHelper.getMaxContentWidth(context)),
        child: ListView.builder(
          padding: EdgeInsets.symmetric(horizontal: hPadding, vertical: 8).copyWith(bottom: 100),
          itemCount: _liveSessions.length,
          itemBuilder: (context, index) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _buildSessionCard(
                _liveSessions[index],
                isDark: isDark,
                textColor: textColor,
                secondaryTextColor: secondaryTextColor,
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildOptionCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required String imagePath,
    required bool isDark,
    required Color gradientStart,
    required Color gradientEnd,
    required VoidCallback onTap,
  }) {
    final isTablet = ResponsiveHelper.isTablet(context);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: isTablet ? 280 : 180,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(isTablet ? 22 : 16),
          gradient: LinearGradient(
            begin: const Alignment(-0.5, -0.5),
            end: const Alignment(0.5, 0.5),
            colors: [gradientStart, gradientEnd],
          ),
        ),
        child: Stack(
          children: [
            Padding(
              padding: EdgeInsets.all(isTablet ? 24 : 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontWeight: FontWeight.w600,
                      fontSize: isTablet ? 22 : 16,
                      color: isDark ? Colors.white : const Color(0xFF000000),
                      height: 1.3,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Container(
                    padding: EdgeInsets.symmetric(horizontal: isTablet ? 14 : 10, vertical: isTablet ? 6 : 4),
                    decoration: BoxDecoration(
                      color: isDark ? AppColors.darkSurface : Colors.white,
                      borderRadius: BorderRadius.circular(isTablet ? 16 : 12),
                    ),
                    child: Text(
                      subtitle,
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontWeight: FontWeight.w500,
                        fontSize: isTablet ? 15 : 11,
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
                borderRadius: BorderRadius.only(bottomRight: Radius.circular(isTablet ? 22 : 16)),
                child: Image.asset(
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
                        borderRadius: BorderRadius.only(bottomRight: Radius.circular(isTablet ? 22 : 16)),
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

  Widget _buildOptionCardsLayout(List<Widget> cards, double gap) {
    if (cards.length == 1) {
      return Row(
        children: [
          Expanded(child: cards[0]),
          SizedBox(width: gap),
          const Expanded(child: SizedBox()),
        ],
      );
    }
    if (cards.length == 2) {
      return Row(
        children: [
          Expanded(child: cards[0]),
          SizedBox(width: gap),
          Expanded(child: cards[1]),
        ],
      );
    }
    // 3 cards: first two in a row, third below at half width
    return Column(
      children: [
        Row(
          children: [
            Expanded(child: cards[0]),
            SizedBox(width: gap),
            Expanded(child: cards[1]),
          ],
        ),
        SizedBox(height: gap),
        Row(
          children: [
            Expanded(child: cards[2]),
            SizedBox(width: gap),
            const Expanded(child: SizedBox()),
          ],
        ),
      ],
    );
  }

  // ── Notes Series List View ───────────────────────────────────────────────

  Widget _buildNotesSeriesListView(
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
            Icon(Icons.description_outlined, size: isTablet ? 60 : 48, color: textColor.withValues(alpha: 0.5)),
            const SizedBox(height: 16),
            Text(
              'Notes Coming Soon',
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: isTablet ? 20 : 16,
                fontWeight: FontWeight.w600,
                color: textColor,
              ),
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
          itemCount: _series.length,
          itemBuilder: (context, index) {
            final series = _series[index];
            final isItemLocked = isSubscribed ? false : series.isLocked;

            return GestureDetector(
              onTap: () {
                if (isItemLocked) {
                  _showEnrollmentPopup();
                } else if (series.seriesId.isNotEmpty) {
                  context.push('/available-notes?seriesId=${series.seriesId}&subscribed=$isSubscribed&packageId=${_selectedPackage!.packageId}');
                }
              },
              child: _buildNotesSeriesCard(
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

  Widget _buildNotesSeriesCard(
    SeriesModel series, {
    required bool isDark,
    required Color textColor,
    required Color cardBgColor,
    required Color iconColor,
    required bool isLocked,
  }) {
    final isTablet = ResponsiveHelper.isTablet(context);
    return Container(
      margin: EdgeInsets.only(bottom: isTablet ? 18 : 14),
      decoration: BoxDecoration(
        color: cardBgColor,
        borderRadius: BorderRadius.circular(isTablet ? 22 : 16),
      ),
      child: Padding(
        padding: EdgeInsets.all(isTablet ? 24 : 18),
        child: Row(
          children: [
            Container(
              width: isTablet ? 60 : 44,
              height: isTablet ? 60 : 44,
              decoration: BoxDecoration(
                color: isDark ? AppColors.darkSurface : Colors.white,
                borderRadius: BorderRadius.circular(isTablet ? 16 : 12),
              ),
              clipBehavior: Clip.antiAlias,
              child: series.thumbnailUrl != null
                  ? CachedNetworkImage(
                      imageUrl: series.thumbnailUrl!,
                      fit: BoxFit.cover,
                      width: isTablet ? 60 : 44,
                      height: isTablet ? 60 : 44,
                      placeholder: (context, url) => Center(
                        child: Icon(Icons.description_outlined, size: isTablet ? 30 : 22, color: iconColor),
                      ),
                      errorWidget: (context, url, error) => Center(
                        child: Icon(Icons.description_outlined, size: isTablet ? 30 : 22, color: iconColor),
                      ),
                    )
                  : Center(
                      child: Icon(Icons.description_outlined, size: isTablet ? 30 : 22, color: iconColor),
                    ),
            ),
            SizedBox(width: isTablet ? 18 : 14),
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
                  const SizedBox(height: 4),
                  Text(
                    '${series.totalDocuments ?? 0} Documents',
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontWeight: FontWeight.w400,
                      fontSize: isTablet ? 15 : 12,
                      color: textColor.withValues(alpha: 0.5),
                    ),
                  ),
                ],
              ),
            ),
            // Lock icon for locked series
            if (isLocked) ...[
              const SizedBox(width: 8),
              Container(
                width: isTablet ? 42 : 32,
                height: isTablet ? 42 : 32,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isDark ? AppColors.darkSurface : Colors.white,
                ),
                child: Center(child: Icon(Icons.lock_rounded, size: isTablet ? 20 : 16, color: iconColor)),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildPackageInfoSection(
    bool isDark,
    Color textColor,
    Color secondaryTextColor,
    Color iconColor,
    Color cardBgColor,
    bool isSubscribed,
    int totalLectures,
    int packageSessions,
    int totalDocuments,
  ) {
    final isTablet = ResponsiveHelper.isTablet(context);
    final hPadding = isTablet ? ResponsiveHelper.horizontalPadding(context) : 16.0;
    final pkg = _selectedPackage!;
    final totalDuration = _getTotalDuration();

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: hPadding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Package name
          Text(
            pkg.name,
            style: TextStyle(
              fontFamily: 'Poppins',
              fontWeight: FontWeight.w600,
              fontSize: isTablet ? 24 : 18,
              color: textColor,
            ),
          ),
          if (pkg.description != null && pkg.description!.isNotEmpty) ...[
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
                  icon: Icons.videocam_outlined,
                  value: '$packageSessions',
                  label: 'Sessions',
                  iconColor: iconColor,
                  textColor: textColor,
                  secondaryColor: secondaryTextColor,
                ),
                if (totalDocuments > 0) ...[
                  _buildStatDivider(isDark),
                  _buildStatItem(
                    icon: Icons.description_outlined,
                    value: '$totalDocuments',
                    label: 'Notes',
                    iconColor: iconColor,
                    textColor: textColor,
                    secondaryColor: secondaryTextColor,
                  ),
                ],
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
          if (pkg.isPurchased) ...[
            SizedBox(
              width: double.infinity,
              height: isTablet ? 60 : 48,
              child: ElevatedButton.icon(
                onPressed: () {
                  setState(() => _contentMode = 'videos');
                },
                icon: Icon(Icons.check_circle_outline, size: isTablet ? 22 : 20, color: Colors.white),
                label: Text(
                  'Enrolled',
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontWeight: FontWeight.w600,
                    fontSize: isTablet ? 20 : 16,
                    color: Colors.white,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: isDark ? const Color(0xFF2E7D32) : const Color(0xFF388E3C),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(isTablet ? 30 : 24),
                  ),
                  elevation: 0,
                ),
              ),
            ),
            const SizedBox(height: 20),
          ] else ...[
            Container(
              padding: EdgeInsets.all(isTablet ? 28 : 20),
              decoration: BoxDecoration(
                color: cardBgColor,
                borderRadius: BorderRadius.circular(isTablet ? 22 : 16),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      if (!Platform.isIOS) ...[
                        if (pkg.isOnSale && pkg.salePrice != null) ...[
                          Text(
                            '₹${pkg.salePrice}',
                            style: TextStyle(
                              fontFamily: 'Poppins',
                              fontWeight: FontWeight.w700,
                              fontSize: isTablet ? 30 : 24,
                              color: textColor,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '₹${pkg.price}',
                            style: TextStyle(
                              fontFamily: 'Poppins',
                              fontWeight: FontWeight.w400,
                              fontSize: isTablet ? 18 : 16,
                              decoration: TextDecoration.lineThrough,
                              color: secondaryTextColor,
                            ),
                          ),
                        ] else
                          Text(
                            '₹${pkg.price}',
                            style: TextStyle(
                              fontFamily: 'Poppins',
                              fontWeight: FontWeight.w700,
                              fontSize: isTablet ? 30 : 24,
                              color: textColor,
                            ),
                          ),
                      ],
                      if (pkg.durationDays != null) ...[
                        const SizedBox(width: 8),
                        Text(
                          '/ ${_formatDuration(pkg.durationDays!)}',
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            fontWeight: FontWeight.w400,
                            fontSize: isTablet ? 14 : 12,
                            color: secondaryTextColor,
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    height: isTablet ? 60 : 48,
                    child: ElevatedButton(
                      onPressed: () {
                        if (WebStoreLauncher.shouldUseWebStore) {
                          WebStoreLauncher.openProductPage(context, productType: 'packages', productId: pkg.packageId);
                        } else {
                          context.push('/package-access?packageId=${pkg.packageId}&packageType=Practical');
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: isDark ? const Color(0xFF0047CF) : const Color(0xFF0000D1),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(isTablet ? 30 : 24),
                        ),
                        elevation: 0,
                      ),
                      child: Text(
                        Platform.isIOS ? 'Learn More' : 'Enroll Now',
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          fontWeight: FontWeight.w500,
                          fontSize: isTablet ? 20 : 16,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
          ],

          // What's included / Features
          if (pkg.features != null && pkg.features!.isNotEmpty) ...[
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
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.check_circle_rounded, size: isTablet ? 22 : 18, color: iconColor),
                      const SizedBox(width: 10),
                      Expanded(
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
                      ),
                    ],
                  ),
                )),
            const SizedBox(height: 16),
          ],

          // // Series overview
          // if (_series.isNotEmpty) ...[
          //   Text(
          //     'Series',
          //     style: TextStyle(
          //       fontFamily: 'Poppins',
          //       fontWeight: FontWeight.w600,
          //       fontSize: isTablet ? 20 : 16,
          //       color: textColor,
          //     ),
          //   ),
          //   const SizedBox(height: 12),
          //   ..._series.map((s) => _buildSeriesPreviewTile(
          //         s,
          //         isDark,
          //         textColor,
          //         secondaryTextColor,
          //         iconColor,
          //       )),
          // ],
        ],
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
      color: isDark
          ? Colors.white.withValues(alpha: 0.1)
          : Colors.black.withValues(alpha: 0.1),
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
    return Container(
      margin: EdgeInsets.only(bottom: isTablet ? 12 : 10),
      padding: EdgeInsets.symmetric(horizontal: isTablet ? 18 : 14, vertical: isTablet ? 16 : 12),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface : const Color(0xFFF8F9FA),
        borderRadius: BorderRadius.circular(isTablet ? 16 : 12),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.06)
              : Colors.black.withValues(alpha: 0.06),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: isTablet ? 48 : 36,
            height: isTablet ? 48 : 36,
            decoration: BoxDecoration(
              color: isDark
                  ? AppColors.darkCardBackground
                  : const Color(0xFFE8F0FE),
              borderRadius: BorderRadius.circular(isTablet ? 12 : 10),
            ),
            child: Center(
              child: Icon(Icons.science_outlined, size: isTablet ? 22 : 18, color: iconColor),
            ),
          ),
          SizedBox(width: isTablet ? 14 : 12),
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
                const SizedBox(height: 2),
                Text(
                  '${series.totalLectures ?? 0} lectures${series.formattedDuration != 'N/A' ? ' · ${series.formattedDuration}' : ''}',
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
            Icon(Icons.lock_rounded, size: isTablet ? 20 : 16, color: secondaryTextColor),
        ],
      ),
    );
  }

  // ── Package Card (for list view) ─────────────────────────────────────────

  Widget _buildPackageCard(
    PackageModel package, {
    required bool isDark,
    required Color textColor,
    required Color secondaryTextColor,
    required Color iconColor,
  }) {
    final isTablet = ResponsiveHelper.isTablet(context);
    final isPurchased = package.isPurchased;
    final gradientStart = isDark ? const Color(0xFF1A3A5C) : const Color(0xFFCDE5FF);
    final gradientEnd = isDark ? const Color(0xFF2D5A9E) : const Color(0xFF8FC6FF);

    return GestureDetector(
      onTap: () => _selectPackage(package),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(isTablet ? 22 : 16),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [gradientStart, gradientEnd],
          ),
        ),
        child: Padding(
          padding: EdgeInsets.all(isTablet ? 28 : 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header row: title + status badge
              Row(
                children: [
                  Expanded(
                    child: Text(
                      package.name,
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontWeight: FontWeight.w600,
                        fontSize: isTablet ? 22 : 18,
                        color: isDark ? Colors.white : const Color(0xFF000000),
                      ),
                    ),
                  ),
                  if (isPurchased)
                    Container(
                      padding: EdgeInsets.symmetric(horizontal: isTablet ? 14 : 10, vertical: isTablet ? 6 : 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFF4CAF50),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        'Active',
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          fontWeight: FontWeight.w500,
                          fontSize: isTablet ? 13 : 11,
                          color: Colors.white,
                        ),
                      ),
                    ),
                ],
              ),

              if (package.description != null && package.description!.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  package.description!,
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontWeight: FontWeight.w400,
                    fontSize: isTablet ? 16 : 13,
                    height: 1.4,
                    color: (isDark ? Colors.white : const Color(0xFF000000))
                        .withValues(alpha: 0.6),
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],

              const SizedBox(height: 16),

              // Features chips
              if (package.features != null && package.features!.isNotEmpty)
                Wrap(
                  spacing: isTablet ? 10 : 8,
                  runSpacing: isTablet ? 10 : 8,
                  children: package.features!.take(3).map((feature) {
                    return Container(
                      padding: EdgeInsets.symmetric(horizontal: isTablet ? 14 : 10, vertical: isTablet ? 7 : 5),
                      decoration: BoxDecoration(
                        color: isDark
                            ? AppColors.darkSurface.withValues(alpha: 0.7)
                            : Colors.white.withValues(alpha: 0.7),
                        borderRadius: BorderRadius.circular(isTablet ? 10 : 8),
                      ),
                      child: Text(
                        feature,
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          fontWeight: FontWeight.w400,
                          fontSize: isTablet ? 13 : 11,
                          color: isDark ? Colors.white : const Color(0xFF333333),
                        ),
                      ),
                    );
                  }).toList(),
                ),

              const SizedBox(height: 16),

              // Price + action row
              Row(
                children: [
                  if (!isPurchased && !Platform.isIOS) ...[
                    if (package.isOnSale && package.salePrice != null) ...[
                      Text(
                        '₹${package.salePrice}',
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          fontWeight: FontWeight.w700,
                          fontSize: isTablet ? 26 : 20,
                          color: isDark ? Colors.white : const Color(0xFF000000),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '₹${package.price}',
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          fontWeight: FontWeight.w400,
                          fontSize: isTablet ? 15 : 13,
                          decoration: TextDecoration.lineThrough,
                          color: (isDark ? Colors.white : const Color(0xFF000000))
                              .withValues(alpha: 0.4),
                        ),
                      ),
                    ] else
                      Text(
                        '₹${package.price}',
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          fontWeight: FontWeight.w700,
                          fontSize: isTablet ? 26 : 20,
                          color: isDark ? Colors.white : const Color(0xFF000000),
                        ),
                      ),
                    if (package.durationDays != null) ...[
                      const SizedBox(width: 6),
                      Text(
                        '/ ${_formatDuration(package.durationDays!)}',
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          fontWeight: FontWeight.w400,
                          fontSize: isTablet ? 14 : 12,
                          color: (isDark ? Colors.white : const Color(0xFF000000))
                              .withValues(alpha: 0.5),
                        ),
                      ),
                    ],
                  ],
                  const Spacer(),
                  Container(
                    padding: EdgeInsets.symmetric(horizontal: isTablet ? 20 : 16, vertical: isTablet ? 10 : 8),
                    decoration: BoxDecoration(
                      color: isDark ? AppColors.darkSurface : Colors.white,
                      borderRadius: BorderRadius.circular(isTablet ? 24 : 20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          isPurchased ? 'View' : 'Explore',
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            fontWeight: FontWeight.w500,
                            fontSize: isTablet ? 16 : 13,
                            color: iconColor,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Icon(Icons.arrow_forward_rounded, size: isTablet ? 20 : 16, color: iconColor),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Session Card ─────────────────────────────────────────────────────────

  Widget _buildSessionCard(
    LiveSessionModel session, {
    required bool isDark,
    required Color textColor,
    required Color secondaryTextColor,
  }) {
    final isTablet = ResponsiveHelper.isTablet(context);
    final isLive = session.status == 'live';

    return GestureDetector(
      onTap: () => context.push('/session/${session.sessionId}'),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(isTablet ? 24 : 18),
          gradient: LinearGradient(
            begin: const Alignment(-0.85, 0),
            end: const Alignment(0.85, 0),
            colors: isDark
                ? [const Color(0xFF0D2A5C), const Color(0xFF2D5A9E)]
                : [const Color(0xFF1847A2), const Color(0xFF8EC6FF)],
            stops: const [0.35, 0.71],
          ),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(isTablet ? 24 : 18),
          child: Stack(
            children: [
              // Background illustration
              Positioned(
                right: -5,
                bottom: 5,
                child: Image.asset(
                  'assets/illustrations/home.png',
                  width: isTablet ? 180 : 130,
                  height: isTablet ? 100 : 70,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => SizedBox(width: isTablet ? 180 : 130, height: isTablet ? 100 : 70),
                ),
              ),

              // Content
              Padding(
                padding: EdgeInsets.all(isTablet ? 20 : 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Status badge
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: isLive
                            ? Colors.red.withValues(alpha: 0.9)
                            : Colors.white.withValues(alpha: 0.25),
                        borderRadius: BorderRadius.circular(7),
                      ),
                      child: Text(
                        isLive ? 'LIVE NOW' : 'LIVE CLASS',
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          fontWeight: FontWeight.w500,
                          fontSize: isTablet ? 13 : 10,
                          color: Colors.white,
                        ),
                      ),
                    ),

                    const SizedBox(height: 8),

                    // Title
                    Text(
                      session.title,
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontWeight: FontWeight.w700,
                        fontSize: isTablet ? 20 : 16,
                        color: Colors.white,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),

                    const SizedBox(height: 2),

                    // Timing
                    Text(
                      isLive ? 'Live Now' : _formatSessionDateTime(session.scheduledStartTime),
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontWeight: FontWeight.w400,
                        fontSize: isTablet ? 15 : 12,
                        color: Colors.white.withValues(alpha: 0.85),
                      ),
                    ),

                    const SizedBox(height: 16),

                    // View Details button
                    Container(
                      padding: EdgeInsets.symmetric(horizontal: isTablet ? 18 : 14, vertical: isTablet ? 7 : 5),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(isTablet ? 10 : 8),
                      ),
                      child: Text(
                        'View Details',
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          fontWeight: FontWeight.w500,
                          fontSize: isTablet ? 14 : 11,
                          color: const Color(0xFF1847A2),
                        ),
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

  // ── Enrollment Dialog ────────────────────────────────────────────────────

  Widget _buildEnrollmentDialog(BuildContext dialogContext, bool isDark) {
    final isTablet = ResponsiveHelper.isTablet(context);
    final pkg = _selectedPackage!;
    final dialogBgColor = isDark ? AppColors.darkSurface : Colors.white;
    final textColor = isDark ? AppColors.darkTextPrimary : const Color(0xFF000000);
    final secondaryTextColor = isDark ? AppColors.darkTextSecondary : const Color(0xFF666666);
    final boxBgColor = isDark ? AppColors.darkCardBackground : const Color(0xFFF5F5F5);
    final iconColor = isDark ? const Color(0xFF00BEFA) : const Color(0xFF2470E4);
    final buttonColor = isDark ? const Color(0xFF0047CF) : const Color(0xFF0000D1);

    final displayPrice = pkg.isOnSale && pkg.salePrice != null ? pkg.salePrice! : pkg.price;

    // Tablet-scaled dimensions
    final dialogWidth = isTablet ? 500.0 : 356.0;
    final dialogRadius = isTablet ? 28.0 : 20.8;
    final closePad = isTablet ? 16.0 : 12.0;
    final closeSize = isTablet ? 28.0 : 24.0;
    final imgWidth = isTablet ? 260.0 : 180.0;
    final imgHeight = isTablet ? 180.0 : 120.0;
    final titleSize = isTablet ? 26.0 : 20.0;
    final descSize = isTablet ? 16.0 : 14.0;
    final descPadH = isTablet ? 36.0 : 24.0;
    final boxMarginH = isTablet ? 32.0 : 20.0;
    final boxPad = isTablet ? 24.0 : 16.0;
    final boxRadius = isTablet ? 18.0 : 12.0;
    final featureIconSize = isTablet ? 22.0 : 18.0;
    final featureTextSize = isTablet ? 16.0 : 13.0;
    final featureGap = isTablet ? 12.0 : 8.0;
    final featureIconGap = isTablet ? 12.0 : 8.0;
    final priceSize = isTablet ? 30.0 : 24.0;
    final durationSize = isTablet ? 15.0 : 12.0;
    final btnHeight = isTablet ? 56.0 : 40.0;
    final btnFontSize = isTablet ? 19.0 : 16.0;
    final btnRadius = isTablet ? 28.0 : 22.0;

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: EdgeInsets.symmetric(horizontal: isTablet ? 40 : 24, vertical: isTablet ? 48 : 40),
      child: Container(
        width: dialogWidth,
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height - (isTablet ? 100 : 80)),
        decoration: BoxDecoration(color: dialogBgColor, borderRadius: BorderRadius.circular(dialogRadius)),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Align(
                alignment: Alignment.topRight,
                child: Padding(
                  padding: EdgeInsets.only(top: closePad, right: closePad),
                  child: GestureDetector(
                    onTap: () => Navigator.of(dialogContext).pop(false),
                    child: Icon(Icons.close, size: closeSize, color: secondaryTextColor),
                  ),
                ),
              ),
              Image.asset(
                'assets/illustrations/enroll.png',
                width: imgWidth,
                height: imgHeight,
                fit: BoxFit.contain,
                errorBuilder: (context, error, stackTrace) {
                  return Container(
                    width: imgWidth,
                    height: imgHeight,
                    decoration: BoxDecoration(
                      color: isDark ? AppColors.darkCardBackground : const Color(0xFFDCEAF7),
                      borderRadius: BorderRadius.circular(isTablet ? 16 : 12),
                    ),
                    child: Icon(Icons.school_outlined, size: isTablet ? 80 : 60, color: iconColor),
                  );
                },
              ),
              SizedBox(height: isTablet ? 20 : 16),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: descPadH),
                child: Text(
                  Platform.isIOS ? 'View ${pkg.name}' : 'Get ${pkg.name}',
                  style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w600, fontSize: titleSize, color: textColor),
                  textAlign: TextAlign.center,
                ),
              ),
              SizedBox(height: isTablet ? 12 : 8),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: descPadH),
                child: Text(
                  pkg.description ?? 'Unlock all series and get access to hands-on training materials.',
                  style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w400, fontSize: descSize, height: 1.4, color: secondaryTextColor),
                  textAlign: TextAlign.center,
                ),
              ),
              SizedBox(height: isTablet ? 24 : 20),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: boxMarginH),
                child: Container(
                  width: double.infinity,
                  padding: EdgeInsets.all(boxPad),
                  decoration: BoxDecoration(color: boxBgColor, borderRadius: BorderRadius.circular(boxRadius)),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (pkg.features != null)
                        ...pkg.features!.map((f) => Padding(
                              padding: EdgeInsets.only(bottom: featureGap),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Icon(Icons.check_circle, size: featureIconSize, color: iconColor),
                                  SizedBox(width: featureIconGap),
                                  Expanded(child: Text(f, style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w400, fontSize: featureTextSize, height: 1.3, color: textColor))),
                                ],
                              ),
                            )),
                      SizedBox(height: isTablet ? 12 : 8),
                      Row(
                        children: [
                          if (!Platform.isIOS) Text('₹$displayPrice', style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w700, fontSize: priceSize, color: textColor)),
                          if (pkg.durationDays != null) ...[
                            SizedBox(width: isTablet ? 10 : 8),
                            Text('/ ${_formatDuration(pkg.durationDays!)}', style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w400, fontSize: durationSize, color: secondaryTextColor)),
                          ],
                        ],
                      ),
                      SizedBox(height: isTablet ? 20 : 16),
                      SizedBox(
                        width: double.infinity,
                        height: btnHeight,
                        child: ElevatedButton(
                          onPressed: () => Navigator.of(dialogContext).pop(true),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: buttonColor,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(btnRadius)),
                            elevation: 0,
                          ),
                          child: Text(Platform.isIOS ? 'Learn More' : 'Enroll Now', style: TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w500, fontSize: btnFontSize, color: Colors.white)),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              SizedBox(height: isTablet ? 48 : 40),
            ],
          ),
        ),
      ),
    );
  }

  // ── Loading Shimmer ──────────────────────────────────────────────────────

  Widget _buildLoadingShimmer(bool isDark) {
    final isTablet = ResponsiveHelper.isTablet(context);
    final hPadding = isTablet ? ResponsiveHelper.horizontalPadding(context) : 16.0;
    final shimmerRadius = isTablet ? 20.0 : 12.0;

    // Show different shimmer based on current view mode
    if (_contentMode == 'videos' || _contentMode == 'notes') {
      // Series list shimmer
      return ShimmerWidgets.seriesListShimmer(isDark: isDark);
    } else if (_contentMode == 'sessions') {
      // Sessions list shimmer
      return Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: ResponsiveHelper.getMaxContentWidth(context)),
          child: ListView.builder(
            padding: EdgeInsets.symmetric(horizontal: hPadding),
            itemCount: 4,
            itemBuilder: (context, index) => ShimmerWidgets.sessionCardShimmer(isDark: isDark),
          ),
        ),
      );
    } else if (_selectedPackage != null) {
      // Package detail shimmer
      return Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: ResponsiveHelper.getMaxContentWidth(context)),
          child: SingleChildScrollView(
            padding: EdgeInsets.all(hPadding),
            child: Column(
              children: [
                // Two option cards
                Row(
                  children: [
                    Expanded(
                      child: ShimmerWidgets.container(
                        width: double.infinity,
                        height: isTablet ? 160 : 120,
                        borderRadius: shimmerRadius,
                        isDark: isDark,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: ShimmerWidgets.container(
                        width: double.infinity,
                        height: isTablet ? 160 : 120,
                        borderRadius: shimmerRadius,
                        isDark: isDark,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                // Package info shimmer
                ShimmerWidgets.container(
                  width: double.infinity,
                  height: isTablet ? 240 : 200,
                  borderRadius: shimmerRadius,
                  isDark: isDark,
                ),
                const SizedBox(height: 16),
                ShimmerWidgets.container(
                  width: double.infinity,
                  height: isTablet ? 180 : 150,
                  borderRadius: shimmerRadius,
                  isDark: isDark,
                ),
              ],
            ),
          ),
        ),
      );
    } else {
      // Landing page shimmer (packages + sessions)
      return Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: ResponsiveHelper.getMaxContentWidth(context)),
          child: SingleChildScrollView(
            padding: const EdgeInsets.only(bottom: 100),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Live Sessions section
                Padding(
                  padding: EdgeInsets.all(hPadding),
                  child: ShimmerWidgets.container(
                    width: 150,
                    height: 20,
                    borderRadius: 4,
                    isDark: isDark,
                  ),
                ),
                SizedBox(
                  height: isTablet ? 240 : 200,
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    padding: EdgeInsets.symmetric(horizontal: hPadding),
                    itemCount: 2,
                    itemBuilder: (context, index) => Padding(
                      padding: EdgeInsets.only(right: index == 1 ? 0 : 12),
                      child: ShimmerWidgets.container(
                        width: isTablet ? 380 : 300,
                        height: isTablet ? 240 : 200,
                        borderRadius: isTablet ? 22.0 : 16.0,
                        isDark: isDark,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                // Practical Packages section
                Padding(
                  padding: EdgeInsets.all(hPadding),
                  child: ShimmerWidgets.container(
                    width: 150,
                    height: 20,
                    borderRadius: 4,
                    isDark: isDark,
                  ),
                ),
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: hPadding),
                  child: Column(
                    children: List.generate(
                      3,
                      (index) => Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: ShimmerWidgets.container(
                          width: double.infinity,
                          height: isTablet ? 170 : 140,
                          borderRadius: shimmerRadius,
                          isDark: isDark,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }
  }

  // ── Error View ───────────────────────────────────────────────────────────

  Widget _buildErrorView(Color textColor, Color secondaryTextColor, Color iconColor) {
    final isTablet = ResponsiveHelper.isTablet(context);
    return Center(
      child: Padding(
        padding: EdgeInsets.all(isTablet ? 24.0 : 16.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: isTablet ? 60 : 48, color: textColor.withValues(alpha: 0.5)),
            const SizedBox(height: 16),
            Text(
              'Failed to load data',
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: isTablet ? 20 : 16,
                fontWeight: FontWeight.w600,
                color: textColor,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _error!.replaceAll('Exception: ', ''),
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: isTablet ? 16 : 14,
                color: secondaryTextColor,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _loadData,
              style: ElevatedButton.styleFrom(
                backgroundColor: iconColor,
                padding: EdgeInsets.symmetric(horizontal: isTablet ? 28 : 20, vertical: isTablet ? 14 : 10),
              ),
              child: Text(
                'Retry',
                style: TextStyle(fontSize: isTablet ? 16 : 14),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Helper Methods ───────────────────────────────────────────────────────

  String _getTotalDuration() {
    int totalMinutes = 0;
    for (final series in _series) {
      if (series.totalDurationMinutes != null) {
        totalMinutes += series.totalDurationMinutes!;
      }
    }
    if (totalMinutes == 0) return '';

    final hours = totalMinutes ~/ 60;
    if (hours > 0) {
      return '${hours}h';
    }
    return '${totalMinutes}m';
  }

  String _formatSessionDateTime(String isoString) {
    try {
      final dt = DateTime.parse(isoString).toLocal();
      final now = DateTime.now();
      final hour = dt.hour > 12 ? dt.hour - 12 : (dt.hour == 0 ? 12 : dt.hour);
      final minute = dt.minute.toString().padLeft(2, '0');
      final period = dt.hour >= 12 ? 'PM' : 'AM';
      final time = '$hour:$minute $period';

      if (dt.year == now.year && dt.month == now.month && dt.day == now.day) {
        return 'Today, $time';
      }

      final tomorrow = now.add(const Duration(days: 1));
      if (dt.year == tomorrow.year &&
          dt.month == tomorrow.month &&
          dt.day == tomorrow.day) {
        return 'Tomorrow, $time';
      }

      const months = [
        'Jan',
        'Feb',
        'Mar',
        'Apr',
        'May',
        'Jun',
        'Jul',
        'Aug',
        'Sep',
        'Oct',
        'Nov',
        'Dec'
      ];
      return '${months[dt.month - 1]} ${dt.day}, $time';
    } catch (_) {
      return 'Upcoming';
    }
  }

  String _formatDuration(int days) {
    if (days >= 365) {
      final years = days ~/ 365;
      return '$years year${years > 1 ? 's' : ''}';
    } else if (days >= 30) {
      final months = days ~/ 30;
      return '$months month${months > 1 ? 's' : ''}';
    }
    return '$days days';
  }
}
