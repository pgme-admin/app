import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:pgme/core/constants/indian_states.dart';
import 'package:pgme/core/models/address_model.dart';
import 'package:pgme/core/providers/theme_provider.dart';
import 'package:pgme/core/services/location_service.dart';
import 'package:pgme/core/services/pincode_service.dart';
import 'package:pgme/core/theme/app_theme.dart';
import 'package:pgme/core/utils/responsive_helper.dart';
import 'package:pgme/core/widgets/app_dialog.dart';

/// Shows an address bottom sheet and returns an [Address] or null if dismissed.
///
/// [initialAddress] - Pre-fill with user's saved address.
/// [showShippingOption] - If true, shows "Use as shipping address" checkbox (for book orders).
/// Returns a map with 'billing' and optionally 'shipping' Address objects.
Future<Map<String, Address>?> showAddressSheet(
  BuildContext context, {
  Address? initialAddress,
  bool showShippingOption = false,
}) {
  return showModalBottomSheet<Map<String, Address>>(
    context: context,
    isScrollControlled: true,
    useRootNavigator: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => _AddressSheet(
      initialAddress: initialAddress,
      showShippingOption: showShippingOption,
    ),
  );
}

class _AddressSheet extends StatefulWidget {
  final Address? initialAddress;
  final bool showShippingOption;

  const _AddressSheet({
    this.initialAddress,
    this.showShippingOption = false,
  });

  @override
  State<_AddressSheet> createState() => _AddressSheetState();
}

class _AddressSheetState extends State<_AddressSheet> {
  final _formKey = GlobalKey<FormState>();
  final _pincodeController = TextEditingController();
  final _cityController = TextEditingController();
  final _streetController = TextEditingController();
  final _street2Controller = TextEditingController();

  // Shipping address controllers (for book orders)
  final _shipPincodeController = TextEditingController();
  final _shipCityController = TextEditingController();
  final _shipStreetController = TextEditingController();
  final _shipStreet2Controller = TextEditingController();

  final PincodeService _pincodeService = PincodeService();
  final LocationService _locationService = LocationService();

  String? _selectedState;
  String? _selectedStateCode;
  String? _shipSelectedState;
  String? _shipSelectedStateCode;

  bool _isLoadingPincode = false;
  bool _isLoadingLocation = false;
  bool _isLoadingShipPincode = false;
  bool _sameAsShipping = true;
  bool _useSavedAddress = false;

  bool get _hasSavedAddress =>
      widget.initialAddress != null && widget.initialAddress!.isValid;

  @override
  void initState() {
    super.initState();
    if (_hasSavedAddress) {
      _useSavedAddress = true;
      _applySavedAddress();
    }
  }

  /// Fill form fields from saved address and run pincode lookup
  /// to ensure state/state_code are derived consistently.
  void _applySavedAddress() {
    final addr = widget.initialAddress!;
    _pincodeController.text = addr.pincode;
    _cityController.text = addr.city;
    _streetController.text = addr.street;
    _street2Controller.text = addr.street2;
    if (addr.stateCode.isNotEmpty) {
      _selectedStateCode = addr.stateCode;
      _selectedState = getStateName(addr.stateCode) ?? addr.state;
    } else if (addr.state.isNotEmpty) {
      _selectedState = addr.state;
      _selectedStateCode = getStateCode(addr.state);
    }
    // Re-derive state from pincode to ensure consistency
    if (addr.pincode.isNotEmpty) {
      _onPincodeChanged(addr.pincode);
    }
  }

  void _clearAddressFields() {
    _pincodeController.clear();
    _cityController.clear();
    _streetController.clear();
    _street2Controller.clear();
    _selectedState = null;
    _selectedStateCode = null;
  }

  @override
  void dispose() {
    _pincodeController.dispose();
    _cityController.dispose();
    _streetController.dispose();
    _street2Controller.dispose();
    _shipPincodeController.dispose();
    _shipCityController.dispose();
    _shipStreetController.dispose();
    _shipStreet2Controller.dispose();
    super.dispose();
  }

