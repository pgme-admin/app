import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:pgme/core/services/push_notification_service.dart';
import 'package:pgme/core/services/version_check_service.dart';
import 'package:pgme/core/widgets/force_update_modal.dart';
import 'package:pgme/features/auth/providers/auth_provider.dart';
import 'package:pgme/core/services/storage_service.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  // Dark blue background color matching the design
  static const Color _darkBlue = Color(0xFF0033CC);

  VersionCheckResult? _forceUpdateResult;

  @override
  void initState() {
    super.initState();
    // Set status bar to light icons for dark background
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
      ),
    );
    _checkAuthAndNavigate();
  }

  Future<void> _checkAuthAndNavigate() async {
    debugPrint('=== Splash Navigation ===');

    try {
      // Initialize core services first
      await dotenv.load(fileName: '.env');

      // Firebase may already be initialized natively in AppDelegate.
      // Catch duplicate-init and continue safely.
      try {
        await Firebase.initializeApp();
      } catch (e) {
        // ignore: avoid_print
        print('Firebase already initialized (native): $e');
      }

      await PushNotificationService().initialize();

      if (!mounted) return;

      // Check app version before proceeding
      final versionResult = await VersionCheckService().checkVersion();
      if (versionResult.updateRequired) {
        debugPrint('Force update required: current=${versionResult.currentVersion}, min=${versionResult.minVersion}');
        if (!mounted) return;
        setState(() {
          _forceUpdateResult = versionResult;
        });
        return; // Stop here — don't navigate, show the modal
      }

      final authProvider = context.read<AuthProvider>();
      final storageService = StorageService();

      // Run minimum splash duration and auth check concurrently
      await Future.wait([
        Future.delayed(const Duration(milliseconds: 1500)), // Minimum splash time
        authProvider.checkAuthStatus(),
      ]);

      if (!mounted) return;

      if (authProvider.isAuthenticated) {
        // User is authenticated
        debugPrint('User is authenticated');

        // Check for multiple sessions
        if (authProvider.hasMultipleSessions) {
          debugPrint('Multiple sessions detected, navigating to multiple-logins');
          context.go('/multiple-logins');
        } else if (authProvider.onboardingCompleted) {
          // Onboarding completed - go to home
          debugPrint('Onboarding completed, navigating to home');
          context.go('/home');
        } else {
          // Onboarding not completed - go to subject selection
          debugPrint('Onboarding not completed, navigating to subject-selection');
          context.go('/subject-selection');
        }
      } else {
        // User is not authenticated - check if intro was seen
        final introSeen = await storageService.getIntroSeen();
        if (introSeen) {
          // Intro already seen - go directly to login
          debugPrint('Intro seen, navigating to login');
          context.go('/login');
        } else {
          // First time user - show onboarding
          debugPrint('First time user, navigating to onboarding');
          context.go('/onboarding');
        }
      }
    } catch (e) {
      debugPrint('Error checking auth status: $e');
      if (!mounted) return;
      // On error, go to login
      context.go('/login');
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final shortestSide = screenSize.shortestSide;
    final isTablet = shortestSide >= 600;
    final isLandscape = screenSize.width > screenSize.height;

    // Tablet: significantly bigger logo & text for the larger screen
    final logoWidth = isTablet
        ? (isLandscape ? shortestSide * 0.38 : shortestSide * 0.42)
        : screenSize.width * 0.35;
    final textWidth = isTablet
        ? (isLandscape ? shortestSide * 0.48 : shortestSide * 0.55)
        : screenSize.width * 0.45;
    final versionFontSize = isTablet ? 18.0 : 14.0;
    final logoTextGap = isTablet ? 36.0 : 20.0;
    final logoLeftPadding = isTablet ? 16.0 : 12.0;
    final versionBottom = isTablet
        ? (isLandscape ? 32.0 : 48.0)
        : (isLandscape ? 24.0 : 40.0);

    return Scaffold(
      backgroundColor: _darkBlue,
      body: Stack(
        children: [
          // Main content centered
          Container(
            width: double.infinity,
            height: double.infinity,
            color: _darkBlue,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // PGME logo in the center (slightly offset to the right)
                Padding(
                  padding: EdgeInsets.only(left: logoLeftPadding),
                  child: Image.asset(
                    'assets/illustrations/pgme.png',
                    width: logoWidth,
                    fit: BoxFit.contain,
                    errorBuilder: (context, error, stackTrace) {
                      return Icon(
                        Icons.medical_services,
                        size: isTablet ? 160 : 100,
                        color: Colors.white,
                      );
                    },
                  ),
                ),
                SizedBox(height: logoTextGap),
                // PGME text below the logo
                Image.asset(
                  'assets/illustrations/pgmetext.png',
                  width: textWidth,
                  fit: BoxFit.contain,
                  errorBuilder: (context, error, stackTrace) {
                    return Text(
                      'PGME',
                      style: TextStyle(
                        fontSize: isTablet ? 64 : 48,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
          // Version number at the bottom
          Positioned(
            left: 0,
            right: 0,
            bottom: versionBottom,
            child: Center(
              child: Text(
                'Ver 1.6.5',
                style: TextStyle(
                  fontSize: versionFontSize,
                  color: Colors.white.withValues(alpha: 0.7),
                  fontWeight: FontWeight.w400,
                ),
              ),
            ),
          ),

          // Force Update Modal (blocks entire screen)
          if (_forceUpdateResult != null)
            Positioned.fill(
              child: ForceUpdateModal(
                storeUrl: _forceUpdateResult!.storeUrl,
                currentVersion: _forceUpdateResult!.currentVersion,
                minVersion: _forceUpdateResult!.minVersion,
              ),
            ),
        ],
      ),
    );
  }
}
