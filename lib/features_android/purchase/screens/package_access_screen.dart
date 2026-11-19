import 'dart:io';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:pgme/core_android/providers/theme_provider.dart';
import 'package:pgme/core_android/theme/app_theme.dart';
import 'package:pgme/core_android/models/package_model.dart';
import 'package:pgme/core_android/models/gateway_models.dart';
import 'package:pgme/core_android/services/dashboard_service.dart';
import 'package:pgme/core_android/widgets/gateway_widget.dart';
import 'package:pgme/core_android/widgets/address_bottom_sheet.dart';
import 'package:pgme/core_android/models/address_model.dart';
import 'package:pgme/core_android/services/user_service.dart';
import 'package:pgme/features_android/home/providers/dashboard_provider.dart';
import 'package:pgme/core_android/utils/responsive_helper.dart';
import 'package:pgme/core_android/utils/web_store_launcher.dart';
import 'package:pgme/features_android/purchase/widgets/tier_change_sheet.dart';
import 'package:pgme/features_android/purchase/widgets/combo_upgrade_sheet.dart';
import 'package:pgme/features_android/purchase/widgets/combo_offer_card.dart';
import 'package:pgme/core_android/widgets/app_dialog.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';

class PackageAccessScreen extends StatefulWidget {
  final String? packageId;
  final String? packageType; // 'Theory' or 'Practical'

  const PackageAccessScreen({super.key, this.packageId, this.packageType});

  @override
  State<PackageAccessScreen> createState() => _PackageAccessScreenState();
}

