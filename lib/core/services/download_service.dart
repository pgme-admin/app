import 'dart:io';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pgme/core/constants/api_constants.dart';
import 'package:pgme/core/services/api_service.dart';

class DownloadService {
  static final DownloadService _instance = DownloadService._internal();
  factory DownloadService() => _instance;
  DownloadService._internal();

  final ApiService _apiService = ApiService();

  /// Get the persistent downloads directory
  Future<Directory> _getDownloadsDir() async {
    final appDir = await getApplicationDocumentsDirectory();
    final downloadsDir = Directory('${appDir.path}/pgme_downloads');
    if (!await downloadsDir.exists()) {
      await downloadsDir.create(recursive: true);
    }
    // Create .nomedia file to hide from device media scanner / file browser
    final nomediaFile = File('${downloadsDir.path}/.nomedia');
    if (!await nomediaFile.exists()) {
      await nomediaFile.create();
    }
    return downloadsDir;
  }

  /// Get video download URL from backend
  Future<Map<String, dynamic>> getVideoDownloadUrl(String videoId) async {
    try {
      final response = await _apiService.dio.get(
        ApiConstants.videoDownloadUrl(videoId),
      );

      if (response.statusCode == 200 && response.data['success'] == true) {
        return response.data['data'] as Map<String, dynamic>;
      }
      throw Exception(
          response.data['message'] ?? 'Failed to get download URL');
    } on DioException catch (e) {
      throw Exception(_apiService.getErrorMessage(e));
    } catch (e) {
      throw Exception('Failed to get video download URL: ${e.toString()}');
    }
  }

  /// Download a file with progress tracking and optional cancellation
  Future<String> downloadFile({
    required String url,
    required String fileName,
    required Function(double) onProgress,
    CancelToken? cancelToken,
  }) async {
    final dir = await _getDownloadsDir();
    final filePath = '${dir.path}/$fileName';

    // Use a separate Dio instance without base URL for direct downloads
    final downloadDio = Dio();
    downloadDio.options.receiveTimeout = const Duration(minutes: 30);

    // Download to a temporary name and rename only once complete. Writing
    // straight to the final name left a truncated file behind when the app
    // was killed mid-download, and that file then counted as "downloaded"
    // (and failed to open) for good.
    final partPath = '$filePath.part';
    final partFile = File(partPath);
    try {
      await downloadDio.download(
        url,
        partPath,
        cancelToken: cancelToken,
        onReceiveProgress: (received, total) {
          if (total > 0) {
            onProgress(received / total);
          }
        },
      );
      final finalFile = File(filePath);
      if (await finalFile.exists()) await finalFile.delete();
      await partFile.rename(filePath);
    } catch (_) {
      if (await partFile.exists()) {
        try {
          await partFile.delete();
        } catch (_) {/* best-effort */}
      }
      rethrow;
    }

    return filePath;
  }

  /// Check if a file is already downloaded
  Future<bool> isDownloaded(String fileName) async {
    final dir = await _getDownloadsDir();
    final file = File('${dir.path}/$fileName');
    return file.exists();
  }

  /// Get path of a downloaded file (null if not downloaded)
  Future<String?> getDownloadedPath(String fileName) async {
    final dir = await _getDownloadsDir();
    final file = File('${dir.path}/$fileName');
    if (await file.exists()) {
      return file.path;
    }
    return null;
  }

  /// Delete a downloaded file
  Future<void> deleteDownload(String fileName) async {
    final dir = await _getDownloadsDir();
    final file = File('${dir.path}/$fileName');
    if (await file.exists()) {
      await file.delete();
    }
  }
}