  Future<void> _onPincodeChanged(String value) async {
    if (value.length == 6 && RegExp(r'^[1-9][0-9]{5}$').hasMatch(value)) {
      setState(() => _isLoadingPincode = true);
      final result = await _pincodeService.lookupPincode(value);
      if (result != null && mounted) {
        final stateCode = getStateCode(result.state);
        setState(() {
          _cityController.text = result.city;
          _selectedState = result.state;
          _selectedStateCode = stateCode;
          _isLoadingPincode = false;
        });
      } else if (mounted) {
        setState(() => _isLoadingPincode = false);
      }
    }
  }

  Future<void> _onShipPincodeChanged(String value) async {
    if (value.length == 6 && RegExp(r'^[1-9][0-9]{5}$').hasMatch(value)) {
      setState(() => _isLoadingShipPincode = true);
      final result = await _pincodeService.lookupPincode(value);
      if (result != null && mounted) {
        final stateCode = getStateCode(result.state);
        setState(() {
          _shipCityController.text = result.city;
          _shipSelectedState = result.state;
          _shipSelectedStateCode = stateCode;
          _isLoadingShipPincode = false;
        });
      } else if (mounted) {
        setState(() => _isLoadingShipPincode = false);
      }
    }
  }

  Future<void> _useMyLocation() async {
    setState(() => _isLoadingLocation = true);
    try {
      final hasPermission = await _locationService.requestLocationPermission();
      if (!hasPermission) {
        if (mounted) {
          showAppDialog(context, message: 'Location permission denied', type: AppDialogType.info);
        }
        setState(() => _isLoadingLocation = false);
        return;
      }

      final position = await _locationService.getCurrentLocation();
      if (position == null || !mounted) {
        setState(() => _isLoadingLocation = false);
        return;
      }

      final structured = await _locationService.getStructuredAddressFromCoordinates(
        position.latitude,
        position.longitude,
      );

      if (structured != null && mounted) {
        final city = structured['city'] ?? '';
        final state = structured['state'] ?? '';
        final postcode = structured['postcode'] ?? '';
        final road = structured['road'] ?? '';
        final suburb = structured['suburb'] ?? '';

        setState(() {
          if (city.isNotEmpty) _cityController.text = city;
          if (postcode.isNotEmpty) _pincodeController.text = postcode;
          if (road.isNotEmpty) _streetController.text = road;
          if (suburb.isNotEmpty) _street2Controller.text = suburb;

          if (state.isNotEmpty) {
            final code = getStateCode(state);
            if (code != null) {
              _selectedState = state;
              _selectedStateCode = code;
            } else {
              _selectedState = state;
            }
          }
        });
      }
    } catch (e) {
      debugPrint('Error getting location: $e');
    } finally {
      if (mounted) setState(() => _isLoadingLocation = false);
    }
  }

