import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/certificate_profile.dart';

/// Almacenamiento de certificados de firma y de sus contraseñas.
///
/// Los certificados (nombre, motivo, ruta del PFX y rúbrica opcional) se
/// guardan en `shared_preferences`; la contraseña del PFX se guarda en el
/// almacenamiento seguro del sistema (Credential Manager / DPAPI en Windows).
class SignatureStore {
  SignatureStore(this._prefs);

  static const String _kProfilesKey = 'certificate_profiles_v1';
  static const String _kLastCertificateIdKey = 'last_certificate_id';
  static const FlutterSecureStorage _secure = FlutterSecureStorage();

  final SharedPreferences _prefs;

  Future<List<CertificateProfile>> loadProfiles() async {
    final String? raw = _prefs.getString(_kProfilesKey);
    if (raw == null) return <CertificateProfile>[];
    final List<dynamic> list = jsonDecode(raw) as List<dynamic>;
    return list
        .map((dynamic item) =>
            CertificateProfile.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  Future<void> saveProfile(CertificateProfile profile) async {
    final List<CertificateProfile> profiles = await loadProfiles();
    final int index =
        profiles.indexWhere((CertificateProfile p) => p.id == profile.id);
    if (index >= 0) {
      profiles[index] = profile;
    } else {
      profiles.add(profile);
    }
    await _persist(profiles);
  }

  Future<void> deleteProfile(String id) async {
    final List<CertificateProfile> profiles = await loadProfiles()
      ..removeWhere((CertificateProfile p) => p.id == id);
    await _persist(profiles);
    await _secure.delete(key: _passwordKey(id));
    if (_prefs.getString(_kLastCertificateIdKey) == id) {
      await _prefs.remove(_kLastCertificateIdKey);
    }
  }

  Future<void> setLastCertificateId(String id) async {
    await _prefs.setString(_kLastCertificateIdKey, id);
  }

  Future<String?> get lastCertificateId async =>
      _prefs.getString(_kLastCertificateIdKey);

  Future<void> _persist(List<CertificateProfile> profiles) async {
    final List<Map<String, dynamic>> json = profiles
        .map((CertificateProfile p) => p.toJson())
        .toList();
    await _prefs.setString(_kProfilesKey, jsonEncode(json));
  }

  String _passwordKey(String profileId) => 'certificate_password_$profileId';

  Future<String?> readPassword(String profileId) =>
      _secure.read(key: _passwordKey(profileId));

  Future<void> savePassword(String profileId, String password) =>
      _secure.write(key: _passwordKey(profileId), value: password);

  Future<void> clearPassword(String profileId) =>
      _secure.delete(key: _passwordKey(profileId));
}