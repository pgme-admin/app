import 'dart:io';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:pgme/core_android/providers/theme_provider.dart';
import 'package:pgme/core_android/theme/app_theme.dart';
import 'package:pgme/core_android/models/package_model.dart';
import 'package:pgme/core_android/services/dashboard_service.dart';
import 'package:pgme/features_android/home/providers/dashboard_provider.dart';
import 'package:pgme/core_android/widgets/shimmer_widgets.dart';
import 'package:pgme/core_android/utils/responsive_helper.dart';
import 'package:pgme/core_android/utils/web_store_launcher.dart';

class AllPackagesScreen extends StatefulWidget {
  const AllPackagesScreen({super.key});

  @override
  State<AllPackagesScreen> createState() => _AllPackagesScreenState();
}

class _AllPackagesScreenState extends State<AllPackagesScreen>
    with WidgetsBindingObserver {
  int _selectedIndex = 0;
  bool _isLoading = true;
  List<PackageModel> _packages = [];
  String? _error;
  final DashboardService _dashboardService = DashboardService();

  @override
  void initState() {
    super.initState();
    if (Platform.isIOS) WidgetsBinding.instance.addObserver(this);
    _loadPackages();
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
      _loadPackages();
    }
  }

  Future<void> _loadPackages() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      // Get the user's selected subject from provider
      final dashboardProvider = context.read<DashboardProvider>();
      final subjectId = dashboardProvider.primarySubject?.subjectId;

      // Load packages for the selected subject
      final allPackages = await _dashboardService.getPackages(
        subjectId: subjectId,
        forceRefresh: true,
      );

      // Filter to only show Theory, Practical and Combo packages
      final filteredPackages = allPackages.where((pkg) {
        final type = pkg.type?.toLowerCase();
        return type == 'theory' || type == 'practical' || type == 'combo';
      }).toList();

      if (mounted) {
        setState(() {
          _packages = filteredPackages;
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

  List<Color> _getGradientColors(String? type, bool isDark) {
    if (type == 'Practical') {
      return isDark
          ? [const Color(0xFF3D2A6B), const Color(0xFF6B4EAF)]
          : [const Color(0xFF6B4EAF), const Color(0xFF9D7FD9)];
    }
    // Theory or default
    return isDark
        ? [const Color(0xFF0D2A5C), const Color(0xFF1A5A9E)]
        : [const Color(0xFF1847A2), const Color(0xFF5B9BD5)];
  }

  IconData _getPackageIcon(String? type) {
    if (type == 'Practical') {
      return Icons.science_outlined;
    }
    return Icons.menu_book_outlined;
  }

  void _selectPackage(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  void _enrollPackage(PackageModel package) {
    if (package.accessRevoked) {
      // Show revoked message
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Access Revoked'),
          content: const Text(
            'Your access to this package has been revoked. Please contact support for assistance.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      return;
    }
    if (package.isPurchased) {
      context.pop();
      // Navigate to appropriate series screen based on package type
      // Don't pass packageId so it shows the landing page with options
      if (package.type == 'Theory') {
        context.push('/revision-series?subscribed=true');
      } else if (package.type == 'Practical') {
        context.push('/practical-series?subscribed=true');
      } else {
        context.go('/home');
      }
    } else if (WebStoreLauncher.shouldUseWebStore) {
      // iOS: redirect to web store to avoid Apple IAP requirement
      WebStoreLauncher.openProductPage(
        context,
        productType: 'packages',
        productId: package.packageId,
      );
    } else {
      context.pop();
      context.push('/package-access?packageId=${package.packageId}');
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
    final backgroundColor = isDark ? AppColors.darkBackground : const Color(0xFFF5F7FA);
    final surfaceColor = isDark ? AppColors.darkSurface : Colors.white;
    final cardBgColor = isDark ? AppColors.darkCardBackground : Colors.white;
    final textColor = isDark ? AppColors.darkTextPrimary : const Color(0xFF000000);
    final secondaryTextColor = isDark ? AppColors.darkTextSecondary : const Color(0xFF666666);
    final borderColor = isDark ? AppColors.darkDivider : Colors.transparent;
    final buttonColor = isDark ? const Color(0xFF0047CF) : const Color(0xFF0000D1);
    final priceColor = isDark ? const Color(0xFF00BEFA) : const Color(0xFF1847A2);

    final hPadding = isTablet ? ResponsiveHelper.horizontalPadding(context) : 16.0;

    if (_isLoading) {
      return Scaffold(
        backgroundColor: backgroundColor,
        body: ShimmerWidgets.packageGridShimmer(isDark: isDark),
      );
    }

    if (_error != null || _packages.isEmpty) {
      return Scaffold(
        backgroundColor: backgroundColor,
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.error_outline, size: isTablet ? 60 : 48, color: secondaryTextColor),
              SizedBox(height: isTablet ? 20 : 16),
              Text(
                _error != null ? 'Failed to load packages' : 'No packages available',
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: isTablet ? 20 : 16,
                  color: textColor,
                ),
              ),
              SizedBox(height: isTablet ? 20 : 16),
              ElevatedButton(
                onPressed: _loadPackages,
                style: ElevatedButton.styleFrom(backgroundColor: priceColor),
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: backgroundColor,
      body: Column(
        children: [
          // Header
          Container(
            padding: EdgeInsets.only(top: topPadding + (isTablet ? 20 : 16), left: hPadding, right: hPadding, bottom: isTablet ? 20 : 16),
            decoration: BoxDecoration(
              color: surfaceColor,
              boxShadow: isDark
                  ? [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.2),
                        blurRadius: 10,
                        offset: const Offset(0, 2),
                      ),
                    ]
                  : const [
                      BoxShadow(
                        color: Color(0x0A000000),
                        blurRadius: 10,
                        offset: Offset(0, 2),
                      ),
                    ],
            ),
            child: Row(
              children: [
                GestureDetector(
                  onTap: () => context.pop(),
                  child: Container(
                    width: isTablet ? 54 : 44,
                    height: isTablet ? 54 : 44,
                    decoration: BoxDecoration(
                      color: backgroundColor,
                      borderRadius: BorderRadius.circular(isTablet ? 16 : 12),
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
                Expanded(
                  child: Text(
                    'Choose Your Package',
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: isTablet ? 25 : 20,
                      fontWeight: FontWeight.w600,
                      color: textColor,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Package List
          Expanded(
            child: Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: ResponsiveHelper.getMaxContentWidth(context)),
                child: RefreshIndicator(
                  onRefresh: _loadPackages,
                  child: ListView.builder(
                  padding: EdgeInsets.only(top: isTablet ? 26 : 20, left: hPadding, right: hPadding, bottom: bottomPadding + (isTablet ? 125 : 100)),
                  itemCount: _packages.length,
                  itemBuilder: (context, index) {
                    final package = _packages[index];
                    final isSelected = _selectedIndex == index;
                    return _buildPackageCard(package, index, isSelected, isDark, textColor, secondaryTextColor, cardBgColor, borderColor, isTablet: isTablet);
                  },
                ),
                ),
              ),
            ),
          ),
        ],
      ),

      // Bottom Enroll Button
      bottomSheet: Container(
        padding: EdgeInsets.only(left: isTablet ? 26 : 20, right: isTablet ? 26 : 20, top: isTablet ? 20 : 16, bottom: bottomPadding + (isTablet ? 20 : 16)),
        decoration: BoxDecoration(
          color: surfaceColor,
          borderRadius: BorderRadius.vertical(top: Radius.circular(isTablet ? 28 : 20)),
          boxShadow: [
            BoxShadow(
              color: isDark ? Colors.black.withValues(alpha: 0.3) : Colors.black.withValues(alpha: 0.08),
              blurRadius: 20,
              offset: const Offset(0, -4),
            ),
          ],
        ),
        child: Center(
          heightFactor: 1.0,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: ResponsiveHelper.getMaxContentWidth(context)),
            child: Row(
              children: [
                // Selected package info
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _packages[_selectedIndex].name,
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: isTablet ? 17 : 14,
                          fontWeight: FontWeight.w500,
                          color: secondaryTextColor,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      SizedBox(height: isTablet ? 3 : 2),
                      Text(
                        _formatPrice(
                          _packages[_selectedIndex].hasTiers && _packages[_selectedIndex].tiers != null && _packages[_selectedIndex].tiers!.isNotEmpty
                              ? _packages[_selectedIndex].startingPrice ?? _packages[_selectedIndex].tiers!.first.effectivePrice
                              : (_packages[_selectedIndex].isOnSale && _packages[_selectedIndex].salePrice != null
                                  ? _packages[_selectedIndex].salePrice!
                                  : _packages[_selectedIndex].price),
                        ),
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: isTablet ? 30 : 24,
                          fontWeight: FontWeight.w400,
                          color: priceColor,
                        ),
                      ),
                    ],
                  ),
                ),
                // Enroll/Access Button
                GestureDetector(
                  onTap: () => _enrollPackage(_packages[_selectedIndex]),
                  child: Container(
                    width: isTablet ? 200 : 160,
                    height: isTablet ? 66 : 54,
                    decoration: BoxDecoration(
                      color: _packages[_selectedIndex].accessRevoked
                          ? const Color(0xFFE53935)
                          : _packages[_selectedIndex].isPurchased
                              ? const Color(0xFF4CAF50)
                              : buttonColor,
                      borderRadius: BorderRadius.circular(isTablet ? 21 : 16),
                      boxShadow: [
                        BoxShadow(
                          color: (_packages[_selectedIndex].accessRevoked
                              ? const Color(0xFFE53935)
                              : _packages[_selectedIndex].isPurchased
                                  ? const Color(0xFF4CAF50)
                                  : buttonColor).withValues(alpha: 0.3),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Center(
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (_packages[_selectedIndex].accessRevoked)
                            Padding(
                              padding: const EdgeInsets.only(right: 6),
                              child: Icon(Icons.block, color: Colors.white, size: isTablet ? 18 : 16),
                            )
                          else if (!_packages[_selectedIndex].isPurchased && WebStoreLauncher.shouldUseWebStore)
                            const Padding(
                              padding: EdgeInsets.only(right: 6),
                              child: Icon(Icons.open_in_new, color: Colors.white, size: 16),
                            ),
                          Flexible(
                            child: Text(
                              _packages[_selectedIndex].accessRevoked
                                  ? 'Revoked'
                                  : _packages[_selectedIndex].isPurchased
                                      ? 'Go to Content'
                                      : WebStoreLauncher.shouldUseWebStore
                                          ? 'Learn More'
                                          : (Platform.isIOS ? 'Learn More' : 'Enroll Now'),
                              style: TextStyle(
                                fontFamily: 'Poppins',
                                fontSize: isTablet ? 20 : 16,
                                fontWeight: FontWeight.w600,
                                color: Colors.white,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPackageCard(PackageModel package, int index, bool isSelected, bool isDark, Color textColor, Color secondaryTextColor, Color cardBgColor, Color borderColor, {bool isTablet = false}) {
    final selectedBorderColor = isDark ? const Color(0xFF00BEFA) : const Color(0xFF1847A2);
    final featureTextColor = isDark ? AppColors.darkTextPrimary : const Color(0xFF333333);
    final dividerColor = isDark ? AppColors.darkDivider : const Color(0xFFEEEEEE);
    final gradientColors = _getGradientColors(package.type, isDark);
    final hasTiers = package.hasTiers && package.tiers != null && package.tiers!.isNotEmpty;
    final displayPrice = hasTiers
        ? package.startingPrice ?? package.tiers!.first.effectivePrice
        : (package.isOnSale && package.salePrice != null ? package.salePrice! : package.price);
    final discount = hasTiers ? 0 : _calculateDiscount(displayPrice, package.originalPrice);

    return GestureDetector(
      onTap: () => _selectPackage(index),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: EdgeInsets.only(bottom: isTablet ? 20 : 16),
        decoration: BoxDecoration(
          color: cardBgColor,
          borderRadius: BorderRadius.circular(isTablet ? 26 : 20),
          border: Border.all(
            color: isSelected ? selectedBorderColor : borderColor,
            width: 2,
          ),
          boxShadow: [
            BoxShadow(
              color: isSelected
                  ? selectedBorderColor.withValues(alpha: 0.15)
                  : (isDark ? Colors.black.withValues(alpha: 0.2) : Colors.black.withValues(alpha: 0.05)),
              blurRadius: isSelected ? 20 : 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          children: [
            // Header with gradient
            Container(
              padding: EdgeInsets.all(isTablet ? 26 : 20),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: gradientColors,
                ),
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(isTablet ? 24 : 18),
                  topRight: Radius.circular(isTablet ? 24 : 18),
                ),
              ),
              child: Row(
                children: [
                  // Icon
                  Container(
                    width: isTablet ? 62 : 50,
                    height: isTablet ? 62 : 50,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(isTablet ? 18 : 14),
                    ),
                    child: Center(
                      child: Icon(
                        _getPackageIcon(package.type),
                        size: isTablet ? 32 : 26,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  SizedBox(width: isTablet ? 18 : 14),
                  // Title & Subtitle
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          package.name,
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: isTablet ? 22 : 18,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        SizedBox(height: isTablet ? 3 : 2),
                        Text(
                          package.type ?? 'Package',
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: isTablet ? 16 : 13,
                            fontWeight: FontWeight.w400,
                            color: Colors.white.withValues(alpha: 0.8),
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Badges
                  if (package.accessRevoked)
                    Container(
                      padding: EdgeInsets.symmetric(horizontal: isTablet ? 13 : 10, vertical: isTablet ? 7 : 5),
                      decoration: BoxDecoration(
                        color: const Color(0xFFE53935),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.block, color: Colors.white, size: isTablet ? 15 : 12),
                          SizedBox(width: isTablet ? 6 : 4),
                          Text(
                            'REVOKED',
                            style: TextStyle(
                              fontFamily: 'Poppins',
                              fontSize: isTablet ? 13 : 10,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ],
                      ),
                    )
                  else if (package.isPurchased)
                    Container(
                      padding: EdgeInsets.symmetric(horizontal: isTablet ? 13 : 10, vertical: isTablet ? 7 : 5),
                      decoration: BoxDecoration(
                        color: const Color(0xFF4CAF50),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.check_circle, color: Colors.white, size: isTablet ? 15 : 12),
                          SizedBox(width: isTablet ? 6 : 4),
                          Text(
                            'PURCHASED',
                            style: TextStyle(
                              fontFamily: 'Poppins',
                              fontSize: isTablet ? 13 : 10,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ],
                      ),
                    )
                  else if (index == 0)
                    Container(
                      padding: EdgeInsets.symmetric(horizontal: isTablet ? 13 : 10, vertical: isTablet ? 7 : 5),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        'POPULAR',
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: isTablet ? 13 : 10,
                          fontWeight: FontWeight.w700,
                          color: gradientColors[0],
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                ],
              ),
            ),

            // Content
            Padding(
              padding: EdgeInsets.all(isTablet ? 26 : 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Features or rich description excerpt
                  if (package.hasRichDescription)
                    Padding(
                      padding: EdgeInsets.only(bottom: isTablet ? 13 : 10),
                      child: Text(
                        package.richDescription!.replaceAll(RegExp(r'<[^>]*>'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim(),
                        maxLines: 4,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: isTablet ? 17 : 14,
                          fontWeight: FontWeight.w400,
                          color: featureTextColor,
                          height: 1.4,
                        ),
                      ),
                    )
                  else if (package.features != null && package.features!.isNotEmpty)
                    ...package.features!.take(4).map((feature) => Padding(
                      padding: EdgeInsets.only(bottom: isTablet ? 13 : 10),
                      child: Row(
                        children: [
                          Container(
                            width: isTablet ? 25 : 20,
                            height: isTablet ? 25 : 20,
                            decoration: BoxDecoration(
                              color: gradientColors[0].withValues(alpha: 0.1),
                              shape: BoxShape.circle,
                            ),
                            child: Center(
                              child: Icon(
                                Icons.check,
                                size: isTablet ? 15 : 12,
                                color: isDark ? gradientColors[1] : gradientColors[0],
                              ),
                            ),
                          ),
                          SizedBox(width: isTablet ? 16 : 12),
                          Expanded(
                            child: Text(
                              feature,
                              style: TextStyle(
                                fontFamily: 'Poppins',
                                fontSize: isTablet ? 17 : 14,
                                fontWeight: FontWeight.w400,
                                color: featureTextColor,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ))
                  else
                    ..._getDefaultFeatures(package.type).map((feature) => Padding(
                      padding: EdgeInsets.only(bottom: isTablet ? 13 : 10),
                      child: Row(
                        children: [
                          Container(
                            width: isTablet ? 25 : 20,
                            height: isTablet ? 25 : 20,
                            decoration: BoxDecoration(
                              color: gradientColors[0].withValues(alpha: 0.1),
                              shape: BoxShape.circle,
                            ),
                            child: Center(
                              child: Icon(
                                Icons.check,
                                size: isTablet ? 15 : 12,
                                color: isDark ? gradientColors[1] : gradientColors[0],
                              ),
                            ),
                          ),
                          SizedBox(width: isTablet ? 16 : 12),
                          Expanded(
                            child: Text(
                              feature,
                              style: TextStyle(
                                fontFamily: 'Poppins',
                                fontSize: isTablet ? 17 : 14,
                                fontWeight: FontWeight.w400,
                                color: featureTextColor,
                              ),
                            ),
                          ),
                        ],
                      ),
                    )),

                  SizedBox(height: isTablet ? 13 : 10),
                  Divider(color: dividerColor, height: 1),
                  SizedBox(height: isTablet ? 20 : 16),

                  // Price Row
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      if (hasTiers) ...[
                        Text(
                          'From ',
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: isTablet ? 17 : 14,
                            fontWeight: FontWeight.w400,
                            color: textColor.withValues(alpha: 0.5),
                          ),
                        ),
                      ],
                      Text(
                        _formatPrice(displayPrice),
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: isTablet ? 35 : 28,
                          fontWeight: FontWeight.w400,
                          color: isDark ? gradientColors[1] : gradientColors[0],
                        ),
                      ),
                      if (!hasTiers && package.originalPrice != null && package.originalPrice! > displayPrice) ...[
                        SizedBox(width: isTablet ? 10 : 8),
                        Padding(
                          padding: EdgeInsets.only(bottom: isTablet ? 6 : 4),
                          child: Text(
                            _formatPrice(package.originalPrice!),
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
                      if (discount > 0) ...[
                        SizedBox(width: isTablet ? 16 : 12),
                        Container(
                          padding: EdgeInsets.symmetric(horizontal: isTablet ? 13 : 10, vertical: isTablet ? 6 : 4),
                          decoration: BoxDecoration(
                            color: const Color(0xFF4CAF50).withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(isTablet ? 8 : 6),
                          ),
                          child: Text(
                            '$discount% OFF',
                            style: TextStyle(
                              fontFamily: 'Poppins',
                              fontSize: isTablet ? 15 : 12,
                              fontWeight: FontWeight.w600,
                              color: const Color(0xFF4CAF50),
                            ),
                          ),
                        ),
                      ],
                      const Spacer(),
                      if (hasTiers) ...[
                        Text(
                          '${_formatDuration(package.tiers!.first.durationDays)} - ${_formatDuration(package.tiers!.last.durationDays)}',
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: isTablet ? 15 : 12,
                            fontWeight: FontWeight.w400,
                            color: textColor.withValues(alpha: 0.5),
                          ),
                        ),
                      ] else if (package.durationDays != null) ...[
                        Text(
                          '/ ${_formatDuration(package.durationDays)}',
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: isTablet ? 17 : 14,
                            fontWeight: FontWeight.w400,
                            color: textColor.withValues(alpha: 0.5),
                          ),
                        ),
                      ],
                    ],
                  ),

                  // Selection indicator
                  if (isSelected) ...[
                    SizedBox(height: isTablet ? 20 : 16),
                    Container(
                      padding: EdgeInsets.symmetric(vertical: isTablet ? 13 : 10),
                      decoration: BoxDecoration(
                        color: (isDark ? const Color(0xFF00BEFA) : const Color(0xFF1847A2)).withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(isTablet ? 13 : 10),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.check_circle,
                            size: isTablet ? 22 : 18,
                            color: isDark ? const Color(0xFF00BEFA) : const Color(0xFF1847A2),
                          ),
                          SizedBox(width: isTablet ? 10 : 8),
                          Text(
                            'Selected Package',
                            style: TextStyle(
                              fontFamily: 'Poppins',
                              fontSize: isTablet ? 17 : 14,
                              fontWeight: FontWeight.w500,
                              color: isDark ? const Color(0xFF00BEFA) : const Color(0xFF1847A2),
                            ),
                          ),
                        ],
                      ),
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

  List<String> _getDefaultFeatures(String? type) {
    if (type == 'Practical') {
      return [
        'Practical Demonstrations',
        'Live Sessions',
        'Lab Techniques',
        'Expert Support',
      ];
    }
    return [
      'Video Lectures',
      'Comprehensive Notes',
      'Live Doubt Sessions',
      'Practice MCQs',
    ];
  }
}
