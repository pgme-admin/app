# PGME notes for this plugin

This is `flutter_zoom_meeting_sdk` 0.0.11 from pub.dev (Apache-2.0), kept in the app repository
because it carries PGME changes. Zoom's own SDK binaries are **not** in git: this repository is
public, and the biggest files exceed GitHub's 100 MB limit.

Zoom Meeting SDK version: **6.4.3** on both platforms. Zoom enforces a minimum SDK version every
quarter (6.0.2 as of November 2026, per Zoom's Software Quarterly Lifecycle Policy). When Zoom
raises it, update Android and iOS together.

## Android: nothing to download

`android/build.gradle` depends on Zoom's official Maven Central package
`us.zoom.meetingsdk:zoomsdk:6.4.3`. It is published by Zoom Communications, Inc. and PGP-signed.
Gradle downloads it, and the SDK's own dependencies, on the first build.

The upstream setup (copy `mobilertc.aar` and a hand-edited `build.gradle` from the Zoom Marketplace
download into `android/libs/`) is no longer used. That aar is 275 MB and could not be committed.

The release shrinker rules for the SDK are in the app's `android/app/proguard-rules.pro`.

## iOS: copy two frameworks from Zoom's SDK download

Download "Meeting SDK for iOS" **6.4.3.23800** from the Zoom App Marketplace. A Zoom developer
login is required. From its `lib/` folder:

| From the SDK zip | To |
|---|---|
| `lib/MobileRTC.xcframework` | `<app>/ios/MobileRTC.xcframework` |
| `lib/MobileRTCScreenShare.xcframework` | `<app>/ios/MobileRTCScreenShare.xcframework` |
| `lib/zoomcml.xcframework` | `packages/flutter_zoom_meeting_sdk/ios/zoomcml.xcframework` |

Git already has the frameworks' headers and metadata under `<app>/ios/`. Only the binaries are
missing, so copying over them is safe. Then run `pod install` in `<app>/ios`.

## Changes from upstream 0.0.11

- `android/build.gradle`: Zoom SDK from Maven Central (above). Removed the `jcenter()` + `flatDir`
  repositories the upstream plugin added to every project.
- `android/.../FlutterZoomMeetingSdkPlugin.kt`, `onDetachedFromEngine`: calls
  `ZoomSDK.uninitialize()` only when the SDK was initialized, and catches native failures. Closing
  the app with Back on Android 10 before any meeting used to crash with `UnsatisfiedLinkError`.
- `ios/flutter_zoom_meeting_sdk.podspec`: compiles and links against `<app>/ios/MobileRTC.xcframework`
  (the Runner target embeds it), and vendors `zoomcml.xcframework` so CocoaPods embeds it.
