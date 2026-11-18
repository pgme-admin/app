import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Android Back for every screen inside the app's ShellRoute (the tabs and
/// the screens that hide the bottom nav: PDF/EPUB reader, profile,
/// downloads...).
///
///  * A page pushed on top can be popped: go_router pops it (and that page's
///    own PopScope, e.g. the PDF reader closing its search bar, still runs).
///  * Nothing to pop on a screen other than Home: go to Home.
///  * Home with nothing to pop: leave the app.
///
/// Two separate problems made this necessary:
///  * go_router 13's popRoute returns false when nothing can pop without
///    asking any PopScope, so the old handler inside AppScaffold never ran and
///    Back on a non-Home tab closed the app.
///  * With predictive back (`enableOnBackInvokedCallback="true"`), Android
///    only sends Back to Flutter while some route says it handles it. The
///    hidden-nav screens had no PopScope at shell level, so on Android 13+
///    Back there sent the app to the background instead of going back.
///    The `PopScope(canPop: false)` here keeps Back in Flutter on every screen.
class ShellBackHandler extends StatelessWidget {
  final bool isHome;
  final Widget child;

  const ShellBackHandler({super.key, required this.isHome, required this.child});

  /// Returns true when Back was handled here.
  bool _handleBack(BuildContext context) {
    final router = GoRouter.of(context);
    if (router.canPop()) return false; // go_router pops the top page
    if (!isHome) {
      context.go('/home');
      return true;
    }
    return false; // Home: let the app close
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (!_handleBack(context)) {
          // Only reached when the root navigator itself is asked to pop.
          final router = GoRouter.of(context);
          if (router.canPop()) router.pop();
        }
      },
      child: BackButtonListener(
        onBackButtonPressed: () async => _handleBack(context),
        child: child,
      ),
    );
  }
}
