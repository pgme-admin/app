import 'package:flutter_test/flutter_test.dart';
import 'package:pgme/core/utils/pdf_engine_policy.dart';

void main() {
  test('iOS always uses pdfrx', () {
    expect(PdfEnginePolicy.decide(isAndroid: false, isIOS: true, androidSdkInt: null), isTrue);
  });
  test('every Android version (and unknown version) uses pdfrx', () {
    for (final sdk in [26, 29, 34, 35, 36, null]) {
      expect(PdfEnginePolicy.decide(isAndroid: true, androidSdkInt: sdk), isTrue,
          reason: 'Android API $sdk');
    }
  });
  test('other platforms keep the Syncfusion reader', () {
    expect(PdfEnginePolicy.decide(isAndroid: false, androidSdkInt: null), isFalse);
  });
}
