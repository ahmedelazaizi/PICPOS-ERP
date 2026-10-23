// Internal-identifier migration (owner decision 2026-10-23): the crypto salts /
// pepper / OLD storage-key names are assembled at runtime so the PicPos binary
// has no readable old product name — but the bytes MUST equal the previous
// literals, otherwise stored invoice hashes, sessions, bearer tokens and the
// legacy DB-key derivation would change.
//
// The expected SHA-256 values below were computed from the previous literals
// (`git show HEAD~:<file>` at the time of the change: api_auth_middleware.dart,
// api_session_token.dart, invoice_integrity_service.dart, legacy_device_seed.dart
// (char codes), db_key_names.dart, server_secrets.dart, lan_pairing_service.dart,
// server_proxy.dart).
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/services/api/api_auth_middleware.dart';
import 'package:picpos_erp/services/api/api_session_token.dart';
import 'package:picpos_erp/services/invoice_integrity_service.dart';
import 'package:picpos_erp/services/legacy_device_seed.dart';
import 'package:picpos_erp/services/legacy_identifiers.dart';

String _sha(String s) => sha256.convert(utf8.encode(s)).toString();

void main() {
  group('decoded value == previous literal (SHA-256 pinned)', () {
    final expected = <String, ({String actual, String sha})>{
      'apiTokenSalt (UralCash-API-v1)': (
        actual: LegacyIdentifiers.apiTokenSalt,
        sha: '9af46af701258a9ac668358de071b22a62a4865c52bc01fbcd4ba8649b508e15',
      ),
      'sessionSalt (UralCash-Session-v1)': (
        actual: LegacyIdentifiers.sessionSalt,
        sha: '677ce23b1b454c613aad0289ab3ea0ac4f15de37ac6fefbdceaf6d02735ee0bb',
      ),
      'integritySalt (UralCash-ERP-Integrity-v1)': (
        actual: LegacyIdentifiers.integritySalt,
        sha: '029642219fb45dd7644b13af0da2cb8fa1f4f0a98402c6f825ddb1d14cab7729',
      ),
      'devicePepper (UralCash_Security_Pepper_v2)': (
        actual: LegacyIdentifiers.devicePepper,
        sha: '572f36d8e885888814738319b81db5a8ae7ae9a45fc70dd2fc2f571f540b66a8',
      ),
      'dbFallbackStorageKey': (
        actual: LegacyIdentifiers.dbFallbackStorageKey,
        sha: 'c203aede0aef21fc42ebac298aa07c16e9a1d24ea7e8e0d1c192da933c4c7462',
      ),
      'integritySecretStorageKey': (
        actual: LegacyIdentifiers.integritySecretStorageKey,
        sha: 'efcfd001332dd2fe0b76129eb583f962c31673e09c425a4d39f75e7570604045',
      ),
      'sessionHmacStorageKey': (
        actual: LegacyIdentifiers.sessionHmacStorageKey,
        sha: 'e4b81ae00d03cd702f2bdb4e8fdf606737f6162ee9415a1ac69b69f8f5038158',
      ),
      'tableBillHmacStorageKey': (
        actual: LegacyIdentifiers.tableBillHmacStorageKey,
        sha: '8492923d2411508f9f107155c2b8895b8224be756a02859d2627bdcaca5de21b',
      ),
      'lanInstallSecretStorageKey': (
        actual: LegacyIdentifiers.lanInstallSecretStorageKey,
        sha: '5769898522e5349b054cf3fec18f6809a6344c4a5ba9341e54446997902c7129',
      ),
      'apiTokenStorageKey': (
        actual: LegacyIdentifiers.apiTokenStorageKey,
        sha: 'bdf963358aed58c0f4e0b7edd79726a8b8b9d77c0c2b4d5924003984c0944a15',
      ),
    };
    for (final e in expected.entries) {
      test(e.key, () => expect(_sha(e.value.actual), e.value.sha));
    }
  });

  group('derived outputs unchanged (golden values from the old literals)', () {
    test('legacy shared bearer: sha256("seed-1:<salt>")[:32]', () {
      expect(ApiAuthMiddleware.generateToken('seed-1'),
          'f198f467c01506f77c26f67ad439efa5');
    });

    test('session signing key: a token signed with the OLD derivation verifies',
        () {
      // Build a token exactly like the previous build did.
      final key =
          sha256.convert(utf8.encode('seed-1:UralCash-Session-v1')).bytes;
      final now = DateTime.now().millisecondsSinceEpoch;
      final payload = base64Url.encode(utf8.encode(
          jsonEncode({'uid': 7, 'exp': now + 3600000, 'iat': now})));
      final sig = base64Url.encode(
          Hmac(sha256, key).convert(utf8.encode(payload)).bytes);

      ApiSessionToken.deriveKey('seed-1');
      addTearDown(ApiSessionToken.clearKey);
      expect(ApiSessionToken.verify('$payload.$sig'), 7);
    });

    test('legacy device-derived DB key: sha256("ABC:<pepper>")', () {
      expect(LegacyDeviceSeed.deriveFor('ABC'),
          '9488ca7d4aea06239362a2d0750174bc63235dcc348a9d27afbbdbc603a1d5f3');
    });

    test('legacy invoice HMAC key: HMAC-SHA256(old literal, "payload-1")', () {
      // Expected value computed offline from the previous literal.
      final legacy = Hmac(sha256, utf8.encode(LegacyIdentifiers.integritySalt))
          .convert(utf8.encode('payload-1'))
          .toString();
      expect(legacy,
          '91fca5eb9cbc2b9d92e06954455332baff37218cdd5a441d046582fcb3818549');
    });

    test('a legacy-signed stored invoice still verifies (public API)', () {
      // Signature as stored by earlier builds: HMAC(old literal, payload).
      final payload = [
        'N', '2026-01-01T00:00:00.000Z', '1.0000', '1.0000', '0.0000',
        '0.0000', '1.0000', '0', '1', 'cash', //
      ].join('|');
      final stored = Hmac(sha256, utf8.encode('UralCash-ERP-Integrity-v1'))
          .convert(utf8.encode(payload))
          .toString();
      expect(
        InvoiceIntegrityService.verifySalesInvoiceHash(
          storedHash: stored,
          invoiceNumber: 'N',
          invoiceDate: DateTime.parse('2026-01-01T00:00:00.000Z'),
          total: 1,
          subtotal: 1,
          discount: 0,
          tax: 0,
          paid: 1,
          customerId: null,
          userId: 1,
          paymentMethod: 'cash',
        ),
        isTrue,
      );
    });
  });

  test('the identifiers file itself carries no readable old product name', () {
    final src = File('lib/services/legacy_identifiers.dart').readAsStringSync();
    // Only the doc comments may talk about "the old product name" generically.
    expect(RegExp('ural', caseSensitive: false).hasMatch(src), isFalse);
  });
}
