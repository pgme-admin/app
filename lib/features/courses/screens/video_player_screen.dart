import 'dart:async';

import 'package:better_player_plus/better_player_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:pgme/core/models/video_model.dart';
import 'package:pgme/core/services/dashboard_service.dart';
import 'package:pgme/core/services/download_service.dart';
import 'package:pgme/core/services/enrolled_courses_service.dart';
import 'package:pgme/core/services/offline_storage_service.dart';
import 'package:pgme/core/services/video_review_service.dart';
import 'package:pgme/features/courses/providers/download_provider.dart';
import 'package:pgme/features/courses/providers/enrolled_courses_provider.dart';
import 'package:pgme/features/courses/widgets/star_rating_input.dart';
import 'package:pgme/features/home/providers/dashboard_provider.dart';

class VideoPlayerScreen extends StatefulWidget {
  final String videoId;
  /// Resume position passed from the caller (e.g. dashboard).
  /// When non-null, this is used directly — no need to fetch from API/local.
  final int? resumeFromSeconds;

  const VideoPlayerScreen({
    super.key,
    required this.videoId,
    this.resumeFromSeconds,
  });

  @override
  State<VideoPlayerScreen> createState() => _VideoPlayerScreenState();
}

class _VideoPlayerScreenState extends State<VideoPlayerScreen> {
  final DashboardService _dashboardService = DashboardService();
  final VideoReviewService _videoReviewService = VideoReviewService();

  BetterPlayerController? _playerController;
  Timer? _progressTimer;
  Timer? _fullscreenCheckTimer;

  // Video metadata from API
  String? _videoUrl;
  String? _videoTitle;
  int _videoDurationSeconds = 0;

  // Progress tracking
  int _watchTimeSeconds = 0;
  int _lastSavedPositionSeconds = 0;
  DateTime? _playStartTime;
  bool _isProgressSaving = false;

  // UI state
  bool _isLoading = true;
  String? _error;
  bool _isDisposed = false;
  bool _isPlayerInitialized = false;
  bool _isLocalFile = false;

  // Best resume position found across all sources
  int _localResumePosition = 0;

  // Resume position to seek after player initialization (more reliable than startAt for HLS)
  int _pendingSeekSeconds = 0;

  // Review state
  bool _reviewLoading = true;
  bool _ratingSubmitted = false;
  bool _feedbackSubmitted = false;
  int? _submittedRating;
  String? _submittedFeedback;
  int _pendingRating = 0;
  final TextEditingController _feedbackCtrl = TextEditingController();
  bool _isSubmittingRating = false;
  bool _isSubmittingFeedback = false;

  // Fullscreen overlay
  OverlayEntry? _fullscreenBackButtonOverlay;
  bool _isFullscreen = false;
  bool _controlsVisible = true;
  Timer? _controlsHideTimer;

  @override
  void initState() {
    super.initState();
    debugPrint('VideoPlayer: init for videoId=${widget.videoId}');
    _loadVideoData();
    _loadMyReview();
  }

