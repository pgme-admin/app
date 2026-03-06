import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:no_screenshot/no_screenshot.dart';
import 'package:pgme/core/theme/app_theme.dart';
import 'package:pgme/core/routes/app_router.dart';
import 'package:pgme/core/providers/theme_provider.dart';
import 'package:pgme/core/services/push_notification_service.dart';
import 'package:pgme/features/auth/providers/auth_provider.dart';
import 'package:pgme/features/onboarding/providers/onboarding_provider.dart';
import 'package:pgme/features/home/providers/dashboard_provider.dart';
import 'package:pgme/features/books/providers/book_provider.dart';
import 'package:pgme/features/settings/providers/access_record_provider.dart';
import 'package:pgme/features/notifications/providers/notification_provider.dart';
import 'package:pgme/features/courses/providers/enrolled_courses_provider.dart';
import 'package:pgme/features/courses/providers/download_provider.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Prevent screenshots and screen recording across the entire app
  await NoScreenshot.instance.screenshotOff();

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

  // Run the app immediately — heavy initialization (Firebase, dotenv, etc.)
  // happens inside the splash screen so it shows right away
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  bool _orientationSet = false;

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
              // Lock orientation based on device type once MediaQuery is available
              if (!_orientationSet) {
                _orientationSet = true;
                final shortestSide = MediaQuery.of(context).size.shortestSide;
                final isTablet = shortestSide >= 600;
                if (!isTablet) {
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
