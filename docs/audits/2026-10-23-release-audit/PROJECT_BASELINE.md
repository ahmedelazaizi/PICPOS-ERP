# PROJECT_BASELINE — PicPos ERP at the audited version

This file merges the three axis baselines with duplicates removed: [A](<axis-A-security-sync/PROJECT_BASELINE-A.md>) (auth, permissions, sync), [B](<axis-B-data-accounting/PROJECT_BASELINE-B.md>) (data, accounting, migrations, backup), and [C](<axis-C-product-ux-release/PROJECT_BASELINE-C.md>) (product, components, build, CI, modes). The axis files hold more line-level detail. Everything here describes the **code as read**, not observed runtime behaviour.

## 1. Version pinned for the audit

| Item | Value |
|---|---|
| Repo | `D:\PICPOS-ERP` (origin `https://github.com/ahmedelazaizi/PICPOS-ERP.git`) |
| Branch / HEAD | `feat/tables-reservations-permissions` @ `d69be1eafc7d82b924723dfdbb53960b7e33acdb`, committed 2026-10-23 03:08:46 +0300 (`chore(release): QA fixes, i18n keys, docs, version 3.9.2+277`). HEAD stayed unchanged for the whole audit (re-checked when this consolidation was written). |
| Candidate range | `c5f5056c` (3.9.1+276, 2026-10-17) `..d69be1ea`: 4 commits (`2eef5c0e`, `c56da2c9`, `d2272da0`, `d69be1ea`), all stamped 2026-10-23 03:08. 156 files changed, +10,090 / −1,064. |
| Versions | Desktop `3.9.2+277` (pubspec, exe resource, installer `AppVersion 3.9.2.277`). Android apps `0.1.0+1`. Cloud server `picpos_cloud 0.1.0`. `schemaVersion` 196 (`lib/data/database/database.dart:673`). |
| Toolchain | Dart SDK `^3.10.4`. CI pins Flutter `3.41.x`. Local Flutter at `D:\Cash\develop\flutter`. |
| Local changes | No tracked file is modified. Untracked: `Cairo,Noto_Naskh_Arabic/`; root scratch `*.txt` (`all_final.txt`, `all_print_tests*.txt`, `font_*.txt`, `orig5.txt`); two Arabic design folders (one holds `picpos_login_log_server.txt`, SEC-012); `طلب مراجعه.txt`; the two plan docs `docs/plans/2026-10-23-*`; and `docs/audits/`. |
| Remote | No `git fetch` was run. Local tracking showed the branch level with `origin/…`, but the remote's current state is **unknown**. |
| Artifact | `FlavorBuilds\PicPos\` (65 files, 82.4 MB, `PicPos.exe` 2026-10-23 03:14:32, FileVersion `3.9.2+277`). `installer\output\PicPos-Setup-3.9.2.277.exe` (2026-10-23 03:15, ≈ 47.7 MB). It is **assumed, not proven**, that both were built from HEAD (timestamps are 6 minutes after the commit). |

## 2. Product, users, markets

- **Purpose:** an Arabic-first (RTL, with a per-user English UI) ERP + POS for small and medium businesses in **Jordan (JOD, JoFotara) and Egypt (EGP, ETA)**: retail, supermarkets, wholesale, distribution, restaurants and cafés, light manufacturing (`README.md:20-23`). The code implements only JOD and EGP in `CurrencyInfo` (see UX-001).
- **Users:**
  - Owner / admin.
  - Accountant.
  - Cashier (POS, shifts).
  - Storekeeper.
  - Field sales rep (Van app).
  - A manager approving sensitive operations (manager override).
  - Developer / support (separate developer password).
  - Planned: warehouse staff (warehouse-app plan).
- **Owner decisions of 2026-10-23** (appended to both plans):
  1. PicPos only; nothing may mention UralCash.
  2. Activation is not part of first-run setup; it stays in Settings.
  3. The warehouse app is for the warehouse manager, supervisor, manager and clerk, installed on their phones and paired with the permission of the administrator responsible for linking and pairing devices.
  4. Real estate comes later.
  5. Review first, then ordering of work.

## 3. Components

| Component | Path | Notes |
|---|---|---|
| Windows desktop app (primary) | `lib/`, `windows/` | Flutter + Riverpod + Drift. SQLite + SQLCipher locally, or PostgreSQL in server mode. Embedded shelf LAN API on the host. Dart package name `picpos_erp` (BRAND-006). |
| Web mirror client | `lib/main_web_entry.dart`, `web/` | Reads over WebSocket, writes via the HTTP API. Built in CI as an artifact only. |
| PicPos Van (field rep) | `mobile/` | `com.picpos.picpos_van`, offline-first, Bluetooth printing, `mobile_scanner`. |
| PicPos إدارة (Admin) | `mobile_admin/` | `com.picpos.admin`: cloud pairing, signed snapshots, approvals, app lock. Partly placeholder. |
| PicPos كاشير (Cashier) | `mobile_pos/` | `com.picpos.pos`: M-0 shell; pairing disabled. |
| Cloud server | `server/` (`picpos_cloud`), `docker/` | Pure Dart shelf + PostgreSQL. Routes `/mobile/*`, `/desktop/*`, `/manage/*`, `/admin/*`. Binds plain HTTP (SEC-014). Only a TEST docker stack is shipped. |
| Live shared packages | `packages/picpos_api_client` (desktop path dep), `picpos_rules`, `picpos_ui`, `picpos_device` | The desktop does not use `picpos_rules` (ARCH-002). |
| Dead / legacy | `packages/{core,accounting,inventory,pos,treasury,shared_widgets}`, `web_app/`, `patches-for-uralcash/`, `supabase/` | UralCash-described; not in the delivery path (BRAND-010). To be removed per owner decision 1. |
| Installer | `installer/setup.iss` (Inno Setup 6), `installer/prereqs/vc_redist.x64.exe` | x64, admin, Arabic UI; optional PostgreSQL 16.4 component downloaded at install time (REL-007). |
| Activation | `lib/services/license_service.dart`, Settings › حول (About) | Offline, machine-bound Ed25519 key (§9). |

## 4. Deployment modes

Modes are defined in `NetworkMode` (`lib/services/network_service.dart:35-39`).

| Mode | Data store | Network surface |
|---|---|---|
| `standalone` | Local SQLite + SQLCipher | None; the UI is the only entry point. |
| `server` (host) | SQLite + SQLCipher, or PostgreSQL (`drift_postgres`) | Embedded shelf server on `anyIPv4:<port>` (default 8080). HTTP unless `network_tls_enabled` (`network_service.dart:748-819`); TOFU pinning. Optional web access (`/api/web/*`, `/webdb`). |
| `client` (terminal) | Local SQLite + SQLCipher full replica | Delta pull, outbox replay via `ClientWriteInterceptor` → `ServerProxy`, WebSocket notify. First sync is mandatory (`client_first_sync_completed`). |
| `mirror` | Local replica of all branches the user may see | Like a client, with mirror scope rules. |
| Web mirror | Browser | Against the host. |
| Mobile | Device-local SQLCipher stores | Van, Admin and POS apps, paired by code or QR to the desktop LAN server or to the cloud. |

Multi-user with fine-grained permissions, manager override and branch scope (`UserBranchAccess`). Multi-branch through branch ids on documents. Business profiles (`lite` is the PicPos default) gate the visible modules.

## 5. Authentication and sessions

**Local login**
- `authenticateUser` (`lib/data/database/daos/user_dao.dart:339-413`) requires `is_active=1` and `is_locked=0`.
- Hashes are Argon2id (m=4096 KiB, t=3, p=1); legacy PBKDF2 (10k) hashes are rehashed on login (`security_service.dart:72,142-215`). A dummy Argon2 runs for unknown users.
- Password-or-card login (`user_dao.dart:460-510`) is used by the manager override, the session lock and close-shift. Duplicate passwords are refused.
- Lockout: 5 failures → 15 minutes, **in memory only** (SEC-009).
- Seeded admin `admin`/`admin` with `force_password_change`. The local UI enforces the forced change (`login_screen.dart:359-376`); the wizard sets the admin password only in standalone mode.
- Self-heal paths can reset or re-create `admin`/`admin`: `database_startup.dart:798-889, 1240-1273`; `api_get_users.dart:163-256` (SEC-001, SEC-011).
- POS idle lock: default 5 minutes.

**LAN API** (`lib/services/api/api_auth_middleware.dart:214-318`)
1. **Device bearer:** `HMAC(installSecret, deviceId)` after pairing (8-character one-time code, 10-minute TTL, 5 attempts per IP). For 30 days a shared legacy bearer is also accepted (SEC-006). Exempt paths: `/api/health`, `/api/pair`, `/cfd`, `/menu`, `/ws`, `/api/table-bill`.
2. **Identity:** `X-Session-Token` HMAC `{uid, exp}` with a 30-day TTL, issued by `POST /api/auth/session` (`api_auth_handler.dart:156-208`). Stateless, with no revocation (SEC-003). The forged `X-User-Id` header is ignored.
3. **Web sessions:** 12-hour TTL, revocable `sid`, Origin allowlist, `WebHttpReadGate`.

**Cloud**
- Device tokens are random and stored as SHA-256, with rotation grace.
- PIN login: PBKDF2 120k.
- Admin-app pairing: one-time hashed code; Ed25519-signed snapshots, verified against the public key from the QR (SEC-017).
- The tenant is always derived from the authenticated device or link (`server/lib/src/service/auth_service.dart:105-139`).

## 6. Permissions and branch scope

**Model**
- One role per user. Each `role_permissions` row has `grant_mode` normal or conditional.
- `getUserPermissionCodes` returns `code` plus a `cond:<code>` marker for conditional rows (`permissions_dao.dart:251-314`).
- The system-admin role (`مدير النظام`) gets every non-critical code plus a `system_admin` marker. `criticalFinancialOps` must be granted explicitly.

**UI checks**
- `PermissionGuard` / `hasPermissionWithAdminBypass` (`permission_guard.dart:835-845`).
- `ensurePermission` → manager-override dialog for missing or conditional codes (:863-890; AUTHZ-001).
- `tableActionGate`.

**Screen access** (new in `c56da2c9`)
- `canOpenScreen = bypass || any code in screenPermissionSet(id)`; settings, users and roles are strict.
- Screen access grants no read or action rights by itself (`screen_access_resolver.dart`).

**Figure masking** (new in `d2272da0`)
- `canSeeScreenFigures` / `screenFiguresVisibilityProvider` (`financial_figures_access.dart`).
- Applied widget by widget in 7 presentation files; not in details, statements, exports or prints (AUTHZ-002, AUTHZ-003).

**Service/DAO layer**
- `PermissionEnforcer` covers ≈ 10 critical financial operations; everything else is widget-level (AUTHZ-010).

**API layer**
- `ApiUserCtx.requirePermission` on mutation routes (`api_user_context.dart:47-85`). It does not distinguish conditional grants (AUTHZ-005) and does not check active/locked status (SEC-003).
- A grep test guards mutation handlers. GET handlers have no permission gate for device sessions (AUTHZ-006).

**Device pairing (UI)**
- Settings › «ربط التطبيقات والأجهزة» (`lib/presentation/settings_picpos/screens/linked_devices_section.dart:54-86`) lets only holders of the `system_admin` marker (or `*`) pair or revoke devices; others see a read-only notice.
- There is **no dedicated permission code** for pairing. This was read for this consolidation; it matters for the warehouse plan.

**Branch scope**
- Client `branchScopeProvider` (`branch_scope_provider.dart:157-292`) is fail-closed for unassigned users.
- Host `_resolveBranchScope` (`api_branch_scope.dart:105-142`): fail-closed `[-1]` for no identity on transactional reads.
- `GET /api/parties` is unscoped (SEC-008); the parties export is unscoped (AUTHZ-003).

## 7. Sync as implemented

**Pull**
- `DeltaPullService` iterates a fixed FK-ordered table list (`delta_pull_service.dart:53-200`), keyset paging `(last_modified_at, id)` with 500-row pages.
- Watermark = server time of the first page.
- Per-row work: natural-key / `global_id` matching, conflict policy, soft-delete, party FK remap (now including reservations and bookings), column filter (v196+ clients only).
- Per-row failures are `debugPrint`ed and the watermark still advances (SYNC-002).
- The host serves `SELECT *`; there is **no schema or version handshake** (SYNC-001).

**Push**
- Writes go through `ClientWriteInterceptor` or the `sync_outbox` while offline.
- `OfflineSyncWorker` replays with stable idempotency keys; bounded retries; dead-letter UI.
- Non-financial conflicts are marked synced and the change is dropped (SYNC-005).
- Table reservations have no push path (SYNC-003).

**Cloud**
- The desktop pushes master data, documents and signed admin snapshots.
- Mobile reps push field documents (max 50 per request, 60 per minute) and pull master data.
- There is no command/query relay (SYNC-007).

## 8. Data architecture

**Engines**
- SQLite + SQLCipher via Drift `2.32.1` (pinned) and `sqlcipher_flutter_libs ^0.6.8` (EOL upstream, DEP-001).
- The key is resolved before any file handle. `PRAGMA key` comes first, then a `cipher_version` probe that refuses plain sqlite3, then `foreign_keys = ON` and WAL (`connection_io.dart:49-118`).
- PostgreSQL via `drift_postgres ^1.3.1`. Raw SQL is translated by `PgCompatSql.fixSql`, which handles strftime, julianday, INSTR and GROUP_CONCAT only (`pg_compat_sql.dart:112-157`; RPT-003).
- The PG schema is created fresh; **`onUpgrade` is skipped on PG**, and parity is enforced at `beforeOpen` (`database.dart:846-856`).

**Schema**
- 167 Drift tables, 134 DAO files, `schemaVersion` 196.
- Integer PKs; `global_id` UUIDv7 for cross-device identity.
- FKs enforced on SQLite. Notable missing constraints are listed in DATA-004.
- Two soft-delete conventions: `is_deleted` (+ `deleted_at`) on journal entries, sales and purchase invoices and purchase returns; `deleted_at` only elsewhere.
- Void sets `status='voided'` **and** `is_deleted=1`. A full purchase return sets `status='returned'` and keeps `is_deleted=0`.

**Money**
- `REAL` columns (decision FA-04).
- `FinancialUtils.round()` rounds half away from zero; decimals from `AppConstants.decimalPlaces` (JOD 3, EGP 2).
- Fixed tolerance 0.01 (ACC-010).
- Dates are epoch **seconds**, with some millisecond columns; local time, no TZ normalisation.

**Accounting**
- Single writer `createJournalEntry` (`accounting_dao_writes.dart:45-311`): transactional, balanced in minor units, period checks, auto-post dedup index.
- Auto-posting covers sales, returns, purchases, vouchers, payroll, depreciation, disposal, inventory adjustments, transfers, manufacturing, FX revaluation and booking deposits.
- The sales JE is posted **after** the invoice transaction commits (DATA-005).
- Cached `parties.balance`, with a startup mismatch check and repair.

**Migrations**
- `onUpgrade` (SQLite only) → `runOnUpgrade` → best-effort pre-migration backup (MIG-004) → epoch files (`epoch_1` … `epoch_3_v196_v205`).
- `_safeMigrate` swallows "duplicate column / already exists / no such column / cannot add a unique column" (MIG-003).
- Drift 2.32.1 runs migrations with **no wrapping transaction** (MIG-002) and calls `onUpgrade` for a **newer** DB too, then stamps it 196 (MIG-001).

**Backup / restore**
- Byte copy of the encrypted DB to `Documents/backups/…` plus a keyinfo sidecar; optional WAL checkpoint; 7 retained per DB, shared with startup and manual backups (`connection_io.dart:366-454, 574-599`).
- Auto backup when the newest is > 24 h old; **SQLite only** (BKP-004).
- Restore is two-phase `PendingRestore`: key + `quick_check` validation, `.pre-restore` rollback, no `user_version` check (BKP-002).
- No real restore test exists (BKP-001).

**Import/export**
- XLSX via `excel_service.dart`: products match by code, with tax normalised and checked; parties match by name and the **balance is overwritten** (DATA-003); purchases are grouped by supplier invoice number.
- CSV export without formula escaping (DATA-007).

## 9. Activation (licence), as implemented

This section exists so the first-run redesign does not duplicate activation (owner decision 2). Facts come from [REL-006](<axis-C-product-ux-release/FINDINGS-C.md#L671>); the key lines were re-read for this consolidation.

- **Where:** Settings › حول (About) licence card (`lib/presentation/settings_picpos/screens/settings_picpos_about.dart:139-179`). It shows «النسخة مفعلة بالكامل» or «نسخة تجريبية محدودة».
  - When not activated, the «تفعيل الآن» button opens `showActivationDialog(context, picpos: true)` (`lib/presentation/widgets/settings/activation_dialog.dart`).
  - The button is guarded by `system_license` with manager override (`settings_permission_tiles.dart:220-239`).
  - A second, deliberately unguarded entry exists on the trial-expired screen (`core/trial/trial_guard.dart`).
- **Machine ID:** `LicenseService.getMachineId()` (`lib/services/license_service.dart:102-129`).
  - Windows: `deviceId + computerName + numberOfCores` → SHA-256 → first 16 hex characters, uppercase.
  - Android: `androidInfo.id`. Web: `WEB_STATION`.
  - The dialog shows the ID (copyable) and accepts a pasted key.
- **Key:** `PP2-<base64url JSON>.<base64url Ed25519 signature>` (`license_service.dart:24`), payload `{v:2, machineId, issuedAt}`.
  - No expiry and no modules.
  - Verified with an embedded **public** key.
  - Issued offline with `tool/license/issue_license.dart <private-key> <machine-id>`. The private key file sits untracked in `tools/picpos-activation/` (REL-009).
- **Activation:** `LicenseService.activate(key)` (`license_service.dart:294`) stores it in secure storage `license_key` and mirrors it into DB `settings`.
  - Auto-import of `license.txt` / `activation.key` / `license.key` next to the exe (`:141-164`).
- **Trial:** 30 days, 200 invoices, 50 products, customers and suppliers, 2 users, watermark.
  - In non-demo builds the limits sit behind `AppConfig.isDemo`, so activation effectively gates only the watermark and `TrialGuard`.
  - The startup cache refresh is demo-only (REL-005).
- **First run:** the wizard never requires activation. `step_welcome.dart:124-197` shows a read-only licence banner.

## 10. Build, test, install, update (as implemented)

- **Run (dev):** `flutter run -d windows --dart-define=APP_BRAND=picpos --dart-define=APP_FLAVOR=unified`. Omitting `APP_BRAND` runs **UralCash** (BRAND-004).
- **Release (Windows):** `build_picpos.bat` runs these steps in order:
  1. Set the PicPos `BRAND_*` env.
  2. Run the `brand_picpos_test`.
  3. Copy the icon.
  4. Clean build.
  5. `flutter build windows --release` with the PicPos defines.
  6. Fail if `UralCash.exe` exists.
  7. Swap in the SQLCipher `sqlite3.dll` and `findstr sqlcipher`.
  8. Sign, optionally.
  9. Copy to `FlavorBuilds\PicPos`.
- **Installer:** `build_installer_picpos.bat` → `tool/fetch_prereqs.ps1` (VC++ hash and signature) → `ISCC /DBrandId=picpos`. Signing only if `PICPOS_SIGN_PFX` / `PICPOS_SIGN_THUMBPRINT` is set; the 3.9.2 artifacts are unsigned (REL-002).
- **Android:** `flutter build apk --release` per app. Van always debug-signs, POS falls back to debug, Admin is strict (REL-004).
- **Server:** `cd server; dart run bin/server.dart`, or Docker.
- **Tests:** about 1,374 `*_test.dart` files (unit 691, integration 160, integration_pg 26, scenarios 14, structural 117, widget 264, data 33); `scripts/run_pg_tests.dart`; `tool/run_e2e.ps1`; `scripts/gate.sh`.
- **Install:** `{autopf}\PicPos`. Data in `Documents\picpos_<flavor>.db`, `%APPDATA%\PicPos\PicPos`, `Documents\PicPos_Backups`. No registry section.
- **Update:** no in-app updater. Run the newer installer over the old one (same AppId). The schema migrates on first launch behind a non-blocking backup. Host and clients must be upgraded together; this is documented but not enforced (REL-003, SYNC-001).
- **First run:** `_SetupGate` reads `setup_completed` (`main.dart:1560-1631`). The wizard has 9 steps (standalone), 8 (mirror), 8 (server) or 6 (client).

## 11. CI (`.github/workflows/ci.yml`, the only workflow)

- **Triggers:** push to any branch, pull requests, `v*.*.*` tags.
- **Jobs:** `secrets`; `gitleaks` (advisory); `root_static` (`flutter analyze lib/` + file-size gates); `root_tests` (12 shards, coverage); `coverage_gate` (≥ 18%); `packages_and_mobile` (api_client + 3 apps); `server` (PG 16); `e2e`; `web`; `build-windows` (no brand define, no SQLCipher step, no signing); `release` (tags, publishes the zip — BRAND-003).
- **Not run in CI:** APK/AAB builds, the installer, the PicPos brand guard, analyze of `test/`, 9 packages, `integration_pg` (ARCH-006).
- The status of CI runs for HEAD was **not checked** (no remote access).

## 12. Secrets inventory (locations only; no values)

| Secret | Where | Protection |
|---|---|---|
| SQLCipher key, new installs | `flutter_secure_storage` (Windows: DPAPI user scope) + non-secret `<db>.keyinfo.json` | Windows user account |
| SQLCipher key, upgraded installs | Derived `sha256(deviceId:pepper)`; the pepper is in source | Effectively none against local readers (SEC-005) |
| Recovery envelope | `<db>.keyinfo.json` (Argon2id KEK + AES-GCM) | Recovery code |
| LAN install secret / session key / table-bill key | Secure storage (`ural_*` key names, BRAND-005) | Windows user account |
| Legacy LAN bearer | Derived from the legacy seed during the 30-day window | None (SEC-006) |
| Desktop Ed25519 admin signing seed | `CloudLinkConfigStore` secret | Secure store |
| Licence private key | `tools/picpos-activation/license_private_key.txt` (untracked, ignored, never committed) | File system only (REL-009) |
| Cloud `TOKEN_SECRET`, `ADMIN_KEY`, DB password | Environment (test values in `docker-compose.yml`) | Deployment |
| Password hashes / PIN / card code | `users` table, synced with restrictions | Argon2id; PIN never served |

## 13. Assumptions

1. The `D:\qa\logs4` run (2026-10-21) tested the same tracked content as HEAD. This is supported by file timestamps, not by a tree hash (see TEST_RESULTS §2).
2. `FlavorBuilds\PicPos` and the 3.9.2.277 installer were built from HEAD (timestamp evidence only). The installer payload equals that folder (inferred from `[Files]`).
3. The product markets are only Jordan and Egypt.
4. PG server mode ships to customers in 3.9.2. Provisioning code and the PG E2E exist; this is assumed, not confirmed.
5. Client→host LAN deployments with table reservations exist or are possible.

## 14. Open questions for the owner

The consolidated list, with the decision each one unblocks, is in [HANDOFF.md §4](<HANDOFF.md#4-open-owner-questions>). Questions answered by the owner decisions of 2026-10-23 have been removed. In particular, "may UralCash be deleted from this repository?" is answered: **yes, remove; do not preserve**.
