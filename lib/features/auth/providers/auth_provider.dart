import 'dart:async';

import 'package:flutter/material.dart';
import 'package:sendotp_flutter_sdk/sendotp_flutter_sdk.dart';
import 'package:pgme/core/constants/api_constants.dart';
import 'package:pgme/core/models/user_model.dart';
import 'package:pgme/core/services/auth_service.dart';
import 'package:pgme/core/services/user_service.dart';
import 'package:pgme/core/services/storage_service.dart';
import 'package:pgme/core/services/push_notification_service.dart';
import 'package:pgme/core/services/session_manager.dart';

class AuthProvider with ChangeNotifier {
  final AuthService _authService = AuthService();
  final UserService _userService = UserService();
  final StorageService _storageService = StorageService();

  UserModel? _user;
  bool _isAuthenticated = false;
  bool _onboardingCompleted = false;
  bool _isInitialized = false;
  String? _msg91ReqId; // Store MSG91 request ID for OTP verification
  List<Map<String, dynamic>> _activeSessions = [];
  bool _hasMultipleSessions = false;
  String? _currentSessionId;

  UserModel? get user => _user;
  bool get isAuthenticated => _isAuthenticated;
  bool get onboardingCompleted => _onboardingCompleted;
  bool get isInitialized => _isInitialized;
  String? get msg91ReqId => _msg91ReqId;
  List<Map<String, dynamic>> get activeSessions => _activeSessions;
  bool get hasMultipleSessions => _hasMultipleSessions;
  String? get currentSessionId => _currentSessionId;

  AuthProvider() {
    _initializeMSG91();
    // Don't auto-check auth status - it causes rebuilds during screen initialization
    // Call checkAuthStatus() manually when needed (e.g., on splash screen)
  }

  /// Initialize MSG91 Widget
  void _initializeMSG91() {
    try {
      debugPrint('=== Initializing MSG91 Widget ===');
      debugPrint('Widget ID: ${ApiConstants.msg91WidgetId}');
      debugPrint('Auth Token: ${ApiConstants.msg91AuthToken.substring(0, 10)}...');

      OTPWidget.initializeWidget(
        ApiConstants.msg91WidgetId,
        ApiConstants.msg91AuthToken,
      );

      debugPrint('✓ MSG91 Widget initialized successfully');
    } catch (e, stackTrace) {
      debugPrint('✗ MSG91 initialization error: $e');
      debugPrint('Stack trace: $stackTrace');
    }
  }

  /// Check authentication status - call this manually when needed (e.g., splash screen)
  Future<void> checkAuthStatus() async {
    try {
      final isAuth = await _storageService.isAuthenticated();
      if (isAuth) {
        // Try to fetch user profile
        _user = await _userService.getProfile();
        _isAuthenticated = true;
        _onboardingCompleted = _user!.onboardingCompleted;

        // Get current session ID from storage
        _currentSessionId = await _storageService.getSessionId();

        // Re-register FCM token on every app startup (critical for
        // notifications). Fire-and-forget with a timeout — never `await` this on
        // the startup path: FCM token fetch can hang on devices with unhealthy
        // Google Play Services and would otherwise block the splash.
        unawaited(
          PushNotificationService()
              .registerToken()
              .timeout(
                const Duration(seconds: 8),
                onTimeout: () =>
                    debugPrint('FCM token registration timed out — continuing'),
              )
              .catchError(
                (e) => debugPrint('FCM token registration failed: $e'),
              ),
        );

        // Check for multiple active sessions
        try {
          _activeSessions = await _authService.getActiveSessions();
          // Filter out current session and only count OTHER ACTIVE devices
          final otherSessions = _activeSessions.where(
            (s) => s['session_id'] != _currentSessionId &&
                   s['is_active'] == true,
          ).toList();
          _hasMultipleSessions = otherSessions.isNotEmpty;
          debugPrint('Auth check: Active sessions: ${_activeSessions.length}, Other active devices: ${otherSessions.length}');
        } catch (e) {
          debugPrint('Failed to check sessions during auth check: $e');
          _hasMultipleSessions = false;
        }
      }
    } catch (e) {
      // If profile fetch fails, clear tokens
      debugPrint('Auth check failed: $e');
      await _storageService.clearAll();
      _isAuthenticated = false;
      _onboardingCompleted = false;
      _hasMultipleSessions = false;
    } finally {
      _isInitialized = true;
      notifyListeners();
    }
  }

