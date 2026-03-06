import 'dart:io';
import 'package:flutter_dotenv/flutter_dotenv.dart';

class ApiConstants {
  // Platform-aware helper: use neutral aliases on iOS
  static bool get _useAlias => Platform.isIOS;
  // Base URL - Use deployed backend on Render
  // static const String baseUrl = 'http://192.168.29.105:5000/api/v1';
  static const String baseUrl = 'https://d1po9pb0pflxq5.cloudfront.net/api/v1';
//   static const String baseUrl = 'https://pgme-backend.onrender.com/api/v1';

  // Timeout
  static const int connectTimeout = 30000; // 30 seconds
  static const int receiveTimeout = 30000; // 30 seconds

  // MSG91 Configuration
  static const String msg91WidgetId = '3662426d6a49313834333034';
  static const String msg91AuthToken = '497163T6jH5bBz69a2e7cbP1';

  // Authentication Endpoints
  static const String verifyWidget = '/auth/verify-widget';
  static const String refreshToken = '/auth/refresh-token';
  static const String logout = '/auth/logout';
  static const String activeSessions = '/auth/active-sessions';
  static String deviceSession(String sessionId) =>
      '/auth/device-session/$sessionId';
  static const String webLoginToken = '/auth/web-login-token';

  // Web Store Base URL
  static const String webStoreBaseUrl = 'https://store-frontend-ivory.vercel.app';

  // User Endpoints (Onboarding accessible)
  static const String profile = '/users/profile';
  static const String uploadPhoto = '/users/upload-photo';
  static const String subjectSelection = '/users/subject-selection';
  static const String onboardingComplete = '/users/onboarding-complete';

  // User Endpoints (Protected - requires onboarding)
  static const String preferences = '/users/preferences';
  static const String fcmToken = '/users/fcm-token';

  // Subject Endpoints
  static const String subjects = '/subjects';
  static String subject(String subjectId) => '/subjects/$subjectId';

  // Dashboard Endpoints (Fixed to match backend routes)
  static const String nextUpcomingSession = '/live-sessions/next-upcoming';
  static const String liveSessions = '/live-sessions';
  static String liveSessionDetails(String sessionId) =>
      '/live-sessions/$sessionId';
  static String sessionAccessStatus(String sessionId) =>
      '/live-sessions/$sessionId/access-status';
  static String sessionCreateOrder(String sessionId) =>
      '/live-sessions/$sessionId/create-order';
  static String sessionVerifyPayment(String sessionId) =>
      '/live-sessions/$sessionId/verify-payment';
  static String sessionTestPurchase(String sessionId) =>
      '/live-sessions/$sessionId/test-purchase';
  static String sessionJoin(String sessionId) =>
      '/live-sessions/$sessionId/join';
  static String sessionZoomSignature(String sessionId) =>
      '/live-sessions/$sessionId/zoom-signature';
  static const String userSessionPurchases = '/users/session-purchases';
  static String activeSessionInitAccess(String sessionId) => _useAlias ? '/live-sessions/$sessionId/init-session' : sessionCreateOrder(sessionId);
  static String activeSessionConfirmAccess(String sessionId) => _useAlias ? '/live-sessions/$sessionId/confirm-access' : sessionVerifyPayment(sessionId);
  static String activeSessionTestAccess(String sessionId) => _useAlias ? '/live-sessions/$sessionId/test-access' : sessionTestPurchase(sessionId);
  static String get activeSessionActivity => _useAlias ? '/session-activity' : userSessionPurchases;

  // Enrollment Endpoints
  static String sessionEnrollmentStatus(String sessionId) =>
      '/live-sessions/$sessionId/enrollment-status';
  static String sessionEnroll(String sessionId) =>
      '/live-sessions/$sessionId/enroll';
  static String sessionCapacity(String sessionId) =>
      '/live-sessions/$sessionId/capacity';
  static const String userEnrollments = '/users/me/enrollments';
  static const String sessionPurchases = '/session-purchases';
  static String sessionPurchaseStatus(String sessionId) =>
      '/session-purchases/$sessionId/status';
  static const String subjectSelections = '/users/subject-selections';
  static const String packages = '/packages';
  static const String packageTypes = '/package-types';
  static String packageSeries(String packageId) =>
      '/packages/$packageId/series';
  static String packageTestPurchase(String packageId) =>
      '/packages/$packageId/test-purchase';
  static const String lastWatched = '/users/progress/last-watched';
  static const String faculty = '/faculty';
  static String facultyDetails(String facultyId) => '/faculty/$facultyId';