  @override
  void dispose() {
    debugPrint('VideoPlayer: disposing');
    _isDisposed = true;
    _saveProgressOnExit();
    _progressTimer?.cancel();
    _progressTimer = null;
    _fullscreenCheckTimer?.cancel();
    _fullscreenCheckTimer = null;
    _controlsHideTimer?.cancel();
    _controlsHideTimer = null;
    _removeFullscreenOverlay();
    _playerController?.removeEventsListener(_onPlayerEvent);
    // Pause first to stop audio immediately, then dispose
    _playerController?.pause();
    _playerController?.dispose();
    _playerController = null;
    // Restore orientation - allow landscape on tablets, portrait-only on phones
    final view = WidgetsBinding.instance.platformDispatcher.views.first;
    final logicalShortestSide = view.physicalSize.shortestSide / view.devicePixelRatio;
    final isTablet = logicalShortestSide >= 600;
    SystemChrome.setPreferredOrientations(isTablet
        ? [
            DeviceOrientation.portraitUp,
            DeviceOrientation.portraitDown,
            DeviceOrientation.landscapeLeft,
            DeviceOrientation.landscapeRight,
          ]
        : [
            DeviceOrientation.portraitUp,
            DeviceOrientation.portraitDown,
          ]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    _feedbackCtrl.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Data Loading
  // ---------------------------------------------------------------------------

  Future<void> _loadVideoData() async {
    debugPrint('VideoPlayer: loading video data');
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      // Check for locally downloaded video first (fast disk check)
      final isCurrentlyDownloading = Provider.of<DownloadProvider>(context, listen: false)
          .isDownloading(widget.videoId);
      if (!isCurrentlyDownloading) {
        final downloadedPath = await DownloadService().getDownloadedPath('video_${widget.videoId}.mp4');
        if (downloadedPath != null) {
          final offlineVideo = await OfflineStorageService().getOfflineVideo(widget.videoId);
          if (offlineVideo != null) {
            debugPrint('VideoPlayer: using local file at $downloadedPath');
            _videoUrl = downloadedPath;
            _isLocalFile = true;
            _videoTitle = offlineVideo.title;
            _videoDurationSeconds = offlineVideo.durationSeconds;
            // For local files: load progress from fast local sources only, skip network API
            await _loadLocalProgress();
            _initializePlayer();
            return;
          }
          debugPrint('VideoPlayer: local file found but no metadata, streaming instead');
        }
      } else {
        debugPrint('VideoPlayer: download in progress, streaming instead');
      }

      // For streaming: load full progress (including API) before player init
      await _loadExistingProgress();

      final videoData =
          await _dashboardService.getVideoPlaybackData(widget.videoId);

      if (_isDisposed || !mounted) return;

      final videoUrl = videoData['video_url'] as String?;
      if (videoUrl == null || videoUrl.isEmpty) {
        final status = videoData['status'] as String?;
        debugPrint('VideoPlayer: no video_url in response, status=$status');
        setState(() {
          _error = status == 'processing'
              ? 'This video is still being processed. Please try again in a few minutes.'
              : 'Video URL not available';
          _isLoading = false;
        });
        return;
      }

      _videoUrl = videoUrl;
      _videoTitle = videoData['title'] as String? ?? 'Untitled';
      _videoDurationSeconds = (videoData['duration_seconds'] as num?)?.toInt() ?? 0;

      debugPrint(
          'VideoPlayer: data loaded - title=$_videoTitle, duration=${_videoDurationSeconds}s');

      _initializePlayer();
    } catch (e) {
      debugPrint('VideoPlayer: load error - $e');
      if (_isDisposed || !mounted) return;
      setState(() {
        _error = e.toString().replaceAll('Exception: ', '');
        _isLoading = false;
      });
    }
  }

  Future<void> _loadExistingProgress() async {
    int bestPosition = 0;
    bool bestCompleted = false;
    String bestSource = 'none';

    // 0. If caller passed the position directly (e.g. dashboard), trust it
    if (widget.resumeFromSeconds != null && widget.resumeFromSeconds! > 0) {
      bestPosition = widget.resumeFromSeconds!;
      bestSource = 'route-param';
      // ignore: avoid_print
      print('VideoPlayer: route param pos=${bestPosition}s');
    }

    // 1. Check DashboardProvider.lastWatchedVideo — proven correct
    //    (the dashboard loaded it from GET /users/progress/last-watched)
    try {
      final dashboard =
          Provider.of<DashboardProvider>(context, listen: false);
      final lastWatched = dashboard.lastWatchedVideo;
      if (lastWatched != null && lastWatched.videoId == widget.videoId) {
        final dashPos = lastWatched.positionSeconds;
        // ignore: avoid_print
        print('VideoPlayer: dashboard pos=${dashPos}s, completed=${lastWatched.completed}');
        if (dashPos > bestPosition) {
          bestPosition = dashPos;
          bestCompleted = lastWatched.completed;
          bestSource = 'dashboard';
        }
      }
    } catch (e) {
      debugPrint('VideoPlayer: dashboard lookup failed - $e');
    }

    // 2. Fetch from backend API for this specific video
    try {
      final service = EnrolledCoursesService();
      final apiProgress = await service.getVideoProgress(widget.videoId);
      if (apiProgress != null) {
        // Log raw response to debug field names
        // ignore: avoid_print
        print('VideoPlayer: API raw response keys=${apiProgress.keys.toList()}');
        final apiPos = (apiProgress['position_seconds'] as num?)?.toInt() ??
            (apiProgress['last_watched_position_seconds'] as num?)?.toInt() ??
            (apiProgress['positionSeconds'] as num?)?.toInt() ?? 0;
        final apiCompleted = apiProgress['completed'] as bool? ??
            apiProgress['is_completed'] as bool? ?? false;
        // ignore: avoid_print
        print('VideoPlayer: API pos=${apiPos}s, completed=$apiCompleted');
        if (apiPos > bestPosition) {
          bestPosition = apiPos;
          bestCompleted = apiCompleted;
          bestSource = 'API';
        }
      }
    } catch (e) {
      debugPrint('VideoPlayer: API progress fetch failed - $e');
    }

    // 3. Check local SharedPreferences
    try {
      final local =
          await OfflineStorageService().getVideoProgress(widget.videoId);
      if (local != null) {
        final localPos = (local['positionSeconds'] as num?)?.toInt() ?? 0;
        final localCompleted = local['isCompleted'] as bool? ?? false;
        // ignore: avoid_print
        print('VideoPlayer: local pos=${localPos}s, completed=$localCompleted');
        if (localPos > bestPosition) {
          bestPosition = localPos;
          bestCompleted = localCompleted;
          bestSource = 'local';
        }
      }
    } catch (e) {
      debugPrint('VideoPlayer: local progress lookup failed - $e');
    }

    // 4. Check in-memory provider
    try {
      final provider =
          Provider.of<EnrolledCoursesProvider>(context, listen: false);
      final providerProgress = provider.getProgressForLecture(widget.videoId);
      if (providerProgress != null) {
        _watchTimeSeconds = providerProgress.watchTimeSeconds;
        final provPos = providerProgress.lastWatchedPositionSeconds;
        // ignore: avoid_print
        print('VideoPlayer: provider pos=${provPos}s');
        if (provPos > bestPosition) {
          bestPosition = provPos;
          bestCompleted = providerProgress.isCompleted;
          bestSource = 'provider';
        }
      }
    } catch (e) {
      debugPrint('VideoPlayer: provider lookup failed - $e');
    }

    // Use the best (highest) position from all sources
    _localResumePosition = bestPosition;

    // ignore: avoid_print
    print('===== VideoPlayer RESUME: pos=${bestPosition}s from $bestSource, completed=$bestCompleted =====');
  }

  /// Fast progress loading for local/downloaded videos — skips network API call
  Future<void> _loadLocalProgress() async {
    int bestPosition = 0;
    String bestSource = 'none';

    // 0. Route param
    if (widget.resumeFromSeconds != null && widget.resumeFromSeconds! > 0) {
      bestPosition = widget.resumeFromSeconds!;
      bestSource = 'route-param';
    }

    // 1. DashboardProvider (in-memory, instant)
    try {
      final dashboard =
          Provider.of<DashboardProvider>(context, listen: false);
      final lastWatched = dashboard.lastWatchedVideo;
      if (lastWatched != null && lastWatched.videoId == widget.videoId) {
        final dashPos = lastWatched.positionSeconds;
        if (dashPos > bestPosition) {
          bestPosition = dashPos;
          bestSource = 'dashboard';
        }
      }
    } catch (_) {}

    // 2. Local SharedPreferences (fast disk read)
    try {
      final local =
          await OfflineStorageService().getVideoProgress(widget.videoId);
      if (local != null) {
        final localPos = (local['positionSeconds'] as num?)?.toInt() ?? 0;
        if (localPos > bestPosition) {
          bestPosition = localPos;
          bestSource = 'local';
        }
      }
    } catch (_) {}

    // 3. In-memory provider (instant)
    try {
      final provider =
          Provider.of<EnrolledCoursesProvider>(context, listen: false);
      final providerProgress = provider.getProgressForLecture(widget.videoId);
      if (providerProgress != null) {
        _watchTimeSeconds = providerProgress.watchTimeSeconds;
        final provPos = providerProgress.lastWatchedPositionSeconds;
        if (provPos > bestPosition) {
          bestPosition = provPos;
          bestSource = 'provider';
        }
      }
    } catch (_) {}

    _localResumePosition = bestPosition;
    // ignore: avoid_print
    print('===== VideoPlayer LOCAL RESUME: pos=${bestPosition}s from $bestSource =====');
  }

  // ---------------------------------------------------------------------------
  // Player Initialization
  // ---------------------------------------------------------------------------

  void _initializePlayer() {
    if (_videoUrl == null || _isDisposed) return;

    // Use the resume position — even if "completed", resume from where user left off
    int resumePositionSeconds = _localResumePosition;

    // Only reset to 0 if position exceeds duration (truly finished)
    if (_videoDurationSeconds > 0 &&
        resumePositionSeconds >= _videoDurationSeconds) {
      // ignore: avoid_print
      print('VideoPlayer: resume pos ($resumePositionSeconds) >= duration ($_videoDurationSeconds), resetting');
      resumePositionSeconds = 0;
    }

    // Store for post-init seek
    _pendingSeekSeconds = resumePositionSeconds;

    // ignore: avoid_print
    print('===== VideoPlayer INIT: resume=${resumePositionSeconds}s, pendingSeek=$_pendingSeekSeconds =====');

    final BetterPlayerDataSource dataSource;
    if (_isLocalFile) {
      dataSource = BetterPlayerDataSource.file(_videoUrl!);
    } else {
      dataSource = BetterPlayerDataSource.network(
        _videoUrl!,
        videoFormat: BetterPlayerVideoFormat.hls,
        useAsmsTracks: true,
        useAsmsSubtitles: true,
        useAsmsAudioTracks: true,
        bufferingConfiguration: const BetterPlayerBufferingConfiguration(
          minBufferMs: 2000,
          maxBufferMs: 30000,
          bufferForPlaybackMs: 1500,
          bufferForPlaybackAfterRebufferMs: 3000,
        ),
      );
    }

    // Don't autoPlay when we need to seek first — seek then play manually
    final shouldSeek = resumePositionSeconds > 0;

    _playerController = BetterPlayerController(
      BetterPlayerConfiguration(
        autoPlay: !shouldSeek,
        fit: BoxFit.contain,
        fullScreenByDefault: false,
        allowedScreenSleep: false,
        handleLifecycle: true,
        autoDispose: false,
        deviceOrientationsOnFullScreen: const [
          DeviceOrientation.landscapeLeft,
          DeviceOrientation.landscapeRight,
        ],
        deviceOrientationsAfterFullScreen: const [
          DeviceOrientation.portraitUp,
          DeviceOrientation.portraitDown,
        ],
        controlsConfiguration: const BetterPlayerControlsConfiguration(
          enableProgressBar: true,
          enablePlayPause: true,
          enableFullscreen: true,
          enableSkips: true,
          enablePlaybackSpeed: true,
          enableQualities: true,
          enableMute: true,
          enableProgressText: true,
          enableOverflowMenu: true,
          enableRetry: true,
          forwardSkipTimeInMilliseconds: 10000,
          backwardSkipTimeInMilliseconds: 10000,
          loadingColor: Colors.white,
          progressBarPlayedColor: Colors.white,
          progressBarHandleColor: Colors.white,
          progressBarBufferedColor: Colors.white70,
          progressBarBackgroundColor: Colors.white24,
        ),
        errorBuilder: (context, errorMessage) {
          return _buildPlayerError(errorMessage);
        },
      ),
      betterPlayerDataSource: dataSource,
    );

    _playerController!.addEventsListener(_onPlayerEvent);

    if (!_isDisposed && mounted) {
      setState(() {
        _isLoading = false;
        _isPlayerInitialized = true;
      });
    }

    _startProgressTimer();
    _startFullscreenMonitoring();
  }

  // ---------------------------------------------------------------------------
  // Player Events
  // ---------------------------------------------------------------------------

  void _onPlayerEvent(BetterPlayerEvent event) {
    if (_isDisposed) return;

    switch (event.betterPlayerEventType) {
      case BetterPlayerEventType.initialized:
        debugPrint('VideoPlayer: player initialized');
        final duration =
            _playerController?.videoPlayerController?.value.duration;
        if (duration != null && _videoDurationSeconds == 0) {
          _videoDurationSeconds = duration.inSeconds;
          debugPrint(
              'VideoPlayer: duration from player - ${_videoDurationSeconds}s');
        }
        // Seek to resume position, then start playing
        if (_pendingSeekSeconds > 0) {
          final seekTo = _pendingSeekSeconds;
          _pendingSeekSeconds = 0; // consume so we don't seek again
          // ignore: avoid_print
          print('===== VideoPlayer SEEKING to ${seekTo}s =====');
          Future.delayed(const Duration(milliseconds: 100), () {
            if (_isDisposed || _playerController == null) return;
            _playerController!.seekTo(Duration(seconds: seekTo)).then((_) {
              // ignore: avoid_print
              print('===== VideoPlayer SEEK DONE, now playing =====');
              if (!_isDisposed) {
                _playerController?.play();
              }
            });
          });
        }
        break;

      case BetterPlayerEventType.play:
        // Accumulate any existing watch time before resetting the start marker.
        // Prevents losing tracked time if multiple play events fire consecutively
        // (e.g., during seeks or buffering).
        _accumulateWatchTime();
        _playStartTime = DateTime.now();
        break;

      case BetterPlayerEventType.pause:
        debugPrint('VideoPlayer: paused');
        _accumulateWatchTime();
        _saveProgress();
        break;

      case BetterPlayerEventType.finished:
        debugPrint('VideoPlayer: finished');
        _accumulateWatchTime();
        _saveProgress(forceComplete: true);
        break;

      case BetterPlayerEventType.exception:
        final errorMsg = event.parameters?['exception'];
        debugPrint('VideoPlayer: exception - $errorMsg');
        break;

      default:
        break;
    }
  }

  // ---------------------------------------------------------------------------
  // Progress Tracking
  // ---------------------------------------------------------------------------

  void _accumulateWatchTime() {
    if (_playStartTime != null) {
      final now = DateTime.now();
      // Clamp to non-negative to guard against device clock changes
      final elapsed = now.difference(_playStartTime!).inSeconds.clamp(0, 86400);
      _watchTimeSeconds += elapsed;
      _playStartTime = now;
    }
  }

  void _startProgressTimer() {
    _progressTimer?.cancel();
    _progressTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (_isDisposed) return;
      _accumulateWatchTime();
      _saveProgress();
    });
    debugPrint('VideoPlayer: progress timer started (15s)');
  }

  Future<void> _saveProgress({bool forceComplete = false}) async {
    if (_isDisposed || _isProgressSaving) return;
    if (_playerController?.videoPlayerController == null) return;

    final value = _playerController!.videoPlayerController!.value;
    final positionSeconds = value.position.inSeconds;

    // Skip if position hasn't changed since last save
    if (!forceComplete && positionSeconds == _lastSavedPositionSeconds) return;

    _isProgressSaving = true;

    try {
      final duration = _videoDurationSeconds > 0
          ? _videoDurationSeconds
          : (value.duration?.inSeconds ?? 0);

      if (duration <= 0) {
        debugPrint('VideoPlayer: skip save, duration unknown');
        _isProgressSaving = false;
        return;
      }

      final completionPercentage =
          ((positionSeconds / duration) * 100).round().clamp(0, 100);
      final isCompleted = forceComplete || completionPercentage >= 90;

      debugPrint(
          'VideoPlayer: saving pos=${positionSeconds}s, watch=${_watchTimeSeconds}s, $completionPercentage%, done=$isCompleted');

      // Always persist locally first — works offline and serves as fallback for
      // the home-screen resume card and provider-list lookup.
      try {
        await OfflineStorageService().saveVideoProgress(
          widget.videoId,
          positionSeconds,
          duration,
          isCompleted,
        );
        final lastWatchedJson = {
          'video_id': widget.videoId,
          'title': _videoTitle ?? '',
          'thumbnail_url': null,
          'duration_seconds': duration,
          'module_title': null,
          'position_seconds': positionSeconds,
          'watch_percentage': completionPercentage,
          'completed': isCompleted,
          'is_free': false,
          'last_accessed_at': DateTime.now().toIso8601String(),
        };
        await OfflineStorageService().saveLastWatchedVideo(lastWatchedJson);

        // Update the home-screen card in-memory so it reflects current video
        // immediately when the user pops back, without a full dashboard reload.
        try {
          final dashboard =
              Provider.of<DashboardProvider>(context, listen: false);
          dashboard.updateLastWatchedLocally(
              VideoModel.fromJson(lastWatchedJson));
        } catch (_) {}
      } catch (localErr) {
        debugPrint('VideoPlayer: local save failed - $localErr');
      }

      // Sync to backend (may fail when offline — that's acceptable)
      try {
        final provider =
            Provider.of<EnrolledCoursesProvider>(context, listen: false);
        await provider.updateLectureProgress(
          lectureId: widget.videoId,
          lastWatchedPositionSeconds: positionSeconds,
          watchTimeSeconds: _watchTimeSeconds,
          isCompleted: isCompleted,
          completionPercentage: completionPercentage,
        );
      } catch (backendErr) {
        debugPrint('VideoPlayer: backend save failed (offline?) - $backendErr');
      }

      _lastSavedPositionSeconds = positionSeconds;
    } catch (e) {
      debugPrint('VideoPlayer: save failed - $e');
    } finally {
      _isProgressSaving = false;
    }
  }

  void _saveProgressOnExit() {
    if (_playerController?.videoPlayerController == null) return;

    _accumulateWatchTime();

    final value = _playerController!.videoPlayerController!.value;
    final positionSeconds = value.position.inSeconds;

    if (positionSeconds == _lastSavedPositionSeconds) return;

    final duration = _videoDurationSeconds > 0
        ? _videoDurationSeconds
        : (value.duration?.inSeconds ?? 0);

    if (duration <= 0) return;

    final completionPercentage =
        ((positionSeconds / duration) * 100).round().clamp(0, 100);
    final isCompleted = completionPercentage >= 90;

    debugPrint(
        'VideoPlayer: exit save pos=${positionSeconds}s, watch=${_watchTimeSeconds}s');

    // Save locally (fire-and-forget) — ensures resume works even if app is killed
    OfflineStorageService().saveVideoProgress(
      widget.videoId, positionSeconds, duration, isCompleted);
    OfflineStorageService().saveLastWatchedVideo({
      'video_id': widget.videoId,
      'title': _videoTitle ?? '',
      'thumbnail_url': null,
      'duration_seconds': duration,
      'module_title': null,
      'position_seconds': positionSeconds,
      'watch_percentage': completionPercentage,
      'completed': isCompleted,
      'is_free': false,
      'last_accessed_at': DateTime.now().toIso8601String(),
    });

    try {
      final provider =
          Provider.of<EnrolledCoursesProvider>(context, listen: false);
      // Fire-and-forget on dispose
      provider.updateLectureProgress(
        lectureId: widget.videoId,
        lastWatchedPositionSeconds: positionSeconds,
        watchTimeSeconds: _watchTimeSeconds,
        isCompleted: isCompleted,
        completionPercentage: completionPercentage,
      );
    } catch (e) {
      debugPrint('VideoPlayer: exit save failed - $e');
    }
  }

  // ---------------------------------------------------------------------------
  // Navigation
  // ---------------------------------------------------------------------------

  Future<void> _stopAndGoBack() async {
    _playerController?.pause();
    await _saveProgressBeforeExit();
    if (mounted) {
      context.pop();
    }
  }

  /// Awaitable save — called before navigation so data is persisted
  /// before the next screen tries to read it.
  Future<void> _saveProgressBeforeExit() async {
    if (_playerController?.videoPlayerController == null) return;

    _accumulateWatchTime();

    final value = _playerController!.videoPlayerController!.value;
    final positionSeconds = value.position.inSeconds;

    final duration = _videoDurationSeconds > 0
        ? _videoDurationSeconds
        : (value.duration?.inSeconds ?? 0);

    if (duration <= 0) return;

    final completionPercentage =
        ((positionSeconds / duration) * 100).round().clamp(0, 100);
    final isCompleted = completionPercentage >= 90;

    debugPrint(
        'VideoPlayer: pre-exit save pos=${positionSeconds}s, watch=${_watchTimeSeconds}s');

    // Save locally and AWAIT so it's persisted before the next screen reads it
    await OfflineStorageService().saveVideoProgress(
        widget.videoId, positionSeconds, duration, isCompleted);

    final lastWatchedJson = {
      'video_id': widget.videoId,
      'title': _videoTitle ?? '',
      'thumbnail_url': null,
      'duration_seconds': duration,
      'module_title': null,
      'position_seconds': positionSeconds,
      'watch_percentage': completionPercentage,
      'completed': isCompleted,
      'is_free': false,
      'last_accessed_at': DateTime.now().toIso8601String(),
    };
    await OfflineStorageService().saveLastWatchedVideo(lastWatchedJson);

    // Update in-memory dashboard state
    try {
      final dashboard =
          Provider.of<DashboardProvider>(context, listen: false);
      dashboard.updateLastWatchedLocally(
          VideoModel.fromJson(lastWatchedJson));
    } catch (_) {}

    // Backend save (fire-and-forget is OK here, local is already saved)
    try {
      final provider =
          Provider.of<EnrolledCoursesProvider>(context, listen: false);
      provider.updateLectureProgress(
        lectureId: widget.videoId,
        lastWatchedPositionSeconds: positionSeconds,
        watchTimeSeconds: _watchTimeSeconds,
        isCompleted: isCompleted,
        completionPercentage: completionPercentage,
      );
    } catch (_) {}

    _lastSavedPositionSeconds = positionSeconds;
  }

  // ---------------------------------------------------------------------------
  // Fullscreen Overlay Management
  // ---------------------------------------------------------------------------

  void _startFullscreenMonitoring() {
    _fullscreenCheckTimer = Timer.periodic(const Duration(milliseconds: 300), (timer) {
      if (_isDisposed || !mounted) {
        timer.cancel();
        return;
      }

      final isFullscreen = _playerController?.isFullScreen ?? false;
      if (isFullscreen != _isFullscreen) {
        _isFullscreen = isFullscreen;
        if (isFullscreen) {
          _showFullscreenOverlay();
        } else {
          _removeFullscreenOverlay();
        }
      }
    });
  }

  void _showFullscreenOverlay() {
    if (_fullscreenBackButtonOverlay != null) return;

    _fullscreenBackButtonOverlay = OverlayEntry(
      builder: (context) => StatefulBuilder(
        builder: (context, setState) {
          // Start auto-hide timer initially
          _startControlsHideTimer(() {
            if (mounted && _fullscreenBackButtonOverlay != null) {
              setState(() {
                _controlsVisible = false;
              });
            }
          });

          return Listener(
            behavior: HitTestBehavior.translucent,
            onPointerDown: (_) {
              // Show controls on tap
              setState(() {
                _controlsVisible = true;
              });
              // Restart hide timer
              _startControlsHideTimer(() {
                if (mounted && _fullscreenBackButtonOverlay != null) {
                  setState(() {
                    _controlsVisible = false;
                  });
                }
              });
            },
            child: Stack(
              children: [
                // Back button - synced with control visibility
                Positioned(
                  top: 16,
                  left: 16,
                  child: SafeArea(
                    child: AnimatedOpacity(
                      opacity: _controlsVisible ? 1.0 : 0.0,
                      duration: const Duration(milliseconds: 300),
                      child: IgnorePointer(
                        ignoring: !_controlsVisible,
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            onTap: () {
                              _playerController?.exitFullScreen();
                            },
                            borderRadius: BorderRadius.circular(24),
                            child: Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.6),
                                borderRadius: BorderRadius.circular(24),
                              ),
                              child: const Icon(
                                Icons.arrow_back,
                                color: Colors.white,
                                size: 28,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );

    Overlay.of(context).insert(_fullscreenBackButtonOverlay!);
  }

  void _startControlsHideTimer(VoidCallback onHide) {
    _controlsHideTimer?.cancel();
    _controlsHideTimer = Timer(const Duration(seconds: 3), onHide);
  }

  void _removeFullscreenOverlay() {
    _controlsHideTimer?.cancel();
    _controlsHideTimer = null;
    _fullscreenBackButtonOverlay?.remove();
    _fullscreenBackButtonOverlay = null;
    _controlsVisible = true; // Reset for next session
  }

  // ---------------------------------------------------------------------------
  // UI
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;

        // Check if player is in fullscreen mode
        final isFullscreen = _playerController?.isFullScreen ?? false;
        if (isFullscreen) {
          // Exit fullscreen first, don't close the screen
          _playerController?.exitFullScreen();
          return;
        }

        // Save progress, then navigate back
        _playerController?.pause();
        await _saveProgressBeforeExit();
        if (mounted) {
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          child: Column(
            children: [
              _buildPlayerArea(),
              if (!_isLoading && _error == null) _buildVideoInfo(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPlayerArea() {
    if (_isLoading) {
      return _buildLoadingState();
    }

    if (_error != null) {
      return _buildErrorState();
    }

    if (_playerController != null && _isPlayerInitialized) {
      return AspectRatio(
        aspectRatio: 16 / 9,
        child: BetterPlayer(controller: _playerController!),
      );
    }

    return _buildLoadingState();
  }

  Widget _buildLoadingState() {
    return AspectRatio(
      aspectRatio: 16 / 9,
      child: Container(
        color: Colors.black,
        child: const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(color: Colors.white),
              SizedBox(height: 16),
              Text(
                'Loading video...',
                style: TextStyle(color: Colors.white70, fontSize: 14),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildErrorState() {
    return AspectRatio(
      aspectRatio: 16 / 9,
      child: Container(
        color: Colors.black,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(
                    Icons.error_outline, color: Colors.white54, size: 48),
                const SizedBox(height: 16),
                Text(
                  _error ?? 'Failed to load video',
                  style:
                      const TextStyle(color: Colors.white70, fontSize: 14),
                  textAlign: TextAlign.center,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    TextButton.icon(
                      onPressed: _stopAndGoBack,
                      icon: const Icon(Icons.arrow_back,
                          color: Colors.white70, size: 18),
                      label: const Text('Go Back',
                          style: TextStyle(color: Colors.white70)),
                    ),
                    const SizedBox(width: 16),
                    ElevatedButton.icon(
                      onPressed: _loadVideoData,
                      icon: const Icon(Icons.refresh, size: 18),
                      label: const Text('Retry'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white24,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPlayerError(String? errorMessage) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
                Icons.error_outline, color: Colors.white54, size: 40),
            const SizedBox(height: 12),
            Text(
              errorMessage ?? 'Playback error',
              style:
                  const TextStyle(color: Colors.white70, fontSize: 13),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Review
  // ---------------------------------------------------------------------------

  Future<void> _loadMyReview() async {
    try {
      final review = await _videoReviewService.getMyReview(widget.videoId);
      if (!mounted) return;
      setState(() {
        _reviewLoading = false;
        if (review == null) {
          _ratingSubmitted = false;
          _feedbackSubmitted = false;
        } else {
          _ratingSubmitted = review['rating_submitted_at'] != null;
          _feedbackSubmitted = review['feedback_submitted_at'] != null;
          _submittedRating = review['rating'] as int?;
          _submittedFeedback = review['feedback'] as String?;
        }
      });
    } catch (_) {
      // Silently fail — don't block the video player for a review fetch failure
      if (mounted) setState(() => _reviewLoading = false);
    }
  }

  Future<void> _submitRating() async {
    if (_pendingRating == 0) return;
    setState(() => _isSubmittingRating = true);
    try {
      final review = await _videoReviewService.submitRating(widget.videoId, _pendingRating);
      if (!mounted) return;
      setState(() {
        _ratingSubmitted = true;
        _submittedRating = review['rating'] as int?;
        _isSubmittingRating = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Rating submitted!'),
          backgroundColor: Color(0xFF1847A2),
          duration: Duration(seconds: 2),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSubmittingRating = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.toString().replaceAll('Exception: ', '')),
          backgroundColor: Colors.red[700],
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  Future<void> _submitFeedback() async {
    final text = _feedbackCtrl.text.trim();
    if (text.isEmpty) return;
    setState(() => _isSubmittingFeedback = true);
    try {
      final review = await _videoReviewService.submitFeedback(widget.videoId, text);
      if (!mounted) return;
      setState(() {
        _feedbackSubmitted = true;
        _submittedFeedback = review['feedback'] as String?;
        _isSubmittingFeedback = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Feedback submitted!'),
          backgroundColor: Color(0xFF1847A2),
          duration: Duration(seconds: 2),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSubmittingFeedback = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.toString().replaceAll('Exception: ', '')),
          backgroundColor: Colors.red[700],
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  Widget _buildRatingSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Rate this lecture',
          style: TextStyle(
            color: Colors.white,
            fontSize: 14,
            fontWeight: FontWeight.w600,
            fontFamily: 'Poppins',
          ),
        ),
        const SizedBox(height: 12),
        if (_reviewLoading)
          Container(
            width: 160,
            height: 32,
            decoration: BoxDecoration(
              color: Colors.white12,
              borderRadius: BorderRadius.circular(6),
            ),
          )
        else if (_ratingSubmitted)
          Row(
            children: [
              StarRatingDisplay(rating: _submittedRating ?? 0, size: 28),
              const SizedBox(width: 10),
              Text(
                '${_submittedRating ?? 0}/5',
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 14,
                  fontFamily: 'Poppins',
                ),
              ),
            ],
          )
        else
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              StarRatingInput(
                current: _pendingRating,
                onChanged: (v) => setState(() => _pendingRating = v),
                size: 32,
              ),
              if (_pendingRating > 0) ...[
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _isSubmittingRating ? null : _submitRating,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF1847A2),
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: Colors.white24,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: _isSubmittingRating
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2,
                            ),
                          )
                        : const Text(
                            'Submit Rating',
                            style: TextStyle(
                              fontFamily: 'Poppins',
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                  ),
                ),
              ],
            ],
          ),
      ],
    );
  }

  Widget _buildFeedbackSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Share your feedback',
          style: TextStyle(
            color: Colors.white,
            fontSize: 14,
            fontWeight: FontWeight.w600,
            fontFamily: 'Poppins',
          ),
        ),
        const SizedBox(height: 12),
        if (_reviewLoading)
          Container(
            height: 100,
            decoration: BoxDecoration(
              color: Colors.white12,
              borderRadius: BorderRadius.circular(8),
            ),
          )
        else if (_feedbackSubmitted)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.white24),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              _submittedFeedback ?? '',
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 13,
                fontFamily: 'Poppins',
                height: 1.5,
              ),
            ),
          )
        else
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: _feedbackCtrl,
                maxLines: 4,
                minLines: 3,
                maxLength: 2000,
                style: const TextStyle(
                  color: Colors.white,
                  fontFamily: 'Poppins',
                  fontSize: 13,
                ),
                decoration: InputDecoration(
                  hintText: 'What did you like or dislike about this lecture?',
                  hintStyle: const TextStyle(color: Colors.white38, fontSize: 13),
                  counterStyle: const TextStyle(color: Colors.white38, fontSize: 11),
                  filled: true,
                  fillColor: Colors.white10,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: Colors.white24),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: Colors.white24),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: Color(0xFF1847A2), width: 1.5),
                  ),
                  contentPadding: const EdgeInsets.all(12),
                ),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: (_feedbackCtrl.text.trim().isEmpty || _isSubmittingFeedback)
                      ? null
                      : _submitFeedback,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1847A2),
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: Colors.white12,
                    disabledForegroundColor: Colors.white38,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: _isSubmittingFeedback
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
                          ),
                        )
                      : const Text(
                          'Submit Feedback',
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                ),
              ),
            ],
          ),
      ],
    );
  }

  Widget _buildVideoInfo() {
    return Expanded(
      child: Container(
        width: double.infinity,
        color: Colors.black,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  GestureDetector(
                    onTap: _stopAndGoBack,
                    child: const Padding(
                      padding: EdgeInsets.only(right: 12),
                      child: Icon(Icons.arrow_back,
                          color: Colors.white, size: 24),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      _videoTitle ?? 'Video',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        fontFamily: 'Poppins',
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              if (_videoDurationSeconds > 0) ...[
                const SizedBox(height: 8),
                Text(
                  _formatDuration(_videoDurationSeconds),
                  style: const TextStyle(
                    color: Colors.white54,
                    fontSize: 13,
                    fontFamily: 'Poppins',
                  ),
                ),
              ],
              const SizedBox(height: 28),
              _buildRatingSection(),
              const SizedBox(height: 24),
              _buildFeedbackSection(),
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }

  String _formatDuration(int totalSeconds) {
    final hours = totalSeconds ~/ 3600;
    final minutes = (totalSeconds % 3600) ~/ 60;
    final seconds = totalSeconds % 60;
    if (hours > 0) {
      return '$hours hr ${minutes > 0 ? "$minutes min" : ""}';
    }
    if (minutes > 0) {
      return '$minutes min ${seconds > 0 ? "$seconds sec" : ""}';
    }
    return '$seconds sec';
  }
}
