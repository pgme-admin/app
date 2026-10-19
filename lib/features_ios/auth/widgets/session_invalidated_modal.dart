import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:pgme/features_ios/auth/providers/auth_provider.dart';
import 'package:pgme/core_ios/utils/responsive_helper.dart';

class SessionInvalidatedModal extends StatelessWidget {
  const SessionInvalidatedModal({super.key});

  @override
  Widget build(BuildContext context) {
    final isTablet = ResponsiveHelper.isTablet(context);

    return PopScope(
      canPop: false, // Prevent back button from dismissing
      child: Material(
        color: Colors.black.withValues(alpha: 0.7),
        child: Center(
          child: Container(
            width: isTablet ? 480 : 320,
            margin: const EdgeInsets.symmetric(horizontal: 24),
            padding: EdgeInsets.all(isTablet ? 32 : 24),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(isTablet ? 24 : 16),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Warning Icon
                Container(
                  width: isTablet ? 80 : 64,
                  height: isTablet ? 80 : 64,
                  decoration: BoxDecoration(
                    color: const Color(0xFFEF6B6B),
                    borderRadius: BorderRadius.circular(isTablet ? 20 : 16),
                  ),
                  child: Icon(
                    Icons.info_outline_rounded,
                    size: isTablet ? 44 : 36,
                    color: Colors.white,
                  ),
                ),
                SizedBox(height: isTablet ? 24 : 20),

                // Title
                Text(
                  'Session Ended',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: isTablet ? 26 : 22,
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFF000000),
                  ),
                ),
                SizedBox(height: isTablet ? 12 : 10),

                // Message
                Text(
                  'Your account was logged in from another device. You have been logged out from this device.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: isTablet ? 16 : 14,
                    fontWeight: FontWeight.w400,
                    height: 1.5,
                    color: const Color(0xFF666666),
                  ),
                ),
                SizedBox(height: isTablet ? 32 : 24),

                // Logout Button
                SizedBox(
                  width: double.infinity,
                  height: isTablet ? 56 : 48,
                  child: ElevatedButton(
                    onPressed: () async {
                      final authProvider = context.read<AuthProvider>();
                      await authProvider.handleSessionInvalidationLogout();
                      if (context.mounted) {
                        context.go('/login');
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF0000D1),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(isTablet ? 28 : 24),
                      ),
                      elevation: 0,
                    ),
                    child: Text(
                      'Okay',
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: isTablet ? 18 : 16,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
