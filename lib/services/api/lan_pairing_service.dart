import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

import '../../data/database/database.dart';
import '../secure_storage_service.dart';
import '../security_service.dart';

/// Server-side LAN pairing state. The install secret never leaves this process.
class LanPairingService {
  static const installSecretStorageKey = 'ural_lan_install_secret_v1';
  static const transitionStartedKey = 'lan_legacy_transition_started_at';
  static const transitionDaysKey = 'lan_legacy_transition_days';
  static const transitionEndedKey = 'lan_legacy_transition_ended';
  static const defaultTransitionDays = 30;
  static const pairingTtl = Duration(minutes: 10);
  static const attemptWindow = Duration(minutes: 10);
  static const maxAttemptsPerIp = 5;

  final AppDatabase? _db;
  final SecureStorageService _storage;
  final DateTime Function() _now;
  final String Function() _makeCode;
  final Map<String, _PairingDevice> _memoryDevices = {};
  final Map<String, List<DateTime>> _attempts = {};
  _PairingOffer? _pendingOffer;
  String? _installSecret;
  bool _initialized = false;

  LanPairingService(
    this._db, {
    SecureStorageService? storage,
    DateTime Function()? now,
    String Function()? makeCode,
  })  : _storage = storage ?? SecureStorageService(),
        _now = now ?? DateTime.now,
        _makeCode = makeCode ?? _randomCode;

  LanPairingService.forTesting({
    required String installSecret,
    AppDatabase? db,
    DateTime Function()? now,
    String Function()? makeCode,
  })  : _db = db,
        _storage = SecureStorageService(),
        _now = now ?? DateTime.now,
        _makeCode = makeCode ?? _randomCode,
        _installSecret = installSecret,
        _initialized = true;

  static String _randomCode() {
    const alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final random = Random.secure();
    return List.generate(8, (_) => alphabet[random.nextInt(alphabet.length)])
        .join();
  }

  Future<void> initialize() async {
    if (_initialized) return;
    try {
      final stored = await _storage.read(installSecretStorageKey);
      if (stored != null && stored.length >= 43) {
        _installSecret = stored;
      } else {
        final bytes = List<int>.generate(32, (_) => Random.secure().nextInt(256));
        final generated = base64UrlEncode(bytes);
        await _storage.write(installSecretStorageKey, generated);
        _installSecret = generated;
      }
      _initialized = true;
    } catch (error) {
      debugPrint('[LanPairing] secure install-secret initialization failed: $error');
      if (error is DatabaseKeyUnavailableException) rethrow;
      throw const DatabaseKeyUnavailableException();
    }
  }

  bool get isInitialized => _initialized && _installSecret != null;

  PairingOffer issuePairingCode({
    required String serverHost,
    required int port,
    String? serverFingerprint,
  }) {
    _requireInitialized();
    final code = _makeCode().toUpperCase();
    final expiresAt = _now().add(pairingTtl);
    final payload = jsonEncode({
      'serverHost': serverHost,
      'port': port,
      'pairingCode': code,
      'serverFingerprint': serverFingerprint,
    });
    final offer = _PairingOffer(
      code: code,
      expiresAt: expiresAt,
      payload: payload,
    );
    _pendingOffer = offer;
    return PairingOffer(code: code, expiresAt: expiresAt, qrPayload: payload);
  }

  Future<LanPairingResult> pair({
    required String code,
    required String deviceId,
    required String deviceName,
    required String ip,
  }) async {
    if (!_allowAttempt(ip)) {
      return const LanPairingResult.rateLimited();
    }
    final offer = _pendingOffer;
    if (offer == null || _now().isAfter(offer.expiresAt) ||
        !_constantTimeEquals(offer.code, code.trim().toUpperCase())) {
      return const LanPairingResult.invalidCode();
    }
    if (deviceId.trim().isEmpty) {
      return const LanPairingResult.invalidDevice();
    }

    final normalizedId = deviceId.trim();
    final normalizedName = deviceName.trim().isEmpty ? 'جهاز LAN' : deviceName.trim();
    final token = tokenForDevice(normalizedId);
    _pendingOffer = null; // successful pairing is one-time
    await _upsertDevice(
      deviceId: normalizedId,
      name: normalizedName,
      pairedAt: _now().millisecondsSinceEpoch,
      lastSeenAt: _now().millisecondsSinceEpoch,
      ip: ip,
      revoked: false,
      legacySeen: false,
    );
    return LanPairingResult.success(token: token, deviceId: normalizedId);
  }

  bool _allowAttempt(String ip) {
    final now = _now();
    final recent = (_attempts[ip] ?? <DateTime>[])
      ..removeWhere((time) => now.difference(time) >= attemptWindow);
    _attempts[ip] = recent;
    if (recent.length >= maxAttemptsPerIp) return false;
    recent.add(now);
    return true;
  }

  String tokenForDevice(String deviceId) {
    _requireInitialized();
    final mac = Hmac(sha256, utf8.encode(_installSecret!))
        .convert(utf8.encode(deviceId));
    return base64UrlEncode(mac.bytes);
  }

