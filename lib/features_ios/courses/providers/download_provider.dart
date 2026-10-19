import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pgme/core_ios/models/offline_video_model.dart';
import 'package:pgme/core_ios/services/download_service.dart';
import 'package:pgme/core_ios/services/download_notification_service.dart';
import 'package:pgme/core_ios/services/offline_storage_service.dart';
import 'package:pgme/core_ios/services/storage_helper.dart';

/// Holds metadata needed to start/retry a download
class DownloadParams {
  final String videoId;
  final String title;
  final String? thumbnailUrl;
  final String facultyName;
  final int durationSeconds;
  final String? moduleName;
  final String? seriesName;

  DownloadParams({
    required this.videoId,
    required this.title,
    this.thumbnailUrl,
    this.facultyName = '',
    this.durationSeconds = 0,
    this.moduleName,
    this.seriesName,
  });

  Map<String, dynamic> toJson() => {
    'videoId': videoId,
    'title': title,
    'thumbnailUrl': thumbnailUrl,
    'facultyName': facultyName,
    'durationSeconds': durationSeconds,
    'moduleName': moduleName,
    'seriesName': seriesName,
  };

  factory DownloadParams.fromJson(Map<String, dynamic> json) => DownloadParams(
    videoId: json['videoId'] as String,
    title: json['title'] as String,
    thumbnailUrl: json['thumbnailUrl'] as String?,
    facultyName: json['facultyName'] as String? ?? '',
    durationSeconds: (json['durationSeconds'] as num?)?.toInt() ?? 0,
    moduleName: json['moduleName'] as String?,
    seriesName: json['seriesName'] as String?,
  );
}

/// Info about a download failure for UI callbacks
class DownloadFailureInfo {
  final String videoId;
  final String title;
  final String errorMessage;
  DownloadFailureInfo({required this.videoId, required this.title, required this.errorMessage});
}

class DownloadProvider with ChangeNotifier, WidgetsBindingObserver {
  final DownloadService _downloadService = DownloadService();
  final OfflineStorageService _offlineStorage = OfflineStorageService();
  final DownloadNotificationService _notificationService =
      DownloadNotificationService();

  static const String _pendingParamsKey = 'pgme_pending_download_params';

  // State
  List<OfflineVideoModel> _downloadedVideos = [];
  final Map<String, double> _activeDownloads = {}; // videoId -> progress 0.0..1.0
  final Map<String, String> _failedDownloads = {}; // videoId -> error message
  final Map<String, DownloadParams> _downloadParams = {}; // for retry
  // Kept for UI API compatibility — the OS-managed downloader no longer
  // produces "background-paused" states the way Dio did, so this stays empty.
  final Set<String> _backgroundPaused = {};
  double _totalStorageUsedMb = 0;
  bool _isLoaded = false;
  bool _isInitializing = false;
  bool _lifecycleObserverAdded = false;

  /// Callback invoked when a download fails — set by the UI to show retry dialog
  void Function(DownloadFailureInfo failure)? onDownloadFailed;

  /// Callback invoked when storage is too low to start a download.
  /// The parameter is a human-readable string of the free space (e.g. "120 MB").
  void Function(String freeSpace)? onStorageFull;

  // Getters
  List<OfflineVideoModel> get downloadedVideos => _downloadedVideos;
  Map<String, double> get activeDownloads => Map.unmodifiable(_activeDownloads);
  Map<String, String> get failedDownloads => Map.unmodifiable(_failedDownloads);
  double get totalStorageUsedMb => _totalStorageUsedMb;
  bool get isLoaded => _isLoaded;
  int get downloadedCount => _downloadedVideos.length;
  bool get hasActiveDownloads => _activeDownloads.isNotEmpty;
  bool get hasPausedDownloads => _backgroundPaused.isNotEmpty;

  String get formattedTotalStorage {
    if (_totalStorageUsedMb >= 1024) {
      return '${(_totalStorageUsedMb / 1024).toStringAsFixed(1)} GB';
    }
    return '${_totalStorageUsedMb.toStringAsFixed(1)} MB';
  }

