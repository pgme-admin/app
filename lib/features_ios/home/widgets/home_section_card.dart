import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:pgme/core_ios/models/home_section_item_model.dart';
import 'package:pgme/core_ios/providers/theme_provider.dart';
import 'package:pgme/core_ios/theme/app_theme.dart';
import 'package:pgme/core_ios/utils/color_utils.dart';
import 'package:pgme/core_ios/utils/responsive_helper.dart';
import 'package:pgme/features_ios/home/providers/dashboard_provider.dart';

class HomeSectionCard extends StatelessWidget {
  final HomeSectionItemModel item;

  const HomeSectionCard({super.key, required this.item});

  @override
  Widget build(BuildContext context) {
    switch (item.cardType) {
      case 'info_card':
        return _buildInfoCard(context);
      case 'featured_card':
        return _buildFeaturedCard(context);
      case 'horizontal_card':
        return _buildHorizontalCard(context);
      case 'overlay_card':
        return _buildOverlayCard(context);
      case 'promo_banner':
        return _buildPromoBanner(context);
      case 'compact_card':
        return _buildCompactCard(context);
      case 'list_item':
        return _buildListItem(context);
      case 'banner':
        return _buildBanner(context);
      default:
        return _buildInfoCard(context);
    }
  }

  // =====================
  // Navigation Helpers
  // =====================

  /// Inject 'subscribed' query param for routes that need it.
  String _injectSubscribed(BuildContext context, String url) {
    const routesNeedingSubscribed = [
      '/revision-series',
      '/practical-series',
      '/series-detail',
      '/lecture',
    ];
    final routePath = url.split('?').first.split('/').take(3).join('/');
    final matches = routesNeedingSubscribed.any((r) => routePath.startsWith(r));
    if (!matches) return url;

    final dashboardProvider = Provider.of<DashboardProvider>(context, listen: false);
    final subscribed = dashboardProvider.hasActivePurchase == true ? 'true' : 'false';
    final separator = url.contains('?') ? '&' : '?';
    return '$url${separator}subscribed=$subscribed';
  }

  void _handlePrimaryTap(BuildContext context) {
    _handleNavigation(context, linkType: item.linkType, linkUrl: item.linkUrl);
  }

  void _handleSecondaryTap(BuildContext context) {
    _handleNavigation(context, linkType: item.secondaryLinkType, linkUrl: item.secondaryLinkUrl);
  }

  /// Same pattern as promotional_banner.dart: backend constructs the URL,
  /// Flutter just pushes it for internal or launches it for external.
  Future<void> _handleNavigation(
    BuildContext context, {
    String? linkType,
    String? linkUrl,
  }) async {
    if (linkUrl == null || linkUrl.isEmpty) return;

    switch (linkType) {
      case 'internal':
        try {
          context.push(_injectSubscribed(context, linkUrl));
        } catch (e) {
          debugPrint('Navigation error: $e');
        }
        break;
      case 'external':
        try {
          final url = Uri.tryParse(linkUrl);
          if (url != null && await canLaunchUrl(url)) {
            await launchUrl(url, mode: LaunchMode.externalApplication);
          }
        } catch (e) {
          debugPrint('External URL launch error: $e');
        }
        break;
      case 'none':
      default:
        break;
    }
  }

  bool get _hasPrimaryAction =>
      item.linkType != null && item.linkType != 'none' && item.linkUrl != null;

  // =====================
  // Shared Helpers
  // =====================

  Color _cardBg(bool isDark) => parseHexColor(
        item.backgroundColor,
        fallback: isDark ? AppColors.darkCardBackground : Colors.white,
      );

  Color _cardText(bool isDark) => parseHexColor(
        item.textColor,
        fallback: isDark ? AppColors.darkTextPrimary : const Color(0xFF1A1A1A),
      );

  Color _cardSubtext(bool isDark) =>
      _cardText(isDark).withValues(alpha: 0.7);

