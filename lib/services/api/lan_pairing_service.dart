import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart' show Variable;
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
  final Map<int, Future<void>> _branchAllocationQueues = {};
  final Set<_PairingOffer> _claimedOffers = {};
  _PairingOffer? _pendingOffer;
  String? _installSecret;
  bool _initialized = false;

  LanPairingService(
    this._db, {
    SecureStorageService? storage,
    DateTime Function()? now,
    String Function()? makeCode,
  }) : _storage = storage ?? SecureStorageService(),
       _now = now ?? DateTime.now,
       _makeCode = makeCode ?? _randomCode;

  LanPairingService.forTesting({
    required String installSecret,
    AppDatabase? db,
    DateTime Function()? now,
    String Function()? makeCode,
  }) : _db = db,
       _storage = SecureStorageService(),
       _now = now ?? DateTime.now,
       _makeCode = makeCode ?? _randomCode,
       _installSecret = installSecret,
       _initialized = true;

  static String _randomCode() {
    const alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final random = Random.secure();
    return List.generate(
      8,
      (_) => alphabet[random.nextInt(alphabet.length)],
    ).join();
  }

  Future<void> initialize() async {
    if (_initialized) return;
    try {
      final stored = await _storage.read(installSecretStorageKey);
      if (stored != null && stored.length >= 43) {
        _installSecret = stored;
      } else {
        final bytes = List<int>.generate(
          32,
          (_) => Random.secure().nextInt(256),
        );
        final generated = base64UrlEncode(bytes);
        await _storage.write(installSecretStorageKey, generated);
        _installSecret = generated;
      }
      _initialized = true;
    } catch (error) {
      debugPrint(
        '[LanPairing] secure install-secret initialization failed: $error',
      );
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

  Future<LanPairingResult> pair(LanPairingRequest request) async {
    if (!_allowAttempt(request.ip)) return const LanPairingResult.rateLimited();
    final offer = _matchingOffer(request.code);
    if (offer == null) return const LanPairingResult.invalidCode();
    if (request.deviceId.trim().isEmpty) {
      return const LanPairingResult.invalidDevice();
    }
    if (!_claimedOffers.add(offer)) {
      return const LanPairingResult.invalidCode();
    }
    try {
      final result = await _completePairing(request);
      if (result.status == LanPairingStatus.success &&
          identical(_pendingOffer, offer)) {
        _pendingOffer = null;
      }
      return result;
    } finally {
      _claimedOffers.remove(offer);
    }
  }

  _PairingOffer? _matchingOffer(String code) {
    final offer = _pendingOffer;
    if (offer == null || _now().isAfter(offer.expiresAt)) return null;
    if (!_constantTimeEquals(offer.code, code.trim().toUpperCase()))
      return null;
    return offer;
  }

  Future<LanPairingResult> _completePairing(LanPairingRequest request) async {
    final work = _PairingWork(
      request: request,
      deviceId: request.deviceId.trim(),
      pairedAt: _now().millisecondsSinceEpoch,
      token: tokenForDevice(request.deviceId.trim()),
    );
    return request.deviceKind == 'pos'
        ? _pairPosDevice(work)
        : _pairGenericDevice(work);
  }

  Future<LanPairingResult> _pairGenericDevice(_PairingWork work) async {
    final existing = work.request.deviceKind == null
        ? await _findDevice(work.deviceId)
        : null;
    await _upsertDevice(_genericPairedDevice(work, existing));
    return LanPairingResult.success(token: work.token, deviceId: work.deviceId);
  }

  _PairingDevice _genericPairedDevice(
    _PairingWork work,
    _PairingDevice? existing,
  ) {
    final request = work.request;
    return _PairingDevice(
      deviceId: work.deviceId,
      name: work.deviceName,
      pairedAt: DateTime.fromMillisecondsSinceEpoch(work.pairedAt),
      lastSeenAt: DateTime.fromMillisecondsSinceEpoch(work.pairedAt),
      ip: request.ip,
      revoked: false,
      legacySeen: false,
      deviceKind: request.deviceKind ?? existing?.deviceKind,
      branchId: request.deviceKind == null
          ? existing?.branchId
          : request.branchId,
      terminalCode: request.deviceKind == null ? existing?.terminalCode : null,
    );
  }

  Future<LanPairingResult> _pairPosDevice(_PairingWork work) async {
    final branchId = work.request.branchId;
    if (branchId == null || branchId <= 0) {
      return const LanPairingResult.branchRequired();
    }
    final branch = await _posBranch(branchId);
    if (branch.failure != null) return _posBranchFailure(branch.failure!);
    return _withBranchAllocationLock(
      branchId,
      () => _persistAndBuildPosResult(work, branchId, branch.code!),
    );
  }

  Future<T> _withBranchAllocationLock<T>(
    int branchId,
    Future<T> Function() operation,
  ) async {
    final previous = _branchAllocationQueues[branchId] ?? Future<void>.value();
    final release = Completer<void>();
    final queued = release.future;
    _branchAllocationQueues[branchId] = queued;
    await previous;
    try {
      return await operation();
    } finally {
      release.complete();
      if (identical(_branchAllocationQueues[branchId], queued)) {
        _branchAllocationQueues.remove(branchId);
      }
    }
  }

  Future<LanPairingResult> _persistAndBuildPosResult(
    _PairingWork work,
    int branchId,
    String branchCode,
  ) async {
    final terminalCode = await _persistPosDevice(work, branchId);
    return LanPairingResult.posSuccess(
      token: work.token,
      deviceId: work.deviceId,
      branchId: branchId,
      branchCode: branchCode,
      terminalCode: terminalCode,
    );
  }

  LanPairingResult _posBranchFailure(LanPairingStatus status) =>
      switch (status) {
        LanPairingStatus.branchUnavailable =>
          const LanPairingResult.branchUnavailable(),
        LanPairingStatus.branchCodeUnavailable =>
          const LanPairingResult.branchCodeUnavailable(),
        _ => throw StateError('Unexpected POS branch validation status'),
      };

  Future<({String? code, LanPairingStatus? failure})> _posBranch(
    int branchId,
  ) async {
    final db = _db;
    if (db == null) return _branchFailure(LanPairingStatus.branchUnavailable);
    final branches = await db
        .customSelect(
          'SELECT code FROM branches WHERE id = ? '
          'AND is_active = ${db.sqlBool(true)} AND deleted_at IS NULL LIMIT 1',
          variables: [Variable<int>(branchId)],
        )
        .get();
    if (branches.isEmpty) {
      return _branchFailure(LanPairingStatus.branchUnavailable);
    }
    final code = (branches.single.data['code'] as String?)?.trim();
    if (code == null || code.isEmpty) {
      return _branchFailure(LanPairingStatus.branchCodeUnavailable);
    }
    return (code: code, failure: null);
  }

  ({String? code, LanPairingStatus? failure}) _branchFailure(
    LanPairingStatus status,
  ) => (code: null, failure: status);

  Future<String> _persistPosDevice(_PairingWork work, int branchId) async {
    final db = _db!;
    return db.transaction(
      () => _persistPosDeviceTransaction(db, work, branchId),
    );
  }

  Future<String> _persistPosDeviceTransaction(
    AppDatabase db,
    _PairingWork work,
    int branchId,
  ) async {
    final terminalCode = await _terminalCodeForDevice(
      db,
      branchId,
      work.deviceId,
      work.pairedAt,
    );
    await _upsertPosDevice(db, _posDeviceRecord(work, branchId, terminalCode));
    return terminalCode;
  }

  _PosDeviceRecord _posDeviceRecord(
    _PairingWork work,
    int branchId,
    String terminalCode,
  ) => _PosDeviceRecord(
    deviceId: work.deviceId,
    deviceName: work.deviceName,
    ip: work.request.ip,
    branchId: branchId,
    pairedAt: work.pairedAt,
    terminalCode: terminalCode,
  );

  Future<String> _terminalCodeForDevice(
    AppDatabase db,
    int branchId,
    String deviceId,
    int assignedAt,
  ) async {
    final rows = await db
        .customSelect(
          'SELECT terminal_code FROM lan_branch_terminal_codes '
          'WHERE branch_id = ? AND device_id = ? LIMIT 1',
          variables: [Variable<int>(branchId), Variable<String>(deviceId)],
        )
        .get();
    if (rows.isNotEmpty) return rows.single.data['terminal_code'] as String;
    return _allocateTerminalCode(db, branchId, deviceId, assignedAt);
  }

  Future<void> _upsertPosDevice(AppDatabase db, _PosDeviceRecord record) async {
    await db.customStatement(
      'INSERT INTO lan_paired_devices '
      '(device_id, name, paired_at, last_seen_at, last_seen_ip, revoked, '
      'legacy_seen, device_kind, branch_id, terminal_code) '
      "VALUES (?, ?, ?, ?, ?, 0, 0, 'pos', ?, ?) "
      'ON CONFLICT(device_id) DO UPDATE SET '
      'name = excluded.name, paired_at = excluded.paired_at, '
      'last_seen_at = excluded.last_seen_at, last_seen_ip = excluded.last_seen_ip, '
      'revoked = 0, legacy_seen = 0, device_kind = excluded.device_kind, '
      'branch_id = excluded.branch_id, terminal_code = excluded.terminal_code',
      [
        record.deviceId,
        record.deviceName,
        record.pairedAt,
        record.pairedAt,
        record.ip,
        record.branchId,
        record.terminalCode,
      ],
    );
  }

  Future<String> _allocateTerminalCode(
    AppDatabase db,
    int branchId,
    String deviceId,
    int assignedAt,
  ) async {
    final previous = await _highestTerminalNumber(db, branchId);
    final terminalCode = 'T${(previous + 1).toString().padLeft(2, '0')}';
    await _recordTerminalCode(
      db,
      _TerminalAllocation(
        branchId: branchId,
        deviceId: deviceId,
        assignedAt: assignedAt,
        terminalCode: terminalCode,
      ),
    );
    return terminalCode;
  }

  Future<int> _highestTerminalNumber(AppDatabase db, int branchId) async {
    final rows = await db
        .customSelect(
          'SELECT terminal_code FROM lan_branch_terminal_codes '
          'WHERE branch_id = ? '
          'ORDER BY CAST(SUBSTR(terminal_code, 2) AS INTEGER) DESC LIMIT 1',
          variables: [Variable<int>(branchId)],
        )
        .get();
    return rows.isEmpty
        ? 0
        : int.parse((rows.single.data['terminal_code'] as String).substring(1));
  }

  Future<void> _recordTerminalCode(
    AppDatabase db,
    _TerminalAllocation allocation,
  ) async {
    await db.customStatement(
      'INSERT INTO lan_branch_terminal_codes '
      '(branch_id, terminal_code, device_id, assigned_at) VALUES (?, ?, ?, ?)',
      [
        allocation.branchId,
        allocation.terminalCode,
        allocation.deviceId,
        allocation.assignedAt,
      ],
    );
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
    final mac = Hmac(
      sha256,
      utf8.encode(_installSecret!),
    ).convert(utf8.encode(deviceId));
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
      _PairingDevice(
        deviceId: deviceId,
        name: existing.name.isEmpty ? name : existing.name,
        pairedAt: existing.pairedAt,
        lastSeenAt: _now(),
        ip: ip,
        revoked: existing.revoked,
        legacySeen: existing.legacySeen,
        deviceKind: existing.deviceKind,
        branchId: existing.branchId,
        terminalCode: existing.terminalCode,
      ),
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
      _PairingDevice(
        deviceId: id,
        name: name.trim().isEmpty ? 'جهاز غير مقترن' : name.trim(),
        pairedAt: existing?.pairedAt,
        lastSeenAt: _now(),
        ip: ip,
        revoked: existing?.revoked ?? false,
        legacySeen: true,
        deviceKind: existing?.deviceKind,
        branchId: existing?.branchId,
        terminalCode: existing?.terminalCode,
      ),
    );
  }

  Future<List<LanPairingDevice>> listDevices() async {
    if (_db == null) {
      return _memoryDevices.values.map((device) => device.toPublic()).toList();
    }
    final rows = await _db
        .customSelect(
          'SELECT device_id, name, paired_at, last_seen_at, last_seen_ip, revoked, '
          'legacy_seen, device_kind, branch_id, terminal_code '
          'FROM lan_paired_devices ORDER BY last_seen_at DESC NULLS LAST',
        )
        .get();
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
        deviceKind: data['device_kind'] as String?,
        branchId: _asInt(data['branch_id']),
        terminalCode: data['terminal_code'] as String?,
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
      'UPDATE lan_paired_devices SET revoked = 1 WHERE device_id = ?',
      [deviceId],
    );
  }

  Future<void> initializeLegacyTransition() async {
    if (_db == null) return;
    final started = await _db.getSettingValue(transitionStartedKey);
    if (started == null || int.tryParse(started) == null) {
      await _db.setSetting(
        transitionStartedKey,
        '${_now().millisecondsSinceEpoch}',
      );
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
    final days =
        int.tryParse((await _db.getSettingValue(transitionDaysKey)) ?? '') ??
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
    final rows = await _db
        .customSelect(
          'SELECT device_id, name, paired_at, last_seen_at, last_seen_ip, revoked, '
          'legacy_seen, device_kind, branch_id, terminal_code '
          'FROM lan_paired_devices WHERE device_id = ? LIMIT 1',
          variables: [Variable.withString(deviceId)],
        )
        .get();
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
      deviceKind: data['device_kind'] as String?,
      branchId: _asInt(data['branch_id']),
      terminalCode: data['terminal_code'] as String?,
    );
  }

  Future<void> _upsertDevice(_PairingDevice row) async {
    final db = _db;
    if (db == null) {
      _memoryDevices[row.deviceId] = row;
      return;
    }
    final pairedAt = row.pairedAt?.millisecondsSinceEpoch;
    final lastSeenAt = row.lastSeenAt?.millisecondsSinceEpoch;
    await db.customStatement(
      'INSERT INTO lan_paired_devices '
      '(device_id, name, paired_at, last_seen_at, last_seen_ip, revoked, '
      'legacy_seen, device_kind, branch_id, terminal_code) '
      'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?) '
      'ON CONFLICT(device_id) DO UPDATE SET name = excluded.name, '
      'paired_at = excluded.paired_at, last_seen_at = excluded.last_seen_at, '
      'last_seen_ip = excluded.last_seen_ip, revoked = excluded.revoked, '
      'legacy_seen = excluded.legacy_seen, device_kind = excluded.device_kind, '
      'branch_id = excluded.branch_id, terminal_code = excluded.terminal_code',
      [
        row.deviceId,
        row.name,
        pairedAt,
        lastSeenAt,
        row.ip,
        row.revoked ? 1 : 0,
        row.legacySeen ? 1 : 0,
        row.deviceKind,
        row.branchId,
        row.terminalCode,
      ],
    );
  }

  void _requireInitialized() {
    if (!isInitialized) {
      throw StateError(
        'LanPairingService.initialize must run on the server first',
      );
    }
  }

  static DateTime? _asDate(Object? value) {
    final millis = value is int ? value : int.tryParse('$value');
    return millis == null ? null : DateTime.fromMillisecondsSinceEpoch(millis);
  }

  static bool _asBool(Object? value) =>
      value == true || value == 1 || value == '1';

  static int? _asInt(Object? value) =>
      value is int ? value : int.tryParse('$value');

  static bool _constantTimeEquals(String a, String b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
    }
    return diff == 0;
  }
}

