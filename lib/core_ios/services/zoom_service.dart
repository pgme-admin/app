import 'dart:async';
import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_zoom_meeting_sdk/flutter_zoom_meeting_sdk.dart';
import 'package:flutter_zoom_meeting_sdk/enums/status_meeting_status.dart';
import 'package:flutter_zoom_meeting_sdk/enums/status_zoom_error.dart';
import 'package:flutter_zoom_meeting_sdk/models/zoom_meeting_sdk_request.dart';
import 'package:pgme/core_ios/constants/api_constants.dart';
import 'package:pgme/core_ios/services/api_service.dart';

/// Custom exception types for better error handling
enum ZoomErrorType {
  authenticationFailed,
  joinFailed,
  timeout,
  networkError,
  hostNotJoined,
  meetingEnded,
  unknown,
}

class ZoomJoinException implements Exception {
  final ZoomErrorType type;
  final String message;
  final String? technicalDetails;

  ZoomJoinException({
    required this.type,
    required this.message,
    this.technicalDetails,
  });

  @override
  String toString() => message;
}

/// Response model for the Zoom SDK signature from backend
class ZoomSignatureResponse {
  final String sdkKey;
  final String signature;
  final String meetingNumber;
  final String password;
  final Map<String, dynamic> meetingOptions;

  ZoomSignatureResponse({
    required this.sdkKey,
    required this.signature,
    required this.meetingNumber,
    required this.password,
    this.meetingOptions = const {},
  });

  factory ZoomSignatureResponse.fromJson(Map<String, dynamic> json) {
    return ZoomSignatureResponse(
      sdkKey: json['sdkKey'] as String,
      signature: json['signature'] as String,
      meetingNumber: json['meetingNumber'] as String,
      password: json['password'] as String,
      meetingOptions: json['meetingOptions'] != null
          ? Map<String, dynamic>.from(json['meetingOptions'] as Map)
          : {},
    );
  }
}

class ZoomMeetingService {
  final ApiService _apiService = ApiService();
  final FlutterZoomMeetingSdk _zoomSdk = FlutterZoomMeetingSdk();
  bool _isInitialized = false;

  /// Initialize the Zoom SDK (call once before first use)
  Future<bool> initZoomSDK() async {
    if (_isInitialized) {
      debugPrint('Zoom SDK already initialized, skipping');
      return true;
    }

    try {
      debugPrint('=== ZoomMeetingService: Initializing Zoom SDK ===');

      final result = await _zoomSdk.initZoom();

      if (result.isSuccess) {
        _isInitialized = true;
        debugPrint('Zoom SDK initialized successfully: ${result.message}');
        return true;
      } else {
        debugPrint('Zoom SDK initialization failed: ${result.message}');
        return false;
      }
    } catch (e) {
      debugPrint('Zoom SDK initialization error: $e');
      return false;
    }
  }

  /// Decode the role from a Zoom SDK JWT signature.
  /// JWT structure: header.payload.signature — payload is base64url encoded JSON.
  /// Returns true if role == 1 (host).
  bool _isHostRole(String signature) {
    try {
      final parts = signature.split('.');
      if (parts.length != 3) return false;
      // base64url → base64
      String payload = parts[1].replaceAll('-', '+').replaceAll('_', '/');
      while (payload.length % 4 != 0) payload += '=';
      final decoded = String.fromCharCodes(base64Decode(payload));
      final roleMatch = RegExp(r'"role"\s*:\s*(\d+)').firstMatch(decoded);
      return roleMatch != null && roleMatch.group(1) == '1';
    } catch (_) {
      return false; // default to participant on any decode error
    }
  }

  /// Reset the SDK state so the next call re-initializes from scratch.
  /// Use when the SDK may be in a bad state (e.g. after app backgrounding).
  Future<void> resetSDK() async {
    debugPrint('=== ZoomMeetingService: Resetting SDK ===');
    try {
      await _zoomSdk.unInitZoom();
    } catch (_) {}
    _isInitialized = false;
  }

