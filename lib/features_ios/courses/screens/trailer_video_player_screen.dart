import 'package:better_player_plus/better_player_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:pgme/core_ios/utils/responsive_helper.dart';

class TrailerVideoPlayerScreen extends StatefulWidget {
  final String videoUrl;
  final String videoTitle;

  const TrailerVideoPlayerScreen({
    super.key,
    required this.videoUrl,
    required this.videoTitle,
  });

  @override
  State<TrailerVideoPlayerScreen> createState() => _TrailerVideoPlayerScreenState();
}

class _TrailerVideoPlayerScreenState extends State<TrailerVideoPlayerScreen> with WidgetsBindingObserver {
  BetterPlayerController? _playerController;
  bool _isLoading = true;
  String? _error;

  // Preserves the user's chosen playback speed across pause/resume.
  // better_player_plus can reset the native playback rate on pause; we cache
  // the value set via the controls and reapply on play.
  double _currentSpeed = 1.0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initializePlayer();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
      _playerController?.pause();
    }
  }

  @override
  void deactivate() {
    _playerController?.pause();
    super.deactivate();
  }

  Future<void> _initializePlayer() async {
    try {
      // Lock orientation to landscape for better viewing
      await SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
        DeviceOrientation.portraitUp,
      ]);

      // Configure player
      final dataSource = BetterPlayerDataSource(
        BetterPlayerDataSourceType.network,
        widget.videoUrl,
        notificationConfiguration: BetterPlayerNotificationConfiguration(
          showNotification: false,
        ),
      );

      final configuration = BetterPlayerConfiguration(
        aspectRatio: 9 / 16, // Portrait video aspect ratio
        autoPlay: true,
        looping: false,
        fullScreenByDefault: false,
        handleLifecycle: true,
        fit: BoxFit.contain,
        controlsConfiguration: const BetterPlayerControlsConfiguration(
          enableProgressText: true,
          enableFullscreen: true,
          enablePlayPause: true,
          enableMute: true,
          enableSkips: false,
          enableProgressBar: true,
          enablePlaybackSpeed: true,
          enableAudioTracks: false,
          enableOverflowMenu: true,
        ),
      );

      _playerController = BetterPlayerController(configuration);
      _playerController!.addEventsListener(_onPlayerEvent);
      await _playerController!.setupDataSource(dataSource);

      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Failed to load video: $e';
          _isLoading = false;
        });
      }
    }
  }

  void _onPlayerEvent(BetterPlayerEvent event) {
    switch (event.betterPlayerEventType) {
      case BetterPlayerEventType.setSpeed:
        final speed = (event.parameters?['speed'] as num?)?.toDouble();
        if (speed != null && speed > 0) {
          _currentSpeed = speed;
        }
        break;
      case BetterPlayerEventType.play:
        final actualSpeed =
            _playerController?.videoPlayerController?.value.speed ?? 1.0;
        if ((actualSpeed - _currentSpeed).abs() > 0.001) {
          _playerController?.setSpeed(_currentSpeed);
        }
        break;
      default:
        break;
    }
  }

  @override
  void dispose() {
    // Restore device-appropriate orientations on the way out (iPads get
    // landscape back, iPhones stay portrait). Goes through the shared helper
    // so this stays consistent with main_*.dart and the lecture player.
    SystemChrome.setPreferredOrientations(
        ResponsiveHelper.supportedOrientationsForDevice());

    WidgetsBinding.instance.removeObserver(this);
    _playerController?.pause();
    _playerController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        leading: IconButton(
          icon: const Icon(Icons.close, color: Colors.white),
          onPressed: () => context.pop(),
        ),
        title: Text(
          widget.videoTitle,
          style: const TextStyle(color: Colors.white),
        ),
      ),
      body: Center(
        child: _isLoading
            ? const CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
              )
            : _error != null
                ? Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(
                          Icons.error_outline,
                          color: Colors.red,
                          size: 48,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          _error!,
                          style: const TextStyle(color: Colors.white),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 16),
                        ElevatedButton(
                          onPressed: () => context.pop(),
                          child: const Text('Go Back'),
                        ),
                      ],
                    ),
                  )
                : _playerController != null
                    ? AspectRatio(
                        aspectRatio: 9 / 16, // Portrait aspect ratio
                        child: BetterPlayer(controller: _playerController!),
                      )
                    : const SizedBox.shrink(),
      ),
    );
  }
}
