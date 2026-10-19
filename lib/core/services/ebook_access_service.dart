import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:pgme/core/constants/api_constants.dart';
import 'package:pgme/core/models/ebook_access_model.dart';
import 'package:pgme/core/models/gateway_models.dart';
import 'package:pgme/core/services/api_service.dart';

class EbookAccessService {
  final ApiService _apiService = ApiService();

  /// Create a gateway session for ebook access
  Future<GatewaySession> initSession(
    String bookId, {
    Map<String, dynamic>? billingAddress,
    String? couponCode,
    bool? termsAccepted,
  }) async {
    try {
      debugPrint('=== EbookAccessService: Creating gateway session for book $bookId ===');

      final response = await _apiService.dio.post(
        ApiConstants.activeInitUserRead,
        data: {
          'book_id': bookId,
          if (billingAddress != null) 'billing_address': billingAddress,
          if (couponCode != null) 'coupon_code': couponCode,
          if (termsAccepted != null) 'terms_accepted': termsAccepted,
        },
      );

      if (response.statusCode == 201 && response.data['success'] == true) {
        final data = response.data['data'] as Map<String, dynamic>;
        return GatewaySession.fromJson(data);
      }

      throw Exception('Failed to create gateway session');
    } on DioException catch (e) {
      debugPrint('DioException creating ebook gateway session: ${e.message}');
      if (e.response?.data != null && e.response?.data['message'] != null) {
        throw Exception(e.response?.data['message']);
      }
      throw Exception('Network error: ${e.message}');
    } catch (e) {
      debugPrint('Error creating ebook gateway session: $e');
      rethrow;
    }
  }

  /// Confirm ebook access after gateway checkout
  Future<GatewayVerificationResponse> confirmSession({
    required String paymentSessionId,
    required String paymentId,
    String? signature,
  }) async {
    try {
      debugPrint('=== EbookAccessService: Confirming gateway session ===');

      final response = await _apiService.dio.post(
        ApiConstants.activeConfirmUserRead,
        data: {
          'payment_session_id': paymentSessionId,
          'payment_id': paymentId,
          if (signature != null) 'signature': signature,
        },
      );

      if (response.statusCode == 200 && response.data['success'] == true) {
        final data = response.data['data'] as Map<String, dynamic>;
        return GatewayVerificationResponse.fromJson(data);
      }

      throw Exception('Gateway session confirmation failed');
    } on DioException catch (e) {
      debugPrint('DioException confirming ebook gateway session: ${e.message}');
      if (e.response?.data != null && e.response?.data['message'] != null) {
        throw Exception(e.response?.data['message']);
      }
      throw Exception('Network error: ${e.message}');
    } catch (e) {
      debugPrint('Error confirming ebook gateway session: $e');
      rethrow;
    }
  }

  /// Get user's accessible ebooks
  Future<List<EbookAccessModel>> getUserAccessibleEbooks() async {
    try {
      debugPrint('=== EbookAccessService: Getting accessible ebooks ===');

      final response = await _apiService.dio.get(ApiConstants.activeUserReads);

      if (response.statusCode == 200 && response.data['success'] == true) {
        final data = response.data['data'] as Map<String, dynamic>;
        final ebooksList = data['ebooks'] as List;
        return ebooksList
            .map((json) => EbookAccessModel.fromJson(json as Map<String, dynamic>))
            .toList();
      }

      throw Exception('Failed to load accessible ebooks');
    } on DioException catch (e) {
      debugPrint('DioException getting accessible ebooks: ${e.message}');
      if (e.response?.data != null && e.response?.data['message'] != null) {
        throw Exception(e.response?.data['message']);
      }
      throw Exception('Network error: ${e.message}');
    } catch (e) {
      debugPrint('Error getting accessible ebooks: $e');
      rethrow;
    }
  }

  /// Get ebook view URL (presigned URL for reading)
  Future<Map<String, dynamic>> getEbookViewUrl(String bookId) async {
    try {
      debugPrint('=== EbookAccessService: Getting view URL for book $bookId ===');

      final response = await _apiService.dio.get(
        ApiConstants.activeReadViewUrl(bookId),
      );

      if (response.statusCode == 200 && response.data['success'] == true) {
        return response.data['data'] as Map<String, dynamic>;
      }

      throw Exception('Failed to get ebook URL');
    } on DioException catch (e) {
      debugPrint('DioException getting ebook view URL: ${e.message}');
      if (e.response?.data != null && e.response?.data['message'] != null) {
        throw Exception(e.response?.data['message']);
      }
      throw Exception('Network error: ${e.message}');
    } catch (e) {
      debugPrint('Error getting ebook view URL: $e');
      rethrow;
    }
  }
}
