import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:pgme/core_android/models/home_section_model.dart';
import 'package:pgme/core_android/providers/theme_provider.dart';
import 'package:pgme/core_android/theme/app_theme.dart';
import 'package:pgme/core_android/utils/color_utils.dart';
import 'package:pgme/core_android/utils/responsive_helper.dart';
import 'package:pgme/features_android/home/widgets/home_section_card.dart';

class HomeSectionsList extends StatelessWidget {
  final List<HomeSectionModel> sections;

  const HomeSectionsList({super.key, required this.sections});

  @override
  Widget build(BuildContext context) {
    if (sections.isEmpty) return const SizedBox.shrink();

    final themeProvider = Provider.of<ThemeProvider>(context);
    final isDark = themeProvider.isDarkMode;
    final isTablet = ResponsiveHelper.isTablet(context);
    final hPadding =
        isTablet ? ResponsiveHelper.horizontalPadding(context) : 16.0;

    return Column(
      children: sections.map((section) {
        final sectionBg = section.backgroundColor != null
            ? parseHexColor(section.backgroundColor)
            : null;
        final sectionTextColor = section.textColor != null
            ? parseHexColor(section.textColor)
            : (isDark
                ? AppColors.darkTextPrimary
                : const Color(0xFF000000));

        final hasHeader = section.title != null && section.title!.isNotEmpty;

        return Container(
          color: sectionBg,
          padding: EdgeInsets.only(bottom: isTablet ? 36 : 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Section header
              if (hasHeader)
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: hPadding),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        section.title!,
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          fontWeight: FontWeight.w600,
                          fontSize: isTablet ? 28.0 : 20.0,
                          color: sectionTextColor,
                        ),
                      ),
                      if (section.subtitle != null &&
                          section.subtitle!.isNotEmpty) ...[
                        SizedBox(height: isTablet ? 6 : 4),
                        Text(
                          section.subtitle!,
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            fontWeight: FontWeight.w400,
                            fontSize: isTablet ? 16.0 : 13.0,
                            color: sectionTextColor.withValues(alpha: 0.7),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),

              if (hasHeader) SizedBox(height: isTablet ? 18 : 12),

              // Items stacked vertically
              ...section.items.map((item) => Padding(
                    padding: EdgeInsets.symmetric(horizontal: hPadding)
                        .copyWith(bottom: isTablet ? 14 : 10),
                    child: HomeSectionCard(item: item),
                  )),
            ],
          ),
        );
      }).toList(),
    );
  }
}
