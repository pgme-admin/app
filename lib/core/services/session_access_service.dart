import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:pgme/core/constants/api_constants.dart';
import 'package:pgme/core/models/session_access_model.dart';
import 'package:pgme/core/models/gateway_models.dart';
import 'package:pgme/core/services/api_service.dart';
import 'package:pgme/core/services/gateway_service.dart';

class SessionAccessService {
  final ApiService _apiService = ApiService();
  final GatewayService _gatewayService = GatewayService();

  /// Check if user has access to a session
  Future<SessionAccessStatus> checkSessionAccess(String sessionId) async {
    try {
      debugPrint('=== SessionAccessService: Checking session access ===');

      final response = await _apiService.dio.get(
        ApiConstants.sessionAccessStatus(sessionId),
      );

      if (response.statusCode == 200 && response.data['success'] == true) {
        final accessData = response.data['data'] as Map<String, dynamic>;
        final accessStatus = SessionAccessStatus.fromJson(accessData);

        debugPrint('Session access status: hasAccess=${accessStatus.hasAccess}, isFree=${accessStatus.isFree}');
        return accessStatus;
      }

      throw Exception('Failed to check session access');
    } on DioException catch (e) {
      debugPrint('Check session access error: $e');
      throw Exception(_apiService.getErrorMessage(e));
    } catch (e) {
      debugPrint('Unexpected error: $e');
      throw Exception('An unexpected error occurred');
    }
  }

  /// Create order for session access
  Future<SessionAccessResponse> createOrder(String sessionId) async {
    try {
      debugPrint('=== SessionAccessService: Creating session order ===');

      final response = await _apiService.dio.post(
        ApiConstants.activeSessionInitAccess(sessionId),
      );

      if (response.statusCode == 201 && response.data['success'] == true) {
        final orderData = response.data['data'] as Map<String, dynamic>;
        final order = SessionAccessResponse.fromJson(orderData);

        debugPrint('Session order created: ${order.orderId}');
        return order;
      }

      throw Exception('Failed to create session order');
    } on DioException catch (e) {
      debugPrint('Create session order error: $e');
      throw Exception(_apiService.getErrorMessage(e));
    } catch (e) {
      debugPrint('Unexpected error: $e');
      throw Exception('An unexpected error occurred');
    }
  }

  /// Verify session access
  Future<Map<String, dynamic>> verifyAccess({
    required String sessionId,
    required String razorpayOrderId,
    required String razorpayPaymentId,
    required String razorpaySignature,
  }) async {
    try {
      debugPrint('=== SessionAccessService: Verifying session access ===');

      final response = await _apiService.dio.post(
        ApiConstants.activeSessionConfirmAccess(sessionId),
        data: {
          'razorpay_order_id': razorpayOrderId,
          'razorpay_payment_id': razorpayPaymentId,
          'razorpay_signature': razorpaySignature,
        },
      );

      if (response.statusCode == 200 && response.data['success'] == true) {
        final result = response.data['data'] as Map<String, dynamic>;

        debugPrint('Session access verified successfully');
        return result;
      }

      throw Exception('Failed to verify session access');
    } on DioException catch (e) {
      debugPrint('Verify session access error: $e');
      throw Exception(_apiService.getErrorMessage(e));
    } catch (e) {
      debugPrint('Unexpected error: $e');
      throw Exception('An unexpected error occurred');
    }
  }

  /// Join a live session (after access verification)
  Future<Map<String, dynamic>> joinSession(String sessionId) async {
    try {
      debugPrint('=== SessionAccessService: Joining session ===');

      final response = await _apiService.dio.post(
        ApiConstants.sessionJoin(sessionId),
      );

      if (response.statusCode == 200 && response.data['success'] == true) {
        final result = response.data['data'] as Map<String, dynamic>;

        debugPrint('Joined session successfully');
        return result;
      }

      throw Exception('Failed to join session');
    } on DioException catch (e) {
      debugPrint('Join session error: $e');
      throw Exception(_apiService.getErrorMessage(e));
    } catch (e) {
      debugPrint('Unexpected error: $e');
      throw Exception('An unexpected error occurred');
    }
  }

