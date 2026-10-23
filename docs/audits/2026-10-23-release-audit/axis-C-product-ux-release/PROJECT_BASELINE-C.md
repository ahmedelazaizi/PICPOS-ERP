# Axis C: Project baseline (product, components, build/run/test/install/update, CI, modes of use)

| Item | Value |
|---|---|
| Repo | `D:\PICPOS-ERP` (origin `https://github.com/ahmedelazaizi/PICPOS-ERP.git`) |
| Branch | `feat/tables-reservations-permissions`. Local tracking shows it level with `origin/…`, but no `git fetch` was performed, so the remote's current state is unknown. |
| HEAD | `d69be1eafc7d82b924723dfdbb53960b7e33acdb`: `chore(release): QA fixes, i18n keys, docs, version 3.9.2+277` (2026-10-23 03:08 +0300). Unchanged during the audit. |
| Local changes | Untracked only: `Cairo,Noto_Naskh_Arabic/`, root `all_final.txt`, `all_print_tests*.txt`, `font_*.txt`, `orig5.txt`, `docs/plans/2026-10-23-first-run-setup-redesign-plan.md`, `docs/plans/2026-10-23-warehouse-app-plan.md`, two Arabic design folders, `طلب مراجعه.txt`, and `docs/audits/` (axis B created by another session during this audit). No tracked file is modified. |
| Version | Desktop `3.9.2+277` (pubspec, exe resource, installer `AppVersion 3.9.2.277`). Android apps `0.1.0+1`. Server `picpos_cloud 0.1.0`. |
| Toolchain | Dart SDK `^3.10.4`. CI pins Flutter `3.41.x`. Local Flutter at `D:\Cash\develop\flutter`. |
| Auditor mode | Read-only. The only Dart command run was `dart pub outdated --no-dev-dependencies`. The app was not launched. |

