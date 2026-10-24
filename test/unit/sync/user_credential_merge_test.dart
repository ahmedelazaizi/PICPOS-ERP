// CRED-WIPE (plan P0) — the single credential-merge rule used by the users
// full-sync (UserSyncStrategy) and delta pull (DeltaPullService).
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/services/sync/user_credential_merge.dart';

const _argon = r'$argon2id$v=19$m=19456,t=2,p=1$c2FsdHNhbHRzYWx0$aGFzaGhhc2hoYXNoaGFzaA';
const _argon2 = r'$argon2id$v=19$m=19456,t=2,p=1$b3RoZXJzYWx0$b3RoZXJoYXNoaGFzaGhhc2g';
const _pbkdf = 'c29tZWxlZ2FjeWhhc2hzb21lbGVnYWN5aGFzaHNvbWU=';

Future<({String hash, String salt})> _mint() async =>
    (hash: r'$argon2id$v=19$m=1,t=1,p=1$bWludA$bWludGVk', salt: 'minted-salt');

void main() {
  group('isCredentialComplete', () {
    test('Argon2id PHC is complete with an EMPTY salt column', () {
      expect(isCredentialComplete(_argon, ''), isTrue);
      expect(isCredentialComplete(_argon, null), isTrue);
    });
    test('legacy hash needs a non-empty salt', () {
      expect(isCredentialComplete(_pbkdf, ''), isFalse);
      expect(isCredentialComplete(_pbkdf, 'salt'), isTrue);
    });
    test('empty / null hash and a truncated PHC are never complete', () {
      expect(isCredentialComplete('', 'salt'), isFalse);
      expect(isCredentialComplete(null, 'salt'), isFalse);
      expect(isCredentialComplete(r'$argon2id$v=19', ''), isFalse);
    });
  });

  group('resolveCredential', () {
    test('complete server credential wins over everything', () async {
      final r = await resolveCredential(
        serverHash: _argon2,
        serverSalt: '',
        localHash: _argon,
        localSalt: '',
        mint: _mint,
      );
      expect(r.source, CredentialSource.server);
      expect(r.hash, _argon2);
      expect(r.salt, '');
    });

    test('server without credentials keeps the local ARGON2 row (salt "")',
        () async {
      final r = await resolveCredential(
        localHash: _argon,
        localSalt: '',
        mint: _mint,
      );
      expect(r.source, CredentialSource.local);
      expect(r.hash, _argon);
    });

    test('server sends a hash with an empty salt (legacy form): local kept',
        () async {
      final r = await resolveCredential(
        serverHash: _pbkdf,
        serverSalt: '',
        localHash: _argon,
        localSalt: '',
        mint: _mint,
      );
      expect(r.source, CredentialSource.local);
    });

    test('local PBKDF2 row with salt is kept', () async {
      final r = await resolveCredential(
        localHash: _pbkdf,
        localSalt: 'abc',
        mint: _mint,
      );
      expect(r.source, CredentialSource.local);
      expect(r.salt, 'abc');
    });

    test('no server, broken local -> offline duplicate hash', () async {
      final r = await resolveCredential(
        localHash: '',
        localSalt: '',
        dupHash: _argon2,
        dupSalt: '',
        mint: _mint,
      );
      expect(r.source, CredentialSource.duplicate);
      expect(r.hash, _argon2);
    });

    test('nothing usable anywhere -> unusable credential minted (SEC-004)',
        () async {
      var minted = 0;
      final r = await resolveCredential(mint: () async {
        minted++;
        return _mint();
      });
      expect(r.source, CredentialSource.unusable);
      expect(minted, 1);
    });

    test('a complete local credential never triggers minting', () async {
      var minted = 0;
      await resolveCredential(
        localHash: _argon,
        localSalt: '',
        mint: () async {
          minted++;
          return _mint();
        },
      );
      expect(minted, 0);
    });

    test('idempotent: resolving the result again yields the same credential',
        () async {
      final first = await resolveCredential(localHash: _argon, localSalt: '');
      final second = await resolveCredential(
          localHash: first.hash, localSalt: first.salt);
      expect(second.hash, first.hash);
      expect(second.source, CredentialSource.local);
    });
  });
}
