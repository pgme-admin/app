import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:pgme/core_android/providers/theme_provider.dart';
import 'package:pgme/core_android/theme/app_theme.dart';
import 'package:pgme/core_android/utils/web_store_launcher.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:pgme/features_android/home/screens/dashboard_screen.dart';
import 'package:pgme/features_android/home/screens/guest_dashboard_screen.dart';
import 'package:pgme/features_android/home/providers/dashboard_provider.dart';
import 'package:pgme/features_android/home/widgets/dashboard_skeleton.dart';
import 'package:pgme/core_android/services/push_notification_service.dart';
import 'package:pgme/features_android/auth/providers/auth_provider.dart';

class MainScreen extends StatefulWidget {
  final bool isSubscribed;

  const MainScreen({
    super.key,
    this.isSubscribed = false,
  });

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Load dashboard data once here
    Future.microtask(() {
      if (mounted) {
        context.read<DashboardProvider>().loadDashboard();
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed) {
      _checkSessionValidity();
      // Retry FCM token registration if it failed at startup (e.g., APNs not ready on TestFlight)
      PushNotificationService().retryTokenRegistrationIfNeeded();
      // Refresh entire dashboard when returning from an external purchase
      if (WebStoreLauncher.awaitingExternalPurchase) {
        WebStoreLauncher.clearAwaitingPurchase();
        if (mounted) {
          context.read<DashboardProvider>().refresh();
        }
      }
      // Consume pending push notification navigation (background → foreground tap)
      final pendingUrl = PushNotificationService().consumePendingNavigation();
      if (pendingUrl != null && pendingUrl.isNotEmpty && mounted) {
        debugPrint('Push resume navigate: $pendingUrl');
        if (pendingUrl.startsWith('http://') || pendingUrl.startsWith('https://')) {
          launchUrl(Uri.parse(pendingUrl), mode: LaunchMode.externalApplication);
        } else {
          context.push(pendingUrl);
        }
      }
    }
  }

  Future<void> _checkSessionValidity() async {
    try {
      final authProvider = context.read<AuthProvider>();
      final isValid = await authProvider.checkSessionValidity();
      if (!isValid && mounted) {
        // Session is invalid, redirect to login
        context.go('/login');
      }
    } catch (e) {
      debugPrint('Session check error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final isDark = themeProvider.isDarkMode;
    final backgroundColor = isDark ? AppColors.darkBackground : Colors.white;

    // Check subscription status from both widget parameter and provider
    final dashboardProvider = Provider.of<DashboardProvider>(context);
    final isSubscribed = widget.isSubscribed || (dashboardProvider.hasActivePurchase ?? false);

    return Scaffold(
      backgroundColor: backgroundColor,
      body: dashboardProvider.isInitialLoading
          ? const DashboardSkeleton()
          : isSubscribed
              ? const DashboardScreen()
              : const GuestDashboardScreen(),
    );
  }
}