  /// Send OTP using MSG91
  Future<bool> sendOTP(String phoneNumber) async {
    try {
      debugPrint('=== Sending OTP via MSG91 ===');
      debugPrint('Phone number: $phoneNumber');

      final response = await OTPWidget.sendOTP({
        'identifier': phoneNumber,
      });

      debugPrint('MSG91 Response: $response');
      debugPrint('Response type: ${response?['type']}');
      debugPrint('Response message: ${response?['message']}');

      if (response != null && response['type'] == 'success') {
        // MSG91 returns request ID in the 'message' field for successful OTP send
        _msg91ReqId = response['message'] as String?;
        debugPrint('✓ OTP sent successfully. Request ID: $_msg91ReqId');
        notifyListeners();
        return true;
      } else {
        final errorMsg = response?['message'] ?? 'Failed to send OTP';
        debugPrint('✗ OTP sending failed: $errorMsg');
        throw Exception(errorMsg);
      }
    } catch (e, stackTrace) {
      debugPrint('✗ Send OTP error: $e');
      debugPrint('Stack trace: $stackTrace');
      throw Exception('Failed to send OTP: ${e.toString()}');
    }
  }

  /// Verify OTP with MSG91 and authenticate with backend
  Future<bool> verifyOTP(String otp) async {
    try {
      if (_msg91ReqId == null) {
        throw Exception('No request ID found. Please request OTP first.');
      }

      // Step 1: Verify OTP with MSG91
      debugPrint('=== Verifying OTP with MSG91 ===');
      debugPrint('Request ID: $_msg91ReqId');
      debugPrint('OTP: $otp');

      final msg91Response = await OTPWidget.verifyOTP({
        'reqId': _msg91ReqId!,
        'otp': otp,
      });

      debugPrint('MSG91 Verify Response: $msg91Response');
      debugPrint('Response type: ${msg91Response?['type']}');
      debugPrint('Response message: ${msg91Response?['message']}');
      debugPrint('Response data: ${msg91Response?['data']}');

      if (msg91Response == null || msg91Response['type'] != 'success') {
        throw Exception(msg91Response?['message'] ?? 'Invalid OTP');
      }

      // Step 2: Get MSG91 access token (it's in the 'message' field, not 'data')
      final msg91AccessToken = msg91Response['message'] as String?;
      debugPrint('MSG91 Access Token: $msg91AccessToken');

      if (msg91AccessToken == null || msg91AccessToken.isEmpty) {
        throw Exception('MSG91 access token not received');
      }

      // Step 3: Verify with backend and get JWT tokens
      final authResponse = await _authService.verifyMSG91Token(
        msg91AccessToken,
      );

      // Step 4: Update provider state
      _user = authResponse.user;
      _isAuthenticated = true;
      _onboardingCompleted = authResponse.user.onboardingCompleted;
      _currentSessionId = authResponse.sessionId;

      // Logout (PushNotificationService.cleanup) switched the push listeners
      // off and only the splash switches them on, so after logging out and
      // back in without restarting, in-app banners and notification taps did
      // nothing. No-op when they are already on. Bounded like the splash:
      // FCM calls can hang on devices with unhealthy Play Services.
      unawaited(PushNotificationService()
          .initialize()
          .timeout(const Duration(seconds: 8), onTimeout: () {})
          .catchError((Object e) => debugPrint('Push init after login failed: $e')));

      // Step 5: Register FCM token after successful authentication (await to ensure delivery)
      await PushNotificationService().registerToken();

      // Step 6: Check for other active sessions (using backend flag)
      _hasMultipleSessions = authResponse.hasOtherActiveSessions;

      // If there are multiple sessions, fetch the list of sessions
      if (_hasMultipleSessions) {
        try {
          _activeSessions = await _authService.getActiveSessions();
          debugPrint('Multiple sessions detected: ${_activeSessions.length} total sessions');
        } catch (e) {
          debugPrint('Failed to fetch active sessions: $e');
          _activeSessions = [];
        }
      }

      notifyListeners();

      return true;
    } catch (e) {
      debugPrint('Verify OTP error: $e');
      throw Exception(e.toString().replaceAll('Exception: ', ''));
    }
  }

  /// Update user profile
  Future<void> updateProfile({
    required String name,
    required String email,
    String? dateOfBirth,
    String? gender,
    String? address,
    String? ugCollege,
    String? pgCollege,
    String? affiliatedOrganisation,
    String? currentDesignation,
  }) async {
    try {
      // Only include fields that have actual values to avoid
      // backend validation errors on empty strings
      final data = <String, dynamic>{};
      if (name.trim().isNotEmpty) data['name'] = name.trim();
      if (email.trim().isNotEmpty) data['email'] = email.trim();
      if (dateOfBirth != null && dateOfBirth.isNotEmpty) {
        data['date_of_birth'] = dateOfBirth;
      }
      if (gender != null && gender.isNotEmpty) {
        data['gender'] = gender.toLowerCase();
      }
      if (address != null && address.isNotEmpty) {
        data['address'] = address.trim();
      }
      if (ugCollege != null && ugCollege.isNotEmpty) {
        data['ug_college'] = ugCollege.trim();
      }
      if (pgCollege != null && pgCollege.isNotEmpty) {
        data['pg_college'] = pgCollege.trim();
      }
      if (affiliatedOrganisation != null && affiliatedOrganisation.isNotEmpty) {
        data['affiliated_organisation'] = affiliatedOrganisation.trim();
      }
      if (currentDesignation != null && currentDesignation.isNotEmpty) {
        data['current_designation'] = currentDesignation.trim();
      }

      final updatedUser = await _userService.updateProfile(data);

      // Complete onboarding after profile update
      await _userService.completeOnboarding();

      // Update local state
      _user = updatedUser.copyWith(onboardingCompleted: true);
      _onboardingCompleted = true;
      await _storageService.saveOnboardingStatus(true);

      notifyListeners();
    } catch (e) {
      debugPrint('Update profile error: $e');
      throw Exception(e.toString().replaceAll('Exception: ', ''));
    }
  }

