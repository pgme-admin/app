import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pgme/core/constants/api_constants.dart';
import 'package:pgme/core/services/storage_service.dart';

// Regression tests for the "session expired" bug: the app used to send
// androidInfo.id (Android's Build.ID — the OS build fingerprint) as the
// device_id on every request. Build.ID changes on every OS/security update,
// so the backend stopped recognising the device and force-logged users out
// with "session terminated from another device", even on a single device
// nobody else had touched. The fix persists our own random id instead of
// deriving it from OS device info.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    // getOrCreateDeviceId() caches in memory for the app's lifetime, which
    // in a real app only resets on process restart. Reset it here so each
    // test observes a clean "first call this run" state.
    StorageService().resetDeviceIdCacheForTesting();
  });

  group('StorageService.getOrCreateDeviceId', () {
    test('generates a well-formed v4 UUID and persists it when nothing is stored yet', () async {
      SharedPreferences.setMockInitialValues({});

      final id = await StorageService().getOrCreateDeviceId();

      final uuidV4 = RegExp(
        r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
      );
      expect(id, isNot('unknown'));
      expect(uuidV4.hasMatch(id), isTrue, reason: 'got: $id');

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(ApiConstants.deviceIdKey), id);
    });

    test('reuses an id already persisted from a previous app run, rather than generating a new one', () async {
      const seeded = 'seeded-device-id-from-earlier-install';
      SharedPreferences.setMockInitialValues({
        ApiConstants.deviceIdKey: seeded,
      });

      final id = await StorageService().getOrCreateDeviceId();

      // The old bug: recomputing from Build.ID on every call meant this
      // could silently change to something other than what was stored,
      // which is exactly what triggered the spurious forced logouts.
      expect(id, seeded);
    });

    test('returns the same value on repeated calls within one app run (no re-derivation)', () async {
      SharedPreferences.setMockInitialValues({});

      final first = await StorageService().getOrCreateDeviceId();
      final second = await StorageService().getOrCreateDeviceId();

      expect(second, first);
    });
  });
}
