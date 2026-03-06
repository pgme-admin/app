import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:pgme/core/constants/api_constants.dart';
import 'package:pgme/core/models/book_request_model.dart';
import 'package:pgme/core/models/gateway_models.dart';
import 'package:pgme/core/services/api_service.dart';
import 'package:pgme/core/services/gateway_service.dart';

class BookRequestService {
  final ApiService _apiService = ApiService();
  final GatewayService _gatewayService = GatewayService();

  /// Create order for book request
  Future<BookRequestResponse> createOrder({
    required List<Map<String, dynamic>> items,
    required String recipientName,
    required String shippingPhone,
    required String shippingAddress,
  }) async {
    try {
      debugPrint('=== BookRequestService: Creating request ===');

      final response = await _apiService.dio.post(
        ApiConstants.activeInitBookRequest,
        data: {
          'items': items,
          'recipient_name': recipientName,
          'shipping_phone': shippingPhone,
          'shipping_address': shippingAddress,
        },
      );

      if (response.statusCode == 201 && response.data['success'] == true) {
        final data = response.data['data'] as Map<String, dynamic>;
        return BookRequestResponse.fromJson(data);
      }

      throw Exception(response.data['message'] ?? 'Failed to create request');
    } on DioException catch (e) {
      debugPrint('DioException creating request: ${e.message}');
      if (e.response?.data != null && e.response?.data['message'] != null) {
        throw Exception(e.response?.data['message']);
      }
      throw Exception('Network error: ${e.message}');
    } catch (e) {
      debugPrint('Error creating request: $e');
      rethrow;
    }
  }

  /// Verify request access
  Future<RequestVerifyResponse> verifyAccess({
    required String razorpayOrderId,
    required String razorpayPaymentId,
    required String razorpaySignature,
  }) async {
    try {
      debugPrint('=== BookRequestService: Verifying access ===');

      final response = await _apiService.dio.post(
        ApiConstants.activeConfirmBookRequest,
        data: {
          'razorpay_order_id': razorpayOrderId,
          'razorpay_payment_id': razorpayPaymentId,
          'razorpay_signature': razorpaySignature,
        },
      );

      if (response.statusCode == 200 && response.data['success'] == true) {
        final data = response.data['data'] as Map<String, dynamic>;
        return RequestVerifyResponse.fromJson(data);
      }

      throw Exception(response.data['message'] ?? 'Access verification failed');
    } on DioException catch (e) {
      debugPrint('DioException verifying access: ${e.message}');
      if (e.response?.data != null && e.response?.data['message'] != null) {
        throw Exception(e.response?.data['message']);
      }
      throw Exception('Access verification failed');
    } catch (e) {
      debugPrint('Error verifying access: $e');
      rethrow;
    }
  }

  /// Create test request (bypasses gateway for testing)
  Future<Map<String, dynamic>> createTestRequest({
    required List<Map<String, dynamic>> items,
    required String recipientName,
    required String shippingPhone,
    required String shippingAddress,
  }) async {
    try {
      debugPrint('=== BookRequestService: Creating test request ===');

      final response = await _apiService.dio.post(
        ApiConstants.testBookOrder,
        data: {
          'items': items,
          'recipient_name': recipientName,
          'shipping_phone': shippingPhone,
          'shipping_address': shippingAddress,
        },
      );

      if (response.statusCode == 201 && response.data['success'] == true) {
        return response.data['data'] as Map<String, dynamic>;
      }

      throw Exception(response.data['message'] ?? 'Failed to create test request');
    } on DioException catch (e) {
      debugPrint('DioException creating test request: ${e.message}');
      if (e.response?.data != null && e.response?.data['message'] != null) {
        throw Exception(e.response?.data['message']);
      }
      throw Exception('Network error: ${e.message}');
    } catch (e) {
      debugPrint('Error creating test request: $e');
      rethrow;
    }
  }

