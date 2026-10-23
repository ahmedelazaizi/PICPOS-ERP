# BRAND remediation notes — "PicPos only" (2026-10-23)

Owner requirement (binding): *the system is PicPos only; nothing that concerns PicPos may mention the other product — no files, images, icons, strings, names, ids, installer text, shipping docs, build outputs or metadata. Files shared by both products are **copied** and the copy is converted; the other product's side is not deleted or altered. There are no real PicPos customers, so PicPos data folder / DB / registry names may be renamed.*

Source audit: `axis-C-product-ux-release/FINDINGS-C.md` (BRAND-001..012, REL-001/004, 8-step plan). This note records what was done, what was deliberately left, and the remaining `ural` / `monexia` occurrences.

## 1. Mechanism decisions

| Topic | Decision | Why |
|---|---|---|
| Brand-conditional Flutter assets | **Not available** on Windows (no `--flavor`). The alternate brand's `logo.PNG` stays declared in `pubspec.yaml`; `tool/prune_picpos_bundle.ps1` **deletes it from the built PicPos bundle** (called by `build_picpos.bat`, so by CI too). | Removing it from pubspec would break every default-brand widget test and the alternate product; the repo already uses a "file copy at build time" mechanism for the icon. The guard proves the result. |
| `catalog_ar.json` | Removed from `pubspec.yaml` assets (no runtime or test reader; dev tool `tool/i18n/extract_catalog.dart` still reads it from disk). Three stale entries removed from the file. | BRAND-002: 1.1 MB source-layout map was shipped. |
| `en.json` | Three alternate-brand keys removed. The code that used them now builds the text from a brand constant (`tr('تطوير: {p0}', {'p0': Brand.vendorName})`, `tr('مرحباً بك في {p0}', …)`) or bypasses `tr()` for the alternate-brand Arabic name. | `i18n_coverage_test` needs every `tr()` key in `en.json`; no key mentions the other brand any more. |
| Dart `APP_BRAND` default | **Left `uralcash`.** | ~1,300 test files run with the default brand and assert the legacy forks; flipping it breaks them. PicPos builds always pass `--dart-define=APP_BRAND=picpos` (`build_picpos.bat`, CI). Native defaults (CMake / `Runner.rc` / `main.cpp`) **were** flipped to PicPos. |
| Installer script | New **`installer/setup_picpos.iss`** (PicPos-only copy, no `BrandId` switch). `installer/setup.iss` untouched (alternate side). | "Copy, convert the copy". `build_installer_picpos.bat` and `tool/make_release_checksums.ps1` use the copy; `installer_version_matches_pubspec_test` checks both. |
| Customer PG guide | New `tools/postgresql_setup_guide_picpos.md` (`picpos` db/user, PicPos name). Original untouched. | BRAND-010 P1 item. |
| Post-build scan | `tool/brand_artifact_scan.dart` is **pure Dart**; `build_picpos.bat` step 5c runs it on the real bundle. | A `flutter test` right after `flutter build windows` crashes (`PathExistsException` on the copied `sqlite3.dll`), observed in the first build attempt. |
| `*.ps1` ignored by git | Added `!tool/*.ps1` to `.gitignore`. | `*.ps1` is ignored repo-wide; without this the new prune script would not be committed and CI would fail. |

## 2. Findings status

| Id | Status | Notes |
|---|---|---|
| BRAND-001 logo in bundle | **Fixed** | Pruned from the bundle; hash deny-list in guard. Source `logo.PNG` kept for the alternate product. |
| BRAND-002 catalogs | **Fixed** | `catalog_ar.json` not bundled; `en.json` clean. |
| BRAND-003 CI release publishes wrong brand | **Fixed (not executed)** | `build-windows` now runs `build_picpos.bat`, re-verifies identity / SQLCipher / version, zips `FlavorBuilds\PicPos`. Not run on GitHub. |
| BRAND-004 defaults | **Partial** | Native defaults → PicPos. Dart default intentionally unchanged (see above). |
| BRAND-005 salts / keys / env vars | **Fixed (owner decision 2026-10-23)** | `URAL_*` support env vars → `PICPOS_*` for PicPos (`lib/core/config/support_env.dart`; const fork, alternate brand unchanged) and gone from `app.so`. Salts / peppers keep their exact bytes but are assembled at runtime (`lib/services/legacy_identifiers.dart`); secure-storage keys renamed to `picpos_*` with a read-old / copy / verify / delete-old migration (`lib/services/storage_key_migration.dart`). Design, per-literal table, tests: `docs/security/internal-identifier-migration.md` (§4). |
| BRAND-006 package `ural_erp` | **Not done (by instruction)** | `pubspec.yaml` description is PicPos now. |
| BRAND-007 installer branch | **Fixed for PicPos** | PicPos has its own script / info text; alternate files untouched. |
| BRAND-008 icons | **Fixed for PicPos** | `app_icon.ico` is the PicPos icon (guard compares hashes); `build_release.bat` restores it after its build. Alternate icon files kept. |
| BRAND-009 alternate code paths | **Left** | Required to stay working. |
| BRAND-010 non-shipped content | **Partial** | PG guide copy done; dead packages, `web_app/`, patches, docs untouched. |
| BRAND-011 data identifiers | **Already PicPos** | `picpos_*` DB, `PicPos_Backups`, `PicPos` data folder, logs. No importer written (owner: no customers). |
| BRAND-012 guards | **Fixed** | `test/structural/brand_artifact_guard_test.dart` + `tool/brand_artifact_scan.dart`; wired into `build_picpos.bat` and CI. |
| REL-001 CI SQLCipher / version | **Fixed (not executed)** | Version from pubspec only (no `--build-number=run_number`). |
| REL-004 Android signing | **Not done** | Out of this task's scope. |
| REL-007 info text | **Partial** | VC++ is bundled and PostgreSQL needs internet — corrected in `info-ar-picpos.txt`. `setup.iss` header comment about "EMBEDDED" PG left. |

