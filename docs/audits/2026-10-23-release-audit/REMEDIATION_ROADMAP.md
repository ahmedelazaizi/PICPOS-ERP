# REMEDIATION_ROADMAP

The roadmap is ordered by impact, likelihood and dependency (brief §14), and grouped into Specs that can be written independently (brief §15). Finding IDs resolve in [FINDINGS.md](<FINDINGS.md>). Sizes come from the axis files and are rough; uncertainty is noted where large. XS < 0.5 d, S ≈ 0.5–1 d, M ≈ 2–4 d, L > 1 week.

**Rule for every item:** a finding is closed only by verification evidence (a test, a repro, or an artifact scan) recorded in the traceability table in §6, never by a code change alone.

## 1. G0 — release blockers (P0), in execution order

| # | Item | Findings | Components | Acceptance (testable) | Depends on | Size |
|---|---|---|---|---|---|---|
| G0.1 | **Repro first.** Decide whether two provisional blockers stay. | RPT-001, REL-005 | Party statement DAO; trial/licence cache, receipt and PDF printers | <ul><li>RPT-001: void a credit sale; statement closing ≠ card/GL confirms it (otherwise downgrade).</li><li>REL-005: fresh-launch print preview shows or does not show the trial banner on an activated machine.</li></ul> | An isolated test DB and a running app | XS each |
| G0.2 | **Brand guard before brand fixes** (SPEC-01 step B0). | BRAND-012 | `tool/check_brand_artifact.ps1` (new), `build_picpos.bat`, CI `build-windows`, `brand_picpos_test` in CI | The scan **fails** on today's `FlavorBuilds\PicPos` (it reports `logo.PNG`, `en.json`) | — | S |
| G0.3 | **Remove UralCash from the shipped artifact and from build defaults** (SPEC-01 B1–B2). Disable the CI `release` job until it uses the shared script. | BRAND-001, BRAND-002, BRAND-004, BRAND-003 (alias REL-001) | `pubspec.yaml` assets, `en.json`, `catalog_ar.json`, `brand.dart`, `windows/CMakeLists.txt`, `Runner.rc`, `main.cpp`, `.github/workflows/ci.yml` | <ul><li>The G0.2 scan passes on a new build.</li><li>A build with no defines yields `PicPos.exe` / CompanyName `PicPos`.</li><li>The CI tag artifact has `sqlcipher` in `sqlite3.dll` and FileVersion = pubspec.</li></ul> | G0.2 | S–M |
| G0.4 | **Manager-approval integrity** (SPEC-03). | AUTHZ-001 | `permission_guard.dart` (`_verifyPassword`, `requestManagerApproval`) | Widget tests: own password denied; another conditional holder denied; an unconditional holder or system admin approved | — | XS–S |
| G0.5 | **Masking on every view of the same data** (SPEC-04). | AUTHZ-002, AUTHZ-007, AUTHZ-003 (alias RPT-006) | `sales_invoice_dialogs.dart`, `parties_picpos_screen.dart`, `PartyStatementPicposScreen`, `excel_service.dart` (party/product export and import), `csv_import_export_service.dart`, `customer_picker_card.dart`, `party_statement_export_picpos.dart`, `financial_figures_access.dart` | <ul><li>Role `{sales_create}` sees no amounts or margin in details.</li><li>Role `{customers_add}` cannot open statement or export, and export rows ⊆ branch scope.</li><li>Masked cells in exports, picker and statement print.</li><li>A structural test that every money widget or export on a figure-masked screen uses the predicate.</li></ul> | Owner Q4 (keep the "hide figures" claim?) and Q5 (AUTHZ-004/009 rules) | M |
| G0.6 | **Currency correctness at first run and on POS** (SPEC-05). | UX-001, UX-002 | `step_company_info.dart:51-58`, `CurrencyInfo.fromCode`, `SystemCurrencyNotifier`, the 15+ literal sites | <ul><li>Wizard shows JOD and EGP only.</li><li>`fromCode('SAR')` throws.</li><li>`system_currency` ∈ {JOD, EGP}.</li><li>A structural guard finds no currency literals in `lib/presentation/**`.</li><li>An EGP widget test shows `ج.م` on `ProductCard` and `ReturnDetailsPanel`.</li></ul> | — (the first-run redesign later reuses this) | S–M |
| G0.7 | **Statement and PG report correctness** (SPEC-06). | RPT-001 (if confirmed by G0.1), RPT-003 | `party_transactions_dao.dart`, `parties_repository_impl.dart:114-160`, `party_reconciliation_dao.dart:57-114` | <ul><li>Voided, deleted fixture: statement closing = `parties.balance` = GL sub-account.</li><li>A `test/integration_pg` case for `getArAgingReport` matches SQLite.</li></ul> | G0.1 | S + S |
| G0.8 | **Deterministic activation state** (SPEC-12). | REL-005 (if confirmed by G0.1) | `app_main_screen_lifecycle.dart`, `trial_state.dart`, `license_service.dart` | A test with startup, no Settings visit and an activated key gives `showWatermark == false`; with no key, the banner shows consistently | G0.1; owner Q6 | XS |
| G0.9 | **Bootstrap-admin and forced-change integrity** (SPEC-02, part 1). | SEC-001, SEC-002 | `api_get_users.dart`, `user_dao.dart:225-259`, `edit_user_dialog.dart`, `api_auth_handler.dart:76-208` | <ul><li>Rename id 1 + `GET /api/users` → no new `admin` row.</li><li>A flagged user gets 403 or a change-only token from both handlers.</li></ul> | Owner Q8 (is renaming the admin supported?) | S |
| G0.10 | **Mixed-fleet safety for 3.9.2** (SPEC-09, release-now part). | SYNC-001 | v196 migration (client watermark reset), release notes | <ul><li>After the v196 migration the `table_reservations` watermark is reset.</li><li>The release note mandates a simultaneous upgrade of host and clients.</li><li>Integration test: a v195-shaped client surfaces the error and does not advance.</li></ul> | — | S |
| G0.11 | **Restore proven** (SPEC-07, part 1). | BKP-001 | `connection_io.dart` backup, `pending_restore.dart`, `db_key_startup.dart` | <ul><li>An integration test: encrypted DB with data → backup → mutate → restore → simulated reboot → rows and key verified.</li><li>A manual drill log in `docs/handoff/`.</li></ul> | — | M |
| G0.12 | **Distribution integrity** (SPEC-11, part 1). | REL-002, REL-004 | Code-signing certificate and `build_installer_picpos.bat` fail-closed; `mobile/` and `mobile_pos/` Gradle signing | <ul><li>`Get-AuthenticodeSignature` Valid on the setup exe, `PicPos.exe`, `sqlite3.dll`.</li><li>A release build without an identity fails.</li><li>`flutter build apk --release` fails without `key.properties` in all apps.</li></ul> | Certificate procurement (external lead time, **unknown**) | S + lead time |
| G0.13 | **Release verification on the exact tree.** | All of the above; ARCH-004 | Whole repo | <ul><li>Analyze reports 0 issues.</li><li>Full suite (S1–S6 equivalents) green on the commit that is built.</li><li>Artifact scan green.</li><li>Clean-VM install, upgrade over 3.9.1 and uninstall logged.</li></ul> | G0.2–G0.12 | 2–3 d |

