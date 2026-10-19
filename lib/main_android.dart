/// Android entry point — deliberately a thin alias for [lib/main.dart].
///
/// This file used to boot a parallel `core_android/` + `features_android/`
/// tree. The two trees drifted, so which app you got depended on the build
/// command: `flutter build apk` (which defaults to lib/main.dart) shipped
/// Workshops and the All Packages card, while
/// `flutter build apk -t lib/main_android.dart` silently shipped a build
/// missing both, and missing lib/main.dart's screen-capture lock and memory
/// monitor.
///
/// Rather than keep two copies honest by hand, this target now runs the same
/// app. Both commands produce an identical APK, so a feature added once can
/// never be missing from "the other build".
///
/// The `features_android/` tree is no longer reachable from any entry point;
/// treat `core/` + `features/` as the app. (`main_ios.dart` is genuinely
/// separate — iOS runs reader-mode with no purchase or payment surfaces.)
library;

import 'package:pgme/main.dart' as app;

Future<void> main() => app.main();
