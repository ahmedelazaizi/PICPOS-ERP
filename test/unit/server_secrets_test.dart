// E-02 المرحلة أ: ServerSecrets — أسرارُ الخادم العشوائيةُ المستقلّة.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/services/api/api_session_token.dart';
import 'package:picpos_erp/services/api/server_secrets.dart';
import 'package:picpos_erp/services/api/table_bill_token.dart';
import 'package:picpos_erp/services/secret_store.dart';

class _FailingStore extends MemorySecretStore {
  _FailingStore({this.failRead = false, this.failWrite = false, this.dropWrites = false});
  bool failRead;
  bool failWrite;
  bool dropWrites; // يكتب بلا أثر ⇒ فشلُ إعادة القراءة

  @override
  Future<String?> read(String key) async {
    if (failRead) throw StateError('read boom');
    return super.read(key);
  }

  @override
  Future<void> write(String key, String value) async {
    if (failWrite) throw StateError('write boom');
    if (dropWrites) return;
    return super.write(key, value);
  }
}

void main() {
  late List<String> logs;
  Future<void> logger(String tag, String msg) async => logs.add('[$tag] $msg');

  setUp(() {
    logs = [];
    ApiSessionToken.clearKey();
    TableBillToken.clearKey();
  });
  tearDown(() {
    ApiSessionToken.clearKey();
    TableBillToken.clearKey();
  });

  test('يولّد عند الغياب (مع سجلّ واضح) ويكتب السرّين بطول 32 بايت', () async {
    final store = MemorySecretStore();
    final s = ServerSecrets(store: store, logger: logger);
    await s.initialize();

    expect(base64Url.decode(store.values[ServerSecrets.sessionStorageKey]!).length, 32);
    expect(base64Url.decode(store.values[ServerSecrets.tableBillStorageKey]!).length, 32);
    expect(store.values[ServerSecrets.sessionStorageKey],
        isNot(store.values[ServerSecrets.tableBillStorageKey]));
    expect(logs.where((l) => l.startsWith('[SEC-WARN]')).length, 2);
    expect(ApiSessionToken.isReady, isTrue);
    expect(TableBillToken.isReady, isTrue);
  });

  test('إعادة القراءة بعد الكتابة: مثيل جديد على نفس المخزن يحصل على نفس السرّ',
      () async {
    final store = MemorySecretStore();
    final a = ServerSecrets(store: store, logger: logger);
    await a.initialize();
    final token = ApiSessionToken.mint(7);

    ApiSessionToken.clearKey();
    final b = ServerSecrets(store: store, logger: logger);
    final before = logs.length;
    await b.initialize();

    expect(b.sessionKey, a.sessionKey);
    expect(b.tableBillKey, a.tableBillKey);
    expect(logs.length, before, reason: 'لا توليد ولا تحذير عند وجود السرّ');
    expect(ApiSessionToken.verify(token), 7,
        reason: 'الرمز يبقى صالحاً عبر إعادة التشغيل');
  });

  test('قيمة تالفة أو قصيرة تُعامَل كغائبة وتُولَّد من جديد مع تحذير', () async {
    final store = MemorySecretStore({
      ServerSecrets.sessionStorageKey: 'short',
      ServerSecrets.tableBillStorageKey: '!!!not-base64!!!',
    });
    await ServerSecrets(store: store, logger: logger).initialize();
    expect(base64Url.decode(store.values[ServerSecrets.sessionStorageKey]!).length, 32);
    expect(logs.where((l) => l.startsWith('[SEC-WARN]')).length, 2);
  });

  test('فشل القراءة/الكتابة/إعادة القراءة ⇒ ServerSecretsUnavailableException', () async {
    for (final store in [
      _FailingStore(failRead: true),
      _FailingStore(failWrite: true),
      _FailingStore(dropWrites: true),
    ]) {
      await expectLater(
        ServerSecrets(store: store, logger: logger).initialize(),
        throwsA(isA<ServerSecretsUnavailableException>()),
      );
    }
    expect(ApiSessionToken.isReady, isFalse,
        reason: 'لا مفتاح جزئي بعد الفشل');
  });

  test('rotate(session): مفتاح جديد، لا فترة سماح، ولا <key>_prev', () async {
    final store = MemorySecretStore();
    final s = ServerSecrets(store: store, logger: logger);
    await s.initialize();
    final oldId = ApiSessionToken.keyId;
    final oldToken = ApiSessionToken.mint(3);

    await s.rotate(ServerSecretKind.session);

    expect(ApiSessionToken.keyId, isNot(oldId));
    expect(ApiSessionToken.verify(oldToken), isNull);
    expect(ApiSessionToken.verify(ApiSessionToken.mint(3)), 3);
    expect(store.values.containsKey(
        ServerSecrets.previousKeyOf(ServerSecrets.sessionStorageKey)), isFalse);
    expect(logs.last, contains('تدوير'));
  });

  test('rotate(tableBill): يحفظ <key>_prev، القديم يُقبل للتحقق والجديد يُصدَر', () async {
    final store = MemorySecretStore();
    final s = ServerSecrets(store: store, logger: logger);
    await s.initialize();
    final oldQr = TableBillToken.mintTable(5);
    final oldKeyB64 = store.values[ServerSecrets.tableBillStorageKey];

    await s.rotate(ServerSecretKind.tableBill);

    expect(store.values[ServerSecrets.previousKeyOf(ServerSecrets.tableBillStorageKey)],
        oldKeyB64);
    expect(store.values[ServerSecrets.tableBillStorageKey], isNot(oldKeyB64));
    expect(TableBillToken.verifyTable(oldQr), 5);
    final newQr = TableBillToken.mintTable(5);
    expect(newQr, isNot(oldQr));
    expect(TableBillToken.verifyTable(newQr), 5);

    // إعادة تشغيل: السابق يُحمَّل من التخزين.
    TableBillToken.clearKey();
    await ServerSecrets(store: store, logger: logger).initialize();
    expect(TableBillToken.verifyTable(oldQr), 5);
  });

  test('rotate عند فشل الكتابة يرمي ولا يبدّل المفتاح الحيّ', () async {
    final store = _FailingStore();
    final s = ServerSecrets(store: store, logger: logger);
    await s.initialize();
    final idBefore = ApiSessionToken.keyId;
    final tokenBefore = ApiSessionToken.mint(4);

    store.failWrite = true;
    await expectLater(s.rotate(ServerSecretKind.session),
        throwsA(isA<ServerSecretsUnavailableException>()));
    expect(ApiSessionToken.keyId, idBefore);
    expect(ApiSessionToken.verify(tokenBefore), 4);
  });
}
