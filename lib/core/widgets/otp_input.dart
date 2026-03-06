import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:smart_auth/smart_auth.dart';

class OTPInput extends StatefulWidget {
  final int length;
  final void Function(String)? onChanged;
  final void Function(String) onCompleted;
  final double boxSize;
  final double fontSize;
  final double spacing;
  final double borderRadius;

  const OTPInput({
    super.key,
    this.length = 4,
    this.onChanged,
    required this.onCompleted,
    this.boxSize = 56,
    this.fontSize = 24,
    this.spacing = 16,
    this.borderRadius = 24,
  });

  @override
  State<OTPInput> createState() => OTPInputState();
}

class OTPInputState extends State<OTPInput> {
  late List<TextEditingController> _controllers;
  late List<FocusNode> _focusNodes;
  final _smartAuth = SmartAuth.instance;
  bool _isAutoFilling = false;

  // Colors
  static const Color _filledBorderColor = Color(0xFF0000D1);
  static const Color _emptyBorderColor = Color(0xFF00C2FF);
  static const Color _backgroundColor = Color(0xFFF6F8FE);

  @override
  void initState() {
    super.initState();
    _controllers = List.generate(widget.length, (_) => TextEditingController());
    _focusNodes = List.generate(widget.length, (_) => FocusNode());

    // Listen for SMS auto-fill via User Consent API (Android)
    _startSmsListener();

    // Add listeners for focus changes to trigger rebuild
    for (var node in _focusNodes) {
      node.addListener(() {
        setState(() {});
      });
    }
  }

  Future<void> _startSmsListener() async {
    try {
      final res = await _smartAuth.getSmsWithUserConsentApi();
      if (res.hasData) {
        final code = res.requireData.code;
        if (code != null && code.length >= widget.length && mounted) {
          _fillOtp(code.substring(0, widget.length));
        }
      }
    } catch (e) {
      debugPrint('SmartAuth SMS listener error: $e');
    }
  }

  void _fillOtp(String code) {
    _isAutoFilling = true;
    // Clear all fields first
    for (var c in _controllers) {
      c.text = '';
    }
    // Fill digits into individual fields
    for (int i = 0; i < widget.length && i < code.length; i++) {
      _controllers[i].text = code[i];
    }
    _isAutoFilling = false;
    setState(() {});
    for (var node in _focusNodes) {
      node.unfocus();
    }
    final otp = _controllers.map((c) => c.text).join();
    widget.onChanged?.call(otp);
    if (otp.length == widget.length) {
      widget.onCompleted(otp);
    }
  }

  /// Clear all OTP input fields
  void clear() {
    for (var controller in _controllers) {
      controller.clear();
    }
    if (_focusNodes.isNotEmpty) {
      _focusNodes[0].requestFocus();
    }
  }

  @override
  void dispose() {
    _smartAuth.removeUserConsentApiListener();
    for (var controller in _controllers) {
      controller.dispose();
    }
    for (var node in _focusNodes) {
      node.dispose();
    }
    super.dispose();
  }

  void _onChanged(String value, int index) {
    if (_isAutoFilling) return;

    // Handle multi-digit paste/autofill (keyboard OTP suggestion)
    if (value.length > 1) {
      final digits = value.replaceAll(RegExp(r'[^0-9]'), '');
      if (digits.isNotEmpty) {
        _fillOtp(digits.length > widget.length
            ? digits.substring(0, widget.length)
            : digits);
      }
      return;
    }

    if (value.length == 1 && index < widget.length - 1) {
      _focusNodes[index + 1].requestFocus();
    }

    String otp = _controllers.map((c) => c.text).join();
    widget.onChanged?.call(otp);

    if (otp.length == widget.length) {
      widget.onCompleted(otp);
    }
  }

  void _onKeyDown(KeyEvent event, int index) {
    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.backspace &&
        _controllers[index].text.isEmpty &&
        index > 0) {
      _focusNodes[index - 1].requestFocus();
      _controllers[index - 1].clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    return AutofillGroup(
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: List.generate(
          widget.length,
          (index) {
            final hasValue = _controllers[index].text.isNotEmpty;
            final isFocused = _focusNodes[index].hasFocus;

            return Container(
              margin: EdgeInsets.only(right: index < widget.length - 1 ? widget.spacing : 0),
              child: SizedBox(
                width: widget.boxSize,
                height: widget.boxSize,
                child: KeyboardListener(
                  focusNode: FocusNode(),
                  onKeyEvent: (event) => _onKeyDown(event, index),
                  child: TextFormField(
                    controller: _controllers[index],
                    focusNode: _focusNodes[index],
                    textAlign: TextAlign.center,
                    keyboardType: TextInputType.number,
                    autofillHints: index == 0
                        ? const [AutofillHints.oneTimeCode]
                        : null,
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: widget.fontSize,
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFF0D0D26),
                    ),
                    decoration: InputDecoration(
                      counterText: '',
                      filled: true,
                      fillColor: _backgroundColor,
                      contentPadding: EdgeInsets.zero,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(widget.borderRadius),
                        borderSide: BorderSide(
                          color: hasValue ? _filledBorderColor : _emptyBorderColor,
                          width: 1,
                        ),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(widget.borderRadius),
                        borderSide: BorderSide(
                          color: hasValue ? _filledBorderColor : _emptyBorderColor,
                          width: 1,
                        ),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(widget.borderRadius),
                        borderSide: BorderSide(
                          color: isFocused ? _emptyBorderColor : (hasValue ? _filledBorderColor : _emptyBorderColor),
                          width: 1,
                        ),
                      ),
                    ),
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                    ],
                    onChanged: (value) => _onChanged(value, index),
                    onTap: () {
                      _controllers[index].clear();
                    },
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
