# Axis C: Findings (product identity, UX, architecture, distribution)

Scope, version and method: see [PROJECT_BASELINE-C.md](<PROJECT_BASELINE-C.md>) and [TEST-EVIDENCE-C.md](<TEST-EVIDENCE-C.md>).
All findings are bound to `feat/tables-reservations-permissions` at `d69be1eafc7d82b924723dfdbb53960b7e33acdb` and to the build in `FlavorBuilds\PicPos` (written 2026-10-23 03:14, `PicPos.exe` FileVersion `3.9.2+277`).

## Conventions

- **Type:** Defect (confirmed) · Suspicion (needs verification) · Requirement gap · Improvement.
- **Severity** is the impact if it happens: Critical / High / Medium / Low / Info. **Priority** is the order of remediation: P0 (before any release), P1 (before wide rollout), P2 (next cycle), P3 (later).
- **Confidence:** High means verified on the artifact or by reading the exact code path. Medium means code-read with one unverified link. Low means an inference.
- **Brand class** (BRAND section only): **(a)** visible to a PicPos user or shipped inside a PicPos artifact; **(b)** an internal identifier not shown in the UI (it may still be compiled into the binary); **(c)** a UralCash-only code path or file that exists for the other product.
- **Release-blocking** means it blocks a general PicPos release. Where it blocks only one channel (for example the Android APKs), the finding says so.

## Summary table

| ID | Title | Type | Sev | Pri | Conf | Blocking |
|---|---|---|---|---|---|---|
| BRAND-001 | UralCash company logo shipped inside every PicPos build and installer | Defect | High | P0 | High | **Yes** (owner requirement) |
| BRAND-002 | Shipped i18n catalogs contain "Ural Technology", "URAL-ERP", "Ural Cash"; `catalog_ar.json` is shipped but unused | Defect | High | P0 | High | **Yes** |
| BRAND-003 | CI release job publishes a UralCash-branded Windows build named "PicPos-ERP" | Defect | Critical | P0 | High | **Yes** (if tags are pushed) |
| BRAND-004 | Every brand default is UralCash (Dart, CMake, Runner.rc, main.cpp) | Defect | High | P0 | High | **Yes** |
| BRAND-005 | UralCash salts, keys and env-var names are compiled into the PicPos binary | Defect | Medium | P1 | High | No |
| BRAND-006 | Dart package `ural_erp` plus description "UralCash ERP" | Improvement | Medium | P2 | High | No |
| BRAND-007 | UralCash installer branch, art and build script are kept in the PicPos tree | Defect | Medium | P1 | High | No |
| BRAND-008 | UralCash icons in `windows/runner/resources` and at the repo root | Defect | Medium | P1 | High | No |
| BRAND-009 | UralCash-only code paths in `lib/` (theme, nav, vendor strip, wizard title, log prefix, legacy screens) | Defect | Medium | P1 | High | No |
| BRAND-010 | Non-shipped repo content still UralCash (dead packages, `web_app/`, patches, docs, scripts, SQL) | Improvement | Low | P2 | High | No |
| BRAND-011 | PicPos runtime data identifiers are PicPos-only; pre-split installs not covered | Info / open question | Info | P1 | Medium | No |
| BRAND-012 | Brand guard tests do not cover the shipped artifact and CI never runs the PicPos guard | Requirement gap | High | P0 | High | **Yes** (needed to close BRAND-001/002) |
| UX-001 | Setup wizard offers SAR/AED/KWD/USD, but the engine silently turns them into JOD, and the choice is final | Defect | High | P0 | High | **Yes** |
| UX-002 | Currency literals `ج.م` / `د.أ` / `JOD` hardcoded in 15+ screens and dialogs | Defect | High | P0/P1 | High | **Yes for EGP installs** |
| UX-003 | `NumberUtils.formatAmount` freezes the currency symbol and decimals on first use | Defect | Medium | P1 | High | No |
| UX-004 | Irreversible currency is preselected (EGP plus 14%) instead of being chosen explicitly | Improvement | Medium | P1 | High | No |
| UX-005 | Company name entered in the wizard not persisted (G2 observation) | Suspicion | Medium | P1 | Low | No (verify) |
| UX-006 | English "Dashboard" label in the Arabic UI (sidebar, tab, breadcrumb, search) | Defect | Low | P2 | High | No |
| UX-007 | Overlapping sidebar destinations and a duplicated HR section header | Improvement | Medium | P2 | Medium | No |
| UX-008 | Destructive "clear PLU" has no confirmation | Defect | Low | P2 | Medium | No |
| UX-009 | Hardcoded `TextDirection.rtl` in dialogs breaks the English layout | Defect | Low | P2 | Medium | No |
| UX-010 | First-run redesign plan: conflicts with owner decisions and the code | Requirement gap | Medium | P0 (plan fix) | High | No (plan doc) |
| UX-011 | Warehouse-app plan: prerequisites missing | Requirement gap | Low | P1 | Medium | No |
| ARCH-001 | Swallowed exceptions in money and sync paths (439 `catch (_)`, 209 empty catches) | Defect | Medium | P1 | High | No |
| ARCH-002 | Tax, totals, rounding and WAC rules implemented in several places | Defect risk | Medium | P2 | Medium | No |
| ARCH-003 | Static caches not invalidated by sync or settings change | Defect risk | Medium | P2 | Medium | No |
| ARCH-004 | Analyzer infos at HEAD (async-gap BuildContext); CI analyze probably red | Defect / Suspicion | Low | P1 | Medium | No |
| ARCH-005 | A large share of tests are source-text scans, not behaviour | Improvement | Medium | P2 | Medium | No |
| ARCH-006 | CI does not run Android builds, the installer, the PicPos brand guard, analyze of `test/`, or 9 packages | Requirement gap | High | P1 | High | No (but see BRAND-003) |
| ARCH-007 | God-file ratchet is in place; it does not cover mobile or server | Info | Low | P3 | High | No |
| REL-001 | CI release artifact skips SQLCipher enforcement and signing, and uses the wrong build number | Defect | High | P0 | High | **Yes** (if tags are pushed) |
| REL-002 | Installer, exe and DLLs unsigned, so SmartScreen shows "unknown publisher" | Requirement gap | High | P1 | High | Blocking for public release; OK for pilot |
| REL-003 | No updater; upgrade backup is non-blocking and can be rotated away; no downgrade guard verified | Requirement gap | Medium | P1 | Medium | No |
| REL-004 | Android Van always release-signs with the debug key; POS falls back to debug | Defect | High | P0 (for APKs) | High | **Yes for APK distribution** |
| REL-005 | Trial watermark and activation cache depend on whether Settings was opened | Defect | High | P0 | Medium | **Yes until verified** |
| REL-006 | Activation mechanism: description and weaknesses (for the setup redesign) | Info / Improvement | Low | P2 | High | No |
| REL-007 | Installer info text stale (VC++ "downloaded"); PostgreSQL downloaded at install time | Defect | Low | P2 | High | No |
| REL-008 | Version identity inconsistent across apps, README and AppConfig | Defect | Low | P2 | High | No |
| REL-009 | Activation private key sits in the working tree (untracked, ignored) | Improvement | Low | P1 | High | No |
| DEP-001 | `sqlcipher_flutter_libs` is EOL upstream (`0.7.0+eol`) | Requirement gap | Medium | P1 | High | No |
| DEP-002 | Major versions behind; discontinued transitives | Improvement | Low | P2 | High | No |
| DEP-003 | Dependency licences: no GPL/LGPL/AGPL found in the root lockfile | Info | Info | — | Medium | No |
| DEP-004 | Unused dependencies and dead code | Improvement | Low | P3 | High | No |

**Counts by severity:** Critical 1 · High 11 · Medium 16 · Low 13 · Info 2 (43 findings: BRAND 12, UX 11, ARCH 7, REL 9, DEP 4).
Release-blocking for the general Windows release: BRAND-001, BRAND-002, BRAND-003, BRAND-004, BRAND-012, UX-001, UX-002 (EGP), REL-001, REL-005. Blocking per channel: REL-004 (APKs) and REL-002 (public, unsigned).

---

## BRAND: exhaustive UralCash inventory

### Method and scope of the inventory
- `git grep -I -i` on every tracked file for `uralcash`, `ural_erp`, `monexia`, `avalon`, `nexplay`, `legal_erp`, `يورال`, `uraljo`, and the word-boundary regex `(?<![a-z])ural(?!_erp)`. The plain `ural` term matches "struct**ural**", "nat**ural**" and "pl**ural**", so those false positives were excluded.
  - `uralcash`: 359 files / 1,064 hits.
  - `ural_erp`: 1,875 files / 4,643 hits (almost all `package:ural_erp/` imports).
  - `monexia`: 19 / 38.
  - `avalon`: 12 / 22 (docs, `scripts/gate.sh`, one test).
  - `يورال`: 6.
  - `uraljo`: 5.
  - word `ural`: 402 files.
  - `nexplay` and `legal_erp`: 0.
- Paths with brand names (`git ls-files`) and binary files were checked as well.
- **Shipped artifact scan.** Every file of `FlavorBuilds\PicPos` (65 files, 82.4 MB) was decoded as Latin-1 and as UTF-16LE and searched for brand terms. Results are in [TEST-EVIDENCE-C.md](<TEST-EVIDENCE-C.md>) (T-C-03).
- Image assets were opened and judged visually.

**Distribution of word-boundary `ural` hits by area:** `lib` 180 · `docs` 81 · `test` 73 · `patches-for-uralcash` 15 · `packages` 13 · `web_app` 8 · `scripts` 7 · `windows` 3 · `installer` 3 · `supabase` 3 · `db` 3 · `assets` 2 · plus root files: README, ARCHITECTURE, PRODUCT, `.env.example`, `.gitignore`, `pubspec.yaml`, the three `build_*.bat`, `tool/`, `tools/`.
**Mobile apps (`mobile/`, `mobile_admin/`, `mobile_pos/`) and `server/`:** zero brand hits apart from one code comment (`server/lib/src/db/migrations.dart:3`) and `structural_test.dart` false positives. App ids `com.picpos.picpos_van`, `com.picpos.admin`, `com.picpos.pos`; labels "PicPos Van", "PicPos إدارة", "PicPos كاشير". The launcher icons show the PicPos logo (viewed `mobile_pos/assets/icon/legacy.png`). **PASS** for brand.

---

