import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:pgme/core/widgets/shell_back_handler.dart';
import 'package:pgme/core/widgets/in_app_notification.dart';
import 'package:pgme/features/splash/screens/splash_screen.dart';
import 'package:pgme/features/onboarding/screens/onboarding_screen.dart';
import 'package:pgme/features/onboarding/screens/subject_selection_screen.dart';
import 'package:pgme/features/onboarding/screens/congratulations_screen.dart' as onboarding;
import 'package:pgme/features/auth/screens/login_screen.dart';
import 'package:pgme/features/auth/screens/otp_verification_screen.dart';
import 'package:pgme/features/auth/screens/data_collection_screen.dart';
import 'package:pgme/features/auth/screens/multiple_logins_screen.dart';
import 'package:pgme/features/home/screens/main_screen.dart';
import 'package:pgme/features/courses/screens/course_detail_screen.dart';
import 'package:pgme/features/courses/screens/lecture_video_screen.dart';
import 'package:pgme/features/courses/screens/video_player_screen.dart';
import 'package:pgme/features/courses/screens/trailer_video_player_screen.dart';
import 'package:pgme/features/notes/screens/notes_list_screen.dart';
import 'package:pgme/features/notes/screens/available_notes_screen.dart';
import 'package:pgme/features/notes/screens/your_notes_screen.dart';
import 'package:pgme/features/settings/screens/settings_screen.dart';
import 'package:pgme/features/settings/screens/profile_screen.dart';
import 'package:pgme/features/settings/screens/edit_profile_screen.dart';
import 'package:pgme/features/settings/screens/manage_plans_screen.dart';
import 'package:pgme/features/purchase/screens/package_access_screen.dart';
import 'package:pgme/features/purchase/screens/success_screen.dart';
import 'package:pgme/features/purchase/screens/all_packages_screen.dart';
import 'package:pgme/features/sessions/screens/session_details_screen.dart';
import 'package:pgme/features/sessions/screens/series_sessions_screen.dart';
import 'package:pgme/features/workshops/screens/workshops_list_screen.dart';
import 'package:pgme/features/workshops/screens/workshop_details_screen.dart';
import 'package:pgme/features/notes/screens/browse_physical_books_screen.dart';
import 'package:pgme/features/notes/screens/ebook_list_screen.dart';
import 'package:pgme/features/books/screens/book_cart_screen.dart';
import 'package:pgme/features/books/screens/book_confirm_screen.dart';
import 'package:pgme/features/books/screens/book_request_confirmation_screen.dart';
import 'package:pgme/features/books/screens/book_requests_screen.dart';
import 'package:pgme/features/courses/screens/practical_series_screen.dart';
import 'package:pgme/features/courses/screens/revision_series_screen.dart';
import 'package:pgme/features/courses/screens/enrolled_course_detail_screen.dart';
import 'package:pgme/features/notifications/screens/notifications_screen.dart';
import 'package:pgme/features/notifications/screens/notification_detail_screen.dart';
import 'package:pgme/core/models/notification_model.dart';
import 'package:pgme/features/settings/screens/help_screen.dart';
import 'package:pgme/features/settings/screens/about_screen.dart';
import 'package:pgme/features/settings/screens/my_records_screen.dart';
import 'package:pgme/features/settings/screens/careers_screen.dart';
import 'package:pgme/features/settings/screens/terms_and_conditions_screen.dart';
import 'package:pgme/features/settings/screens/privacy_policy_screen.dart';
import 'package:pgme/features/settings/screens/refund_policy_screen.dart';
import 'package:pgme/features/settings/screens/downloads_screen.dart';
import 'package:pgme/core/utils/pdf_engine_policy.dart';
import 'package:pgme/features/notes/screens/epub_viewer_screen.dart';
import 'package:pgme/features/auth/screens/map_address_picker_screen.dart';
import 'package:provider/provider.dart';
import 'package:pgme/core/providers/mini_player_provider.dart';
import 'package:pgme/core/widgets/mini_player_widget.dart';
import 'package:pgme/core/widgets/app_scaffold.dart';
import 'package:pgme/core/services/push_notification_service.dart';