  /// Logout user
  Future<void> logout() async {
    try {
      await _authService.logout();
    } catch (e) {
      debugPrint('Logout error: $e');
    } finally {
      await PushNotificationService().cleanup();
      await _storageService.clearAll();
      _user = null;
      _isAuthenticated = false;
      _onboardingCompleted = false;
      _msg91ReqId = null;
      _activeSessions = [];
      _hasMultipleSessions = false;
      _currentSessionId = null;
      notifyListeners();
    }
  }

  /// Retry OTP via different channel
  Future<bool> retryOTP({int? channel}) async {
    try {
      if (_msg91ReqId == null) {
        throw Exception('No request ID found. Please request OTP first.');
      }

      final response = await OTPWidget.retryOTP({
        'reqId': _msg91ReqId!,
        if (channel != null) 'retryChannel': channel,
      });

      if (response != null && response['type'] == 'success') {
        return true;
      } else {
        throw Exception(response?['message'] ?? 'Failed to retry OTP');
      }
    } catch (e) {
      debugPrint('Retry OTP error: $e');
      throw Exception('Failed to retry OTP: ${e.toString()}');
    }
  }

  /// Get active sessions
  Future<List<Map<String, dynamic>>> getActiveSessions() async {
    try {
      return await _authService.getActiveSessions();
    } catch (e) {
      debugPrint('Get sessions error: $e');
      throw Exception(e.toString().replaceAll('Exception: ', ''));
    }
  }

  /// Logout specific device session
  Future<void> logoutDeviceSession(String sessionId) async {
    try {
      await _authService.logoutDeviceSession(sessionId);
      // Remove from local list
      _activeSessions.removeWhere((s) => s['session_id'] == sessionId);
      // Recheck if multiple ACTIVE sessions still exist
      final otherSessions = _activeSessions.where(
        (s) => s['session_id'] != _currentSessionId &&
               s['is_active'] == true,
      ).toList();
      _hasMultipleSessions = otherSessions.isNotEmpty;
      // Re-register FCM token so backend associates it with THIS session only
      await PushNotificationService().registerToken();
      notifyListeners();
    } catch (e) {
      debugPrint('Logout device error: $e');
      throw Exception(e.toString().replaceAll('Exception: ', ''));
    }
  }

  /// Refresh active sessions list
  Future<void> refreshActiveSessions() async {
    try {
      _activeSessions = await _authService.getActiveSessions();
      final otherSessions = _activeSessions.where(
        (s) => s['session_id'] != _currentSessionId &&
               s['is_active'] == true,
      ).toList();
      _hasMultipleSessions = otherSessions.isNotEmpty;
      notifyListeners();
    } catch (e) {
      debugPrint('Refresh sessions error: $e');
    }
  }

  /// Clear multiple sessions flag (after user acknowledges)
  void clearMultipleSessionsFlag() {
    _hasMultipleSessions = false;
    notifyListeners();
  }

  /// Check if current session is still valid
  /// Returns true if valid, false if session was invalidated
  Future<bool> checkSessionValidity() async {
    try {
      // Try to fetch user profile - if session is invalid, this will fail with 401
      await _userService.getProfile();
      return true;
    } catch (e) {
      debugPrint('Session validity check failed: $e');
      // If we get here, session might be invalid
      // The API interceptor will handle 401 and clear tokens
      return false;
    }
  }

  /// Refresh user profile from server and notify listeners
  Future<void> refreshUser() async {
    try {
      _user = await _userService.getProfile();
      notifyListeners();
    } catch (e) {
      debugPrint('Refresh user error: $e');
    }
  }

  /// Check if session was invalidated (logged out from another device)
  bool get isSessionInvalidated => SessionManager().isSessionInvalidated;

  /// Handle logout after session invalidation modal is dismissed
  Future<void> handleSessionInvalidationLogout() async {
    try {
      // Clear the session invalidation flag
      SessionManager().clearSessionInvalidation();

      // Clear local state and storage
      await PushNotificationService().cleanup();
      await _storageService.clearAll();
      _user = null;
      _isAuthenticated = false;
      _onboardingCompleted = false;
      _msg91ReqId = null;
      _activeSessions = [];
      _hasMultipleSessions = false;
      _currentSessionId = null;
      notifyListeners();
    } catch (e) {
      debugPrint('Session invalidation logout error: $e');
    }
  }
}
