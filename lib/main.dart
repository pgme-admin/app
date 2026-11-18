import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:no_screenshot/no_screenshot.dart';
import 'package:pgme/core/theme/app_theme.dart';
import 'package:pgme/core/routes/app_router.dart';
import 'package:pgme/core/providers/theme_provider.dart';
import 'package:pgme/core/services/pdf_cache_service.dart';
import 'package:pgme/core/utils/pdf_engine_policy.dart';
import 'package:pgme/core/utils/responsive_helper.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:pgme/core/services/push_notification_service.dart';
import 'package:pgme/features/auth/providers/auth_provider.dart';
import 'package:pgme/features/onboarding/providers/onboarding_provider.dart';
import 'package:pgme/features/home/providers/dashboard_provider.dart';
import 'package:pgme/features/books/providers/book_provider.dart';
import 'package:pgme/features/settings/providers/access_record_provider.dart';
import 'package:pgme/features/notifications/providers/notification_provider.dart';
import 'package:pgme/features/courses/providers/enrolled_courses_provider.dart';
import 'package:pgme/features/courses/providers/download_provider.dart';
import 'package:pgme/core/providers/mini_player_provider.dart';
import 'package:pgme/core/services/memory_monitor.dart';

/// Lets a build permit screenshots and screen recording.
///
/// Off unless a build explicitly passes
/// `--dart-define=ALLOW_SCREEN_CAPTURE=true`, so the protection can only ever
/// be lifted deliberately — a plain `flutter build` always produces a locked
/// binary. Intended for demo and QA builds; a build made with this must not be
/// handed to students, since it removes the only barrier to recording paid
/// lecture content.
const bool kAllowScreenCapture =
    bool.fromEnvironment('ALLOW_SCREEN_CAPTURE');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Cap Flutter's in-memory image cache. Without this, the cache is
  // effectively unbounded (default ~100MB bytes / 1000 entries) and on a
  // heavy scrolling session it balloons to 150-250MB of decoded bitmaps —
  // which is the primary contributor to OOMs on mid-tier Android tablets
  // whose per-app heap is capped at 256-384MB by the OEM. 80MB is enough
  // for two screens of full-resolution thumbnails; anything older gets
  // evicted LRU-style and re-decoded from CachedNetworkImage's disk cache.
  // Flutter automatically clears this cache on `didHaveMemoryPressure`, so
  // this is a long-term ceiling, not a one-shot.
  PaintingBinding.instance.imageCache.maximumSizeBytes = 80 << 20; // 80 MB
  PaintingBinding.instance.imageCache.maximumSize = 150;

  // Tag-prefixed heap logging so we can track per-app heap headroom in adb
  // logcat. Surfaces growth toward the OEM cap (256-384MB on mid-tier
  // Android) and warns at 80% / 95%. Filter with: adb logcat | findstr MEM
  MemoryMonitor.instance.start();

  // Block screenshots and screen recording app-wide.
  //
  // MainActivity also sets FLAG_SECURE in onCreate, so the native window is
  // locked before the first frame regardless. screenshotOn() clears that flag,
  // which is why lifting the restriction only needs this one branch.
  if (kAllowScreenCapture) {
    await NoScreenshot.instance.screenshotOn();
  } else {
    await NoScreenshot.instance.screenshotOff();
  }

  // Set system UI overlay style immediately
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
      statusBarBrightness: Brightness.light,
      systemNavigationBarColor: Colors.white,
      systemNavigationBarIconBrightness: Brightness.dark,
    ),
  );

  // Allow all orientations initially, then lock based on device type after first frame
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);

  // Cache the Android API level so PDF readers can pick pdfrx on old devices.
  // Never throws and is time-capped inside; getter is safe if this is skipped.
  try {
    await PdfEnginePolicy.init();
  } catch (_) {}

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
  bool _orientationSet = false;
  // Phone (portrait only) or tablet (rotates), as last applied.
  bool? _tabletClass;

  @override
  void didChangeMetrics() {
    // The class was decided once at launch, so a foldable opened on its cover
    // screen (or the app started in split screen) stayed portrait-locked
    // after unfolding / going full screen. Re-apply the rule when the class
    // changes; rotation and the keyboard never change it.
    final current = _tabletClass;
    if (current == null) return;
    final view = WidgetsBinding.instance.platformDispatcher.views.first;
    if (view.devicePixelRatio <= 0) return;
    final shortest = view.physicalSize.shortestSide / view.devicePixelRatio;
    if (shortest <= 0) return;
    final tablet = shortest >= ResponsiveHelper.rotationTabletBreakpoint;
    if (tablet == current) return;
    _tabletClass = tablet;
    SystemChrome.setPreferredOrientations(
        ResponsiveHelper.supportedOrientationsForDevice());
  }

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
    // Only hold the wakelock while we're actually visible.
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
              // Apply the device-appropriate orientation policy once. Using
              // ResponsiveHelper.isTabletDevice() (looser than the layout
              // breakpoint) so borderline tablets like the Lenovo Yoga Tab 11
              // don't get portrait-locked.
              if (!_orientationSet) {
                _orientationSet = true;
                _tabletClass = ResponsiveHelper.isTabletDevice();
                if (!_tabletClass!) {
                  SystemChrome.setPreferredOrientations([
                    DeviceOrientation.portraitUp,
                    DeviceOrientation.portraitDown,
                  ]);
                }
              }
              return child!;
            },
          );
        },
      ),
    );
  }
}