  /// Create test access record (bypasses gateway for testing)
  Future<Map<String, dynamic>> createTestRecord(String sessionId) async {
    try {
      debugPrint('=== SessionAccessService: Creating test access record ===');

      final response = await _apiService.dio.post(
        ApiConstants.activeSessionTestAccess(sessionId),
      );

      if (response.statusCode == 201 && response.data['success'] == true) {
        final result = response.data['data'] as Map<String, dynamic>;

        debugPrint('Test access record created: ${result['purchase_id']}');
        return result;
      }

      throw Exception('Failed to create test access record');
    } on DioException catch (e) {
      debugPrint('Create test access record error: $e');
      throw Exception(_apiService.getErrorMessage(e));
    } catch (e) {
      debugPrint('Unexpected error: $e');
      throw Exception('An unexpected error occurred');
    }
  }

  /// Get user's session access records
  Future<List<SessionAccessModel>> getUserSessionRecords({
    bool? isActive,
    String? paymentStatus,
  }) async {
    try {
      debugPrint('=== SessionAccessService: Getting user session records ===');

      final queryParams = <String, dynamic>{};
      if (isActive != null) queryParams['is_active'] = isActive.toString();
      if (paymentStatus != null) queryParams['payment_status'] = paymentStatus;

      final response = await _apiService.dio.get(
        ApiConstants.activeSessionActivity,
        queryParameters: queryParams.isNotEmpty ? queryParams : null,
      );

      if (response.statusCode == 200 && response.data['success'] == true) {
        final recordsData = response.data['data']['purchases'] as List;
        final records = recordsData
            .map((json) => SessionAccessModel.fromJson(json as Map<String, dynamic>))
            .toList();

        debugPrint('${records.length} session access records retrieved');
        return records;
      }

      throw Exception('Failed to load session access records');
    } on DioException catch (e) {
      debugPrint('Get session access records error: $e');
      throw Exception(_apiService.getErrorMessage(e));
    } catch (e) {
      debugPrint('Unexpected error: $e');
      throw Exception('An unexpected error occurred');
    }
  }

  // ============================================================================
  // ENROLLMENT METHODS
  // ============================================================================

  /// Check enrollment status for a session
  Future<Map<String, dynamic>> checkEnrollmentStatus(String sessionId) async {
    try {
      final response = await _apiService.dio.get(
        ApiConstants.sessionEnrollmentStatus(sessionId),
      );

      if (response.statusCode == 200 && response.data['success'] == true) {
        return response.data['data'] as Map<String, dynamic>;
      }

      throw Exception('Failed to check enrollment status');
    } on DioException catch (e) {
      debugPrint('Check enrollment status error: $e');
      throw Exception(_apiService.getErrorMessage(e));
    }
  }

  /// Enroll in a session (for free sessions)
  Future<Map<String, dynamic>> enrollInSession(String sessionId) async {
    try {
      final response = await _apiService.dio.post(
        ApiConstants.sessionEnroll(sessionId),
      );

      if (response.statusCode == 200 && response.data['success'] == true) {
        return response.data['data'] as Map<String, dynamic>;
      }

      throw Exception('Failed to enroll in session');
    } on DioException catch (e) {
      debugPrint('Enroll in session error: $e');
      throw Exception(_apiService.getErrorMessage(e));
    }
  }

  // ============================================================================
  // GATEWAY METHODS
  // ============================================================================

  /// Create gateway session for session access
  Future<GatewaySession> initSession(
    String sessionId, {
    Map<String, dynamic>? billingAddress,
  }) async {
    return await _gatewayService.initSession(
      endpoint: ApiConstants.activeSessionInitAccess(sessionId),
      data: billingAddress != null ? {'billing_address': billingAddress} : null,
    );
  }

  /// Confirm gateway session for session access
  Future<GatewayVerificationResponse> confirmSession({
    required String sessionId,
    required String paymentSessionId,
    required String paymentId,
    String? signature,
  }) async {
    return await _gatewayService.confirmSession(
      endpoint: ApiConstants.activeSessionConfirmAccess(sessionId),
      paymentSessionId: paymentSessionId,
      paymentId: paymentId,
      signature: signature,
    );
  }
}