  /// Fetch Zoom SDK signature (JWT) from backend
  Future<ZoomSignatureResponse> getZoomSignature(String sessionId) async {
    try {
      debugPrint('=== ZoomMeetingService: Getting Zoom signature ===');

      final response = await _apiService.dio.get(
        ApiConstants.sessionZoomSignature(sessionId),
      );

      if (response.statusCode == 200 && response.data['success'] == true) {
        final data = response.data['data'] as Map<String, dynamic>;
        final signatureResponse = ZoomSignatureResponse.fromJson(data);
        debugPrint('Zoom signature obtained for meeting: ${signatureResponse.meetingNumber}');
        return signatureResponse;
      }

      throw Exception('Failed to get Zoom signature');
    } on DioException catch (e) {
      debugPrint('Get Zoom signature error: $e');
      throw Exception(_apiService.getErrorMessage(e));
    }
  }

  /// Join a Zoom meeting in-app using the Meeting SDK
  Future<bool> joinMeeting({
    required String sessionId,
    required String displayName,
  }) async {
    try {
      debugPrint('=== ZoomMeetingService: Joining meeting ===');

      // Ensure SDK is initialized before anything else
      final initialized = await initZoomSDK();
      if (!initialized) {
        throw ZoomJoinException(
          type: ZoomErrorType.authenticationFailed,
          message: 'Failed to initialize Zoom SDK. Please try again.',
        );
      }

      // Get the SDK signature from backend
      final zoomSignature = await getZoomSignature(sessionId);
      debugPrint('Joining meeting: ${zoomSignature.meetingNumber}');

      // Authenticate with SDK using JWT token
      debugPrint('Authenticating with Zoom SDK...');
      final authResult = await _zoomSdk.authZoom(jwtToken: zoomSignature.signature);

      if (!authResult.isSuccess) {
        debugPrint('Zoom SDK authentication failed: ${authResult.message}');
        throw ZoomJoinException(
          type: ZoomErrorType.authenticationFailed,
          message: 'Unable to authenticate with Zoom. Please try again.',
          technicalDetails: authResult.message,
        );
      }

      debugPrint('Zoom SDK auth request sent, waiting for completion...');

      // Wait for the actual authentication to complete via event stream.
      // authZoom() only sends the request — the real result arrives on
      // onAuthenticationReturn. Without this, joinMeeting() fires before
      // the SDK is ready, causing the first-click failure.
      final authEvent = await _zoomSdk.onAuthenticationReturn.first.timeout(
        const Duration(seconds: 10),
        onTimeout: () => throw ZoomJoinException(
          type: ZoomErrorType.authenticationFailed,
          message: 'Zoom authentication timed out. Please try again.',
        ),
      );

      final authStatus = authEvent.params?.statusEnum;
      if (authStatus != StatusZoomError.success) {
        throw ZoomJoinException(
          type: ZoomErrorType.authenticationFailed,
          message: 'Zoom authentication failed. Please try again.',
          technicalDetails: 'Auth status: $authStatus',
        );
      }

      debugPrint('Zoom SDK authentication confirmed via event');

      // Decode role from JWT signature (payload is the middle segment)
      final isHost = _isHostRole(zoomSignature.signature);
      debugPrint('Zoom role: ${isHost ? 'HOST' : 'PARTICIPANT'}');

      // Apply UI restrictions based on role — participants get locked down,
      // hosts get full controls. All done client-side, no backend change needed.
      final meetingConfig = isHost
          ? ZoomMeetingSdkRequest(
              meetingNumber: zoomSignature.meetingNumber,
              password: zoomSignature.password,
              displayName: displayName,
              noInvite: true,
              noDriveMode: true,
              noDialIn: true,
              noDialOut: true,
            )
          : ZoomMeetingSdkRequest(
              meetingNumber: zoomSignature.meetingNumber,
              password: zoomSignature.password,
              displayName: displayName,
              noShare: true,
              noVideo: true,
              noInvite: true,
              noChat: true,
              noDriveMode: true,
              noDialIn: true,
              noDialOut: true,
              noDisconnectAudio: true,
              noRecord: true,
              noReaction: true,
              noParticipantList: true,
              noMore: true,
              muteOnEntry: true,
              videoOffOnEntry: true,
            );

      // Set up status listener with timeout
      final completer = Completer<bool>();
      ZoomErrorType? errorType;
      String? errorMessage;
      late StreamSubscription subscription;

      subscription = _zoomSdk.onMeetingStatusChanged.listen((event) {
        final status = event.params?.statusEnum;
        final statusString = status?.toString() ?? 'unknown';
        debugPrint('Zoom meeting status: $statusString');

        // Check for various failure scenarios
        if (status == StatusMeetingStatus.failed) {
          errorType = ZoomErrorType.joinFailed;
          errorMessage = 'Failed to join the meeting';
          if (!completer.isCompleted) {
            completer.complete(false);
          }
          subscription.cancel();
        } else if (status == StatusMeetingStatus.ended) {
          errorType = ZoomErrorType.meetingEnded;
          errorMessage = 'The meeting has ended';
          if (!completer.isCompleted) {
            completer.complete(false);
          }
          subscription.cancel();
        } else if (status == StatusMeetingStatus.disconnecting) {
          // Only treat as error if we haven't successfully joined yet
          if (!completer.isCompleted) {
            errorType = ZoomErrorType.networkError;
            errorMessage = 'Connection lost before joining';
            completer.complete(false);
          }
          subscription.cancel();
        }
        // Check for "waiting for host" by looking at the status string
        // Zoom SDK may have statuses like "waitingForHost" or similar
        else if (statusString.toLowerCase().contains('waiting') ||
                 statusString.toLowerCase().contains('host')) {
          errorType = ZoomErrorType.hostNotJoined;
          errorMessage = 'Waiting for host to join the meeting';
          // Don't complete yet - keep waiting
          debugPrint('Detected waiting for host scenario');
        }
        else if (status == StatusMeetingStatus.inMeeting) {
          if (!completer.isCompleted) {
            completer.complete(true);
          }
          // Don't cancel subscription - keep listening until meeting ends
        }
      });

      // Join the meeting
      final joinResult = await _zoomSdk.joinMeeting(meetingConfig);
      debugPrint('Join meeting result: ${joinResult.message}');

      if (!joinResult.isSuccess) {
        subscription.cancel();
        if (!completer.isCompleted) {
          completer.complete(false);
        }

        // Check if error message indicates host not joined
        final resultMessage = joinResult.message?.toLowerCase() ?? '';
        if (resultMessage.contains('host') || resultMessage.contains('waiting')) {
          throw ZoomJoinException(
            type: ZoomErrorType.hostNotJoined,
            message: 'The host has not started the meeting yet. Please wait for the host to join.',
            technicalDetails: joinResult.message,
          );
        }

        throw ZoomJoinException(
          type: ZoomErrorType.joinFailed,
          message: 'Unable to join the meeting. Please check your connection and try again.',
          technicalDetails: joinResult.message,
        );
      }

      // Wait for meeting status with timeout
      final result = await completer.future.timeout(
        const Duration(seconds: 30),
        onTimeout: () {
          debugPrint('Zoom meeting join timeout');
          subscription.cancel();
          errorType = ZoomErrorType.timeout;
          errorMessage = 'Connection timeout - meeting join took too long';
          return false;
        },
      );

      if (!result) {
        // Join failed - throw appropriate exception
        throw ZoomJoinException(
          type: errorType ?? ZoomErrorType.unknown,
          message: errorMessage ?? 'Unable to join the meeting',
        );
      }

      return result;
    } on ZoomJoinException {
      // Re-throw our custom exceptions
      rethrow;
    } on DioException catch (e) {
      debugPrint('Network error getting Zoom signature: $e');
      throw ZoomJoinException(
        type: ZoomErrorType.networkError,
        message: 'Network error. Please check your internet connection and try again.',
        technicalDetails: e.toString(),
      );
    } catch (e) {
      debugPrint('Join Zoom meeting error: $e');
      throw ZoomJoinException(
        type: ZoomErrorType.unknown,
        message: 'An unexpected error occurred while joining the meeting.',
        technicalDetails: e.toString(),
      );
    }
  }
}