  @override
  void dispose() {
    if (_lifecycleObserverAdded) {
      WidgetsBinding.instance.removeObserver(this);
    }
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // Auto-resume background-paused downloads
      if (_backgroundPaused.isNotEmpty) {
        _resumeBackgroundPausedDownloads();
      }
      // Also check for persisted pending downloads (survived app restart)
      _resumePersistedPendingDownloads();
    }
  }

  void _resumeBackgroundPausedDownloads() {
    final toResume = List<String>.from(_backgroundPaused);
    _backgroundPaused.clear();
    debugPrint('DownloadProvider: Auto-resuming ${toResume.length} paused download(s) after foreground');
    for (final videoId in toResume) {
      retryDownload(videoId);
    }
  }

  /// Resume downloads that were persisted before app was killed
  Future<void> _resumePersistedPendingDownloads() async {
    if (_downloadParams.isNotEmpty) return; // already have in-memory params
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_pendingParamsKey);
      if (raw == null || raw.isEmpty) return;

      final Map<String, dynamic> paramsMap = jsonDecode(raw) as Map<String, dynamic>;
      if (paramsMap.isEmpty) return;

      debugPrint('DownloadProvider: Found ${paramsMap.length} persisted pending download(s)');
      for (final entry in paramsMap.entries) {
        final params = DownloadParams.fromJson(entry.value as Map<String, dynamic>);
        // Only resume if not already downloaded or actively downloading
        if (!isDownloaded(params.videoId) && !isDownloading(params.videoId)) {
          _downloadParams[params.videoId] = params;
          _failedDownloads[params.videoId] = 'Interrupted — tap to retry';
        }
      }
      // Clear persisted params now that we've loaded them into memory
      await prefs.remove(_pendingParamsKey);
      if (_failedDownloads.isNotEmpty) {
        notifyListeners();
      }
    } catch (e) {
      debugPrint('DownloadProvider: Failed to restore pending downloads - $e');
    }
  }

  /// Persist current download params so they survive app restart
  Future<void> _persistPendingParams() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (_downloadParams.isEmpty) {
        await prefs.remove(_pendingParamsKey);
        return;
      }
      final map = <String, dynamic>{};
      for (final entry in _downloadParams.entries) {
        map[entry.key] = entry.value.toJson();
      }
      await prefs.setString(_pendingParamsKey, jsonEncode(map));
    } catch (e) {
      debugPrint('DownloadProvider: Failed to persist pending params - $e');
    }
  }

  /// Initialize: load persisted metadata and verify files still exist
  Future<void> loadDownloads() async {
    if (_isLoaded || _isInitializing) return;
    _isInitializing = true;

    // Register lifecycle observer so we can auto-resume background-paused downloads
    if (!_lifecycleObserverAdded) {
      WidgetsBinding.instance.addObserver(this);
      _lifecycleObserverAdded = true;
    }

    try {
      debugPrint('DownloadProvider: Loading downloads');
      await _notificationService.initialize();
      _downloadedVideos = await _offlineStorage.getOfflineVideos();

      // Verify files still exist on disk (user might have cleared storage)
      final toRemove = <String>[];
      for (final video in _downloadedVideos) {
        final exists = await _downloadService.isDownloaded(video.fileName);
        if (!exists) {
          toRemove.add(video.videoId);
        }
      }
      for (final videoId in toRemove) {
        await _offlineStorage.removeOfflineVideo(videoId);
        _downloadedVideos.removeWhere((v) => v.videoId == videoId);
      }

      // Restore any pending downloads from a previous session
      await _resumePersistedPendingDownloads();

      _totalStorageUsedMb = await _offlineStorage.getTotalStorageUsedMb();
      _isLoaded = true;
      notifyListeners();
      debugPrint(
          'DownloadProvider: Loaded ${_downloadedVideos.length} videos, $formattedTotalStorage used');
    } finally {
      _isInitializing = false;
    }
  }

  /// Check if a video is downloaded (persistent check)
  bool isDownloaded(String videoId) {
    return _downloadedVideos.any((v) => v.videoId == videoId);
  }

  /// Check if a video is currently downloading
  bool isDownloading(String videoId) {
    return _activeDownloads.containsKey(videoId);
  }

  /// Check if a video download failed (real failure, not background pause)
  bool hasFailed(String videoId) {
    return _failedDownloads.containsKey(videoId) && !_backgroundPaused.contains(videoId);
  }

  /// Check if a video download was paused because the app was backgrounded
  bool isPaused(String videoId) {
    return _backgroundPaused.contains(videoId);
  }

  /// Get failure error message
  String? getFailureMessage(String videoId) {
    return _failedDownloads[videoId];
  }

  /// Get download progress for a video (null if not downloading)
  double? getProgress(String videoId) {
    return _activeDownloads[videoId];
  }

  /// Get offline metadata for a video
  OfflineVideoModel? getOfflineVideo(String videoId) {
    try {
      return _downloadedVideos.firstWhere((v) => v.videoId == videoId);
    } catch (_) {
      return null;
    }
  }

  /// Get the title for a video that is downloading or failed
  String? getActiveDownloadTitle(String videoId) {
    return _downloadParams[videoId]?.title;
  }

  /// Start downloading a video.
  /// Does NOT throw on failure — instead sets error state in [failedDownloads]
  /// and invokes [onDownloadFailed] callback so the UI can show a retry dialog.
  Future<void> startDownload({
    required String videoId,
    required String title,
    String? thumbnailUrl,
    String facultyName = '',
    int durationSeconds = 0,
    String? moduleName,
    String? seriesName,
  }) async {
    if (_activeDownloads.containsKey(videoId) || isDownloaded(videoId)) return;

    // --- Storage guard ---
    final hasSpace = await StorageHelper.hasEnoughSpace();
    if (!hasSpace) {
      final freeMb = await StorageHelper.getFreeDiskSpaceMB();
      final freeStr = StorageHelper.formatMb(freeMb);
      debugPrint('DownloadProvider: Not enough storage ($freeStr free)');
      _failedDownloads[videoId] = 'Not enough storage';
      notifyListeners();
      onStorageFull?.call(freeStr);
      return;
    }

    // Store params for potential retry
    final params = DownloadParams(
      videoId: videoId,
      title: title,
      thumbnailUrl: thumbnailUrl,
      facultyName: facultyName,
      durationSeconds: durationSeconds,
      moduleName: moduleName,
      seriesName: seriesName,
    );
    _downloadParams[videoId] = params;

    // Persist params so they survive app restart
    _persistPendingParams();

    // Clear any previous failure
    _failedDownloads.remove(videoId);
    _backgroundPaused.remove(videoId);

    debugPrint('DownloadProvider: Starting download for $videoId');
    _activeDownloads[videoId] = 0.0;
    notifyListeners();

    final fileName = 'video_$videoId.mp4';

    try {
      // 1. Get signed download URL from backend
      final data = await _downloadService.getVideoDownloadUrl(videoId);
      final url = data['download_url'] as String;

      // Extract metadata from API response (backend now provides these)
      final apiThumbnail = data['thumbnail_url'] as String?;
      final apiDuration =
          (data['duration_seconds'] as num?)?.toInt() ?? durationSeconds;

      // 2. Hand off to OS-managed background downloader (URLSession on iOS).
      // This survives app backgrounding, screen-off, and (mostly) app kill.
      // Resume on retry works on networks/CDNs that honor HTTP Range (S3, Cloudinary do).
      // The plugin shows its own iOS background transfer indicator.
      final result = await _downloadService.downloadVideoFile(
        url: url,
        videoId: videoId,
        fileName: fileName,
        title: title,
        onProgress: (progress) {
          _activeDownloads[videoId] = progress;
          notifyListeners();
        },
      );

      if (result.canceled) {
        debugPrint('DownloadProvider: Download cancelled for $videoId');
        _activeDownloads.remove(videoId);
        _downloadParams.remove(videoId);
        _persistPendingParams();
        notifyListeners();
        await _downloadService.deleteDownload(fileName);
        return;
      }

      if (!result.success) {
        final errorMsg = result.errorMessage ?? 'Download failed';
        _activeDownloads.remove(videoId);
        _failedDownloads[videoId] = errorMsg;
        notifyListeners();
        debugPrint('DownloadProvider: Download failed for $videoId: $errorMsg');
        await _downloadService.deleteDownload(fileName);
        onDownloadFailed?.call(DownloadFailureInfo(
          videoId: videoId,
          title: title,
          errorMessage: errorMsg,
        ));
        return;
      }

      // 3. Success — persist metadata
      final filePath = result.filePath!;
      final fileOnDisk = File(filePath);
      final fileSizeBytes = await fileOnDisk.length();
      final actualFileSizeMb = fileSizeBytes / (1024 * 1024);

      final offlineVideo = OfflineVideoModel(
        videoId: videoId,
        title: title,
        thumbnailUrl: apiThumbnail ?? thumbnailUrl,
        facultyName: facultyName,
        durationSeconds: apiDuration,
        fileSizeMb: actualFileSizeMb,
        downloadedAt: DateTime.now(),
        filePath: filePath,
        moduleName: moduleName,
        seriesName: seriesName,
      );

      await _offlineStorage.saveOfflineVideo(offlineVideo);
      _downloadedVideos.insert(0, offlineVideo);
      _totalStorageUsedMb = await _offlineStorage.getTotalStorageUsedMb();

      _activeDownloads.remove(videoId);
      _downloadParams.remove(videoId);
      _persistPendingParams();
      notifyListeners();

      debugPrint(
          'DownloadProvider: Download complete for $videoId (${actualFileSizeMb.toStringAsFixed(1)} MB)');
    } catch (e) {
      _activeDownloads.remove(videoId);
      final errorMsg = e.toString().replaceAll('Exception: ', '');
      _failedDownloads[videoId] = errorMsg;
      notifyListeners();
      debugPrint('DownloadProvider: Download failed for $videoId: $e');

      await _downloadService.deleteDownload(fileName);

      onDownloadFailed?.call(DownloadFailureInfo(
        videoId: videoId,
        title: title,
        errorMessage: errorMsg,
      ));
    }
  }

  /// Cancel an active download
  Future<void> cancelDownload(String videoId) async {
    await _downloadService.cancelVideoDownload(videoId);
    // The awaiting downloadVideoFile() future will return canceledByUser
    // and clean up state. As a safety net, clean up here too in case the
    // task was still in the URL-fetch phase.
    if (_activeDownloads.containsKey(videoId)) {
      _activeDownloads.remove(videoId);
      _downloadParams.remove(videoId);
      _persistPendingParams();
      notifyListeners();
      await _downloadService.deleteDownload('video_$videoId.mp4');
    }
  }

  /// Retry a failed download.
  /// Does NOT throw — uses the same callback mechanism as [startDownload].
  Future<void> retryDownload(String videoId) async {
    final params = _downloadParams[videoId];
    if (params == null) return;

    _failedDownloads.remove(videoId);
    _backgroundPaused.remove(videoId);
    notifyListeners();

    await startDownload(
      videoId: params.videoId,
      title: params.title,
      thumbnailUrl: params.thumbnailUrl,
      facultyName: params.facultyName,
      durationSeconds: params.durationSeconds,
      moduleName: params.moduleName,
      seriesName: params.seriesName,
    );
  }

  /// Clear a failed/paused download entry (dismiss)
  void clearFailure(String videoId) {
    _failedDownloads.remove(videoId);
    _backgroundPaused.remove(videoId);
    _downloadParams.remove(videoId);
    _persistPendingParams();
    notifyListeners();
  }

  /// Delete a downloaded video (file + metadata)
  Future<void> deleteDownload(String videoId) async {
    debugPrint('DownloadProvider: Deleting download $videoId');
    await _downloadService.deleteDownload('video_$videoId.mp4');
    await _offlineStorage.removeOfflineVideo(videoId);
    _downloadedVideos.removeWhere((v) => v.videoId == videoId);
    _totalStorageUsedMb = await _offlineStorage.getTotalStorageUsedMb();
    await _notificationService.cancel(videoId);
    notifyListeners();
  }

  /// Delete all downloaded videos
  Future<void> deleteAllDownloads() async {
    debugPrint('DownloadProvider: Deleting all downloads');
    for (final video in _downloadedVideos) {
      await _downloadService.deleteDownload(video.fileName);
      await _notificationService.cancel(video.videoId);
    }
    await _offlineStorage.clearAll();
    _downloadedVideos = [];
    _totalStorageUsedMb = 0;
    notifyListeners();
  }

  /// Get downloaded videos grouped by series
  Map<String, List<OfflineVideoModel>> get downloadsBySeriesGroup {
    final Map<String, List<OfflineVideoModel>> grouped = {};
    for (final video in _downloadedVideos) {
      final key = video.seriesName ?? 'Other';
      grouped.putIfAbsent(key, () => []);
      grouped[key]!.add(video);
    }
    return grouped;
  }
}
