import 'package:dio/dio.dart';
import 'package:pgme/core/constants/api_constants.dart';
import 'package:pgme/core/services/api_service.dart';

class ProgressService {
  final ApiService _apiService = ApiService();

  /// Get document progress (last page, total pages, completed)
  Future<Map<String, dynamic>> getDocumentProgress(
      String documentId) async {
    try {
      final response = await _apiService.dio.get(
        ApiConstants.documentProgress(documentId),
      );

      if (response.statusCode == 200 && response.data['success'] == true) {
        return response.data['data'] as Map<String, dynamic>;
      }
      return {};
    } on DioException catch (e) {
      throw Exception(_apiService.getErrorMessage(e));
    } catch (e) {
      throw Exception('Failed to fetch document progress: ${e.toString()}');
    }
  }

  /// Update document progress (saves current page number)
  Future<Map<String, dynamic>> updateDocumentProgress({
    required String documentId,
    required int pageNumber,
  }) async {
    try {
      final response = await _apiService.dio.post(
        ApiConstants.documentProgress(documentId),
        data: {'page_number': pageNumber},
      );

      if (response.statusCode == 200 && response.data['success'] == true) {
        return response.data['data'] as Map<String, dynamic>;
      }
      throw Exception(
          response.data['message'] ?? 'Failed to update document progress');
    } on DioException catch (e) {
      throw Exception(_apiService.getErrorMessage(e));
    } catch (e) {
      throw Exception('Failed to update document progress: ${e.toString()}');
    }
  }
}
