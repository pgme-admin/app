import 'dart:async';

import 'package:better_player_plus/better_player_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pgme/core/utils/video_speed_store.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:pgme/core/models/video_model.dart';
import 'package:pgme/core/providers/mini_player_provider.dart';
import 'package:pgme/core/services/dashboard_service.dart';
import 'package:pgme/core/services/download_service.dart';
import 'package:pgme/core/services/enrolled_courses_service.dart';
import 'package:pgme/core/services/offline_storage_service.dart';
import 'package:pgme/core/services/video_review_service.dart';
import 'package:pgme/core/utils/responsive_helper.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:pgme/features/courses/providers/download_provider.dart';
import 'package:pgme/features/courses/providers/enrolled_courses_provider.dart';
import 'package:pgme/features/courses/widgets/star_rating_input.dart';
import 'package:pgme/features/courses/widgets/document_picker_sheet.dart';
// The split pane hosts the full pdfrx reader in `embedded` mode, so the pane has
// the same annotation tools (highlight, underline, notes, undo, bookmarks) as
// the full-screen reader. The lightweight read-only viewer remains available at:
//   import 'package:pgme/features/courses/widgets/inline_pdf_viewer_pdfrx.dart';
import 'package:pgme/features/notes/screens/pdf_viewer_screen_pdfrx.dart'
    as pdfrx_reader;
import 'package:pgme/core/models/selectable_document.dart';
import 'package:pgme/core/widgets/resizable_split_view.dart';
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

class _VideoPlayerScreenState extends State<VideoPlayerScreen> with WidgetsBindingObserver {
  final DashboardService _dashboardService = DashboardService();
  final VideoReviewService _videoReviewService = VideoReviewService();

  BetterPlayerController? _playerController;
  Timer? _progressTimer;
  Timer? _fullscreenCheckTimer;

  // Video metadata from API
  String? _videoUrl;
  String? _videoTitle;
  String? _videoDescription;
  int _videoDurationSeconds = 0;

  // Progress tracking
  int _watchTimeSeconds = 0;
  int _lastSavedPositionSeconds = 0;
  DateTime? _playStartTime;
  bool _isProgressSaving = false;

  // Preserves the user's chosen playback speed across pause/resume.
  // better_player_plus can reset the native playback rate on pause; we cache
  // the value set via the controls and reapply on play. Persisted via
  // [VideoSpeedStore] (sync file write) so the value survives even an
  // abrupt app kill and applies to subsequent videos.
  double _currentSpeed = 1.0;

  // Mutable list passed into the data source as `asmsTrackNames`. The
  // better_player_plus controls read this list by index when building the
  // quality menu — we populate it once the HLS manifest is parsed so the menu
  // shows simple labels ("Low"/"Medium"/"High") instead of bare resolutions.
  final List<String> _qualityLabels = [];
  bool _qualityLabelsApplied = false;

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

  // Split-view PDF state
  bool _isSplitViewActive = false;
  SelectableDocument? _activeDocument;

  // "Study mode": landscape, immersive layout with the video on the left and
  // the notes PDF on the right. Entered from the fullscreen player's Notes
  // button so a student can read along while watching fullscreen.
  bool _isStudyMode = false;

  // Fullscreen overlay
  OverlayEntry? _fullscreenBackButtonOverlay;
  bool _isFullscreen = false;
  bool _controlsVisible = true;
  Timer? _controlsHideTimer;

  // MiniPlayerProvider captured in initState (see there for why).
  MiniPlayerProvider? _miniProvider;

  // Mini player support: when true, dispose() will NOT destroy the controller
  bool _isMinimizing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    debugPrint('VideoPlayer: init for videoId=${widget.videoId}');