  // Banner Endpoints
  static const String banners = '/banners';

  // Home Sections Endpoint (public, no auth)
  static const String homeSections = '/home-sections';

  // Library Endpoints
  static const String userLibrary = '/users/library';
  static String libraryItem(String libraryId) => '/users/library/$libraryId';
  static String libraryBookmark(String libraryId) =>
      '/users/library/$libraryId/bookmark';

  // Record Endpoints
  static const String userPurchases = '/users/purchases';
  static const String purchases = '/users/purchases';
  static const String allPurchases = '/users/purchases/all';
  static const String subscriptionStatus =
      '/users/purchases/subscription-status';
  static String purchaseDetails(String purchaseId) =>
      '/users/purchases/$purchaseId';
  static String get activeUserRecords => _useAlias ? '/users/activity' : userPurchases;
  static String get activeAllRecords => _useAlias ? '/users/activity/all' : allPurchases;
  static String get activeAccessLevel => _useAlias ? '/users/activity/access-level' : subscriptionStatus;
  static String activeRecordDetails(String id) => _useAlias ? '/users/activity/$id' : purchaseDetails(id);

  // App Settings Endpoints
  static const String appSettings = '/app-settings';

  // Series & Progress Endpoints
  static const String series = '/series';
  static const String progress = '/users/progress';
  // Correct video-progress endpoints (backend: POST/GET /users/progress/video/:id)
  static String updateVideoProgress(String videoId) =>
      '/users/progress/video/$videoId';
  static String getVideoProgress(String videoId) =>
      '/users/progress/video/$videoId';

  // Video Playback Endpoints
  static String videoPlayback(String videoId) => '/videos/$videoId/playback';
  static String videoDownloadUrl(String videoId) =>
      '/videos/$videoId/download-url';

  // Video Review Endpoints
  static String videoMyReview(String videoId) => '/videos/$videoId/my-review';
  static String submitVideoRating(String videoId) => '/videos/$videoId/rating';
  static String submitVideoFeedback(String videoId) =>
      '/videos/$videoId/feedback';

  // Document Endpoints
  static String documentViewUrl(String documentId) =>
      '/documents/$documentId/view-url';

  // Document Highlight Endpoints
  static const String documentHighlights = '/users/document-highlights';
  static String documentHighlight(String highlightId) =>
      '/users/document-highlights/$highlightId';
  static String documentHighlightNote(String highlightId) =>
      '/users/document-highlights/$highlightId/note';

  // Document Bookmark Endpoints
  static const String documentBookmarks = '/users/document-bookmarks';
  static String documentBookmark(String bookmarkId) =>
      '/users/document-bookmarks/$bookmarkId';
  static String documentBookmarkNote(String bookmarkId) =>
      '/users/document-bookmarks/$bookmarkId/note';

  // Document Progress Endpoints
  static String documentProgress(String documentId) =>
      '/users/progress/document/$documentId';

  // Career Application Endpoints
  static const String careerApplications = '/career-applications';

  // Library Endpoints (additional)
  static const String library = '/users/library';
  static const String addToLibrary = '/users/library';
  static String removeFromLibrary(String libraryId) =>
      '/users/library/$libraryId';

  // Book Endpoints
  static const String books = '/books';
  static const String bookCategories = '/books/categories';
  static const String searchBooks = '/books/search';
  static String bookDetails(String bookId) => '/books/$bookId';
  static String bookStock(String bookId) => '/books/$bookId/stock';

