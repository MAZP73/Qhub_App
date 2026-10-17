import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../domain/qhub_connection.dart';

class SecureCredentialStore implements CredentialStore {
  SecureCredentialStore([FlutterSecureStorage? storage]) : _storage = storage ?? const FlutterSecureStorage();
  final FlutterSecureStorage _storage;

  String _k(String orgId, String f) => 'qhub.$orgId.$f';

  @override
  Future<QhubCredential?> read(String orgId) async {
    try {
      final id = await _storage.read(key: _k(orgId, 'id'));
      final pw = await _storage.read(key: _k(orgId, 'pw'));
      if (id == null || pw == null) return null;
      return QhubCredential(id, pw);
    } catch (_) {
      return null; // sin keyring disponible: se pide login de nuevo
    }
  }

  @override
  Future<void> write(String orgId, QhubCredential c) async {
    try {
      await _storage.write(key: _k(orgId, 'id'), value: c.identifier);
      await _storage.write(key: _k(orgId, 'pw'), value: c.password);
    } catch (_) {}
  }

  @override
  Future<void> delete(String orgId) async {
    try {
      await _storage.delete(key: _k(orgId, 'id'));
      await _storage.delete(key: _k(orgId, 'pw'));
    } catch (_) {}
  }
}
