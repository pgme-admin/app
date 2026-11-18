import 'package:better_player_plus/better_player_plus.dart';
import 'package:flutter/material.dart';
import 'package:pgme/core/services/offline_storage_service.dart';

/// Global provider that keeps the video player alive across route changes.
///
/// When the user minimizes the video player, this provider retains the
/// [BetterPlayerController] so playback continues while the mini-player
/// bar is visible. When the user expands the mini-player, [VideoPlayerScreen]
/// reuses the existing controller from here.
class MiniPlayerProvider extends ChangeNotifier with WidgetsBindingObserver {
  BetterPlayerController? _controller;
  String? _videoId;
  String? _videoTitle;
  String? _videoDescription;
  int _videoDurationSeconds = 0;
  bool _isMinimized = false;

  // Carried over from VideoPlayerScreen so it can be restored on expand
  int _watchTimeSeconds = 0;

  // ── Getters ──────────────────────────────────────────────────────────────

  BetterPlayerController? get controller => _controller;
  String? get videoId => _videoId;
  String? get videoTitle => _videoTitle;
  String? get videoDescription => _videoDescription;
  int get videoDurationSeconds => _videoDurationSeconds;
  bool get isMinimized => _isMinimized;
  bool get isActive => _controller != null;
  int get watchTimeSeconds => _watchTimeSeconds;

  MiniPlayerProvider() {
    WidgetsBinding.instance.addObserver(this);
  }

  // ── Lifecycle ────────────────────────────────────────────────────────────

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Only handle lifecycle when we truly own the player (minimized state).
    // When VideoPlayerScreen is open, it handles its own lifecycle.
    if (!_isMinimized || _controller == null) return;

    // Pause only when the app really leaves the screen (paused / hidden).
    // `inactive` also fires on Android when the notification shade is pulled
    // down or another split-screen app is tapped, which stopped the lecture
    // and never resumed it.
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      _controller?.pause();
    }
    if (state == AppLifecycleState.detached) {
      close();
    }
  }

  // ── Public API ───────────────────────────────────────────────────────────

  /// Called by [VideoPlayerScreen] after initializing a controller.
  /// Registers the controller so it can survive route pops.
  void registerController({
    required BetterPlayerController controller,
    required String videoId,
    String? videoTitle,
    String? videoDescription,
    int videoDurationSeconds = 0,
    int watchTimeSeconds = 0,
  }) {
    // Switching to a different video — clean up the old one
    BetterPlayerController? oldController;
    if (_videoId != null && _videoId != videoId && _controller != null) {
      _saveProgressBeforeClose();
      oldController = _controller;
      oldController!.pause();
    }

    // Update state and notify *first* so widgets stop referencing the old
    // controller before we dispose it.
    _controller = controller;
    _videoId = videoId;
    _videoTitle = videoTitle;
    _videoDescription = videoDescription;
    _videoDurationSeconds = videoDurationSeconds;
    _watchTimeSeconds = watchTimeSeconds;
    _isMinimized = false;
    notifyListeners();

    // Now safe to dispose — no widget references the old controller.
    oldController?.dispose();
  }

  /// Update metadata that may arrive after registration (e.g. from API).
  void updateMetadata({
    String? videoTitle,
    String? videoDescription,
    int? videoDurationSeconds,
  }) {
    if (videoTitle != null) _videoTitle = videoTitle;
    if (videoDescription != null) _videoDescription = videoDescription;
    if (videoDurationSeconds != null) {
      _videoDurationSeconds = videoDurationSeconds;
    }
    notifyListeners();
  }

  /// Save the accumulated watch-time so it can be restored on expand.
  void updateWatchTime(int seconds) {
    _watchTimeSeconds = seconds;
  }

  /// Transition to minimized state — video keeps playing in the mini bar.
  void minimize() {
    if (_controller == null) return;
    _isMinimized = true;
    notifyListeners();
  }

  /// Transition back to full-screen player.
  void expand() {
    _isMinimized = false;
    notifyListeners();
  }

  /// Stop playback, persist progress, and release the controller entirely.
  void close() {
    _saveProgressBeforeClose();
    _controller?.pause();
    _controller?.dispose();
    _controller = null;
    _videoId = null;
    _videoTitle = null;
    _videoDescription = null;
    _videoDurationSeconds = 0;
    _watchTimeSeconds = 0;
    _isMinimized = false;
    notifyListeners();
  }

  /// Read the current playback position from the live controller and persist
  /// it locally so the user can resume later.
  void _saveProgressBeforeClose() {
    if (_controller == null || _videoId == null) return;

    final vpCtrl = _controller!.videoPlayerController;
    if (vpCtrl == null) return;

    final value = vpCtrl.value;
    final positionSeconds = value.position.inSeconds;
    final duration = _videoDurationSeconds > 0
        ? _videoDurationSeconds
        : (value.duration?.inSeconds ?? 0);

    if (duration <= 0) return;

    final completionPercentage =
        ((positionSeconds / duration) * 100).round().clamp(0, 100);
    final isCompleted = completionPercentage >= 90;

    debugPrint(
        'MiniPlayer: saving progress before close pos=${positionSeconds}s');

    // Fire-and-forget local save
    OfflineStorageService().saveVideoProgress(
      _videoId!, positionSeconds, duration, isCompleted,
    );
    OfflineStorageService().saveLastWatchedVideo({
      'video_id': _videoId!,
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
  }

  // ── Route-aware auto-close ───────────────────────────────────────────────

  /// Route prefixes where the mini player is allowed to keep playing.
  /// Any navigation to a route NOT matching these prefixes will close it.
  static const _allowedRoutePrefixes = [
    '/home',
    '/revision-series',
    '/practical-series',
    '/your-notes',
    '/notes',
    '/available-notes',
    '/course',
    '/series-detail',
    '/enrolled-course',
    '/lecture',
    '/session',
    '/series-sessions',
    '/settings',
    '/profile',
    '/edit-profile',
    '/downloads',
    '/notifications',
    '/help',
    '/about',
    '/my-records',
    '/careers',
    '/video', // VideoPlayerScreen handles adoption/replacement itself
    // NOTE: '/pdf-viewer' intentionally NOT in this list. Opening a fullscreen
    // PDF must release the video player so the heap has room for Syncfusion.
    // The PDF viewer screens additionally call MiniPlayerProvider.close() in
    // initState as a belt-and-suspenders.
  ];

  /// Called on every route change. Closes the mini player if the new route
  /// is not in the allowed list (e.g. payment, auth, policy, trailer, etc.).
  void closeIfRouteRestricted(String path) {
    if (!_isMinimized || _controller == null) return;

    final isAllowed = _allowedRoutePrefixes.any(
      (prefix) => path == prefix || path.startsWith('$prefix/') || path.startsWith('$prefix?'),
    );

    if (!isAllowed) {
      debugPrint('MiniPlayer: closing — route "$path" is not allowed');
      close();
    }
  }

  /// Detach without disposing — used when [VideoPlayerScreen] fully owns
  /// the controller again and will dispose it on its own.
  void unregister() {
    _controller = null;
    _videoId = null;
    _videoTitle = null;
    _videoDescription = null;
    _videoDurationSeconds = 0;
    _watchTimeSeconds = 0;
    _isMinimized = false;
    notifyListeners();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller?.pause();
    _controller?.dispose();
    super.dispose();
  }
}
