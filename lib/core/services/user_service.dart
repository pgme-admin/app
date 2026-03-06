import 'dart:io';
import 'package:dio/dio.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:pgme/core/constants/api_constants.dart';
import 'package:pgme/core/models/user_model.dart';
import 'package:pgme/core/services/api_service.dart';

class UserService {
  final ApiService _apiService = ApiService();

  /// Get user profile
  Future<UserModel> getProfile() async {
    try {
      final response = await _apiService.dio.get(
        ApiConstants.profile,
      );

      if (response.statusCode == 200 && response.data['success'] == true) {
        return UserModel.fromJson(response.data['data']['user']);
      } else {
        throw Exception(response.data['message'] ?? 'Failed to fetch profile');
      }
    } on DioException catch (e) {
      throw Exception(_apiService.getErrorMessage(e));
    } catch (e) {
      throw Exception('Failed to fetch profile: ${e.toString()}');
    }
  }

  /// Update user profile
  Future<UserModel> updateProfile(Map<String, dynamic> data) async {
    try {
      final response = await _apiService.dio.put(
        ApiConstants.profile,
        data: data,
      );

      if (response.statusCode == 200 && response.data['success'] == true) {
        return UserModel.fromJson(response.data['data']['user']);
      } else {
        throw Exception(response.data['message'] ?? 'Failed to update profile');
      }
    } on DioException catch (e) {
      throw Exception(_apiService.getErrorMessage(e));
    } catch (e) {
      throw Exception('Failed to update profile: ${e.toString()}');
    }
  }

  /// Complete onboarding process
  Future<void> completeOnboarding() async {
    try {
      final response = await _apiService.dio.put(
        ApiConstants.onboardingComplete,
      );

      if (response.statusCode != 200 || response.data['success'] != true) {
        throw Exception(
            response.data['message'] ?? 'Failed to complete onboarding');
      }
    } on DioException catch (e) {
      throw Exception(_apiService.getErrorMessage(e));
    } catch (e) {
      throw Exception('Failed to complete onboarding: ${e.toString()}');
    }
  }

  /// Update subject selection
  Future<void> updateSubjectSelection({
    required String subjectId,
    bool isPrimary = true,
  }) async {
    try {
      final response = await _apiService.dio.put(
        ApiConstants.subjectSelection,
        data: {
          'subject_id': subjectId,
          'is_primary': isPrimary,
        },
      );

      if (response.statusCode != 200 || response.data['success'] != true) {
        throw Exception(
            response.data['message'] ?? 'Failed to update subject selection');
      }
    } on DioException catch (e) {
      throw Exception(_apiService.getErrorMessage(e));
    } catch (e) {
      throw Exception('Failed to update subject selection: ${e.toString()}');
    }
  }

  /// Get available subjects
  Future<List<Map<String, dynamic>>> getSubjects() async {
    try {
      final response = await _apiService.dio.get(
        ApiConstants.subjects,
      );

      if (response.statusCode == 200 && response.data['success'] == true) {
        final subjects = response.data['data']['subjects'] as List;
        return subjects.cast<Map<String, dynamic>>();
      }

      return [];
    } on DioException catch (e) {
      throw Exception(_apiService.getErrorMessage(e));
    } catch (e) {
      throw Exception('Failed to fetch subjects: ${e.toString()}');
    }
  }

  /// Update FCM token for push notifications
  Future<void> updateFCMToken(String fcmToken) async {
    try {
      final deviceId = await _getDeviceId();

      final response = await _apiService.dio.post(
        ApiConstants.fcmToken,
        data: {
          'fcm_token': fcmToken,
          'device_id': deviceId,
        },
      );

      if (response.statusCode != 200 || response.data['success'] != true) {
        throw Exception(
            response.data['message'] ?? 'Failed to update FCM token');
      }
    } on DioException catch (e) {
      throw Exception(_apiService.getErrorMessage(e));
    } catch (e) {
      throw Exception('Failed to update FCM token: ${e.toString()}');
    }
  }

  /// Get device ID (same logic as auth_service)
  Future<String> _getDeviceId() async {
    final deviceInfo = DeviceInfoPlugin();
    try {
      if (Platform.isAndroid) {
        final androidInfo = await deviceInfo.androidInfo;
        return androidInfo.id;
      } else if (Platform.isIOS) {
        final iosInfo = await deviceInfo.iosInfo;
        return iosInfo.identifierForVendor ?? 'unknown';
      }
    } catch (e) {
      // Fallback
    }
    return 'unknown';
  }
}