  // Book Request Endpoints
  static const String bookOrders = '/book-orders';
  static const String createBookOrder = '/book-orders/create-order';
  static const String verifyBookPayment = '/book-orders/verify-payment';
  static const String testBookOrder = '/book-orders/test-order';
  static String bookOrderDetails(String orderId) => '/book-orders/$orderId';
  static String cancelBookOrder(String orderId) =>
      '/book-orders/$orderId/cancel';
  static String get activeBookRequests => _useAlias ? '/book-requests' : bookOrders;
  static String get activeInitBookRequest => _useAlias ? '/book-requests/init-session' : createBookOrder;
  static String get activeConfirmBookRequest => _useAlias ? '/book-requests/confirm' : verifyBookPayment;
  static String activeBookRequestDetails(String id) => _useAlias ? '/book-requests/$id' : bookOrderDetails(id);
  static String activeCancelBookRequest(String id) => _useAlias ? '/book-requests/$id/cancel' : cancelBookOrder(id);

  // User Reads Endpoints
  static const String ebookOrders = '/ebook-orders';
  static const String createEbookOrder = '/ebook-orders/create-order';
  static const String verifyEbookPayment = '/ebook-orders/verify-payment';
  static String ebookViewUrl(String bookId) => '/ebook-orders/$bookId/view-url';
  static String get activeUserReads => _useAlias ? '/user-reads' : ebookOrders;
  static String get activeInitUserRead => _useAlias ? '/user-reads/init-session' : createEbookOrder;
  static String get activeConfirmUserRead => _useAlias ? '/user-reads/confirm' : verifyEbookPayment;
  static String activeReadViewUrl(String bookId) => _useAlias ? '/user-reads/$bookId/view-url' : ebookViewUrl(bookId);

  // Access Endpoints
  static const String createPaymentOrder =
      '/payments/create-order'; // For packages
  static const String verifyPayment = '/payments/verify'; // For packages
  static String get activeInitAccessSession => _useAlias ? '/content-access/init-session' : createPaymentOrder;
  static String get activeConfirmAccess => _useAlias ? '/content-access/confirm' : verifyPayment;

  // Tier Change Endpoints
  static const String calculateUpgrade = '/payments/upgrade/calculate';
  static const String createUpgradeOrder = '/payments/upgrade/create-order';
  static const String verifyUpgradePayment = '/payments/upgrade/verify';
  static String get activeTierPreview => _useAlias ? '/content-access/tier-preview' : calculateUpgrade;
  static String get activeTierInit => _useAlias ? '/content-access/tier-init' : createUpgradeOrder;
  static String get activeTierConfirm => _useAlias ? '/content-access/tier-confirm' : verifyUpgradePayment;

  // Gateway Configuration
  static const String gatewayScriptUrl =
      'https://static.zohocdn.com/zpay/zpay-js/v1/zpayments.js';

  // Get gateway credentials from environment
  static String get gatewayAccountId =>
      dotenv.env['PG_ACCOUNT_ID'] ?? '';
  static String get gatewayApiKey => dotenv.env['PG_API_KEY'] ?? '';

  // Record Export Endpoints
  static String invoiceByPurchase(String purchaseId) => '/invoices/$purchaseId';
  static String invoicePdf(String invoiceId) => '/invoices/$invoiceId/pdf';
  static String activeRecordExport(String id) => _useAlias ? '/records/$id' : invoiceByPurchase(id);
  static String activeRecordPdf(String id) => _useAlias ? '/records/$id/export' : invoicePdf(id);

  // Notification Endpoints
  static const String notifications = '/users/notifications';
  static String markNotificationRead(String notificationId) =>
      '/notifications/$notificationId/read';
  static String deleteNotification(String notificationId) =>
      '/notifications/$notificationId';

  // Storage Keys
  static const String accessTokenKey = 'access_token';
  static const String refreshTokenKey = 'refresh_token';
  static const String sessionIdKey = 'session_id';
  static const String userIdKey = 'user_id';
  static const String onboardingCompletedKey = 'onboarding_completed';
  static const String introSeenKey = 'intro_seen';
}
