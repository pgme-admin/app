import 'package:flutter_test/flutter_test.dart';
import 'package:pgme/core/utils/pdf_engine_policy.dart';

void main() {
  test('iOS always uses pdfrx', () {
    expect(PdfEnginePolicy.decide(isAndroid: false, isIOS: true, androidSdkInt: null), isTrue);
  });
  test('Android below 15 (and unknown version) uses pdfrx', () {
    expect(PdfEnginePolicy.decide(isAndroid: true, androidSdkInt: 29), isTrue);
    expect(PdfEnginePolicy.decide(isAndroid: true, androidSdkInt: 34), isTrue);
    expect(PdfEnginePolicy.decide(isAndroid: true, androidSdkInt: null), isTrue);
  });
  test('Android 15+ keeps the Syncfusion reader', () {
    expect(PdfEnginePolicy.decide(isAndroid: true, androidSdkInt: 35), isFalse);
    expect(PdfEnginePolicy.decide(isAndroid: true, androidSdkInt: 36), isFalse);
  });
}