## 1. Product purpose and users
PicPos ERP is an Arabic-first (RTL, with a per-user English UI) ERP + POS for small and medium businesses in **Jordan (JOD, JoFotara) and Egypt (EGP, ETA)**: supermarkets, retail, wholesale, distribution, restaurants and cafés, and light manufacturing ([README.md:20-23](<../../../../README.md#L20-L23>)). This is stated by the docs; the code confirms JOD and EGP as the only implemented currencies (`CurrencyInfo`).

**Users (from the docs, nav and permissions):**
- Owner/admin.
- Accountant.
- Cashier (POS, shifts).
- Storekeeper.
- Sales rep (Van app).
- Manager approving sensitive operations (manager override).
- Developer/support (a separate developer password).
- Planned: warehouse staff (warehouse-app plan).

**Owner decision 2026-10-23:** the system is PicPos only. Nothing may mention UralCash.

## 2. Components

| Component | Path | Notes |
|---|---|---|
| Windows desktop app (primary) | root `lib/`, `windows/` | Flutter, Riverpod, Drift. SQLite+SQLCipher locally, or PostgreSQL in server mode. An embedded shelf API/LAN server runs on the host. Dart package `picpos_erp` (BRAND-006). |
| Web mirror client | `lib/main_web_entry.dart`, `web/` | Reads over WebSocket (drift remote) and writes via the HTTP API. Built in CI as an artifact only. |
| PicPos Van (field rep) | `mobile/` | `com.picpos.picpos_van`, offline-first, Bluetooth printing. |
| PicPos إدارة (Admin) | `mobile_admin/` | `com.picpos.admin`. Pairing, KPIs, approvals. Partially placeholder. |
| PicPos كاشير (Cashier) | `mobile_pos/` | `com.picpos.pos`. Phase M-0 shell (README:63). |
| Cloud server | `server/` (`picpos_cloud`), `docker/` | Pure Dart shelf + PostgreSQL. Routes `/mobile/*`, `/desktop/*`, `/manage/*`, `/admin/*`. |
| Live shared packages | `packages/picpos_api_client` (desktop path dep), `picpos_rules`, `picpos_ui`, `picpos_device` | `picpos_rules` is not used by the desktop (ARCH-002). |
| Dead packages | `packages/{core,accounting,inventory,pos,treasury,shared_widgets}` | UralCash-described, 0 imports (BRAND-010). |
| Legacy | `web_app/` (UralCash Web + Supabase), `patches-for-uralcash/`, `supabase/` | Not in the delivery path. |
| Installer | `installer/setup.iss` (Inno Setup 6), `installer/prereqs/vc_redist.x64.exe` | x64, admin, Arabic UI. Optional PostgreSQL 16.4 component. |
| Activation | `lib/services/license_service.dart`, Settings › About | Offline Ed25519 key bound to the machine ID (REL-006). |

## 3. Build, run, test, install, update procedures (as implemented)
- **Run (dev):** `flutter pub get` then `flutter run -d windows --dart-define=APP_BRAND=picpos --dart-define=APP_FLAVOR=unified`. Omitting `APP_BRAND` runs **UralCash** (BRAND-004).
- **Release build (Windows):** [build_picpos.bat](<../../../../build_picpos.bat>). It:
  1. Sets `BRAND_*` env (PicPos).
  2. Runs `flutter test --dart-define=APP_BRAND=picpos test\unit\brand_picpos_test.dart`.
  3. Copies the PicPos icon over `app_icon.ico`.
  4. Deletes `build\windows`.
  5. Runs `flutter build windows --release --dart-define=APP_BRAND=picpos --dart-define=APP_FLAVOR=unified`.
  6. Fails if `UralCash.exe` is present.
  7. Overwrites `sqlite3.dll` with the SQLCipher build and runs `findstr /C:sqlcipher`.
  8. Signs, optionally.
  9. Copies the output to `FlavorBuilds\PicPos`.
  - The version comes from pubspec.
- **Installer:** [build_installer_picpos.bat](<../../../../build_installer_picpos.bat>). It checks the exe, runs `tool/fetch_prereqs.ps1` (VC++ hash and signature), then `ISCC /DBrandId=picpos`. Signing applies only if `PICPOS_SIGN_PFX` or `PICPOS_SIGN_THUMBPRINT` is set. The output is `installer\output\PicPos-Setup-<ver>.exe` (47.7 MB for 3.9.2.277, unsigned).
- **Android:** `flutter build apk --release` in each app. Release signing: `mobile` always uses the debug key, `mobile_pos` falls back to debug, and `mobile_admin` is strict (REL-004).
- **Server:** `cd server; dart run bin/server.dart`, or Docker (`docker/`).
- **Tests:**
  - `flutter test` (root; about 1,374 test files).
  - `flutter test test/structural`.
  - `cd server; dart test -j 1`.
  - `dart run scripts/run_pg_tests.dart` (PG integration).
  - `scripts/gate.sh` (local gate).
  - Latest full local run [prior, `D:\qa\logs4`]: main +10018, scenarios +61, integration +1018, brand +13, e2e pass, PG +92.
- **Install:** run the setup as admin. It installs to `{autopf}\PicPos` and installs VC++ only if it is missing. No certificate trust-store changes. Data lives in `Documents\picpos_<flavor>.db`, `%APPDATA%\PicPos\PicPos` (secure storage, prefs) and `Documents\PicPos_Backups`.
- **Update:** no in-app updater. Run the newer installer over the old one (same AppId). The schema migrates on first launch, with a **non-blocking** backup that is rotated at 7 (REL-003). The fleet (host and clients) must be upgraded together; this is documented but not enforced.
- **First run:** `_SetupGate` reads `setup_completed`. The wizard has 9 steps (standalone), 8 (mirror), 8 (server) or 6 (client). Activation is **not** part of it; it lives in Settings.

## 4. CI (`.github/workflows/ci.yml`, the only workflow)
- **Triggers:** push to any branch, pull requests, and `v*.*.*` tags.
- **Jobs:** `secrets`, `gitleaks` (advisory), `root_static` (`flutter analyze lib/` plus file-size gates), `root_tests` (12 shards, coverage), `coverage_gate` (≥18%), `packages_and_mobile` (api_client and the 3 apps: analyze and test), `server` (analyze and test on PG 16), `e2e` (Linux and PG), `web` (build artifact), `build-windows` (main and tags; **no brand define, no SQLCipher step, no signing**), `release` (tags; publishes the zip).
- **Not run:** APKs, the installer, the PicPos brand guard, analyze of `test/`, 9 packages, and `integration_pg` (ARCH-006).

## 5. Modes of use
- **Standalone:** one PC, local SQLCipher DB, offline.
- **Server (host):** PostgreSQL plus the embedded API. The LAN server is HTTP on 8080 by default, with optional TLS and TOFU pinning.
- **Client:** a LAN device with a full local DB. First sync is mandatory (`client_first_sync_completed` gate). Offline queue with idempotency keys.
- **Mirror:** a read-mostly secondary.
- **Web mirror:** a browser client against the host.
- **Mobile:** Van, Admin and Cashier apps, paired via code or QR to the desktop or cloud server.
- **Multi-user** with fine-grained permissions, manager override, and branch scope (`UserBranchAccess`).
- **Multi-branch** via branch IDs on documents. Business profiles (`lite` default for PicPos) gate visible modules.

## 6. Authentication (for context; details belong to the security axis)
- Local login uses Argon2id hashes. Server sessions use HMAC tokens (salts are UralCash-named, BRAND-005). LAN pairing uses an 8-character code (10 minutes, 5 attempts per IP).
- Licence: offline Ed25519 (REL-006).

## 7. Confirmed requirements, assumptions, open questions
- **Confirmed (owner, 2026-10-23):**
  - PicPos only.
  - Activation stays in Settings, not in first-run.
  - The warehouse app is for staff and paired by an admin.
  - Real estate comes later.
  - The review comes first, then ordering.
- **Assumptions:**
  - `FlavorBuilds\PicPos` was built from HEAD (timestamps 03:14 vs commit 03:08).
  - The installer payload equals that folder.
  - The markets are only JO and EG.
- **Open questions (owner):**
  1. Were any PicPos customers installed before the brand split (2026-07-26), or from a UralCash-default build? This decides whether an importer from `uralcash_*` / `Monexia` is needed (BRAND-011).
  2. In non-demo builds, what should activation gate (watermark only, or limits)? See REL-005.
  3. May UralCash be deleted from this repository outright, or must it remain buildable elsewhere? This decides between delete and move-to-branch (BRAND-007/009/010).
  4. Is the GitHub Release (tag) a distribution channel today? If yes, BRAND-003 and REL-001 are live risks.
  5. Rename the Dart package `picpos_erp` → `picpos_erp` now, or after the feature branches merge (BRAND-006)?
