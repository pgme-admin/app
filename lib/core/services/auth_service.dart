import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:dio/dio.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:pgme/core/constants/api_constants.dart';
import 'package:pgme/core/models/auth_response_model.dart';
import 'package:pgme/core/services/api_service.dart';
import 'package:pgme/core/services/storage_service.dart';

class AuthService {
  final ApiService _apiService = ApiService();
  final StorageService _storageService = StorageService();

  /// Verify MSG91 token with backend and get JWT tokens
  Future<AuthResponseModel> verifyMSG91Token(
    String msg91AccessToken,
  ) async {
    try {
      // Get device information
      final deviceInfo = await _getDeviceInfo();

      debugPrint('=== Calling Backend Verify Widget ===');
      debugPrint('URL: ${ApiConstants.baseUrl}${ApiConstants.verifyWidget}');
      debugPrint('MSG91 Token: ${msg91AccessToken.substring(0, min(20, msg91AccessToken.length))}...');
      debugPrint('Device Info: $deviceInfo');

      final response = await _apiService.dio.post(
        ApiConstants.verifyWidget,
        data: {
          'access_token': msg91AccessToken,
          'device_id': deviceInfo['device_id'],
          'device_name': deviceInfo['device_name'],
          'device_type': deviceInfo['device_type'],
        },
      );

      debugPrint('Backend Response Status: ${response.statusCode}');
      debugPrint('Backend Response: ${response.data}');
      debugPrint('Backend Response Type: ${response.data.runtimeType}');

      // Handle case where response.data might be a String instead of Map
      final responseData = _parseResponseData(response.data);

      if (response.statusCode == 200 && responseData['success'] == true) {
        final authData = AuthResponseModel.fromJson(responseData['data'] as Map<String, dynamic>);

        // Store tokens in secure storage
        await _storageService.saveAuthTokens(
          accessToken: authData.accessToken,
          refreshToken: authData.refreshToken,
          sessionId: authData.sessionId,
          userId: authData.user.userId,
          onboardingCompleted: authData.user.onboardingCompleted,
        );

        return authData;
      } else {
        throw Exception(responseData['message'] ?? 'Authentication failed');
      }
    } on DioException catch (e) {
      debugPrint('=== DioException in verifyMSG91Token ===');
      debugPrint('Type: ${e.type}');
      debugPrint('Message: ${e.message}');
      debugPrint('Response status: ${e.response?.statusCode}');
      debugPrint('Response data: ${e.response?.data}');
      throw Exception(_apiService.getErrorMessage(e));
    } catch (e) {
      debugPrint('=== General exception in verifyMSG91Token ===');
      debugPrint('Error: $e');
      debugPrint('Error type: ${e.runtimeType}');
      throw Exception('Authentication failed: ${e.toString()}');
    }
  }

  /// Refresh access token using refresh token
  Future<bool> refreshToken() async {
    try {
      final refreshToken = await _storageService.getRefreshToken();
      if (refreshToken == null) {
        return false;
      }

      final response = await _apiService.dio.post(
        ApiConstants.refreshToken,
        data: {'refresh_token': refreshToken},
      );

      // Handle case where response.data might be a String instead of Map
      final responseData = _parseResponseData(response.data);

      if (response.statusCode == 200 && responseData['success'] == true) {
        final data = responseData['data'] as Map<String, dynamic>;
        await _storageService.saveAccessToken(data['access_token']);
        await _storageService.saveRefreshToken(data['refresh_token']);
        return true;
      }

      return false;
    } catch (e) {
      return false;
    }
  }

  /// Logout user and clear session
  Future<void> logout() async {
    try {
      final sessionId = await _storageService.getSessionId();

      await _apiService.dio.post(
        ApiConstants.logout,
        data: sessionId != null ? {'session_id': sessionId} : null,
      );
    } catch (e) {
      // Ignore errors during logout, still clear local storage
    } finally {
      await _storageService.clearAll();
    }
  }

  /// Get active sessions for the user
  Future<List<Map<String, dynamic>>> getActiveSessions() async {
    try {
      final response = await _apiService.dio.get(
        ApiConstants.activeSessions,
      );

      // Handle case where response.data might be a String instead of Map
      final responseData = _parseResponseData(response.data);

      if (response.statusCode == 200 && responseData['success'] == true) {
        final data = responseData['data'] as Map<String, dynamic>;
        final sessions = data['sessions'] as List;
        return sessions.cast<Map<String, dynamic>>();
      }

      return [];
    } on DioException catch (e) {
      throw Exception(_apiService.getErrorMessage(e));
    } catch (e) {
      throw Exception('Failed to fetch sessions: ${e.toString()}');
    }
  }

  /// Logout a specific device session
  Future<void> logoutDeviceSession(String sessionId) async {
    try {
      await _apiService.dio.delete(
        ApiConstants.deviceSession(sessionId),
      );
    } on DioException catch (e) {
      throw Exception(_apiService.getErrorMessage(e));
    } catch (e) {
      throw Exception('Failed to logout device: ${e.toString()}');
    }
  }

  /// Get device information for session tracking
  Future<Map<String, String>> _getDeviceInfo() async {
    final deviceInfo = DeviceInfoPlugin();
    String deviceId = 'unknown';
    String deviceName = 'Unknown Device';
    String deviceType = 'Unknown';

    try {
      if (Platform.isAndroid) {
        final androidInfo = await deviceInfo.androidInfo;
        deviceId = androidInfo.id;
        deviceName = '${androidInfo.brand} ${androidInfo.model}';
        deviceType = 'Android';
      } else if (Platform.isIOS) {
        final iosInfo = await deviceInfo.iosInfo;
        deviceId = iosInfo.identifierForVendor ?? 'unknown';
        deviceName = '${iosInfo.name} ${iosInfo.model}';
        deviceType = 'iOS';
      }
    } catch (e) {
      // Use defaults if device info fetch fails
    }

    return {
      'device_id': deviceId,
      'device_name': deviceName,
      'device_type': deviceType,
    };
  }

  /// Helper to parse response data that might be String or Map
  Map<String, dynamic> _parseResponseData(dynamic data) {
    if (data is String) {
      return jsonDecode(data) as Map<String, dynamic>;
    } else if (data is Map<String, dynamic>) {
      return data;
    } else if (data is Map) {
      return Map<String, dynamic>.from(data);
    } else {
      throw Exception('Unexpected response format: ${data.runtimeType}');
    }
  }
}