    // Check if MiniPlayerProvider already has a live controller for this video
    final miniProvider = Provider.of<MiniPlayerProvider>(context, listen: false);
    // Kept for dispose(): looking the provider up from `context` there fails
    // (the element is already deactivated), which left a disposed controller
    // registered and crashed the next open of the same video when it was
    // "adopted" ("VideoPlayerController was used after being disposed").
    _miniProvider = miniProvider;
    if (miniProvider.videoId == widget.videoId && miniProvider.controller != null) {
      // Reuse the existing controller — player was expanded from mini mode
      debugPrint('VideoPlayer: adopting controller from MiniPlayerProvider');
      _playerController = miniProvider.controller;
      _videoTitle = miniProvider.videoTitle;
      _videoDescription = miniProvider.videoDescription;
      _videoDurationSeconds = miniProvider.videoDurationSeconds;
      _watchTimeSeconds = miniProvider.watchTimeSeconds;
      _isLoading = false;
      _isPlayerInitialized = true;
      miniProvider.expand(); // mark as no longer minimized

      _playerController!.addEventsListener(_onPlayerEvent);
      _playerController!.videoPlayerController?.addListener(_enforceSpeed);
      _startProgressTimer();
      _startFullscreenMonitoring();

      _loadMyReview();
      return;
    }

