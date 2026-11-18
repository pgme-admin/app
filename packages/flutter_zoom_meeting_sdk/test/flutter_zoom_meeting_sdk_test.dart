import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_zoom_meeting_sdk/flutter_zoom_meeting_sdk.dart';
import 'package:flutter_zoom_meeting_sdk/flutter_zoom_meeting_sdk_platform_interface.dart';
import 'package:flutter_zoom_meeting_sdk/flutter_zoom_meeting_sdk_method_channel.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class MockFlutterZoomMeetingSdkPlatform
    with MockPlatformInterfaceMixin
    implements FlutterZoomMeetingSdkPlatform {

  @override
  Future<String?> getPlatformVersion() => Future.value('42');
}

void main() {
  final FlutterZoomMeetingSdkPlatform initialPlatform = FlutterZoomMeetingSdkPlatform.instance;

  test('$MethodChannelFlutterZoomMeetingSdk is the default instance', () {
    expect(initialPlatform, isInstanceOf<MethodChannelFlutterZoomMeetingSdk>());
  });

  test('getPlatformVersion', () async {
    FlutterZoomMeetingSdk flutterZoomMeetingSdkPlugin = FlutterZoomMeetingSdk();
    MockFlutterZoomMeetingSdkPlatform fakePlatform = MockFlutterZoomMeetingSdkPlatform();
    FlutterZoomMeetingSdkPlatform.instance = fakePlatform;

    expect(await flutterZoomMeetingSdkPlugin.getPlatformVersion(), '42');
  });
}