class _PairingWork {
  const _PairingWork({
    required this.request,
    required this.deviceId,
    required this.pairedAt,
    required this.token,
  });

  final LanPairingRequest request;
  final String deviceId;
  final int pairedAt;
  final String token;

  String get deviceName => request.deviceName.trim().isEmpty
      ? 'جهاز LAN'
      : request.deviceName.trim();
}

class PairingOffer {
  const PairingOffer({
    required this.code,
    required this.expiresAt,
    required this.qrPayload,
  });
  final String code;
  final DateTime expiresAt;
  final String qrPayload;
}

class LanPairingRequest {
  const LanPairingRequest({
    required this.code,
    required this.deviceId,
    required this.deviceName,
    required this.ip,
    this.deviceKind,
    this.branchId,
  });

  final String code;
  final String deviceId;
  final String deviceName;
  final String ip;
  final String? deviceKind;
  final int? branchId;
}

class _TerminalAllocation {
  const _TerminalAllocation({
    required this.branchId,
    required this.deviceId,
    required this.assignedAt,
    required this.terminalCode,
  });

  final int branchId;
  final String deviceId;
  final int assignedAt;
  final String terminalCode;
}

class _PosDeviceRecord {
  const _PosDeviceRecord({
    required this.deviceId,
    required this.deviceName,
    required this.ip,
    required this.branchId,
    required this.pairedAt,
    required this.terminalCode,
  });

