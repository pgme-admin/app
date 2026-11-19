import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:pgme/core_ios/providers/theme_provider.dart';
import 'package:pgme/core_ios/theme/app_theme.dart';
import 'package:pgme/core_ios/services/dashboard_service.dart';
import 'package:pgme/core_ios/utils/web_store_launcher.dart';
import 'package:pgme/core_ios/models/series_document_model.dart';
import 'package:pgme/core_ios/models/series_model.dart';
import 'package:pgme/core_ios/models/package_model.dart';
import 'package:pgme/core_ios/widgets/shimmer_widgets.dart';
import 'package:pgme/core_ios/utils/responsive_helper.dart';
import 'package:pgme/core_ios/widgets/app_dialog.dart';
import 'package:pgme/core_ios/widgets/tutorial_section_widget.dart';

class AvailableNotesScreen extends StatefulWidget {
  final String seriesId;
  final bool isSubscribed;
  final String? packageId;

  const AvailableNotesScreen({
    super.key,
    required this.seriesId,
    this.isSubscribed = false,
    this.packageId,
  });

  @override
  State<AvailableNotesScreen> createState() => _AvailableNotesScreenState();
}

class _AvailableNotesScreenState extends State<AvailableNotesScreen> {
  final DashboardService _dashboardService = DashboardService();

  List<SeriesDocumentModel> _documents = [];
  SeriesModel? _series;
  PackageModel? _package;
  bool _isLoading = true;
  String? _error;
  Set<String> _addedToLibrary = {}; // Track which documents have been added
  bool _isAddingToLibrary = false;

  int? _expandedIndex = 0; // First card expanded by default

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      // Fetch series details and documents in parallel
      final results = await Future.wait([
        _dashboardService.getSeriesDetails(widget.seriesId),
        _dashboardService.getSeriesDocuments(widget.seriesId),
      ]);

      final series = results[0] as SeriesModel;
      final documents = results[1] as List<SeriesDocumentModel>;

      // Fetch package for enrollment dialog
      // Use widget.packageId if passed explicitly, otherwise use package_id from series details
      PackageModel? package;
      final lookupPackageId = widget.packageId ?? series.packageId;
      if (lookupPackageId != null) {
        try {
          final packages = await _dashboardService.getPackages(forceRefresh: true);
          final matching = packages.where((p) => p.packageId == lookupPackageId);
          if (matching.isNotEmpty) {
            package = matching.first;
          }
        } catch (e) {
          debugPrint('Failed to load package: $e');
        }
      }

      if (mounted) {
        setState(() {
          _series = series;
          _documents = documents;
          _package = package;
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
        final packageId = _package?.packageId ?? _series?.packageId ?? '';
        WebStoreLauncher.openProductPage(context, productType: 'packages', productId: packageId);
      } else if (_package != null) {
        context.push('/package-access?packageId=${_package!.packageId}&packageType=${_package!.type ?? 'Theory'}');
      } else if (_series?.packageId != null) {
        context.push('/package-access?packageId=${_series!.packageId}');
      } else {
        context.push('/all-packages');
      }
    }
  }

