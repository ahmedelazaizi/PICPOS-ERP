# `sqlcipher_flutter_libs` is end-of-life upstream - assessment and migration options

Audit finding **DEP-001** (Medium, P1). **No dependency was changed.** This document records the
risk and the supported ways forward so the migration can be scheduled deliberately.

## Facts (from the repository)

| Item | Value |
|---|---|
| Declared | `sqlcipher_flutter_libs: ^0.6.8` (`pubspec.yaml`) |
| Latest on pub.dev | `0.7.0+eol` (an empty, deprecated release that ends the package) |
| Engine actually shipped | SQLCipher `sqlite3.dll` (5.4 MB) built by that package's CMake plugin |
| Enforcement already in place | `build_picpos.bat` step 5 overwrites the bundle's `sqlite3.dll` with the plugin's SQLCipher build and fails unless the DLL contains `sqlcipher`; CI re-checks it; the app probes `PRAGMA cipher_version` at open and refuses a non-SQLCipher engine |
| Trap already documented | a direct `sqlite3` dependency pulls the `sqlite3` build hook, which drops a *plain* `sqlite3.dll` over SQLCipher (see the comment in `pubspec.yaml`) |
| Drift pin | `drift 2.32.1` (exact; the remote protocol needs identical versions on both ends) |

## Assessment

- **No exploitable vulnerability is implied today.** `0.6.8` keeps working and the bundled SQLCipher
  library is unchanged. The risk is *future*: no SQLCipher security fixes will arrive through this
  package, and a Flutter / Dart / CMake / MSVC upgrade may break its native build without a fix.
- The database key handling (`DbKeyManager`, rawV2 keys, legacy-key migration) is independent of
  the delivery mechanism of the engine; only the engine binary and the way it is linked change.
- Impact area: the Windows desktop build (the root app). The Android apps do **not** use this package:
  mobile and packages/picpos_device use sqflite_sqlcipher (a different SQLCipher binding with its
  own lifecycle - assess separately); mobile_pos/mobile_admin do not declare a SQLCipher dependency.
  The web target does not use it.

## Options

| # | Option | Pros | Cons / work |
|---|---|---|---|
| A | **Stay on 0.6.8 and freeze** (status quo, with a review date) | zero change risk | no engine updates; must re-evaluate at every Flutter upgrade |
| B | **`sqlite3` 3.x with the SQLCipher build hook** (upstream's recommended successor: `hooks.user_defines.sqlite3.source: sqlcipher` in `pubspec.yaml`, drift's `sqlite3` + `NativeDatabase`) | maintained path, current SQLCipher | replaces the whole native packaging: the `build_picpos.bat` step 5 DLL overwrite and the "do not depend on sqlite3" rule invert; must re-prove `cipher_version`, key pragmas, WAL/backup behaviour and Android ABI builds |
| C | **Vendor SQLCipher** (own build of the Zetetic Community edition, shipped as `sqlite3.dll` / `.so`) | full control of the version | owns patching and build infrastructure; licence notice duty (BSD-style) |
| D | **Commercial SQLCipher / SQLite Encryption Extension** | vendor support | cost and licensing |

**Recommendation:** B, scheduled as its own release, after Drift/sqlite3 minor upgrades are done.
Until then A, with a calendar review (every Flutter upgrade and at least quarterly).

## Migration gate (must pass before switching)

1. Open an **existing encrypted v196+ database fixture** (legacy-key and rawV2-key variants) with
   the new engine and read it without re-keying (`test/security` key-compat fixture to be added at
   that time).
2. `PRAGMA cipher_version` is non-empty in the packaged artifact; the DLL/SO contains `sqlcipher`
   (CI step "Verify PicPos bundle" already asserts this for Windows).
3. Backup / restore, `sqlcipher_export` based key rotation (M1-M8 flow in `db-key-design.md`) and
   WAL checkpointing work on the new engine.
4. Android: only relevant if the Android apps are moved to the same engine; sqflite_sqlcipher is a separate dependency.
5. Rollback: the pre-upgrade backup (installer, see `REL-003`) restores the previous binary + DB.

## Operational mitigations until then

- Keep `pubspec.lock` pinned; do not run `flutter pub upgrade --major-versions` for this package.
- Subscribe to SQLCipher release notes; re-assess when a CVE is published for the bundled version.
- The mandatory pre-upgrade database backup in the installer limits the blast radius of an engine swap.
