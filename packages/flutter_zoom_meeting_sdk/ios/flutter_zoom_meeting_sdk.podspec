#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
# Run `pod lib lint flutter_zoom_meeting_sdk.podspec` to validate before publishing.
#
Pod::Spec.new do |s|
  s.name             = 'flutter_zoom_meeting_sdk'
  s.version          = '0.0.1'
  s.summary          = 'A new Flutter plugin project.'
  s.description      = <<-DESC
A new Flutter plugin project.
                       DESC
  s.homepage         = 'http://example.com'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Your Company' => 'email@example.com' }
  s.source           = { :path => '.' }
  s.source_files = 'Classes/**/*'
  s.dependency 'Flutter'

  # PGME: Zoom Meeting SDK 6.4.3.23800 lives in <app>/ios (the plugin does not bundle it).
  # - MobileRTC: the plugin only compiles/links against it ("Do Not Embed"); the Runner
  #   target links + embeds it. Search path is <app>/ios (= ${PODS_ROOT}/..), set here so it
  #   survives every `pod install`.
  # - zoomcml: required by the SDK (Zoom's sample embeds it); copy lives in this plugin's
  #   ios/ folder and is vendored so CocoaPods links + embeds it without editing Runner.xcodeproj.
  s.vendored_frameworks = 'zoomcml.xcframework'
  s.platform = :ios, '12.0'

  # Flutter.framework does not contain a i386 slice.
  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386',
    'FRAMEWORK_SEARCH_PATHS[sdk=iphoneos*]' => '$(inherited) "${PODS_ROOT}/../MobileRTC.xcframework/ios-arm64"',
    'FRAMEWORK_SEARCH_PATHS[sdk=iphonesimulator*]' => '$(inherited) "${PODS_ROOT}/../MobileRTC.xcframework/ios-arm64_x86_64-simulator"',
    'OTHER_LDFLAGS' => '$(inherited) -framework MobileRTC',
  }
  s.swift_version = '5.0'

  # If your plugin requires a privacy manifest, for example if it uses any
  # required reason APIs, update the PrivacyInfo.xcprivacy file to describe your
  # plugin's privacy impact, and then uncomment this line. For more information,
  # see https://developer.apple.com/documentation/bundleresources/privacy_manifest_files
  # s.resource_bundles = {'flutter_zoom_meeting_sdk_privacy' => ['Resources/PrivacyInfo.xcprivacy']}
end
