import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:pgme/core/constants/api_constants.dart';

class StorageService {
  static final StorageService _instance = StorageService._internal();
  factory StorageService() => _instance;
  StorageService._internal();

  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  // Token Management
  Future<void> saveAccessToken(String token) async {
    await _secureStorage.write(
      key: ApiConstants.accessTokenKey,
      value: token,
    );
  }

  Future<String?> getAccessToken() async {
    return await _secureStorage.read(key: ApiConstants.accessTokenKey);
  }

  Future<void> saveRefreshToken(String token) async {
    await _secureStorage.write(
      key: ApiConstants.refreshTokenKey,
      value: token,
    );
  }

  Future<String?> getRefreshToken() async {
    return await _secureStorage.read(key: ApiConstants.refreshTokenKey);
  }

  Future<void> saveSessionId(String sessionId) async {
    await _secureStorage.write(
      key: ApiConstants.sessionIdKey,
      value: sessionId,
    );
  }

  Future<String?> getSessionId() async {
    return await _secureStorage.read(key: ApiConstants.sessionIdKey);
  }

  Future<void> saveUserId(String userId) async {
    await _secureStorage.write(
      key: ApiConstants.userIdKey,
      value: userId,
    );
  }

  Future<String?> getUserId() async {
    return await _secureStorage.read(key: ApiConstants.userIdKey);
  }

  Future<void> saveOnboardingStatus(bool completed) async {
    await _secureStorage.write(
      key: ApiConstants.onboardingCompletedKey,
      value: completed.toString(),
    );
  }

  Future<bool> getOnboardingStatus() async {
    final value = await _secureStorage.read(
      key: ApiConstants.onboardingCompletedKey,
    );
    return value == 'true';
  }

  // Intro screens seen status (informational onboarding carousel)
  Future<void> saveIntroSeen(bool seen) async {
    await _secureStorage.write(
      key: ApiConstants.introSeenKey,
      value: seen.toString(),
    );
  }

  Future<bool> getIntroSeen() async {
    final value = await _secureStorage.read(
      key: ApiConstants.introSeenKey,
    );
    return value == 'true';
  }

  // Save all tokens at once
  Future<void> saveAuthTokens({
    required String accessToken,
    required String refreshToken,
    required String sessionId,
    required String userId,
    required bool onboardingCompleted,
  }) async {
    await Future.wait([
      saveAccessToken(accessToken),
      saveRefreshToken(refreshToken),
      saveSessionId(sessionId),
      saveUserId(userId),
      saveOnboardingStatus(onboardingCompleted),
    ]);
  }

  // Check if user is authenticated
  Future<bool> isAuthenticated() async {
    final token = await getAccessToken();
    return token != null && token.isNotEmpty;
  }

  // Clear all stored data (logout)
  Future<void> clearAll() async {
    await _secureStorage.deleteAll();
  }

  // Clear specific keys
  Future<void> clearTokens() async {
    await Future.wait([
      _secureStorage.delete(key: ApiConstants.accessTokenKey),
      _secureStorage.delete(key: ApiConstants.refreshTokenKey),
      _secureStorage.delete(key: ApiConstants.sessionIdKey),
    ]);
  }
}
