// سياسةُ الدخول دون اتصال لأجهزة الفروع (P7 · B11 · E10).
//
// مدةُ السماح (`offline_login_grace_days`، مزامَنةٌ من الرئيسي، الافتراضيّ 7) تُحتسب
// من **آخر تحقّقٍ ناجحٍ بجلسة خادمٍ** لكلّ مستخدمٍ على هذا الجهاز. الطابعُ محفوظٌ في
// التخزين الآمن لا في قاعدة البيانات (‏لا يُنقل ولا يُزامَن)، ومعه أعلى وقتٍ شوهد
// فإرجاعُ ساعة الجهاز للخلف لتمديد المدة يُرفض (‏تسامحٌ 10 دقائق).
//
// ⚠️ [OfflineLoginDecision.neverVerified] قرارٌ **منفصل**: النداءُ هو الذي يقرّر
// (‏المثبَّت قبل هذا الإصدار لا طابعَ له؛ رفضُه يقفل كلَّ كاشير حتى يتصل مرّة).
library;

import 'dart:convert';

import '../secure_storage_service.dart';

enum OfflineLoginDecision { allowed, neverVerified, expired, clockRolledBack }

class OfflineLoginVerdict {
  const OfflineLoginVerdict(this.decision, {required this.graceDays, this.lastVerified});

  final OfflineLoginDecision decision;
  final int graceDays;
  final DateTime? lastVerified;

  bool get allowed => decision == OfflineLoginDecision.allowed;
}

/// مخزنُ الطوابع — واجهةٌ كي تُقاس السياسةُ بلا قناة منصّة.
abstract interface class OfflineLoginStore {
  Future<String?> read();
  Future<void> write(String json);
}

/// التخزين الآمن للمنصّة (‏مفتاح `offline_auth_verified_v1`).
class SecureOfflineLoginStore implements OfflineLoginStore {
  SecureOfflineLoginStore([SecureStorageService? storage])
      : _storage = storage ?? SecureStorageService();

  static const key = 'offline_auth_verified_v1';
  final SecureStorageService _storage;

  @override
  Future<String?> read() => _storage.read(key);

  @override
  Future<void> write(String json) => _storage.write(key, json);
}

class OfflineLoginPolicy {
  OfflineLoginPolicy({
    required OfflineLoginStore store,
    required Future<int?> Function() readGraceDays,
    DateTime Function()? clock,
  })  : _store = store,
        _readGraceDays = readGraceDays,
        _clock = clock ?? DateTime.now;

  static const defaultGraceDays = 7;
  static const maxGraceDays = 365;
  static const clockTolerance = Duration(minutes: 10);
  static const _maxSeenKey = '_max_seen';

  final OfflineLoginStore _store;
  final Future<int?> Function() _readGraceDays;
  final DateTime Function() _clock;

  Future<Map<String, String>> _load() async {
    try {
      final raw = await _store.read();
      if (raw == null || raw.isEmpty) return {};
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return {};
      return {
        for (final e in decoded.entries)
          if (e.value is String) '${e.key}': e.value as String,
      };
    } catch (_) {
      return {};
    }
  }

  DateTime? _parse(String? s) => s == null ? null : DateTime.tryParse(s);

  Future<int> _grace() async {
    final n = await _readGraceDays();
    if (n == null || n < 1) return defaultGraceDays;
    return n > maxGraceDays ? maxGraceDays : n;
  }

  /// تحقّقٌ ناجحٌ بجلسة خادم الآن — يبدأ مدةَ سماحٍ جديدة.
  Future<void> recordVerified(int userId) async {
    final map = await _load();
    final now = _clock();
    final maxSeen = _parse(map[_maxSeenKey]);
    map['$userId'] = now.toUtc().toIso8601String();
    map[_maxSeenKey] =
        (maxSeen != null && maxSeen.isAfter(now) ? maxSeen : now).toUtc().toIso8601String();
    await _store.write(jsonEncode(map));
  }

  /// هل يُسمح لـ[userId] بالدخول والخادمُ غيرُ متاح؟
  Future<OfflineLoginVerdict> check(int userId) async {
    final map = await _load();
    final now = _clock();
    final grace = await _grace();
    final maxSeen = _parse(map[_maxSeenKey]);
    final last = _parse(map['$userId']);

    OfflineLoginVerdict verdict(OfflineLoginDecision d) =>
        OfflineLoginVerdict(d, graceDays: grace, lastVerified: last);

    if (maxSeen != null && now.isBefore(maxSeen.subtract(clockTolerance))) {
      return verdict(OfflineLoginDecision.clockRolledBack);
    }
    // أعلى وقتٍ شوهد يتقدّم دائماً (‏لا يتراجع).
    if (maxSeen == null || now.isAfter(maxSeen)) {
      map[_maxSeenKey] = now.toUtc().toIso8601String();
      try {
        await _store.write(jsonEncode(map));
      } catch (_) {}
    }
    if (last == null) return verdict(OfflineLoginDecision.neverVerified);
    if (now.difference(last) > Duration(days: grace)) {
      return verdict(OfflineLoginDecision.expired);
    }
    return verdict(OfflineLoginDecision.allowed);
  }
}