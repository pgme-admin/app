import 'dart:async';
import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:pgme/core/services/user_service.dart';
import 'package:pgme/core/services/storage_service.dart';
import 'package:pgme/core/widgets/in_app_notification.dart';

/// Local notifications plugin (shared between foreground + background)
final FlutterLocalNotificationsPlugin _localNotifications =
    FlutterLocalNotificationsPlugin();

/// Android notification channel for push messages (used by flutter_local_notifications)
const AndroidNotificationChannel _pushChannel = AndroidNotificationChannel(
  'pgme_push',
  'Push Notifications',
  description: 'Notifications from PGME',
  importance: Importance.high,
);

/// Android notification channel matching FCM default (used by OS for background messages)
const AndroidNotificationChannel _fcmDefaultChannel = AndroidNotificationChannel(
  'pgme_default',
  'PGME Notifications',
  description: 'Default notifications from PGME',
  importance: Importance.high,
);

/// Initialize local notifications (called from both foreground and background)
Future<void> _initLocalNotifications() async {
  const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
  const iosSettings = DarwinInitializationSettings(
    requestAlertPermission: false,
    requestBadgePermission: false,
    requestSoundPermission: false,
  );
  const initSettings = InitializationSettings(
    android: androidSettings,
    iOS: iosSettings,
  );
  await _localNotifications.initialize(initSettings);

  // Create Android notification channels
  final androidPlugin = _localNotifications
      .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
  await androidPlugin?.createNotificationChannel(_pushChannel);
  await androidPlugin?.createNotificationChannel(_fcmDefaultChannel);
}

/// Show a local notification from an FCM message
Future<void> _showLocalNotification(RemoteMessage message) async {
  final title = message.notification?.title ??
      message.data['title'] as String? ??
      '';
  final body = message.notification?.body ??
      message.data['body'] as String? ??
      message.data['message'] as String? ??
      '';

  if (title.isEmpty && body.isEmpty) return;

  const androidDetails = AndroidNotificationDetails(
    'pgme_push',
    'Push Notifications',
    channelDescription: 'Notifications from PGME',
    importance: Importance.high,
    priority: Priority.high,
    icon: '@mipmap/ic_launcher',
  );

  const darwinDetails = DarwinNotificationDetails(
    presentAlert: true,
    presentBadge: true,
    presentSound: true,
  );

  const details = NotificationDetails(
    android: androidDetails,
    iOS: darwinDetails,
  );

  final id = message.messageId?.hashCode ?? DateTime.now().millisecondsSinceEpoch % 0x7FFFFFFF;

  await _localNotifications.show(id, title, body, details);
}

/// Top-level background handler (MUST be top-level, not a class method)
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  try {
    await Firebase.initializeApp();
  } catch (_) {
    // Already initialized natively
  }
  // ignore: avoid_print
  print('Background FCM message: ${message.messageId}');

  // Show local notification for data-only messages on both platforms.
  // Messages WITH a notification payload are shown automatically by the OS
  // in background, but data-only messages need manual handling.
  if (message.notification == null) {
    try {
      await _initLocalNotifications();
      await _showLocalNotification(message);
    } catch (e) {
      debugPrint('Background local notification error: $e');
    }
  }
}

class PushNotificationService {
  static final PushNotificationService _instance =
      PushNotificationService._internal();
  factory PushNotificationService() => _instance;
  PushNotificationService._internal();

  final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  final UserService _userService = UserService();
  final StorageService _storageService = StorageService();

  bool _initialized = false;
  bool _tokenRegistered = false;
  StreamSubscription<RemoteMessage>? _foregroundSub;
  StreamSubscription<RemoteMessage>? _tapSub;
  StreamSubscription<String>? _tokenRefreshSub;

  /// Initialize Firebase Messaging and set up handlers.
  /// Call this from main.dart AFTER Firebase.initializeApp()
  Future<void> initialize() async {
    if (_initialized) return;

    // Initialize local notifications for showing FCM messages
    await _initLocalNotifications();

    // Register background handler
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

    // Request permission (iOS requires explicit permission, Android auto-grants)
    final settings = await _messaging.requestPermission(
      alert: true,
      announcement: false,
      badge: true,
      carPlay: false,
      criticalAlert: false,
      provisional: false,
      sound: true,
    );

    // ignore: avoid_print
    print('===== FCM SETUP =====');
    // ignore: avoid_print
    print('FCM Permission: ${settings.authorizationStatus}');

    if (settings.authorizationStatus == AuthorizationStatus.denied) {
      debugPrint('User denied push notification permission');
      return;
    }

    // Disable iOS system notification in foreground — we show our own in-app banner
    await _messaging.setForegroundNotificationPresentationOptions(
      alert: false,
      badge: true,
      sound: true,
    );

    // Check APNs token (critical for iOS)
    final apnsToken = await _messaging.getAPNSToken();
    // ignore: avoid_print
    print('APNs Token: ${apnsToken != null ? "RECEIVED OK" : "NULL - notifications will NOT work!"}');

    // Listen for foreground messages
    _foregroundSub = FirebaseMessaging.onMessage.listen(_handleForegroundMessage);

    // Listen for notification taps (when app is in background/terminated)
    _tapSub = FirebaseMessaging.onMessageOpenedApp.listen(_handleNotificationTap);

    // Check if app was opened from a terminated state via notification tap
    final initialMessage = await _messaging.getInitialMessage();
    if (initialMessage != null) {
      _handleNotificationTap(initialMessage);
    }

    // Listen for token refresh
    _tokenRefreshSub = _messaging.onTokenRefresh.listen(_onTokenRefresh);

    _initialized = true;
    // ignore: avoid_print
    print('===== PUSH SERVICE INITIALIZED =====');
  }

