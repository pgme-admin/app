import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:pgme/core/widgets/app_dialog.dart';
import 'package:pgme/features/auth/providers/auth_provider.dart';
import 'package:pgme/core/utils/responsive_helper.dart';

class DataCollectionScreen extends StatefulWidget {
  const DataCollectionScreen({super.key});

  @override
  State<DataCollectionScreen> createState() => _DataCollectionScreenState();
}

class _DataCollectionScreenState extends State<DataCollectionScreen> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _firstNameController = TextEditingController();
  final TextEditingController _lastNameController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _dobController = TextEditingController();
  final TextEditingController _addressController = TextEditingController();
  final TextEditingController _ugCollegeController = TextEditingController();
  final TextEditingController _pgCollegeController = TextEditingController();
  final TextEditingController _organisationController = TextEditingController();
  final TextEditingController _designationController = TextEditingController();
  DateTime? _selectedDob;
  String? _selectedGender;
  bool _isLoading = false;

  // Colors
  static const Color _darkBlue = Color(0xFF0000D1);
  static const Color _labelColor = Color(0xFF78828A);
  static const Color _hintColor = Color(0xFFAAAAAA);

  static const List<String> _genderOptions = ['Male', 'Female', 'Other'];

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    _firstNameController.dispose();
    _lastNameController.dispose();
    _emailController.dispose();
    _dobController.dispose();
    _addressController.dispose();
    _ugCollegeController.dispose();
    _pgCollegeController.dispose();
    _organisationController.dispose();
    _designationController.dispose();
    super.dispose();
  }

  void _showSuccessDialog() {
    final isTablet = ResponsiveHelper.isTablet(context);
    final dialogWidth = isTablet ? 440.0 : 327.0;
    final checkSize = isTablet ? 120.0 : 100.0;
    final checkIconSize = isTablet ? 60.0 : 50.0;
    final titleSize = isTablet ? 30.0 : 24.0;
    final subtitleSize = isTablet ? 18.0 : 14.0;
    final btnWidth = isTablet ? 380.0 : 275.0;
    final btnHeight = isTablet ? 68.0 : 56.0;
    final btnFontSize = isTablet ? 20.0 : 16.0;
    final btnRadius = isTablet ? 32.0 : 24.0;
    final dialogPadding = isTablet ? 40.0 : 32.0;
    final dialogRadius = isTablet ? 30.0 : 24.0;

    showDialog(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.transparent,
      builder: (BuildContext context) {
        return BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Dialog(
            backgroundColor: Colors.transparent,
            elevation: 0,
            child: Container(
              width: dialogWidth,
              padding: EdgeInsets.all(dialogPadding),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(dialogRadius),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Green checkmark circle
                  Container(
                    width: checkSize,
                    height: checkSize,
                    decoration: const BoxDecoration(
                      color: Color(0xFF4CD964),
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: Icon(
                        Icons.check,
                        color: Colors.white,
                        size: checkIconSize,
                      ),
                    ),
                  ),

                  const SizedBox(height: 24),

                  // Success title
                  Text(
                    'Profile completed\nsuccessfully',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: titleSize,
                      fontWeight: FontWeight.w700,
                      height: 1.33,
                      letterSpacing: 0.12,
                      color: Colors.black,
                    ),
                  ),

                  const SizedBox(height: 16),

                  // Subtitle
                  Text(
                    'Your account has been set up.\nLet\'s get started!',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: subtitleSize,
                      fontWeight: FontWeight.w500,
                      height: 1.57,
                      letterSpacing: 0.07,
                      color: _labelColor,
                    ),
                  ),

                  const SizedBox(height: 24),

                  // Continue button
                  SizedBox(
                    width: btnWidth,
                    height: btnHeight,
                    child: ElevatedButton(
                      onPressed: () {
                        Navigator.of(context).pop();
                        context.go('/subject-selection');
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _darkBlue,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(btnRadius),
                        ),
                        elevation: 0,
                        padding: EdgeInsets.zero,
                        alignment: Alignment.center,
                      ),
                      child: Text(
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
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _pickDateOfBirth() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDob ?? DateTime(now.year - 25),
      firstDate: DateTime(1940),
      lastDate: now,
      helpText: 'Select Date of Birth',
    );
    if (picked != null) {
      setState(() {
        _selectedDob = picked;
        _dobController.text = DateFormat('dd/MM/yyyy').format(picked);
      });
    }
  }

  Future<void> _openMapPicker() async {
    final result = await context.push<String>('/map-address-picker');
    if (result != null && result.isNotEmpty && mounted) {
      setState(() {
        _addressController.text = result;
      });
    }
  }

  Future<void> _submitData() async {
    if (!_formKey.currentState!.validate()) {
      debugPrint('Form validation failed');
      return;
    }

    // Validate fields not covered by form validators
    final errors = <String>[];
    if (_selectedDob == null) {
      errors.add('Date of Birth');
    }
    if (_selectedGender == null) {
      errors.add('Gender');
    }
    if (_addressController.text.trim().isEmpty) {
      errors.add('Address');
    }

    if (errors.isNotEmpty) {
      showAppDialog(context, message: 'Please fill in: ${errors.join(', ')}');
      return;
    }

    setState(() => _isLoading = true);

    try {
      final provider = context.read<AuthProvider>();

      debugPrint('Submitting profile data...');
      await provider.updateProfile(
        name: '${_firstNameController.text.trim()} ${_lastNameController.text.trim()}',
        email: _emailController.text.trim(),
        dateOfBirth: DateFormat('yyyy-MM-dd').format(_selectedDob!),
        gender: _selectedGender!.toLowerCase(),
        address: _addressController.text.trim(),
        ugCollege: _ugCollegeController.text.trim(),
        pgCollege: _pgCollegeController.text.trim(),
        affiliatedOrganisation: _organisationController.text.trim(),
        currentDesignation: _designationController.text.trim(),
      );

      debugPrint('Profile updated successfully, showing dialog');
      if (mounted) {
        setState(() => _isLoading = false);
        _showSuccessDialog();
      }
    } catch (e) {
      debugPrint('Error updating profile: $e');
      if (mounted) {
        setState(() => _isLoading = false);
        showAppDialog(context, message: e.toString().replaceAll('Exception: ', ''));
      }
    }
  }

  Widget _buildTextField({
    required String label,
    required String hint,
    required TextEditingController controller,
    required bool isTablet,
    required double fieldWidth,
    required double fieldHeight,
    required double labelSize,
    required double inputSize,
    required double hintSize,
    required double fieldRadius,
    TextInputType keyboardType = TextInputType.text,
    String? Function(String?)? validator,
    int maxLines = 1,
    Widget? trailingWidget,
    FocusNode? focusNode,
  }) {
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(fieldRadius),
      borderSide: BorderSide.none,
    );

    return SizedBox(
      width: fieldWidth,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: labelSize,
              fontWeight: FontWeight.w500,
              height: 1.57,
              letterSpacing: 0.07,
              color: Colors.white,
            ),
          ),
          SizedBox(height: isTablet ? 10 : 8),
          SizedBox(
            height: maxLines > 1 ? null : fieldHeight,
            child: TextFormField(
              controller: controller,
              keyboardType: keyboardType,
              validator: validator,
              maxLines: maxLines,
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: inputSize,
                fontWeight: FontWeight.w400,
                color: const Color(0xFF333333),
              ),
              focusNode: focusNode,
              decoration: InputDecoration(
                hintText: hint,
                hintStyle: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: hintSize,
                  fontWeight: FontWeight.w400,
                  color: _hintColor,
                ),
                filled: true,
                fillColor: Colors.white,
                border: border,
                enabledBorder: border,
                focusedBorder: border,
                errorBorder: border,
                focusedErrorBorder: border,
                contentPadding: EdgeInsets.symmetric(
                  horizontal: isTablet ? 22 : 16,
                  vertical: isTablet ? 18 : 14,
                ),
                errorStyle: const TextStyle(height: 0, fontSize: 0),
                suffixIcon: trailingWidget,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGenderSelector({
    required bool isTablet,
    required double fieldWidth,
    required double fieldHeight,
    required double labelSize,
    required double inputSize,
    required double hintSize,
    required double fieldRadius,
  }) {
    return SizedBox(
      width: fieldWidth,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Gender',
            style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: labelSize,
              fontWeight: FontWeight.w500,
              height: 1.57,
              letterSpacing: 0.07,
              color: Colors.white,
            ),
          ),
          SizedBox(height: isTablet ? 10 : 8),
          Container(
            height: fieldHeight,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(fieldRadius),
            ),
            padding: EdgeInsets.symmetric(horizontal: isTablet ? 22 : 16),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _selectedGender,
                hint: Text(
                  'Select your gender',
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: hintSize,
                    fontWeight: FontWeight.w400,
                    color: _hintColor,
                  ),
                ),
                icon: Icon(
                  Icons.keyboard_arrow_down,
                  color: _hintColor,
                  size: isTablet ? 28 : 24,
                ),
                isExpanded: true,
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: inputSize,
                  fontWeight: FontWeight.w400,
                  color: const Color(0xFF333333),
                ),
                items: _genderOptions.map((gender) {
                  return DropdownMenuItem<String>(
                    value: gender,
                    child: Text(gender),
                  );
                }).toList(),
                onChanged: (value) {
                  setState(() {
                    _selectedGender = value;
                  });
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Sign-up illustration: person with edit/pencil badge (tablet only)
  Widget _buildSignUpIllustration(double size) {
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Outer glow ring
          Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.12),
                width: 1.5,
              ),
            ),
          ),
          // Main circle with person icon
          Container(
            width: size * 0.72,
            height: size * 0.72,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white.withValues(alpha: 0.15),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.25),
                width: 2,
              ),
            ),
            child: Icon(
              Icons.person_outline_rounded,
              size: size * 0.42,
              color: Colors.white.withValues(alpha: 0.9),
            ),
          ),
          // Edit badge (bottom-right)
          Positioned(
            right: size * 0.12,
            bottom: size * 0.10,
            child: Container(
              width: size * 0.30,
              height: size * 0.30,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFF00C2FF),
                border: Border.all(
                  color: const Color(0xFF0033CC),
                  width: 2.5,
                ),
              ),
              child: Icon(
                Icons.edit_rounded,
                size: size * 0.15,
                color: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.of(context).padding.bottom;
    final keyboardHeight = MediaQuery.of(context).viewInsets.bottom;
    final isTablet = ResponsiveHelper.isTablet(context);

    // Responsive sizes
    final fieldWidth = isTablet ? 520.0 : 327.0;
    final fieldHeight = isTablet ? 62.0 : 52.0;
    final fieldRadius = isTablet ? 28.0 : 24.0;
    final labelSize = isTablet ? 18.0 : 14.0;
    final inputSize = isTablet ? 18.0 : 16.0;
    final hintSize = isTablet ? 16.0 : 14.0;
    final backBtnSize = isTablet ? 52.0 : 48.0;
    final backIconSize = isTablet ? 28.0 : 24.0;
    final signUpTitleSize = isTablet ? 32.0 : 28.0;
    final completeTitleSize = isTablet ? 28.0 : 24.0;
    final completeSubSize = isTablet ? 16.0 : 14.0;
    final submitBtnWidth = isTablet ? 520.0 : 327.0;
    final submitBtnHeight = isTablet ? 78.0 : 56.0;
    final submitBtnFontSize = isTablet ? 21.0 : 16.0;
    final submitBtnRadius = isTablet ? 32.0 : 24.0;
    final fieldGap = isTablet ? 20.0 : 16.0;
    final hPadding = isTablet ? 32.0 : 24.0;

    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF0033CC), Color(0xFF0033CC)],
          ),
        ),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(hPadding, 12, hPadding, keyboardHeight > 0 ? keyboardHeight + 16 : bottomPadding + 24),
            child: Center(
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Back button and title row
                    Row(
                      children: [
                        // Back button
                        GestureDetector(
                          onTap: () => context.go('/login'),
                          child: Container(
                            width: backBtnSize,
                            height: backBtnSize,
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.2),
                              shape: BoxShape.circle,
                            ),
                            child: Center(
                              child: Icon(
                                Icons.arrow_back,
                                size: backIconSize,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                        Expanded(
                          child: Center(
                            child: Text(
                              'Sign Up',
                              style: TextStyle(
                                fontFamily: 'Poppins',
                                fontSize: signUpTitleSize,
                                fontWeight: FontWeight.w700,
                                height: 1.0,
                                letterSpacing: 0.14,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                        // Spacer to balance
                        SizedBox(width: backBtnSize),
                      ],
                    ),

                    // Illustration (tablet only)
                    if (isTablet) ...[
                      const SizedBox(height: 16),
                      Center(child: _buildSignUpIllustration(110)),
                      const SizedBox(height: 12),
                    ] else
                      const SizedBox(height: 32),

                    // Complete your account title
                    Center(
                      child: Text(
                        'Complete your account',
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: completeTitleSize,
                          fontWeight: FontWeight.w700,
                          height: 1.2,
                          letterSpacing: 0.12,
                          color: Colors.white,
                        ),
                      ),
                    ),

                    SizedBox(height: isTablet ? 2 : 8),

                    // Subtitle
                    Center(
                      child: Text(
                        'Tell us a bit about yourself',
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          fontSize: completeSubSize,
                          fontWeight: FontWeight.w400,
                          color: const Color(0xFF00C2FF),
                        ),
                      ),
                    ),

                    SizedBox(height: isTablet ? 24 : 32),

                    // First Name
                    Center(
                      child: _buildTextField(
                        label: 'First Name',
                        hint: 'Enter your first name',
                        controller: _firstNameController,
                        isTablet: isTablet,
                        fieldWidth: fieldWidth,
                        fieldHeight: fieldHeight,
                        labelSize: labelSize,
                        inputSize: inputSize,
                        hintSize: hintSize,
                        fieldRadius: fieldRadius,
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Required';
                          }
                          return null;
                        },
                      ),
                    ),

                    SizedBox(height: fieldGap),

                    // Last Name
                    Center(
                      child: _buildTextField(
                        label: 'Last Name',
                        hint: 'Enter your last name',
                        controller: _lastNameController,
                        isTablet: isTablet,
                        fieldWidth: fieldWidth,
                        fieldHeight: fieldHeight,
                        labelSize: labelSize,
                        inputSize: inputSize,
                        hintSize: hintSize,
                        fieldRadius: fieldRadius,
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Required';
                          }
                          return null;
                        },
                      ),
                    ),

                    SizedBox(height: fieldGap),

                    // E-mail
                    Center(
                      child: _buildTextField(
                        label: 'E-mail',
                        hint: 'Enter your email',
                        controller: _emailController,
                        isTablet: isTablet,
                        fieldWidth: fieldWidth,
                        fieldHeight: fieldHeight,
                        labelSize: labelSize,
                        inputSize: inputSize,
                        hintSize: hintSize,
                        fieldRadius: fieldRadius,
                        keyboardType: TextInputType.emailAddress,
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Required';
                          }
                          if (!RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(value)) {
                            return 'Invalid email';
                          }
                          return null;
                        },
                      ),
                    ),

                    SizedBox(height: fieldGap),

                    // Date of Birth
                    Center(
                      child: SizedBox(
                        width: fieldWidth,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Date of Birth',
                              style: TextStyle(
                                fontFamily: 'Poppins',
                                fontSize: labelSize,
                                fontWeight: FontWeight.w500,
                                height: 1.57,
                                letterSpacing: 0.07,
                                color: Colors.white,
                              ),
                            ),
                            SizedBox(height: isTablet ? 10 : 8),
                            GestureDetector(
                              onTap: _pickDateOfBirth,
                              child: AbsorbPointer(
                                child: SizedBox(
                                  height: fieldHeight,
                                  child: TextFormField(
                                    controller: _dobController,
                                    style: TextStyle(
                                      fontFamily: 'Poppins',
                                      fontSize: inputSize,
                                      fontWeight: FontWeight.w400,
                                      color: const Color(0xFF333333),
                                    ),
                                    decoration: InputDecoration(
                                      hintText: 'DD/MM/YYYY',
                                      hintStyle: TextStyle(
                                        fontFamily: 'Poppins',
                                        fontSize: hintSize,
                                        fontWeight: FontWeight.w400,
                                        color: _hintColor,
                                      ),
                                      filled: true,
                                      fillColor: Colors.white,
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(fieldRadius),
                                        borderSide: BorderSide.none,
                                      ),
                                      enabledBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(fieldRadius),
                                        borderSide: BorderSide.none,
                                      ),
                                      focusedBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(fieldRadius),
                                        borderSide: BorderSide.none,
                                      ),
                                      contentPadding: EdgeInsets.symmetric(
                                        horizontal: isTablet ? 22 : 16,
                                        vertical: isTablet ? 18 : 14,
                                      ),
                                      suffixIcon: Padding(
                                        padding: EdgeInsets.only(right: isTablet ? 24 : 12),
                                        child: Icon(
                                          Icons.calendar_today_outlined,
                                          color: _hintColor,
                                          size: isTablet ? 20 : 18,
                                        ),
                                      ),
                                      suffixIconConstraints: BoxConstraints(
                                        minHeight: isTablet ? 20 : 18,
                                        minWidth: isTablet ? 20 : 18,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    SizedBox(height: fieldGap),

                    // Gender
                    Center(
                      child: _buildGenderSelector(
                        isTablet: isTablet,
                        fieldWidth: fieldWidth,
                        fieldHeight: fieldHeight,
                        labelSize: labelSize,
                        inputSize: inputSize,
                        hintSize: hintSize,
                        fieldRadius: fieldRadius,
                      ),
                    ),

                    SizedBox(height: fieldGap),

                    // Address (tap to open map picker)
                    Center(
                      child: GestureDetector(
                        onTap: _openMapPicker,
                        child: SizedBox(
                          width: fieldWidth,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Address',
                                style: TextStyle(
                                  fontFamily: 'Poppins',
                                  fontSize: labelSize,
                                  fontWeight: FontWeight.w500,
                                  height: 1.57,
                                  letterSpacing: 0.07,
                                  color: Colors.white,
                                ),
                              ),
                              SizedBox(height: isTablet ? 10 : 8),
                              Container(
                                height: fieldHeight,
                                padding: EdgeInsets.symmetric(
                                  horizontal: isTablet ? 16 : 12,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(fieldRadius),
                                  border: Border.all(
                                    color: const Color(0xFFE0E0E0),
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        _addressController.text.isEmpty
                                            ? 'Tap to pick your address'
                                            : _addressController.text,
                                        style: TextStyle(
                                          fontFamily: 'Poppins',
                                          fontSize: inputSize,
                                          color: _addressController.text.isEmpty
                                              ? _hintColor
                                              : Colors.black87,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    Icon(
                                      Icons.location_on_outlined,
                                      size: isTablet ? 22 : 18,
                                      color: const Color(0xFF0000C8),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),

                    SizedBox(height: fieldGap),

                    // UG College
                    Center(
                      child: _buildTextField(
                        label: 'UG College',
                        hint: 'Enter your UG college',
                        controller: _ugCollegeController,
                        isTablet: isTablet,
                        fieldWidth: fieldWidth,
                        fieldHeight: fieldHeight,
                        labelSize: labelSize,
                        inputSize: inputSize,
                        hintSize: hintSize,
                        fieldRadius: fieldRadius,
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Required';
                          }
                          return null;
                        },
                      ),
                    ),

                    SizedBox(height: fieldGap),

                    // PG College
                    Center(
                      child: _buildTextField(
                        label: 'PG College',
                        hint: 'Enter your PG college',
                        controller: _pgCollegeController,
                        isTablet: isTablet,
                        fieldWidth: fieldWidth,
                        fieldHeight: fieldHeight,
                        labelSize: labelSize,
                        inputSize: inputSize,
                        hintSize: hintSize,
                        fieldRadius: fieldRadius,
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Required';
                          }
                          return null;
                        },
                      ),
                    ),

                    SizedBox(height: fieldGap),

                    // Current Affiliated Organisation
                    Center(
                      child: _buildTextField(
                        label: 'Current Affiliated Organisation',
                        hint: 'Enter your organisation',
                        controller: _organisationController,
                        isTablet: isTablet,
                        fieldWidth: fieldWidth,
                        fieldHeight: fieldHeight,
                        labelSize: labelSize,
                        inputSize: inputSize,
                        hintSize: hintSize,
                        fieldRadius: fieldRadius,
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Required';
                          }
                          return null;
                        },
                      ),
                    ),

                    SizedBox(height: fieldGap),

                    // Current Designation
                    Center(
                      child: _buildTextField(
                        label: 'Current Designation',
                        hint: 'Enter your designation',
                        controller: _designationController,
                        isTablet: isTablet,
                        fieldWidth: fieldWidth,
                        fieldHeight: fieldHeight,
                        labelSize: labelSize,
                        inputSize: inputSize,
                        hintSize: hintSize,
                        fieldRadius: fieldRadius,
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Required';
                          }
                          return null;
                        },
                      ),
                    ),

                    SizedBox(height: isTablet ? 40 : 32),

                    // Sign Up Button
                    Center(
                      child: SizedBox(
                        width: submitBtnWidth,
                        height: submitBtnHeight,
                        child: ElevatedButton(
                          onPressed: _isLoading ? null : _submitData,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF00C2FF),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(submitBtnRadius),
                            ),
                            elevation: 0,
                            padding: EdgeInsets.zero,
                            alignment: Alignment.center,
                          ),
                          child: _isLoading
                              ? SizedBox(
                                  width: isTablet ? 28 : 24,
                                  height: isTablet ? 28 : 24,
                                  child: const CircularProgressIndicator(
                                    strokeWidth: 2,
                                    valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF0000D1)),
                                  ),
                                )
                              : Text(
                                  'Sign Up',
                                  style: TextStyle(
                                    fontFamily: 'Poppins',
                                    fontSize: submitBtnFontSize,
                                    fontWeight: FontWeight.w600,
                                    height: 1.0,
                                    color: const Color(0xFF0000D1),
                                  ),
                                ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