class _PackageAccessScreenState extends State<PackageAccessScreen>
    with WidgetsBindingObserver {
  bool _isProcessing = false;
  bool _isLoading = true;
  PackageModel? _package;
  String? _error;
  int _selectedTierIndex = 0;
  final DashboardService _dashboardService = DashboardService();

  @override
  void initState() {
    super.initState();
    if (Platform.isIOS) WidgetsBinding.instance.addObserver(this);
    _loadPackageData();
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
      _loadPackageData();
      // Refresh the dashboard so the home screen shows the new purchase
      // status without requiring a manual pull-to-refresh.
      if (mounted) {
        context.read<DashboardProvider>().refresh();
      }
    }
  }

  Future<void> _loadPackageData() async {
    if (widget.packageId == null && widget.packageType == null) {
      // If no packageId or packageType provided, try to get the first package from dashboard
      final dashboardProvider = context.read<DashboardProvider>();
      if (dashboardProvider.packages.isNotEmpty) {
        setState(() {
          _package = dashboardProvider.packages.first;
          _selectedTierIndex = 0;
          _isLoading = false;
        });
        return;
      }
    }

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      // Use primary subject to filter packages when no specific packageId is given
      final dashboardProvider = context.read<DashboardProvider>();
      final primarySubjectId = dashboardProvider.primarySubject?.subjectId;

      // Load packages filtered by subject when looking up by type
      final packages = await _dashboardService.getPackages(
        subjectId: widget.packageId == null ? primarySubjectId : null,
      );

      if (mounted) {
        PackageModel? foundPackage;
        if (widget.packageId != null) {
          // Find by packageId
          foundPackage = packages.firstWhere(
            (p) => p.packageId == widget.packageId,
            orElse: () => packages.isNotEmpty ? packages.first : throw Exception('No packages available'),
          );
        } else if (widget.packageType != null) {
          // Find by packageType (Theory or Practical) within the subject-filtered results
          foundPackage = packages.firstWhere(
            (p) => p.type?.toLowerCase() == widget.packageType!.toLowerCase(),
            orElse: () => packages.isNotEmpty ? packages.first : throw Exception('No packages available'),
          );
        } else if (packages.isNotEmpty) {
          foundPackage = packages.first;
        }

        setState(() {
          _package = foundPackage;
          _selectedTierIndex = 0;
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

  /// Close the purchase popup and open the credited combo checkout.
  void _takeComboOffer(Map<String, dynamic> offer) {
    final comboId = (offer['combo'] as Map<String, dynamic>?)?['package_id']?.toString();
    if (comboId == null) return;
    showComboUpgradeSheet(context, comboPackageId: comboId, quote: offer).then((done) {
      if (done == true && mounted) _loadPackageData();
    });
  }

  String _formatPrice(int price) {
    if (Platform.isIOS) return '';
    return '₹${price.toString().replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (Match m) => '${m[1]},')}';
  }

  String _formatDuration(int? days) {
    if (days == null) return '';
    if (days >= 365) {
      final years = days ~/ 365;
      return '$years ${years == 1 ? 'year' : 'years'}';
    } else if (days >= 30) {
      final months = days ~/ 30;
      return '$months ${months == 1 ? 'month' : 'months'}';
    } else {
      return '$days ${days == 1 ? 'day' : 'days'}';
    }
  }

  int _calculateDiscount(int price, int? originalPrice) {
    if (originalPrice == null || originalPrice <= price) return 0;
    return ((originalPrice - price) * 100 / originalPrice).round();
  }

  void _showPaymentPopup() async {
    if (_package == null) return;

    // iOS: redirect to web store to avoid Apple IAP requirement
    if (WebStoreLauncher.shouldUseWebStore) {
      WebStoreLauncher.openProductPage(
        context,
        productType: 'packages',
        productId: _package!.packageId,
      );
      return;
    }

    final themeProvider = Provider.of<ThemeProvider>(context, listen: false);
    final isDark = themeProvider.isDarkMode;

    final shouldEnroll = await showDialog<bool>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.5),
      builder: (dialogContext) => _buildEnrollmentDialog(dialogContext, isDark),
    );

    if (shouldEnroll == true && mounted) {
      _processPayment();
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

    final package = _package!;
    final hasTiers = package.hasTiers && package.tiers != null && package.tiers!.isNotEmpty;

    // Tablet-scaled dimensions
    final dialogWidth = isTablet ? 560.0 : 356.0;
    final dialogRadius = isTablet ? 28.0 : 20.8;
    final closePad = isTablet ? 18.0 : 12.0;
    final closeSize = isTablet ? 32.0 : 24.0;
    final imgWidth = isTablet ? dialogWidth : 180.0;
    final imgHeight = isTablet ? 380.0 : 120.0;
    final titleSize = isTablet ? 26.0 : 16.0;
    final descSize = isTablet ? 17.0 : 12.0;
    final descPadH = isTablet ? 48.0 : 40.0;
    final boxMarginH = isTablet ? 32.0 : 18.0;
    final boxPad = isTablet ? 28.0 : 16.0;
    final boxRadius = isTablet ? 18.0 : 10.93;
    final pkgNameSize = isTablet ? 22.0 : 14.0;
    final featureIconSize = isTablet ? 26.0 : 16.0;
    final featureCheckSize = isTablet ? 16.0 : 10.0;
    final featureTextSize = isTablet ? 17.0 : 12.0;
    final featureGap = isTablet ? 14.0 : 8.0;
    final featureIconGap = isTablet ? 14.0 : 8.0;
    final priceSize = isTablet ? 36.0 : 24.0;
    final durationSize = isTablet ? 19.0 : 14.0;
    final saleSize = isTablet ? 17.0 : 12.0;
    final btnHeight = isTablet ? 58.0 : 40.0;
    final btnFontSize = isTablet ? 21.0 : 16.0;
    final btnRadius = isTablet ? 28.0 : 22.0;
    final btnPadH = isTablet ? 24.0 : 16.0;
    final btnPadV = isTablet ? 14.0 : 10.0;
    final fallbackIconSize = isTablet ? 100.0 : 60.0;
    final fallbackRadius = isTablet ? 22.0 : 12.0;

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: EdgeInsets.symmetric(horizontal: isTablet ? 48 : 24, vertical: isTablet ? 60 : 40),
      child: Container(
        width: dialogWidth,
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height - (isTablet ? 120 : 80),
        ),
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: dialogBgColor,
          borderRadius: BorderRadius.circular(dialogRadius),
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Image + Close button (stacked on tablet so close overlays image)
              if (isTablet)
                Stack(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.only(
                        topLeft: Radius.circular(dialogRadius),
                        topRight: Radius.circular(dialogRadius),
                      ),
                      child: Image.asset(
                        'assets/illustrations/enroll.png',
                        width: imgWidth,
                        height: imgHeight,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) {
                          return Container(
                            width: imgWidth,
                            height: imgHeight,
                            decoration: BoxDecoration(
                              color: featureBgColor,
                              borderRadius: BorderRadius.only(
                                topLeft: Radius.circular(dialogRadius),
                                topRight: Radius.circular(dialogRadius),
                              ),
                            ),
                            child: Icon(
                              Icons.play_circle_outline,
                              size: fallbackIconSize,
                              color: iconColor,
                            ),
                          );
                        },
                      ),
                    ),
                    Positioned(
                      top: closePad,
                      right: closePad,
                      child: GestureDetector(
                        onTap: () => Navigator.of(dialogContext).pop(false),
                        child: Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: dialogBgColor.withValues(alpha: 0.7),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            Icons.close,
                            size: closeSize,
                            color: textColor,
                          ),
                        ),
                      ),
                    ),
                  ],
                )
              else ...[
                // Close button (mobile)
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
                // Illustration (mobile)
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
                        borderRadius: BorderRadius.circular(fallbackRadius),
                      ),
                      child: Icon(
                        Icons.play_circle_outline,
                        size: fallbackIconSize,
                        color: iconColor,
                      ),
                    );
                  },
                ),
              ],

              // Content section - overlaps image on tablet
              Container(
                width: isTablet ? double.infinity : null,
                transform: isTablet ? Matrix4.translationValues(0, -50, 0) : null,
                decoration: isTablet
                    ? BoxDecoration(
                        color: dialogBgColor,
                        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
                      )
                    : null,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(height: isTablet ? 20 : 16),

              // Title
              Text(
                Platform.isIOS ? 'View ${package.type ?? ''}\nPackage' : 'Get the ${package.type ?? ''}\nPackage',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontWeight: FontWeight.w500,
                  fontSize: titleSize,
                  height: isTablet ? 1.25 : 1.1,
                  letterSpacing: -0.18,
                  color: textColor,
                ),
              ),

              SizedBox(height: isTablet ? 10 : 12),

              // Description
              if (package.description != null)
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: descPadH),
                  child: Text(
                    package.description!,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontWeight: FontWeight.w400,
                      fontSize: descSize,
                      height: isTablet ? 1.4 : 1.05,
                      letterSpacing: -0.18,
                      color: secondaryTextColor,
                    ),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),

              SizedBox(height: isTablet ? 14 : 16),

              // Package details box
              Container(
                margin: EdgeInsets.symmetric(horizontal: boxMarginH),
                padding: EdgeInsets.all(boxPad),
                decoration: BoxDecoration(
                  color: boxBgColor,
                  borderRadius: BorderRadius.circular(boxRadius),
                  border: isTablet ? null : Border.all(
                    color: borderColor,
                    width: 1,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      package.name,
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontWeight: FontWeight.w600,
                        fontSize: pkgNameSize,
                        color: textColor,
                      ),
                    ),
                    SizedBox(height: isTablet ? 20 : 12),
                    // Features
                    if (package.features != null && package.features!.isNotEmpty)
                      ...package.features!.take(4).map((feature) => Padding(
                        padding: EdgeInsets.only(bottom: featureGap),
                        child: _buildPopupFeatureItem(feature, isDark, textColor, iconColor, featureBgColor,
                          isTablet: isTablet,
                          iconSize: featureIconSize,
                          checkSize: featureCheckSize,
                          textSize: featureTextSize,
                          iconGap: featureIconGap,
                        ),
                      ))
                    else ...[
                      _buildPopupFeatureItem('Full access to ${package.type?.toLowerCase() ?? ''} content', isDark, textColor, iconColor, featureBgColor,
                        isTablet: isTablet, iconSize: featureIconSize, checkSize: featureCheckSize, textSize: featureTextSize, iconGap: featureIconGap),
                      SizedBox(height: featureGap),
                      _buildPopupFeatureItem('Expert faculty guidance', isDark, textColor, iconColor, featureBgColor,
                        isTablet: isTablet, iconSize: featureIconSize, checkSize: featureCheckSize, textSize: featureTextSize, iconGap: featureIconGap),
                      SizedBox(height: featureGap),
                      _buildPopupFeatureItem('24/7 doubt resolution support', isDark, textColor, iconColor, featureBgColor,
                        isTablet: isTablet, iconSize: featureIconSize, checkSize: featureCheckSize, textSize: featureTextSize, iconGap: featureIconGap),
                    ],
                    SizedBox(height: isTablet ? 24 : 16),
                    // Tier selector + price (wrapped in StatefulBuilder so price updates on tier change)
                    StatefulBuilder(
                      builder: (context, setDialogState) {
                        final selectedTier = hasTiers ? package.tiers![_selectedTierIndex] : null;
                        final dialogDisplayPrice = hasTiers
                            ? selectedTier!.effectivePrice
                            : (package.isOnSale && package.salePrice != null ? package.salePrice! : package.price);
                        final dialogDisplayDuration = hasTiers ? selectedTier!.durationDays : package.durationDays;

                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (hasTiers) ...[
                              Divider(height: 1, thickness: 1, color: borderColor),
                              SizedBox(height: isTablet ? 16 : 12),
                              Text(
                                'Select Duration',
                                style: TextStyle(
                                  fontFamily: 'Poppins',
                                  fontWeight: FontWeight.w600,
                                  fontSize: isTablet ? 16 : 13,
                                  color: textColor,
                                ),
                              ),
                              SizedBox(height: isTablet ? 12 : 8),
                              Wrap(
                                spacing: isTablet ? 10 : 8,
                                runSpacing: isTablet ? 10 : 8,
                                children: List.generate(package.tiers!.length, (i) {
                                  final tier = package.tiers![i];
                                  final isSelected = _selectedTierIndex == i;
                                  return GestureDetector(
                                    onTap: () {
                                      setState(() => _selectedTierIndex = i);
                                      setDialogState(() {});
                                    },
                                    child: Container(
                                      padding: EdgeInsets.symmetric(
                                        horizontal: isTablet ? 16 : 12,
                                        vertical: isTablet ? 10 : 8,
                                      ),
                                      decoration: BoxDecoration(
                                        color: isSelected ? buttonColor : Colors.transparent,
                                        borderRadius: BorderRadius.circular(isTablet ? 12 : 8),
                                        border: Border.all(
                                          color: isSelected ? buttonColor : borderColor,
                                          width: 1.5,
                                        ),
                                      ),
                                      child: Column(
                                        children: [
                                          Text(
                                            tier.name,
                                            style: TextStyle(
                                              fontFamily: 'Poppins',
                                              fontWeight: FontWeight.w600,
                                              fontSize: isTablet ? 14 : 11,
                                              color: isSelected ? Colors.white : textColor,
                                            ),
                                          ),
                                          SizedBox(height: isTablet ? 4 : 2),
                                          Text(
                                            _formatPrice(tier.effectivePrice),
                                            style: TextStyle(
                                              fontFamily: 'Poppins',
                                              fontWeight: FontWeight.w500,
                                              fontSize: isTablet ? 13 : 10,
                                              color: isSelected ? Colors.white70 : secondaryTextColor,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  );
                                }),
                              ),
                              SizedBox(height: isTablet ? 16 : 12),
                            ],
                            Divider(height: 1, thickness: 1, color: borderColor),
                            SizedBox(height: isTablet ? 24 : 16),
                            // Price
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.baseline,
                              textBaseline: TextBaseline.alphabetic,
                              children: [
                                Text(
                                  _formatPrice(dialogDisplayPrice),
                                  style: TextStyle(
                                    fontFamily: 'Poppins',
                                    fontWeight: FontWeight.w400,
                                    fontSize: priceSize,
                                    height: 1.0,
                                    letterSpacing: -0.18,
                                    color: textColor,
                                  ),
                                ),
                                if (dialogDisplayDuration != null) ...[
                                  SizedBox(width: isTablet ? 12 : 8),
                                  Text(
                                    '/ ${_formatDuration(dialogDisplayDuration)}',
                                    style: TextStyle(
                                      fontFamily: 'Poppins',
                                      fontWeight: FontWeight.w400,
                                      fontSize: durationSize,
                                      color: textColor.withValues(alpha: 0.5),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                            if (hasTiers && (selectedTier!.originalPrice ?? selectedTier.price) > selectedTier.effectivePrice) ...[
                              SizedBox(height: isTablet ? 4 : 2),
                              Text(
                                '${_formatPrice(selectedTier.originalPrice ?? selectedTier.price)} (${(((selectedTier.originalPrice ?? selectedTier.price) - selectedTier.effectivePrice) * 100 ~/ (selectedTier.originalPrice ?? selectedTier.price))}% off)',
                                style: TextStyle(
                                  fontFamily: 'Poppins',
                                  fontWeight: FontWeight.w400,
                                  fontSize: saleSize,
                                  color: const Color(0xFF4CAF50),
                                  decoration: TextDecoration.lineThrough,
                                  decorationColor: secondaryTextColor,
                                ),
                              ),
                            ] else if (package.isOnSale) ...[
                              SizedBox(height: isTablet ? 8 : 4),
                              Text(
                                'Limited Time Offer',
                                style: TextStyle(
                                  fontFamily: 'Poppins',
                                  fontWeight: FontWeight.w400,
                                  fontSize: saleSize,
                                  color: secondaryTextColor,
                                ),
                              ),
                            ],
                          ],
                        );
                      },
                    ),
                    SizedBox(height: isTablet ? 28 : 16),
                    // Credited combo offer — the better deal leads, since this
                    // is the moment the customer is choosing what to buy.
                    ComboOfferSection(
                      packageId: package.packageId,
                      isCombo: package.type?.toLowerCase() == 'combo',
                      isPurchased: package.isPurchased,
                      isDark: isDark,
                      isTablet: isTablet,
                      onTake: (offer) {
                        Navigator.of(dialogContext).pop(false);
                        _takeComboOffer(offer);
                      },
                    ),
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
                          padding: EdgeInsets.symmetric(horizontal: btnPadH, vertical: btnPadV),
                        ),
                        child: Text(
                          Platform.isIOS ? 'Learn More' : 'Enroll Now',
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
                    SizedBox(height: isTablet ? 14 : 8),
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
                            width: isTablet ? 1.5 : 1,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(btnRadius),
                          ),
                          padding: EdgeInsets.symmetric(horizontal: btnPadH, vertical: btnPadV),
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

              SizedBox(height: isTablet ? 0 : 24),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPopupFeatureItem(String text, bool isDark, Color textColor, Color iconColor, Color featureBgColor, {
    bool isTablet = false,
    double? iconSize,
    double? checkSize,
    double? textSize,
    double? iconGap,
  }) {
    final circleSize = iconSize ?? (isTablet ? 20.0 : 16.0);
    final checkIconSize = checkSize ?? (isTablet ? 13.0 : 10.0);
    final fontSize = textSize ?? (isTablet ? 15.0 : 12.0);
    final gap = iconGap ?? (isTablet ? 10.0 : 8.0);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: circleSize,
          height: circleSize,
          margin: EdgeInsets.only(top: isTablet ? 4 : 2),
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
        SizedBox(width: gap),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              fontFamily: 'Poppins',
              fontWeight: FontWeight.w400,
              fontSize: fontSize,
              height: isTablet ? 1.45 : 1.2,
              color: textColor,
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _processPayment() async {
    if (_package == null) return;

    // Show billing address bottom sheet before payment
    Address? savedAddress;
    try {
      final user = await UserService().getProfile();
      if (user.billingAddress != null && user.billingAddress!.isNotEmpty) {
        savedAddress = Address.fromJson(user.billingAddress!);
      }
    } catch (_) {}

    if (!mounted) return;

    final addressResult = await showAddressSheet(
      context,
      initialAddress: savedAddress,
    );

    if (addressResult == null || !mounted) return;
    final billingAddress = addressResult['billing']!;

    setState(() => _isProcessing = true);

    try {
      // Step 1: Create Zoho payment session
      final hasTiers = _package!.hasTiers && _package!.tiers != null && _package!.tiers!.isNotEmpty;
      final paymentSession = await _dashboardService.createPackagePaymentSession(
        _package!.packageId,
        billingAddress: billingAddress.toJson(),
        tierIndex: hasTiers ? _selectedTierIndex : null,
      );

      if (!mounted) return;

      // Step 2: Show Zoho payment widget
      final result = await Navigator.of(context, rootNavigator: true).push<GatewayResponse>(
        MaterialPageRoute(
          builder: (context) => GatewayWidget(
            paymentSession: paymentSession,
            onPaymentComplete: (response) {
              Navigator.pop(context, response);
            },
          ),
          fullscreenDialog: true,
        ),
      );

      // Step 3: Handle payment response
      if (result != null && mounted) {
        if (result.isSuccess) {
          // Verify payment with backend
          final verification = await _dashboardService.verifyPackagePayment(
            paymentSessionId: result.paymentSessionId!,
            paymentId: result.paymentId!,
            signature: result.signature,
          );

          if (verification.success && mounted) {
            setState(() => _isProcessing = false);
            // Navigate to congratulations screen with purchase ID
            context.go('/success?purchaseId=${verification.purchaseId}');
          } else if (mounted) {
            _showError('Payment verification failed. Please contact support.');
          }
        } else if (result.isFailed) {
          _showError('Payment failed: ${result.errorMessage ?? "Unknown error"}');
        } else if (result.isCancelled) {
          _showInfo('Payment cancelled');
        }
      }
    } catch (e) {
      if (mounted) {
        _showError('Error processing payment: $e');
      }
    } finally {
      if (mounted) {
        setState(() => _isProcessing = false);
      }
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    showAppDialog(context, message: message.replaceAll('Exception: ', ''), type: AppDialogType.info);
  }

  void _showInfo(String message) {
    if (!mounted) return;
    showAppDialog(context, message: message, type: AppDialogType.info);
  }

  void _showUpgradeSheet(PackageModel package) async {
    final currentIdx = package.currentTier?.tierIndex ?? package.currentTierIndex;
    if (currentIdx == null) return;

    final result = await showTierChangeSheet(
      context,
      package: package,
      currentTierIndex: currentIdx,
    );

    if (result == true && mounted) {
      // Reload package data to reflect the upgrade
      _loadPackageData();
    }
  }

  @override
  Widget build(BuildContext context) {
    final topPadding = MediaQuery.of(context).padding.top;
    final bottomPadding = MediaQuery.of(context).padding.bottom;
    final themeProvider = Provider.of<ThemeProvider>(context);
    final isDark = themeProvider.isDarkMode;
    final isTablet = ResponsiveHelper.isTablet(context);

    // Theme-aware colors
    final backgroundColor = isDark ? AppColors.darkBackground : Colors.white;
    final textColor = isDark ? AppColors.darkTextPrimary : const Color(0xFF000000);
    final secondaryTextColor = isDark ? AppColors.darkTextSecondary : const Color(0xFF666666);
    final cardBgColor = isDark ? AppColors.darkCardBackground : const Color(0xFFF8FAFC);
    final surfaceColor = isDark ? AppColors.darkSurface : Colors.white;
    final borderColor = isDark ? AppColors.darkDivider : const Color(0xFFE8EEF4);
    final iconBgColor = isDark ? const Color(0xFF1A3A5C) : const Color(0xFFDCEAF7);
    final iconColor = isDark ? const Color(0xFF00BEFA) : const Color(0xFF1847A2);
    final buttonColor = isDark ? const Color(0xFF0047CF) : const Color(0xFF0000D1);
    final priceColor = isDark ? const Color(0xFF00BEFA) : const Color(0xFF1847A2);

    final hPadding = isTablet ? ResponsiveHelper.horizontalPadding(context) : 16.0;

    if (_isLoading) {
      return Scaffold(
        backgroundColor: backgroundColor,
        body: Center(
          child: CircularProgressIndicator(color: iconColor),
        ),
      );
    }

    if (_error != null || _package == null) {
      return Scaffold(
        backgroundColor: backgroundColor,
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.error_outline, size: isTablet ? 60 : 48, color: secondaryTextColor),
              SizedBox(height: isTablet ? 20 : 16),
              Text(
                'Failed to load package',
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: isTablet ? 20 : 16,
                  color: textColor,
                ),
              ),
              SizedBox(height: isTablet ? 20 : 16),
              ElevatedButton(
                onPressed: _loadPackageData,
                style: ElevatedButton.styleFrom(backgroundColor: iconColor),
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    final package = _package!;

    // Show revoked state
    if (package.accessRevoked) {
      return Scaffold(
        backgroundColor: backgroundColor,
        body: Center(
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: hPadding + 16),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: isTablet ? 100 : 80,
                  height: isTablet ? 100 : 80,
                  decoration: BoxDecoration(
                    color: const Color(0xFFE53935).withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.block,
                    size: isTablet ? 50 : 40,
                    color: const Color(0xFFE53935),
                  ),
                ),
                SizedBox(height: isTablet ? 28 : 24),
                Text(
                  'Access Revoked',
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: isTablet ? 26 : 22,
                    fontWeight: FontWeight.w600,
                    color: textColor,
                  ),
                ),
                SizedBox(height: isTablet ? 14 : 12),
                Text(
                  'Your access to this package has been revoked.\nPlease contact support for assistance.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: isTablet ? 17 : 14,
                    fontWeight: FontWeight.w400,
                    color: secondaryTextColor,
                    height: 1.5,
                  ),
                ),
                SizedBox(height: isTablet ? 36 : 32),
                ElevatedButton(
                  onPressed: () => context.pop(),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: buttonColor,
                    padding: EdgeInsets.symmetric(horizontal: isTablet ? 40 : 32, vertical: isTablet ? 16 : 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: Text(
                    'Go Back',
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: isTablet ? 18 : 15,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final hasTiers = package.hasTiers && package.tiers != null && package.tiers!.isNotEmpty;
    final selectedTier = hasTiers ? package.tiers![_selectedTierIndex] : null;
    final displayPrice = hasTiers
        ? selectedTier!.effectivePrice
        : (package.isOnSale && package.salePrice != null ? package.salePrice! : package.price);
    final displayDuration = hasTiers ? selectedTier!.durationDays : package.durationDays;
    final originalForDiscount = hasTiers ? (selectedTier!.originalPrice ?? selectedTier.price) : package.originalPrice;
    final discount = _calculateDiscount(displayPrice, originalForDiscount);

    return Scaffold(
      backgroundColor: backgroundColor,
      body: Stack(
        children: [
          // Main scrollable content
          RefreshIndicator(
            onRefresh: _loadPackageData,
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              child: Center(
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: ResponsiveHelper.getMaxContentWidth(context)),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Header with back button
                    Container(
                      padding: EdgeInsets.only(top: topPadding + (isTablet ? 20 : 16), left: hPadding, right: hPadding),
                      child: Row(
                        children: [
                          GestureDetector(
                            onTap: () => context.pop(),
                            child: Container(
                              width: isTablet ? 54 : 44,
                              height: isTablet ? 54 : 44,
                              decoration: BoxDecoration(
                                color: surfaceColor,
                                borderRadius: BorderRadius.circular(isTablet ? 16 : 12),
                                border: Border.all(color: borderColor, width: 1),
                              ),
                              child: Center(
                                child: Icon(
                                  Icons.arrow_back_ios_new,
                                  size: isTablet ? 22 : 18,
                                  color: textColor,
                                ),
                              ),
                            ),
                          ),
                          SizedBox(width: isTablet ? 20 : 16),
                          Text(
                            'Course Details',
                            style: TextStyle(
                              fontFamily: 'Poppins',
                              fontSize: isTablet ? 25 : 20,
                              fontWeight: FontWeight.w600,
                              color: textColor,
                            ),
                          ),
                        ],
                      ),
                    ),

                    SizedBox(height: isTablet ? 30 : 24),

                    // Course Banner
                    Padding(
                      padding: EdgeInsets.symmetric(horizontal: hPadding),
                      child: Container(
                        width: double.infinity,
                        height: isTablet ? 225 : 180,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(isTablet ? 26 : 20),
                          gradient: LinearGradient(
                            begin: const Alignment(-0.85, 0),
                            end: const Alignment(0.85, 0),
                            colors: isDark
                                ? [const Color(0xFF0D2A5C), const Color(0xFF1A5A9E)]
                                : [const Color(0xFF1847A2), const Color(0xFF8EC6FF)],
                            stops: const [0.3469, 0.7087],
                          ),
                        ),
                        child: Stack(
                          children: [
                            // Background pattern
                            Positioned(
                              right: -20,
                              bottom: -20,
                              child: Opacity(
                                opacity: 0.1,
                                child: Icon(
                                  package.type == 'Practical' ? Icons.science : Icons.school,
                                  size: isTablet ? 225 : 180,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                            // Content
                            Padding(
                              padding: EdgeInsets.all(isTablet ? 26 : 20),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Container(
                                    padding: EdgeInsets.symmetric(horizontal: isTablet ? 16 : 12, vertical: isTablet ? 8 : 6),
                                    decoration: BoxDecoration(
                                      color: Colors.white.withValues(alpha: 0.2),
                                      borderRadius: BorderRadius.circular(20),
                                    ),
                                    child: Text(
                                      '${package.type?.toUpperCase() ?? 'COURSE'} PACKAGE',
                                      style: TextStyle(
                                        fontFamily: 'Poppins',
                                        fontSize: isTablet ? 14 : 11,
                                        fontWeight: FontWeight.w600,
                                        color: Colors.white,
                                        letterSpacing: 1,
                                      ),
                                    ),
                                  ),
                                  SizedBox(height: isTablet ? 16 : 12),
                                  Text(
                                    package.name,
                                    style: TextStyle(
                                      fontFamily: 'Poppins',
                                      fontSize: isTablet ? 30 : 24,
                                      fontWeight: FontWeight.w700,
                                      color: Colors.white,
                                      height: 1.2,
                                    ),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const Spacer(),
                                  Row(
                                    children: [
                                      if (displayDuration != null) ...[
                                        Icon(Icons.access_time, size: isTablet ? 20 : 16, color: Colors.white70),
                                        SizedBox(width: isTablet ? 8 : 6),
                                        Text(
                                          '${_formatDuration(displayDuration)} Access',
                                          style: TextStyle(
                                            fontFamily: 'Poppins',
                                            fontSize: isTablet ? 16 : 13,
                                            color: Colors.white70,
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    SizedBox(height: isTablet ? 30 : 24),

                    // Tier Selector (if package has tiers)
                    if (hasTiers) ...[
                      Padding(
                        padding: EdgeInsets.symmetric(horizontal: hPadding),
                        child: Text(
                          'Select Duration',
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: isTablet ? 22 : 18,
                            fontWeight: FontWeight.w600,
                            color: textColor,
                          ),
                        ),
                      ),
                      SizedBox(height: isTablet ? 16 : 12),
                      SizedBox(
                        height: isTablet ? 120 : 100,
                        child: ListView.builder(
                          scrollDirection: Axis.horizontal,
                          padding: EdgeInsets.symmetric(horizontal: hPadding),
                          itemCount: package.tiers!.length,
                          itemBuilder: (context, i) {
                            final tier = package.tiers![i];
                            final isSelected = _selectedTierIndex == i;
                            return GestureDetector(
                              onTap: () => setState(() => _selectedTierIndex = i),
                              child: Container(
                                width: isTablet ? 160 : 130,
                                margin: EdgeInsets.only(right: isTablet ? 14 : 10),
                                padding: EdgeInsets.all(isTablet ? 16 : 12),
                                decoration: BoxDecoration(
                                  color: isSelected ? buttonColor : surfaceColor,
                                  borderRadius: BorderRadius.circular(isTablet ? 18 : 14),
                                  border: Border.all(
                                    color: isSelected ? buttonColor : borderColor,
                                    width: isSelected ? 2 : 1,
                                  ),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Text(
                                      tier.name,
                                      style: TextStyle(
                                        fontFamily: 'Poppins',
                                        fontSize: isTablet ? 16 : 13,
                                        fontWeight: FontWeight.w600,
                                        color: isSelected ? Colors.white : textColor,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    SizedBox(height: isTablet ? 6 : 4),
                                    Text(
                                      _formatPrice(tier.effectivePrice),
                                      style: TextStyle(
                                        fontFamily: 'Poppins',
                                        fontSize: isTablet ? 18 : 15,
                                        fontWeight: FontWeight.w700,
                                        color: isSelected ? Colors.white : priceColor,
                                      ),
                                    ),
                                    if ((tier.originalPrice ?? tier.price) > tier.effectivePrice) ...[
                                      SizedBox(height: isTablet ? 2 : 1),
                                      Text(
                                        _formatPrice(tier.originalPrice ?? tier.price),
                                        style: TextStyle(
                                          fontFamily: 'Poppins',
                                          fontSize: isTablet ? 13 : 11,
                                          color: isSelected ? Colors.white54 : secondaryTextColor,
                                          decoration: TextDecoration.lineThrough,
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                      SizedBox(height: isTablet ? 30 : 24),
                    ],

                    // Course Overview
                    Padding(
                      padding: EdgeInsets.symmetric(horizontal: hPadding),
                      child: Text(
                        'Course Overview',
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: isTablet ? 22 : 18,
                          fontWeight: FontWeight.w600,
                          color: textColor,
                        ),
                      ),
                    ),

                    SizedBox(height: isTablet ? 16 : 12),

                    // Rich description (new) or plain description + features (backward compat)
                    if (package.hasRichDescription) ...[
                      Padding(
                        padding: EdgeInsets.symmetric(horizontal: hPadding),
                        child: HtmlWidget(
                          package.richDescription!,
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
                      ),
                    ] else ...[
                      Padding(
                        padding: EdgeInsets.symmetric(horizontal: hPadding),
                        child: Text(
                          package.description ?? 'Master your medical education with our comprehensive ${package.type?.toLowerCase() ?? ''} package. This course covers all essential topics with expert faculty guidance and structured learning paths.',
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: isTablet ? 17 : 14,
                            fontWeight: FontWeight.w400,
                            color: secondaryTextColor,
                            height: 1.5,
                          ),
                        ),
                      ),

                      SizedBox(height: isTablet ? 30 : 24),

                      // What's Included
                      Padding(
                        padding: EdgeInsets.symmetric(horizontal: hPadding),
                        child: Text(
                          'What\'s Included',
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: isTablet ? 22 : 18,
                            fontWeight: FontWeight.w600,
                            color: textColor,
                          ),
                        ),
                      ),

                      SizedBox(height: isTablet ? 20 : 16),

                      // Feature Cards from package features
                      Padding(
                        padding: EdgeInsets.symmetric(horizontal: hPadding),
                        child: Column(
                          children: _buildFeatureCards(package, isDark, textColor, cardBgColor, borderColor, iconBgColor, iconColor, isTablet: isTablet),
                        ),
                      ),
                    ],

                    SizedBox(height: isTablet ? 30 : 24),

                    // Space for bottom button
                    SizedBox(height: bottomPadding + (isTablet ? 150 : 120)),
                  ],
                ),
              ),
            ),
          ),
          ),

          // Loading overlay
          if (_isProcessing)
            Container(
              color: Colors.black.withValues(alpha: 0.5),
              child: const Center(
                child: CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              ),
            ),

          // Bottom Buy Section
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Container(
              padding: EdgeInsets.only(
                left: isTablet ? 26 : 20,
                right: isTablet ? 26 : 20,
                top: isTablet ? 20 : 16,
                bottom: bottomPadding + (isTablet ? 20 : 16),
              ),
              decoration: BoxDecoration(
                color: surfaceColor,
                boxShadow: [
                  BoxShadow(
                    color: isDark ? Colors.black.withValues(alpha: 0.3) : Colors.black.withValues(alpha: 0.08),
                    blurRadius: 20,
                    offset: const Offset(0, -4),
                  ),
                ],
              ),
              child: Center(
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: ResponsiveHelper.getMaxContentWidth(context)),
                  child: Row(
                    children: [
                      // Price
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                _formatPrice(displayPrice),
                                style: TextStyle(
                                  fontFamily: 'Poppins',
                                  fontSize: isTablet ? 35 : 28,
                                  fontWeight: FontWeight.w400,
                                  color: priceColor,
                                ),
                              ),
                              if (originalForDiscount != null && originalForDiscount > displayPrice) ...[
                                SizedBox(width: isTablet ? 10 : 8),
                                Padding(
                                  padding: EdgeInsets.only(bottom: isTablet ? 6 : 4),
                                  child: Text(
                                    _formatPrice(originalForDiscount),
                                    style: TextStyle(
                                      fontFamily: 'Poppins',
                                      fontSize: isTablet ? 20 : 16,
                                      fontWeight: FontWeight.w400,
                                      color: textColor.withValues(alpha: 0.4),
                                      decoration: TextDecoration.lineThrough,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                          if (discount > 0) ...[
                            SizedBox(height: isTablet ? 3 : 2),
                            Container(
                              padding: EdgeInsets.symmetric(horizontal: isTablet ? 10 : 8, vertical: isTablet ? 3 : 2),
                              decoration: BoxDecoration(
                                color: const Color(0xFF4CAF50).withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(isTablet ? 6 : 4),
                              ),
                              child: Text(
                                '$discount% OFF',
                                style: TextStyle(
                                  fontFamily: 'Poppins',
                                  fontSize: isTablet ? 14 : 11,
                                  fontWeight: FontWeight.w600,
                                  color: const Color(0xFF4CAF50),
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const Spacer(),
                      // Buy / Upgrade Button
                      Builder(
                        builder: (context) {
                          final currentIdx = package.currentTier?.tierIndex ?? package.currentTierIndex;
                          final canUpgrade = hasTiers &&
                              currentIdx != null &&
                              _selectedTierIndex > currentIdx;
                          final isCurrentTier = hasTiers &&
                              currentIdx != null &&
                              _selectedTierIndex == currentIdx;

                          if (isCurrentTier) {
                            return Container(
                              width: isTablet ? 200 : 160,
                              height: isTablet ? 66 : 54,
                              decoration: BoxDecoration(
                                color: const Color(0xFF4CAF50),
                                borderRadius: BorderRadius.circular(isTablet ? 21 : 16),
                              ),
                              child: Center(
                                child: Text(
                                  'Current Plan',
                                  style: TextStyle(
                                    fontFamily: 'Poppins',
                                    fontSize: isTablet ? 20 : 16,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            );
                          }

                          return GestureDetector(
                            onTap: _isProcessing
                                ? null
                                : canUpgrade
                                    ? WebStoreLauncher.shouldUseWebStore
                                        ? () => WebStoreLauncher.openProductPage(context, productType: 'packages', productId: package.packageId)
                                        : () => _showUpgradeSheet(package)
                                    : _showPaymentPopup,
                            child: Container(
                              width: isTablet ? 200 : 160,
                              height: isTablet ? 66 : 54,
                              decoration: BoxDecoration(
                                color: buttonColor,
                                borderRadius: BorderRadius.circular(isTablet ? 21 : 16),
                                boxShadow: [
                                  BoxShadow(
                                    color: buttonColor.withValues(alpha: 0.3),
                                    blurRadius: 12,
                                    offset: const Offset(0, 4),
                                  ),
                                ],
                              ),
                              child: Center(
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    if (WebStoreLauncher.shouldUseWebStore)
                                      const Padding(
                                        padding: EdgeInsets.only(right: 6),
                                        child: Icon(Icons.open_in_new, color: Colors.white, size: 16),
                                      ),
                                    Text(
                                      canUpgrade
                                          ? (WebStoreLauncher.shouldUseWebStore ? 'Change Plan' : (Platform.isIOS ? 'Change Plan' : 'Upgrade'))
                                          : (WebStoreLauncher.shouldUseWebStore ? 'Learn More' : (Platform.isIOS ? 'Learn More' : 'Buy Now')),
                                      style: TextStyle(
                                        fontFamily: 'Poppins',
                                        fontSize: isTablet ? 22 : 18,
                                        fontWeight: FontWeight.w600,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _colorToHex(Color color) {
    final r = (color.r * 255.0).round().clamp(0, 255);
    final g = (color.g * 255.0).round().clamp(0, 255);
    final b = (color.b * 255.0).round().clamp(0, 255);
    return '#${r.toRadixString(16).padLeft(2, '0')}${g.toRadixString(16).padLeft(2, '0')}${b.toRadixString(16).padLeft(2, '0')}';
  }

  List<Widget> _buildFeatureCards(
    PackageModel package,
    bool isDark,
    Color textColor,
    Color cardBgColor,
    Color borderColor,
    Color iconBgColor,
    Color iconColor, {
    bool isTablet = false,
  }) {
    final features = package.features;

    if (features != null && features.isNotEmpty) {
      return features.map((feature) {
        return Padding(
          padding: EdgeInsets.only(bottom: isTablet ? 16 : 12),
          child: _buildFeatureCard(
            icon: _getFeatureIcon(feature),
            title: feature,
            subtitle: '',
            isDark: isDark,
            textColor: textColor,
            cardBgColor: cardBgColor,
            borderColor: borderColor,
            iconBgColor: iconBgColor,
            iconColor: iconColor,
            isTablet: isTablet,
          ),
        );
      }).toList();
    }

    // Default features if none provided
    final defaultFeatures = package.type == 'Practical'
        ? [
            {'icon': Icons.science_outlined, 'title': 'Practical Demonstrations', 'subtitle': 'Hands-on learning experience'},
            {'icon': Icons.live_tv_outlined, 'title': 'Live Sessions', 'subtitle': 'Interactive live classes'},
            {'icon': Icons.support_agent_outlined, 'title': 'Expert Support', 'subtitle': '24/7 doubt resolution'},
          ]
        : [
            {'icon': Icons.video_library_outlined, 'title': 'Video Lectures', 'subtitle': 'High-quality recorded content'},
            {'icon': Icons.menu_book_outlined, 'title': 'Study Materials', 'subtitle': 'Comprehensive notes & PDFs'},
            {'icon': Icons.support_agent_outlined, 'title': 'Expert Support', 'subtitle': '24/7 doubt resolution'},
          ];

    return defaultFeatures.map((f) {
      return Padding(
        padding: EdgeInsets.only(bottom: isTablet ? 16 : 12),
        child: _buildFeatureCard(
          icon: f['icon'] as IconData,
          title: f['title'] as String,
          subtitle: f['subtitle'] as String,
          isDark: isDark,
          textColor: textColor,
          cardBgColor: cardBgColor,
          borderColor: borderColor,
          iconBgColor: iconBgColor,
          iconColor: iconColor,
          isTablet: isTablet,
        ),
      );
    }).toList();
  }

  IconData _getFeatureIcon(String feature) {
    final lowerFeature = feature.toLowerCase();
    if (lowerFeature.contains('video') || lowerFeature.contains('lecture')) {
      return Icons.video_library_outlined;
    } else if (lowerFeature.contains('live') || lowerFeature.contains('session')) {
      return Icons.live_tv_outlined;
    } else if (lowerFeature.contains('note') || lowerFeature.contains('material') || lowerFeature.contains('pdf')) {
      return Icons.menu_book_outlined;
    } else if (lowerFeature.contains('test') || lowerFeature.contains('quiz') || lowerFeature.contains('mcq')) {
      return Icons.quiz_outlined;
    } else if (lowerFeature.contains('support') || lowerFeature.contains('doubt')) {
      return Icons.support_agent_outlined;
    } else if (lowerFeature.contains('practical') || lowerFeature.contains('lab')) {
      return Icons.science_outlined;
    } else {
      return Icons.check_circle_outline;
    }
  }

  Widget _buildFeatureCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool isDark,
    required Color textColor,
    required Color cardBgColor,
    required Color borderColor,
    required Color iconBgColor,
    required Color iconColor,
    bool isTablet = false,
  }) {
    return Container(
      padding: EdgeInsets.all(isTablet ? 20 : 16),
      decoration: BoxDecoration(
        color: cardBgColor,
        borderRadius: BorderRadius.circular(isTablet ? 18 : 14),
        border: Border.all(color: borderColor, width: 1),
      ),
      child: Row(
        children: [
          Container(
            width: isTablet ? 60 : 48,
            height: isTablet ? 60 : 48,
            decoration: BoxDecoration(
              color: iconBgColor,
              borderRadius: BorderRadius.circular(isTablet ? 16 : 12),
            ),
            child: Center(
              child: Icon(
                icon,
                size: isTablet ? 30 : 24,
                color: iconColor,
              ),
            ),
          ),
          SizedBox(width: isTablet ? 18 : 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: isTablet ? 19 : 15,
                    fontWeight: FontWeight.w600,
                    color: textColor,
                  ),
                ),
                if (subtitle.isNotEmpty) ...[
                  SizedBox(height: isTablet ? 3 : 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: isTablet ? 16 : 13,
                      fontWeight: FontWeight.w400,
                      color: textColor.withValues(alpha: 0.5),
                    ),
                  ),
                ],
              ],
            ),
          ),
          Icon(
            Icons.check_circle,
            size: isTablet ? 27 : 22,
            color: const Color(0xFF4CAF50),
          ),
        ],
      ),
    );
  }
}
