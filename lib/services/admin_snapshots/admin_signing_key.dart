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
}