  /// Get FCM token and send to backend.
  /// Call this AFTER successful login or on app startup when already authenticated.
  /// Handles all edge cases: APNs delays (TestFlight/release), network failures,
  /// reinstalls, and token refreshes.
  Future<void> registerToken() async {
    try {
      // On iOS, FCM requires the APNs token before it can return an FCM token.
      // TestFlight/release builds can take much longer than debug to get APNs token.
      // Retry up to 10 times with increasing delays (total ~30s).
      if (Platform.isIOS) {
        String? apnsToken;
        for (int i = 0; i < 10; i++) {
          apnsToken = await _messaging.getAPNSToken();
          if (apnsToken != null) break;
          // Increasing delay: 1s, 1s, 2s, 2s, 3s, 3s, 4s, 4s, 5s, 5s
          await Future.delayed(Duration(seconds: (i ~/ 2) + 1));
          debugPrint('APNs token retry ${i + 1}/10...');
        }
        if (apnsToken == null) {
          // ignore: avoid_print
          print('APNs token unavailable after 10 retries — FCM registration FAILED');
          _tokenRegistered = false;
          return;
        }
        debugPrint('APNs token confirmed, requesting FCM token');
      }

      final token = await _messaging.getToken();
      if (token != null) {
        // ignore: avoid_print
        print('===== FCM TOKEN =====');
        // ignore: avoid_print
        print(token);
        // ignore: avoid_print
        print('===== END FCM TOKEN =====');
        await _userService.updateFCMToken(token);
        _tokenRegistered = true;
        // ignore: avoid_print
        print('FCM token registered with backend ✓');
      } else {
        _tokenRegistered = false;
        // ignore: avoid_print
        print('FCM token was null — will retry via onTokenRefresh');
      }
    } catch (e) {
      _tokenRegistered = false;
      // ignore: avoid_print
      print('Failed to register FCM token: $e');
    }
  }

  /// Retry token registration if it previously failed.
  /// Call this on app resume (AppLifecycleState.resumed) to handle cases where
  /// APNs token wasn't ready at startup or network was unavailable.
  Future<void> retryTokenRegistrationIfNeeded() async {
    if (_tokenRegistered) return;
    final isAuth = await _storageService.isAuthenticated();
    if (!isAuth) return;
    debugPrint('Retrying FCM token registration on app resume...');
    await registerToken();
  }

  /// Subscribe to a subject topic
  Future<void> subscribeToSubject(String subjectId) async {
    try {
      final topic = 'subject_$subjectId';
      await _messaging.subscribeToTopic(topic);
      debugPrint('Subscribed to topic: $topic');
    } catch (e) {
      debugPrint('Failed to subscribe to subject topic: $e');
    }
  }

  /// Unsubscribe from a subject topic
  Future<void> unsubscribeFromSubject(String subjectId) async {
    try {
      final topic = 'subject_$subjectId';
      await _messaging.unsubscribeFromTopic(topic);
      debugPrint('Unsubscribed from topic: $topic');
    } catch (e) {
      debugPrint('Failed to unsubscribe from subject topic: $e');
    }
  }

  /// Handle foreground message (app is open and in focus)
  void _handleForegroundMessage(RemoteMessage message) {
    final title = message.notification?.title ??
        message.data['title'] as String? ??
        '';
    final body = message.notification?.body ??
        message.data['body'] as String? ??
        message.data['message'] as String? ??
        '';

    // ignore: avoid_print
    print('Foreground FCM: $title - $body');

    // Show in-app notification banner (works on both iOS and Android)
    if (title.isNotEmpty || body.isNotEmpty) {
      showInAppNotification(title: title, body: body);
    }
  }

  /// Handle notification tap (app launched from background/terminated)
  void _handleNotificationTap(RemoteMessage message) {
    debugPrint('Notification tap: ${message.data}');
    final data = message.data;
    final clickUrl = data['click_url'];

    if (clickUrl != null && clickUrl.toString().isNotEmpty) {
      _pendingNavigation = clickUrl.toString();
    }
  }

  /// Token refresh handler — FCM automatically refreshes tokens periodically.
  /// This also fires when APNs token becomes available after a delay (TestFlight).
  Future<void> _onTokenRefresh(String newToken) async {
    // ignore: avoid_print
    print('FCM token refreshed — re-registering with backend');
    try {
      final isAuth = await _storageService.isAuthenticated();
      if (isAuth) {
        await _userService.updateFCMToken(newToken);
        _tokenRegistered = true;
        // ignore: avoid_print
        print('Refreshed FCM token registered with backend ✓');
      }
    } catch (e) {
      // ignore: avoid_print
      print('Failed to register refreshed FCM token: $e');
    }
  }

  // Pending deep link navigation (consumed by the router/navigator)
  String? _pendingNavigation;

  /// Consume pending navigation (call from your app shell/router guard)
  String? consumePendingNavigation() {
    final nav = _pendingNavigation;
    _pendingNavigation = null;
    return nav;
  }

  /// Cleanup on logout
  Future<void> cleanup() async {
    // Cancel stream subscriptions to prevent duplicate handlers on re-login
    await _foregroundSub?.cancel();
    await _tapSub?.cancel();
    await _tokenRefreshSub?.cancel();
    _foregroundSub = null;
    _tapSub = null;
    _tokenRefreshSub = null;
    // Don't delete the FCM token itself — the backend clears it on logout
    _initialized = false;
    _tokenRegistered = false;
  }
}