## 3. Remaining occurrences (tracked source, word-start `ural` / `monexia` / «يورال»)

`git grep -P '(?<![A-Za-z])(?i:ural)|(?i:monexia)|يورال'`, excluding `docs/audits`. Almost all hits are `package:ural_erp/…` imports.

| Area | Hits (files) | Class | Action |
|---|---|---|---|
| `test/` | ~3,800 (1,237) | internal; `package:ural_erp` imports + tests of the alternate fork | none (package rename later) |
| `lib/` | ~1,340 (692) | internal; imports, comments, alternate-brand forks in `brand.dart`, `app_theme.dart`, `auth_providers.dart`, `login_screen.dart` footer, `setup_wizard_screen.dart`. The crypto salts / key names are no longer literals (migrated, §4) | allow-listed per file in the guard (new literals fail); the crypto/storage-literal allow-list is **empty** |
| `docs/` | ~570 (106) | not shipped | untouched |
| `patches-for-uralcash/` | 64 (17) | alternate-product patches, not shipped | untouched |
| `installer/` | 29 (3) | alternate-product installer (`setup.iss`, `info-ar-uralcash.txt`, `make_wizard_images.py`) + 2 alternate BMPs | untouched; **not** referenced by `setup_picpos.iss` |
| root | 18 (7) | README/ARCHITECTURE/PRODUCT prose, `.env.example`, `.gitignore`, `build_release.bat` (alternate build), `pubspec.yaml` `name:` | `build_release.bat` kept |
| `packages/`, `web_app/`, `supabase/`, `db/`, `scripts/`, `tools/`, `tool/` | ~75 | not shipped (dead packages, legacy web, SQL, helper scripts; `tools/postgresql_setup_guide.md` alternate original) | untouched (BRAND-010) |
| `windows/` | 2 (1) | `project(ural_erp …)` in CMake — package name | later rename |
| `server/` | 1 (1) | comment | untouched |
| `assets/` | 0 | — | `en.json`, `catalog_ar.json` cleaned |

Also not UralCash but flagged: `web/icons/*` are the stock Flutter icons (not PicPos art).

## 4. Internal secret / identifier literals — MIGRATED (owner decision 2026-10-23)

This section used to list ten literals that were kept because renaming them would have invalidated sessions, the invoice hash chain, the owner's encrypted DB, etc. The owner decided to migrate them without locking anyone out. Full design (rules a/b/c, per-literal table, risks): **`docs/security/internal-identifier-migration.md`**.

| Literal (old) | Now | Strategy |
|---|---|---|
| `UralCash-API-v1`, `UralCash-Session-v1`, `UralCash-ERP-Integrity-v1` (+ the legacy device-key pepper) | same bytes, assembled at runtime from masked numbers (`LegacyIdentifiers`) | (b) value unchanged; SHA-256 of each pinned in `test/unit/legacy_identifiers_test.dart` |
| `ural_db_fallback_enc_key` | `picpos_db_fallback_enc_key` | (a) migration in `DbKeyManager.legacyCandidates` and `SecurityService`; real-SQLCipher test with a DB whose key is pre-seeded under the old name |
| `ural_invoice_integrity_secret_v2` | `picpos_invoice_integrity_secret_v2` | (a) |
| `ural_api_session_hmac_v1`, `ural_table_bill_hmac_v1` (+ `_prev`) | `picpos_*` | (a) `ServerSecrets` |
| `ural_lan_install_secret_v1` | `picpos_lan_install_secret_v1` | (a) `LanPairingService` |
| `ural_api_token` | `picpos_api_token` | (a) `ServerProxy` |
| `ural_lan_device_name` | `picpos_lan_device_name` | (c) unused label |

`tool/brand_artifact_scan.dart`: `brandDeferredCryptoLiterals` is now **empty** (a guard test keeps it empty). Still excepted, exactly: the Dart package name `ural_erp` (later mechanical rename, 1,850 files) and ICU's `Uralsk` entry. Left alone: `api_key_dao.dart` generates API keys with an `ural_` prefix in a dead method (data-access code owned by another stream; tree-shaken, scan-clean).

## 5. Verification (see the task report for command output)

`build_picpos.bat` ends with `tool/brand_artifact_scan.dart` on `build\windows\x64\runner\Release`; after the B5 migration the scan finds, in the PicPos bundle, only: `package:ural_erp` (1,518 in `app.so`) and ICU's `Uralsk` time-zone entry in `icudtl.dat` (Kazakh city, third-party data, exact file-scoped exception). **No salt / storage-key literal remains.** Re-run 2026-10-23: `brand scan: build\windows\x64\runner\Release: CLEAN; documented exceptions: {data/app.so :: ural_erp: 1518, data/icudtl.dat :: Uralsk: 1}`, identical for `FlavorBuilds\PicPos`. (Before the migration the same scan listed ten extra literals.)

## Update: package rename (BRAND-006 closed)

The root Dart package was renamed `ural_erp` -> `picpos_erp` (pubspec, all `package:` imports in lib/ and test/, generated `database.g.dart` URIs, CMake `project()`, tools/docs). `brandPackageNameExceptions` in `tool/brand_artifact_scan.dart` is now empty; the only remaining documented exception is ICU's `Uralsk` entry in `data/icudtl.dat`. The older rows above describe the state before the rename. Historical `.patch`/`.diff` files under `docs/superpowers/backports` and `patches-for-uralcash` are archived diffs and were left byte-identical.