**G0 rough total:** ≈ 17–25 engineer-days, excluding certificate lead time. G0.4, G0.6, G0.9, G0.10 and G0.11 are independent and can run in parallel. G0.3 needs G0.2. G0.7 and G0.8 need G0.1. G0.13 is last.

## 2. G1 — must fix before wider rollout (P1)

| Item | Findings | Components | Acceptance | Depends on | Size |
|---|---|---|---|---|---|
| Token lifecycle and API identity | SEC-003, AUTHZ-005 | `api_session_token.dart`, `api_user_context.dart`, `permissions_dao.dart:117-131` | Deactivate, lock or change password → old token 401; a conditional-grant API call → 403 `approval_required` | G0.9 | S–M |
| Credentials on clients | SEC-004 | `delta_pull_service.dart:1280-1309`, `user_sync_strategy.dart:131` | Login with `<username>123` fails; the row is marked locked or pending | — | S |
| Unauthenticated LAN reads and parties scope | SEC-008 | `api_get_sync_pull.dart`, `api_sync_pull_tables.dart`, `api_get_directory.dart` | A tokenless pull of parties has no balance; a branch-limited session sees only its parties | — | S |
| Sync integrity | SYNC-002, SYNC-005, SYNC-003 (alias DATA-001, cond.) | `delta_pull_service.dart`, `offline_sync_worker_drain.dart`, reservations CWI and host route | <ul><li>A bad row keeps the watermark and logs a failure.</li><li>A conflict is not marked synced.</li><li>Client reservations appear on the host with the same `global_id`.</li></ul> | G0.10 | M + M |
| Import integrity | DATA-003 | `excel_service.dart` party import | Re-import after a credit sale leaves balance = GL | G0.5 (same file) | S |
| Fixed-asset depreciation cap (cond.) | ACC-001 | `fixed_assets_dao_ext.dart:460-482` | Month `life*12+1` → 0 posted; salvage respected | — | S |
| Newer-DB guard | MIG-001 | `database_migrations.dart`, `pending_restore.dart` | `user_version = 999` → typed exception, version unchanged | — | S |
| Brand clean-up beyond the artifact (owner decision 1: **remove, do not preserve**) | BRAND-005, BRAND-007, BRAND-008, BRAND-009, BRAND-011 (answer), BRAND-010 (customer PG guide part) | Installer, scripts, icons, `lib/` brand forks incl. the legacy setup wizard path, secure-storage key names (read old / write new), `tools/postgresql_setup_guide.md` | <ul><li>`git grep -i -E "uralcash\|monexia\|uraljo\|يورال" -- lib installer windows tool build_*.bat` returns 0 (pipes escaped for the table).</li><li>Golden tests on derived salts and keys are unchanged.</li><li>An existing v196 DB still opens.</li></ul> | G0.3; owner Q1 | M–L (B5 is high risk if done wrong) |
| Currency formatting and selection | UX-003, UX-004 | `number_utils.dart`, wizard currency default | `formatAmount` follows `setCurrency`; Next stays disabled with no currency chosen | G0.6 | S |
| Wizard data round-trip | UX-005 (verify) | `step_company_info`, `step_review` | An Arabic name round-trips to settings | — | XS |
| CI coverage | ARCH-006, ARCH-004 | `ci.yml` | <ul><li>APK release builds fail on debug signing.</li><li>Brand scan job.</li><li>`picpos_rules` / `picpos_device` / `picpos_ui` tests.</li><li>`integration_pg`.</li><li>Analyze reports 0 issues.</li></ul> | G0.2, G0.12 | M |
| Swallowed exceptions on money and sync paths | ARCH-001 (incl. fail-open `sales_return_provider.dart:171`) | 15 listed sites + ratchet test | Listed sites rethrow or log; a test for the null-branch case | — | M |
| DB key on upgraded installs | SEC-005 | Upgrade prompt for key migration | A banner persists while the key kind is legacy | Owner Q9 | S |
| SQLCipher package EOL | DEP-001 | DB engine dependency | An existing encrypted v196 DB opens after the migration; the artifact DLL contains SQLCipher | G0.11 (restore test as a safety net) | M (uncertain) |
| Update path | REL-003 | Installer / pre-migration backup class | A failed backup blocks the migration; pre-migration backups survive rotation | MIG-004 | S–M |
| Repo hygiene | SEC-012, REL-009 | Untracked log and private key | Not present in the working tree, or ignored; issuance procedure documented | — | XS |
| Masking rule decisions | AUTHZ-004 (and AUTHZ-009 in G2) | `any_permission_masked_text.dart`, `financial_figures_access.dart` | Tests follow the owner's rule | Owner Q5 | XS |

