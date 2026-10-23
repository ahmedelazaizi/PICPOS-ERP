# Internal identifier migration — removing the old product name from the PicPos binary

Owner decision 2026-10-23 (BRAND-005 / step B5): the PicPos build must contain no
`ural` text except the Dart package name `picpos_erp` (until the mechanical rename) and
ICU's `Uralsk` time-zone entry — **without locking anyone out**. Existing encrypted
databases (e.g. `Documents\picpos_unified.db` + `.keyinfo.json`), sessions, bearer tokens,
invoice hashes and stored secrets must keep working.

Code: `lib/services/legacy_identifiers.dart` (runtime-assembled old values),
`lib/services/storage_key_migration.dart` (copy → verify → delete helper).
Tests: `test/unit/legacy_identifiers_test.dart`, `test/unit/internal_identifier_migration_test.dart`,
`test/integration/db_key_old_fallback_name_real_test.dart` (real SQLCipher),
`test/structural/brand_artifact_guard_test.dart`, post-build scan `tool/brand_artifact_scan.dart`
(allow-list for these literals is now **empty**).

## Design rules

* **(a) Storage keys** (secure storage / prefs / settings): the PicPos-named key is primary.
  Read: new key → else old key; a valid old value is copied to the new key, **read back and
  compared**, and only then is the old key deleted. Write: new key only (a superseded old copy
  is removed after the new value reads back). Delete: both names (old first). If both exist with
  the same value (earlier run died between copy and delete) the old one is removed; if they
  differ the new one wins and the old one is left untouched (we never delete a value we did not
  copy). Failure of the copy or of the delete never loses data and never throws — the value is
  returned and the next read retries. The old key *names* are still needed at runtime to find
  data written by earlier builds, so they are assembled from masked numbers
  (`LegacyIdentifiers`), not stored as text.
* **(b) Crypto salts / peppers** that feed derived keys or stored hashes: the **bytes stay
  identical**. They are stored XOR-masked as number lists and decoded on first use. The tests
  pin the SHA-256 of every decoded value to the SHA-256 of the previous literal and pin derived
  outputs (bearer token, session signature verification, legacy invoice HMAC, legacy DB key).
* **(c) Labels** (header, log tag, file name, never persisted): renamed to PicPos.

## Per-literal decisions

| # | Old (not in the build any more) | New | Class | Where / how used | Strategy |
|---|---|---|---|---|---|
| 1 | `UralCash-API-v1` | same bytes (`LegacyIdentifiers.apiTokenSalt`) | (b) salt | `ApiAuthMiddleware.generateToken`: `sha256('$machineSeed:$salt')[:32]` = legacy shared LAN bearer (valid inside the pairing transition window) | bytes unchanged; masked list. Golden: `generateToken('seed-1') == f198f467…` |
| 2 | `UralCash-Session-v1` | same bytes (`sessionSalt`) | (b) salt | `ApiSessionToken.deriveKey`: HMAC key of sessions signed with the *derived* key | bytes unchanged. Test: a token signed by the old derivation verifies |
| 3 | `UralCash-ERP-Integrity-v1` | same bytes (`integritySalt`) | (b) HMAC key | `InvoiceIntegrityService`: legacy (pre-`v2:`) signatures stored on invoices; also the pre-init fallback | bytes unchanged. Test: a legacy-signed invoice still verifies; HMAC golden |
| 4 | `UralCash_Security_Pepper_v2` | same bytes (`devicePepper`) | (b) pepper | `LegacyDeviceSeed.deriveFor`: `sha256('$deviceId:$pepper')` = legacy DB key candidate | bytes unchanged (it was already built from char codes; now shares the masked mechanism). Golden: `deriveFor('ABC') == 9488ca7d…` |
| 5 | `ural_db_fallback_enc_key` | `picpos_db_fallback_enc_key` (`DbKeyNames.legacyFallback`) | (a) secure storage | DB key candidate (`DbKeyManager.legacyCandidates`, read-only) and `SecurityService` fallback key (generated on a fresh install without a device id). `clearAll()` must not wipe it | migration on read in both readers (`isValid: length ≥ 32`); `DbKeyNames.isProtected` covers **both** names. Tests: fake-engine + **real SQLCipher** DB opened with a key pre-seeded under the old name |
| 6 | `ural_invoice_integrity_secret_v2` | `picpos_invoice_integrity_secret_v2` | (a) secure storage | per-install HMAC secret for `v2:` invoice signatures | migration on read in `InvoiceIntegrityService.initialize`. **Critical**: a lost secret would invalidate every `v2:` invoice, so the value is copied byte-for-byte; test signs/verifies with an old-named secret |
| 7 | `ural_api_session_hmac_v1` | `picpos_api_session_hmac_v1` | (a) secure storage | `ServerSecrets` session HMAC key (LAN server) | migration on read/write in `ServerSecrets`; same key ⇒ issued sessions keep verifying (tested) |
| 8 | `ural_table_bill_hmac_v1` (+ `_prev`) | `picpos_table_bill_hmac_v1` (+ `_prev`) | (a) secure storage | table-bill token key and its rotation predecessor | same as 7; `legacyNameOf` maps `<new>_prev` → `<old>_prev`; rotate writes the new `_prev` and drops the old one |
| 9 | `ural_lan_install_secret_v1` | `picpos_lan_install_secret_v1` | (a) secure storage | `LanPairingService` install secret: `HMAC(secret, deviceId)` = paired-device tokens | migration on read/write; test: token for a device equals the one computed from the old-named secret (paired devices need no re-pairing) |
| 10 | `ural_api_token` | `picpos_api_token` | (a) secure storage | client's stored bearer (`ServerProxy`); also mirrored in prefs under `network_api_token` | migration on `restoreToken`; `setApiToken` writes new/drops old; clear deletes both names (no resurrection) |
| 11 | `ural_lan_device_name` | `picpos_lan_device_name` | (c) label | `LanPairingClient.deviceNameKey`: nothing reads or writes it (device name = hostname) | simply renamed; no stored value exists to migrate |

Not part of this migration: the Dart package name `picpos_erp` (later rename);
`lib/data/database/daos/api_key_dao.dart` generates API-key strings with an `ural_` prefix in a
dead method (no callers, tree-shaken — verified by the bundle scan). It is data-access code
owned by another stream and is left for them (remains the single entry of `_libLiteralAllowList`
in the guard test).

## Why it cannot lock the owner out

* The owner's DB is `rawV2` (random key in the `db_key_v2__*` primary/shadow slots, names
  unchanged); the fallback key is only a *read-only candidate* tried after the primary/shadow
  slots. For databases still on a legacy key (derived from the device id, or the stored fallback)
  nothing changes: same pepper bytes, same fallback value (now also under the new name).
* A copy always precedes a delete, and a delete only follows a successful read-back comparison.
  Any interruption leaves the value under at least one name; both names are accepted forever as
  read sources and both are protected from `SecureStorageService.clearAll()`.

## Residual risks

* **Downgrade**: after the old key is deleted, re-installing an *older* build on the same Windows
  profile will not find `ural_*` entries. The DB-key entries are still present in the `db_key_v2__*`
  slots for migrated databases; a database that was still on the stored fallback key would need
  the new-named entry (the older build can't see it). Keep a backup before rolling back.
* The runtime-masked values are obfuscation against casual `strings`-style scans, not secrecy;
  none of these salts was ever a secret (they are in git history and in older binaries).
* Byte equality is guarded by SHA-256 pins in `legacy_identifiers_test.dart`; editing a masked
  list without updating the pin fails the test.
