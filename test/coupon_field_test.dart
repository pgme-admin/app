import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pgme/core/services/coupon_service.dart';
import 'package:pgme/core/widgets/coupon_field.dart';

/// The app previously only ever called `/coupons/validate`, so a customer had
/// to already know a code — the web store's suggestion chips had no
/// counterpart here. These cover the chip path end to end.
class _FakeCouponApi implements CouponApi {
  _FakeCouponApi({this.visible = const [], this.preview});

  final List<VisibleCoupon> visible;
  final CouponPreview? preview;

  /// Codes passed to [validateCoupon], in order.
  final List<String> validated = [];

  @override
  Future<List<VisibleCoupon>> listVisibleCoupons({
    required String purchaseType,
    String? productId,
    int? tierIndex,
    List<Map<String, dynamic>>? items,
  }) async =>
      visible;

  @override
  Future<CouponPreview> validateCoupon({
    required String code,
    required String purchaseType,
    String? productId,
    int? tierIndex,
    List<Map<String, dynamic>>? items,
  }) async {
    validated.add(code);
    return preview ??
        CouponPreview(valid: false, beneficial: false, reason: 'nope');
  }
}

Widget _host(CouponApi api, {void Function(String?, num)? onChanged}) {
  return MaterialApp(
    home: Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(8),
        child: CouponField(
          purchaseType: 'package',
          productId: 'pkg-1',
          service: api,
          onChanged: onChanged ?? (_, __) {},
        ),
      ),
    ),
  );
}

void main() {
  group('CouponField suggestions', () {
    testWidgets('offers each visible coupon with its code and discount', (tester) async {
      final api = _FakeCouponApi(visible: [
        VisibleCoupon(
          code: 'TEST COUPON',
          description: 'Launch offer',
          discountType: 'percentage',
          discountValue: 20,
        ),
        VisibleCoupon(code: 'FLAT500', discountType: 'fixed', discountValue: 500),
      ]);

      await tester.pumpWidget(_host(api));
      await tester.pumpAndSettle();

      expect(find.text('TEST COUPON'), findsOneWidget);
      expect(find.text('20% off'), findsOneWidget);
      expect(find.text('Launch offer'), findsOneWidget);
      expect(find.text('FLAT500'), findsOneWidget);
      expect(find.text('₹500 off'), findsOneWidget);
    });

    testWidgets('shows no chips when nothing is marked visible', (tester) async {
      await tester.pumpWidget(_host(_FakeCouponApi()));
      await tester.pumpAndSettle();

      // Only the manual field's own Apply button remains.
      expect(find.text('Apply'), findsOneWidget);
      expect(find.byType(TextField), findsOneWidget);
    });

    testWidgets('tapping a suggestion validates it and shows it as applied', (tester) async {
      final api = _FakeCouponApi(
        visible: [
          VisibleCoupon(code: 'SAVE20', discountType: 'percentage', discountValue: 20),
        ],
        preview: CouponPreview(
          valid: true,
          beneficial: true,
          code: 'SAVE20',
          couponDiscount: 700,
        ),
      );
      String? reportedCode;
      num reportedDiscount = 0;

      await tester.pumpWidget(_host(api, onChanged: (c, d) {
        reportedCode = c;
        reportedDiscount = d;
      }));
      await tester.pumpAndSettle();

      // The chip's Apply, not the manual field's.
      await tester.tap(find.text('Apply').first);
      await tester.pumpAndSettle();

      expect(api.validated, ['SAVE20'],
          reason: 'a suggested code must still go through validation, not be trusted');
      expect(find.textContaining('SAVE20'), findsOneWidget);
      expect(reportedCode, 'SAVE20');
      expect(reportedDiscount, 700);
    });

    testWidgets('a suggestion the server rejects is not shown as applied', (tester) async {
      final api = _FakeCouponApi(
        visible: [
          VisibleCoupon(code: 'STALE', discountType: 'fixed', discountValue: 100),
        ],
        preview: CouponPreview(
          valid: false,
          beneficial: false,
          reason: 'This coupon does not apply to the selected item(s)',
        ),
      );
      String? reportedCode = 'unset';

      await tester.pumpWidget(_host(api, onChanged: (c, _) => reportedCode = c));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Apply').first);
      await tester.pumpAndSettle();

      expect(find.text('This coupon does not apply to the selected item(s)'), findsOneWidget);
      expect(reportedCode, isNull, reason: 'nothing should be reported as applied');
    });
  });
}