  void _onConfirm() {
    if (!_formKey.currentState!.validate()) return;

    if (_selectedStateCode == null || _selectedStateCode!.isEmpty) {
      showAppDialog(context, message: 'Please select a state', type: AppDialogType.info);
      return;
    }

    final billing = Address(
      street: _streetController.text.trim(),
      street2: _street2Controller.text.trim(),
      city: _cityController.text.trim(),
      state: _selectedState ?? '',
      stateCode: _selectedStateCode ?? '',
      pincode: _pincodeController.text.trim(),
    );

    final result = <String, Address>{'billing': billing};

    if (widget.showShippingOption) {
      if (_sameAsShipping) {
        result['shipping'] = billing;
      } else {
        if (_shipSelectedStateCode == null || _shipSelectedStateCode!.isEmpty) {
          showAppDialog(context, message: 'Please select a state for shipping address', type: AppDialogType.info);
          return;
        }
        result['shipping'] = Address(
          street: _shipStreetController.text.trim(),
          street2: _shipStreet2Controller.text.trim(),
          city: _shipCityController.text.trim(),
          state: _shipSelectedState ?? '',
          stateCode: _shipSelectedStateCode ?? '',
          pincode: _shipPincodeController.text.trim(),
        );
      }
    }

    Navigator.pop(context, result);
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final isDark = themeProvider.isDarkMode;
    final isTablet = ResponsiveHelper.isTablet(context);
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final bottomSafeArea = MediaQuery.of(context).padding.bottom;
    final screenHeight = MediaQuery.of(context).size.height;

    final bgColor = isDark ? AppColors.darkCardBackground : Colors.white;
    final textColor = isDark ? AppColors.darkTextPrimary : const Color(0xFF000000);
    final secondaryTextColor = isDark ? AppColors.darkTextSecondary : const Color(0xFF666666);
    final borderColor = isDark ? AppColors.darkDivider : const Color(0xFFE0E0E0);
    final inputFillColor = isDark ? AppColors.darkSurface : const Color(0xFFF5F5F5);
    final accentColor = isDark ? const Color(0xFF4D8FFF) : const Color(0xFF0033CC);

    final hPadding = isTablet ? 28.0 : 20.0;
    final borderRadius = isTablet ? 20.0 : 16.0;
    final fieldRadius = isTablet ? 14.0 : 10.0;
    final fieldFontSize = isTablet ? 16.0 : 14.0;
    final labelFontSize = isTablet ? 14.0 : 12.0;
    final headingFontSize = isTablet ? 22.0 : 18.0;
    final buttonFontSize = isTablet ? 18.0 : 16.0;
    final spacing = isTablet ? 16.0 : 12.0;

    return Container(
      constraints: BoxConstraints(maxHeight: screenHeight * 0.9),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.vertical(top: Radius.circular(borderRadius)),
      ),
      child: Padding(
        padding: EdgeInsets.only(bottom: bottomInset),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Drag handle
            Container(
              margin: EdgeInsets.only(top: isTablet ? 14 : 10),
              width: isTablet ? 50 : 40,
              height: 4,
              decoration: BoxDecoration(
                color: borderColor,
                borderRadius: BorderRadius.circular(2),
              ),
            ),

            // Header
            Padding(
              padding: EdgeInsets.fromLTRB(hPadding, spacing, hPadding, 0),
              child: Row(
                children: [
                  Text(
                    'Address',
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontWeight: FontWeight.w600,
                      fontSize: headingFontSize,
                      color: textColor,
                    ),
                  ),
                  const Spacer(),
                  TextButton.icon(
                    onPressed: _isLoadingLocation ? null : _useMyLocation,
                    icon: _isLoadingLocation
                        ? SizedBox(
                            width: isTablet ? 18 : 14,
                            height: isTablet ? 18 : 14,
                            child: CircularProgressIndicator(strokeWidth: 2, color: accentColor),
                          )
                        : Icon(Icons.my_location, size: isTablet ? 20 : 16, color: accentColor),
                    label: Text(
                      'Use Location',
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: labelFontSize,
                        color: accentColor,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Form
            Flexible(
              child: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(hPadding, spacing, hPadding, hPadding + bottomSafeArea),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // "Use saved address" toggle
                      if (_hasSavedAddress) ...[
                        Row(
                          children: [
                            SizedBox(
                              width: 24,
                              height: 24,
                              child: Checkbox(
                                value: _useSavedAddress,
                                onChanged: (v) {
                                  setState(() {
                                    _useSavedAddress = v ?? false;
                                    if (_useSavedAddress) {
                                      _applySavedAddress();
                                    } else {
                                      _clearAddressFields();
                                    }
                                  });
                                },
                                activeColor: accentColor,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: GestureDetector(
                                onTap: () {
                                  setState(() {
                                    _useSavedAddress = !_useSavedAddress;
                                    if (_useSavedAddress) {
                                      _applySavedAddress();
                                    } else {
                                      _clearAddressFields();
                                    }
                                  });
                                },
                                child: Text(
                                  'Use saved address',
                                  style: TextStyle(
                                    fontFamily: 'Poppins',
                                    fontSize: fieldFontSize,
                                    color: textColor,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        SizedBox(height: spacing),
                      ],

                      // Pincode
                      _buildTextField(
                        controller: _pincodeController,
                        label: 'Pincode *',
                        hint: 'Enter 6-digit pincode',
                        keyboardType: TextInputType.number,
                        inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(6)],
                        isLoading: _isLoadingPincode,
                        onChanged: _onPincodeChanged,
                        validator: (v) {
                          if (v == null || v.isEmpty) return 'Pincode is required';
                          if (!RegExp(r'^[1-9][0-9]{5}$').hasMatch(v)) return 'Enter a valid 6-digit pincode';
                          return null;
                        },
                        isDark: isDark,
                        fieldRadius: fieldRadius,
                        fieldFontSize: fieldFontSize,
                        labelFontSize: labelFontSize,
                        inputFillColor: inputFillColor,
                        borderColor: borderColor,
                        textColor: textColor,
                        secondaryTextColor: secondaryTextColor,
                      ),
                      SizedBox(height: spacing),

                      // State dropdown
                      _buildStateDropdown(
                        selectedState: _selectedState,
                        onSelected: (name) {
                          setState(() {
                            _selectedState = name;
                            _selectedStateCode = indianStateNameToCode[name];
                          });
                        },
                        label: 'State *',
                        isDark: isDark,
                        fieldRadius: fieldRadius,
                        fieldFontSize: fieldFontSize,
                        labelFontSize: labelFontSize,
                        inputFillColor: inputFillColor,
                        borderColor: borderColor,
                        textColor: textColor,
                        secondaryTextColor: secondaryTextColor,
                      ),
                      SizedBox(height: spacing),

                      // City
                      _buildTextField(
                        controller: _cityController,
                        label: 'City *',
                        hint: 'Enter city name',
                        validator: (v) {
                          if (v == null || v.trim().isEmpty) return 'City is required';
                          return null;
                        },
                        isDark: isDark,
                        fieldRadius: fieldRadius,
                        fieldFontSize: fieldFontSize,
                        labelFontSize: labelFontSize,
                        inputFillColor: inputFillColor,
                        borderColor: borderColor,
                        textColor: textColor,
                        secondaryTextColor: secondaryTextColor,
                      ),
                      SizedBox(height: spacing),

                      // Street (optional)
                      _buildTextField(
                        controller: _streetController,
                        label: 'Street / Address Line 1',
                        hint: 'House no, building, street',
                        isDark: isDark,
                        fieldRadius: fieldRadius,
                        fieldFontSize: fieldFontSize,
                        labelFontSize: labelFontSize,
                        inputFillColor: inputFillColor,
                        borderColor: borderColor,
                        textColor: textColor,
                        secondaryTextColor: secondaryTextColor,
                      ),
                      SizedBox(height: spacing),

                      // Street 2 (optional)
                      _buildTextField(
                        controller: _street2Controller,
                        label: 'Area / Landmark',
                        hint: 'Area, landmark (optional)',
                        isDark: isDark,
                        fieldRadius: fieldRadius,
                        fieldFontSize: fieldFontSize,
                        labelFontSize: labelFontSize,
                        inputFillColor: inputFillColor,
                        borderColor: borderColor,
                        textColor: textColor,
                        secondaryTextColor: secondaryTextColor,
                      ),

                      // Shipping address section (for book orders)
                      if (widget.showShippingOption) ...[
                        SizedBox(height: spacing * 1.5),
                        Divider(color: borderColor),
                        SizedBox(height: spacing * 0.5),
                        Row(
                          children: [
                            Checkbox(
                              value: _sameAsShipping,
                              onChanged: (v) => setState(() => _sameAsShipping = v ?? true),
                              activeColor: accentColor,
                            ),
                            Expanded(
                              child: GestureDetector(
                                onTap: () => setState(() => _sameAsShipping = !_sameAsShipping),
                                child: Text(
                                  'Same as above',
                                  style: TextStyle(
                                    fontFamily: 'Poppins',
                                    fontSize: fieldFontSize,
                                    color: textColor,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        if (!_sameAsShipping) ...[
                          SizedBox(height: spacing),
                          Text(
                            'Shipping Address',
                            style: TextStyle(
                              fontFamily: 'Poppins',
                              fontWeight: FontWeight.w600,
                              fontSize: headingFontSize * 0.85,
                              color: textColor,
                            ),
                          ),
                          SizedBox(height: spacing),

                          // Shipping Pincode
                          _buildTextField(
                            controller: _shipPincodeController,
                            label: 'Pincode *',
                            hint: 'Enter 6-digit pincode',
                            keyboardType: TextInputType.number,
                            inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(6)],
                            isLoading: _isLoadingShipPincode,
                            onChanged: _onShipPincodeChanged,
                            validator: (v) {
                              if (_sameAsShipping) return null;
                              if (v == null || v.isEmpty) return 'Pincode is required';
                              if (!RegExp(r'^[1-9][0-9]{5}$').hasMatch(v)) return 'Enter a valid 6-digit pincode';
                              return null;
                            },
                            isDark: isDark,
                            fieldRadius: fieldRadius,
                            fieldFontSize: fieldFontSize,
                            labelFontSize: labelFontSize,
                            inputFillColor: inputFillColor,
                            borderColor: borderColor,
                            textColor: textColor,
                            secondaryTextColor: secondaryTextColor,
                          ),
                          SizedBox(height: spacing),

                          // Shipping State
                          _buildStateDropdown(
                            selectedState: _shipSelectedState,
                            onSelected: (name) {
                              setState(() {
                                _shipSelectedState = name;
                                _shipSelectedStateCode = indianStateNameToCode[name];
                              });
                            },
                            label: 'State *',
                            isDark: isDark,
                            fieldRadius: fieldRadius,
                            fieldFontSize: fieldFontSize,
                            labelFontSize: labelFontSize,
                            inputFillColor: inputFillColor,
                            borderColor: borderColor,
                            textColor: textColor,
                            secondaryTextColor: secondaryTextColor,
                          ),
                          SizedBox(height: spacing),

                          // Shipping City
                          _buildTextField(
                            controller: _shipCityController,
                            label: 'City *',
                            hint: 'Enter city name',
                            validator: (v) {
                              if (_sameAsShipping) return null;
                              if (v == null || v.trim().isEmpty) return 'City is required';
                              return null;
                            },
                            isDark: isDark,
                            fieldRadius: fieldRadius,
                            fieldFontSize: fieldFontSize,
                            labelFontSize: labelFontSize,
                            inputFillColor: inputFillColor,
                            borderColor: borderColor,
                            textColor: textColor,
                            secondaryTextColor: secondaryTextColor,
                          ),
                          SizedBox(height: spacing),

                          // Shipping Street
                          _buildTextField(
                            controller: _shipStreetController,
                            label: 'Street / Address Line 1',
                            hint: 'House no, building, street',
                            isDark: isDark,
                            fieldRadius: fieldRadius,
                            fieldFontSize: fieldFontSize,
                            labelFontSize: labelFontSize,
                            inputFillColor: inputFillColor,
                            borderColor: borderColor,
                            textColor: textColor,
                            secondaryTextColor: secondaryTextColor,
                          ),
                          SizedBox(height: spacing),

                          // Shipping Street 2
                          _buildTextField(
                            controller: _shipStreet2Controller,
                            label: 'Area / Landmark',
                            hint: 'Area, landmark (optional)',
                            isDark: isDark,
                            fieldRadius: fieldRadius,
                            fieldFontSize: fieldFontSize,
                            labelFontSize: labelFontSize,
                            inputFillColor: inputFillColor,
                            borderColor: borderColor,
                            textColor: textColor,
                            secondaryTextColor: secondaryTextColor,
                          ),
                        ],
                      ],

                      SizedBox(height: spacing * 1.5),

                      // Confirm button
                      SizedBox(
                        width: double.infinity,
                        height: isTablet ? 56 : 48,
                        child: ElevatedButton(
                          onPressed: _onConfirm,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: accentColor,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(fieldRadius),
                            ),
                          ),
                          child: Text(
                            'Confirm Address',
                            style: TextStyle(
                              fontFamily: 'Poppins',
                              fontWeight: FontWeight.w600,
                              fontSize: buttonFontSize,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    String? hint,
    TextInputType? keyboardType,
    List<TextInputFormatter>? inputFormatters,
    bool isLoading = false,
    ValueChanged<String>? onChanged,
    String? Function(String?)? validator,
    required bool isDark,
    required double fieldRadius,
    required double fieldFontSize,
    required double labelFontSize,
    required Color inputFillColor,
    required Color borderColor,
    required Color textColor,
    required Color secondaryTextColor,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontFamily: 'Poppins',
            fontSize: labelFontSize,
            fontWeight: FontWeight.w500,
            color: secondaryTextColor,
          ),
        ),
        const SizedBox(height: 4),
        TextFormField(
          controller: controller,
          keyboardType: keyboardType,
          inputFormatters: inputFormatters,
          onChanged: onChanged,
          validator: validator,
          style: TextStyle(
            fontFamily: 'Poppins',
            fontSize: fieldFontSize,
            color: textColor,
          ),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(
              fontFamily: 'Poppins',
              fontSize: fieldFontSize,
              color: secondaryTextColor.withValues(alpha: 0.6),
            ),
            filled: true,
            fillColor: inputFillColor,
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(fieldRadius),
              borderSide: BorderSide(color: borderColor),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(fieldRadius),
              borderSide: BorderSide(color: borderColor),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(fieldRadius),
              borderSide: BorderSide(
                color: isDark ? const Color(0xFF4D8FFF) : const Color(0xFF0033CC),
                width: 1.5,
              ),
            ),
            suffixIcon: isLoading
                ? const Padding(
                    padding: EdgeInsets.all(12),
                    child: SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : null,
          ),
        ),
      ],
    );
  }

  Widget _buildStateDropdown({
    required String? selectedState,
    required ValueChanged<String> onSelected,
    required String label,
    required bool isDark,
    required double fieldRadius,
    required double fieldFontSize,
    required double labelFontSize,
    required Color inputFillColor,
    required Color borderColor,
    required Color textColor,
    required Color secondaryTextColor,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontFamily: 'Poppins',
            fontSize: labelFontSize,
            fontWeight: FontWeight.w500,
            color: secondaryTextColor,
          ),
        ),
        const SizedBox(height: 4),
        Autocomplete<String>(
          initialValue: TextEditingValue(text: selectedState ?? ''),
          optionsBuilder: (textEditingValue) {
            if (textEditingValue.text.isEmpty) return indianStateNames;
            final query = textEditingValue.text.toLowerCase();
            return indianStateNames
                .where((s) => s.toLowerCase().contains(query))
                .toList();
          },
          onSelected: onSelected,
          fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
            // Sync controller if selectedState was set programmatically
            if (selectedState != null && controller.text != selectedState) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                controller.text = selectedState;
                controller.selection = TextSelection.fromPosition(
                  TextPosition(offset: controller.text.length),
                );
              });
            }
            return TextFormField(
              controller: controller,
              focusNode: focusNode,
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: fieldFontSize,
                color: textColor,
              ),
              decoration: InputDecoration(
                hintText: 'Search state...',
                hintStyle: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: fieldFontSize,
                  color: secondaryTextColor.withValues(alpha: 0.6),
                ),
                filled: true,
                fillColor: inputFillColor,
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(fieldRadius),
                  borderSide: BorderSide(color: borderColor),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(fieldRadius),
                  borderSide: BorderSide(color: borderColor),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(fieldRadius),
                  borderSide: BorderSide(
                    color: isDark ? const Color(0xFF4D8FFF) : const Color(0xFF0033CC),
                    width: 1.5,
                  ),
                ),
                suffixIcon: Icon(Icons.arrow_drop_down, color: secondaryTextColor),
              ),
              validator: (v) {
                if (v == null || v.isEmpty) return 'State is required';
                if (!indianStateNames.contains(v)) return 'Please select a valid state';
                return null;
              },
            );
          },
          optionsViewBuilder: (context, onSelected, options) {
            final isDarkTheme = Provider.of<ThemeProvider>(context, listen: false).isDarkMode;
            return Align(
              alignment: Alignment.topLeft,
              child: Material(
                elevation: 4,
                borderRadius: BorderRadius.circular(fieldRadius),
                color: isDarkTheme ? AppColors.darkCardBackground : Colors.white,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 200),
                  child: ListView.builder(
                    padding: EdgeInsets.zero,
                    shrinkWrap: true,
                    itemCount: options.length,
                    itemBuilder: (_, i) {
                      final option = options.elementAt(i);
                      return ListTile(
                        dense: true,
                        title: Text(
                          option,
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            fontSize: fieldFontSize,
                            color: isDarkTheme ? AppColors.darkTextPrimary : const Color(0xFF000000),
                          ),
                        ),
                        onTap: () => onSelected(option),
                      );
                    },
                  ),
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}
