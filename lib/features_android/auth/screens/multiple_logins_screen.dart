import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:pgme/core_android/widgets/app_dialog.dart';
import 'package:pgme/features_android/auth/providers/auth_provider.dart';
import 'package:pgme/core_android/utils/responsive_helper.dart';

class MultipleLoginsScreen extends StatefulWidget {
  const MultipleLoginsScreen({super.key});

  @override
  State<MultipleLoginsScreen> createState() => _MultipleLoginsScreenState();
}

class _MultipleLoginsScreenState extends State<MultipleLoginsScreen>
    with SingleTickerProviderStateMixin {
  bool _isLoading = false;
  bool _isLoggingOut = false;
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeOut),
    );

    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.1),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeOut),
    );

    _animationController.forward();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  Future<void> _logoutDevice(String sessionId) async {
    setState(() => _isLoggingOut = true);
    try {
      await context.read<AuthProvider>().logoutDeviceSession(sessionId);
      if (mounted) {
        showAppDialog(context, message: 'Device logged out successfully', type: AppDialogType.success);
      }
    } catch (e) {
      if (mounted) {
        showAppDialog(context, message: e.toString().replaceAll('Exception: ', ''));
      }
    } finally {
      if (mounted) {
        setState(() => _isLoggingOut = false);
      }
    }
  }

  Future<void> _continue() async {
    setState(() => _isLoading = true);
    try {
      final provider = context.read<AuthProvider>();
      provider.clearMultipleSessionsFlag();

      if (mounted) {
        if (provider.onboardingCompleted) {
          // Old user - go to dashboard
          context.go('/home');
        } else {
          // New user - go to subject selection
          context.go('/subject-selection');
        }
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  String _formatLastActive(String? lastActive) {
    if (lastActive == null) return 'Unknown';
    try {
      final date = DateTime.parse(lastActive);
      final now = DateTime.now();
      final difference = now.difference(date);

      if (difference.inMinutes < 5) {
        return 'Active now';
      } else if (difference.inMinutes < 60) {
        return 'Active ${difference.inMinutes} mins ago';
      } else if (difference.inHours < 24) {
        return 'Active ${difference.inHours} hours ago';
      } else {
        return 'Active ${difference.inDays} days ago';
      }
    } catch (e) {
      return lastActive;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isTablet = ResponsiveHelper.isTablet(context);

    return Scaffold(
      backgroundColor: const Color(0xFF0000D1),
      body: Container(
        width: double.infinity,
        height: double.infinity,
        color: const Color(0xFF0000D1),
        child: SafeArea(
          child: FadeTransition(
            opacity: _fadeAnimation,
            child: SlideTransition(
              position: _slideAnimation,
              child: Center(
                child: SingleChildScrollView(
                  padding: EdgeInsets.symmetric(
                    horizontal: isTablet ? 32 : 24,
                    vertical: 20,
                  ),
                  child: _buildMainCard(isTablet),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMainCard(bool isTablet) {
    // Responsive sizes
    final cardWidth = isTablet ? 520.0 : 327.0;
    final cardPaddingH = isTablet ? 20.0 : 10.0;
    final cardPaddingV = isTablet ? 36.0 : 28.0;
    final cardRadius = isTablet ? 24.0 : 16.0;
    final iconBoxSize = isTablet ? 100.0 : 80.0;
    final iconBoxRadius = isTablet ? 28.0 : 20.0;
    final iconSize = isTablet ? 52.0 : 40.0;
    final titleSize = isTablet ? 32.0 : 24.0;
    final subtitleSize = isTablet ? 18.0 : 14.0;
    final btnWidth = isTablet ? 440.0 : 275.0;
    final btnHeight = isTablet ? 68.0 : 56.0;
    final btnFontSize = isTablet ? 20.0 : 16.0;
    final btnRadius = isTablet ? 32.0 : 24.0;

    return Consumer<AuthProvider>(
      builder: (context, provider, _) {
        // Get other ACTIVE sessions (exclude current session)
        final otherSessions = provider.activeSessions.where(
          (s) => s['session_id'] != provider.currentSessionId &&
                 s['is_active'] == true,
        ).toList();

        return Container(
          width: cardWidth,
          padding: EdgeInsets.only(
            top: cardPaddingV,
            right: cardPaddingH,
            bottom: cardPaddingV,
            left: cardPaddingH,
          ),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(cardRadius),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.15),
                blurRadius: 40,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Warning Icon - Red hexagon with exclamation
              Container(
                width: iconBoxSize,
                height: iconBoxSize,
                decoration: BoxDecoration(
                  color: const Color(0xFFEF6B6B),
                  borderRadius: BorderRadius.circular(iconBoxRadius),
                ),
                child: Center(
                  child: Icon(
                    Icons.priority_high_rounded,
                    size: iconSize,
                    color: Colors.white,
                  ),
                ),
              ),
              const SizedBox(height: 24),
              // Title
              SizedBox(
                width: cardWidth - 60,
                child: Text(
                  'Multiple Logins\nDetected',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: titleSize,
                    fontWeight: FontWeight.w700,
                    height: 32 / 24,
                    letterSpacing: 0.12,
                    color: const Color(0xFF000000),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              // Subtitle
              SizedBox(
                width: cardWidth - 20,
                child: Text(
                  otherSessions.isEmpty
                      ? 'You can now continue to the app'
                      : 'Log Out from any one of the devices',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: subtitleSize,
                    fontWeight: FontWeight.w500,
                    height: 22 / 14,
                    letterSpacing: 0.07,
                    color: const Color(0xFF666666),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              // Device Cards
              if (otherSessions.isEmpty)
                _buildAllLoggedOutBanner(isTablet)
              else
                ...otherSessions.asMap().entries.map((entry) {
                  final index = entry.key;
                  final session = entry.value;
                  return Padding(
                    padding: EdgeInsets.only(
                      bottom: index < otherSessions.length - 1 ? (isTablet ? 12 : 8) : 0,
                    ),
                    child: _buildDeviceCard(session, isTablet),
                  );
                }),
              const SizedBox(height: 24),
              // Continue Button
              _buildContinueButton(
                isEnabled: otherSessions.isEmpty,
                isTablet: isTablet,
                btnWidth: btnWidth,
                btnHeight: btnHeight,
                btnFontSize: btnFontSize,
                btnRadius: btnRadius,
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildAllLoggedOutBanner(bool isTablet) {
    return Container(
      padding: EdgeInsets.all(isTablet ? 20 : 16),
      decoration: BoxDecoration(
        color: const Color(0xFFE8F5E9),
        borderRadius: BorderRadius.circular(isTablet ? 16 : 12),
      ),
      child: Row(
        children: [
          Icon(Icons.check_circle, color: Colors.green, size: isTablet ? 28 : 24),
          SizedBox(width: isTablet ? 16 : 12),
          Expanded(
            child: Text(
              'All other devices have been logged out',
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: isTablet ? 16 : 14,
                color: const Color(0xFF2E7D32),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDeviceCard(Map<String, dynamic> session, bool isTablet) {
    final deviceName = session['device_name'] ?? 'Unknown Device';
    final lastActive = session['last_active'] as String?;
    final sessionId = session['session_id'] as String?;

    final cardHeight = isTablet ? 86.0 : 72.29;
    final cardRadius = isTablet ? 32.0 : 27.45;
    final deviceNameSize = isTablet ? 17.0 : 14.0;
    final lastActiveSize = isTablet ? 14.0 : 12.0;
    final logoutBtnSize = isTablet ? 44.0 : 36.0;
    final logoutIconSize = isTablet ? 22.0 : 18.31;
    final logoutBtnRadius = isTablet ? 12.0 : 8.0;

    return Container(
      width: double.infinity,
      height: cardHeight,
      padding: EdgeInsets.symmetric(
        horizontal: isTablet ? 24 : 20,
        vertical: isTablet ? 16 : 14,
      ),
      decoration: BoxDecoration(
        color: const Color(0xFFF5F5F5),
        borderRadius: BorderRadius.circular(cardRadius),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          // Device info - centered
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Text(
                  deviceName,
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: deviceNameSize,
                    fontWeight: FontWeight.w500,
                    color: const Color(0xFF000000),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  'Last active ${_formatLastActive(lastActive).replaceAll('Active ', '')}',
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: lastActiveSize,
                    fontWeight: FontWeight.w400,
                    color: const Color(0xFF888888),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          // Logout button - exit icon
          GestureDetector(
            onTap: _isLoggingOut || sessionId == null
                ? null
                : () => _logoutDevice(sessionId),
            child: Container(
              width: logoutBtnSize,
              height: logoutBtnSize,
              decoration: BoxDecoration(
                color: const Color(0xFF0000D1),
                borderRadius: BorderRadius.circular(logoutBtnRadius),
              ),
              child: Center(
                child: _isLoggingOut
                    ? SizedBox(
                        width: logoutIconSize,
                        height: logoutIconSize,
                        child: const CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                        ),
                      )
                    : Icon(
                        Icons.exit_to_app_rounded,
                        size: logoutIconSize,
                        color: Colors.white,
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContinueButton({
    required bool isEnabled,
    required bool isTablet,
    required double btnWidth,
    required double btnHeight,
    required double btnFontSize,
    required double btnRadius,
  }) {
    final canContinue = isEnabled && !_isLoading;

    return GestureDetector(
      onTap: canContinue ? _continue : null,
      child: Container(
        width: btnWidth,
        height: btnHeight,
        decoration: BoxDecoration(
          color: const Color(0xFF0000D1),
          borderRadius: BorderRadius.circular(btnRadius),
        ),
        child: Center(
          child: _isLoading
              ? SizedBox(
                  width: isTablet ? 28 : 24,
                  height: isTablet ? 28 : 24,
                  child: const CircularProgressIndicator(
                    strokeWidth: 2.5,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                )
              : Text(
                  'Continue',
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: btnFontSize,
                    fontWeight: FontWeight.w600,
                    height: 1.0,
                    letterSpacing: 0.08,
                    color: Colors.white,
                  ),
                ),
        ),
      ),
    );
  }
}