  final String deviceId;
  final String deviceName;
  final String ip;
  final int branchId;
  final int pairedAt;
  final String terminalCode;
}

class LanPairingResult {
  const LanPairingResult._({
    required this.status,
    this.token,
    this.deviceId,
    this.branchId,
    this.branchCode,
    this.terminalCode,
  });

  const LanPairingResult.success({
    required String token,
    required String deviceId,
  }) : this._(
         status: LanPairingStatus.success,
         token: token,
         deviceId: deviceId,
       );
  const LanPairingResult.posSuccess({
    required String token,
    required String deviceId,
    required int branchId,
    required String branchCode,
    required String terminalCode,
  }) : this._(
         status: LanPairingStatus.success,
         token: token,
         deviceId: deviceId,
         branchId: branchId,
         branchCode: branchCode,
         terminalCode: terminalCode,
       );
  const LanPairingResult.invalidCode()
    : this._(status: LanPairingStatus.invalidCode);
  const LanPairingResult.rateLimited()
    : this._(status: LanPairingStatus.rateLimited);
  const LanPairingResult.invalidDevice()
    : this._(status: LanPairingStatus.invalidDevice);
  const LanPairingResult.branchRequired()
    : this._(status: LanPairingStatus.branchRequired);
  const LanPairingResult.branchUnavailable()
    : this._(status: LanPairingStatus.branchUnavailable);
  const LanPairingResult.branchCodeUnavailable()
    : this._(status: LanPairingStatus.branchCodeUnavailable);