class AppRouter {
  static int _getNavIndex(String location) {
    if (location.startsWith('/revision-series')) return 1;
    if (location.startsWith('/practical-series')) return 2;
    if (location.startsWith('/available-notes')) return 1;
    if (location.startsWith('/your-notes') ||
        location.startsWith('/notes')) return 3;

    // Series sessions are always practical
    if (location.startsWith('/series-sessions')) return 2;

    // Child routes (series-detail, lecture) use packageType to determine tab
    final uri = Uri.parse(location);
    final packageType = uri.queryParameters['packageType'];
    if (packageType == 'Practical') return 2;
    if (packageType == 'Theory') return 1;

    return 0;
  }

  static final GoRouter router = GoRouter(
    navigatorKey: navigatorKey,
    initialLocation: '/',
    debugLogDiagnostics: true,
    redirect: (context, state) {
      // Close the mini player on routes where it shouldn't be visible
      try {
        final miniPlayer = Provider.of<MiniPlayerProvider>(context, listen: false);
        miniPlayer.closeIfRouteRestricted(state.uri.path);
      } catch (_) {
        // Provider not yet available (e.g. splash before providers mount)
      }

      // Consume pending push notification deep link when arriving at /home
      if (state.uri.path == '/home') {
        final pendingUrl = PushNotificationService().consumePendingNavigation();
        if (pendingUrl != null &&
            pendingUrl.isNotEmpty &&
            !pendingUrl.startsWith('http://') &&
            !pendingUrl.startsWith('https://')) {
          debugPrint('Push redirect: /home → $pendingUrl');
          return pendingUrl;
        }
      }

      return null;
    },
    routes: [
      // Splash Screen
      GoRoute(
        path: '/',
        name: 'splash',
        pageBuilder: (context, state) => CustomTransitionPage(
          key: state.pageKey,
          child: const SplashScreen(),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            return FadeTransition(opacity: animation, child: child);
          },
        ),
      ),

      // Onboarding
      GoRoute(
        path: '/onboarding',
        name: 'onboarding',
        pageBuilder: (context, state) => CustomTransitionPage(
          key: state.pageKey,
          child: const OnboardingScreen(),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            return FadeTransition(opacity: animation, child: child);
          },
        ),
      ),