## 3. G2 — important (P2)

- **Accounting and reports:**
  - ACC-002, ACC-004, ACC-005, ACC-006
  - RPT-002, RPT-004, RPT-005, RPT-007
  - DATA-005, DATA-006
  - DATA-002 (owner Q7)
- **Migrations and backup:** MIG-002, MIG-003, MIG-004, MIG-006, MIG-007, BKP-002, BKP-003, BKP-004 (PG operator backup, or provision `pg_dump`).
- **LAN and API hardening:** SEC-006, SEC-007 (TLS by default + pin), SEC-009, SEC-010, SEC-011, AUTHZ-006, AUTHZ-008, AUTHZ-009, AUTHZ-010 (structural test), SYNC-004.
- **UX:** UX-006, UX-007, UX-008, UX-009.
- **Architecture:** ARCH-002, ARCH-003, ARCH-005.
- **Brand:** BRAND-006 (package rename after the branches merge), BRAND-010 (non-shipped content).
- **Release and dependencies:** REL-006, REL-007, REL-008, DEP-002.
- **Cloud:** SEC-014 (before any cloud production use), SYNC-007 (relay; a product decision).

## 4. G3 — optional / backlog (P3)

- **Security:** SEC-013, SEC-015, SEC-016, SEC-017 (signing-key rotation).
- **Sync:** SYNC-006 (document).
- **Data and accounting:** DATA-004, DATA-007, DATA-008, ACC-003, ACC-007, ACC-008, ACC-009, ACC-010.
- **Reports:** RPT-008, RPT-009.
- **Migrations and backup:** MIG-005, BKP-005 (after security analysis).
- **Architecture and dependencies:** ARCH-007, DEP-004. DEP-003 is info, with no action.

