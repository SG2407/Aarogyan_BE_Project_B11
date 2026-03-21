import 'package:flutter_secure_storage/flutter_secure_storage.dart';

const _storage = FlutterSecureStorage();

const _kToken = 'access_token';
const _kUserId = 'user_id';

class TokenStorage {
  static Future<void> saveToken(String token, String userId) async {
    await Future.wait([
      _storage.write(key: _kToken, value: token),
      _storage.write(key: _kUserId, value: userId),
    ]);
  }

  static Future<String?> getToken() => _storage.read(key: _kToken);
  static Future<String?> getUserId() => _storage.read(key: _kUserId);

  static Future<void> clear() async {
    await Future.wait([
      _storage.delete(key: _kToken),
      _storage.delete(key: _kUserId),
    ]);
  }
}