  Widget _buildEnrollmentDialog(BuildContext dialogContext, bool isDark) {
    final isTablet = ResponsiveHelper.isTablet(context);
    final dialogBgColor = isDark ? AppColors.darkSurface : Colors.white;
    final textColor = isDark ? AppColors.darkTextPrimary : const Color(0xFF000000);
    final secondaryTextColor = isDark ? AppColors.darkTextSecondary : const Color(0xFF666666);
    final boxBgColor = isDark ? AppColors.darkCardBackground : Colors.white;
    final borderColor = isDark ? AppColors.darkDivider : const Color(0xFFE0E0E0);
    final iconColor = isDark ? const Color(0xFF00BEFA) : const Color(0xFF2470E4);
    final buttonColor = isDark ? const Color(0xFF0047CF) : const Color(0xFF0000D1);
    final featureBgColor = isDark ? AppColors.darkCardBackground : const Color(0xFFE8F4FF);

    final dialogWidth = isTablet ? 480.0 : 356.0;
    final dialogRadius = isTablet ? 28.0 : 20.8;
    final closePad = isTablet ? 16.0 : 12.0;
    final closeSize = isTablet ? 28.0 : 24.0;
    final imgWidth = isTablet ? 240.0 : 180.0;
    final imgHeight = isTablet ? 160.0 : 120.0;
    final titleSize = isTablet ? 20.0 : 16.0;
    final descSize = isTablet ? 15.0 : 12.0;
    final descPadH = isTablet ? 48.0 : 40.0;
    final boxMarginH = isTablet ? 24.0 : 18.0;
    final boxPad = isTablet ? 22.0 : 16.0;
    final boxRadius = isTablet ? 16.0 : 10.93;
    final pkgNameSize = isTablet ? 18.0 : 14.0;
    final priceSize = isTablet ? 28.0 : 22.57;
    final strikePriceSize = isTablet ? 19.0 : 16.0;
    final durationSize = isTablet ? 17.0 : 14.0;
    final offerSize = isTablet ? 15.0 : 12.0;
    final btnHeight = isTablet ? 52.0 : 40.0;
    final btnFontSize = isTablet ? 19.0 : 16.0;
    final btnRadius = isTablet ? 26.0 : 22.0;
    final btnPadH = isTablet ? 22.0 : 16.0;

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: EdgeInsets.symmetric(horizontal: isTablet ? 40 : 24, vertical: isTablet ? 48 : 40),
      child: Container(
        width: dialogWidth,
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height - (isTablet ? 100 : 80),
        ),
        decoration: BoxDecoration(
          color: dialogBgColor,
          borderRadius: BorderRadius.circular(dialogRadius),
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
            // Close button
            Align(
              alignment: Alignment.topRight,
              child: Padding(
                padding: EdgeInsets.only(top: closePad, right: closePad),
                child: GestureDetector(
                  onTap: () => Navigator.of(dialogContext).pop(false),
                  child: Icon(
                    Icons.close,
                    size: closeSize,
                    color: secondaryTextColor,
                  ),
                ),
              ),
            ),

            // Illustration
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
                    color: featureBgColor,
                    borderRadius: BorderRadius.circular(isTablet ? 16 : 12),
                  ),
                  child: Icon(
                    Icons.play_circle_outline,
                    size: isTablet ? 80 : 60,
                    color: iconColor,
                  ),
                );
              },
            ),

            SizedBox(height: isTablet ? 20 : 16),

            // Title
            Text(
              _package != null ? 'View\n${_package!.name}' : 'View\nPackage',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'Poppins',
                fontWeight: FontWeight.w500,
                fontSize: titleSize,
                height: 1.1,
                letterSpacing: -0.18,
                color: textColor,
              ),
            ),

            SizedBox(height: isTablet ? 16 : 12),

            // Description
            Padding(
              padding: EdgeInsets.symmetric(horizontal: descPadH),
              child: Text(
                _package?.description ?? 'Access all modules, recorded lectures, and expert study resources',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontWeight: FontWeight.w400,
                  fontSize: descSize,
                  height: 1.05,
                  letterSpacing: -0.18,
                  color: secondaryTextColor,
                ),
              ),
            ),

            SizedBox(height: isTablet ? 22 : 16),

            // Package details box
            Container(
              margin: EdgeInsets.symmetric(horizontal: boxMarginH),
              padding: EdgeInsets.all(boxPad),
              decoration: BoxDecoration(
                color: boxBgColor,
                borderRadius: BorderRadius.circular(boxRadius),
                border: Border.all(
                  color: borderColor,
                  width: 1,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _package?.name ?? 'Package',
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontWeight: FontWeight.w600,
                      fontSize: pkgNameSize,
                      color: textColor,
                    ),
                  ),
                  SizedBox(height: isTablet ? 16 : 12),
                  ...(_package?.features?.isNotEmpty == true
                      ? _package!.features!.take(3).map((feature) =>
                          Padding(
                            padding: EdgeInsets.only(bottom: isTablet ? 10 : 8),
                            child: _buildFeatureItem(feature, isDark, isTablet, textColor, iconColor, featureBgColor),
                          ))
                      : [
                          _buildFeatureItem('Full access to all content', isDark, isTablet, textColor, iconColor, featureBgColor),
                          SizedBox(height: isTablet ? 10 : 8),
                          _buildFeatureItem('Downloadable study materials', isDark, isTablet, textColor, iconColor, featureBgColor),
                          SizedBox(height: isTablet ? 10 : 8),
                          _buildFeatureItem('Expert-curated resources', isDark, isTablet, textColor, iconColor, featureBgColor),
                        ]),
                  SizedBox(height: isTablet ? 10 : 8),
                  Divider(height: 1, color: borderColor),
                  SizedBox(height: isTablet ? 20 : 16),
                  // Price
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      // Price hidden on iOS
                      SizedBox(width: isTablet ? 10 : 8),
                      Text(
                        '/ ${_package?.durationDays != null ? '${(_package!.durationDays! / 30).round()} months' : '3 months'}',
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          fontWeight: FontWeight.w400,
                          fontSize: durationSize,
                          color: textColor.withValues(alpha: 0.5),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  if (_package?.isOnSale == true)
                    Text(
                      'Limited Time Offer',
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontWeight: FontWeight.w400,
                        fontSize: offerSize,
                        color: secondaryTextColor,
                      ),
                    ),
                  SizedBox(height: isTablet ? 20 : 16),
                  // Enroll Now button
                  SizedBox(
                    width: double.infinity,
                    height: btnHeight,
                    child: ElevatedButton(
                      onPressed: () {
                        Navigator.of(dialogContext).pop(true);
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: buttonColor,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(btnRadius),
                        ),
                        elevation: 0,
                        padding: EdgeInsets.symmetric(horizontal: btnPadH, vertical: isTablet ? 12 : 10),
                      ),
                      child: Text(
                        'Learn More',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          fontWeight: FontWeight.w500,
                          fontSize: btnFontSize,
                          letterSpacing: -0.18,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                  SizedBox(height: isTablet ? 10 : 8),
                  // See All Packages button
                  SizedBox(
                    width: double.infinity,
                    height: btnHeight,
                    child: OutlinedButton(
                      onPressed: () {
                        Navigator.of(dialogContext).pop(false);
                        context.push('/all-packages');
                      },
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(
                          color: buttonColor,
                          width: 1,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(btnRadius),
                        ),
                        padding: EdgeInsets.symmetric(horizontal: btnPadH, vertical: isTablet ? 12 : 10),
                      ),
                      child: Text(
                        'See All Packages',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          fontWeight: FontWeight.w500,
                          fontSize: btnFontSize,
                          letterSpacing: -0.18,
                          color: buttonColor,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            SizedBox(height: isTablet ? 120 : 100),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFeatureItem(String text, bool isDark, bool isTablet, Color textColor, Color iconColor, Color featureBgColor) {
    final checkBgSize = isTablet ? 22.0 : 16.0;
    final checkIconSize = isTablet ? 14.0 : 10.0;
    final featureTextSize = isTablet ? 15.0 : 12.0;

    return Row(
      children: [
        Container(
          width: checkBgSize,
          height: checkBgSize,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: featureBgColor,
          ),
          child: Center(
            child: Icon(
              Icons.check,
              size: checkIconSize,
              color: iconColor,
            ),
          ),
        ),
        SizedBox(width: isTablet ? 12 : 8),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              fontFamily: 'Poppins',
              fontWeight: FontWeight.w400,
              fontSize: featureTextSize,
              color: textColor,
            ),
          ),
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

    // Theme-aware colors
    final backgroundColor = isDark ? AppColors.darkBackground : Colors.white;
    final textColor = isDark ? AppColors.darkTextPrimary : const Color(0xFF000000);
    final secondaryTextColor = isDark ? AppColors.darkTextSecondary : const Color(0xFF666666);
    final cardBgColor = isDark ? AppColors.darkCardBackground : Colors.white;
    final imagePlaceholderColor = isDark ? AppColors.darkSurface : const Color(0xFFD9D9D9);
    final iconColor = isDark ? const Color(0xFF00BEFA) : const Color(0xFF2470E4);

    final hPadding = isTablet ? ResponsiveHelper.horizontalPadding(context) : 16.0;

    return Scaffold(
      backgroundColor: backgroundColor,
      body: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: ResponsiveHelper.getMaxContentWidth(context)),
          child: Column(
        children: [
          // Header
          Padding(
            padding: EdgeInsets.only(top: topPadding + (isTablet ? 16 : 12), left: hPadding, right: hPadding),
            child: Row(
              children: [
                // Back arrow
                GestureDetector(
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
                    child: Icon(
                      Icons.arrow_back,
                      size: isTablet ? 30 : 24,
                      color: textColor,
                    ),
                  ),
                ),
                const Spacer(),
                // Title
                SizedBox(
                  width: isTablet ? 240 : 180,
                  child: Text(
                    widget.isSubscribed ? 'Series Notes' : 'Available Notes',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontWeight: FontWeight.w500,
                      fontSize: isTablet ? 25 : 20,
                      height: 1.0,
                      letterSpacing: -0.5,
                      color: textColor,
                    ),
                  ),
                ),
                const Spacer(),
                // // Three dots menu
                // GestureDetector(
                //   onTap: () {
                //     // Menu options
                //   },
                //   child: SizedBox(
                //     width: isTablet ? 30 : 24,
                //     height: isTablet ? 30 : 24,
                //     child: Icon(
                //       Icons.more_horiz,
                //       size: isTablet ? 30 : 24,
                //       color: textColor,
                //     ),
                //   ),
                // ),
              ],
            ),
          ),

          // Notes List (banner is now the first scrollable item)
          Expanded(
            child: RefreshIndicator(
              onRefresh: _loadData,
              child: _isLoading
                ? ListView(
                    padding: EdgeInsets.only(top: isTablet ? 29 : 22),
                    children: [
                      _buildNotesBanner(isTablet, hPadding, imagePlaceholderColor, secondaryTextColor),
                      SizedBox(height: isTablet ? 36 : 28),
                      ...List.generate(5, (index) => Padding(
                        padding: EdgeInsets.symmetric(horizontal: hPadding),
                        child: ShimmerWidgets.listItemShimmer(isDark: isDark),
                      )),
                    ],
                  )
                : _error != null
                    ? ListView(
                        padding: EdgeInsets.only(top: isTablet ? 29 : 22),
                        children: [
                          _buildNotesBanner(isTablet, hPadding, imagePlaceholderColor, secondaryTextColor),
                          SizedBox(height: isTablet ? 36 : 28),
                          SizedBox(
                            height: MediaQuery.of(context).size.height * 0.4,
                            child: Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.error_outline, size: isTablet ? 64 : 48, color: secondaryTextColor),
                                  SizedBox(height: isTablet ? 21 : 16),
                                  Text(
                                    'Failed to load notes',
                                    style: TextStyle(
                                      fontFamily: 'Poppins',
                                      fontSize: isTablet ? 20 : 16,
                                      color: textColor,
                                    ),
                                  ),
                                  SizedBox(height: isTablet ? 21 : 16),
                                  ElevatedButton(
                                    onPressed: _loadData,
                                    style: ElevatedButton.styleFrom(backgroundColor: iconColor),
                                    child: const Text('Retry'),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      )
                    : _documents.isEmpty
                        ? ListView(
                            padding: EdgeInsets.only(top: isTablet ? 29 : 22),
                            children: [
                              _buildNotesBanner(isTablet, hPadding, imagePlaceholderColor, secondaryTextColor),
                              SizedBox(height: isTablet ? 36 : 28),
                              SizedBox(
                                height: MediaQuery.of(context).size.height * 0.4,
                                child: Center(
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(Icons.upcoming_outlined, size: isTablet ? 64 : 48, color: secondaryTextColor),
                                      SizedBox(height: isTablet ? 21 : 16),
                                      Text(
                                        'Notes Coming Soon',
                                        style: TextStyle(
                                          fontFamily: 'Poppins',
                                          fontSize: isTablet ? 20 : 16,
                                          fontWeight: FontWeight.w600,
                                          color: textColor,
                                        ),
                                      ),
                                      SizedBox(height: isTablet ? 8 : 6),
                                      Text(
                                        _series?.documentsReleaseAt != null
                                            ? 'Expected on ${_formatReleaseDate(_series!.documentsReleaseAt!)}'
                                            : 'Documents will be available soon',
                                        style: TextStyle(
                                          fontFamily: 'Poppins',
                                          fontSize: isTablet ? 15 : 13,
                                          color: secondaryTextColor,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          )
                        : ListView.builder(
                            padding: EdgeInsets.only(top: isTablet ? 29 : 22, bottom: isTablet ? 150 : 120),
                            itemCount: _documents.length + 2,
                            itemBuilder: (context, index) {
                              if (index == 0) {
                                return Padding(
                                  padding: EdgeInsets.only(bottom: isTablet ? 36 : 28),
                                  child: _buildNotesBanner(isTablet, hPadding, imagePlaceholderColor, secondaryTextColor),
                                );
                              }
                              if (index == _documents.length + 1) {
                                return const TutorialSectionWidget();
                              }
                              final document = _documents[index - 1];
                              return Padding(
                                padding: EdgeInsets.symmetric(horizontal: hPadding),
                                child: _buildNoteCard(
                                  context,
                                  document: document,
                                  index: index - 1,
                                  isExpanded: _expandedIndex == (index - 1),
                                  isDark: isDark,
                                  isTablet: isTablet,
                                  textColor: textColor,
                                  cardBgColor: cardBgColor,
                                  iconColor: iconColor,
                                ),
                              );
                            },
                          ),
            ),
          ),
        ],
      ),
        ),
      ),
    );
  }

  Widget _buildNotesBanner(bool isTablet, double hPadding, Color imagePlaceholderColor, Color secondaryTextColor) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: hPadding),
      child: AspectRatio(
        aspectRatio: 16 / 9,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(isTablet ? 16 : 12),
          child: (_package?.notesThumbnailUrl ?? _series?.thumbnailUrl) != null && (_package?.notesThumbnailUrl ?? _series?.thumbnailUrl)!.isNotEmpty
              ? CachedNetworkImage(
                  imageUrl: (_package?.notesThumbnailUrl ?? _series?.thumbnailUrl)!,
                  width: double.infinity,
                  height: double.infinity,
                  fit: BoxFit.cover,
                  placeholder: (context, url) => Container(
                    color: imagePlaceholderColor,
                    child: Center(
                      child: Icon(
                        Icons.image_outlined,
                        size: isTablet ? 75 : 60,
                        color: secondaryTextColor,
                      ),
                    ),
                  ),
                  errorWidget: (context, url, error) => Container(
                    color: imagePlaceholderColor,
                    child: Center(
                      child: Icon(
                        Icons.image_outlined,
                        size: isTablet ? 75 : 60,
                        color: secondaryTextColor,
                      ),
                    ),
                  ),
                )
              : Container(
                  color: imagePlaceholderColor,
                  child: Center(
                    child: Icon(
                      Icons.image_outlined,
                      size: isTablet ? 75 : 60,
                      color: secondaryTextColor,
                    ),
                  ),
                ),
        ),
      ),
    );
  }

  Future<void> _addToLibrary(SeriesDocumentModel document) async {
    if (_isAddingToLibrary || _addedToLibrary.contains(document.documentId)) {
      return;
    }

    setState(() {
      _isAddingToLibrary = true;
    });

    try {
      await _dashboardService.addToLibrary(document.documentId);

      if (mounted) {
        setState(() {
          _addedToLibrary.add(document.documentId);
          _isAddingToLibrary = false;
        });

        showAppDialog(context, message: '${document.title} added to Your Notes', type: AppDialogType.success);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isAddingToLibrary = false;
        });

        showAppDialog(context, message: e.toString().replaceAll('Exception: ', ''));
      }
    }
  }

  Widget _buildNoteCard(
    BuildContext context, {
    required SeriesDocumentModel document,
    required int index,
    required bool isExpanded,
    required bool isDark,
    required bool isTablet,
    required Color textColor,
    required Color cardBgColor,
    required Color iconColor,
  }) {
    // If subscribed, nothing is locked; otherwise check if document is free
    final isLocked = widget.isSubscribed ? false : !document.isFree;
    final isAlreadyAdded = document.isInLibrary || _addedToLibrary.contains(document.documentId);
    final placeholderColor = isDark ? AppColors.darkDivider : const Color(0xFFE8E8E8);
    final lockBadgeBgColor = isDark ? AppColors.darkCardBackground : const Color(0xFFDCEAF7);
    final buttonColor = isDark ? const Color(0xFF0047CF) : const Color(0xFF0000D1);
    return GestureDetector(
      onTap: () {
        if (isLocked) {
          _showEnrollmentPopup();
        } else {
          setState(() {
            _expandedIndex = isExpanded ? null : index;
          });
        }
      },
      child: Container(
        width: isTablet ? double.infinity : 359,
        margin: EdgeInsets.only(top: index == 0 ? 4 : 0, bottom: isTablet ? 21 : 16),
        decoration: BoxDecoration(
          color: cardBgColor,
          borderRadius: BorderRadius.circular(isTablet ? 16 : 12),
          boxShadow: isDark
              ? [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.3),
                    blurRadius: 8,
                    offset: const Offset(0, 4),
                  ),
                ]
              : const [
                  BoxShadow(
                    color: Color(0x4D000000),
                    blurRadius: 3,
                    offset: Offset(0, 1),
                  ),
                  BoxShadow(
                    color: Color(0x26000000),
                    blurRadius: 8,
                    spreadRadius: 3,
                    offset: Offset(0, 4),
                  ),
                ],
        ),
        child: Padding(
          padding: EdgeInsets.all(isTablet ? 20 : 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Document thumbnail with lock overlay for locked items
                  Stack(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(isTablet ? 10 : 8),
                        child: document.thumbnailUrl != null && document.thumbnailUrl!.isNotEmpty
                            ? CachedNetworkImage(
                                imageUrl: document.thumbnailUrl!,
                                width: isTablet ? 100 : 80,
                                height: isTablet ? 56 : 45,
                                fit: BoxFit.cover,
                                placeholder: (context, url) => Container(
                                  width: isTablet ? 100 : 80,
                                  height: isTablet ? 56 : 45,
                                  color: placeholderColor,
                                  child: Center(
                                    child: Icon(
                                      document.fileFormat.toLowerCase() == 'epub' ? Icons.auto_stories : Icons.picture_as_pdf,
                                      size: isTablet ? 40 : 32,
                                      color: isDark ? AppColors.darkTextSecondary : const Color(0xFF666666),
                                    ),
                                  ),
                                ),
                                errorWidget: (context, url, error) => Container(
                                  width: isTablet ? 100 : 80,
                                  height: isTablet ? 56 : 45,
                                  color: placeholderColor,
                                  child: Center(
                                    child: Icon(
                                      document.fileFormat.toLowerCase() == 'epub' ? Icons.auto_stories : Icons.picture_as_pdf,
                                      size: isTablet ? 40 : 32,
                                      color: isDark ? AppColors.darkTextSecondary : const Color(0xFF666666),
                                    ),
                                  ),
                                ),
                              )
                            : Container(
                                width: isTablet ? 100 : 80,
                                height: isTablet ? 56 : 45,
                                decoration: BoxDecoration(
                                  color: placeholderColor,
                                ),
                                child: Center(
                                  child: Icon(
                                    Icons.picture_as_pdf,
                                    size: isTablet ? 40 : 32,
                                    color: isDark ? AppColors.darkTextSecondary : const Color(0xFF666666),
                                  ),
                                ),
                              ),
                      ),
                      if (isLocked)
                        Positioned.fill(
                          child: Container(
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.3),
                              borderRadius: BorderRadius.circular(isTablet ? 10 : 8),
                            ),
                            child: Center(
                              child: Container(
                                width: isTablet ? 40 : 32,
                                height: isTablet ? 40 : 32,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: lockBadgeBgColor,
                                ),
                                child: Center(
                                  child: Icon(
                                    Icons.lock,
                                    size: isTablet ? 20 : 16,
                                    color: iconColor,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                  SizedBox(width: isTablet ? 20 : 16),
                  // Content
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                document.title,
                                style: TextStyle(
                                  fontFamily: 'Poppins',
                                  fontWeight: FontWeight.w600,
                                  fontSize: isTablet ? 20 : 16,
                                  height: 1.2,
                                  color: textColor,
                                ),
                              ),
                            ),
                            if (isLocked)
                              Container(
                                padding: EdgeInsets.symmetric(horizontal: isTablet ? 10 : 8, vertical: isTablet ? 5 : 4),
                                decoration: BoxDecoration(
                                  color: lockBadgeBgColor,
                                  borderRadius: BorderRadius.circular(isTablet ? 16 : 12),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.lock,
                                      size: isTablet ? 15 : 12,
                                      color: iconColor,
                                    ),
                                    SizedBox(width: isTablet ? 5 : 4),
                                    Text(
                                      'Locked',
                                      style: TextStyle(
                                        fontFamily: 'Poppins',
                                        fontSize: isTablet ? 13 : 10,
                                        fontWeight: FontWeight.w500,
                                        color: iconColor,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                          ],
                        ),
                        SizedBox(height: isTablet ? 8 : 6),
                        Text(
                          document.description ?? 'No description available',
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            fontWeight: FontWeight.w400,
                            fontSize: isTablet ? 15 : 12,
                            height: 1.4,
                            color: textColor.withValues(alpha: 0.5),
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              // Animated buttons section - Different for subscribed vs non-subscribed
              AnimatedSize(
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeInOut,
                alignment: Alignment.topCenter,
                child: isExpanded
                    ? Column(
                        children: [
                          SizedBox(height: isTablet ? 20 : 16),
                          // Show different buttons based on subscription status
                          if (widget.isSubscribed && isAlreadyAdded)
                            // Subscribed + already in library: Show "View PDF" button
                            SizedBox(
                              width: double.infinity,
                              height: isTablet ? 54 : 44,
                              child: ElevatedButton(
                                onPressed: () {
                                  context.pushNamed(
                                    document.fileFormat.toLowerCase() == 'epub' ? 'epub-viewer' : 'pdf-viewer',
                                    queryParameters: {
                                      'documentId': document.documentId,
                                      'title': document.title,
                                      if (document.fileFormat.toLowerCase() == 'epub') 'source': 'document',
                                    },
                                  );
                                },
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: buttonColor,
                                  foregroundColor: Colors.white,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(isTablet ? 27 : 22),
                                  ),
                                  elevation: 0,
                                  padding: EdgeInsets.symmetric(horizontal: isTablet ? 20 : 16),
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      document.fileFormat.toLowerCase() == 'epub' ? Icons.auto_stories : Icons.picture_as_pdf,
                                      size: isTablet ? 25 : 20,
                                      color: Colors.white,
                                    ),
                                    SizedBox(width: isTablet ? 10 : 8),
                                    Flexible(
                                      child: Text(
                                        document.fileFormat.toLowerCase() == 'epub' ? 'Read EPUB' : 'View PDF',
                                        style: TextStyle(
                                          fontFamily: 'Poppins',
                                          fontSize: isTablet ? 17 : 14,
                                          fontWeight: FontWeight.w500,
                                          color: Colors.white,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            )
                          else if (widget.isSubscribed && !isAlreadyAdded)
                            // Subscribed + not yet in library: Show "Add to Notes" button
                            SizedBox(
                              width: double.infinity,
                              height: isTablet ? 54 : 44,
                              child: ElevatedButton(
                                onPressed: _isAddingToLibrary
                                    ? null
                                    : () => _addToLibrary(document),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: buttonColor,
                                  foregroundColor: Colors.white,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(isTablet ? 27 : 22),
                                  ),
                                  elevation: 0,
                                  padding: EdgeInsets.symmetric(horizontal: isTablet ? 20 : 16),
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    if (_isAddingToLibrary)
                                      SizedBox(
                                        width: isTablet ? 22 : 18,
                                        height: isTablet ? 22 : 18,
                                        child: const CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: Colors.white,
                                        ),
                                      )
                                    else
                                      Icon(
                                        Icons.add,
                                        size: isTablet ? 25 : 20,
                                        color: Colors.white,
                                      ),
                                    SizedBox(width: isTablet ? 10 : 8),
                                    Flexible(
                                      child: Text(
                                        'Add to Notes',
                                        style: TextStyle(
                                          fontFamily: 'Poppins',
                                          fontSize: isTablet ? 17 : 14,
                                          fontWeight: FontWeight.w500,
                                          color: Colors.white,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            )
                          else if (document.isFree)
                            // Not subscribed but FREE document: View PDF + Add to Notes (if not already added)
                            Row(
                              children: [
                                // View PDF button
                                Expanded(
                                  child: SizedBox(
                                    height: isTablet ? 50 : 40,
                                    child: ElevatedButton(
                                      onPressed: () {
                                        context.pushNamed(
                                          document.fileFormat.toLowerCase() == 'epub' ? 'epub-viewer' : 'pdf-viewer',
                                          queryParameters: {
                                            'documentId': document.documentId,
                                            'title': document.title,
                                            if (document.fileFormat.toLowerCase() == 'epub') 'source': 'document',
                                          },
                                        );
                                      },
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: buttonColor,
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(isTablet ? 25 : 20),
                                        ),
                                        elevation: 0,
                                        padding: EdgeInsets.symmetric(horizontal: isTablet ? 10 : 8),
                                      ),
                                      child: FittedBox(
                                        fit: BoxFit.scaleDown,
                                        child: Text(
                                          document.fileFormat.toLowerCase() == 'epub' ? 'Read EPUB' : 'View PDF',
                                          style: TextStyle(
                                            fontFamily: 'Poppins',
                                            fontSize: isTablet ? 14 : 11,
                                            fontWeight: FontWeight.w500,
                                            color: Colors.white,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                if (!isAlreadyAdded) ...[
                                  SizedBox(width: isTablet ? 10 : 8),
                                  // Add to Notes button
                                  Expanded(
                                    child: SizedBox(
                                      height: isTablet ? 50 : 40,
                                      child: ElevatedButton(
                                        onPressed: _isAddingToLibrary
                                            ? null
                                            : () => _addToLibrary(document),
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: buttonColor,
                                          foregroundColor: Colors.white,
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(isTablet ? 25 : 20),
                                          ),
                                          elevation: 0,
                                          padding: EdgeInsets.symmetric(horizontal: isTablet ? 10 : 8),
                                        ),
                                        child: FittedBox(
                                          fit: BoxFit.scaleDown,
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              if (_isAddingToLibrary)
                                                SizedBox(
                                                  width: isTablet ? 18 : 14,
                                                  height: isTablet ? 18 : 14,
                                                  child: const CircularProgressIndicator(
                                                    strokeWidth: 2,
                                                    color: Colors.white,
                                                  ),
                                                )
                                              else
                                                Icon(
                                                  Icons.add,
                                                  size: isTablet ? 18 : 14,
                                                  color: Colors.white,
                                                ),
                                              SizedBox(width: isTablet ? 5 : 4),
                                              Text(
                                                'Add to Notes',
                                                style: TextStyle(
                                                  fontFamily: 'Poppins',
                                                  fontSize: isTablet ? 14 : 11,
                                                  fontWeight: FontWeight.w500,
                                                  color: Colors.white,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            )
                          else
                            // Not subscribed + LOCKED document
                            Row(
                              children: [
                                // View sample pdf button — only if preview_url exists
                                if (document.previewUrl != null) ...[
                                  Expanded(
                                    child: SizedBox(
                                      height: isTablet ? 50 : 40,
                                      child: ElevatedButton(
                                        onPressed: () {
                                          context.pushNamed(
                                            'pdf-viewer',
                                            queryParameters: {
                                              'pdfUrl': document.previewUrl!,
                                              'title': '${document.title} (Sample)',
                                            },
                                          );
                                        },
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: buttonColor,
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(isTablet ? 25 : 20),
                                          ),
                                          elevation: 0,
                                          padding: EdgeInsets.symmetric(horizontal: isTablet ? 10 : 8),
                                        ),
                                        child: FittedBox(
                                          fit: BoxFit.scaleDown,
                                          child: Text(
                                            'View sample pdf',
                                            style: TextStyle(
                                              fontFamily: 'Poppins',
                                              fontSize: isTablet ? 14 : 11,
                                              fontWeight: FontWeight.w500,
                                              color: Colors.white,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                  SizedBox(width: isTablet ? 10 : 8),
                                ],
                                // Enroll / View full book button
                                Expanded(
                                  child: SizedBox(
                                    height: isTablet ? 50 : 40,
                                    child: ElevatedButton(
                                      onPressed: () {
                                        _showEnrollmentPopup();
                                      },
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: buttonColor,
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(isTablet ? 25 : 20),
                                        ),
                                        elevation: 0,
                                        padding: EdgeInsets.symmetric(horizontal: isTablet ? 10 : 8),
                                      ),
                                      child: FittedBox(
                                        fit: BoxFit.scaleDown,
                                        child: Text(
                                          document.previewUrl != null ? 'View full book' : 'View details',
                                          style: TextStyle(
                                            fontFamily: 'Poppins',
                                            fontSize: isTablet ? 14 : 11,
                                            fontWeight: FontWeight.w500,
                                            color: Colors.white,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                        ],
                      )
                    : const SizedBox.shrink(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatReleaseDate(String isoDate) {
    try {
      final date = DateTime.parse(isoDate);
      final months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
      return '${months[date.month - 1]} ${date.day}, ${date.year}';
    } catch (_) {
      return 'Soon';
    }
  }
}
