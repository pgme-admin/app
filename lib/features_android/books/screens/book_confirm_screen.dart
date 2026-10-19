import 'dart:io';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:pgme/core_android/models/gateway_models.dart';
import 'package:pgme/core_android/providers/theme_provider.dart';
import 'package:pgme/core_android/services/user_service.dart';
import 'package:pgme/core_android/theme/app_theme.dart';
import 'package:pgme/core_android/widgets/gateway_widget.dart';
import 'package:pgme/core_android/widgets/address_bottom_sheet.dart';
import 'package:pgme/core_android/models/address_model.dart';
import 'package:pgme/features_android/books/providers/book_provider.dart';
import 'package:pgme/core_android/utils/responsive_helper.dart';
import 'package:pgme/core_android/widgets/app_dialog.dart';
import 'package:pgme/core_android/utils/web_store_launcher.dart';

class BookConfirmScreen extends StatefulWidget {
  const BookConfirmScreen({super.key});

  @override
  State<BookConfirmScreen> createState() => _BookConfirmScreenState();
}

class _BookConfirmScreenState extends State<BookConfirmScreen>
    with WidgetsBindingObserver {
  final _formKey = GlobalKey<FormState>();
  final _recipientNameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _addressController = TextEditingController();

  bool _isLoading = false;
  bool _isLoadingUser = true;

  @override
  void initState() {
    super.initState();
    if (Platform.isIOS) WidgetsBinding.instance.addObserver(this);
    _loadUserDetails();
  }

  @override
  void dispose() {
    if (Platform.isIOS) WidgetsBinding.instance.removeObserver(this);
    _recipientNameController.dispose();
    _phoneController.dispose();
    _addressController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed &&
        WebStoreLauncher.awaitingExternalPurchase) {
      WebStoreLauncher.clearAwaitingPurchase();
      _loadUserDetails();
    }
  }

  Future<void> _loadUserDetails() async {
    try {
      final userService = UserService();
      final user = await userService.getProfile();

      if (mounted) {
        setState(() {
          _recipientNameController.text = user.name ?? '';
          _phoneController.text = user.phoneNumber.replaceAll('+91', '') ?? '';
          _addressController.text = user.address ?? '';
          _isLoadingUser = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoadingUser = false);
      }
    }
  }

  Future<void> _processOrder() async {
    if (!_formKey.currentState!.validate()) return;

    // iOS: redirect to web store
    if (WebStoreLauncher.shouldUseWebStore) {
      WebStoreLauncher.openProductPage(context, productType: 'books', productId: '');
      return;
    }

    // Show billing address bottom sheet before payment
    Address? savedAddress;
    try {
      final userService = UserService();
      final user = await userService.getProfile();
      if (user.billingAddress != null && user.billingAddress!.isNotEmpty) {
        savedAddress = Address.fromJson(user.billingAddress!);
      }
    } catch (_) {}

    if (!mounted) return;

    final addressResult = await showAddressSheet(
      context,
      initialAddress: savedAddress,
      showShippingOption: true,
    );

    if (addressResult == null || !mounted) return;
    final billingAddress = addressResult['billing']!;
    final shippingAddressStructured = addressResult['shipping'];

    final provider = Provider.of<BookProvider>(context, listen: false);

    setState(() => _isLoading = true);

    try {
      // Step 1: Create Zoho payment session
      final paymentSession = await provider.initSession(
        recipientName: _recipientNameController.text.trim(),
        shippingPhone: _phoneController.text.trim(),
        shippingAddress: _addressController.text.trim(),
        billingAddress: billingAddress.toJson(),
        shippingAddressStructured: shippingAddressStructured?.toJson(),
      );

      if (!mounted) return;

      // Step 2: Show Zoho payment widget
      final result = await Navigator.of(context, rootNavigator: true).push<GatewayResponse>(
        MaterialPageRoute(
          builder: (context) => GatewayWidget(
            paymentSession: paymentSession,
            onPaymentComplete: (response) {
              Navigator.pop(context, response);
            },
          ),
          fullscreenDialog: true,
        ),
      );

      // Step 3: Handle payment response
      if (result != null && mounted) {
        if (result.isSuccess) {
          // Verify payment with backend
          final verification = await provider.confirmSession(
            paymentSessionId: result.paymentSessionId!,
            paymentId: result.paymentId!,
            signature: result.signature,
          );

          if (verification.success && mounted) {
            context.go('/book-request-confirmation/${verification.purchaseId}');
          } else if (mounted) {
            _showError('Payment verification failed. Please contact support.');
          }
        } else if (result.isFailed) {
          _showError('Payment failed: ${result.errorMessage ?? "Unknown error"}');
        } else if (result.isCancelled) {
          _showInfo('Payment cancelled');
        }
      }
    } catch (e) {
      if (mounted) {
        _showError('Error processing order: $e');
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    showAppDialog(context, message: message.replaceAll('Exception: ', ''), type: AppDialogType.info);
  }

  void _showInfo(String message) {
    if (!mounted) return;
    showAppDialog(context, message: message, type: AppDialogType.info);
  }

  @override
  Widget build(BuildContext context) {
    final topPadding = MediaQuery.of(context).padding.top;
    final bottomPadding = MediaQuery.of(context).padding.bottom;
    final themeProvider = Provider.of<ThemeProvider>(context);
    final isDark = themeProvider.isDarkMode;
    final isTablet = ResponsiveHelper.isTablet(context);

    // Theme-aware colors
    final backgroundColor = isDark ? AppColors.darkBackground : Colors.white;
    final textColor = isDark ? AppColors.darkTextPrimary : const Color(0xFF000000);
    final secondaryTextColor = isDark ? AppColors.darkTextSecondary : const Color(0xFF666666);
    final cardBgColor = isDark ? AppColors.darkCardBackground : Colors.white;
    final borderColor = isDark ? AppColors.darkDivider : const Color(0xFFE0E0E0);
    final buttonColor = isDark ? const Color(0xFF1A1A4D) : const Color(0xFF000080);
    final inputFillColor = isDark ? AppColors.darkSurface : const Color(0xFFF5F5F5);

    final hPadding = isTablet ? ResponsiveHelper.horizontalPadding(context) : 16.0;

    return Scaffold(
      backgroundColor: backgroundColor,
      body: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: ResponsiveHelper.getMaxContentWidth(context)),
          child: Column(
        children: [
          // Header
          Padding(
            padding: EdgeInsets.only(top: topPadding + (isTablet ? 21 : 16), left: hPadding, right: hPadding),
            child: Row(
              children: [
                GestureDetector(
                  onTap: () => context.pop(),
                  child: Icon(Icons.arrow_back, size: isTablet ? 30 : 24, color: textColor),
                ),
                const Spacer(),
                Text(
                  Platform.isIOS ? 'Confirm' : 'Checkout',
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

          SizedBox(height: isTablet ? 21 : 16),

          // Form
          Expanded(
            child: _isLoadingUser
                ? const Center(child: CircularProgressIndicator())
                : SingleChildScrollView(
                    padding: EdgeInsets.symmetric(horizontal: hPadding),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Shipping Address Section
                          Text(
                            'Shipping Address',
                            style: TextStyle(
                              fontFamily: 'Poppins',
                              fontWeight: FontWeight.w600,
                              fontSize: isTablet ? 20 : 16,
                              color: textColor,
                            ),
                          ),
                          SizedBox(height: isTablet ? 21 : 16),

                          // Recipient Name
                          TextFormField(
                            controller: _recipientNameController,
                            decoration: InputDecoration(
                              labelText: 'Recipient Name',
                              hintText: 'Enter full name',
                              filled: true,
                              fillColor: inputFillColor,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(isTablet ? 16 : 12),
                                borderSide: BorderSide(color: borderColor),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(isTablet ? 16 : 12),
                                borderSide: BorderSide(color: borderColor),
                              ),
                            ),
                            validator: (value) {
                              if (value == null || value.trim().isEmpty) {
                                return 'Please enter recipient name';
                              }
                              return null;
                            },
                          ),
                          SizedBox(height: isTablet ? 21 : 16),

                          // Phone Number
                          TextFormField(
                            controller: _phoneController,
                            keyboardType: TextInputType.phone,
                            maxLength: 10,
                            decoration: InputDecoration(
                              labelText: 'Phone Number',
                              hintText: '10 digit phone number',
                              prefixText: '+91 ',
                              filled: true,
                              fillColor: inputFillColor,
                              counterText: '',
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(isTablet ? 16 : 12),
                                borderSide: BorderSide(color: borderColor),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(isTablet ? 16 : 12),
                                borderSide: BorderSide(color: borderColor),
                              ),
                            ),
                            validator: (value) {
                              if (value == null || value.trim().isEmpty) {
                                return 'Please enter phone number';
                              }
                              if (!RegExp(r'^[0-9]{10}$').hasMatch(value.trim())) {
                                return 'Please enter valid 10 digit phone number';
                              }
                              return null;
                            },
                          ),
                          SizedBox(height: isTablet ? 21 : 16),

                          // Address
                          TextFormField(
                            controller: _addressController,
                            maxLines: 4,
                            maxLength: 500,
                            decoration: InputDecoration(
                              labelText: 'Delivery Address',
                              hintText: 'Enter complete address with pincode',
                              alignLabelWithHint: true,
                              filled: true,
                              fillColor: inputFillColor,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(isTablet ? 16 : 12),
                                borderSide: BorderSide(color: borderColor),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(isTablet ? 16 : 12),
                                borderSide: BorderSide(color: borderColor),
                              ),
                            ),
                            validator: (value) {
                              if (value == null || value.trim().isEmpty) {
                                return 'Please enter delivery address';
                              }
                              if (value.trim().length < 20) {
                                return 'Please enter a complete address';
                              }
                              return null;
                            },
                          ),

                          SizedBox(height: isTablet ? 31 : 24),

                          // Order Summary Section
                          Text(
                            Platform.isIOS ? 'Summary' : 'Order Summary',
                            style: TextStyle(
                              fontFamily: 'Poppins',
                              fontWeight: FontWeight.w600,
                              fontSize: isTablet ? 20 : 16,
                              color: textColor,
                            ),
                          ),
                          SizedBox(height: isTablet ? 21 : 16),

                          Consumer<BookProvider>(
                            builder: (context, provider, _) {
                              return Container(
                                padding: EdgeInsets.all(isTablet ? 20 : 16),
                                decoration: BoxDecoration(
                                  color: cardBgColor,
                                  borderRadius: BorderRadius.circular(isTablet ? 16 : 12),
                                  border: Border.all(color: borderColor),
                                ),
                                child: Column(
                                  children: [
                                    // Items
                                    ...provider.cartItems.map((item) => Padding(
                                          padding: EdgeInsets.only(bottom: isTablet ? 10 : 8),
                                          child: Row(
                                            children: [
                                              Expanded(
                                                child: Text(
                                                  '${item.title} x${item.quantity}',
                                                  style: TextStyle(
                                                    fontSize: isTablet ? 17 : 14,
                                                    color: textColor,
                                                  ),
                                                ),
                                              ),
                                              Text(
                                                '\u{20B9}${item.totalPrice}',
                                                style: TextStyle(
                                                  fontSize: isTablet ? 17 : 14,
                                                  color: textColor,
                                                ),
                                              ),
                                            ],
                                          ),
                                        )),
                                    Divider(color: borderColor),
                                    SizedBox(height: isTablet ? 10 : 8),
                                    // Subtotal
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Text(
                                          'Subtotal',
                                          style: TextStyle(
                                            fontSize: isTablet ? 17 : 14,
                                            color: secondaryTextColor,
                                          ),
                                        ),
                                        Text(
                                          '\u{20B9}${provider.cartSubtotal}',
                                          style: TextStyle(
                                            fontSize: isTablet ? 17 : 14,
                                            color: textColor,
                                          ),
                                        ),
                                      ],
                                    ),
                                    SizedBox(height: isTablet ? 10 : 8),
                                    // Shipping
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Text(
                                          'Shipping',
                                          style: TextStyle(
                                            fontSize: isTablet ? 17 : 14,
                                            color: secondaryTextColor,
                                          ),
                                        ),
                                        Text(
                                          '\u{20B9}${provider.shippingCost}',
                                          style: TextStyle(
                                            fontSize: isTablet ? 17 : 14,
                                            color: textColor,
                                          ),
                                        ),
                                      ],
                                    ),
                                    SizedBox(height: isTablet ? 10 : 8),
                                    Divider(color: borderColor),
                                    SizedBox(height: isTablet ? 10 : 8),
                                    // Total
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Text(
                                          'Total',
                                          style: TextStyle(
                                            fontSize: isTablet ? 22 : 18,
                                            fontWeight: FontWeight.w600,
                                            color: textColor,
                                          ),
                                        ),
                                        Text(
                                          '\u{20B9}${provider.cartTotal}',
                                          style: TextStyle(
                                            fontSize: isTablet ? 22 : 18,
                                            fontWeight: FontWeight.w600,
                                            color: textColor,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                          SizedBox(height: isTablet ? 130 : 100), // Space for button
                        ],
                      ),
                    ),
                  ),
          ),

          // Place Order Button
          Container(
            padding: EdgeInsets.fromLTRB(hPadding, isTablet ? 20 : 16, hPadding, bottomPadding + (isTablet ? 21 : 16)),
            decoration: BoxDecoration(
              color: cardBgColor,
              border: Border(
                top: BorderSide(color: borderColor),
              ),
            ),
            child: SizedBox(
              width: double.infinity,
              height: isTablet ? 60 : 50,
              child: ElevatedButton(
                onPressed: _isLoading ? null : _processOrder,
                style: ElevatedButton.styleFrom(
                  backgroundColor: buttonColor,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: buttonColor.withValues(alpha: 0.5),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(isTablet ? 16 : 12),
                  ),
                ),
                child: _isLoading
                    ? SizedBox(
                        height: isTablet ? 30 : 24,
                        width: isTablet ? 30 : 24,
                        child: const CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2,
                        ),
                      )
                    : Text(
                        Platform.isIOS ? 'Confirm' : 'Place Order',
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          fontWeight: FontWeight.w600,
                          fontSize: isTablet ? 20 : 16,
                        ),
                      ),
              ),
            ),
          ),
        ],
      ),
        ),
      ),
    );
  }
}
