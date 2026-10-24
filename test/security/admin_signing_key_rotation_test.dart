// SEC-017 — desktop side of the admin signing key rotation: new seed, publish to
// the cloud first (which revokes every admin phone), persist only on success.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:picpos_erp/data/database/database.dart';
import 'package:picpos_erp/services/admin_snapshots/admin_signing_key.dart';
import 'package:picpos_erp/services/cloud_sync/cloud_link_api.dart';
import 'package:picpos_erp/services/cloud_sync/cloud_sync_service.dart';

void main() {
  late AppDatabase db;
  late Map<String, String> secrets;
  late CloudLinkConfigStore store;

  setUp(() {
    db = AppDatabase.forTesting();
    secrets = {};
    store = CloudLinkConfigStore(
      db,
      readSecret: (k) async => secrets[k],
      writeSecret: (k, v) async => secrets[k] = v,
    );
  });
  tearDown(() => db.close());

  test('rotate replaces the seed and publishes the NEW public key first', () async {
    final key = AdminSigningKey(store);
    final oldSigner = await key.load();
    final oldPub = await oldSigner.publicKeyBase64();
    final oldSeed = secrets[AdminSigningKey.storageKey];

    String? published;
    final newSigner = await key.rotate(publish: (pub) async {
      published = pub;
      // at publish time the old seed must still be the stored one
      expect(secrets[AdminSigningKey.storageKey], oldSeed);
    });

    final newPub = await newSigner.publicKeyBase64();
    expect(newPub, isNot(oldPub));
    expect(published, newPub);
    expect(secrets[AdminSigningKey.storageKey], isNot(oldSeed));
    expect(await (await key.load()).publicKeyBase64(), newPub);
    expect(base64.decode(published!), hasLength(32));
  });

  test('a failed publish keeps the old (still registered) key', () async {
    final key = AdminSigningKey(store);
    final oldPub = await (await key.load()).publicKeyBase64();
    final oldSeed = secrets[AdminSigningKey.storageKey];

    await expectLater(
      key.rotate(publish: (_) async => throw CloudLinkException(0, 'network_error')),
      throwsA(isA<CloudLinkException>()),
    );

    expect(secrets[AdminSigningKey.storageKey], oldSeed);
    expect(await (await key.load()).publicKeyBase64(), oldPub);
  });

  test('CloudLinkApi.rotateAdminSigningKey posts the key and returns the revoked count', () async {
    late http.Request seen;
    final api = CloudLinkApi(
      const CloudLinkCredentials(baseUrl: 'https://cloud.example.com', linkId: 'L1', secret: 's3cret'),
      client: MockClient((req) async {
        seen = req;
        return http.Response(jsonEncode({'revokedDevices': 3}), 200, headers: {'content-type': 'application/json'});
      }),
    );
    final n = await api.rotateAdminSigningKey('PUBKEY');
    expect(n, 3);
    expect(seen.method, 'POST');
    expect(seen.url.path, '/desktop/link/rotate-signing-key');
    expect(jsonDecode(seen.body), {'publicKey': 'PUBKEY'});
    expect(seen.headers['x-desktop-link'], 'L1');
  });
}
