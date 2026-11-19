import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:pgme/core_ios/models/banner_model.dart';
import 'package:pgme/core_ios/utils/responsive_helper.dart';

class PromotionalBanner extends StatelessWidget {
  final BannerModel banner;

  const PromotionalBanner({
    super.key,
    required this.banner,
  });

  Future<void> _handleBannerTap(BuildContext context) async {
    if (banner.linkUrl == null || banner.linkUrl!.isEmpty) return;

    switch (banner.linkType) {
      case 'internal':
        // Navigate to internal route
        context.push(banner.linkUrl!);
        break;
      case 'external':
        // Open external URL
        final url = Uri.parse(banner.linkUrl!);
        if (await canLaunchUrl(url)) {
          await launchUrl(url, mode: LaunchMode.externalApplication);
        }
        break;
      case 'none':
      default:
        // Do nothing
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isTablet = ResponsiveHelper.isTablet(context);
    return GestureDetector(
      onTap: () => _handleBannerTap(context),
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: isTablet ? 24 : 16),
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: ResponsiveHelper.getMaxContentWidth(context),
            ),
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(isTablet ? 28 : 16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.1),
                    blurRadius: isTablet ? 12 : 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(isTablet ? 28 : 16),
                child: CachedNetworkImage(
                  imageUrl: banner.imageUrl,
                  width: double.infinity,
                  height: double.infinity,
                  fit: BoxFit.cover,
                  placeholder: (context, url) => Container(
                    color: Colors.grey[200],
                  ),
                  errorWidget: (context, url, error) => Container(
                    color: Colors.grey[200],
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.image_not_supported,
                          size: isTablet ? 56 : 48,
                          color: Colors.grey[400],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          banner.title,
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: isTablet ? 16 : 14,
                            fontWeight: FontWeight.w500,
                            color: Colors.grey[600],
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
