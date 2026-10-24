import 'dart:convert';

import 'package:picpos_api_client/picpos_api_client.dart';

import '../cloud_sync/cloud_sync_service.dart';

/// Ed25519 seed is stored beside the desktop link secret, never in settings.
class AdminSigningKey {
  AdminSigningKey(this.store);

  static const storageKey = 'cloud_link_admin_signing_seed';
  final CloudLinkConfigStore store;

  Future<PayloadSigner> load() async {
    final stored = await store.readSecret(storageKey);
    if (stored != null) {
      return PayloadSigner.fromSeed(base64.decode(stored));
    }
    final seed = PayloadSigner.newSeed();
    await store.writeSecret(storageKey, base64.encode(seed));
    return PayloadSigner.fromSeed(seed);
  }

  /// SEC-017: replaces the seed. [publish] receives the NEW public key and must
  /// register it with the cloud (which also revokes every paired admin phone);
  /// the new seed is stored only after that call succeeded, so a failed
  /// network call leaves the old (still registered) key in place.
  Future<PayloadSigner> rotate({
    required Future<void> Function(String newPublicKey) publish,
  }) async {
    final seed = PayloadSigner.newSeed();
    final signer = await PayloadSigner.fromSeed(seed);
    await publish(await signer.publicKeyBase64());
    await store.writeSecret(storageKey, base64.encode(seed));
    return signer;
  }
}
