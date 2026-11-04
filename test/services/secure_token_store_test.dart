import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/services/secret_store.dart';
import 'package:picpos_erp/services/secure_token_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FailingStore implements SecretStore {
  @override
  Future<String?> read(String key) async => throw StateError('unavailable');
  @override
  Future<void> write(String key, String value) async =>
      throw StateError('unavailable');
  @override
  Future<void> delete(String key) async => throw StateError('unavailable');
}

/// مخزنٌ تفشل كتابتُه بعد [_writeFailAfter] (كما يتأخر فشل الكتابة في الآمن)،
/// وتفشل قراءتُه فوراً.
class _SlowFailingStore implements SecretStore {
  _SlowFailingStore(this._writeFailAfter);
  final Duration _writeFailAfter;

  @override
  Future<String?> read(String key) async => throw StateError('unavailable');
  @override
  Future<void> write(String key, String value) async {
    await Future<void>.delayed(_writeFailAfter);
    throw StateError('unavailable');
  }

  @override
  Future<void> delete(String key) async => throw StateError('unavailable');
}

/// مخزنٌ في الذاكرة تصل كتاباتُه بتأخيرٍ مختلف: الكتابة رقم i تنتظر
/// [_writeDelaysMs][i] ms قبل أن تُكتب فعلاً.
class _ReorderingStore implements SecretStore {
  _ReorderingStore(this._inner, this._writeDelaysMs);
  final MemorySecretStore _inner;
  final List<int> _writeDelaysMs;

  @override
  Future<String?> read(String key) => _inner.read(key);
  @override
  Future<void> write(String key, String value) async {
    final ms = _writeDelaysMs.isEmpty ? 0 : _writeDelaysMs.removeAt(0);
    await Future<void>.delayed(Duration(milliseconds: ms));
    await _inner.write(key, value);
  }

  @override
  Future<void> delete(String key) => _inner.delete(key);
}

void main() {
  const secret = SecureTokenStore.apiToken;
  const pwd = SecureTokenStore.tlsKeyPassword;

  late MemorySecretStore mem;
  late List<String> warnings;

  SecureTokenStore make(SecretStore s) => SecureTokenStore(
        store: s,
        prefsLoader: SharedPreferences.getInstance,
        warn: warnings.add,
      );

  setUp(() {
    mem = MemorySecretStore();
    warnings = [];
  });

  test('migrates legacy prefs value to secure store and removes it', () async {
    SharedPreferences.setMockInitialValues({
      secret.prefKey: 'tok-123',
      pwd.prefKey: 'pw-456',
    });
    final store = make(mem);

    expect(await store.read(secret), 'tok-123');
    expect(await store.read(pwd), 'pw-456');

    expect(mem.values[secret.secureKey], 'tok-123');
    expect(mem.values[pwd.secureKey], 'pw-456');
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.containsKey(secret.prefKey), isFalse);
    expect(prefs.containsKey(pwd.prefKey), isFalse);
  });

  test('read after re-creating the store still returns the value', () async {
    SharedPreferences.setMockInitialValues({secret.prefKey: 'tok-123'});
    expect(await make(mem).read(secret), 'tok-123');
    expect(await make(mem).read(secret), 'tok-123'); // prefs now empty
  });

  test('write stores securely and leaves nothing in prefs', () async {
    SharedPreferences.setMockInitialValues({secret.prefKey: 'old'});
    await make(mem).write(secret, 'new');
    expect(mem.values[secret.secureKey], 'new');
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getKeys(), isEmpty);
  });

  test('stale prefs copy is dropped when secure value exists', () async {
    SharedPreferences.setMockInitialValues({secret.prefKey: 'stale'});
    mem.values[secret.secureKey] = 'fresh';
    expect(await make(mem).read(secret), 'fresh');
    expect((await SharedPreferences.getInstance()).getKeys(), isEmpty);
  });

  test('secure failure falls back to legacy prefs without throwing', () async {
    SharedPreferences.setMockInitialValues({secret.prefKey: 'tok-123'});
    final store = make(_FailingStore());

    expect(await store.read(secret), 'tok-123');
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(secret.prefKey), 'tok-123'); // not lost
    expect(warnings, isNotEmpty);
    expect(warnings.any((w) => w.contains('tok-123')), isFalse);
  });

  test('secure write failure keeps value in prefs, warning has no value',
      () async {
    SharedPreferences.setMockInitialValues({});
    final store = make(_FailingStore());
    await store.write(pwd, 'pw-secret');
    expect((await SharedPreferences.getInstance()).getString(pwd.prefKey),
        'pw-secret');
    expect(warnings, isNotEmpty);
    expect(warnings.any((w) => w.contains('pw-secret')), isFalse);
  });

  test('delete clears both secure and prefs', () async {
    SharedPreferences.setMockInitialValues({secret.prefKey: 'x'});
    mem.values[secret.secureKey] = 'x';
    await make(mem).delete(secret);
    expect(mem.values, isEmpty);
    expect((await SharedPreferences.getInstance()).getKeys(), isEmpty);
    expect(await make(mem).read(secret), isNull);
  });

  test('legacy secure key name is migrated too', () async {
    SharedPreferences.setMockInitialValues({});
    mem.values['old_name'] = 'tok';
    final store = make(mem);
    expect(await store.read(secret, legacySecureKey: 'old_name'), 'tok');
    expect(mem.values[secret.secureKey], 'tok');
    expect(mem.values.containsKey('old_name'), isFalse);
  });

  test('unawaited secure write that fails is seen by an immediate read',
      () async {
    SharedPreferences.setMockInitialValues({});
    final store = make(_SlowFailingStore(const Duration(milliseconds: 20)));

    // كما في ServerProxy.setApiToken: الكتابة لا تُنتظَر ثم تأتي قراءة فورية.
    unawaited(store.write(secret, 'tok-live'));
    expect(await store.read(secret), 'tok-live');

    expect((await SharedPreferences.getInstance()).getString(secret.prefKey),
        'tok-live');
    expect(warnings, isNotEmpty);
    expect(warnings.any((w) => w.contains('tok-live')), isFalse);
  });

  test('two unawaited writes then a delete end empty, in call order',
      () async {
    SharedPreferences.setMockInitialValues({});
    // لو لم تُسلسَل الكتابات تنزل الأولى (المتأخرة) بعد الحذف فتعود 'first'.
    final store = make(_ReorderingStore(mem, [30, 0]));

    unawaited(store.write(secret, 'first'));
    unawaited(store.write(secret, 'second'));
    unawaited(store.delete(secret));

    expect(await store.read(secret), isNull);
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(mem.values, isEmpty);
    expect((await SharedPreferences.getInstance()).getKeys(), isEmpty);
  });
}