  Widget _buildTagChip(bool isTablet) {
    if (item.tagLabel == null || item.tagLabel!.isEmpty) {
      return const SizedBox.shrink();
    }
    final tagBg = parseHexColor(item.tagColor, fallback: const Color(0xFF4CAF50));
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: isTablet ? 12 : 8,
        vertical: isTablet ? 6 : 4,
      ),
      decoration: BoxDecoration(
        color: tagBg,
        borderRadius: BorderRadius.circular(isTablet ? 8 : 6),
      ),
      child: Text(
        item.tagLabel!,
        style: TextStyle(
          fontFamily: 'Poppins',
          fontWeight: FontWeight.w500,
          fontSize: isTablet ? 13 : 11,
          color: Colors.white,
        ),
      ),
    );
  }

  Widget _buildPrimaryButton(BuildContext context, bool isDark, bool isTablet,
      {bool fullWidth = false}) {
    if (item.buttonText == null || item.buttonText!.isEmpty) {
      return const SizedBox.shrink();
    }
    final btnBg = parseHexColor(
      item.buttonColor,
      fallback: isDark ? const Color(0xFF2470E4) : const Color(0xFF0000C8),
    );
    final btnText = parseHexColor(
      item.buttonTextColor,
      fallback: Colors.white,
    );
    return SizedBox(
      width: fullWidth ? double.infinity : null,
      child: ElevatedButton(
        onPressed: () => _handlePrimaryTap(context),
        style: ElevatedButton.styleFrom(
          backgroundColor: btnBg,
          foregroundColor: btnText,
          elevation: 0,
          padding: EdgeInsets.symmetric(
            horizontal: isTablet ? 24 : 16,
            vertical: isTablet ? 14 : 10,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(isTablet ? 12 : 8),
          ),
        ),
        child: Text(
          item.buttonText!,
          style: TextStyle(
            fontFamily: 'Poppins',
            fontWeight: FontWeight.w600,
            fontSize: isTablet ? 15 : 13,
          ),
        ),
      ),
    );
  }

  Widget _buildSecondaryButton(
      BuildContext context, bool isDark, bool isTablet) {
    if (item.secondaryButtonText == null ||
        item.secondaryButtonText!.isEmpty) {
      return const SizedBox.shrink();
    }
    final textColor =
        isDark ? const Color(0xFF00BEFA) : const Color(0xFF0000C8);
    return TextButton(
      onPressed: () => _handleSecondaryTap(context),
      style: TextButton.styleFrom(
        foregroundColor: textColor,
        padding: EdgeInsets.symmetric(
          horizontal: isTablet ? 24 : 16,
          vertical: isTablet ? 12 : 8,
        ),
      ),
      child: Text(
        item.secondaryButtonText!,
        style: TextStyle(
          fontFamily: 'Poppins',
          fontWeight: FontWeight.w600,
          fontSize: isTablet ? 15 : 13,
        ),
      ),
    );
  }

  Widget _buildMetadataRows(bool isDark, bool isTablet) {
    if (item.metadata.isEmpty) return const SizedBox.shrink();
    final textColor = _cardSubtext(isDark);
    return Column(
      children: item.metadata.map((entry) {
        return Padding(
          padding: EdgeInsets.only(bottom: isTablet ? 6 : 4),
          child: Row(
            children: [
              if (entry.iconUrl != null && entry.iconUrl!.isNotEmpty) ...[
                CachedNetworkImage(
                  imageUrl: entry.iconUrl!,
                  width: isTablet ? 18 : 14,
                  height: isTablet ? 18 : 14,
                  errorWidget: (_, __, ___) => const SizedBox.shrink(),
                ),
                SizedBox(width: isTablet ? 8 : 6),
              ],
              Text(
                '${entry.label}: ',
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontWeight: FontWeight.w500,
                  fontSize: isTablet ? 14 : 12,
                  color: textColor,
                ),
              ),
              Flexible(
                child: Text(
                  entry.value,
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontWeight: FontWeight.w400,
                    fontSize: isTablet ? 14 : 12,
                    color: textColor,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _buildImage(
    String url, {
    double? width,
    double? height,
    BoxFit fit = BoxFit.cover,
    BorderRadius? borderRadius,
  }) {
    Widget image = CachedNetworkImage(
      imageUrl: url,
      width: width,
      height: height,
      fit: fit,
      placeholder: (_, __) => Container(
        width: width,
        height: height,
        color: Colors.grey[200],
      ),
      errorWidget: (_, __, ___) => Container(
        width: width,
        height: height,
        color: Colors.grey[200],
        child: Icon(
          Icons.image_not_supported_outlined,
          size: 24,
          color: Colors.grey[400],
        ),
      ),
    );
    if (borderRadius != null) {
      image = ClipRRect(borderRadius: borderRadius, child: image);
    }
    return image;
  }

  // =====================
  // Card Type: info_card
  // =====================

  Widget _buildInfoCard(BuildContext context) {
    final isDark = Provider.of<ThemeProvider>(context).isDarkMode;
    final isTablet = ResponsiveHelper.isTablet(context);
    final cardBg = _cardBg(isDark);
    final textColor = _cardText(isDark);
    final subtextColor = _cardSubtext(isDark);
    final borderColor = parseHexColor(item.borderColor);
    final radius = isTablet ? 20.0 : 14.0;

    return GestureDetector(
      onTap: _hasPrimaryAction ? () => _handlePrimaryTap(context) : null,
      child: Container(
        decoration: BoxDecoration(
          color: cardBg,
          borderRadius: BorderRadius.circular(radius),
          border: borderColor != Colors.transparent
              ? Border.all(color: borderColor, width: 1)
              : Border.all(
                  color: isDark
                      ? AppColors.darkDivider
                      : const Color(0xFFE0E0E0),
                  width: 0.5,
                ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (item.imageUrl != null)
              AspectRatio(
                aspectRatio: 16 / 9,
                child: _buildImage(
                  item.imageUrl!,
                  width: double.infinity,
                  height: double.infinity,
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(radius),
                    topRight: Radius.circular(radius),
                  ),
                ),
              ),
            Padding(
              padding: EdgeInsets.all(isTablet ? 20 : 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (item.tagLabel != null) ...[
                    _buildTagChip(isTablet),
                    SizedBox(height: isTablet ? 12 : 8),
                  ],
                  if (item.title != null)
                    Text(
                      item.title!,
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontWeight: FontWeight.w600,
                        fontSize: isTablet ? 20 : 16,
                        color: textColor,
                      ),
                    ),
                  if (item.subtitle != null) ...[
                    SizedBox(height: isTablet ? 6 : 4),
                    Text(
                      item.subtitle!,
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontWeight: FontWeight.w400,
                        fontSize: isTablet ? 15 : 13,
                        color: subtextColor,
                      ),
                    ),
                  ],
                  if (item.description != null) ...[
                    SizedBox(height: isTablet ? 10 : 8),
                    Text(
                      item.description!,
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontWeight: FontWeight.w400,
                        fontSize: isTablet ? 14 : 12,
                        color: subtextColor,
                        height: 1.5,
                      ),
                      maxLines: 4,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                  if (item.metadata.isNotEmpty) ...[
                    SizedBox(height: isTablet ? 12 : 8),
                    _buildMetadataRows(isDark, isTablet),
                  ],
                  if (item.buttonText != null) ...[
                    SizedBox(height: isTablet ? 14 : 10),
                    _buildPrimaryButton(context, isDark, isTablet),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // =====================
  // Card Type: featured_card
  // =====================

  Widget _buildFeaturedCard(BuildContext context) {
    final isDark = Provider.of<ThemeProvider>(context).isDarkMode;
    final isTablet = ResponsiveHelper.isTablet(context);
    final cardBg = _cardBg(isDark);
    final textColor = _cardText(isDark);
    final subtextColor = _cardSubtext(isDark);
    final borderColor = parseHexColor(item.borderColor);
    final radius = isTablet ? 22.0 : 16.0;

    return Container(
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(radius),
        border: borderColor != Colors.transparent
            ? Border.all(color: borderColor, width: 1)
            : Border.all(
                color:
                    isDark ? AppColors.darkDivider : const Color(0xFFE0E0E0),
                width: 0.5,
              ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (item.imageUrl != null)
            AspectRatio(
              aspectRatio: 16 / 9,
              child: Stack(
                children: [
                  _buildImage(
                    item.imageUrl!,
                    width: double.infinity,
                    height: double.infinity,
                    borderRadius: BorderRadius.only(
                      topLeft: Radius.circular(radius),
                      topRight: Radius.circular(radius),
                    ),
                  ),
                  if (item.tagLabel != null)
                    Positioned(
                      top: isTablet ? 16 : 12,
                      right: isTablet ? 16 : 12,
                      child: _buildTagChip(isTablet),
                    ),
                  if (item.iconUrl != null)
                    Positioned(
                      bottom: isTablet ? 16 : 12,
                      left: isTablet ? 16 : 12,
                      child: Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: _buildImage(
                          item.iconUrl!,
                          width: isTablet ? 36 : 28,
                          height: isTablet ? 36 : 28,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          Padding(
            padding: EdgeInsets.all(isTablet ? 20 : 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (item.title != null)
                  Text(
                    item.title!,
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontWeight: FontWeight.w700,
                      fontSize: isTablet ? 24 : 18,
                      color: textColor,
                    ),
                  ),
                if (item.description != null) ...[
                  SizedBox(height: isTablet ? 10 : 8),
                  Text(
                    item.description!,
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontWeight: FontWeight.w400,
                      fontSize: isTablet ? 15 : 13,
                      color: subtextColor,
                      height: 1.5,
                    ),
                    maxLines: 5,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
                if (item.metadata.isNotEmpty) ...[
                  SizedBox(height: isTablet ? 12 : 8),
                  _buildMetadataRows(isDark, isTablet),
                ],
                if (item.buttonText != null) ...[
                  SizedBox(height: isTablet ? 16 : 12),
                  _buildPrimaryButton(context, isDark, isTablet,
                      fullWidth: true),
                ],
                if (item.secondaryButtonText != null)
                  Center(
                    child: _buildSecondaryButton(context, isDark, isTablet),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // =====================
  // Card Type: horizontal_card
  // =====================

  Widget _buildHorizontalCard(BuildContext context) {
    final isDark = Provider.of<ThemeProvider>(context).isDarkMode;
    final isTablet = ResponsiveHelper.isTablet(context);
    final cardBg = _cardBg(isDark);
    final textColor = _cardText(isDark);
    final subtextColor = _cardSubtext(isDark);
    final borderColor = parseHexColor(item.borderColor);
    final radius = isTablet ? 18.0 : 12.0;
    // Bumped from 180/140 to 190/150. With tag chip + title + subtitle +
    // 2-line description + primary button, the previous height overflowed
    // by ~5px on phone for fully-populated package cards.
    final cardHeight = isTablet ? 190.0 : 150.0;

    return GestureDetector(
      onTap: _hasPrimaryAction ? () => _handlePrimaryTap(context) : null,
      child: Container(
        height: cardHeight,
        decoration: BoxDecoration(
          color: cardBg,
          borderRadius: BorderRadius.circular(radius),
          border: borderColor != Colors.transparent
              ? Border.all(color: borderColor, width: 1)
              : Border.all(
                  color: isDark
                      ? AppColors.darkDivider
                      : const Color(0xFFE0E0E0),
                  width: 0.5,
                ),
        ),
        child: Row(
          children: [
            if (item.imageUrl != null)
              AspectRatio(
                aspectRatio: 16 / 9,
                child: _buildImage(
                  item.imageUrl!,
                  width: double.infinity,
                  height: cardHeight,
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(radius),
                    bottomLeft: Radius.circular(radius),
                  ),
                ),
              ),
            Expanded(
              child: Padding(
                padding: EdgeInsets.all(isTablet ? 16 : 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (item.tagLabel != null) ...[
                      _buildTagChip(isTablet),
                      SizedBox(height: isTablet ? 8 : 6),
                    ],
                    if (item.title != null)
                      Text(
                        item.title!,
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          fontWeight: FontWeight.w600,
                          fontSize: isTablet ? 18 : 15,
                          color: textColor,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    if (item.subtitle != null) ...[
                      SizedBox(height: isTablet ? 4 : 2),
                      Text(
                        item.subtitle!,
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          fontWeight: FontWeight.w400,
                          fontSize: isTablet ? 14 : 12,
                          color: subtextColor,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                    if (item.description != null) ...[
                      SizedBox(height: isTablet ? 6 : 4),
                      Text(
                        item.description!,
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          fontWeight: FontWeight.w400,
                          fontSize: isTablet ? 13 : 11,
                          color: subtextColor,
                          height: 1.4,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                    if (item.buttonText != null) ...[
                      const Spacer(),
                      _buildPrimaryButton(context, isDark, isTablet),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // =====================
  // Card Type: overlay_card
  // =====================

  Widget _buildOverlayCard(BuildContext context) {
    final isDark = Provider.of<ThemeProvider>(context).isDarkMode;
    final isTablet = ResponsiveHelper.isTablet(context);
    final radius = isTablet ? 22.0 : 16.0;
    final overlayTextColor = parseHexColor(
      item.textColor,
      fallback: Colors.white,
    );

    return GestureDetector(
      onTap: _hasPrimaryAction ? () => _handlePrimaryTap(context) : null,
      child: AspectRatio(
        aspectRatio: 16 / 9,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(radius),
            color: isDark ? AppColors.darkCardBackground : Colors.grey[300],
          ),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (item.imageUrl != null)
                _buildImage(
                  item.imageUrl!,
                  width: double.infinity,
                  height: double.infinity,
                ),
            // Gradient overlay
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    Colors.black.withValues(alpha: 0.7),
                  ],
                  stops: const [0.3, 1.0],
                ),
              ),
            ),
            // Tag badge
            if (item.tagLabel != null)
              Positioned(
                top: isTablet ? 16 : 12,
                right: isTablet ? 16 : 12,
                child: _buildTagChip(isTablet),
              ),
            // Content at bottom
            Positioned(
              left: isTablet ? 20 : 16,
              right: isTablet ? 20 : 16,
              bottom: isTablet ? 20 : 16,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (item.title != null)
                    Text(
                      item.title!,
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontWeight: FontWeight.w700,
                        fontSize: isTablet ? 24 : 20,
                        color: overlayTextColor,
                      ),
                    ),
                  if (item.subtitle != null) ...[
                    SizedBox(height: isTablet ? 4 : 2),
                    Text(
                      item.subtitle!,
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontWeight: FontWeight.w400,
                        fontSize: isTablet ? 15 : 13,
                        color: overlayTextColor.withValues(alpha: 0.85),
                      ),
                    ),
                  ],
                  if (item.description != null) ...[
                    SizedBox(height: isTablet ? 8 : 6),
                    Text(
                      item.description!,
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontWeight: FontWeight.w400,
                        fontSize: isTablet ? 14 : 12,
                        color: overlayTextColor.withValues(alpha: 0.8),
                        height: 1.4,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                  if (item.buttonText != null) ...[
                    SizedBox(height: isTablet ? 12 : 10),
                    _buildPrimaryButton(context, isDark, isTablet),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
      ),
    );
  }

  // =====================
  // Card Type: promo_banner
  // =====================

  Widget _buildPromoBanner(BuildContext context) {
    final isDark = Provider.of<ThemeProvider>(context).isDarkMode;
    final isTablet = ResponsiveHelper.isTablet(context);
    final cardBg = parseHexColor(
      item.backgroundColor,
      fallback: isDark ? const Color(0xFF1A2A4A) : const Color(0xFF0000C8),
    );
    final textColor = parseHexColor(
      item.textColor,
      fallback: Colors.white,
    );
    final radius = isTablet ? 20.0 : 14.0;

    return Container(
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(radius),
      ),
      padding: EdgeInsets.all(isTablet ? 24 : 16),
      child: Row(
        children: [
          // Icon/image on left
          if (item.iconUrl != null || item.imageUrl != null) ...[
            SizedBox(
              width: isTablet ? 80 : 60,
              height: isTablet ? 80 : 60,
              child: item.iconUrl != null
                  ? _buildImage(
                      item.iconUrl!,
                      width: isTablet ? 80 : 60,
                      height: isTablet ? 80 : 60,
                      borderRadius: BorderRadius.circular(isTablet ? 14 : 10),
                    )
                  : _buildImage(
                      item.imageUrl!,
                      width: isTablet ? 80 : 60,
                      height: isTablet ? 80 : 60,
                      borderRadius: BorderRadius.circular(isTablet ? 14 : 10),
                    ),
            ),
            SizedBox(width: isTablet ? 20 : 14),
          ],
          // Content on right
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (item.title != null)
                  Text(
                    item.title!,
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontWeight: FontWeight.w700,
                      fontSize: isTablet ? 20 : 16,
                      color: textColor,
                    ),
                  ),
                if (item.subtitle != null) ...[
                  SizedBox(height: isTablet ? 4 : 2),
                  Text(
                    item.subtitle!,
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontWeight: FontWeight.w400,
                      fontSize: isTablet ? 14 : 12,
                      color: textColor.withValues(alpha: 0.8),
                    ),
                  ),
                ],
                if (item.description != null) ...[
                  SizedBox(height: isTablet ? 8 : 6),
                  Text(
                    item.description!,
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontWeight: FontWeight.w400,
                      fontSize: isTablet ? 13 : 11,
                      color: textColor.withValues(alpha: 0.7),
                      height: 1.4,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
                if (item.buttonText != null ||
                    item.secondaryButtonText != null) ...[
                  SizedBox(height: isTablet ? 14 : 10),
                  Row(
                    children: [
                      if (item.buttonText != null)
                        _buildPrimaryButton(context, isDark, isTablet),
                      if (item.buttonText != null &&
                          item.secondaryButtonText != null)
                        SizedBox(width: isTablet ? 12 : 8),
                      if (item.secondaryButtonText != null)
                        _buildSecondaryButton(context, isDark, isTablet),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  // =====================
  // Card Type: compact_card
  // =====================

  Widget _buildCompactCard(BuildContext context) {
    final isDark = Provider.of<ThemeProvider>(context).isDarkMode;
    final isTablet = ResponsiveHelper.isTablet(context);
    final cardBg = _cardBg(isDark);
    final textColor = _cardText(isDark);
    final subtextColor = _cardSubtext(isDark);
    final borderColor = parseHexColor(item.borderColor);
    final radius = isTablet ? 14.0 : 10.0;
    final iconSize = isTablet ? 48.0 : 40.0;

    return GestureDetector(
      onTap: _hasPrimaryAction ? () => _handlePrimaryTap(context) : null,
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: isTablet ? 16 : 12,
          vertical: isTablet ? 14 : 10,
        ),
        decoration: BoxDecoration(
          color: cardBg,
          borderRadius: BorderRadius.circular(radius),
          border: borderColor != Colors.transparent
              ? Border.all(color: borderColor, width: 1)
              : Border.all(
                  color: isDark
                      ? AppColors.darkDivider
                      : const Color(0xFFE0E0E0),
                  width: 0.5,
                ),
        ),
        child: Row(
          children: [
            if (item.iconUrl != null)
              _buildImage(
                item.iconUrl!,
                width: iconSize,
                height: iconSize,
                borderRadius: BorderRadius.circular(isTablet ? 12 : 8),
              )
            else if (item.imageUrl != null)
              _buildImage(
                item.imageUrl!,
                width: iconSize,
                height: iconSize,
                borderRadius: BorderRadius.circular(isTablet ? 12 : 8),
              ),
            if (item.iconUrl != null || item.imageUrl != null)
              SizedBox(width: isTablet ? 14 : 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (item.title != null)
                    Text(
                      item.title!,
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontWeight: FontWeight.w600,
                        fontSize: isTablet ? 16 : 14,
                        color: textColor,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  if (item.subtitle != null) ...[
                    SizedBox(height: isTablet ? 2 : 1),
                    Text(
                      item.subtitle!,
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontWeight: FontWeight.w400,
                        fontSize: isTablet ? 13 : 11,
                        color: subtextColor,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
            if (item.tagLabel != null) ...[
              SizedBox(width: isTablet ? 10 : 8),
              _buildTagChip(isTablet),
            ],
            SizedBox(width: isTablet ? 8 : 4),
            Icon(
              Icons.chevron_right_rounded,
              size: isTablet ? 24 : 20,
              color: subtextColor,
            ),
          ],
        ),
      ),
    );
  }

  // =====================
  // Card Type: list_item
  // =====================

  Widget _buildListItem(BuildContext context) {
    final isDark = Provider.of<ThemeProvider>(context).isDarkMode;
    final isTablet = ResponsiveHelper.isTablet(context);
    final textColor = _cardText(isDark);
    final subtextColor = _cardSubtext(isDark);
    final iconSize = isTablet ? 40.0 : 32.0;

    return GestureDetector(
      onTap: _hasPrimaryAction ? () => _handlePrimaryTap(context) : null,
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: isTablet ? 4 : 2,
          vertical: isTablet ? 12 : 8,
        ),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: isDark ? AppColors.darkDivider : const Color(0xFFEEEEEE),
              width: 0.5,
            ),
          ),
        ),
        child: Row(
          children: [
            if (item.iconUrl != null)
              ClipOval(
                child: _buildImage(
                  item.iconUrl!,
                  width: iconSize,
                  height: iconSize,
                ),
              )
            else if (item.imageUrl != null)
              ClipOval(
                child: _buildImage(
                  item.imageUrl!,
                  width: iconSize,
                  height: iconSize,
                ),
              ),
            if (item.iconUrl != null || item.imageUrl != null)
              SizedBox(width: isTablet ? 14 : 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (item.title != null)
                    Text(
                      item.title!,
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontWeight: FontWeight.w500,
                        fontSize: isTablet ? 16 : 14,
                        color: textColor,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  if (item.subtitle != null) ...[
                    SizedBox(height: isTablet ? 2 : 1),
                    Text(
                      item.subtitle!,
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontWeight: FontWeight.w400,
                        fontSize: isTablet ? 13 : 11,
                        color: subtextColor,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
            if (item.tagLabel != null) ...[
              SizedBox(width: isTablet ? 10 : 8),
              _buildTagChip(isTablet),
            ],
            SizedBox(width: isTablet ? 8 : 4),
            Icon(
              Icons.arrow_forward_ios_rounded,
              size: isTablet ? 18 : 14,
              color: subtextColor,
            ),
          ],
        ),
      ),
    );
  }

  // =====================
  // Card Type: banner
  // =====================

  Widget _buildBanner(BuildContext context) {
    final isDark = Provider.of<ThemeProvider>(context).isDarkMode;
    final isTablet = ResponsiveHelper.isTablet(context);
    final radius = isTablet ? 22.0 : 14.0;

    if (item.imageUrl != null) {
      return GestureDetector(
        onTap: _hasPrimaryAction ? () => _handlePrimaryTap(context) : null,
        child: AspectRatio(
          aspectRatio: 16 / 9,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(radius),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.08),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: _buildImage(
              item.imageUrl!,
              width: double.infinity,
              height: double.infinity,
              borderRadius: BorderRadius.circular(radius),
            ),
          ),
        ),
      );
    }

    // Fallback: colored container with text
    final cardBg = parseHexColor(
      item.backgroundColor,
      fallback: isDark ? AppColors.darkCardBackground : const Color(0xFFF5F5F5),
    );
    final textColor = _cardText(isDark);

    return GestureDetector(
      onTap: _hasPrimaryAction ? () => _handlePrimaryTap(context) : null,
      child: AspectRatio(
        aspectRatio: 16 / 9,
        child: Container(
          decoration: BoxDecoration(
            color: cardBg,
            borderRadius: BorderRadius.circular(radius),
          ),
          alignment: Alignment.center,
          child: item.title != null
              ? Text(
                  item.title!,
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontWeight: FontWeight.w600,
                    fontSize: isTablet ? 20 : 16,
                    color: textColor,
                  ),
                  textAlign: TextAlign.center,
                )
              : null,
        ),
      ),
    );
  }
}
