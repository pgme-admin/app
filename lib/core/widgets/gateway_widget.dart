import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:pgme/core/constants/api_constants.dart';
import 'package:pgme/core/models/gateway_models.dart';
import 'package:pgme/core/utils/responsive_helper.dart';

class GatewayWidget extends StatefulWidget {
  final GatewaySession paymentSession;
  final Function(GatewayResponse) onPaymentComplete;
  final VoidCallback? onCancel;

  const GatewayWidget({
    super.key,
    required this.paymentSession,
    required this.onPaymentComplete,
    this.onCancel,
  });

  @override
  State<GatewayWidget> createState() => _GatewayWidgetState();
}

class _GatewayWidgetState extends State<GatewayWidget> {
  late final WebViewController _controller;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();

    debugPrint('');
    debugPrint('=== GatewayWidget INIT ===');
    debugPrint('Session ID: "${widget.paymentSession.paymentSessionId}"');
    debugPrint('Amount: ${widget.paymentSession.amount} ${widget.paymentSession.currency}');
    debugPrint('=============================');
    debugPrint('');

    _initializeWebView();
  }

  void _initializeWebView() {
    // Build the backend checkout URL with gateway session details
    final baseUrl = ApiConstants.baseUrl.replaceAll('/api/v1', '');
    final checkoutUrl = '$baseUrl/checkout'
        '?session_id=${widget.paymentSession.paymentSessionId}'
        '&amount=${widget.paymentSession.amount}'
        '&currency=${widget.paymentSession.currency}';

    debugPrint('WebView: Loading checkout from $checkoutUrl');

    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.white)
      ..setOnConsoleMessage((JavaScriptConsoleMessage message) {
        debugPrint('JS [${message.level.name}]: ${message.message}');
      })
      ..addJavaScriptChannel(
        'FlutterPayment',
        onMessageReceived: (JavaScriptMessage message) {
          debugPrint('JS->Flutter: ${message.message}');
          _handlePaymentResponse(message.message);
        },
      )
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (url) {
            debugPrint('WebView started: $url');
          },
          onPageFinished: (url) {
            debugPrint('WebView finished: $url');
            setState(() {
              _isLoading = false;
            });
          },
          onWebResourceError: (WebResourceError error) {
            debugPrint('WebView ERROR: ${error.errorCode} - ${error.description}');
          },
          onNavigationRequest: (NavigationRequest request) {
            debugPrint('WebView nav: ${request.url}');
            final uri = Uri.parse(request.url);
            // Allow only http/https in WebView - launch everything else externally
            // This handles all UPI apps: upi://, paytmmp://, phonepe://, gpay://,
            // tez://, bhim://, cred://, intent://, etc.
            if (uri.scheme != 'http' && uri.scheme != 'https' && uri.scheme != 'about') {
              debugPrint('Launching external app: ${request.url}');
              _launchExternal(request.url);
              return NavigationDecision.prevent;
            }
            return NavigationDecision.navigate;
          },
        ),
      )
      // Load from backend - gives proper HTTPS origin for Gateway SDK
      ..loadRequest(Uri.parse(checkoutUrl));
  }

  /// Opens a non-web link from the checkout page in the app that handles it.
  ///
  /// Android checkout pages open UPI apps with `intent://` links, e.g.
  /// `intent://pay?pa=...#Intent;scheme=upi;package=com.phonepe.app;end`.
  /// Nothing handles the `intent` scheme itself, so launching it as-is did
  /// nothing: open the target scheme (`upi://pay?pa=...`) instead, then the
  /// page's own fallback URL if it gave one.
  Future<void> _launchExternal(String url) async {
    Future<bool> tryLaunch(Uri target) async {
      try {
        return await launchUrl(target, mode: LaunchMode.externalApplication);
      } catch (e) {
        debugPrint('Could not open $target: $e');
        return false;
      }
    }

    if (!url.startsWith('intent:')) {
      await tryLaunch(Uri.parse(url));
      return;
    }
    final marker = url.indexOf('#Intent;');
    final params = <String, String>{};
    if (marker >= 0) {
      for (final part in url.substring(marker + '#Intent;'.length).split(';')) {
        final eq = part.indexOf('=');
        if (eq > 0) params[part.substring(0, eq)] = part.substring(eq + 1);
      }
    }
    final scheme = params['scheme'];
    if (scheme != null) {
      final rest = (marker >= 0 ? url.substring(0, marker) : url)
          .substring('intent:'.length);
      if (await tryLaunch(Uri.parse('$scheme:$rest'))) return;
    }
    final fallback = params['S.browser_fallback_url'];
    if (fallback != null) {
      await tryLaunch(Uri.parse(Uri.decodeComponent(fallback)));
    }
  }

  void _handlePaymentResponse(String message) {
    try {
      debugPrint('Parsing gateway response: $message');
      final Map<String, dynamic> data = json.decode(message);

      final response = GatewayResponse(
        status: data['status'] as String,
        paymentId: data['payment_id'] as String?,
        paymentSessionId: data['payment_session_id'] as String?,
        signature: data['signature'] as String?,
        errorMessage: data['error_message'] as String?,
      );

      debugPrint('Gateway result: status=${response.status}, paymentId=${response.paymentId}');
      widget.onPaymentComplete(response);
    } catch (e) {
      debugPrint('Error parsing gateway response: $e');
      widget.onPaymentComplete(
        GatewayResponse(
          status: 'failed',
          errorMessage: 'Failed to process payment response',
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isTablet = ResponsiveHelper.isTablet(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Continue',
          style: TextStyle(fontSize: isTablet ? 20 : null),
        ),
        toolbarHeight: isTablet ? 64 : null,
        automaticallyImplyLeading: false,
        elevation: 0,
      ),
      body: Stack(
        children: [
          WebViewWidget(controller: _controller),
          if (_isLoading)
            Container(
              color: Colors.white,
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    SizedBox(
                      width: isTablet ? 48 : 36,
                      height: isTablet ? 48 : 36,
                      child: CircularProgressIndicator(
                        strokeWidth: isTablet ? 4.0 : 3.0,
                      ),
                    ),
                    SizedBox(height: isTablet ? 24 : 16),
                    Text(
                      'Loading...',
                      style: TextStyle(
                        fontSize: isTablet ? 18 : 16,
                        color: Colors.grey,
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
}
