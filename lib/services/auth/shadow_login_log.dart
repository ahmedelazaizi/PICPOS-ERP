// Leftover #1: what `shadow` mode WOULD have rejected, kept as a small bounded
// log so the owner can read it before switching the device to `enforce`.
//
// Device-local setting `offline_login_shadow_log_v1` (in kDeviceLocalSettingKeys:
// never synced). Bounded twice: at most [maxEntries] entries and nothing older
// than [retention]. Reads and writes never throw into the login.
library;

import 'dart:convert';

import '../../data/database/database.dart';
import 'offline_login_policy.dart';

class ShadowLoginSummary {
  const ShadowLoginSummary({
    required this.windowDays,
    required this.total,
    required this.accounts,
    required this.byDecision,
  });

  const ShadowLoginSummary.empty(this.windowDays)
      : total = 0,
        accounts = 0,
        byDecision = const {};

  final int windowDays;

  /// Offline sign-ins that shadow allowed but `enforce` would have refused.
  final int total;

  /// Distinct accounts among them.
  final int accounts;
  final Map<OfflineLoginDecision, int> byDecision;

  bool get isClean => total == 0;
}

class ShadowLoginLog {
  ShadowLoginLog(this.db, {DateTime Function()? clock})
      : _clock = clock ?? DateTime.now;

  static const settingKey = 'offline_login_shadow_log_v1';
  static const maxEntries = 200;
  static const retention = Duration(days: 90);

  final AppDatabase db;
  final DateTime Function() _clock;

  Future<List<Map<String, dynamic>>> _load() async {
    try {
      final raw = await db.getSettingValue(settingKey);
      if (raw == null || raw.trim().isEmpty) return [];
      final j = jsonDecode(raw);
      if (j is! List) return [];
      return [
        for (final e in j)
          if (e is Map && e['t'] is String && e['d'] is String)
            Map<String, dynamic>.from(e),
      ];
    } catch (_) {
      return [];
    }
  }

  /// One shadow-allowed sign-in that `enforce` would have refused.
  Future<void> record(OfflineLoginDecision decision, int userId) async {
    if (decision == OfflineLoginDecision.allowed) return;
    try {
      final now = _clock().toUtc();
      final cutoff = now.subtract(retention);
      final entries = (await _load()).where((e) {
        final t = DateTime.tryParse('${e['t']}');
        return t != null && t.isAfter(cutoff);
      }).toList()
        ..add({'t': now.toIso8601String(), 'u': userId, 'd': decision.name});
      final bounded = entries.length > maxEntries
          ? entries.sublist(entries.length - maxEntries)
          : entries;
      await db.setSetting(settingKey, jsonEncode(bounded));
    } catch (_) {
      // The log is advisory: a storage failure must never block a login.
    }
  }

  Future<ShadowLoginSummary> summary({int days = 30}) async {
    final since = _clock().toUtc().subtract(Duration(days: days));
    final by = <OfflineLoginDecision, int>{};
    final users = <int>{};
    var total = 0;
    for (final e in await _load()) {
      final t = DateTime.tryParse('${e['t']}');
      if (t == null || t.isBefore(since)) continue;
      final d = OfflineLoginDecision.values
          .where((v) => v.name == e['d'])
          .firstOrNull;
      if (d == null) continue;
      total++;
      by[d] = (by[d] ?? 0) + 1;
      final u = e['u'];
      if (u is num) users.add(u.toInt());
    }
    return ShadowLoginSummary(
        windowDays: days, total: total, accounts: users.length, byDecision: by);
  }

  Future<void> clear() async {
    try {
      await db.setSetting(settingKey, '');
    } catch (_) {}
  }
}
