import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'secret_store.dart';
import 'storage_key_migration.dart';

/// S-04: يخزّن الأسرار (API token، كلمة مرور مفتاح TLS) في التخزين الآمن بدل
/// SharedPreferences النصيّ، مع ترحيلٍ تلقائيّ لمرةٍ واحدة:
///  * القراءة: الآمن أولاً؛ إن غاب وُجدت نسخة prefs قديمة تُنسخ إلى الآمن
///    وتُتحقَّق ثم تُحذف من prefs (لا يضيع الاقتران القائم).
///  * فشل الآمن (استثناء/غير متاح): تُقرأ/تُكتب نسخة prefs القديمة دون كسر،
///    مع تحذير لا يحوي القيمة أبداً.
///  * كل عملية (قراءة/كتابة/حذف) على سرٍّ تنتظر آخر عملية جارية له، فلا تقرأ
///    قراءةٌ قبل اكتمال كتابةٍ غير منتظَرة (مثل ServerProxy.setApiToken).
class SecureTokenStore {
  SecureTokenStore({
    SecretStore? store,
    Future<SharedPreferences> Function()? prefsLoader,
    void Function(String message)? warn,
  })  : _store = store ?? const FlutterSecureSecretStore(FlutterSecureStorage()),
        _prefsLoader = prefsLoader ?? SharedPreferences.getInstance,
        _warn = warn ?? ((m) => debugPrint('[SecureTokenStore] $m'));

  /// النسخة المشتركة؛ تُستبدل في الاختبارات.
  static SecureTokenStore instance = SecureTokenStore();

  /// API token: نفس مفتاح الآمن الذي يستعمله ServerProxy.
  static const apiToken = SecureSecret(
    secureKey: 'picpos_api_token',
    prefKey: 'network_api_token',
  );

  /// كلمة مرور مفتاح TLS المخصّص.
  static const tlsKeyPassword = SecureSecret(
    secureKey: 'picpos_tls_key_password',
    prefKey: 'network_tls_key_password',
  );

  final SecretStore _store;
  final Future<SharedPreferences> Function() _prefsLoader;
  final void Function(String message) _warn;

  /// آخر عملية جارية لكل مفتاح سرّ (بالاسم الآمن)، تُسلسَل خلفها العمليات التالية.
  final Map<String, Future<void>> _pending = {};

  /// قيمة السرّ، أو null. [legacySecureKey] اسم قديم في الآمن (ترحيل إعادة التسمية).
  Future<String?> read(SecureSecret s, {String? legacySecureKey}) =>
      _serialized(
          s.secureKey, () => _read(s, legacySecureKey: legacySecureKey));

  Future<String?> _read(SecureSecret s, {String? legacySecureKey}) async {
    String? secure;
    var secureOk = true;
    try {
      secure = await StorageKeyMigration.read(
        _store,
        newKey: s.secureKey,
        oldKey: legacySecureKey ?? s.secureKey,
      );
    } catch (_) {
      secureOk = false;
      _warn('secure storage unavailable reading ${s.secureKey}; '
          'falling back to legacy prefs');
    }
    final prefs = await _tryPrefs();
    final legacy = prefs?.getString(s.prefKey);
    final hasLegacy = legacy != null && legacy.isNotEmpty;

    if (secure != null && secure.isNotEmpty) {
      if (prefs != null && prefs.containsKey(s.prefKey)) {
        await _removePref(prefs, s); // نسخة بائتة بنص صريح
      }
      return secure;
    }
    if (!hasLegacy) return null;
    if (secureOk && await _copyToSecure(s, legacy)) {
      await _removePref(prefs!, s);
    }
    return legacy;
  }

  /// يكتب السرّ في الآمن ويزيل نسخة prefs؛ عند فشل الآمن يتراجع إلى prefs.
  Future<void> write(SecureSecret s, String value,
          {String? legacySecureKey}) =>
      _serialized(s.secureKey,
          () => _write(s, value, legacySecureKey: legacySecureKey));

  Future<void> _write(SecureSecret s, String value,
      {String? legacySecureKey}) async {
    final prefs = await _tryPrefs();
    try {
      await StorageKeyMigration.write(
        _store,
        newKey: s.secureKey,
        oldKey: legacySecureKey ?? s.secureKey,
        value: value,
      );
      if (prefs != null) await _removePref(prefs, s);
    } catch (_) {
      _warn('secure storage unavailable writing ${s.secureKey}; '
          'kept in legacy prefs');
      try {
        await prefs?.setString(s.prefKey, value);
      } catch (_) {}
    }
  }

  /// يحذف السرّ من الآمن (الاسمين) ومن prefs.
  Future<void> delete(SecureSecret s, {String? legacySecureKey}) =>
      _serialized(
          s.secureKey, () => _delete(s, legacySecureKey: legacySecureKey));

  Future<void> _delete(SecureSecret s, {String? legacySecureKey}) async {
    try {
      await StorageKeyMigration.delete(
        _store,
        newKey: s.secureKey,
        oldKey: legacySecureKey ?? s.secureKey,
      );
    } catch (_) {
      _warn('secure storage unavailable deleting ${s.secureKey}');
    }
    final prefs = await _tryPrefs();
    if (prefs != null) await _removePref(prefs, s);
  }

  /// يُشغِّل [op] بعد انتهاء آخر عملية جارية لنفس [key] ويُرجع نتيجتها.
  /// فشلُ عملية لا يوقف اللاحقة، والخريطة لا تحتفظ إلا بالعملية الأخيرة.
  Future<T> _serialized<T>(String key, Future<T> Function() op) {
    final previous = _pending[key] ?? Future<void>.value();
    final run = previous.then((_) => op());
    final tail = run.then<void>((_) {}, onError: (Object _) {});
    _pending[key] = tail;
    unawaited(tail.then((_) {
      if (identical(_pending[key], tail)) _pending.remove(key);
    }));
    return run;
  }

  Future<bool> _copyToSecure(SecureSecret s, String value) async {
    try {
      await _store.write(s.secureKey, value);
      return await _store.read(s.secureKey) == value;
    } catch (_) {
      _warn('migration of ${s.secureKey} to secure storage failed; '
          'legacy prefs copy kept');
      return false;
    }
  }

  Future<SharedPreferences?> _tryPrefs() async {
    try {
      return await _prefsLoader();
    } catch (_) {
      return null;
    }
  }

  Future<void> _removePref(SharedPreferences prefs, SecureSecret s) async {
    try {
      await prefs.remove(s.prefKey);
    } catch (_) {}
  }
}

/// اسما سرٍّ واحد: مفتاح التخزين الآمن ومفتاح prefs القديم.
class SecureSecret {
  const SecureSecret({required this.secureKey, required this.prefKey});
  final String secureKey;
  final String prefKey;
}