  final LanPairingStatus status;
  final String? token;
  final String? deviceId;
  final int? branchId;
  final String? branchCode;
  final String? terminalCode;
}

enum LanPairingStatus {
  success,
  invalidCode,
  rateLimited,
  invalidDevice,
  branchRequired,
  branchUnavailable,
  branchCodeUnavailable,
}

class LanPairingDevice {
  const LanPairingDevice({
    required this.deviceId,
    required this.name,
    required this.pairedAt,
    required this.lastSeenAt,
    required this.ip,
    required this.revoked,
    required this.legacySeen,
    this.deviceKind,
    this.branchId,
    this.terminalCode,
  });

  final String deviceId;
  final String name;
  final DateTime? pairedAt;
  final DateTime? lastSeenAt;
  final String? ip;
  final bool revoked;
  final bool legacySeen;
  final String? deviceKind;
  final int? branchId;
  final String? terminalCode;

  bool get isPaired => pairedAt != null;
}

class _PairingOffer {
  const _PairingOffer({
    required this.code,
    required this.expiresAt,
    required this.payload,
  });
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
    this.deviceKind,
    this.branchId,
    this.terminalCode,
  });

  final String deviceId;
  final String name;
  final DateTime? pairedAt;
  final DateTime? lastSeenAt;
  final String? ip;
  bool revoked;
  final bool legacySeen;
  final String? deviceKind;
  final int? branchId;
  final String? terminalCode;

  LanPairingDevice toPublic() => LanPairingDevice(
    deviceId: deviceId,
    name: name,
    pairedAt: pairedAt,
    lastSeenAt: lastSeenAt,
    ip: ip,
    revoked: revoked,
    legacySeen: legacySeen,
    deviceKind: deviceKind,
    branchId: branchId,
    terminalCode: terminalCode,
  );
}
