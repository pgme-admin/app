import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:pgme/core/constants/api_constants.dart';
import 'package:pgme/core/services/storage_service.dart';
import 'package:pgme/core/services/session_manager.dart';

class ApiService {
  static final ApiService _instance = ApiService._internal();
  factory ApiService() => _instance;
  ApiService._internal() {
    _initializeDio();
  }

  late Dio _dio;
  final StorageService _storageService = StorageService();
  String? _cachedDeviceId;

  Dio get dio => _dio;

  void _initializeDio() {
    _dio = Dio(
      BaseOptions(
        baseUrl: ApiConstants.baseUrl,
        connectTimeout: const Duration(milliseconds: ApiConstants.connectTimeout),
        receiveTimeout: const Duration(milliseconds: ApiConstants.receiveTimeout),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
      ),
    );

    // Add request interceptor to inject access token and device ID
    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          // Add access token to headers if available
          final token = await _storageService.getAccessToken();
          if (token != null && token.isNotEmpty) {
            options.headers['Authorization'] = 'Bearer $token';
          }

          // Add device ID header for session validation
          final sessionId = await _storageService.getSessionId();
          if (sessionId != null && sessionId.isNotEmpty) {
            // Extract device_id from storage or use a stored device identifier
            // For now, we'll add the session tracking via a custom method
            try {
              final deviceInfo = await _getDeviceId();
              options.headers['x-device-id'] = deviceInfo;
            } catch (e) {
              // Device ID not available, continue without it
            }
          }
          return handler.next(options);
        },
        onError: (error, handler) async {
          // Handle 401 Unauthorized (token expired or session terminated)
          if (error.response?.statusCode == 401) {
            // Check if this is a SESSION_TERMINATED error (logged out from another device)
            final errorCode = _getErrorCodeFromResponse(error.response?.data);

            if (errorCode == 'SESSION_TERMINATED') {
              // Session was terminated from another device - show modal immediately
              SessionManager().markSessionInvalidated();
              await _storageService.clearAll();
              return handler.next(error);
            }

            // Normal token expiration - try to refresh
            final refreshed = await _refreshToken();
            if (refreshed) {
              // Retry the original request
              final options = error.requestOptions;
              final token = await _storageService.getAccessToken();
              options.headers['Authorization'] = 'Bearer $token';

              try {
                final response = await _dio.fetch(options);
                return handler.resolve(response);
              } catch (e) {
                return handler.next(error);
              }
            } else {
              // Refresh failed - mark session as invalidated
              SessionManager().markSessionInvalidated();
              await _storageService.clearAll();
              return handler.next(error);
            }
          }

          // Handle 403 Forbidden (onboarding incomplete)
          if (error.response?.statusCode == 403) {
            final message = _getMessageFromResponse(error.response?.data);
            if (message?.contains('onboarding') ?? false) {
              // Navigation will be handled by the UI layer
            }
          }

          return handler.next(error);
        },
      ),
    );

    // Add logging interceptor for debugging (remove in production)
    _dio.interceptors.add(
      LogInterceptor(
        requestBody: true,
        responseBody: true,
        error: true,
        logPrint: (obj) {
          // Only log in debug mode
          // print(obj);
        },
      ),
    );
  }

  Future<bool> _refreshToken() async {
    try {
      final refreshToken = await _storageService.getRefreshToken();
      if (refreshToken == null || refreshToken.isEmpty) {
        return false;
      }

      final response = await _dio.post(
        ApiConstants.refreshToken,
        data: {'refresh_token': refreshToken},
        options: Options(
          headers: {
            'Authorization': null, // Don't use access token for refresh
          },
        ),
      );

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

  // Error handling helper
  String getErrorMessage(dynamic error) {
    if (error is DioException) {
      switch (error.type) {
        case DioExceptionType.connectionTimeout:
        case DioExceptionType.sendTimeout:
        case DioExceptionType.receiveTimeout:
          return 'Connection timeout. Please check your internet connection.';
        case DioExceptionType.badResponse:
          final statusCode = error.response?.statusCode;
          final message = _getMessageFromResponse(error.response?.data);

          if (statusCode == 400) {
            return message ?? 'Invalid request. Please check your input.';
          } else if (statusCode == 401) {
            return message ?? 'Session expired. Please login again.';
          } else if (statusCode == 403) {
            return message ?? 'Access denied.';
          } else if (statusCode == 404) {
            return 'Resource not found.';
          } else if (statusCode == 500) {
            return 'Server error. Please try again later.';
          }
          return message ?? 'An error occurred. Please try again.';
        case DioExceptionType.cancel:
          return 'Request was cancelled.';
        case DioExceptionType.connectionError:
          return 'No internet connection. Please check your network.';
        default:
          return 'An unexpected error occurred. Please try again.';
      }
    }
    return 'An error occurred. Please try again.';
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
      return {};
    }
  }

  /// Helper to safely extract message from response data
  String? _getMessageFromResponse(dynamic data) {
    if (data == null) return null;
    if (data is String) {
      try {
        final parsed = jsonDecode(data) as Map<String, dynamic>;
        return parsed['message'] as String?;
      } catch (_) {
        return null;
      }
    } else if (data is Map) {
      return data['message'] as String?;
    }
    return null;
  }

  /// Helper to extract error code from response data
  String? _getErrorCodeFromResponse(dynamic data) {
    if (data == null) return null;
    if (data is String) {
      try {
        final parsed = jsonDecode(data) as Map<String, dynamic>;
        return parsed['error_code'] as String?;
      } catch (_) {
        return null;
      }
    } else if (data is Map) {
      return data['error_code'] as String?;
    }
    return null;
  }

  /// Get device ID for session validation
  Future<String> _getDeviceId() async {
    if (_cachedDeviceId != null) {
      return _cachedDeviceId!;
    }

    final deviceInfo = DeviceInfoPlugin();
    String deviceId = 'unknown';

    try {
      if (Platform.isAndroid) {
        final androidInfo = await deviceInfo.androidInfo;
        deviceId = androidInfo.id;
      } else if (Platform.isIOS) {
        final iosInfo = await deviceInfo.iosInfo;
        deviceId = iosInfo.identifierForVendor ?? 'unknown';
      }
    } catch (e) {
      // Use default if device info fetch fails
    }

    _cachedDeviceId = deviceId;
    return deviceId;
  }
}
