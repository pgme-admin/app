import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:pgme/core_ios/services/storage_service.dart';
import 'package:pgme/features_ios/onboarding/providers/onboarding_provider.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final PageController _pageController = PageController();

  // Dark blue background color matching the design
  static const Color _darkBlue = Color(0xFF0033CC);
  static const Color _buttonColor = Color(0xFF00C2FF);

  final List<OnboardingData> _pages = [
    OnboardingData(
      title: 'Postgraduate Medical\nExcellence',
      subtitle: 'Access structured residency courses specifically designed for MD/DNB candidates and faculty. The curriculum focuses on mastery of core medical concepts through expert-led modules.',
      illustration: 'assets/illustrations/1.png',
    ),
    OnboardingData(
      title: 'Interactive Training\n& Resources',
      subtitle: 'Join interactive live sessions or access high-yield recorded lectures at any time. Detailed revision notes and study materials are provided to ensure a comprehensive preparation experience.',
      illustration: 'assets/illustrations/2.png',
    ),
    OnboardingData(
      title: 'Redefining Medical\nEducation',
      subtitle: 'PGME serves as a comprehensive learning companion for postgraduate medical training. The platform empowers medical professionals with realistic assessment scenarios and up-to-date content to excel in clinical careers.',
      illustration: 'assets/illustrations/3.png',
    ),
  ];

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _onPageChanged(int page) {
    context.read<OnboardingProvider>().setCurrentPage(page);
  }

  Future<void> _onSkip() async {
    await StorageService().saveIntroSeen(true);
    if (mounted) {
      context.go('/login');
    }
  }

  Future<void> _onContinue() async {
    final provider = context.read<OnboardingProvider>();
    if (provider.currentPage < _pages.length - 1) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    } else {
      await StorageService().saveIntroSeen(true);
      if (mounted) {
        context.go('/login');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.of(context).padding.bottom;
    final screenSize = MediaQuery.of(context).size;
    final shortestSide = screenSize.shortestSide;
    final isTablet = shortestSide >= 600;
    final isLandscape = screenSize.width > screenSize.height;

    // Tablet-scaled sizes
    final logoWidth = isTablet ? 72.0 : 52.0;
    final logoHeight = isTablet ? 46.0 : 33.0;
    final skipFontSize = isTablet ? 20.0 : 16.0;
    final topBarHPadding = isTablet ? 32.0 : 20.0;
    final topBarVPadding = isTablet ? 20.0 : 16.0;
    final dotHeight = isTablet ? 10.0 : 8.0;
    final dotActiveWidth = isTablet ? 30.0 : 24.0;
    final dotInactiveWidth = isTablet ? 10.0 : 8.0;
    final dotSpacing = isTablet ? 10.0 : 8.0;
    final buttonWidth = isTablet ? 500.0 : 325.0;
    final buttonHeight = isTablet ? 68.0 : 50.0;
    final buttonFontSize = isTablet ? 21.0 : 15.0;
    final termsFontSize = isTablet ? 15.0 : 12.0;
    final termsWidth = isTablet ? 420.0 : 327.0;
    final indicatorBtnGap = isTablet ? 32.0 : 24.0;
    final btnTermsGap = isTablet ? 20.0 : 16.0;
    final bottomPaddingExtra = isTablet ? 28.0 : 20.0;

    return Scaffold(
      backgroundColor: _darkBlue,
      body: SafeArea(
        child: Column(
          children: [
            // Top bar with Logo and Skip button
            Padding(
              padding: EdgeInsets.symmetric(horizontal: topBarHPadding, vertical: topBarVPadding),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // Logo in top left
                  Image.asset(
                    'assets/illustrations/pgme.png',
                    width: logoWidth,
                    height: logoHeight,
                    fit: BoxFit.contain,
                    errorBuilder: (context, error, stackTrace) {
                      return SizedBox(height: logoHeight, width: logoWidth);
                    },
                  ),
                  // Skip button
                  GestureDetector(
                    onTap: _onSkip,
                    child: Text(
                      'Skip',
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: skipFontSize,
                        fontWeight: FontWeight.w500,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // PageView content
            Expanded(
              child: PageView.builder(
                controller: _pageController,
                onPageChanged: _onPageChanged,
                itemCount: _pages.length,
                itemBuilder: (context, index) {
                  return _OnboardingPage(
                    data: _pages[index],
                    index: index,
                    isTablet: isTablet,
                    isLandscape: isLandscape,
                  );
                },
              ),
            ),

            // Bottom section with indicators, button and terms
            Padding(
              padding: EdgeInsets.fromLTRB(25, 0, 25, bottomPadding + bottomPaddingExtra),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Page indicators
                  Consumer<OnboardingProvider>(
                    builder: (context, provider, _) {
                      return Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: List.generate(
                          _pages.length,
                          (index) => AnimatedContainer(
                            duration: const Duration(milliseconds: 300),
                            width: provider.currentPage == index ? dotActiveWidth : dotInactiveWidth,
                            height: dotHeight,
                            margin: EdgeInsets.only(
                              right: index < _pages.length - 1 ? dotSpacing : 0,
                            ),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(dotHeight / 2),
                              color: provider.currentPage == index
                                  ? _buttonColor
                                  : Colors.white.withValues(alpha: 0.4),
                            ),
                          ),
                        ),
                      );
                    },
                  ),

                  SizedBox(height: indicatorBtnGap),

                  // Continue/Get Started button
                  Consumer<OnboardingProvider>(
                    builder: (context, provider, _) {
                      final isLastPage = provider.currentPage == _pages.length - 1;
                      return GestureDetector(
                        onTap: _onContinue,
                        child: Container(
                          width: buttonWidth,
                          height: buttonHeight,
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: _buttonColor,
                            borderRadius: BorderRadius.circular(50),
                          ),
                          child: Center(
                            child: Text(
                              isLastPage ? 'Get Started' : 'Continue',
                              style: TextStyle(
                                fontFamily: 'Sora',
                                fontSize: buttonFontSize,
                                fontWeight: FontWeight.w600,
                                height: 1.0,
                                letterSpacing: 0,
                                color: const Color(0xFF0000D1),
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),

                  SizedBox(height: btnTermsGap),

                  // Terms and Privacy text
                  SizedBox(
                    width: termsWidth,
                    child: RichText(
                      textAlign: TextAlign.center,
                      text: TextSpan(
                        style: TextStyle(
                          fontFamily: 'Sora',
                          fontWeight: FontWeight.w400,
                          fontSize: termsFontSize,
                          height: 1.5,
                          color: Colors.white,
                        ),
                        children: [
                          const TextSpan(text: 'By continuing, you agree to our '),
                          TextSpan(
                            text: 'Terms of Service',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              color: Colors.white.withValues(alpha: 0.9),
                            ),
                          ),
                          const TextSpan(text: ' and\n'),
                          TextSpan(
                            text: 'Privacy Policy',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              color: Colors.white.withValues(alpha: 0.9),
                            ),
                          ),
                          const TextSpan(text: '.'),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OnboardingPage extends StatelessWidget {
  final OnboardingData data;
  final int index;
  final bool isTablet;
  final bool isLandscape;

  const _OnboardingPage({
    required this.data,
    required this.index,
    required this.isTablet,
    required this.isLandscape,
  });

  @override
  Widget build(BuildContext context) {
    // On landscape tablet, use side-by-side layout
    if (isTablet && isLandscape) {
      return _buildLandscapeTabletLayout(context);
    }
    return _buildPortraitLayout(context);
  }

  Widget _buildPortraitLayout(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final shortestSide = MediaQuery.of(context).size.shortestSide;

    // On tablet portrait, base circle on shortestSide for bigger display
    final circleSize = isTablet ? shortestSide * 0.62 : screenWidth * 0.85;

    final titleSize = isTablet ? 46.0 : 32.0;
    final subtitleSize = isTablet ? 17.0 : 12.0;
    final titleWidth = isTablet ? 560.0 : 355.0;
    final subtitleWidth = isTablet ? 540.0 : 341.0;
    final hPadding = isTablet ? 32.0 : 24.0;
    final topGap = isTablet ? 12.0 : 20.0;
    final titleTopGap = isTablet ? 48.0 : 40.0;
    final titleSubGap = isTablet ? 20.0 : 16.0;
    final errorIconSize = isTablet ? 130.0 : 100.0;

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: hPadding),
      child: Column(
        children: [
          SizedBox(height: topGap),

          // Illustration with circle background
          Expanded(
            flex: 4,
            child: Center(
              child: _buildCircleIllustration(circleSize, errorIconSize),
            ),
          ),

          // Text content
          Expanded(
            flex: isTablet ? 3 : 4,
            child: Column(
              mainAxisAlignment: isTablet ? MainAxisAlignment.center : MainAxisAlignment.start,
              children: [
                if (!isTablet) SizedBox(height: titleTopGap),
                // Title
                SizedBox(
                  width: titleWidth,
                  child: Text(
                    data.title,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: titleSize,
                      fontWeight: FontWeight.w700,
                      height: 1.0,
                      letterSpacing: 0,
                      color: Colors.white,
                    ),
                  ),
                ),

                SizedBox(height: titleSubGap),

                // Subtitle
                SizedBox(
                  width: subtitleWidth,
                  child: Text(
                    data.subtitle,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontFamily: 'Sora',
                      fontSize: subtitleSize,
                      fontWeight: FontWeight.w400,
                      height: 1.6,
                      letterSpacing: 0,
                      color: const Color(0xFF00C2FF),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLandscapeTabletLayout(BuildContext context) {
    final shortestSide = MediaQuery.of(context).size.shortestSide;

    // In landscape, height is the limiting factor for the circle
    final circleSize = shortestSide * 0.55;
    const titleSize = 44.0;
    const subtitleSize = 19.0;
    const errorIconSize = 120.0;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Row(
        children: [
          // Left: Illustration
          Expanded(
            flex: 5,
            child: Center(
              child: _buildCircleIllustration(circleSize, errorIconSize),
            ),
          ),

          const SizedBox(width: 24),

          // Right: Text content
          Expanded(
            flex: 5,
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Title
                  SizedBox(
                    width: 440,
                    child: Text(
                      data.title,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: titleSize,
                        fontWeight: FontWeight.w700,
                        height: 1.1,
                        letterSpacing: 0,
                        color: Colors.white,
                      ),
                    ),
                  ),

                  const SizedBox(height: 20),

                  // Subtitle
                  SizedBox(
                    width: 420,
                    child: Text(
                      data.subtitle,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontFamily: 'Sora',
                        fontSize: subtitleSize,
                        fontWeight: FontWeight.w400,
                        height: 1.6,
                        letterSpacing: 0,
                        color: Color(0xFF00C2FF),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCircleIllustration(double circleSize, double errorIconSize) {
    return SizedBox(
      width: circleSize,
      height: circleSize,
      child: Stack(
        children: [
          // Outer circle (largest)
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.15),
                  width: 1.5,
                ),
              ),
            ),
          ),
          // Middle circle
          Center(
            child: Container(
              width: circleSize * 0.78,
              height: circleSize * 0.78,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.12),
                  width: 1.5,
                ),
              ),
            ),
          ),
          // Inner circle (smallest)
          Center(
            child: Container(
              width: circleSize * 0.56,
              height: circleSize * 0.56,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.10),
                  width: 1.5,
                ),
              ),
            ),
          ),
          // Dotted points on circle lines
          ..._buildCircleDots(circleSize),
          // Main illustration centered exactly on circle
          Positioned.fill(
            child: Center(
              child: Image.asset(
                data.illustration,
                width: circleSize * 2.0,
                height: circleSize * 2.0,
                fit: BoxFit.contain,
                errorBuilder: (context, error, stackTrace) {
                  return Icon(
                    Icons.image_outlined,
                    size: errorIconSize,
                    color: Colors.white.withValues(alpha: 0.3),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildCircleDots(double circleSize) {
    final center = circleSize / 2;
    final List<Widget> dots = [];

    // Three circles: outer (100%), middle (78%), inner (56%)
    // Dots should be exactly ON the border lines
    final outerRadius = center - 1.5;
    final middleRadius = (circleSize * 0.78 / 2) - 1.5;
    final innerRadius = (circleSize * 0.56 / 2) - 1.5;

    // Scale dot sizes for tablet
    final dotScale = isTablet ? 1.3 : 1.0;

    // Dot configurations: [angle in degrees, circleIndex (2=outer, 1=middle, 0=inner), size]
    final dotConfigs = [
      // Outer circle dots
      [30.0, 2, 7.0],
      [90.0, 2, 5.0],
      [150.0, 2, 8.0],
      [210.0, 2, 6.0],
      [270.0, 2, 7.0],
      [330.0, 2, 5.0],
      // Middle circle dots
      [15.0, 1, 6.0],
      [60.0, 1, 8.0],
      [120.0, 1, 5.0],
      [180.0, 1, 7.0],
      [240.0, 1, 6.0],
      [300.0, 1, 8.0],
      // Inner circle dots
      [45.0, 0, 5.0],
      [105.0, 0, 7.0],
      [165.0, 0, 6.0],
      [225.0, 0, 8.0],
      [285.0, 0, 5.0],
      [345.0, 0, 7.0],
    ];

    for (final config in dotConfigs) {
      final angle = config[0] as double;
      final circleIndex = config[1] as int;
      final dotSize = (config[2] as double) * dotScale;

      final radians = angle * math.pi / 180;
      final cosVal = math.cos(radians);
      final sinVal = math.sin(radians);

      final dotRadius = circleIndex == 2 ? outerRadius : (circleIndex == 1 ? middleRadius : innerRadius);

      dots.add(
        Positioned(
          left: center + dotRadius * cosVal - dotSize / 2,
          top: center - dotRadius * sinVal - dotSize / 2,
          child: Container(
            width: dotSize,
            height: dotSize,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white.withValues(alpha: 0.5),
            ),
          ),
        ),
      );
    }

    return dots;
  }
}

class OnboardingData {
  final String title;
  final String subtitle;
  final String illustration;

  OnboardingData({
    required this.title,
    required this.subtitle,
    required this.illustration,
  });
}