  Future<bool> verifyDeviceToken({
    required String token,
    required String deviceId,
  }) async {
    if (!_initialized || deviceId.trim().isEmpty) return false;
    final expected = tokenForDevice(deviceId.trim());
    if (!_constantTimeEquals(expected, token)) return false;
    final row = await _findDevice(deviceId.trim());
    return row != null && row.revoked == false && row.pairedAt != null;
  }

  Future<void> recordSeen({
    required String deviceId,
    required String name,
    required String ip,
  }) async {
    final existing = await _findDevice(deviceId);
    if (existing == null) return;
    await _upsertDevice(
      deviceId: deviceId,
      name: existing.name.isEmpty ? name : existing.name,
      pairedAt: existing.pairedAt?.millisecondsSinceEpoch,
      lastSeenAt: _now().millisecondsSinceEpoch,
      ip: ip,
      revoked: existing.revoked,
      legacySeen: existing.legacySeen,
    );
  }

  Future<void> recordLegacyDevice({
    required String deviceId,
    required String name,
    required String ip,
  }) async {
    final id = deviceId.trim().isEmpty ? 'legacy@$ip' : deviceId.trim();
    final existing = await _findDevice(id);
    await _upsertDevice(
      deviceId: id,
      name: name.trim().isEmpty ? 'جهاز غير مقترن' : name.trim(),
      pairedAt: existing?.pairedAt?.millisecondsSinceEpoch,
      lastSeenAt: _now().millisecondsSinceEpoch,
      ip: ip,
      revoked: existing?.revoked ?? false,
      legacySeen: true,
    );
  }

  Future<List<LanPairingDevice>> listDevices() async {
    if (_db == null) {
      return _memoryDevices.values.map((device) => device.toPublic()).toList();
    }
    final rows = await _db.customSelect(
      'SELECT device_id, name, paired_at, last_seen_at, last_seen_ip, revoked, legacy_seen '
      'FROM lan_paired_devices ORDER BY last_seen_at DESC NULLS LAST',
    ).get();
    return rows.map((row) {
      final data = row.data;
      return LanPairingDevice(
        deviceId: data['device_id'] as String,
        name: data['name'] as String? ?? '',
        pairedAt: _asDate(data['paired_at']),
        lastSeenAt: _asDate(data['last_seen_at']),
        ip: data['last_seen_ip'] as String?,
        revoked: _asBool(data['revoked']),
        legacySeen: _asBool(data['legacy_seen']),
      );
    }).toList();
  }

  Future<List<LanPairingDevice>> listUnpairedDevices() async {
    final devices = await listDevices();
    return devices.where((device) => device.pairedAt == null).toList();
  }

  Future<void> revoke(String deviceId) async {
    if (_db == null) {
      final existing = _memoryDevices[deviceId];
      if (existing != null) existing.revoked = true;
      return;
    }
    await _db.customStatement(
      "UPDATE lan_paired_devices SET revoked = 1 WHERE device_id = '${_sql(deviceId)}'",
    );
  }

  Future<void> initializeLegacyTransition() async {
    if (_db == null) return;
    final started = await _db.getSettingValue(transitionStartedKey);
    if (started == null || int.tryParse(started) == null) {
      await _db.setSetting(transitionStartedKey, '${_now().millisecondsSinceEpoch}');
    }
    if (await _db.getSettingValue(transitionDaysKey) == null) {
      await _db.setSetting(transitionDaysKey, '$defaultTransitionDays');
    }
  }

  Future<bool> legacyAllowed() async {
    if (_db == null) return true;
    if ((await _db.getSettingValue(transitionEndedKey)) == 'true') return false;
    final started = int.tryParse(
      (await _db.getSettingValue(transitionStartedKey)) ?? '',
    );
    final days = int.tryParse(
          (await _db.getSettingValue(transitionDaysKey)) ?? '',
        ) ??
        defaultTransitionDays;
    if (started == null) return false;
    return _now().millisecondsSinceEpoch - started <
        Duration(days: days.clamp(1, 3650)).inMilliseconds;
  }

  Future<int> legacyTransitionDays() async {
    if (_db == null) return defaultTransitionDays;
    return int.tryParse((await _db.getSettingValue(transitionDaysKey)) ?? '') ??
        defaultTransitionDays;
  }

  Future<void> setLegacyTransitionDays(int days) async {
    if (_db == null) return;
    await _db.setSetting(transitionDaysKey, days.clamp(1, 3650).toString());
  }

  Future<void> endLegacyTransition() async {
    if (_db == null) return;
    await _db.setSetting(transitionEndedKey, 'true');
  }