### BRAND-001: UralCash company logo shipped inside every PicPos build and installer
- **Type / axis:** Defect · Brand. **Severity** High · **Priority** P0 · **Confidence** High (verified on the artifact) · **Class (a)**.
- **Location:**
  - [pubspec.yaml:139-141](<../../../../pubspec.yaml#L139-L141>) declares `- logo.PNG` for all brands.
  - [brand.dart:68-69](<../../../../lib/core/config/brand.dart#L68-L69>).
  - Shipped copy: `FlavorBuilds\PicPos\data\flutter_assets\logo.PNG` (141,097 bytes). Its hash is identical to the repo-root [logo.PNG](<../../../../logo.PNG>).
  - The installer packs `{#ReleaseDir}\*` ([setup.iss:246](<../../../../installer/setup.iss#L246>)), so it is inferred to be in `PicPos-Setup-3.9.2.277.exe` (the installer is compressed and was not unpacked).
- **Evidence:** visual inspection. The image is the "شركة جبال الأورال لتكنولوجيا المعلومات / Ural Information Technology" logo (teal mountain). The PicPos UI does not display it, because `Brand.logoAsset` is a const that resolves to `assets/brand/picpos/logo.png`. It is still present in `C:\Program Files\PicPos\data\flutter_assets\`.
- **Expected:** no other company's artwork in a PicPos artifact. **Actual:** shipped.
- **Impact:** brand and legal exposure (another company's mark distributed inside the product). It also adds 141 KB.
- **Root cause:** Flutter assets are not brand-conditional. The comment in pubspec accepts "every brand's assets ship in every build".
- **Remediation:** UralCash work is halted (setup.iss:39-41), so delete `logo.PNG` from pubspec and from the repo, together with the `Brand.logoAsset` UralCash branch. The alternative, if UralCash must stay buildable, is to move UralCash to its own branch or repo. Do not try conditional assets.
- **Effort:** S (under 1 h), plus deleting the UralCash branch (BRAND-009).
- **Acceptance:** the artifact scan (BRAND-012) finds no file whose SHA-256 equals the UralCash logo or icon, and `flutter_assets` contains only `assets/brand/picpos/*` brand images.
- **Release-blocking:** yes, because the owner's requirement is explicit ("no images… nothing").

### BRAND-002: Shipped i18n catalogs contain UralCash strings; `catalog_ar.json` is shipped but unused
- **Type:** Defect · **Severity** High · **Priority** P0 · **Confidence** High (artifact scan) · **Class (a)**.
- **Location:**
  - [en.json:4340](<../../../../assets/i18n/en.json#L4340>) `"تطوير: Ural Technology": "Developed by: Ural Technology"`, [en.json:8743](<../../../../assets/i18n/en.json#L8743>) `"Welcome to URAL-ERP"`, [en.json:9874](<../../../../assets/i18n/en.json#L9874>) `"يورال كاش": "Ural Cash"`.
  - [catalog_ar.json:4048, 8245, 9325](<../../../../assets/i18n/catalog_ar.json#L4048>).
  - Both are declared at [pubspec.yaml:137-138](<../../../../pubspec.yaml#L137-L138>).
  - Shipped: `data\flutter_assets\assets\i18n\en.json` (hits: "ural technology" 2, "ural-erp" 2, "ural cash" 1) and `catalog_ar.json` ("ural technology" 1, "ural-erp" 1).
- **Additional fact:** no file under `lib/` references `catalog_ar` (grep, 0 hits). It is a 1.1 MB map from each Arabic key to the source `file:line` where it is used, so the product ships a map of its own source tree.
- **Impact:**
  - Brand strings are readable in the install folder. They are not rendered in PicPos, because the source widgets are in const-false branches; T-C-03 confirms those literals are absent from `app.so`.
  - `catalog_ar.json` leaks the internal code layout and costs 1.1 MB.
- **Root cause:** the catalogs are generated from all source, including UralCash-only branches, and no step filters brand keys.
- **Remediation:**
  1. After BRAND-009 removes the UralCash branches, regenerate `en.json` with `tool/i18n/*` and delete the three keys.
  2. Remove `catalog_ar.json` from pubspec assets. Keep it as a dev-only file if `i18n_coverage_test` needs it; verify first which tests read it.
- **Acceptance:** the artifact scan finds 0 forbidden terms in `flutter_assets/**`, and `catalog_ar.json` is absent from the build output.
- **Release-blocking:** yes (owner requirement).

### BRAND-003: CI release job publishes a UralCash-branded Windows build named "PicPos-ERP"
- **Type:** Defect · **Severity** Critical · **Priority** P0 · **Confidence** High (workflow read; not executed) · **Class (a)**.
- **Location:**
  - [ci.yml:641-645](<../../../../.github/workflows/ci.yml#L641-L645>): `flutter build windows --release --build-name=… --build-number=${{ github.run_number }}`, with no `--dart-define=APP_BRAND`.
  - There are 0 occurrences of `APP_BRAND`/`BRAND_` in `.github/workflows/*`.
  - [ci.yml:648-698](<../../../../.github/workflows/ci.yml#L648-L698>) zips it as `PicPos-ERP-<semver>+<sha>-windows.zip` and attaches it to a public GitHub Release on `v*.*.*` tags.
- **What that build is:**
  - `Brand.id` defaults to `'uralcash'` ([brand.dart:37-40](<../../../../lib/core/config/brand.dart#L37-L40>)).
  - CMake falls back to `BINARY_NAME "UralCash"`, `BRAND_PRODUCT_NAME "UralCash ERP"`, `BRAND_COMPANY_NAME "Monexia"` ([windows/CMakeLists.txt:21-36](<../../../../windows/CMakeLists.txt#L21-L36>)).
  - The resulting app is `UralCash.exe` with the teal UralCash theme, `uralcash_unified.db`, `%APPDATA%\Monexia\UralCash ERP`, `UralCash_Backups`, the Ural vendor strip on the login screen, and the UralCash icon if `app_icon.ico` was not overwritten.
- **Impact:** a tag push ships a wrong-brand, separately-namespaced product. A PicPos customer who "upgrades" from that zip gets an empty database in a different folder (data looks lost).
- **Remediation:** make CI call the same entry point as the local release (`build_picpos.bat`, or a shared PowerShell script). Set `BRAND_*` env and `--dart-define=APP_BRAND=picpos`, then run the artifact brand scan (BRAND-012) and the SQLCipher check (REL-001) before upload. Until then, disable the `release` job.
- **Acceptance:**
  - A CI run on a test tag produces an artifact containing `PicPos.exe` with CompanyName `PicPos`.
  - The brand scan exits 0.
  - `sqlite3.dll` contains the `sqlcipher` marker.
- **Release-blocking:** yes for any tag-driven release.

### BRAND-004: Every brand default is UralCash
- **Type:** Defect · **Severity** High · **Priority** P0 · **Confidence** High · **Class (a)** whenever a build omits flags, otherwise **(c)**.
- **Location:**
  - [brand.dart:37-40](<../../../../lib/core/config/brand.dart#L37-L40>) `defaultValue: 'uralcash'`.
  - [windows/CMakeLists.txt:14-36](<../../../../windows/CMakeLists.txt#L14-L36>).
  - [Runner.rc:79-87](<../../../../windows/runner/Runner.rc#L79-L87>) (`"UralCash"`, `"UralCash ERP"`, `"Monexia"`).
  - [main.cpp:15](<../../../../windows/runner/main.cpp#L15>) `L"UralCash"`.
  - [README.md:95](<../../../../README.md#L95>) documents the trap.
- **Impact:** `flutter run`, IDE runs, CI (BRAND-003) and any forgotten flag produce UralCash. The QA rounds avoided this only by using `build_picpos.bat`.
- **Remediation:**
  - Flip every default to PicPos, or better, delete the UralCash branch so there is no second value.
  - Keep `Brand.assertKnownBrand()`.
  - Make CMake `FATAL_ERROR` when `BRAND_BINARY_NAME` is unset, or default it to `PicPos`.
- **Acceptance:** `flutter build windows --release` with no defines and no env vars yields `PicPos.exe`, with CompanyName `PicPos` and title `PicPos`.
- **Release-blocking:** yes, because it is the root cause of BRAND-003.

### BRAND-005: UralCash salts, keys and env-var names compiled into the PicPos binary
- **Type:** Defect · **Severity** Medium · **Priority** P1 · **Confidence** High (T-C-03 strings in `data\app.so`) · **Class (b)**: not in the UI, but readable with `strings`.
- **Strings found in the shipped `app.so`:**
  - `UralCash-ERP-Integrity-v1` ([invoice_integrity_service.dart:10](<../../../../lib/services/invoice_integrity_service.dart#L10>)) and `UralCash-API-v1` ([api_auth_middleware.dart:146](<../../../../lib/services/api/api_auth_middleware.dart#L146>)).
  - Secure-storage keys: `ural_invoice_integrity_secret_v2`, `ural_db_fallback_enc_key` ([db_key_names.dart:15](<../../../../lib/services/db_key_names.dart#L15>)), `ural_table_bill_hmac_v1`, `ural_api_session_hmac_v1` ([server_secrets.dart:37-38](<../../../../lib/services/api/server_secrets.dart#L37-L38>)), `ural_api_token` ([server_proxy.dart:36](<../../../../lib/services/server_proxy.dart#L36>)), `ural_lan_install_secret_v1` ([lan_pairing_service.dart:15](<../../../../lib/services/api/lan_pairing_service.dart#L15>)).
  - Support env vars: `URAL_RESET_ADMIN_PASSWORD`, `URAL_PURGE_USERS`, `URAL_RESET_SETUP_WIZARD` ([main.dart:738-821](<../../../../lib/main.dart#L738>)) and `URAL_RESET_DEV_PASSWORD` ([developer_auth_service.dart:160](<../../../../lib/services/developer_auth_service.dart#L160>)).
  - 1,503 `package:ural_erp/…` library URIs (BRAND-006).
- **Related, not found as a literal:**
  - `UralCash-Session-v1` ([api_session_token.dart:32](<../../../../lib/services/api/api_session_token.dart#L32>)).
  - The pepper `UralCash_Security_Pepper_v2`, built from char codes ([legacy_device_seed.dart:37-42](<../../../../lib/services/legacy_device_seed.dart#L37-L42>)).
  - Dead API-key prefix `'ural_'` ([api_key_dao.dart:99](<../../../../lib/data/database/daos/api_key_dao.dart#L99>)); `createApiKey` has no callers.
- **Impact:**
  - Brand text is visible to anyone inspecting the binary, and package URIs appear in crash and stack traces that end up in customer log files.
  - **Changing the values breaks data:**
    - The salts invalidate every LAN session and token ([brand.dart:22-25](<../../../../lib/core/config/brand.dart#L22-L25>)).
    - The pepper derives the legacy DB fallback key, so changing it makes an existing encrypted DB unopenable.
    - The integrity secret invalidates the invoice hash chain.
- **Remediation (keep values, remove literals):**
  - Store each salt or pepper as the precomputed byte array of the *same* value (or its SHA-256 where only a digest is used). This keeps compatibility and removes the readable word.
  - Rename secure-storage keys with a read-old/write-new/delete-old migration in `SecureStorageService`.
  - Accept `PICPOS_*` env vars, keeping `URAL_*` as deprecated aliases for one release.
  - Delete the dead `_generateApiKey` or change the prefix to `pp_`.
- **Risks:** any mistake in the byte-array transcription is a data-loss bug. Add unit tests asserting that the bytes equal the old literal before the literal is deleted.
- **Acceptance:** the artifact scan finds 0 occurrences of `uralcash` or `ural_` (except `package:ural_erp/` until BRAND-006), and the existing session, integrity and DB-key tests stay green.
- **Release-blocking:** no (not user-visible), but it is required for a literal reading of the owner requirement.

### BRAND-006: Dart package `ural_erp` plus description "UralCash ERP"
- **Type:** Improvement · **Severity** Medium · **Priority** P2 · **Confidence** High · **Class (b)**.
- **Location:**
  - [pubspec.yaml:1-2](<../../../../pubspec.yaml#L1-L2>) (`name: ural_erp`, `description: "UralCash ERP - …"`).
  - `windows/CMakeLists.txt` `project(ural_erp …)`.
  - 603 `lib/` files and 1,219 `test/` files import `package:ural_erp/`, plus `tool/`, `scripts/` and `server/` comments.
- **Feasibility analysis:**
  - No runtime string keyed on the package name was found (`'ural_erp'` or `"ural_erp"` literal: 0 hits).
  - Windows data paths come from the exe version resource (CompanyName/ProductName), not the package name.
  - No `package: 'ural_erp'` asset lookups.
  - So user data risk is low. The cost is about 1,850 mechanical file edits, regenerating `database.g.dart` and `l10n`, and merge conflicts with every open branch and the `patches-for-uralcash` diffs.
- **Recommendation:**
  - (1) Now: change the `description` to PicPos (zero risk).
  - (2) Rename to `picpos_erp` in a single dedicated mechanical commit once the feature branches are merged, gated by the full test suite.
  - (3) Alternatively keep `ural_erp` as internal-only and build with `--obfuscate --split-debug-info`. *Not verified* whether obfuscation also removes library URIs from the AOT snapshot; it must be measured with the artifact scan before relying on it.
- **Acceptance:** `pubspec.yaml` contains no UralCash text, and after a rename the scan finds 0 `ural_erp`.
- **Release-blocking:** no.

### BRAND-007: UralCash installer branch, art and build script kept in the PicPos tree
- **Type:** Defect · **Severity** Medium · **Priority** P1 · **Confidence** High · **Class (c)**: not in the PicPos installer (`/DBrandId=picpos`).
- **Location:**
  - [setup.iss:11-12, 39-66, 91, 128](<../../../../installer/setup.iss#L54-L66>): AppName "UralCash ERP", Publisher "Monexia", URL `https://uralcash.app`, `UralCash.exe`.
  - [info-ar-uralcash.txt](<../../../../installer/info-ar-uralcash.txt>), which also has a stale claim about installing a certificate.
  - `installer/assets/wizard-{large,small}-uralcash.bmp`.
  - [make_wizard_images.py:59-64](<../../../../installer/make_wizard_images.py#L59-L64>).
  - [tool/gen_installer_art.dart:78-86](<../../../../tool/gen_installer_art.dart#L78-L86>).
  - [build_release.bat:27-30](<../../../../build_release.bat#L27-L30>) (`Monexia`, `APP_BRAND=uralcash`; no SQLCipher check).
  - Comments and guards in [build_picpos.bat:11,48,88-90](<../../../../build_picpos.bat#L88-L90>) and [build_installer_picpos.bat:47-48](<../../../../build_installer_picpos.bat#L47-L48>).
- **Impact:** a one-flag mistake (`/DBrandId=uralcash`, or running `build_release.bat`) produces a UralCash product from the PicPos repo. Mixed maintenance burden.
- **Remediation:**
  - Delete the UralCash `#if` block, the art, the info file, `make_wizard_images.py` and `build_release.bat`.
  - Make `setup.iss` PicPos-only, without the BrandId switch.
  - Keep the "foreign exe present" guard as a generic check: exactly one `*.exe`, named `PicPos.exe`.
- **Acceptance:** `git grep -i uralcash -- installer build_*.bat tool` returns 0, and `ISCC installer\setup.iss` builds PicPos without a define.

### BRAND-008: UralCash icons in `windows/runner/resources` and at the repo root
- **Type:** Defect · **Severity** Medium · **Priority** P1 · **Confidence** High (hashes) · **Class (c)**, and (a) if `app_icon.ico` is not overwritten.
- **Location:**
  - `windows/runner/resources/app_icon_uralcash.ico` and the root [icon.ico](<../../../../icon.ico>): identical hash `A1B1B26B2ED1…`.
  - `app_icon.ico` currently equals `app_icon_picpos.ico` (`E6A1F0FFCF72…`), only because `build_picpos.bat` copies it in. [build_release.bat:20](<../../../../build_release.bat#L20>) notes that a UralCash build restores the UralCash icon into the same file.
- **Impact:** after any UralCash build, the next build that skips the copy step (for example CI, BRAND-003) embeds the UralCash icon into the exe.
- **Remediation:** delete `app_icon_uralcash.ico` and root `icon.ico`, and make `app_icon.ico` the PicPos icon committed as-is (no copy step).
- **Acceptance:** no `.ico` in the repo whose hash equals the UralCash icon, and `Runner.rc` references only the PicPos icon.

### BRAND-009: UralCash-only code paths in `lib/`
- **Type:** Defect · **Severity** Medium · **Priority** P1 · **Confidence** High · **Class (c)**.
- **Inventory (non-comment literals):**
  - [brand.dart:42-153](<../../../../lib/core/config/brand.dart#L42-L153>): `isUralCash` (0 uses in `lib/`), `name`/`nameAr` (`'UralCash'`, `tr('يورال كاش')`), `dbPrefix 'uralcash'`, `dataFolderName`, `backupFolderName 'UralCash_Backups'`, `documentCompanyFallback 'UralCash Market'`, `pgIdentifier`, and the vendor block (`Ural Technology`, a phone number, `info@uraljo.com`, `www.uraljo.com`, wa.me, instagram/facebook `uraltechnology`; PII-like contact data, so it is not reproduced in full here).
  - [app_theme.dart:27-35, 278](<../../../../lib/core/theme/app_theme.dart#L27-L35>): `_uralCashLightTheme` / `_uralCashDarkTheme`.
  - [auth_providers.dart:716-753](<../../../../lib/data/providers/auth_providers.dart#L716-L753>): `_uralCashFinanceNavLayout`.
  - [login_screen.dart:904-971](<../../../../lib/presentation/screens/login_screen.dart#L904-L971>): vendor footer literals (`tr('تطوير: Ural Technology')`, `www.uraljo.com`, `'© Ural Technology …'`), gated by `Brand.hasVendorInfo`.
  - [setup_wizard_screen.dart:444-446](<../../../../lib/presentation/screens/setup_wizard_screen.dart#L444-L446>): `tr('مرحباً بك في URAL-ERP')`.
  - [log_writer_io.dart:36](<../../../../lib/services/log_writer_io.dart#L36>): `'monexia'` log prefix.
  - [app_flavor.dart](<../../../../lib/core/config/app_flavor.dart>): flavor labels built from `Brand.nameAr`.
  - About 38 `Brand.isPicPos ? XPicpos : X` forks in [app_main_screen_catalog.dart](<../../../../lib/app_main_screen_catalog.dart>), with 26 legacy/PicPos screen pairs (fixed_assets, activity_log, categories, offers, manufacturing, landed_cost, products, sales/purchase returns, tables, users, dashboard, analytics, settings, COA, GL, cost centers, journal, treasury, cycle count, inventory bonds, stock transfer, party statement, shift close, report builder, reports).
  - Comments mentioning UralCash or Monexia: about 150 `lib/` files (class b).
- **Evidence the PicPos binary already drops them:** T-C-03 found no `Ural Technology`, `uraljo`, `URAL-ERP` or `Monexia` strings in `app.so`, so the const-false branches are tree-shaken. Their text survives only through the i18n catalogs (BRAND-002).
- **Impact:**
  - Every `Brand.*` getter is a fork that tests must cover twice.
  - Legacy screens stay compiled into tests and keep the duplicated rules in ARCH-002 alive.
  - The 'UralCash' default is a standing risk (BRAND-004).
- **Remediation (phased):**
  1. Make `Brand` a PicPos-only constants class (keep the API so call sites compile), and delete `isUralCash`, the vendor block, the UralCash themes, nav layout and wizard title.
  2. Delete the generic legacy screens that only the false branch reaches. One pair per PR, guarded by `screenconfig_builds_the_picpos_fork_test`.
  3. Rewrite comments.
- **Do not change the runtime identifiers PicPos already uses** (`picpos_*` DB, `PicPos_Backups`, `picpos` PG); see BRAND-011.
- **Acceptance:** `git grep -i -E "uralcash|monexia|uraljo|ural technology|يورال" -- lib` returns 0 (comments included), and the full test suite is green.

### BRAND-010: Non-shipped repo content still UralCash
- **Type:** Improvement · **Severity** Low · **Priority** P2 · **Confidence** High · **Class (b)/(c)**. None of it is packed by the installer ([setup.iss:246](<../../../../installer/setup.iss#L246>) packs only the Release dir).
- **Dead packages:** `packages/{core,accounting,inventory,pos,treasury,shared_widgets}` are described "…for UralCash" and carry a "UralCash Teal Palette" ([packages/core/lib/theme/app_colors.dart:3-45](<../../../../packages/core/lib/theme/app_colors.dart#L3>)). There are 0 imports from `lib/`, `mobile*` and `server/`.
- **`web_app/`:** `cashier_market_web`, "UralCash Web", "© 2024 Ural Solutions" ([web_app/lib/presentation/screens/settings_screen.dart:83-89](<../../../../web_app/lib/presentation/screens/settings_screen.dart#L83-L89>)), Supabase seed `storeName 'UralCash POS'`, and a copy of the UralCash logo (`web_app/assets/logo.PNG`, the same 141,097 bytes). CI builds the web from root `lib/main_web_entry.dart`, not from `web_app/`.
- **Patches and backports:** `patches-for-uralcash/` (15 files) and `docs/superpowers/backports/ural-*.patch` (26 files).
- **Docs:** 81 `docs/` files, plus README, ARCHITECTURE and PRODUCT describing the dual brand.
- **Scripts:** [scripts/build_user_guide.py:4-6,452,643](<../../../../scripts/build_user_guide.py#L452>) ("UralCash user-guide", teal identity), `scripts/reset_system_data.sql`, `scripts/reset_user_password.dart`, `scripts/remediation_*.sql` headers, and `scripts/gate.sh:504` (mentions an "Avalon" database on a shared server).
- **`tools/postgresql_setup_guide.md`:** a customer-facing setup guide that tells users to create a PG db and user named `uralcash` and to open "URAL-ERP". This contradicts `Brand.pgIdentifier = 'picpos'`.
- **SQL headers and config:** `supabase/migrations/0001,0002` ("URAL-ERP"), `db/legacy_migrations/*` headers, [.env.example:2](<../../../../.env.example#L2>), and [.gitignore:187](<../../../../.gitignore#L187>) `tools/UralCash_License_Tool.*`.
- **Remediation:**
  - Delete the dead packages and `web_app/`, or archive them in a separate repository.
  - Move `patches-for-uralcash/` and `backports/ural-*` to the UralCash repository.
  - Rewrite `tools/postgresql_setup_guide.md` for PicPos (`picpos` db and user). This one is **P1**, because the guide is handed to customers.
  - Rebrand the user-guide builder.
- **Acceptance:** `git grep -i uralcash` returns only an explicitly allow-listed `docs/archive/` folder, or nothing.

### BRAND-011: PicPos runtime data identifiers are PicPos-only; pre-split installs not covered
- **Type:** Info / open question · **Severity** Info · **Priority** P1 (answer needed) · **Confidence** Medium.
- **PASS (verified on the artifact or in code):**
  - Exe version resource: CompanyName, ProductName and FileDescription `PicPos`, `OriginalFilename PicPos.exe`, `© 2026 PicPos`.
  - Windows app-support dir `%APPDATA%\PicPos\PicPos` (observed on this machine).
  - DB `Documents\picpos_<flavor>.db`, backups `PicPos_Backups` / `picpos_backup_*`, logs `logs\picpos_<date>.log`, login log `picpos_login_log*.txt` ([diagnostic_logger.dart:26](<../../../../lib/core/logging/diagnostic_logger.dart#L26>)), PG db and user `picpos`.
  - Installer AppId `{6700CCE0-…}`, distinct from UralCash's.
  - No `[Registry]` section in the installer.
- **Open question:** the brand split landed on 2026-07-26 (commit `186f78ab`). This dev machine also has `%APPDATA%\Monexia\UralCash ERP` (dated Aug 2026) and `%APPDATA%\Ural Information Technology\Ural-Medixa` (another product). No code migrates `uralcash_*.db`, `Monexia\…` secure storage or `UralCash_Backups` into PicPos names.
  - **Owner question:** was any PicPos customer installed before 2026-07-26, or from a UralCash-default build?
  - If yes, those installs need a one-time importer. The importer must not rename silently: detect, show, back up and copy.
  - If no, nothing is needed.
- **Acceptance:** an owner answer is recorded. If an importer is needed, a test seeds `uralcash_unified.db` and asserts the PicPos first run offers the import.

### BRAND-012: Brand guard tests do not cover the shipped artifact; CI never runs the PicPos guard
- **Type:** Requirement gap · **Severity** High · **Priority** P0 · **Confidence** High.
- **What the current guards prove:**
  - [test/unit/brand_isolation_test.dart](<../../../../test/unit/brand_isolation_test.dart>) runs with the **default (uralcash)** brand. It asserts `Brand` constants, flavor names, DB file names and uniqueness, `designLanguage == 'uralcash'`, nav fencing and `navItemVisibleForBrand`.
  - [test/unit/brand_picpos_test.dart](<../../../../test/unit/brand_picpos_test.dart>) is skipped unless `--dart-define=APP_BRAND=picpos` (:33, :275). It asserts PicPos `Brand` values, `AppColors` (no teal), `picpos_` DB names and lite-profile nav. It is run by `build_picpos.bat:51`, and QA run S4 passed 13/13. CI never passes `APP_BRAND`, so it is **skipped in CI**.
  - `build_picpos.bat:88-90` and `build_installer_picpos.bat:47-48` only check that `UralCash.exe` is absent.
  - Several structural tests assert `src.contains('Brand.isPicPos')`, which is source text only.
- **What nothing proves:**
  - The content of the build output: assets (BRAND-001/002), `app.so` strings (BRAND-005) and exe resources.
  - Installer text.
  - PDF and receipt output.
  - Words other than the exact `UralCash.exe` file name.
  - The comment in `brand.dart:134-138` records that an earlier `uralcash`-only grep missed "Ural Technology / uraljo.com"; the same class of miss happened again with `logo.PNG` and `en.json`.
- **Remediation:** add `tool/check_brand_artifact.ps1` (reusable in CI) and call it at the end of `build_picpos.bat`, before ISCC, and in CI `build-windows`. It should:
  1. Hash-deny-list the known UralCash images (`logo.PNG`, `icon.ico`, the wizard BMPs).
  2. Byte-scan every file under the Release dir, as Latin-1 and UTF-16LE, for `(?i)uralcash|ural[ _-]?(cash|erp|technology|information)|monexia|uraljo|يورال|الأورال`. Allow-list `package:ural_erp/` only until BRAND-006.
  3. Assert the exe VersionInfo fields equal `PicPos`.
  4. Fail with the file name and offset.
  - Also extract the installer with `innounp` or install it silently into a temp VM and rescan, if feasible.
  - Run `brand_picpos_test` in CI with `--dart-define=APP_BRAND=picpos`.
- **Acceptance:** the scan fails on today's artifact (it must report `logo.PNG` and `en.json`) and passes after BRAND-001/002/005, and CI shows the brand job green.

### BRAND remediation plan (consolidated)

| Step | What | Findings | Risk | Acceptance check |
|---|---|---|---|---|
| B0 (P0, ~0.5 d) | Add `tool/check_brand_artifact.ps1`, wire it into `build_picpos.bat` and CI, and run `brand_picpos_test` in CI. | BRAND-012 | None. It must fail on today's build (proves the guard works). | Fails now on `logo.PNG` and `en.json`. |
| B1 (P0, ~0.5 d) | Remove `logo.PNG` and `catalog_ar.json` from pubspec assets; regenerate `en.json` without the three UralCash keys. | BRAND-001/002 | Low. Check that no test reads `catalog_ar.json` at runtime. | B0 scan passes for `flutter_assets`. |
| B2 (P0, ~0.5 d) | Make every default PicPos: Dart `APP_BRAND`, CMake, Runner.rc, main.cpp. Fix CI `build-windows` to use the shared script, or disable `release`. | BRAND-003/004, REL-001 | Low | A build without defines gives `PicPos.exe`/CompanyName PicPos; the CI artifact passes the scan. |
| B3 (P1, 1–2 d) | Delete the UralCash branch from installer, build scripts and icons: `setup.iss` `#if uralcash`, info file, BMPs, `make_wizard_images.py`, `build_release.bat`, `app_icon_uralcash.ico`, root `icon.ico`, `gen_installer_art` entry. | BRAND-007/008 | None for PicPos (AppId unchanged). | `git grep -i uralcash -- installer windows tool build_*.bat` returns 0. |
| B4 (P1, 2–4 d, incremental) | Collapse `Brand` to PicPos constants; delete UralCash themes, nav layout, vendor strip, wizard title and `monexia` log prefix; rewrite comments. | BRAND-009 | Medium. Brand-dependent tests (`brand_isolation_test`) must be rewritten as PicPos-only. **Keep the `picpos_*` runtime identifiers unchanged.** | `git grep -i -E "uralcash|monexia|uraljo|يورال" -- lib` returns 0; the full suite is green. |
| B5 (P1, 1–2 d) | Replace salt and pepper literals with byte-identical constants; migrate secure-storage keys (read old, write new, delete old); add env-var aliases. | BRAND-005 | **High if done wrong.** It can lock users out of an encrypted DB or invalidate sessions and the invoice hash chain. Mitigate with golden tests on derived values before and after, and a pre-change backup. | Scan shows 0 `uralcash`/`ural_` in `app.so`; key-derivation golden tests pass; an existing v196 DB still opens. |
| B6 (P2, 1 d plus merge cost) | Rename the package to `picpos_erp` in one mechanical commit after the branches merge. Change the description now. | BRAND-006 | Medium (merge conflicts); low for data (no runtime keying found). | Scan shows 0 `ural_erp`; the full suite is green. |
| B7 (P2, 1–2 d) | Purge or archive non-shipped content: dead packages, `web_app/`, patches, backports, docs, scripts, SQL headers. Rewrite the customer-facing `tools/postgresql_setup_guide.md` (P1). | BRAND-010 | Low. Archive first if history is wanted. | `git grep -i uralcash` returns only an explicit archive allow-list. |
| B8 (owner) | Answer the BRAND-011 question about pre-split installs; if any exist, design a one-time importer. | BRAND-011 | Data-loss perception if old installs exist. | Answer recorded, and an importer test if needed. |

**What can stay internal:** nothing visible. After B5/B6 the only residual items would be git history and an archived docs folder, if the owner allows one.
**CI guard (permanent):** the B0 scan on every Windows build, plus `git grep` on the source tree as a structural test, together with a hash deny-list for the UralCash images.

---

## UX: journeys, terminology, currency, setup plans

### UX-001: Wizard offers SAR/AED/KWD/USD, but the engine silently turns them into JOD, and the choice is final
- **Type:** Defect · **Severity** High · **Priority** P0 · **Confidence** High (code path read end to end; not run).
- **Location:**
  - [step_company_info.dart:51-58](<../../../../lib/presentation/screens/setup_wizard/step_company_info.dart#L51-L58>) offers six chips.
  - [CurrencyInfo.fromCode](<../../../../lib/core/constants/app_constants.dart#L215-L223>) knows only `EGP`; everything else falls to `default: return jod`.
  - [SystemCurrencyNotifier.setCurrency](<../../../../lib/data/providers/providers.dart#L422-L436>) stores the raw code (`setSetting('system_currency', code)`) but applies `AppConstants.setCurrency`, which is JOD: symbol `د.أ`, 3 decimals.
  - The wizard banner says "العملة قرار نهائي" (screenshot `D:\qa\shots\G1b\G1b-01-currency.png`), and the notifier refuses changes after the first financial movement (:425-431).
- **Repro (by code):** wizard → choose «ريال سعودي (SAR)» → finish → the settings row `system_currency='SAR'`, the UI shows `د.أ` and all amounts round to 3 decimals. JoFotara/ETA mapping follows the separate e-invoice country.
- **Expected:** only supported currencies are offered, or the full currency metadata exists for every chip. **Actual:** a silent substitution that is locked after the first invoice.
- **Impact:** wrong currency on every document and wrong precision in the ledger for any user who picks one of 4 of the 6 chips, with no recovery path short of reinstalling.
- **Remediation:** limit the chips to `JOD` and `EGP` (the product's markets) now, and make `fromCode` throw on unknown codes. Add currencies later only with a full `CurrencyInfo` (symbol, decimals, e-invoice mapping).
- **Effort:** S.
- **Acceptance:**
  - A widget test shows exactly the supported chips.
  - A unit test shows that `fromCode('SAR')` throws.
  - A setup-finish test asserts `system_currency` ∈ {JOD, EGP}.
- **Release-blocking:** yes (irreversible data error at first run).

### UX-002: Currency literals hardcoded in screens and dialogs
- **Type:** Defect · **Severity** High · **Priority** P0 for POS, P1 for the rest · **Confidence** High (each line read by the reader; samples re-checked).
- **Canonical source to use instead:** `AppConstants.currencySymbol` (locale-aware) or `NumberUtils.formatCurrency` ([number_utils.dart:21-28](<../../../../lib/core/utils/number_utils.dart#L21-L28>)), driven by `SystemCurrencyNotifier`.
- **Instances and correctness per market:**

| File:line | Literal | Wrong for |
|---|---|---|
| [fixed_assets_picpos_screen.dart:1034,1041](<../../../../lib/presentation/fixed_assets_picpos/screens/fixed_assets_picpos_screen.dart#L1034>) | `{p0} ج.م` | JOD installs |
| [asset_locations_picpos_screen.dart:141](<../../../../lib/presentation/fixed_assets_picpos/screens/asset_locations_picpos_screen.dart#L141>) | `… · ج.م` | JOD |
| [opex_picpos_screen.dart:571,890,1004,1011,1018,1185](<../../../../lib/presentation/opex_picpos/screens/opex_picpos_screen.dart#L571>) | `{p0} ج.م` | JOD |
| [opex_picpos_allocate_dialog.dart:319-320](<../../../../lib/presentation/opex_picpos/screens/opex_picpos_allocate_dialog.dart#L319>) | `… ج.م` | JOD |
| [activity_log_items_picpos.dart:288,326](<../../../../lib/presentation/activity_log_picpos/screens/activity_log_items_picpos.dart#L288>) and legacy [activity_log_items.dart:268,306](<../../../../lib/presentation/screens/activity_log/activity_log_items.dart#L268>) | `{p0} د.أ` | EGP |
| [product_card.dart:462](<../../../../lib/presentation/pos/widgets/product_card.dart#L462>) (POS) | `' د.أ'` | EGP: every POS tile |
| [customer_selector_v2.dart:240](<../../../../lib/presentation/pos/widgets/customer_selector_v2.dart#L240>) | `{p0} د.أ` | EGP |
| [pos_expense_dialog.dart:471](<../../../../lib/presentation/pos/widgets/pos_expense_dialog.dart#L471>), [pos_deleted_items_dialog.dart:77](<../../../../lib/presentation/pos/widgets/pos_deleted_items_dialog.dart#L77>), [pos_previous_expenses_dialog.dart:165,245,283](<../../../../lib/presentation/pos/widgets/pos_previous_expenses_dialog.dart#L165>) | `د.أ` | EGP |
| [pos_opening_balance_dialog.dart:111](<../../../../lib/presentation/pos/widgets/pos_opening_balance_dialog.dart#L111>), [picpos_opening_balance_dialog.dart:130](<../../../../lib/presentation/shift_close_picpos/widgets/picpos_opening_balance_dialog.dart#L130>) | `suffixText: 'JOD'` | EGP (and Latin text in the Arabic UI) |
| [return_details_panel.dart:276,403,542,654,711,796](<../../../../lib/presentation/screens/sales_returns/return_details_panel.dart#L276>) | `{p0} د.أ` | EGP |
| [app_localizations.dart:53,88](<../../../../lib/core/l10n/app_localizations.dart#L53>) | `'currency': tr('ج.م')` / `'EGP'` | JOD |
| [quick_sale_policy.dart:489,505,671](<../../../../lib/domain/models/quick_sale_policy.dart#L505>) | `'١,٠٠٠ ج.م'`, `'لأقرب جنيه'` option labels | JOD (wording) |

- **Translation layer:** [en.json:141](<../../../../assets/i18n/en.json#L141>) maps `" د.أ"` to `" JOD"`, so switching the language does not help.
- **Legitimate uses (no action):** `CurrencyInfo`, multi-currency seeds, ETA `'EGP'`, JoFotara `'JOD'`, the parser strip list, and the documented JOD boot default ([app_constants.dart:40-56](<../../../../lib/core/constants/app_constants.dart#L40-L56>)).
- **Already fixed:** the report cards (FINAL-QA-VERDICT:24).
- **Impact:**
  - Egyptian POS cashiers see `د.أ` on product tiles, refunds and opening balance.
  - Jordanian users see `ج.م` on fixed assets and OPEX.
  - The amounts themselves are right; only the labels are wrong. Cashiers and customers rely on the labels, though.
- **Remediation:**
  - Replace all of them with the canonical getter.
  - Add a structural guard: no `ج.م`, `د.أ` or `'JOD'`/`'EGP'` string literal under `lib/presentation/**`, with an allow-list for options and protocols.
- **Acceptance:** the guard passes, and a widget test with currency EGP renders `ج.م` on `ProductCard` and `ReturnDetailsPanel`.
- **Release-blocking:** yes for any EGP deployment (POS); P1 otherwise.

### UX-003: `NumberUtils.formatAmount` freezes the symbol and decimals
- **Type:** Defect · **Severity** Medium · **Priority** P1 · **Confidence** High (code); usage frequency not measured.
- **Location:** [number_utils.dart:10-14, 31-33](<../../../../lib/core/utils/number_utils.dart#L10-L14>). `static final _currencyFormat` captures `AppConstants.currencySymbol` and `decimalPlaces` on first access. The same file's comment and [app_constants.dart:33-37](<../../../../lib/core/constants/app_constants.dart#L33-L37>) warn against exactly this.
- **Impact:** if anything formats before `SystemCurrencyNotifier.init()`, every later `formatAmount` call shows JOD with 3 decimals on an EGP install. The function is also documented "without symbol" but includes the symbol.
- **Remediation:** build the format per call, as `formatCurrency` does.
- **Acceptance:** a unit test calls `formatAmount` once, then `setCurrency('EGP')`, then `formatAmount` again, and asserts 2 decimals.

### UX-004: Irreversible currency is preselected (EGP plus 14%)
- **Type:** Improvement · **Severity** Medium · **Priority** P1 · **Confidence** High.
- **Location:** [setup_wizard_screen.dart:148](<../../../../lib/presentation/screens/setup_wizard_screen.dart#L148>) `String _currency = 'EGP';`. The screenshot `G1b-01-currency.png` shows EGP, 14% VAT and ETA preselected. The boot default and every test assume JOD (app_constants:39).
- **Problem:** the one setting the wizard labels "final" defaults to a market that is not the code's own default. A Jordanian user who clicks Next keeps EGP.
- **Proposal:**
  - No preselection: Next stays disabled until a currency is chosen, and the choice derives tax and e-invoice defaults (JOD → 16%/JoFotara, EGP → 14%/ETA).
  - Show a one-line confirmation on Review: "العملة: دينار أردني — لا يمكن تغييرها بعد أول فاتورة".
- **Effect on other journeys:** none. Settings already shows a locked picker ([general_settings_widgets_picpos.dart:185](<../../../../lib/presentation/settings_picpos/screens/general_settings_widgets_picpos.dart#L185>)).
- **Acceptance:** a widget test shows that Next is disabled with no currency selected, and that selecting JOD sets VAT 16% and JoFotara.

### UX-005: Company name entered in the wizard not persisted (G2)
- **Type:** Suspicion · **Severity** Medium · **Priority** P1 · **Confidence** Low.
- **Evidence:** in [G2.md §1](<D:/qa/reports/G2.md>) (`G2-01-wizard-step9.png`), the review shows `Test Company` after the tester tried to replace it with an Arabic name. The same report (§3) shows the automation could not type Arabic into any field, so the cause is probably the tool, not the app.
- **Next step:** reproduce manually, typing an Arabic name and then editing it, or with a widget test on `step_company_info` and `step_review`. The redesign plan's acceptance matrix should include this.

### UX-006: English "Dashboard" label in the Arabic UI
- **Type:** Defect · **Severity** Low · **Priority** P2 · **Confidence** High (screenshot `G1b-02-dashboard.png` plus code).
- **Location:**
  - [auth_providers.dart:648,673,783](<../../../../lib/data/providers/auth_providers.dart#L783>) (`NavGroupDef('home','Dashboard')`, `label: 'Dashboard'`).
  - [app_main_screen_catalog.dart:13](<../../../../lib/app_main_screen_catalog.dart#L13>).
  - [global_search_omnibox.dart:118](<../../../../lib/presentation/widgets/omnibox/global_search_omnibox.dart#L118>).
  - [admin_home_settings_picpos.dart:196](<../../../../lib/presentation/settings_picpos/screens/admin_home_settings_picpos.dart#L196>).
- **Actual:** the sidebar, tab and breadcrumb say "Dashboard" while the page title says «لوحة القيادة».
- **Fix:** use `tr('لوحة القيادة')` in all five places, plus an en.json entry.
- **Acceptance:** a widget test in Arabic finds no `Dashboard` text in the shell.

### UX-007: Overlapping sidebar destinations
- **Type:** Improvement · **Severity** Medium · **Priority** P2 · **Confidence** Medium (reader inventory; not clicked through).
- **Evidence:** `kAllNavItemDefs` has 72 entries in 11 groups ([auth_providers.dart:774-977](<../../../../lib/data/providers/auth_providers.dart#L774>)). Overlaps:
  - «العملاء والموردين» (6) vs «العملاء» (76) and «الموردون» (77).
  - «التوزيع» (24) vs «إدارة المناديب والتوزيع» (78), both under the `distribution_view` permission.
  - «المخزون» (8) vs «أرصدة المخزون» (19).
  - Legacy HR 16 («الحضور والرواتب» in PicPos) next to entries 79-86.
  - The `section: 'الموارد البشرية'` header is declared twice (:864, :875).
- **Problem:** two labels for one job make users wonder which one is "real", and permission admins must grant both.
- **Proposal:** for each pair, keep the PicPos destination, remove the legacy one from PicPos nav (not from code until BRAND-009), and merge the HR header.
- **Effect:** screen-access defaults and `default_screen` choices must be migrated for users whose default is a removed index. This needs a test.
- **Acceptance:** a nav-def unit test finds no duplicated `section` header and no two entries pointing at the same screen builder.

### UX-008: "Clear PLU" without confirmation
- **Location:** [plu_table_mixin.dart:163](<../../../../lib/presentation/screens/plu_manager/plu_table_mixin.dart#L163>) → [plu_manager_screen.dart:403-409](<../../../../lib/presentation/screens/plu_manager_screen.dart#L403-L409>).
- **Severity** Low · **Priority** P2 · **Confidence** Medium.
- **Impact:** an accidental click removes a scale PLU mapping, and weighed-item barcodes stop resolving at the POS.
- **Fix:** `showPicPosDangerConfirm`, the same as the other destructive actions. Restore backup, delete user, cancel invoice and reset wizard already confirm (reader sample of 9 actions).
- **Acceptance:** extend `destructive_user_actions_confirm_test` to cover it.

### UX-009: Hardcoded `TextDirection.rtl` in dialogs
- **Location:**
  - [purchase_returns_picpos_logic.dart:50](<../../../../lib/presentation/purchase_returns_picpos/screens/purchase_returns_picpos_logic.dart#L50>), [sales_returns_picpos_logic.dart:86](<../../../../lib/presentation/sales_returns_picpos/screens/sales_returns_picpos_logic.dart#L86>).
  - `table_reservation_dialog.dart:24,27-32` and `party_phone_dedupe.dart:49` (Q-review E-8).
- **Severity** Low · **Priority** P2.
- **Impact:** wrong layout in English mode, and the dedupe dialog column is not scrollable on small screens.
- **Fix:** inherit `Directionality` from the app locale.
- **Acceptance:** an English-locale golden test on the two return-confirm dialogs.

### UX-010: First-run redesign plan review ([plan](<../../../../docs/plans/2026-10-23-first-run-setup-redesign-plan.md>))
- **Type:** Requirement gap (plan document) · **Severity** Medium · **Priority** P0 (fix the plan before Specs) · **Confidence** High (plan read against the code).
- **What is sound and should be kept:**
  - The gap analysis §A is accurate. The step counts 9/8/8/6, `_SetupGate` on `setup_completed`, the non-transactional `SetupFinishRunner`, the absence of a draft, and the server path bypassing Review with `exit(0)` were all confirmed by reading the code.
  - Rule B: "no ✓ without real success".
  - The draft holds no secrets and is device-local.
  - Idempotent finish keys and `setup_completed` as the last write.
  - Closing the **server-mode `admin/admin`** gap (§A row 5, C.5).
  - Reusing the first-sync gate (B12).
  - Deferring the DB-folder choice, because the SQLCipher DB is already open (B14).
- **Conflicts with owner decision 2 (activation is not part of first-run):**
  - Step 2 `activation` / `branchLicense` in C.2.
  - B1, B2, B4, B5, B7.
  - P4 (`step_activation*`, `license_file_import.dart`).
  - The `activated` flag in C.3.
  - "تفعيل الترخيص" in C.4.
  - E2-E4.
  - **Required edit:** delete all of these. Each path becomes 6 steps.
  - The current read-only license banner on the welcome step ([step_welcome.dart:124-197](<../../../../lib/presentation/screens/setup_wizard/step_welcome.dart#L124-L197>)) may stay as information with a "يمكن التفعيل لاحقًا من الإعدادات › حول" link. It must not duplicate `LicenseService.activate` (described in REL-006).
- **Conflicts with owner decision 1 (PicPos only):**
  - C.1 "the old wizard stays (UralCash + its tests)".
  - P3 `buildFirstRunEntry` with a `Brand.isPicPos` branch.
  - P8 and E1.
  - **Required edit:** the new wizard replaces the old one outright. The mirror path, if kept, moves into the new flow as an advanced option. Do not keep two wizards.
- **Factual errors in the plan:**
  - §A row 3 places the currency chips in `step_currency_tax.dart`. They are in [step_company_info.dart:51-58](<../../../../lib/presentation/screens/setup_wizard/step_company_info.dart#L51-L58>).
  - The plan never notices that 4 of the 6 currencies are unsupported (UX-001), and the design mock's currency list omits EGP.
  - The plan must adopt the UX-001 and UX-004 fixes.
- **Duplication with Settings (periodic setup vs first-run):**
  - Company identity, currency (locked picker), tax and e-invoice, branches (`branches_picpos_screen.dart`), users and roles, and backups already have Settings screens.
  - The plan should state the rule **one writer per setting**: wizard steps call the same service methods Settings uses (not `SetupFinishRunner`-private writes), so the two never diverge.
  - Each wizard step should end with "يمكن تعديل هذا لاحقًا من الإعدادات › …", except currency, which is final.
  - Printers are correctly deferred to the success page (B16).
- **Missing acceptance items:**
  - The Arabic company name round-trip (UX-005).
  - Supported-currency enforcement.
  - 1366×768 and 125%/150% DPI layouts.
  - Keyboard-only completion (the existing Enter=Next).
  - Recovery after a crash mid-`committing` (the plan describes it; add a test).
- **Effort estimate in the plan** (~21 days) drops by P4 (1.5 days), and by part of P3/P8 if the old wizard is deleted rather than kept.

### UX-011: Warehouse-app plan review ([plan](<../../../../docs/plans/2026-10-23-warehouse-app-plan.md>))
- **Type:** Requirement gap · **Severity** Low · **Priority** P1 · **Confidence** Medium.
- **Sound:**
  - LAN-only to the embedded server (there is no cloud relay).
  - The `deviceKind:'warehouse'` route restriction.
  - Scope = the user's warehouses ∩ the device branch.
  - PO receipt does not post stock (R-A).
  - Staged transfers behind an off-by-default setting.
  - It reuses cycle-count tasks.
  - The referenced code exists: `warehouse_locations_*`, `bin_stock_ledger.dart`, `lan_pairing_service.dart`, `api_data_inventory.dart`. `mobile_warehouse/` and `lib/services/api/m1_wh/` are absent, as the plan expects.
- **Missing prerequisites:**
  - (1) Android release signing is broken for 2 of the 3 existing apps (REL-004). W0 must start from the `mobile_admin` pattern (`validateReleaseSigning`).
  - (2) The admin-QR pairing key is long-lived (FINAL-QA-VERDICT:43; plan P7 not done). The warehouse pairing reuses `/api/pair`, so that hardening must land first.
  - (3) CI builds no APK (ARCH-006). W6 "release" has no pipeline.
  - (4) The brand artifact scan (BRAND-012) must include the new app.
  - (5) Owner decision 3 (staff phones paired by the admin responsible for pairing) needs an explicit permission code for "pair warehouse device", separate from POS pairing.
- **Acceptance:** the plan lists these as W0 entry criteria.

---

## ARCH: code and architecture

### ARCH-001: Swallowed exceptions in money and sync paths
- **Type:** Defect · **Severity** Medium · **Priority** P1 · **Confidence** High (grep counts); per-site impact varies.
- **Counts in `lib/`:** 439 `catch (_)`, 209 single-line empty `catch (…) {}`, 28 single-line debugPrint-only catches. Multi-line catches were not counted, so the real total is higher.
- **Money-path examples:**
  - `checkout_controller.dart:264`: the sale audit log is lost silently.
  - `:363` `_resolveBranchId` → null.
  - `cart_controller.dart:1326`: an un-awaited `logActivity`.
  - `pos_closing_controller.dart:221`: the terminal branch becomes null at shift close.
  - `api_data_cash.dart:74,387`: cost center and shift start time on a server cash write.
  - `sales_mutations_dao.dart:234` and `purchase_dao.dart:267`: branch stays null, "non-fatal".
  - `table_pos_operations.dart`: 7 empty catches.
  - Voucher dialogs: cheques and cost centers load as empty.
  - `sales_return_provider.dart:171`: branch scope read failure leaves `scopeIds=null`, which means **full access**. It is documented as intentional ([:163-171](<../../../../lib/presentation/providers/sales_return_provider.dart#L163-L171>)). Flagged to the security axis: it is fail-open.
- **Impact:** records with a null branch or cost center skew branch reports and cost-center P&L silently, and audit gaps go unnoticed.
- **Remediation:**
  - Classify the catches as (i) best-effort UI, kept with a `log.w` via `AppLogger`; (ii) data-affecting, which must surface or abort.
  - Start with the 15 money-path sites.
  - Add a structural ratchet test with a count baseline, so that no new `catch (_) {}` appears under `lib/data/**` or `lib/services/**`.
- **Acceptance:** the ratchet is in CI, and the listed sites either rethrow or log with context, with a test for the null-branch case.

### ARCH-002: Business rules implemented in several places
- **Type:** Defect risk · **Severity** Medium · **Priority** P2 · **Confidence** Medium (locations read; no numeric divergence demonstrated).
- **Tax:**
  - Central `FinancialUtils.calculateTaxAmount` (rounded) vs inline unrounded `lineTotal * taxRate / 100` in both `sales_invoice_save_edit.dart` variants (:653, :589).
  - Also `purchases_state.dart:28`, `e_invoice_service_wrapper.dart:96` and `excel_service.dart:1344`.
- **Totals engines:**
  - `CalculateInvoiceTotalsUseCase`, `FinancialUtils`, `PicPosInvoiceTotals`.
  - Two separate `PurchaseTotals` classes.
  - `TableOrderTotals`, `ReceiptTotals`, plus per-screen totals in `purchase_invoice_form.dart`.
  - `packages/picpos_rules` exists for this exact purpose, but its README says the desktop does not use it.
- **Rounding:** independent `round2` in `expense_allocation.dart:81` (hard 2dp, which is wrong for JOD's 3dp), `landed_cost_dao.dart:209-218` and `hr_leave.dart:86`.
- **Average cost (WAC):** product-level vs per-warehouse WAC in `inventory_dao.dart:590-612, 665, 806`, plus a different formula in `landed_cost_dao.dart:377-383`.
- **Impact:** invoice, receipt and e-invoice totals can differ by rounding, and JOD 3dp allocations are truncated to 2dp.
- **Remediation:** route all of these through one engine (`picpos_rules`, or `FinancialUtils`) one family at a time, each with a parity test (screen total == saved total == receipt == e-invoice) on JOD and EGP fixtures.
- **Acceptance:** the parity tests pass and the duplicated helpers are deleted.
- Coordinate with axis B (data and accounting).

### ARCH-003: Static caches not invalidated by sync or settings change
- **Location:**
  - `StockShortagePolicyService` static `_cachedGlobal/_cachedPerBranch/_cachedPerTerminal` ([stock_shortage_policy_service.dart:75-77](<../../../../lib/services/stock_shortage_policy_service.dart#L75-L77>)), cleared only by its own `save*`.
  - `NumberUtils._currencyFormat` (UX-003).
  - `WebSessionGuard._cache` (10 s TTL, acceptable).
- **Severity** Medium · **Priority** P2 · **Confidence** Medium.
- **Impact:** a policy changed on the host and synced to a client is ignored until restart, so negative-stock rules differ between devices.
- **Fix:** invalidate from the settings-sync strategy, or read through the Riverpod settings provider.
- **Acceptance:** a test applies a synced settings row and the next `policyFor()` returns the new value.

### ARCH-004: Analyzer infos at HEAD; CI analyze probably red
- **Evidence:** `D:\qa\logs4\S0_analyze.log` reports 2 `use_build_context_synchronously` infos:
  - [purchase_returns_picpos_logic.dart:48](<../../../../lib/presentation/purchase_returns_picpos/screens/purchase_returns_picpos_logic.dart#L40-L48>)
  - [sales_returns_picpos_logic.dart:84](<../../../../lib/presentation/sales_returns_picpos/screens/sales_returns_picpos_logic.dart#L76-L84>)
  - Both use `showDialog(context:)` after `await ref.read(screenFiguresVisibilityProvider…future)` with no `mounted` check. They were introduced with commit `d2272da0` (hide monetary figures).
- FINAL-QA-VERDICT:11 calls analyze "clean", which this log contradicts.
- **CI:** [ci.yml:104](<../../../../.github/workflows/ci.yml#L104>) runs `flutter analyze lib/`. *Suspicion, not run:* `flutter analyze` treats infos as fatal by default, so `root_static` would fail on this HEAD.
- **Severity** Low (a crash only if the screen is closed during the await) · **Priority** P1 (CI signal) · **Confidence** Medium.
- **Fix:** `if (!context.mounted) return false;` before `showDialog`.
- **Acceptance:** `flutter analyze lib/` reports 0 issues.

### ARCH-005: A large share of tests are source-text scans
- **Evidence:** 1,374 `*_test.dart` files, 0 `integration_test/`, 117 under `test/structural/`. Many `test/static/*` and `test/structural/*` tests `readAsStringSync()` a `lib/` file and assert substrings, for example `contains('Brand.isPicPos')`. Behaviour tests do exist, for example `test/integration/pos_full_sale_flow_test.dart` (stock 20 → 17, safe +150).
- **Severity** Medium · **Priority** P2 · **Confidence** Medium (the reader sampled about 4 files, not 10).
- **Impact:** a high pass count (10,018 + 1,018 + 61) overstates behavioural coverage. Source-scan guards break on refactors and pass when the behaviour is wrong but the text is present. BRAND-012 is a concrete case: the guards were green while the logo and catalog leaked.
- **Remediation:**
  - Keep the cheap structural guards, but tag them `@Tags(['structural'])` and report them separately.
  - For each money-path guard, add at least one behaviour test.
  - Do not count structural tests toward the coverage gate.
- **Acceptance:** CI reports the structural and behavioural counts separately.

### ARCH-006: CI gaps
- **Source:** [.github/workflows/ci.yml](<../../../../.github/workflows/ci.yml>), read in full by the reader; key lines re-checked.
- **Runs:** secrets scan, gitleaks (advisory), `flutter analyze lib/` plus file-size limits, 12-shard `flutter test --coverage` excluding `test/e2e`, coverage gate ≥18%, analyze and test for `picpos_api_client` and the 3 mobile apps, server analyze and test on PG 16, e2e on Linux and PG, web build, Windows build (main and tags), and the release (tags).
- **Does not run:**
  - Any APK or AAB build or signing check.
  - The Inno installer build.
  - The SQLCipher DLL check.
  - Authenticode.
  - The PicPos brand (`APP_BRAND`) or the brand guard.
  - Analyze of root `test/`.
  - `packages/{core,accounting,inventory,pos,treasury,shared_widgets,picpos_rules,picpos_device,picpos_ui}` (the last three are live PicPos packages).
  - `test/integration_pg` (it is run locally: QA run S6 passed 92 tests).
  - The mobile `key.properties` validation.
- **Severity** High · **Priority** P1 · **Confidence** High.
- **Remediation:**
  - Add jobs for `picpos_rules`, `picpos_device` and `picpos_ui` tests.
  - Add an APK release build for each app, failing on debug signing (REL-004).
  - Add a Windows PicPos build through the shared script, plus the brand scan and SQLCipher check (BRAND-003/REL-001).
  - Make the coverage gate meaningful (ARCH-005).
- **Acceptance:** the workflow contains these jobs, and a deliberately broken brand or signing state fails CI.

### ARCH-007: God-file ratchet
- **Status:** in place. [file_size_ratchet_test.dart](<../../../../test/structural/file_size_ratchet_test.dart>) sets a 30 KB limit with a 172-entry [baseline](<../../../../test/structural/file_size_baseline.txt>). Shrinking passes, and growth or new oversize files fail.
- **Largest entries:** `invoice_template_seeder_dao.dart` 95 KB, `permission_codes.dart` 94 KB, `accounting_reports_dao.dart` 93 KB, `add_product_dialog.dart` 92 KB, `database_startup.dart` 90 KB.
- **Q-review F-2** emulated the test and found no failing file at that time. This audit did not run it (NOT_RUN).
- **Gap:** `mobile*` and `server/` are not covered.
- **Severity** Low · **Priority** P3.

---

## REL: distribution and release

### REL-001: CI release artifact skips SQLCipher enforcement and signing, and uses the wrong build number
- **Location:** [ci.yml:641-698](<../../../../.github/workflows/ci.yml#L641-L698>), compared with [build_picpos.bat:114-133](<../../../../build_picpos.bat#L114-L133>). The local script copies the SQLCipher `sqlite3.dll` over the plain one and runs `findstr /C:sqlcipher`; CI does neither.
- **Build number:** `--build-number=${{ github.run_number }}` overrides pubspec's `+277`. The version stamped in the exe therefore differs from the installer `AppVersion 3.9.2.277` and from `installer_version_matches_pubspec_test`.
- **Severity** High · **Priority** P0 · **Confidence** High (code); a plain-sqlite runtime outcome was not tested.
- **The connection refuses a non-SQLCipher engine:** the `cipher_version` probe (axis B baseline §1). So the CI artifact may fail to open its DB. This is inferred, not run.
- **Fix:** together with BRAND-003, use the shared build script.
- **Acceptance:** the CI artifact's `sqlite3.dll` contains `sqlcipher`, and the exe FileVersion equals the pubspec version.
- **Release-blocking:** yes if the GitHub Release is a distribution channel.

### REL-002: Unsigned installer, exe and DLLs
- **Evidence (T-C-05):** `Get-AuthenticodeSignature` reports NotSigned for `PicPos-Setup-3.9.2.277.exe`, `PicPos.exe` and `sqlite3.dll`.
- Signing is wired but optional: [setup.iss:190-195](<../../../../installer/setup.iss#L190-L195>) (`#ifdef SignInstaller`), `build_installer_picpos.bat:72-76`, and [tool/sign_file.cmd](<../../../../tool/sign_file.cmd>) (exits 0 when no identity is set). [info-ar-picpos.txt](<../../../../installer/info-ar-picpos.txt>) warns users about «ناشر غير معروف».
- **Severity** High · **Priority** P1 · **Confidence** High.
- **Impact:**
  - SmartScreen shows "Windows protected your PC" on download.
  - Some AV products quarantine unsigned POS software.
  - There is no tamper evidence for the update path (the installer is the only update path, REL-003).
- **Remediation:** obtain an OV or EV code-signing certificate and set `PICPOS_SIGN_PFX`/`THUMBPRINT` in the release environment. Make `build_installer_picpos.bat` **fail** (not skip) when `RELEASE=1` and no identity is set. Timestamping is already configured (digicert).
- **Acceptance:** all three files report Valid, and a release build without an identity fails.
- **Release-blocking:** for public distribution yes; for the owner-controlled pilot (FINAL-QA-VERDICT "GO مشروط") acceptable with the existing warning.

### REL-003: Update mechanism and pre-upgrade backup
- **Facts:**
  - No updater in `lib/` (reader search: update, updater, latest_version, releases/latest, checkForUpdate).
  - Users upgrade by running the next installer over the old one: same AppId ([setup.iss:57-60](<../../../../installer/setup.iss#L57-L60>)), `[Run]` only launches the app, no `[UninstallDelete]`, and data lives in `Documents`/`%APPDATA%`, so it survives an uninstall.
  - Before a schema upgrade, `runOnUpgrade` calls `createDatabaseBackup()` and **continues on failure** ("non-blocking", [database_migrations.dart:67-79](<../../../../lib/data/database/database_migrations.dart#L67-L79>)).
  - Backups rotate at 7, shared with the startup auto-backups ([connection_io.dart:420-444](<../../../../lib/data/database/connection_io.dart#L420-L444>)), so the pre-migration copy can be evicted after a week of daily starts.
  - The installer takes no backup.
- **Not verified:** behaviour when an *older* installer runs over a newer DB (downgrade).
- **Fleet note:** host and clients must be upgraded together (FINAL-QA-VERDICT §5), and nothing in the installer or app enforces or announces this.
- **Severity** Medium · **Priority** P1 · **Confidence** Medium.
- **Remediation:**
  - (1) Make the pre-migration backup **blocking**: refuse to migrate, with a recovery screen, if the backup fails.
  - (2) Store pre-migration backups in a separate folder that is excluded from rotation (keep the last 3 versions).
  - (3) Refuse to open a DB whose `schemaVersion` is greater than the app's, with a clear message.
  - (4) Add a client↔host version handshake that warns on mismatch.
  - (5) Optionally add an update check. Not required for the pilot.
- **Acceptance:** a test with a forced backup failure shows the migration not run; a test with DB v197 on app v196 shows a blocking message; a LAN client on the older version sees a warning.

### REL-004: Android release signing
- **Evidence:**
  - `mobile` (PicPos Van): `signingConfig = signingConfigs.getByName("debug")` always ([mobile/android/app/build.gradle.kts:36-38](<../../../../mobile/android/app/build.gradle.kts#L36-L38>)).
  - `mobile_pos`: falls back to debug when `key.properties` is missing ([mobile_pos/android/app/build.gradle.kts:16-20,60](<../../../../mobile_pos/android/app/build.gradle.kts#L60>)).
  - `mobile_admin`: fails the build without `key.properties` ([mobile_admin/android/app/build.gradle.kts:29-45,84-88](<../../../../mobile_admin/android/app/build.gradle.kts#L29-L45>)). This is the correct pattern.
  - `key.properties` files exist locally for admin and pos (not read). None are tracked (`git ls-files` shows no `.jks`/`.keystore`/`key.properties`).
- **Other manifest facts (PASS):** `allowBackup=false`; cleartext disabled in main (`usesCleartextTraffic=false`, `base-config cleartextTrafficPermitted=false`) and enabled only in `src/debug`. Permissions match each app's purpose:
  - Van: location (route).
  - Admin: camera for QR, biometric, notifications.
  - POS: camera and Bluetooth printers with `neverForLocation`.
- **Severity** High · **Priority** P0 for the APK channel · **Confidence** High.
- **Impact:** debug-signed APKs cannot be updated by a properly signed build later; users must uninstall and lose local data. Anyone holding the shared debug key can ship an "update".
- **Remediation:** apply the `mobile_admin` `validateReleaseSigning` pattern to `mobile` and `mobile_pos`, and keep the keystore off the repo with a backup.
- **Acceptance:** `flutter build apk --release` fails without `key.properties` in all 3 apps, and `apksigner verify --print-certs` shows the release certificate.
- **Release-blocking:** yes for distributing Van or POS APKs.

### REL-005: Trial watermark and activation cache depend on whether Settings was opened
- **Type:** Defect · **Severity** High · **Priority** P0 · **Confidence** Medium (code path read; not reproduced at runtime).
- **Code path:**
  - `TrialState.isActivatedCached = false` and `activePolicy = TrialPolicy.defaultTrial` (watermark: true) at process start ([trial_state.dart:7-16](<../../../../lib/core/trial/trial_state.dart#L7-L16>), [trial_policy.dart:80-90](<../../../../lib/core/trial/trial_policy.dart#L80-L90>)).
  - The only startup refresh is guarded by `if (AppConfig.isDemo)` ([app_main_screen_lifecycle.dart:27-30](<../../../../lib/app_main_screen_lifecycle.dart#L27-L30>)), and no build script passes `IS_DEMO`.
  - The cache is otherwise filled only when `activationStatusProvider` is watched (Settings nav rail, the About card, legacy settings) or by `add_product_dialog.dart:893`.
  - Receipts and template PDFs print the trial banner when `LicenseService.showWatermark` is true ([thermal_receipt_generator.dart:1137](<../../../../lib/services/printing/thermal_receipt_generator.dart#L1137>), [template_pdf_renderer.dart:204](<../../../../lib/services/printing/template_pdf_renderer.dart#L204>)).
- **Expected:** the watermark is a deterministic function of the license state. **Predicted actual:** after a fresh launch, receipts carry the trial banner, **even on an activated machine**, until someone opens Settings or the add-product dialog.
- **Related:**
  - In non-demo builds the product, customer and supplier limits are all behind `AppConfig.isDemo` ([product_crud_dao.dart:475](<../../../../lib/data/database/daos/product_crud_dao.dart#L475>), [party_dao.dart:188](<../../../../lib/data/database/daos/party_dao.dart#L188>)).
  - So for the shipped build, activation gates *only* this banner and `TrialGuard`, and `TrialGuard` reads the same stale cache.
- **Not verified:** whether the QA receipts showed the banner. G1/G1b/G2 printed no receipts.
- **Repro to run:** fresh launch of the activated build → POS sale → print preview → check for the banner. Then open Settings › About, return, print again, and compare.
- **Remediation:** call `refreshActivationStatus()` unconditionally at startup, before the first print is possible. The owner must also decide what activation is meant to gate in non-demo builds.
- **Acceptance:** a test with startup + no Settings visit + an activated key shows `showWatermark == false`, and with no key shows the banner consistently.
- **Release-blocking:** yes until the repro is run (customer-facing documents).

### REL-006: Activation mechanism as implemented (so the setup redesign does not duplicate it)
- **UI:** [activation_dialog.dart](<../../../../lib/presentation/widgets/settings/activation_dialog.dart>), opened from the license card in [settings_picpos_about.dart:139-177](<../../../../lib/presentation/settings_picpos/screens/settings_picpos_about.dart#L139-L177>). It needs the `system_license` permission. The dialog shows the machine ID (copyable) and accepts a pasted key.
- **Machine ID** ([license_service.dart:108-129](<../../../../lib/services/license_service.dart#L108-L129>)):
  - Windows: `deviceId + computerName + numberOfCores`, hashed with SHA-256, first 16 hex characters, uppercase.
  - Android: `androidInfo.id`. Web: the literal `WEB_STATION`.
- **Key:** `PP2-<base64url JSON>.<base64url Ed25519 signature>`.
  - The payload has `v=2`, `machineId` and `issuedAt`. It has **no expiry and no modules**.
  - It is verified with an embedded **public** key; no secret is in the app.
  - Keys are issued offline with `tool/license/issue_license.dart <private-key> <machine-id>`.
- **Storage:** secure storage `license_key`, mirrored into DB `settings` (:300-308). The app also auto-reads `license.txt`, `activation.key` or `license.key` next to the exe (:141-164).
- **Trial:** default "combined" policy: 30 days, 200 invoices, 50 products, customers and suppliers, 2 users, watermark. `trial_policy` and `install_date` are plain DB settings.
- **Weaknesses:**
  - (1) Renaming the PC or changing the core count invalidates the license. Support burden; document it or drop `computerName`.
  - (2) The trial policy and install date can be edited with any SQLite tool, but the DB is SQLCipher-encrypted, so the risk is low.
  - (3) REL-005.
  - (4) The first run never needs activation. That is consistent with owner decision 2.
- **Severity** Low · **Priority** P2.

### REL-007: Installer info text stale; PostgreSQL download at install time
- [info-ar-picpos.txt:10-11](<../../../../installer/info-ar-picpos.txt#L10-L11>) says VC++ is downloaded from Microsoft and needs internet. It is actually bundled, with a pinned version and a SHA-256 check ([setup.iss:144-160,248,426-427](<../../../../installer/setup.iss#L144-L160>)).
- The optional PostgreSQL 16.4 is downloaded from EnterpriseDB at install time (SHA-pinned), but the header comment says "EMBEDDED" (:155 vs :386).
- **Severity** Low · **Priority** P2.
- **Fix:** correct both texts, and state on the component page that PostgreSQL needs internet.
- **Acceptance:** the text matches the behaviour, checked on a clean VM.

### REL-008: Version identity inconsistent
- Desktop `3.9.2+277` (pubspec, exe, installer).
- [README.md:59](<../../../../README.md#L59>) says `3.9.1+275`.
- `AppConfig.version = '1.0.0'` ([app_config.dart:45](<../../../../lib/core/config/app_config.dart#L45>)). `about_version_is_not_hardcoded_test` exists; check which value the About screen reads.
- All 3 Android apps are `0.1.0+1`, with no compatibility matrix with the desktop server API.
- The CI build number is the run number (REL-001).
- **Severity** Low · **Priority** P2.
- **Fix:** one version source per app, a README generated from pubspec, and a compatibility table in the release notes (desktop ↔ API ↔ mobile).

### REL-009: Activation private key in the working tree
- `tools/picpos-activation/license_private_key.txt` exists next to `picpos-key-generator.html`. Its contents were not read.
- It is **not tracked** (`git ls-files tools/picpos-activation` is empty) and **never committed** (`git log --all` on the path is empty). The folder is ignored by [.gitignore:191](<../../../../.gitignore#L191>).
- **Severity** Low · **Priority** P1 · **Confidence** High.
- **Risk:** the machine's backups, sync tools or a future `git add -f` would expose the key that mints every license.
- **Fix:** move it to an offline or encrypted store, and keep only the public key in the repo.
- **Acceptance:** the file is absent from the working tree, and the key issuance procedure is documented.

---

## DEP: dependencies (`dart pub outdated --no-dev-dependencies`, run 2026-10-23, exit 0)

### DEP-001: `sqlcipher_flutter_libs` is EOL upstream
- Current `0.6.8`; resolvable and latest `0.7.0+eol`. The package that provides the encryption engine is end-of-life. Related: `sqlite3 3.3.1` (latest 3.7.1) and `drift` pinned at `2.32.1` (latest 2.35.2).
- **Severity** Medium · **Priority** P1 · **Confidence** High (tool output).
- **Impact:** there will be no SQLCipher security updates through this package, and future Flutter or toolchain upgrades may break it.
- **Remediation:** plan a migration to the maintained path, which upstream says is sqlite3 3.x with build hooks and SQLCipher; *verify on pub.dev*. Keep the `cipher_version` probe and the `build_picpos.bat` DLL check as the acceptance gate, and test opening existing encrypted DBs (a key-compat test on a v196 fixture).
- **Acceptance:** the app opens an existing encrypted v196 DB after the migration, and the artifact `sqlite3.dll` contains SQLCipher.

### DEP-002: Major versions behind; discontinued transitives
- **Majors behind:**
  - `flutter_secure_storage 9.2.4 → 11.2.0`, with Windows impl `3.1.2 → 4.2.2`. This is a storage-format risk: test the migration of the existing `flutter_secure_storage.dat` first.
  - `device_info_plus 12 → 13`. It feeds the machine ID, so a change can invalidate every license (REL-006).
  - `package_info_plus 9 → 10`, `file_picker 11 → 13`, `archive 3 → 4`, `go_router 17 → 18`, `data_table_2 2 → 3`, `shimmer 3 → 4`, `serial_port_win32 2 → 3`, `ftpconnect 2 → 3`.
  - `supabase_flutter 2.12 → 2.18` (minor).
- **Discontinued:** `js`, and `screen_retriever_*` (via `window_manager`).
- **Severity** Low · **Priority** P2.
- **Remediation:** upgrade one package per PR. For `device_info_plus` and `flutter_secure_storage`, add a test proving the machine ID and the stored keys survive.

### DEP-003: Licences
- **Root `pubspec.lock`:** 204 entries; 198 hosted packages were matched to the local pub cache LICENSE files. Result: BSD 127, MIT 51, Apache-2.0 18, **MPL-2.0 2** (`dbus`, `gtk`, transitive and Linux-only, not linked into the Windows build). No GPL, LGPL or AGPL.
- **Bundled fonts:** Cairo and Noto Naskh Arabic are under OFL, with licence files shipped (`assets/fonts/*-OFL.txt`).
- **Runtime components:** the VC++ redist is under Microsoft's redistributable terms, and Flutter's `NOTICES.Z` is shipped in `flutter_assets`.
- **NOT_RUN:** the mobile app and server lockfiles, native SQLCipher/OpenSSL notices, and a vulnerability (CVE/OSV) scan, which belongs to the security axis.
- **Severity** Info.

### DEP-004: Unused dependencies and dead code
- `state_notifier` and `cupertino_icons` have 0 imports in `lib/`.
- `ApiKeyDao.createApiKey` has 0 callers.
- 6 `packages/*` are not imported (BRAND-010).
- `web_app/` is not built.
- **Severity** Low · **Priority** P3.
- **Fix:** remove them, and add `dependency_validator` or a simple import-count check to CI.
