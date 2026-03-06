import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:pgme/core/constants/api_constants.dart';
import 'package:pgme/core/providers/theme_provider.dart';
import 'package:pgme/core/services/api_service.dart';
import 'package:pgme/core/services/user_service.dart';
import 'package:pgme/core/theme/app_theme.dart';
import 'package:pgme/core/utils/responsive_helper.dart';

class CareersScreen extends StatefulWidget {
  const CareersScreen({super.key});

  @override
  State<CareersScreen> createState() => _CareersScreenState();
}

class _CareersScreenState extends State<CareersScreen> {
  final _formKey = GlobalKey<FormState>();
  final UserService _userService = UserService();
  final ApiService _apiService = ApiService();

  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _portfolioController = TextEditingController();
  final _representativeWorkController = TextEditingController();
  final _messageController = TextEditingController();

  String? _selectedRole;
  bool _isSubmitting = false;
  bool _isSubmitted = false;
  String? _error;

  static const List<String> _roles = [
    'Lecturer',
    'Examiner',
    'Subject Coordinator',
    'Marketing & Growth',
    'Operations & Support',
  ];

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _portfolioController.dispose();
    _representativeWorkController.dispose();
    _messageController.dispose();
    super.dispose();
  }

  Future<void> _loadUserData() async {
    try {
      final user = await _userService.getProfile();
      if (mounted) {
        setState(() {
          _nameController.text = user.name ?? '';
          _emailController.text = user.email ?? '';
          _phoneController.text = user.phoneNumber;
        });
      }
    } catch (e) {
      debugPrint('Failed to load user data: $e');
    }
  }

  Future<void> _handleSubmit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isSubmitting = true;
      _error = null;
    });

    try {
      final data = <String, dynamic>{
        'name': _nameController.text.trim(),
        'email': _emailController.text.trim(),
        'phone_number': _phoneController.text.trim(),
        'wished_role': _selectedRole,
      };

      if (_portfolioController.text.trim().isNotEmpty) {
        data['portfolio_link'] = _portfolioController.text.trim();
      }
      if (_representativeWorkController.text.trim().isNotEmpty) {
        data['representative_work'] = _representativeWorkController.text.trim();
      }
      if (_messageController.text.trim().isNotEmpty) {
        data['message'] = _messageController.text.trim();
      }

      await _apiService.dio.post(ApiConstants.careerApplications, data: data);

      if (mounted) {
        setState(() {
          _isSubmitting = false;
          _isSubmitted = true;
        });
      }
    } on DioException catch (e) {
      setState(() {
        _isSubmitting = false;
        _error = e.response?.data?['message'] ?? 'Failed to submit application';
      });
    } catch (e) {
      setState(() {
        _isSubmitting = false;
        _error = 'Failed to submit application';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final topPadding = MediaQuery.of(context).padding.top;
    final themeProvider = Provider.of<ThemeProvider>(context);
    final isDark = themeProvider.isDarkMode;
    final isTablet = ResponsiveHelper.isTablet(context);

    final backgroundColor =
        isDark ? AppColors.darkBackground : const Color(0xFFF5F7FA);
    final headerColor = isDark ? AppColors.darkSurface : Colors.white;
    final textColor =
        isDark ? AppColors.darkTextPrimary : const Color(0xFF000000);
    final secondaryTextColor =
        isDark ? AppColors.darkTextSecondary : const Color(0xFF666666);
    final cardColor = isDark ? AppColors.darkCardBackground : Colors.white;
    final borderColor = isDark ? AppColors.darkDivider : const Color(0xFFE0E0E0);
    final accentColor =
        isDark ? const Color(0xFF00BEFA) : const Color(0xFF0000C8);
    final fieldFillColor = isDark ? AppColors.darkSurface : const Color(0xFFF5F5F5);

    final hPadding = isTablet ? ResponsiveHelper.horizontalPadding(context) : 16.0;

    return Scaffold(
      backgroundColor: backgroundColor,
      body: Column(
        children: [
          // Header
          Container(
            color: headerColor,
            padding: EdgeInsets.only(
                top: topPadding + (isTablet ? 20 : 16), bottom: isTablet ? 20 : 16, left: hPadding, right: hPadding),
            child: Row(
              children: [
                GestureDetector(
                  onTap: () => context.pop(),
                  child: Icon(Icons.arrow_back, size: isTablet ? 30 : 24, color: textColor),
                ),
                const Spacer(),
                Text(
                  'Join PGME',
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontWeight: FontWeight.w600,
                    fontSize: isTablet ? 25 : 20,
                    color: textColor,
                  ),
                ),
                const Spacer(),
                SizedBox(width: isTablet ? 30 : 24),
              ],
            ),
          ),

          // Content
          Expanded(
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              padding: EdgeInsets.all(hPadding),
              child: Center(
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: ResponsiveHelper.getMaxContentWidth(context)),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(height: isTablet ? 20 : 16),

                      // Hero section
                      Container(
                        width: double.infinity,
                        padding: EdgeInsets.all(isTablet ? 30 : 24),
                        decoration: BoxDecoration(
                          gradient: AppColors.blueGradient,
                          borderRadius: BorderRadius.circular(isTablet ? 21 : 16),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(Icons.rocket_launch,
                                color: Colors.white, size: isTablet ? 50 : 40),
                            SizedBox(height: isTablet ? 20 : 16),
                            Text(
                              'Build the Future of\nMedical Education',
                              style: TextStyle(
                                fontFamily: 'Poppins',
                                fontWeight: FontWeight.w700,
                                fontSize: isTablet ? 28 : 22,
                                color: Colors.white,
                                height: 1.3,
                              ),
                            ),
                            SizedBox(height: isTablet ? 10 : 8),
                            Text(
                              'Join our passionate team and help shape how the next generation of doctors learn.',
                              style: TextStyle(
                                fontFamily: 'Poppins',
                                fontSize: isTablet ? 17 : 14,
                                color: Colors.white.withValues(alpha: 0.85),
                                height: 1.5,
                              ),
                            ),
                          ],
                        ),
                      ),

                      SizedBox(height: isTablet ? 36 : 28),

                      // Application Form section
                      Text(
                        'Apply Now',
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          fontWeight: FontWeight.w600,
                          fontSize: isTablet ? 22 : 18,
                          color: textColor,
                        ),
                      ),
                      SizedBox(height: isTablet ? 8 : 6),
                      Text(
                        'Fill in the details below and we\'ll get back to you.',
                        style: TextStyle(
                          fontSize: isTablet ? 16 : 13,
                          color: secondaryTextColor,
                          height: 1.4,
                        ),
                      ),
                      SizedBox(height: isTablet ? 20 : 16),

                      if (_isSubmitted)
                        _buildSuccessCard(cardColor, borderColor, textColor, secondaryTextColor, accentColor, isTablet)
                      else
                        _buildApplicationForm(
                          isDark: isDark,
                          isTablet: isTablet,
                          cardColor: cardColor,
                          borderColor: borderColor,
                          textColor: textColor,
                          secondaryTextColor: secondaryTextColor,
                          fieldFillColor: fieldFillColor,
                        ),

                      SizedBox(height: isTablet ? 150 : 120),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSuccessCard(
    Color cardColor, Color borderColor, Color textColor, Color secondaryTextColor, Color accentColor, bool isTablet,
  ) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(isTablet ? 30 : 24),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(isTablet ? 16 : 12),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        children: [
          Container(
            width: isTablet ? 72 : 60,
            height: isTablet ? 72 : 60,
            decoration: BoxDecoration(
              color: AppColors.success.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.check_circle_outline,
              size: isTablet ? 40 : 32,
              color: AppColors.success,
            ),
          ),
          SizedBox(height: isTablet ? 20 : 16),
          Text(
            'Application Submitted!',
            style: TextStyle(
              fontFamily: 'Poppins',
              fontWeight: FontWeight.w600,
              fontSize: isTablet ? 22 : 18,
              color: textColor,
            ),
          ),
          SizedBox(height: isTablet ? 10 : 8),
          Text(
            'Thank you for your interest in joining PGME. We\'ll review your application and get back to you soon.',
            style: TextStyle(
              fontSize: isTablet ? 16 : 14,
              color: secondaryTextColor,
              height: 1.5,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildApplicationForm({
    required bool isDark,
    required bool isTablet,
    required Color cardColor,
    required Color borderColor,
    required Color textColor,
    required Color secondaryTextColor,
    required Color fieldFillColor,
  }) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(isTablet ? 26 : 20),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(isTablet ? 16 : 12),
        border: Border.all(color: borderColor),
      ),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_error != null) ...[
              Container(
                padding: EdgeInsets.all(isTablet ? 14 : 12),
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(isTablet ? 10 : 8),
                  border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.error_outline, color: Colors.red, size: isTablet ? 22 : 18),
                    SizedBox(width: isTablet ? 10 : 8),
                    Expanded(
                      child: Text(
                        _error!,
                        style: TextStyle(color: Colors.red, fontSize: isTablet ? 14 : 13),
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(height: isTablet ? 20 : 16),
            ],

            // Full Name
            _buildFormField(
              label: 'Full Name',
              controller: _nameController,
              hint: 'Enter your full name',
              isDark: isDark,
              isTablet: isTablet,
              textColor: textColor,
              secondaryTextColor: secondaryTextColor,
              fieldFillColor: fieldFillColor,
              borderColor: borderColor,
              validator: (v) {
                if (v == null || v.trim().isEmpty) return 'Name is required';
                if (v.trim().length < 2) return 'Name must be at least 2 characters';
                return null;
              },
            ),

            SizedBox(height: isTablet ? 20 : 16),

            // Email Address
            _buildFormField(
              label: 'Email Address',
              controller: _emailController,
              hint: 'name@example.com',
              keyboardType: TextInputType.emailAddress,
              isDark: isDark,
              isTablet: isTablet,
              textColor: textColor,
              secondaryTextColor: secondaryTextColor,
              fieldFillColor: fieldFillColor,
              borderColor: borderColor,
              validator: (v) {
                if (v == null || v.trim().isEmpty) return 'Email is required';
                final emailRegex = RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$');
                if (!emailRegex.hasMatch(v.trim())) return 'Invalid email format';
                return null;
              },
            ),

            SizedBox(height: isTablet ? 20 : 16),

            // Contact Number (WhatsApp)
            _buildFormField(
              label: 'Contact Number (WhatsApp)',
              controller: _phoneController,
              hint: '+91 00000-00000',
              readOnly: true,
              isDark: isDark,
              isTablet: isTablet,
              textColor: textColor,
              secondaryTextColor: secondaryTextColor,
              fieldFillColor: fieldFillColor,
              borderColor: borderColor,
            ),

            SizedBox(height: isTablet ? 20 : 16),

            // Role Selection
            Text(
              'Role Selection',
              style: TextStyle(
                fontFamily: 'Poppins',
                fontWeight: FontWeight.w500,
                fontSize: isTablet ? 15 : 13,
                color: textColor,
              ),
            ),
            SizedBox(height: isTablet ? 8 : 6),
            DropdownButtonFormField<String>(
              initialValue: _selectedRole,
              style: TextStyle(fontSize: isTablet ? 16 : 14, color: textColor),
              decoration: _fieldDecoration(
                hint: 'Select a role',
                isDark: isDark,
                isTablet: isTablet,
                secondaryTextColor: secondaryTextColor,
                fieldFillColor: fieldFillColor,
                borderColor: borderColor,
              ),
              dropdownColor: isDark ? AppColors.darkCardBackground : Colors.white,
              items: _roles.map((role) {
                return DropdownMenuItem<String>(
                  value: role,
                  child: Text(role),
                );
              }).toList(),
              onChanged: (value) {
                setState(() {
                  _selectedRole = value;
                });
              },
              validator: (v) {
                if (v == null || v.isEmpty) return 'Please select a role';
                return null;
              },
            ),

            SizedBox(height: isTablet ? 20 : 16),

            // Portfolio Link
            _buildFormField(
              label: 'Portfolio Link (Optional)',
              controller: _portfolioController,
              hint: 'Link to your Drive, CV, or Professional Profile',
              keyboardType: TextInputType.url,
              isDark: isDark,
              isTablet: isTablet,
              textColor: textColor,
              secondaryTextColor: secondaryTextColor,
              fieldFillColor: fieldFillColor,
              borderColor: borderColor,
              validator: (v) {
                if (v != null && v.trim().isNotEmpty) {
                  final urlRegex = RegExp(r'^https?:\/\/.+');
                  if (!urlRegex.hasMatch(v.trim())) return 'Please enter a valid URL';
                }
                return null;
              },
            ),

            SizedBox(height: isTablet ? 20 : 16),

            // Representative Work
            _buildFormField(
              label: 'Representative Work (Optional)',
              controller: _representativeWorkController,
              hint: 'Link to a sample lecture, paper, or project',
              keyboardType: TextInputType.url,
              isDark: isDark,
              isTablet: isTablet,
              textColor: textColor,
              secondaryTextColor: secondaryTextColor,
              fieldFillColor: fieldFillColor,
              borderColor: borderColor,
              validator: (v) {
                if (v != null && v.trim().isNotEmpty) {
                  final urlRegex = RegExp(r'^https?:\/\/.+');
                  if (!urlRegex.hasMatch(v.trim())) return 'Please enter a valid URL';
                }
                return null;
              },
            ),

            SizedBox(height: isTablet ? 20 : 16),

            // Additional Remarks
            _buildFormField(
              label: 'Additional Remarks (Optional)',
              controller: _messageController,
              hint: 'Share your achievements or skills',
              maxLines: 4,
              isDark: isDark,
              isTablet: isTablet,
              textColor: textColor,
              secondaryTextColor: secondaryTextColor,
              fieldFillColor: fieldFillColor,
              borderColor: borderColor,
            ),

            SizedBox(height: isTablet ? 28 : 24),

            // Submit Button
            GestureDetector(
              onTap: _isSubmitting ? null : _handleSubmit,
              child: Container(
                width: double.infinity,
                padding: EdgeInsets.symmetric(vertical: isTablet ? 18 : 14),
                decoration: BoxDecoration(
                  gradient: _isSubmitting ? null : AppColors.blueGradient,
                  color: _isSubmitting ? Colors.grey : null,
                  borderRadius: BorderRadius.circular(isTablet ? 14 : 12),
                ),
                child: _isSubmitting
                    ? Center(
                        child: SizedBox(
                          height: isTablet ? 22 : 20,
                          width: isTablet ? 22 : 20,
                          child: const CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                          ),
                        ),
                      )
                    : Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.send, color: Colors.white, size: isTablet ? 22 : 18),
                          SizedBox(width: isTablet ? 10 : 8),
                          Text(
                            'Submit Application',
                            style: TextStyle(
                              fontFamily: 'Poppins',
                              fontWeight: FontWeight.w600,
                              fontSize: isTablet ? 18 : 15,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFormField({
    required String label,
    required TextEditingController controller,
    required bool isDark,
    required bool isTablet,
    required Color textColor,
    required Color secondaryTextColor,
    required Color fieldFillColor,
    required Color borderColor,
    String? hint,
    TextInputType? keyboardType,
    int maxLines = 1,
    bool readOnly = false,
    String? Function(String?)? validator,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontFamily: 'Poppins',
            fontWeight: FontWeight.w500,
            fontSize: isTablet ? 15 : 13,
            color: textColor,
          ),
        ),
        SizedBox(height: isTablet ? 8 : 6),
        TextFormField(
          controller: controller,
          keyboardType: keyboardType,
          maxLines: maxLines,
          readOnly: readOnly,
          style: TextStyle(
            fontSize: isTablet ? 16 : 14,
            color: readOnly ? secondaryTextColor : textColor,
          ),
          decoration: _fieldDecoration(
            hint: hint,
            isDark: isDark,
            isTablet: isTablet,
            secondaryTextColor: secondaryTextColor,
            fieldFillColor: fieldFillColor,
            borderColor: borderColor,
          ),
          validator: validator,
        ),
      ],
    );
  }

  InputDecoration _fieldDecoration({
    String? hint,
    required bool isDark,
    required bool isTablet,
    required Color secondaryTextColor,
    required Color fieldFillColor,
    required Color borderColor,
  }) {
    return InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(color: secondaryTextColor, fontSize: isTablet ? 15 : 13),
      filled: true,
      fillColor: fieldFillColor,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(isTablet ? 12 : 10),
        borderSide: BorderSide(color: borderColor),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(isTablet ? 12 : 10),
        borderSide: BorderSide(color: borderColor),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(isTablet ? 12 : 10),
        borderSide: const BorderSide(color: AppColors.primaryBlue, width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(isTablet ? 12 : 10),
        borderSide: const BorderSide(color: Colors.red),
      ),
      contentPadding: EdgeInsets.symmetric(
        horizontal: isTablet ? 16 : 14,
        vertical: isTablet ? 16 : 14,
      ),
    );
  }

}