      // Auth Flow
      GoRoute(
        path: '/login',
        name: 'login',
        pageBuilder: (context, state) => CustomTransitionPage(
          key: state.pageKey,
          child: const LoginScreen(),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            return SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(1, 0),
                end: Offset.zero,
              ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic)),
              child: child,
            );
          },
        ),
      ),

      GoRoute(
        path: '/otp-verification',
        name: 'otp-verification',
        pageBuilder: (context, state) {
          return CustomTransitionPage(
            key: state.pageKey,
            child: const OTPVerificationScreen(),
            transitionsBuilder: (context, animation, secondaryAnimation, child) {
              return SlideTransition(
                position: Tween<Offset>(
                  begin: const Offset(1, 0),
                  end: Offset.zero,
                ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic)),
                child: child,
              );
            },
          );
        },
      ),

      GoRoute(
        path: '/data-collection',
        name: 'data-collection',
        pageBuilder: (context, state) => CustomTransitionPage(
          key: state.pageKey,
          child: const DataCollectionScreen(),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            return SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(1, 0),
                end: Offset.zero,
              ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic)),
              child: child,
            );
          },
        ),
      ),

      GoRoute(
        path: '/subject-selection',
        name: 'subject-selection',
        pageBuilder: (context, state) => CustomTransitionPage(
          key: state.pageKey,
          child: const SubjectSelectionScreen(),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            return SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(1, 0),
                end: Offset.zero,
              ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic)),
              child: child,
            );
          },
        ),
      ),

      GoRoute(
        path: '/onboarding-complete',
        name: 'onboarding-complete',
        pageBuilder: (context, state) => CustomTransitionPage(
          key: state.pageKey,
          child: const onboarding.CongratulationsScreen(),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            return FadeTransition(opacity: animation, child: child);
          },
        ),
      ),

      GoRoute(
        path: '/multiple-logins',
        name: 'multiple-logins',
        pageBuilder: (context, state) => CustomTransitionPage(
          key: state.pageKey,
          child: const MultipleLoginsScreen(),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            return SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(1, 0),
                end: Offset.zero,
              ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic)),
              child: child,
            );
          },
        ),
      ),

      // Package Access Flow (outside shell - no nav bar)
      GoRoute(
        path: '/package-access',
        name: 'package-access',
        pageBuilder: (context, state) {
          final packageId = state.uri.queryParameters['packageId'];
          final packageType = state.uri.queryParameters['packageType'];
          return CustomTransitionPage(
            key: state.pageKey,
            child: PackageAccessScreen(packageId: packageId, packageType: packageType),
            transitionsBuilder: (context, animation, secondaryAnimation, child) {
              return SlideTransition(
                position: Tween<Offset>(
                  begin: const Offset(0, 1),
                  end: Offset.zero,
                ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic)),
                child: child,
              );
            },
          );
        },
      ),

      GoRoute(
        path: '/success',
        name: 'success',
        pageBuilder: (context, state) => CustomTransitionPage(
          key: state.pageKey,
          child: const SuccessScreen(),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            return FadeTransition(opacity: animation, child: child);
          },
        ),
      ),

      GoRoute(
        path: '/all-packages',
        name: 'all-packages',
        pageBuilder: (context, state) => CustomTransitionPage(
          key: state.pageKey,
          child: const AllPackagesScreen(),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            return SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(1, 0),
                end: Offset.zero,
              ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic)),
              child: child,
            );
          },
        ),
      ),

      // Notifications
      GoRoute(
        path: '/notifications',
        name: 'notifications',
        pageBuilder: (context, state) => CustomTransitionPage(
          key: state.pageKey,
          child: const NotificationsScreen(),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            return SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(1, 0),
                end: Offset.zero,
              ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic)),
              child: child,
            );
          },
        ),
      ),

      // Notification Detail
      GoRoute(
        path: '/notification-detail',
        name: 'notification-detail',
        pageBuilder: (context, state) {
          final notification = state.extra as NotificationModel;
          return CustomTransitionPage(
            key: state.pageKey,
            child: NotificationDetailScreen(notification: notification),
            transitionsBuilder: (context, animation, secondaryAnimation, child) {
              return SlideTransition(
                position: Tween<Offset>(
                  begin: const Offset(1, 0),
                  end: Offset.zero,
                ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic)),
                child: child,
              );
            },
          );
        },
      ),

      // Help & Support
      GoRoute(
        path: '/help',
        name: 'help',
        pageBuilder: (context, state) => CustomTransitionPage(
          key: state.pageKey,
          child: const HelpScreen(),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            return SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(1, 0),
                end: Offset.zero,
              ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic)),
              child: child,
            );
          },
        ),
      ),

      // About
      GoRoute(
        path: '/about',
        name: 'about',
        pageBuilder: (context, state) => CustomTransitionPage(
          key: state.pageKey,
          child: const AboutScreen(),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            return SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(1, 0),
                end: Offset.zero,
              ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic)),
              child: child,
            );
          },
        ),
      ),

      // Terms and Conditions
      GoRoute(
        path: '/terms-and-conditions',
        name: 'terms-and-conditions',
        pageBuilder: (context, state) => CustomTransitionPage(
          key: state.pageKey,
          child: const TermsAndConditionsScreen(),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            return SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(1, 0),
                end: Offset.zero,
              ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic)),
              child: child,
            );
          },
        ),
      ),

      // Privacy Policy
      GoRoute(
        path: '/privacy-policy',
        name: 'privacy-policy',
        pageBuilder: (context, state) => CustomTransitionPage(
          key: state.pageKey,
          child: const PrivacyPolicyScreen(),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            return SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(1, 0),
                end: Offset.zero,
              ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic)),
              child: child,
            );
          },
        ),
      ),

      // Refund Policy
      GoRoute(
        path: '/refund-policy',
        name: 'refund-policy',
        pageBuilder: (context, state) => CustomTransitionPage(
          key: state.pageKey,
          child: const RefundPolicyScreen(),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            return SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(1, 0),
                end: Offset.zero,
              ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic)),
              child: child,
            );
          },
        ),
      ),

      GoRoute(
        path: '/manage-plans',
        name: 'manage-plans',
        pageBuilder: (context, state) => CustomTransitionPage(
          key: state.pageKey,
          child: const ManagePlansScreen(),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            return SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(1, 0),
                end: Offset.zero,
              ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic)),
              child: child,
            );
          },
        ),
      ),

      // Video Player (fullscreen - no nav bar)
      GoRoute(
        path: '/video/:id',
        name: 'video-player',
        pageBuilder: (context, state) {
          final videoId = state.pathParameters['id']!;
          final resumeStr = state.uri.queryParameters['resume'];
          final resumeFrom = resumeStr != null ? int.tryParse(resumeStr) : null;
          return CustomTransitionPage(
            key: state.pageKey,
            child: VideoPlayerScreen(videoId: videoId, resumeFromSeconds: resumeFrom),
            transitionsBuilder: (context, animation, secondaryAnimation, child) {
              return SlideTransition(
                position: Tween<Offset>(
                  begin: const Offset(0, 1),
                  end: Offset.zero,
                ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic)),
                child: child,
              );
            },
          );
        },
      ),

      // Trailer Video Player (for package type trailers)
      GoRoute(
        path: '/trailer-video',
        name: 'trailer-video',
        pageBuilder: (context, state) {
          final extra = state.extra as Map<String, dynamic>;
          final videoUrl = extra['videoUrl'] as String;
          final videoTitle = extra['videoTitle'] as String;
          return CustomTransitionPage(
            key: state.pageKey,
            child: TrailerVideoPlayerScreen(
              videoUrl: videoUrl,
              videoTitle: videoTitle,
            ),
            transitionsBuilder: (context, animation, secondaryAnimation, child) {
              return SlideTransition(
                position: Tween<Offset>(
                  begin: const Offset(0, 1),
                  end: Offset.zero,
                ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic)),
                child: child,
              );
            },
          );
        },
      ),

      // Book Confirm (outside shell - no nav bar)
      GoRoute(
        path: '/book-confirm',
        name: 'book-confirm',
        pageBuilder: (context, state) => CustomTransitionPage(
          key: state.pageKey,
          child: const BookConfirmScreen(),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            return SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(1, 0),
                end: Offset.zero,
              ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic)),
              child: child,
            );
          },
        ),
      ),

      // Book Request Confirmation (outside shell - no nav bar)
      GoRoute(
        path: '/book-request-confirmation/:requestId',
        name: 'book-request-confirmation',
        pageBuilder: (context, state) {
          final requestId = state.pathParameters['requestId']!;
          return CustomTransitionPage(
            key: state.pageKey,
            child: BookRequestConfirmationScreen(requestId: requestId),
            transitionsBuilder: (context, animation, secondaryAnimation, child) {
              return SlideTransition(
                position: Tween<Offset>(
                  begin: const Offset(1, 0),
                  end: Offset.zero,
                ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic)),
                child: child,
              );
            },
          );
        },
      ),

      // Shell Route - routes with persistent nav bar
      ShellRoute(
        builder: (context, state, child) {
          final location = state.uri.toString();
          final path = state.uri.path;

          // Hide nav bar on profile, edit-profile, map-address-picker, and pdf-viewer screens
          if (path.startsWith('/profile') ||
              path.startsWith('/edit-profile') ||
              path.startsWith('/map-address-picker') ||
              path.startsWith('/pdf-viewer') ||
              path.startsWith('/epub-viewer') ||
              path.startsWith('/downloads')) {
            final bottomPad = MediaQuery.of(context).padding.bottom;
            return ShellBackHandler(
              isHome: false,
              child: Stack(
                children: [
                  child,
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: bottomPad + 16,
                    child: const MiniPlayerWidget(),
                  ),
                ],
              ),
            );
          }

          final navIndex = _getNavIndex(location);
          final isSubscribed = state.uri.queryParameters['subscribed'] == 'true';
          return ShellBackHandler(
            // Not navIndex == 0: course pages and others also map to tab 0.
            isHome: path == '/home',
            child: AppScaffold(
              currentIndex: navIndex,
              isSubscribed: isSubscribed,
              child: child,
            ),
          );
        },
        routes: [
          // Main App
          GoRoute(
            path: '/home',
            name: 'home',
            pageBuilder: (context, state) {
              final isSubscribed = state.uri.queryParameters['subscribed'] == 'true';
              return CustomTransitionPage(
                key: state.pageKey,
                child: MainScreen(isSubscribed: isSubscribed),
                transitionsBuilder: (context, animation, secondaryAnimation, child) {
                  return FadeTransition(opacity: animation, child: child);
                },
              );
            },
          ),

          // Course Details
          GoRoute(
            path: '/course/:id',
            name: 'course-detail',
            pageBuilder: (context, state) {
              final seriesId = state.pathParameters['id']!;
              return CustomTransitionPage(
                key: state.pageKey,
                child: CourseDetailScreen(seriesId: seriesId),
                transitionsBuilder: (context, animation, secondaryAnimation, child) {
                  return SlideTransition(
                    position: Tween<Offset>(
                      begin: const Offset(1, 0),
                      end: Offset.zero,
                    ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic)),
                    child: child,
                  );
                },
              );
            },
          ),

          // Series Detail (for unpurchased users - shows demo video and sample PDF/live session options)
          GoRoute(
            path: '/series-detail/:id',
            name: 'series-detail',
            pageBuilder: (context, state) {
              final seriesId = state.pathParameters['id']!;
              final isSubscribed = state.uri.queryParameters['subscribed'] == 'true';
              final packageType = state.uri.queryParameters['packageType'] ?? 'Theory';
              final packageId = state.uri.queryParameters['packageId'];
              return CustomTransitionPage(
                key: state.pageKey,
                child: EnrolledCourseDetailScreen(
                  seriesId: seriesId,
                  isSubscribed: isSubscribed,
                  packageType: packageType,
                  packageId: packageId,
                ),
                transitionsBuilder: (context, animation, secondaryAnimation, child) {
                  return SlideTransition(
                    position: Tween<Offset>(
                      begin: const Offset(1, 0),
                      end: Offset.zero,
                    ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic)),
                    child: child,
                  );
                },
              );
            },
          ),

          // Lecture Video Screen
          GoRoute(
            path: '/lecture/:id',
            name: 'lecture-video',
            pageBuilder: (context, state) {
              final courseId = state.pathParameters['id']!;
              final isSubscribed = state.uri.queryParameters['subscribed'] == 'true';
              final packageType = state.uri.queryParameters['packageType'] ?? 'Theory';
              final packageId = state.uri.queryParameters['packageId'];
              return CustomTransitionPage(
                key: state.pageKey,
                child: LectureVideoScreen(courseId: courseId, isSubscribed: isSubscribed, packageType: packageType, packageId: packageId),
                transitionsBuilder: (context, animation, secondaryAnimation, child) {
                  return SlideTransition(
                    position: Tween<Offset>(
                      begin: const Offset(1, 0),
                      end: Offset.zero,
                    ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic)),
                    child: child,
                  );
                },
              );
            },
          ),

          // Notes
          GoRoute(
            path: '/notes',
            name: 'notes',
            pageBuilder: (context, state) {
              final isSubscribed = state.uri.queryParameters['subscribed'] == 'true';
              return CustomTransitionPage(
                key: state.pageKey,
                child: NotesListScreen(isSubscribed: isSubscribed),
                transitionsBuilder: (context, animation, secondaryAnimation, child) {
                  return SlideTransition(
                    position: Tween<Offset>(
                      begin: const Offset(1, 0),
                      end: Offset.zero,
                    ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic)),
                    child: child,
                  );
                },
              );
            },
          ),

          // Available Notes
          GoRoute(
            path: '/available-notes',
            name: 'available-notes',
            pageBuilder: (context, state) {
              final seriesId = state.uri.queryParameters['seriesId'] ?? '';
              final isSubscribed = state.uri.queryParameters['subscribed'] == 'true';
              final packageId = state.uri.queryParameters['packageId'];
              return CustomTransitionPage(
                key: state.pageKey,
                child: AvailableNotesScreen(seriesId: seriesId, isSubscribed: isSubscribed, packageId: packageId),
                transitionsBuilder: (context, animation, secondaryAnimation, child) {
                  return SlideTransition(
                    position: Tween<Offset>(
                      begin: const Offset(1, 0),
                      end: Offset.zero,
                    ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic)),
                    child: child,
                  );
                },
              );
            },
          ),

          // PDF Viewer
          GoRoute(
            path: '/pdf-viewer',
            name: 'pdf-viewer',
            pageBuilder: (context, state) {
              final documentId = state.uri.queryParameters['documentId'];
              final pdfUrl = state.uri.queryParameters['pdfUrl'];
              final title = state.uri.queryParameters['title'] ?? 'PDF Viewer';
              // 'ebook' makes Retry fetch a fresh signed link from the ebook
              // endpoint (the one in pdfUrl expires).
              final source = state.uri.queryParameters['source'];
              return CustomTransitionPage(
                key: state.pageKey,
                child: PdfEnginePolicy.buildReader(
                    documentId: documentId, pdfUrl: pdfUrl, title: title, source: source),
                transitionsBuilder: (context, animation, secondaryAnimation, child) {
                  return SlideTransition(
                    position: Tween<Offset>(
                      begin: const Offset(1, 0),
                      end: Offset.zero,
                    ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic)),
                    child: child,
                  );
                },
              );
            },
          ),

          // EPUB Viewer
          GoRoute(
            path: '/epub-viewer',
            name: 'epub-viewer',
            pageBuilder: (context, state) {
              final documentId = state.uri.queryParameters['documentId'];
              final epubUrl = state.uri.queryParameters['epubUrl'];
              final source = state.uri.queryParameters['source'];
              final title = state.uri.queryParameters['title'] ?? 'Reader';
              return CustomTransitionPage(
                key: state.pageKey,
                child: EpubViewerScreen(documentId: documentId, epubUrl: epubUrl, source: source, title: title),
                transitionsBuilder: (context, animation, secondaryAnimation, child) {
                  return SlideTransition(
                    position: Tween<Offset>(
                      begin: const Offset(1, 0),
                      end: Offset.zero,
                    ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic)),
                    child: child,
                  );
                },
              );
            },
          ),

          // Your Notes (for subscribed users)
          GoRoute(
            path: '/your-notes',
            name: 'your-notes',
            pageBuilder: (context, state) => CustomTransitionPage(
              key: state.pageKey,
              child: const YourNotesScreen(),
              transitionsBuilder: (context, animation, secondaryAnimation, child) {
                return SlideTransition(
                  position: Tween<Offset>(
                    begin: const Offset(1, 0),
                    end: Offset.zero,
                  ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic)),
                  child: child,
                );
              },
            ),
          ),

          // Profile (no nav bar - handled in shell builder)
          GoRoute(
            path: '/profile',
            name: 'profile',
            pageBuilder: (context, state) => CustomTransitionPage(
              key: state.pageKey,
              child: const ProfileScreen(),
              transitionsBuilder: (context, animation, secondaryAnimation, child) {
                return SlideTransition(
                  position: Tween<Offset>(
                    begin: const Offset(1, 0),
                    end: Offset.zero,
                  ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic)),
                  child: child,
                );
              },
            ),
          ),

          // Downloads (no nav bar)
          GoRoute(
            path: '/downloads',
            name: 'downloads',
            pageBuilder: (context, state) => CustomTransitionPage(
              key: state.pageKey,
              child: const DownloadsScreen(),
              transitionsBuilder: (context, animation, secondaryAnimation, child) {
                return SlideTransition(
                  position: Tween<Offset>(
                    begin: const Offset(1, 0),
                    end: Offset.zero,
                  ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic)),
                  child: child,
                );
              },
            ),
          ),

          // Edit Profile
          GoRoute(
            path: '/edit-profile',
            name: 'edit-profile',
            pageBuilder: (context, state) {
              final user = state.extra as dynamic;
              return CustomTransitionPage(
                key: state.pageKey,
                child: EditProfileScreen(user: user),
                transitionsBuilder: (context, animation, secondaryAnimation, child) {
                  return SlideTransition(
                    position: Tween<Offset>(
                      begin: const Offset(1, 0),
                      end: Offset.zero,
                    ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic)),
                    child: child,
                  );
                },
              );
            },
          ),

          // Map Address Picker
          GoRoute(
            path: '/map-address-picker',
            name: 'map-address-picker',
            pageBuilder: (context, state) => CustomTransitionPage(
              key: state.pageKey,
              child: const MapAddressPickerScreen(),
              transitionsBuilder: (context, animation, secondaryAnimation, child) {
                return SlideTransition(
                  position: Tween<Offset>(
                    begin: const Offset(0, 1),
                    end: Offset.zero,
                  ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic)),
                  child: child,
                );
              },
            ),
          ),

          // Settings
          GoRoute(
            path: '/settings',
            name: 'settings',
            pageBuilder: (context, state) => CustomTransitionPage(
              key: state.pageKey,
              child: const SettingsScreen(),
              transitionsBuilder: (context, animation, secondaryAnimation, child) {
                return SlideTransition(
                  position: Tween<Offset>(
                    begin: const Offset(1, 0),
                    end: Offset.zero,
                  ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic)),
                  child: child,
                );
              },
            ),
          ),

          // Session Details
          GoRoute(
            path: '/session/:id',
            name: 'session-details',
            pageBuilder: (context, state) {
              final sessionId = state.pathParameters['id']!;
              return CustomTransitionPage(
                key: state.pageKey,
                child: SessionDetailsScreen(sessionId: sessionId),
                transitionsBuilder: (context, animation, secondaryAnimation, child) {
                  return SlideTransition(
                    position: Tween<Offset>(
                      begin: const Offset(1, 0),
                      end: Offset.zero,
                    ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic)),
                    child: child,
                  );
                },
              );
            },
          ),

          // Workshops (multi-day programmes)
          GoRoute(
            path: '/workshops',
            name: 'workshops',
            pageBuilder: (context, state) => CustomTransitionPage(
              key: state.pageKey,
              child: const WorkshopsListScreen(),
              transitionsBuilder: (context, animation, secondaryAnimation, child) {
                return SlideTransition(
                  position: Tween<Offset>(
                    begin: const Offset(1, 0),
                    end: Offset.zero,
                  ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic)),
                  child: child,
                );
              },
            ),
          ),

          // Workshop Details
          GoRoute(
            path: '/workshop/:id',
            name: 'workshop-details',
            pageBuilder: (context, state) {
              final workshopId = state.pathParameters['id']!;
              return CustomTransitionPage(
                key: state.pageKey,
                child: WorkshopDetailsScreen(workshopId: workshopId),
                transitionsBuilder: (context, animation, secondaryAnimation, child) {
                  return SlideTransition(
                    position: Tween<Offset>(
                      begin: const Offset(1, 0),
                      end: Offset.zero,
                    ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic)),
                    child: child,
                  );
                },
              );
            },
          ),

          // Series Live Sessions (for practical packages)
          GoRoute(
            path: '/series-sessions/:id',
            name: 'series-sessions',
            pageBuilder: (context, state) {
              final seriesId = state.pathParameters['id']!;
              final seriesName = state.uri.queryParameters['seriesName'];
              return CustomTransitionPage(
                key: state.pageKey,
                child: SeriesSessionsScreen(
                  seriesId: seriesId,
                  seriesName: seriesName,
                ),
                transitionsBuilder: (context, animation, secondaryAnimation, child) {
                  return SlideTransition(
                    position: Tween<Offset>(
                      begin: const Offset(1, 0),
                      end: Offset.zero,
                    ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic)),
                    child: child,
                  );
                },
              );
            },
          ),

          // Browse Physical Books
          GoRoute(
            path: '/browse-physical-books',
            name: 'browse-physical-books',
            pageBuilder: (context, state) => CustomTransitionPage(
              key: state.pageKey,
              child: const BrowsePhysicalBooksScreen(),
              transitionsBuilder: (context, animation, secondaryAnimation, child) {
                return SlideTransition(
                  position: Tween<Offset>(
                    begin: const Offset(1, 0),
                    end: Offset.zero,
                  ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic)),
                  child: child,
                );
              },
            ),
          ),

          // eBook Store
          GoRoute(
            path: '/ebook-store',
            name: 'ebook-store',
            pageBuilder: (context, state) {
              final bookId = state.uri.queryParameters['bookId'];
              return CustomTransitionPage(
                key: state.pageKey,
                child: EbookListScreen(initialBookId: bookId),
                transitionsBuilder: (context, animation, secondaryAnimation, child) {
                  return SlideTransition(
                    position: Tween<Offset>(
                      begin: const Offset(1, 0),
                      end: Offset.zero,
                    ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic)),
                    child: child,
                  );
                },
              );
            },
          ),

          // Book Cart
          GoRoute(
            path: '/book-cart',
            name: 'book-cart',
            pageBuilder: (context, state) => CustomTransitionPage(
              key: state.pageKey,
              child: const BookCartScreen(),
              transitionsBuilder: (context, animation, secondaryAnimation, child) {
                return SlideTransition(
                  position: Tween<Offset>(
                    begin: const Offset(1, 0),
                    end: Offset.zero,
                  ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic)),
                  child: child,
                );
              },
            ),
          ),

          // Book Requests List
          GoRoute(
            path: '/book-requests',
            name: 'book-requests',
            pageBuilder: (context, state) => CustomTransitionPage(
              key: state.pageKey,
              child: const BookRequestsScreen(),
              transitionsBuilder: (context, animation, secondaryAnimation, child) {
                return SlideTransition(
                  position: Tween<Offset>(
                    begin: const Offset(1, 0),
                    end: Offset.zero,
                  ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic)),
                  child: child,
                );
              },
            ),
          ),

          // My Records
          GoRoute(
            path: '/my-records',
            name: 'my-records',
            pageBuilder: (context, state) => CustomTransitionPage(
              key: state.pageKey,
              child: const MyRecordsScreen(),
              transitionsBuilder: (context, animation, secondaryAnimation, child) {
                return SlideTransition(
                  position: Tween<Offset>(
                    begin: const Offset(1, 0),
                    end: Offset.zero,
                  ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic)),
                  child: child,
                );
              },
            ),
          ),

          // Careers
          GoRoute(
            path: '/careers',
            name: 'careers',
            pageBuilder: (context, state) => CustomTransitionPage(
              key: state.pageKey,
              child: const CareersScreen(),
              transitionsBuilder: (context, animation, secondaryAnimation, child) {
                return SlideTransition(
                  position: Tween<Offset>(
                    begin: const Offset(1, 0),
                    end: Offset.zero,
                  ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic)),
                  child: child,
                );
              },
            ),
          ),

          // Practical Series
          GoRoute(
            path: '/practical-series',
            name: 'practical-series',
            pageBuilder: (context, state) {
              final isSubscribed = state.uri.queryParameters['subscribed'] == 'true';
              final packageId = state.uri.queryParameters['packageId'];
              return CustomTransitionPage(
                key: state.pageKey,
                child: PracticalSeriesScreen(
                  isSubscribed: isSubscribed,
                  packageId: packageId,
                ),
                transitionsBuilder: (context, animation, secondaryAnimation, child) {
                  return SlideTransition(
                    position: Tween<Offset>(
                      begin: const Offset(1, 0),
                      end: Offset.zero,
                    ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic)),
                    child: child,
                  );
                },
              );
            },
          ),

          // Revision Series (Theory Packages)
          GoRoute(
            path: '/revision-series',
            name: 'revision-series',
            pageBuilder: (context, state) {
              final isSubscribed = state.uri.queryParameters['subscribed'] == 'true';
              final packageId = state.uri.queryParameters['packageId'];
              return CustomTransitionPage(
                key: state.pageKey,
                child: RevisionSeriesScreen(
                  isSubscribed: isSubscribed,
                  packageId: packageId,
                ),
                transitionsBuilder: (context, animation, secondaryAnimation, child) {
                  return SlideTransition(
                    position: Tween<Offset>(
                      begin: const Offset(1, 0),
                      end: Offset.zero,
                    ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic)),
                    child: child,
                  );
                },
              );
            },
          ),
        ],
      ),
    ],
  );
}