## 5. Proposed Spec groups (brief §15)

Each Spec has one goal and does not bundle unrelated problems. When written, every Spec must contain the brief §15 sections:
- problem, evidence and finding IDs;
- current and required behaviour;
- scope and out-of-scope;
- proposed changes, alternatives and decisions;
- impact on UI, data, security and integrations;
- failure, compatibility, migration and rollback;
- acceptance and tests;
- dependencies and order.

| Spec | Goal | Scope (findings) | Out of scope | Group |
|---|---|---|---|---|
| **SPEC-01 Brand purge and artifact guard** | The artifact and repository are PicPos-only, proven by an automated scan | BRAND-001…012, REL-001 (via BRAND-003). Steps B0–B8 of [FINDINGS-C](<axis-C-product-ux-release/FINDINGS-C.md#L302>), with owner decision 1 applied: delete, do not move to a branch. | Renaming runtime data identifiers (`picpos_*` stay) | G0 (B0–B2), G1 (B3–B5, B7 guide), G2 (B6–B7) |
| **SPEC-02 Admin and credential lifecycle** | No account ever has a known or guessable password without forced rotation on every path | SEC-001, SEC-002, SEC-004, SEC-009 (lockout persistence), SEC-010, SEC-011; the password policy used by setup (min length) | Approval flows (SPEC-03) | G0 (SEC-001/002), G1, G2 |
| **SPEC-03 Approval integrity** | Conditional permissions always need a *different*, unconditionally authorised approver, on UI and API | AUTHZ-001, AUTHZ-005, SEC-009 (override attempt limit) | Figure visibility | G0, G1 |
| **SPEC-04 Figure visibility everywhere** | One predicate governs every view, export, print and picker of money figures | AUTHZ-002, AUTHZ-003 (+ RPT-006), AUTHZ-004, AUTHZ-007, AUTHZ-009, AUTHZ-010 (structural test) | Balance overwrite on import (SPEC-08) | G0, G1, G2 |
| **SPEC-05 Currency correctness** | The only currencies offered are fully supported ones; every label follows the system currency | UX-001, UX-002, UX-003, UX-004, ACC-010; ARCH-002 rounding part (JOD 3 dp) | e-invoice payloads | G0, G1, G3 |
| **SPEC-06 Statement and report filters** | Every report applies the same live-document predicate and runs on both engines | RPT-001, RPT-002, RPT-003, RPT-004, RPT-005, RPT-007, RPT-008, RPT-009, ACC-006, ACC-007 | Posting logic (SPEC-13) | G0, G2, G3 |
| **SPEC-07 Backup, restore and migration safety** | Backups are restorable and proven; upgrades and rollbacks cannot silently corrupt or lose data | BKP-001…005, MIG-001…007, REL-003, SEC-005, DEP-001 | PG operational backup tooling beyond docs (decide in Spec) | G0 (BKP-001), G1, G2 |
| **SPEC-08 Import/export integrity** | Imports never bypass the ledger or validation; exports are injection-safe | DATA-003, DATA-006, DATA-007, DATA-008, SEC-016 | Export permission gating (SPEC-04) | G1, G2, G3 |
| **SPEC-09 Sync integrity and fleet compatibility** | No row is lost or dropped silently; versions are negotiated | SYNC-001, SYNC-002, SYNC-003 (+ DATA-001), SYNC-004, SYNC-005, DATA-002 | Cloud relay (SPEC-16) | G0 (release-now part), G1, G2 |
| **SPEC-10 LAN API and device hardening** | LAN devices and sessions are revocable, scoped and authorised; pairing has a dedicated permission | SEC-003, SEC-006, SEC-007, SEC-008, AUTHZ-006, AUTHZ-008, SYNC-006 (doc); new permission `devices_pair_manage` (warehouse plan W0) | Warehouse app features | G1, G2 |
| **SPEC-11 Release pipeline and distribution** | Every distributed binary is reproducible, guarded, signed and versioned consistently | REL-002, REL-004, REL-007, REL-008, ARCH-004, ARCH-006, SEC-013, DEP-002, SEC-012 | Brand content (SPEC-01) | G0, G1, G2 |
| **SPEC-12 Activation determinism** | The licence state shown and printed is a pure function of the stored licence, independent of navigation | REL-005, REL-006, REL-009 | First-run setup (activation stays in Settings, owner decision 2) | G0, G1 |
| **SPEC-13 Posting correctness** | Each auto-posted module posts exactly once, atomically, to the right accounts | ACC-001, ACC-002, ACC-003, ACC-004, ACC-005, ACC-008, ACC-009, DATA-005 | Report queries (SPEC-06) | G1, G2, G3 |
| **SPEC-14 UX consistency** | Arabic UI terminology, navigation and confirmations are consistent | UX-005…009 | Currency (SPEC-05) | G1, G2 |
| **SPEC-15 Code health** | Failures surface; caches invalidate; tests measure behaviour | ARCH-001, ARCH-003, ARCH-005, ARCH-007, DATA-004, DEP-004, SEC-015 | — | G1, G2, G3 |
| **SPEC-16 Cloud production readiness** | A cloud deployment is secure and its features match the claims | SEC-014, SYNC-007, SEC-017 | LAN | G2, G3 |
| Feature Spec **FR-SETUP** | First-run setup redesign | UX-010; consumes SPEC-02 and SPEC-05 | Activation (owner decision 2) | After G0 |
| Feature Spec **WH-APP** | Warehouse mobile app | UX-011; consumes SPEC-10 and SPEC-11 as W0 gates | Cloud relay | After G1 items it depends on |

The two feature plans were reconciled with the owner decisions and this audit on 2026-10-23: [first-run plan](<../../plans/2026-10-23-first-run-setup-redesign-plan.md>), [warehouse plan](<../../plans/2026-10-23-warehouse-app-plan.md>).

## 6. Traceability skeleton (Finding → Spec → Task → Change → Verification → Closure)

Fill one row per finding as work proceeds.
- **Change** = commit SHA or PR.
- **Verification** = the test name or repro log that demonstrates the fix on the release tree.
- **Closure** is one of `OPEN` / `IN_PROGRESS` / `FIXED_UNVERIFIED` / `VERIFIED_CLOSED` / `WONT_FIX (owner)` / `NOT_REPRODUCED`.

The working-tree edits made by another session from 2026-10-23 04:35 onward (TEST_RESULTS §6; 43 tracked files by ≈ 04:55) are **not** recorded as changes here until they are committed and verified.

| Finding | Spec | Task | Change | Verification | Closure |
|---|---|---|---|---|---|
| RPT-001 | SPEC-06 | G0.1 repro → G0.7 fix | — | — | OPEN |
| REL-005 | SPEC-12 | G0.1 repro → G0.8 fix | — | — | OPEN |
| BRAND-012 | SPEC-01 | G0.2 | — | — | OPEN |
| BRAND-001 | SPEC-01 | G0.3 | — | — | OPEN |
| BRAND-002 | SPEC-01 | G0.3 | — | — | OPEN |
| BRAND-004 | SPEC-01 | G0.3 | — | — | OPEN |
| BRAND-003 / REL-001 | SPEC-01 / SPEC-11 | G0.3 | — | — | OPEN |
| AUTHZ-001 | SPEC-03 | G0.4 | — | — | OPEN |
| AUTHZ-002 (+AUTHZ-007) | SPEC-04 | G0.5 | — | — | OPEN |
| AUTHZ-003 / RPT-006 | SPEC-04 | G0.5 | — | — | OPEN |
| UX-001 | SPEC-05 | G0.6 | — | — | OPEN |
| UX-002 | SPEC-05 | G0.6 | — | — | OPEN |
| RPT-003 | SPEC-06 | G0.7 | — | — | OPEN |
| SEC-001 | SPEC-02 | G0.9 | — | — | OPEN |
| SEC-002 | SPEC-02 | G0.9 | — | — | OPEN |
| SYNC-001 | SPEC-09 | G0.10 | — | — | OPEN |
| BKP-001 | SPEC-07 | G0.11 | — | — | OPEN |
| REL-002 | SPEC-11 | G0.12 | — | — | OPEN |
| REL-004 | SPEC-11 | G0.12 | — | — | OPEN |
| UX-010 | FR-SETUP | Plan reconciled 2026-10-23 | `docs/plans/2026-10-23-first-run-setup-redesign-plan.md` (uncommitted) | Owner review of the plan | IN_PROGRESS |
| UX-011 | WH-APP | Plan reconciled 2026-10-23 | `docs/plans/2026-10-23-warehouse-app-plan.md` (uncommitted) | Owner review of the plan | IN_PROGRESS |
| *(all other findings)* | per §5 | per §2–§4 | — | — | OPEN |
