import 'dart:convert';
import 'dart:math';

import '../../core/logging/diagnostic_logger.dart';
import '../secret_store.dart';
import 'api_session_token.dart';
import 'table_bill_token.dart';

/// أسرارُ الخادم المستقلّة (E-02، المرحلة أ): سرّان عشوائيّان لا علاقة لهما
/// بمفتاح القاعدة ولا ببذرة الجهاز.
enum ServerSecretKind { session, tableBill }

/// تعذّر تخزين/قراءة أسرار الخادم. يمنع **بدء الخادم فقط** لا التطبيق كلَّه.
class ServerSecretsUnavailableException implements Exception {
  const ServerSecretsUnavailableException(this.reason);
  final String reason;

  @override
  String toString() => 'ServerSecretsUnavailableException: $reason';
}

/// على نمط `LanPairingService.initialize`: إن وُجد السرّ استُعمل، وإلا وُلِّد
/// وكُتب وأُعيدت قراءتُه ومقارنتُه.
///
/// ⚠️ «ولِّد عند null» مقبولٌ **هنا فقط** (بخلاف مفتاح القاعدة): فقدانُ هذه
/// الأسرار يُبطل جلساتٍ/رموزاً ولا يفقد بياناتٍ. لكن `null` على ويندوز قد يعني
/// عطلاً في التخزين (§0.7) فيُسجَّل بوضوح في `DiagnosticLogger`.
class ServerSecrets {
  ServerSecrets({
    SecretStore? store,
    Random? random,
    Future<void> Function(String tag, String message)? logger,
  })  : _store = store ?? SecureStorageSecretStore(),
        _random = random ?? Random.secure(),
        _log = logger ?? DiagnosticLogger.log;

  static const sessionStorageKey = 'ural_api_session_hmac_v1';
  static const tableBillStorageKey = 'ural_table_bill_hmac_v1';
  static String previousKeyOf(String key) => '${key}_prev';

  static String storageKeyFor(ServerSecretKind kind) => switch (kind) {
        ServerSecretKind.session => sessionStorageKey,
        ServerSecretKind.tableBill => tableBillStorageKey,
      };

  final SecretStore _store;
  final Random _random;
  final Future<void> Function(String tag, String message) _log;

  List<int>? _sessionKey;
  List<int>? _tableBillKey;
  List<int>? _tableBillPrevKey;

  bool get isInitialized => _sessionKey != null && _tableBillKey != null;

  List<int> get sessionKey => _sessionKey ?? (throw StateError('not initialized'));
  List<int> get tableBillKey =>
      _tableBillKey ?? (throw StateError('not initialized'));
  List<int>? get tableBillPreviousKey => _tableBillPrevKey;

  /// يحمّل/يولّد السرّين ويضبطهما على [ApiSessionToken] و[TableBillToken].
  /// يرمي [ServerSecretsUnavailableException] عند فشل التخزين.
  Future<void> initialize() async {
    _sessionKey = await _loadOrCreate(sessionStorageKey, 'الجلسات');
    _tableBillKey = await _loadOrCreate(tableBillStorageKey, 'رموز الطاولات');
    _tableBillPrevKey = await _readValid(previousKeyOf(tableBillStorageKey));
    _apply();
  }

  /// يدوّر سرّ [kind]. الجلسات: بلا فترة سماح (تُبطَل كلُّها؛ العملاء يعيدون
  /// السكّ عبر `sessionKeyId`). الطاولات: الحاليّ يُحفظ كـ`<key>_prev` ويبقى
  /// مقبولاً للتحقّق فقط.
  Future<void> rotate(ServerSecretKind kind) async {
    if (!isInitialized) await initialize();
    final key = storageKeyFor(kind);
    final fresh = _generate();
    try {
      if (kind == ServerSecretKind.tableBill) {
        await _store.write(previousKeyOf(key), base64UrlEncode(_tableBillKey!));
      }
      await _writeVerified(key, fresh);
    } catch (e) {
      if (e is ServerSecretsUnavailableException) rethrow;
      throw ServerSecretsUnavailableException('rotate($kind): $e');
    }
    if (kind == ServerSecretKind.session) {
      _sessionKey = fresh;
    } else {
      _tableBillPrevKey = _tableBillKey;
      _tableBillKey = fresh;
    }
    _apply();
    await _log('SEC', 'تدوير سرّ الخادم: ${kind.name} (كلُّ الرموز السابقة '
        '${kind == ServerSecretKind.session ? "أُبطلت" : "تُقبل للتحقّق فقط"})');
  }

  void _apply() {
    ApiSessionToken.setSigningKey(_sessionKey!);
    TableBillToken.setSigningKey(_tableBillKey!);
    TableBillToken.setPreviousSigningKey(_tableBillPrevKey);
  }

  Future<List<int>> _loadOrCreate(String storageKey, String label) async {
    try {
      final existing = await _readValid(storageKey);
      if (existing != null) return existing;
      final fresh = _generate();
      await _writeVerified(storageKey, fresh);
      await _log(
        'SEC-WARN',
        'سرّ $label أُنشئ (أو أُعيد توليده) لأنه غير موجود/غير صالح في التخزين '
            'الآمن [$storageKey]. إن لم يكن هذا أوّلَ تشغيل فقد يدلّ على عطلٍ '
            'في التخزين الآمن؛ تُبطَل الرموز السابقة.',
      );
      return fresh;
    } catch (e) {
      if (e is ServerSecretsUnavailableException) rethrow;
      throw ServerSecretsUnavailableException('$storageKey: $e');
    }
  }

  Future<List<int>?> _readValid(String storageKey) async {
    final String? raw;
    try {
      raw = await _store.read(storageKey);
    } catch (e) {
      throw ServerSecretsUnavailableException('read $storageKey: $e');
    }
    if (raw == null) return null;
    try {
      final bytes = base64Url.decode(raw);
      return bytes.length >= 32 ? bytes : null;
    } catch (_) {
      return null;
    }
  }

  Future<void> _writeVerified(String storageKey, List<int> bytes) async {
    final encoded = base64UrlEncode(bytes);
    try {
      await _store.write(storageKey, encoded);
    } catch (e) {
      throw ServerSecretsUnavailableException('write $storageKey: $e');
    }
    final back = await _store.read(storageKey);
    if (back != encoded) {
      throw ServerSecretsUnavailableException(
          'readback mismatch for $storageKey');
    }
  }

  List<int> _generate() => List<int>.generate(32, (_) => _random.nextInt(256));
}