    _loadSavedSpeed();
    _loadVideoData();
    _loadMyReview();
  }

  /// Listener attached to `videoPlayerController` that snaps the native
  /// playback rate back to [_currentSpeed] when better_player_plus
  /// internally resets it. This enforces the user's selected speed
  /// across pause/buffer/seek events.
  void _enforceSpeed() {
    if (_isDisposed || _currentSpeed <= 0) return;
    final actual =
        _playerController?.videoPlayerController?.value.speed ?? 1.0;
    // If native speed drifts from user's selection, snap it back.
    if ((actual - _currentSpeed).abs() > 0.001) {
      _playerController?.setSpeed(_currentSpeed);
    }
  }

  /// Restores the playback speed the user picked in a previous session.
  /// Read before the player initializes so [_currentSpeed] is correct by
  /// the time the play event fires and we re-apply it on the controller.
  /// Also warms up the [VideoSpeedStore] file handle so subsequent
  /// sync saves run in microseconds without an async platform call.
  Future<void> _loadSavedSpeed() async {
    try {
      await VideoSpeedStore.ensureReady();
      final saved = await VideoSpeedStore.read();
      if (saved != null && saved > 0) {
        _currentSpeed = saved;
        // If the player has already initialized (race during async load),
        // apply immediately. Otherwise the play event handler will pick
        // it up from _currentSpeed.
        _playerController?.setSpeed(saved);
      }
    } catch (e) {
      debugPrint('VideoPlayer: failed to load saved speed - $e');
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Pause only when the app really leaves the screen (paused / hidden).
    // `inactive` also fires on Android when the notification shade is pulled
    // down or another split-screen app is tapped, which stopped the lecture
    // and never resumed it.
    if (state == AppLifecycleState.paused || state == AppLifecycleState.hidden) {
      _playerController?.pause();
    }
  }

  @override
  void deactivate() {
    // Don't pause when minimizing — the mini player should keep playing
    if (!_isMinimizing) {
      _playerController?.pause();
    }
    super.deactivate();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    debugPrint('VideoPlayer: disposing (minimizing=$_isMinimizing)');
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
    _playerController?.videoPlayerController?.removeListener(_enforceSpeed);

    if (_isMinimizing) {
      // Controller ownership transferred to MiniPlayerProvider — do NOT dispose it
      _playerController = null;
    } else {
      // Normal exit — destroy the player.
      // forceDispose overrides autoDispose:false (which is set to survive
      // widget reparenting during split-view transitions); without it the
      // call would no-op and leak the native ExoPlayer/AVPlayer + listeners.
      _playerController?.pause();
      _playerController?.dispose(forceDispose: true);
      _playerController = null;
      // Also close the mini player provider if it was referencing this controller
      try {
        final miniProvider = _miniProvider;
        if (miniProvider != null && miniProvider.videoId == widget.videoId) {
          miniProvider.unregister();
        }
      } catch (e) {
        debugPrint('VideoPlayer: mini player unregister failed: $e');
      }
    }

    // Restore device-appropriate orientations on the way out (tablets get
    // landscape back, phones stay portrait).
    SystemChrome.setPreferredOrientations(
        ResponsiveHelper.supportedOrientationsForDevice());
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
      _videoDescription = videoData['description'] as String?;
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
      dataSource = BetterPlayerDataSource(
        BetterPlayerDataSourceType.network,
        _videoUrl!,
        videoFormat: BetterPlayerVideoFormat.hls,
        useAsmsTracks: true,
        useAsmsSubtitles: true,
        useAsmsAudioTracks: false,
        asmsTrackNames: _qualityLabels,
        // ExoPlayer asserts minBufferMs >= both playback thresholds and
        // throws from the DefaultLoadControl builder otherwise, which aborts
        // player construction — the UI then sits on the buffering spinner
        // forever with no error surfaced. minBufferMs was 2000 while
        // bufferForPlaybackAfterRebufferMs was 3000, so every network
        // playback failed; local files skip this config and still worked,
        // which is what made it look like a streaming problem.
        //
        // 15s of minimum buffer also rebuffers far less on mobile data than
        // the old 2s did, while bufferForPlaybackMs keeps first-frame latency
        // at 1.5s.
        bufferingConfiguration: const BetterPlayerBufferingConfiguration(
          minBufferMs: 15000,
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
        // Keep the controller alive when the BetterPlayer widget is
        // reparented (e.g. swapping into the split-view layout).
        // BetterPlayer.dispose unconditionally calls controller.dispose,
        // which would tear the underlying VideoPlayerController down
        // mid-session and leave the new instance pointed at a disposed
        // controller ("used after being disposed" red box).
        // The screen's own dispose() passes forceDispose: true to actually
        // release the controller when the user leaves the screen.
        autoDispose: false,
        deviceOrientationsOnFullScreen: const [
          DeviceOrientation.landscapeLeft,
          DeviceOrientation.landscapeRight,
        ],
        deviceOrientationsAfterFullScreen:
            ResponsiveHelper.supportedOrientationsForDevice(),
        controlsConfiguration: const BetterPlayerControlsConfiguration(
          enableProgressBar: true,
          enablePlayPause: true,
          enableFullscreen: true,
          enableSkips: true,
          enablePlaybackSpeed: true,
          enableQualities: true,
          enableAudioTracks: false,
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
    // Hard-lock the playback rate to the user's choice. better_player_plus
    // silently resets the native rate to 1.0 around pause, buffering, seek
    // and source swaps — the value listener catches every drift and snaps
    // it back without waiting for a specific event type.
    _playerController!.videoPlayerController?.addListener(_enforceSpeed);

    if (!_isDisposed && mounted) {
      setState(() {
        _isLoading = false;
        _isPlayerInitialized = true;
      });
    }

    // Register with MiniPlayerProvider so controller survives minimize
    try {
      final miniProvider = Provider.of<MiniPlayerProvider>(context, listen: false);
      miniProvider.registerController(
        controller: _playerController!,
        videoId: widget.videoId,
        videoTitle: _videoTitle,
        videoDescription: _videoDescription,
        videoDurationSeconds: _videoDurationSeconds,
        watchTimeSeconds: _watchTimeSeconds,
      );
    } catch (_) {}

    _startProgressTimer();
    _startFullscreenMonitoring();
  }

  // ---------------------------------------------------------------------------
  // Player Events
  // ---------------------------------------------------------------------------

  void _onPlayerEvent(BetterPlayerEvent event) {
    if (_isDisposed) return;

    // Populate the quality menu labels lazily — by the time the controls are
    // visible, the HLS manifest has typically been parsed.
    _ensureQualityLabels();

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
        // Always reapply the user's chosen speed on play, including 1.0.
        // This ensures the selected speed persists across pause/resume.
        if (_currentSpeed > 0) {
          _playerController?.setSpeed(_currentSpeed);
        }
        break;

      case BetterPlayerEventType.pause:
        debugPrint('VideoPlayer: paused');
        _accumulateWatchTime();
        _saveProgress();
        break;

      case BetterPlayerEventType.setSpeed:
        final speed = (event.parameters?['speed'] as num?)?.toDouble();
        // Accept all valid speed values, including 1.0.
        // User-initiated speed changes (from the controls menu) must be
        // saved and applied, regardless of the value.
        if (speed != null && speed > 0) {
          debugPrint('[SpeedEvent] setSpeed=$speed → saving and applying');
          _currentSpeed = speed;
          VideoSpeedStore.saveSync(speed);
        }
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

  // Maps an HLS rendition's pixel height to a label. The backend encodes a
  // fixed 3-rung ladder (480p / 720p / 1080p — see mediaconvert.service.js),
  // so each rung gets its own distinct label.
  String _qualityLabelForHeight(int height) {
    if (height >= 1080) return 'High'; // 1080p
    if (height >= 720) return 'Medium'; // 720p
    return 'Low'; // 480p (and anything lower)
  }

  void _ensureQualityLabels() {
    if (_qualityLabelsApplied) return;
    final tracks = _playerController?.betterPlayerAsmsTracks;
    if (tracks == null || tracks.isEmpty) return;
    final labels = tracks.map((t) {
      final h = t.height ?? 0;
      // Auto track is all-zero — leave blank so the controls fall back to the
      // built-in `qualityAuto` translation ("Auto").
      if (h <= 0) return '';
      return _qualityLabelForHeight(h);
    }).toList();
    _qualityLabels
      ..clear()
      ..addAll(labels);
    _qualityLabelsApplied = true;
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

    // Redundant speed save in case the setSpeed event-handler write
    // missed (e.g. very first session before VideoSpeedStore.ensureReady
    // resolved). Sync write, sub-millisecond on flash storage.
    if (_currentSpeed > 0) {
      VideoSpeedStore.saveSync(_currentSpeed);
    }

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

  /// Minimize the player into the mini-player bar and navigate back.
  void _minimizeAndGoBack() {
    if (_playerController == null) return;

    // Hand ownership to the MiniPlayerProvider
    _accumulateWatchTime();
    final miniProvider = Provider.of<MiniPlayerProvider>(context, listen: false);
    miniProvider.updateWatchTime(_watchTimeSeconds);
    miniProvider.updateMetadata(
      videoTitle: _videoTitle,
      videoDescription: _videoDescription,
      videoDurationSeconds: _videoDurationSeconds,
    );
    miniProvider.minimize();

    // Set _isMinimizing via setState so the widget rebuilds with canPop: true.
    // PopScope(canPop: false) blocks Navigator.pop() in modern Flutter, so we
    // must flip canPop first, then pop in a post-frame callback.
    setState(() {
      _isMinimizing = true;
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Navigator.of(context).pop();
    });
  }

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
          // BetterPlayer disables the wakelock when its fullscreen route
          // pops. Re-assert here so the screen doesn't fall asleep mid-
          // session if the user lingers on the inline player or PDF.
          WakelockPlus.enable();
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
                // Notes button - leaves fullscreen and shows the notes PDF
                // on the right of the video (study mode). Same visibility
                // rules as the back button.
                Positioned(
                  top: 16,
                  right: 16,
                  child: SafeArea(
                    child: AnimatedOpacity(
                      opacity: _controlsVisible ? 1.0 : 0.0,
                      duration: const Duration(milliseconds: 300),
                      child: IgnorePointer(
                        ignoring: !_controlsVisible,
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            onTap: _enterStudyModeFromFullscreen,
                            borderRadius: BorderRadius.circular(24),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 14, vertical: 8),
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.6),
                                borderRadius: BorderRadius.circular(24),
                              ),
                              child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.menu_book,
                                      color: Colors.white, size: 22),
                                  SizedBox(width: 8),
                                  Text(
                                    'Notes',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 15,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
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

  /// Leaves BetterPlayer's fullscreen route and switches to study mode:
  /// landscape + immersive, video on the left, notes PDF on the right.
  /// Opens the document picker first when no PDF is open yet.
  Future<void> _enterStudyModeFromFullscreen() async {
    final controller = _playerController;
    if (controller == null) return;

    // BetterPlayer restores portrait + visible system bars the moment its
    // fullscreen route pops, which flashed the screen to portrait before our
    // landscape lock landed. Tell it to keep landscape + hidden bars for this
    // one exit instead. Cleared in `finally` so normal fullscreen exits are
    // unchanged.
    controller.deviceOrientationsAfterFullScreenOverride = const [
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ];
    controller.systemOverlaysAfterFullScreenOverride = const <SystemUiOverlay>[];
    try {
      controller.exitFullScreen();
      // Wait for BetterPlayer to pop its fullscreen route...
      for (var i = 0; i < 30 && controller.isFullScreen; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      // ...and to finish its own (now landscape-preserving) reset.
      await Future<void>.delayed(const Duration(milliseconds: 500));
      if (!mounted || _isDisposed) return;

      await _applyStudyModeChrome();
      if (!mounted || _isDisposed) return;
      setState(() => _isStudyMode = true);
    } finally {
      controller.deviceOrientationsAfterFullScreenOverride = null;
      controller.systemOverlaysAfterFullScreenOverride = null;
    }

    if (_activeDocument == null && mounted) {
      _openDocumentPicker();
    }
  }

  Future<void> _applyStudyModeChrome() async {
    await SystemChrome.setPreferredOrientations(const [
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  /// Leaves study mode and returns to the normal (portrait) layout. The PDF
  /// stays open in the split view if one was chosen.
  Future<void> _exitStudyMode() async {
    if (!_isStudyMode) return;
    await SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.manual,
      overlays: SystemUiOverlay.values,
    );
    await SystemChrome.setPreferredOrientations(_isSplitViewActive
        ? const [
            DeviceOrientation.portraitUp,
            DeviceOrientation.portraitDown,
            DeviceOrientation.landscapeLeft,
            DeviceOrientation.landscapeRight,
          ]
        : ResponsiveHelper.supportedOrientationsForDevice());
    if (mounted) setState(() => _isStudyMode = false);
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
  // Split-View PDF
  // ---------------------------------------------------------------------------

  void _openDocumentPicker() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => DocumentPickerSheet(
        onDocumentSelected: (doc) {
          // In study mode the layout stays locked to landscape.
          if (!_isStudyMode) {
            SystemChrome.setPreferredOrientations([
              DeviceOrientation.portraitUp,
              DeviceOrientation.portraitDown,
              DeviceOrientation.landscapeLeft,
              DeviceOrientation.landscapeRight,
            ]);
          }
          setState(() {
            _activeDocument = doc;
            _isSplitViewActive = true;
          });
        },
      ),
    ).then((_) {
      // Picker dismissed without a choice while in study mode: nothing to
      // show beside the video, so go back to the normal layout.
      if (mounted && _isStudyMode && _activeDocument == null) {
        _exitStudyMode();
      }
    });
  }

  void _closeSplitView() {
    setState(() {
      _isSplitViewActive = false;
      _activeDocument = null;
    });
    if (_isStudyMode) {
      // Closing the PDF also ends study mode (restores UI + orientation).
      // Runs after the split state is cleared so the device-appropriate
      // orientations are restored, not the split-view ones.
      _exitStudyMode();
    } else {
      SystemChrome.setPreferredOrientations(
          ResponsiveHelper.supportedOrientationsForDevice());
    }
  }

  Widget _buildSplitView() {
    return OrientationBuilder(
      builder: (context, orientation) {
        final axis = orientation == Orientation.portrait
            ? Axis.vertical
            : Axis.horizontal;
        return ResizableSplitView(
          key: const ValueKey('video-pdf-split'),
          axis: axis,
          initialRatio: 0.4,
          minRatio: 0.25,
          maxRatio: 0.75,
          // Side by side (landscape), keep the PDF pane wide enough for the
          // reader's toolbar and annotation bar. Without this, a video made
          // large in portrait kept the same ratio on rotation and squeezed
          // the reader to ~25% of the width, cutting off its buttons.
          minSecondExtent: axis == Axis.horizontal ? 360 : 0,
          firstChild: _buildSplitPlayerArea(),
          // Full pdfrx reader in embedded mode: highlight, underline, notes,
          // undo, bookmarks and search all work inside the split pane.
          // Keyed by document so switching documents rebuilds the reader.
          secondChild: pdfrx_reader.PdfViewerScreen(
            key: ValueKey('split-pdf-${_activeDocument!.id}'),
            documentId: _activeDocument!.id,
            source: _activeDocument!.source == DocumentSource.ebook
                ? 'ebook'
                : null,
            title: _activeDocument!.title,
            embedded: true,
            onClose: _closeSplitView,
          ),
        );
      },
    );
  }

  /// Player area for split view — wraps in a black Container so the
  /// AspectRatio scales down within the flex-allocated space.
  Widget _buildSplitPlayerArea() {
    Widget area;
    if (_playerController != null && _isPlayerInitialized) {
      area = Container(
        color: Colors.black,
        child: Center(
          child: AspectRatio(
            aspectRatio: 16 / 9,
            child: BetterPlayer(controller: _playerController!),
          ),
        ),
      );
    } else {
      // Loading / error state — simple centered indicator, no fixed aspect ratio
      area = Container(
        color: Colors.black,
        child: const Center(
          child: CircularProgressIndicator(color: Colors.white),
        ),
      );
    }

    if (!_isStudyMode) return area;

    // Study mode hides the app chrome, so give the student a way out.
    return Stack(
      children: [
        Positioned.fill(child: area),
        Positioned(
          top: 8,
          left: 8,
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: _exitStudyMode,
              borderRadius: BorderRadius.circular(20),
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Icon(Icons.fullscreen_exit,
                    color: Colors.white, size: 24),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildOpenDocumentButton() {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: _openDocumentPicker,
        icon: const Icon(Icons.menu_book, size: 18),
        label: const Text('Read Notes Alongside'),
        style: OutlinedButton.styleFrom(
          foregroundColor: Colors.white70,
          side: const BorderSide(color: Colors.white24),
          padding: const EdgeInsets.symmetric(vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
        ),
      ),
    );
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

        // Leave study mode first (back to the normal split/inline layout)
        if (_isStudyMode) {
          await _exitStudyMode();
          return;
        }

        // Close split view first, then back exits the screen
        if (_isSplitViewActive) {
          _closeSplitView();
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
          child: _isSplitViewActive && _activeDocument != null
              ? _buildSplitView()
              : _isStudyMode
                  // Study mode while the document picker is still open: just
                  // the video, full area, until a PDF is chosen.
                  ? Container(
                      color: Colors.black,
                      child: _buildSplitPlayerArea(),
                    )
              : OrientationBuilder(
                  builder: (context, orientation) {
                    // On a tablet in landscape, place video and info side by
                    // side so the description, rating, feedback, and
                    // "Read Notes Alongside" stay reachable. Phones and
                    // portrait tablets keep the original stacked layout.
                    final useSideBySide =
                        orientation == Orientation.landscape &&
                            ResponsiveHelper.isTablet(context);
                    if (!useSideBySide) {
                      return Column(
                        children: [
                          _buildPlayerArea(),
                          if (!_isLoading && _error == null)
                            Expanded(child: _buildVideoInfo()),
                        ],
                      );
                    }
                    return Row(
                      children: [
                        Expanded(
                          flex: 6,
                          child: Container(
                            color: Colors.black,
                            child: Center(child: _buildPlayerArea()),
                          ),
                        ),
                        if (!_isLoading && _error == null)
                          Expanded(flex: 4, child: _buildVideoInfo()),
                      ],
                    );
                  },
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
    // Returns a bare scrollable container (no Expanded wrapper) so callers
    // can compose it into either a Column or a Row with their own flex.
    return Container(
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
                  // TODO: Minimize button — disabled until mini player pop issue is resolved
                  // GestureDetector(
                  //   onTap: _minimizeAndGoBack,
                  //   child: Container(
                  //     padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  //     decoration: BoxDecoration(
                  //       color: Colors.white12,
                  //       borderRadius: BorderRadius.circular(8),
                  //     ),
                  //     child: const Text(
                  //       'Minimize',
                  //       style: TextStyle(
                  //         color: Colors.white,
                  //         fontSize: 13,
                  //         fontWeight: FontWeight.w500,
                  //         fontFamily: 'Poppins',
                  //       ),
                  //     ),
                  //   ),
                  // ),
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
              if (_videoDescription != null &&
                  _videoDescription!.trim().isNotEmpty) ...[
                const SizedBox(height: 16),
                Text(
                  _videoDescription!,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 14,
                    fontFamily: 'Poppins',
                    height: 1.5,
                  ),
                ),
              ],
              const SizedBox(height: 20),
              _buildOpenDocumentButton(),
              const SizedBox(height: 28),
              _buildRatingSection(),
              const SizedBox(height: 24),
              _buildFeedbackSection(),
              const SizedBox(height: 32),
            ],
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
