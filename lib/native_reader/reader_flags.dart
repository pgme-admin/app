import 'dart:io' show Platform;

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'package:pgme/core/services/app_settings_service.dart';
import 'package:pgme/core/services/storage_service.dart';

/// Which reader surface a gate check is for. The two surfaces roll out on
/// independent percentages so the video split view can lag behind (or be
/// held at 0%) while the full-screen reader advances.
enum ReaderSurface { notes, split }

/// Server-driven gate that decides, per user and per device, whether to use
/// the new native PDF reader (Jetpack PDF on Android, PDFKit on iOS) or the
/// current viewer.
///
/// ## Safety contract
///
/// This class is the single kill switch for the entire native-reader
/// rollout. It is **fail-closed**: if anything is missing or throws — no
/// network, absent settings keys, an unparseable value — [shouldUseNative]
/// returns `false` and the caller falls back to the existing viewer. A fresh
/// install that has never reached `/app-settings` therefore behaves exactly
/// as it does today. Setting the rollout percent to 0 on the backend reverts
/// every user on their next launch with no app release.
///
/// Nothing here renders a PDF or touches a platform channel; it only answers
/// a boolean. It is inert until a router or the split view calls it, which is
/// wired in a later phase.
///
/// ## Server keys (all in `/app-settings`, all optional)
///
///   * `native_pdf_percent`          — 0..100 rollout for the notes reader (default 0)
///   * `native_pdf_split_percent`    — 0..100 rollout for the video split view (default 0)
///   * `native_pdf_min_build`        — minimum app build number required (default 0)
///   * `native_pdf_min_android_api`  — minimum Android SDK int required (default 28,
///                                     the floor Jetpack PDF supports)
///   * `native_pdf_disabled_doc_ids` — comma-separated document ids to force onto
///                                     the current viewer (per-document kill switch)
class ReaderFlags {
  ReaderFlags._();
  static final ReaderFlags instance = ReaderFlags._();

  // Setting keys.
  static const _kNotesPercent = 'native_pdf_percent';
  static const _kSplitPercent = 'native_pdf_split_percent';
  static const _kMinBuild = 'native_pdf_min_build';
  static const _kMinAndroidApi = 'native_pdf_min_android_api';
  static const _kDisabledDocIds = 'native_pdf_disabled_doc_ids';

  /// Jetpack PDF's backported read/render floor. Android devices below this
  /// never get the native reader regardless of the server value.
  static const int _defaultMinAndroidApi = 28;

  // Cached device facts — these never change within a process, so resolve
  // them once. Null until [warmUp] or the first [shouldUseNative] call.
  int? _androidSdkInt;
  int? _buildNumber;
  String? _userBucket; // the user id used to derive the rollout bucket

  /// Pre-resolve device/app facts at startup so later checks are cheap.
  /// Safe to call fire-and-forget; failures are swallowed.
  Future<void> warmUp() async {
    try {
      await _ensureDeviceFacts();
      await AppSettingsService().getSettings();
    } catch (e) {
      debugPrint('[ReaderFlags] warmUp failed (non-fatal): $e');
    }
  }

  /// Returns true only when every gate passes for [surface]. Fail-closed:
  /// any error or missing data yields false. [documentId], when given, is
  /// checked against the per-document kill switch.
  Future<bool> shouldUseNative(
    ReaderSurface surface, {
    String? documentId,
  }) async {
    try {
      final settings = await AppSettingsService().getSettings();

      final percent = _readInt(
        settings[surface == ReaderSurface.notes ? _kNotesPercent : _kSplitPercent],
        fallback: 0,
      );
      if (percent <= 0) return false;

      // Per-document kill switch.
      if (documentId != null) {
        final disabled = _readIdSet(settings[_kDisabledDocIds]);
        if (disabled.contains(documentId)) return false;
      }

      await _ensureDeviceFacts();

      // Platform floor. iOS 16 (the app's deployment target) always clears
      // PDFKit's requirements, so only Android is gated by API level.
      if (Platform.isAndroid) {
        final minApi = _readInt(settings[_kMinAndroidApi],
            fallback: _defaultMinAndroidApi);
        final sdk = _androidSdkInt ?? 0;
        if (sdk < minApi) return false;
      }

      // Minimum build gate — lets the backend confine the native reader to
      // builds that actually contain the native shell.
      final minBuild = _readInt(settings[_kMinBuild], fallback: 0);
      if ((_buildNumber ?? 0) < minBuild) return false;

      // Stable per-user rollout bucket. A user with no id yet (not logged in)
      // is never bucketed in, so onboarding/guest flows stay on the current
      // viewer.
      final userId = _userBucket;
      if (userId == null || userId.isEmpty) return false;
      final bucket = _bucketOf(userId);
      return bucket < percent;
    } catch (e) {
      debugPrint('[ReaderFlags] shouldUseNative error (fail-closed): $e');
      return false;
    }
  }

  Future<void> _ensureDeviceFacts() async {
    if (_buildNumber == null) {
      final info = await PackageInfo.fromPlatform();
      _buildNumber = int.tryParse(info.buildNumber) ?? 0;
    }
    if (Platform.isAndroid && _androidSdkInt == null) {
      final android = await DeviceInfoPlugin().androidInfo;
      _androidSdkInt = android.version.sdkInt;
    }
    _userBucket ??= await StorageService().getUserId();
  }

  /// Deterministic 0..99 bucket for a user id, stable across sessions,
  /// devices and platforms. Uses FNV-1a (32-bit) rather than
  /// [String.hashCode] so the bucket a user lands in never shifts with a
  /// runtime or app-version change — essential for a gradual rollout where a
  /// user must not flip between readers.
  int _bucketOf(String userId) {
    const int fnvOffset = 0x811c9dc5;
    const int fnvPrime = 0x01000193;
    int hash = fnvOffset;
    for (final codeUnit in userId.codeUnits) {
      hash ^= codeUnit & 0xff;
      hash = (hash * fnvPrime) & 0xffffffff;
    }
    return hash % 100;
  }

  int _readInt(dynamic value, {required int fallback}) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value.trim()) ?? fallback;
    return fallback;
  }

  Set<String> _readIdSet(dynamic value) {
    if (value is List) {
      return value.map((e) => e.toString().trim()).where((e) => e.isNotEmpty).toSet();
    }
    if (value is String) {
      return value
          .split(',')
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toSet();
    }
    return const <String>{};
  }

  /// Test-only reset of cached device facts.
  @visibleForTesting
  void resetForTest() {
    _androidSdkInt = null;
    _buildNumber = null;
    _userBucket = null;
  }
}
