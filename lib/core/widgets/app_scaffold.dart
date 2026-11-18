import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:pgme/core/providers/theme_provider.dart';
import 'package:pgme/core/providers/mini_player_provider.dart';
import 'package:pgme/core/theme/app_theme.dart';
import 'package:pgme/core/utils/responsive_helper.dart';
import 'package:pgme/core/widgets/mini_player_widget.dart';
import 'package:pgme/features/auth/providers/auth_provider.dart';
import 'package:pgme/features/auth/widgets/session_invalidated_modal.dart';

class AppScaffold extends StatelessWidget {
  final Widget child;
  final int currentIndex;
  final bool isSubscribed;

  const AppScaffold({
    super.key,
    required this.child,
    required this.currentIndex,
    this.isSubscribed = false,
  });

  /// Space a scrolling page inside this scaffold must leave after its last
  /// item so that item clears the floating bottom navigation bar, and the
  /// mini player when it is showing. Mirrors the geometry in [build].
  /// Pass [listen] true from build() so the inset updates when the mini
  /// player appears or goes away.
  static double bottomContentInset(BuildContext context, {bool listen = true}) {
    final isTablet = ResponsiveHelper.isTablet(context);
    final navBarHeight = isTablet ? 88.0 : 70.0;
    const navBottomMargin = 12.0;
    const gapAboveNav = 16.0;
    var inset = MediaQuery.of(context).padding.bottom +
        navBottomMargin +
        navBarHeight +
        gapAboveNav;
    try {
      final mini = Provider.of<MiniPlayerProvider>(context, listen: listen);
      if (mini.isMinimized && mini.controller != null) {
        inset += 60.0 + 8.0; // MiniPlayerWidget height + its gap above the nav
      }
    } catch (_) {
      // No provider above this context: nothing extra to clear.
    }
    return inset;
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final authProvider = Provider.of<AuthProvider>(context);
    final isDark = themeProvider.isDarkMode;
    final isTablet = ResponsiveHelper.isTablet(context);

    // Get screen dimensions and safe area insets
    final screenWidth = MediaQuery.of(context).size.width;
    final bottomPadding = MediaQuery.of(context).padding.bottom;

    // Calculate responsive navbar width
    final navBarWidth = ResponsiveHelper.navBarWidth(context);
    final horizontalPadding = (screenWidth - navBarWidth) / 2;

    // Tablet-responsive sizes
    final navBarHeight = isTablet ? 88.0 : 70.0;
    final navItemWidth = isTablet ? 100.0 : 68.0;
    final navItemHeight = isTablet ? 78.0 : 60.0;
    final navIconSize = isTablet ? 40.0 : 30.0;
    final navLabelSize = isTablet ? 15.0 : 11.0;

    // Theme-aware colors
    final backgroundColor = isDark ? AppColors.darkBackground : Colors.white;
    final navBarColor = isDark ? AppColors.darkSurface : const Color(0xFFF6F6F6);
    final inactiveIconColor = isDark ? AppColors.darkTextTertiary : const Color(0xFF666666);
    final activeIconColor = isDark ? const Color(0xFF00BEFA) : const Color(0xFF00C2FF);

    // Android Back is handled for the whole shell by ShellBackHandler
    // (see app_router.dart).
    return Scaffold(
      backgroundColor: backgroundColor,
      extendBody: true,
      body: Stack(
        clipBehavior: Clip.none,
        children: [
          child,
          // Persistent Bottom Navigation Bar
          Positioned(
            bottom: bottomPadding + 12,
            left: horizontalPadding,
            right: horizontalPadding,
            child: Container(
              height: navBarHeight,
              decoration: BoxDecoration(
                color: navBarColor,
                borderRadius: BorderRadius.circular(isTablet ? 28 : 16),
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
                          blurRadius: 4,
                          offset: Offset(0, 4),
                        ),
                        BoxShadow(
                          color: Color(0x26000000),
                          blurRadius: 12,
                          spreadRadius: 6,
                          offset: Offset(0, 8),
                        ),
                      ],
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _buildNavItem(
                    context: context,
                    index: 0,
                    label: 'Home',
                    icon: Icons.home_outlined,
                    activeIcon: Icons.home,
                    route: '/home',
                    activeColor: activeIconColor,
                    inactiveColor: inactiveIconColor,
                    itemWidth: navItemWidth,
                    itemHeight: navItemHeight,
                    iconSize: navIconSize,
                    labelSize: navLabelSize,
                  ),
                  _buildNavItem(
                    context: context,
                    index: 1,
                    label: 'Theory',
                    icon: Icons.menu_book_outlined,
                    activeIcon: Icons.menu_book,
                    route: '/revision-series',
                    activeColor: activeIconColor,
                    inactiveColor: inactiveIconColor,
                    itemWidth: navItemWidth,
                    itemHeight: navItemHeight,
                    iconSize: navIconSize,
                    labelSize: navLabelSize,
                  ),
                  _buildNavItem(
                    context: context,
                    index: 2,
                    label: 'Practical',
                    icon: Icons.science_outlined,
                    activeIcon: Icons.science,
                    route: '/practical-series',
                    activeColor: activeIconColor,
                    inactiveColor: inactiveIconColor,
                    itemWidth: navItemWidth,
                    itemHeight: navItemHeight,
                    iconSize: navIconSize,
                    labelSize: navLabelSize,
                  ),
                  _buildNavItem(
                    context: context,
                    index: 3,
                    label: 'Notes',
                    icon: Icons.description_outlined,
                    activeIcon: Icons.description,
                    route: '/your-notes',
                    activeColor: activeIconColor,
                    inactiveColor: inactiveIconColor,
                    itemWidth: navItemWidth,
                    itemHeight: navItemHeight,
                    iconSize: navIconSize,
                    labelSize: navLabelSize,
                  ),
                ],
              ),
            ),
          ),

          // Mini Player (above nav bar)
          // Positioned MUST be the direct Stack child — Consumer goes inside
          Positioned(
            left: 0,
            right: 0,
            bottom: bottomPadding + 12 + navBarHeight + 8,
            child: const MiniPlayerWidget(),
          ),

          // Session Invalidated Modal (blocks entire screen)
          if (authProvider.isSessionInvalidated)
            const Positioned.fill(
              child: SessionInvalidatedModal(),
            ),
        ],
      ),
    );
  }

  Widget _buildNavItem({
    required BuildContext context,
    required int index,
    required String label,
    required IconData icon,
    required IconData activeIcon,
    required String route,
    required Color activeColor,
    required Color inactiveColor,
    required double itemWidth,
    required double itemHeight,
    required double iconSize,
    required double labelSize,
  }) {
    final isActive = currentIndex == index;
    final currentLocation = GoRouterState.of(context).uri.toString();
    final isOnCurrentRoute = currentLocation.startsWith(route.split('?').first);

    return GestureDetector(
      onTap: () {
        if (!isOnCurrentRoute) {
          context.go(route);
        }
      },
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: itemWidth,
        height: itemHeight,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              isActive ? activeIcon : icon,
              color: isActive ? activeColor : inactiveColor,
              size: iconSize,
            ),
            if (isActive) ...[
              const SizedBox(height: 2),
              Text(
                label,
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: labelSize,
                  fontWeight: FontWeight.w600,
                  color: activeColor,
                  height: 1.2,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
