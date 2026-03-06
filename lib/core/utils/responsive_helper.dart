import 'package:flutter/material.dart';

/// Responsive helper for tablet optimization.
/// Provides device type detection and responsive scaling utilities.
class ResponsiveHelper {
  /// Tablet breakpoint: devices with shortest side >= 600dp
  static const double tabletBreakpoint = 600.0;

  /// Large tablet breakpoint: width >= 900dp (e.g. iPad Pro 13-inch)
  static const double largeTabletBreakpoint = 900.0;

  /// Base tablet width used for scaling (iPad Pro 11-inch portrait)
  static const double _baseTabletWidth = 834.0;

  /// Max content width on tablets to prevent overly wide layouts
  static const double maxContentWidth = 780.0;

  /// Max content width on tablets in landscape mode
  static const double maxContentWidthLandscape = 1100.0;

  /// Check if the device is a tablet based on shortest side
  static bool isTablet(BuildContext context) {
    final shortestSide = MediaQuery.of(context).size.shortestSide;
    return shortestSide >= tabletBreakpoint;
  }

  /// Check if the device is a large tablet (iPad Pro 13-inch, etc.)
  static bool isLargeTablet(BuildContext context) {
    if (!isTablet(context)) return false;
    return screenWidth(context) >= largeTabletBreakpoint;
  }

  /// Scale factor for large tablets relative to base iPad 11-inch (834dp).
  /// Returns 1.0 for phones and standard iPads, >1.0 for larger iPads.
  static double tabletScale(BuildContext context) {
    if (!isLargeTablet(context)) return 1.0;
    return (screenWidth(context) / _baseTabletWidth).clamp(1.0, 1.35);
  }

  /// Get screen width
  static double screenWidth(BuildContext context) {
    return MediaQuery.of(context).size.width;
  }

  /// Get screen height
  static double screenHeight(BuildContext context) {
    return MediaQuery.of(context).size.height;
  }

  /// Check if device is in landscape orientation
  static bool isLandscape(BuildContext context) {
    return MediaQuery.of(context).orientation == Orientation.landscape;
  }

  /// Returns a value based on device type: phone value or tablet value
  static T value<T>(BuildContext context, {required T phone, required T tablet}) {
    return isTablet(context) ? tablet : phone;
  }

  /// Responsive horizontal padding
  static double horizontalPadding(BuildContext context) {
    if (!isTablet(context)) return 16.0;
    if (isLandscape(context)) return 24.0;
    // Large tablets: small fixed padding, centering handled by ConstrainedBox
    if (isLargeTablet(context)) return 24.0;
    final width = screenWidth(context);
    // Standard tablets: center content with side margins
    return ((width - maxContentWidth) / 2).clamp(24.0, double.infinity);
  }

  /// Responsive font scale factor for tablets (slightly larger text)
  static double fontScale(BuildContext context) {
    return isTablet(context) ? 1.15 : 1.0;
  }

  /// Responsive icon size
  static double iconSize(BuildContext context, double baseSize) {
    return isTablet(context) ? baseSize * 1.35 : baseSize;
  }

  /// Responsive spacing
  static double spacing(BuildContext context, double baseSpacing) {
    return isTablet(context) ? baseSpacing * 1.25 : baseSpacing;
  }

  /// Dynamic max content width that scales for larger iPads.
  /// Standard iPad (11-inch): 780dp, Large iPad (13-inch): screen width minus small margins.
  static double _dynamicMaxContentWidth(BuildContext context) {
    if (isLargeTablet(context)) {
      // Use nearly full width, just 24dp margin on each side
      return screenWidth(context) - 48;
    }
    return maxContentWidth;
  }

  /// Get the appropriate max content width based on orientation
  static double getMaxContentWidth(BuildContext context) {
    if (!isTablet(context)) return double.infinity;
    // Landscape: no constraint, let content take full width
    if (isLandscape(context)) return double.infinity;
    return _dynamicMaxContentWidth(context);
  }

  /// Get constrained content width (prevents content from being too wide on tablets)
  static double contentWidth(BuildContext context) {
    final width = screenWidth(context);
    if (!isTablet(context)) return width;
    final maxWidth = isLandscape(context) ? maxContentWidthLandscape : _dynamicMaxContentWidth(context);
    return width.clamp(0, maxWidth);
  }

  /// Wraps a child widget with centered max-width constraint for tablets
  static Widget constrainedContent({
    required BuildContext context,
    required Widget child,
    double? maxWidth,
  }) {
    if (!isTablet(context)) return child;
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: maxWidth ?? _dynamicMaxContentWidth(context),
        ),
        child: child,
      ),
    );
  }

  /// Get responsive grid cross-axis count based on screen width
  static int gridColumns(BuildContext context, {int phoneColumns = 1, int tabletColumns = 2}) {
    return isTablet(context) ? tabletColumns : phoneColumns;
  }

  /// Get navbar width responsive to device
  static double navBarWidth(BuildContext context) {
    final width = screenWidth(context);
    if (!isTablet(context)) {
      return width > 380 ? 361.0 : width * 0.95;
    }
    // Tablet: constrain nav bar width in landscape
    if (isLandscape(context)) {
      return (maxContentWidthLandscape - 48).clamp(0, width - 48);
    }
    final effectiveMaxWidth = _dynamicMaxContentWidth(context);
    return (effectiveMaxWidth).clamp(0, width - 48);
  }

  /// Get carousel height responsive to device
  static double carouselHeight(BuildContext context) {
    if (!isTablet(context)) return 140.0;
    return (260.0 * tabletScale(context)).roundToDouble();
  }

  /// Get responsive card height for ForYou section
  static double forYouCardHeight(BuildContext context) {
    if (!isTablet(context)) return 281.0;
    return (420.0 * tabletScale(context)).roundToDouble();
  }

  /// Get responsive small card height for ForYou section (theory/practical)
  static double forYouSmallCardHeight(BuildContext context) {
    if (!isTablet(context)) return 137.0;
    return (200.0 * tabletScale(context)).roundToDouble();
  }

  /// Faculty card dimensions
  static double facultyCardWidth(BuildContext context) {
    if (!isTablet(context)) return 140.0;
    return (210.0 * tabletScale(context)).roundToDouble();
  }

  static double facultyCardHeight(BuildContext context) {
    if (!isTablet(context)) return 148.0;
    return (240.0 * tabletScale(context)).roundToDouble();
  }

  /// Faculty photo size
  static double facultyPhotoSize(BuildContext context) {
    if (!isTablet(context)) return 88.0;
    return (130.0 * tabletScale(context)).roundToDouble();
  }

  /// Profile avatar size on dashboard header
  static double profileAvatarSize(BuildContext context) {
    if (!isTablet(context)) return 44.0;
    return (68.0 * tabletScale(context)).roundToDouble();
  }

  /// Action button size on dashboard header
  static double actionButtonSize(BuildContext context) {
    if (!isTablet(context)) return 38.0;
    return (56.0 * tabletScale(context)).roundToDouble();
  }

  /// Order book card height
  static double orderBookCardHeight(BuildContext context) {
    if (!isTablet(context)) return 100.0;
    return (160.0 * tabletScale(context)).roundToDouble();
  }
}