  /// Get user's book requests
  Future<List<BookRequestModel>> getUserRequests({
    String? orderStatus,
    String? paymentStatus,
    int limit = 20,
  }) async {
    try {
      debugPrint('=== BookRequestService: Getting user requests ===');

      final queryParams = <String, dynamic>{'limit': limit};
      if (orderStatus != null) queryParams['order_status'] = orderStatus;
      if (paymentStatus != null) queryParams['payment_status'] = paymentStatus;

      final response = await _apiService.dio.get(
        ApiConstants.activeBookRequests,
        queryParameters: queryParams,
      );

      if (response.statusCode == 200 && response.data['success'] == true) {
        final requestsData = response.data['data']['orders'] as List;
        return requestsData
            .map((json) => BookRequestModel.fromJson(json as Map<String, dynamic>))
            .toList();
      }

      return [];
    } on DioException catch (e) {
      debugPrint('DioException getting requests: ${e.message}');
      if (e.response?.data != null && e.response?.data['message'] != null) {
        throw Exception(e.response?.data['message']);
      }
      throw Exception('Network error: ${e.message}');
    } catch (e) {
      debugPrint('Error getting requests: $e');
      rethrow;
    }
  }

  /// Get request by ID
  Future<BookRequestModel> getRequestById(String orderId) async {
    try {
      debugPrint('=== BookRequestService: Getting request $orderId ===');

      final response = await _apiService.dio.get(
        ApiConstants.activeBookRequestDetails(orderId),
      );

      if (response.statusCode == 200 && response.data['success'] == true) {
        final requestData = response.data['data']['order'] as Map<String, dynamic>;
        return BookRequestModel.fromJson(requestData);
      }

      throw Exception('Failed to load request details');
    } on DioException catch (e) {
      debugPrint('DioException getting request: ${e.message}');
      if (e.response?.data != null && e.response?.data['message'] != null) {
        throw Exception(e.response?.data['message']);
      }
      throw Exception('Network error: ${e.message}');
    } catch (e) {
      debugPrint('Error getting request: $e');
      rethrow;
    }
  }

  /// Cancel a request
  Future<Map<String, dynamic>> cancelRequest(String orderId) async {
    try {
      debugPrint('=== BookRequestService: Cancelling request $orderId ===');

      final response = await _apiService.dio.post(
        ApiConstants.activeCancelBookRequest(orderId),
      );

      if (response.statusCode == 200 && response.data['success'] == true) {
        return response.data['data'] as Map<String, dynamic>;
      }

      throw Exception(response.data['message'] ?? 'Failed to cancel request');
    } on DioException catch (e) {
      debugPrint('DioException cancelling request: ${e.message}');
      if (e.response?.data != null && e.response?.data['message'] != null) {
        throw Exception(e.response?.data['message']);
      }
      throw Exception('Network error: ${e.message}');
    } catch (e) {
      debugPrint('Error cancelling request: $e');
      rethrow;
    }
  }

  // ============================================================================
  // GATEWAY METHODS
  // ============================================================================

  /// Create gateway session for book request
  Future<GatewaySession> initSession({
    required List<Map<String, dynamic>> items,
    required String recipientName,
    required String shippingPhone,
    required String shippingAddress,
    Map<String, dynamic>? billingAddress,
    Map<String, dynamic>? shippingAddressStructured,
  }) async {
    return await _gatewayService.initSession(
      endpoint: ApiConstants.activeInitBookRequest,
      data: {
        'items': items,
        'recipient_name': recipientName,
        'shipping_phone': shippingPhone,
        'shipping_address': shippingAddress,
        if (billingAddress != null) 'billing_address': billingAddress,
        if (shippingAddressStructured != null) 'shipping_address_structured': shippingAddressStructured,
      },
    );
  }

  /// Confirm gateway session for book request
  Future<GatewayVerificationResponse> confirmSession({
    required String paymentSessionId,
    required String paymentId,
    String? signature,
  }) async {
    return await _gatewayService.confirmSession(
      endpoint: ApiConstants.activeConfirmBookRequest,
      paymentSessionId: paymentSessionId,
      paymentId: paymentId,
      signature: signature,
    );
  }
}
