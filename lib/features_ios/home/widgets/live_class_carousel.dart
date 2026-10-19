import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:pgme/core_ios/models/live_session_model.dart';
import 'package:pgme/core_ios/models/banner_model.dart';
import 'package:pgme/core_ios/utils/responsive_helper.dart';
import 'package:pgme/features_ios/home/widgets/live_class_banner.dart';

class LiveClassCarousel extends StatefulWidget {
  final List<LiveSessionModel> sessions;
  final List<BannerModel> banners;

  const LiveClassCarousel({
    super.key,
    required this.sessions,
    this.banners = const [],
  });

  @override
  State<LiveClassCarousel> createState() => _LiveClassCarouselState();
}

class _LiveClassCarouselState extends State<LiveClassCarousel> {
  late PageController _pageController;
  int _currentPage = 0;
  Timer? _autoSlideTimer;

  int get _totalItems => widget.sessions.length + widget.banners.length;

  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: 0);
    if (_totalItems > 1) {
      _startAutoSlide();
    }
  }

  @override
  void dispose() {
    _autoSlideTimer?.cancel();
    _pageController.dispose();
    super.dispose();
  }

  void _startAutoSlide() {
    _autoSlideTimer = Timer.periodic(const Duration(seconds: 3), (timer) {
      if (mounted && _pageController.hasClients) {
        final nextPage = (_currentPage + 1) % _totalItems;
        _pageController.animateToPage(
          nextPage,
          duration: const Duration(milliseconds: 400),
          curve: Curves.easeInOut,
        );
      }
    });
  }

  void _onPageChanged(int page) {
    setState(() {
      _currentPage = page;
    });
  }

  /// Fixed carousel height: 16:9 image + text/buttons area below.
  /// Image width is capped by ResponsiveHelper.getBannerMaxWidth so landscape
  /// on tablets doesn't produce a banner that consumes the entire viewport.
  double _getCarouselHeight(BuildContext context) {
    final isTablet = ResponsiveHelper.isTablet(context);
    final horizontalPadding = isTablet ? 24.0 * 2 : 16.0 * 2;
    final screenWidth = MediaQuery.of(context).size.width;
    final bannerMaxWidth = ResponsiveHelper.getBannerMaxWidth(context);
    final availableWidth =
        (screenWidth - horizontalPadding).clamp(0.0, bannerMaxWidth);

    final imageHeight = availableWidth * (9 / 16);

    // Below-image area for title + time + buttons (bumped to fix 8px overflow
    // at larger text scales).
    final belowImageHeight = isTablet ? 100.0 : 80.0;

    return imageHeight + belowImageHeight;
  }

  Widget _buildCarouselItem(int index) {
    if (index < widget.sessions.length) {
      return LiveClassBanner(session: widget.sessions[index]);
    } else {
      final bannerIndex = index - widget.sessions.length;
      return _PromotionalBannerWrapper(banner: widget.banners[bannerIndex]);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_totalItems == 0) {
      return const SizedBox.shrink();
    }

    final isTablet = ResponsiveHelper.isTablet(context);
    final dotSize = isTablet ? 12.0 : 8.0;
    final activeDotWidth = isTablet ? 36.0 : 24.0;
    final carouselHeight = _getCarouselHeight(context);

    if (_totalItems == 1) {
      return SizedBox(
        height: carouselHeight,
        child: widget.sessions.isNotEmpty
            ? LiveClassBanner(session: widget.sessions.first)
            : _PromotionalBannerWrapper(banner: widget.banners.first),
      );
    }

    return Column(
      children: [
        SizedBox(
          height: carouselHeight,
          child: PageView.builder(
            controller: _pageController,
            onPageChanged: _onPageChanged,
            itemCount: _totalItems,
            itemBuilder: (context, index) => _buildCarouselItem(index),
          ),
        ),
        SizedBox(height: isTablet ? 18 : 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(
            _totalItems,
            (index) => Container(
              margin: EdgeInsets.symmetric(horizontal: isTablet ? 6 : 4),
              width: _currentPage == index ? activeDotWidth : dotSize,
              height: dotSize,
              decoration: BoxDecoration(
                color: _currentPage == index
                    ? const Color(0xFF2470E4)
                    : const Color(0xFFD9D9D9),
                borderRadius: BorderRadius.circular(dotSize / 2),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _PromotionalBannerWrapper extends StatelessWidget {
  final BannerModel banner;
  const _PromotionalBannerWrapper({required this.banner});

  bool get _hasLink =>
      banner.linkType != null &&
      banner.linkType != 'none' &&
      banner.linkUrl != null &&
      banner.linkUrl!.isNotEmpty;

  Future<void> _handleTap(BuildContext context) async {
    if (!_hasLink) return;
    switch (banner.linkType) {
      case 'internal':
        context.push(banner.linkUrl!);
        break;
      case 'external':
        final url = Uri.parse(banner.linkUrl!);
        if (await canLaunchUrl(url)) {
          await launchUrl(url, mode: LaunchMode.externalApplication);
        }
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isTablet = ResponsiveHelper.isTablet(context);
    final belowImageHeight = isTablet ? 100.0 : 80.0;
    final titleSize = isTablet ? 20.0 : 14.0;
    final buttonFontSize = isTablet ? 15.0 : 11.0;
    final buttonPaddingH = isTablet ? 24.0 : 14.0;
    final buttonPaddingV = isTablet ? 10.0 : 6.0;
    final isDark = Theme.of(context).brightness == Brightness.dark;

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
              // Banner image — strict 16:9, never crops regardless of parent size
              GestureDetector(
                onTap: () => _handleTap(context),
                child: AspectRatio(
                  aspectRatio: 16 / 9,
                  child: Container(
                    width: double.infinity,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(isTablet ? 20 : 14),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.1),
                          blurRadius: isTablet ? 12 : 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(isTablet ? 20 : 14),
                      child: CachedNetworkImage(
                        imageUrl: banner.imageUrl,
                        width: double.infinity,
                        fit: BoxFit.cover,
                        placeholder: (context, url) => Container(color: Colors.grey[200]),
                        errorWidget: (context, url, error) => Container(
                          color: Colors.grey[200],
                          child: Icon(Icons.image_not_supported, size: 48, color: Colors.grey[400]),
                        ),
                      ),
                    ),
                  ),
                ),
              ),

              // Title + optional button below image
              SizedBox(
                height: belowImageHeight,
                child: Padding(
                  padding: EdgeInsets.only(top: isTablet ? 10 : 7, left: 2, right: 2),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (banner.title.isNotEmpty) ...[
                        Text(
                          banner.title,
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            fontWeight: FontWeight.w600,
                            fontSize: titleSize,
                            color: isDark ? Colors.white : const Color(0xFF1A1A1A),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        SizedBox(height: isTablet ? 8 : 5),
                      ],
                      if (_hasLink) ...[
                        GestureDetector(
                          onTap: () => _handleTap(context),
                          child: Container(
                            padding: EdgeInsets.symmetric(
                              horizontal: buttonPaddingH,
                              vertical: buttonPaddingV,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFF2470E4),
                              borderRadius: BorderRadius.circular(isTablet ? 10 : 7),
                            ),
                            child: Text(
                              'View Details',
                              style: TextStyle(
                                fontFamily: 'Poppins',
                                fontWeight: FontWeight.w500,
                                fontSize: buttonFontSize,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                      ],
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
}
