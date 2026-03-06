import 'package:better_player_plus/better_player_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

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

class _TrailerVideoPlayerScreenState extends State<TrailerVideoPlayerScreen> {
  BetterPlayerController? _playerController;
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _initializePlayer();
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
        fit: BoxFit.contain,
        controlsConfiguration: const BetterPlayerControlsConfiguration(
          enableProgressText: true,
          enableFullscreen: true,
          enablePlayPause: true,
          enableMute: true,
          enableSkips: false,
          enableProgressBar: true,
          enablePlaybackSpeed: true,
          enableOverflowMenu: true,
        ),
      );

      _playerController = BetterPlayerController(configuration);
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

  @override
  void dispose() {
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