  Future<_PairingDevice?> _findDevice(String deviceId) async {
    if (_db == null) return _memoryDevices[deviceId];
    final rows = await _db.customSelect(
      'SELECT device_id, name, paired_at, last_seen_at, last_seen_ip, revoked, legacy_seen '
      "FROM lan_paired_devices WHERE device_id = '${_sql(deviceId)}' LIMIT 1",
    ).get();
    if (rows.isEmpty) return null;
    final data = rows.single.data;
    return _PairingDevice(
      deviceId: data['device_id'] as String,
      name: data['name'] as String? ?? '',
      pairedAt: _asDate(data['paired_at']),
      lastSeenAt: _asDate(data['last_seen_at']),
      ip: data['last_seen_ip'] as String?,
      revoked: _asBool(data['revoked']),
      legacySeen: _asBool(data['legacy_seen']),
    );
  }

  Future<void> _upsertDevice({
    required String deviceId,
    required String name,
    required int? pairedAt,
    required int lastSeenAt,
    required String ip,
    required bool revoked,
    required bool legacySeen,
  }) async {
    final row = _PairingDevice(
      deviceId: deviceId,
      name: name,
      pairedAt: pairedAt == null ? null : DateTime.fromMillisecondsSinceEpoch(pairedAt),
      lastSeenAt: DateTime.fromMillisecondsSinceEpoch(lastSeenAt),
      ip: ip,
      revoked: revoked,
      legacySeen: legacySeen,
    );
    if (_db == null) {
      _memoryDevices[deviceId] = row;
      return;
    }
    final values = "name = '${_sql(name)}', paired_at = ${pairedAt ?? 'NULL'}, "
        'last_seen_at = $lastSeenAt, last_seen_ip = \'${_sql(ip)}\', '
        'revoked = ${revoked ? 1 : 0}, legacy_seen = ${legacySeen ? 1 : 0}';
    await _db.customStatement(
      "UPDATE lan_paired_devices SET $values WHERE device_id = '${_sql(deviceId)}'",
    );
    final found = await _findDevice(deviceId);
    if (found == null) {
      await _db.customStatement(
        "INSERT INTO lan_paired_devices "
        '(device_id, name, paired_at, last_seen_at, last_seen_ip, revoked, legacy_seen) '
        "VALUES ('${_sql(deviceId)}', '${_sql(name)}', ${pairedAt ?? 'NULL'}, "
        "$lastSeenAt, '${_sql(ip)}', ${revoked ? 1 : 0}, ${legacySeen ? 1 : 0})",
      );
    }
  }

  void _requireInitialized() {
    if (!isInitialized) {
      throw StateError('LanPairingService.initialize must run on the server first');
    }
  }

  static String _sql(String value) => value.replaceAll("'", "''");

  static DateTime? _asDate(Object? value) {
    final millis = value is int ? value : int.tryParse('$value');
    return millis == null ? null : DateTime.fromMillisecondsSinceEpoch(millis);
  }

  static bool _asBool(Object? value) => value == true || value == 1 || value == '1';

  static bool _constantTimeEquals(String a, String b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
    }
    return diff == 0;
  }
}

class PairingOffer {
  const PairingOffer({required this.code, required this.expiresAt, required this.qrPayload});
  final String code;
  final DateTime expiresAt;
  final String qrPayload;
}

class LanPairingResult {
  const LanPairingResult._({
    required this.status,
    this.token,
    this.deviceId,
  });

  const LanPairingResult.success({required String token, required String deviceId})
      : this._(status: LanPairingStatus.success, token: token, deviceId: deviceId);
  const LanPairingResult.invalidCode() : this._(status: LanPairingStatus.invalidCode);
  const LanPairingResult.rateLimited() : this._(status: LanPairingStatus.rateLimited);
  const LanPairingResult.invalidDevice() : this._(status: LanPairingStatus.invalidDevice);

  final LanPairingStatus status;
  final String? token;
  final String? deviceId;
}

enum LanPairingStatus { success, invalidCode, rateLimited, invalidDevice }

class LanPairingDevice {
  const LanPairingDevice({
    required this.deviceId,
    required this.name,
    required this.pairedAt,
    required this.lastSeenAt,
    required this.ip,
    required this.revoked,
    required this.legacySeen,
  });

  final String deviceId;
  final String name;
  final DateTime? pairedAt;
  final DateTime? lastSeenAt;
  final String? ip;
  final bool revoked;
  final bool legacySeen;

  bool get isPaired => pairedAt != null;
}

class _PairingOffer {
  const _PairingOffer({required this.code, required this.expiresAt, required this.payload});
  final String code;
  final DateTime expiresAt;
  final String payload;
}

class _PairingDevice {
  _PairingDevice({
    required this.deviceId,
    required this.name,
    required this.pairedAt,
    required this.lastSeenAt,
    required this.ip,
    required this.revoked,
    required this.legacySeen,
  });

  final String deviceId;
  final String name;
  final DateTime? pairedAt;
  final DateTime? lastSeenAt;
  final String? ip;
  bool revoked;
  final bool legacySeen;

  LanPairingDevice toPublic() => LanPairingDevice(
        deviceId: deviceId,
        name: name,
        pairedAt: pairedAt,
        lastSeenAt: lastSeenAt,
        ip: ip,
        revoked: revoked,
        legacySeen: legacySeen,
      );
}
