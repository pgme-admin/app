import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:no_screenshot/no_screenshot.dart';
import 'package:pgme/core_ios/theme/app_theme.dart';
import 'package:pgme/core_ios/routes/app_router.dart';
import 'package:pgme/core_ios/providers/theme_provider.dart';
import 'package:pgme/core/services/pdf_cache_service.dart';
import 'package:pgme/core_ios/utils/responsive_helper.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:pgme/features_ios/auth/providers/auth_provider.dart';
import 'package:pgme/features_ios/onboarding/providers/onboarding_provider.dart';
import 'package:pgme/features_ios/home/providers/dashboard_provider.dart';
import 'package:pgme/features_ios/books/providers/book_provider.dart';
import 'package:pgme/features_ios/settings/providers/access_record_provider.dart';
import 'package:pgme/features_ios/notifications/providers/notification_provider.dart';
import 'package:pgme/features_ios/courses/providers/enrolled_courses_provider.dart';
import 'package:pgme/features_ios/courses/providers/download_provider.dart';
import 'package:pgme/core/providers/mini_player_provider.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Block screenshots and screen recording app-wide.
  try {
    await NoScreenshot.instance.screenshotOff().timeout(
      const Duration(seconds: 5),
      onTimeout: () {
        debugPrint('NoScreenshot.screenshotOff() timed out — continuing');
        return false;
      },
    );
  } catch (e) {
    debugPrint('NoScreenshot init failed: $e');
  }

  // Set system UI overlay style immediately
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
      statusBarBrightness: Brightness.light,
    ),
  );

  // Allow all orientations initially, then lock based on device type after first frame
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);

  // Run the app immediately — heavy initialization (Firebase, dotenv, etc.)
  // happens inside the splash screen so it shows right away
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Keep the screen awake while the app is in use. Per-screen consumers
    // (BetterPlayer fullscreen) may briefly toggle this off; the video
    // player re-asserts via WakelockPlus.enable() on hideFullscreen.
    WakelockPlus.enable();
    // Drop expired PDF cache entries and enforce the size cap. Lazy
    // fire-and-forget — failures are swallowed inside the service.
    unawaited(PdfCacheService.cleanupExpired());
    unawaited(PdfCacheService.pruneToSizeLimit());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    // Best-effort release on app teardown.
    WakelockPlus.disable();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Only hold the wakelock while we're actually visible. Holding it in
    // the background drains battery on iOS even though the app is suspended.
    if (state == AppLifecycleState.resumed) {
      WakelockPlus.enable();
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      WakelockPlus.disable();
    }
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ThemeProvider()),
        ChangeNotifierProvider(create: (_) => AuthProvider()),
        ChangeNotifierProvider(create: (_) => OnboardingProvider()),
        ChangeNotifierProvider(create: (_) => DashboardProvider()),
        ChangeNotifierProvider(create: (_) => BookProvider()),
        ChangeNotifierProvider(create: (_) => AccessRecordProvider()),
        ChangeNotifierProvider(create: (_) => NotificationProvider()),
        ChangeNotifierProvider(create: (_) => EnrolledCoursesProvider()),
        ChangeNotifierProvider(create: (_) => DownloadProvider()),
        ChangeNotifierProvider(create: (_) => MiniPlayerProvider()),
      ],
      child: Consumer<ThemeProvider>(
        builder: (context, themeProvider, child) {
          return MaterialApp.router(
            title: 'PGME',
            debugShowCheckedModeBanner: false,
            theme: AppTheme.lightTheme,
            darkTheme: AppTheme.darkTheme,
            themeMode: themeProvider.isDarkMode ? ThemeMode.dark : ThemeMode.light,
            routerConfig: AppRouter.router,
            scrollBehavior: const MaterialScrollBehavior().copyWith(
              physics: const ClampingScrollPhysics(),
              overscroll: false,
            ),
            builder: (context, child) {
              // All orientations enabled. The earlier policy locked phones
              // to portrait via setPreferredOrientations, but users want
              // rotation to follow the OS rotation-lock setting.
              return child!;
            },
          );
        },
      ),
    );
  }
}
