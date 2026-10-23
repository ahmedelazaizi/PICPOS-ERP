# Axis A — Test evidence: what was run, read, and not run

| Item | Value |
|---|---|
| Auditor | Axis A (security / auth / permissions / sync), read-only |
| Date | 2026-10-23 (local +03:00); dependency check stamped 2026-10-23 04:11 +03:00 |
| HEAD | `d69be1eafc7d82b924723dfdbb53960b7e33acdb` |
| Shell | PowerShell (read-only commands only) |
| Prohibited and not run | Any `flutter` or `dart` command (Flutter lock shared with other workers) |

## 1. Commands executed and observed output

All of the following were executed by this auditor. Outputs are summarised; secret values are never shown.

| # | Command (abridged) | Observed result |
|---|---|---|
| C1 | `git rev-parse HEAD; git branch --show-current; git status --porcelain; git log --oneline -5` | HEAD `d69be1ea…`, branch `feat/tables-reservations-permissions`. Untracked only: `Cairo,Noto_Naskh_Arabic/`, root `*.txt` scratch files, 2 plan docs, 2 Arabic folders, `طلب مراجعه.txt`. Exit 1 came from `Get-ChildItem docs/audits` being absent at the time (benign). |
| C2 | `git log -6 --format="%h %ci %s"` | The candidate commits are all at 2026-10-23 03:08 +0300; the base `c5f5056c` is at 2026-10-17. |
| C3 | `git diff --stat c5f5056c..HEAD -- lib server mobile* packages` | 107 files, +5178/−1032. The security-relevant new files are listed in PROJECT_BASELINE-A. |
| C4 | `git diff c5f5056c..HEAD -- lib/services/delta_pull_service.dart` | D-2 remap added (`table_reservations`, `bookings`) and the column filter wired. |
| C5 | `git diff c5f5056c..HEAD -- lib/presentation/sales_invoices_picpos …` | The masking code changed from `salesAmountsView` to `kSalesFiguresCodes = [salesView, salesAmountsView]` (AUTHZ-004). |
| C6 | `git show c5f5056c:lib/presentation/sales_invoices_picpos/screens/sales_invoice_dialogs.dart \| Select-String ProfitMarginAnalysisWidget` | Present at base line 150, so AUTHZ-007 is pre-existing. |
| C7 | `git ls-files \| Select-String '(\.env\|docker-compose\|gitleaks\|\.jks$\|\.keystore$\|key\.properties\|\.p12$\|\.pem$\|\.pfx$\|google-services\|keyinfo)'` | `.env.example`, `.gitleaks.toml`, `docker/docker-compose.yml`, `lib/services/db_keyinfo_file.dart`. No key material. |
| C8 | `git grep -n -I -E "BEGIN (RSA \|EC \|OPENSSH )?PRIVATE KEY\|AKIA…\|sk_live_\|xox[bp]-\|eyJhbGciOi…"` | 4 hits: 3 in `docs/security/part3-secrets-supplychain.md` (the documentation of the scan patterns) and 1 in `test/services/network_service_tls_test.dart:62` (a `'-----BEGIN PRIVATE KEY-----\nfake\n'` fixture). No real secrets. |
| C9 | `Get-Command gitleaks` | Not installed. History scan → NOT_RUN. |
| C10 | Android manifests and `network_security_config*.xml` scan for `mobile/`, `mobile_admin/`, `mobile_pos/` | Release: `usesCleartextTraffic="false"`, NSC `cleartextTrafficPermitted="false"`, `allowBackup="false"`. Debug NSC allows cleartext. |
| C11 | Lockfile version extraction (regex over `pubspec.lock`, `server/`, `mobile*/`) | Versions recorded in COVERAGE-A §7. |
| C12 | `web_fetch https://osv.dev/list?ecosystem=Pub` | 12 Pub advisories listed (dio_http2_adapter, jose, shared_preferences_android, agent_dart, serverpod ×2, archive ×2, dio, personnummer, http, plus one cross-ecosystem). Source: [OSV Pub list](https://osv.dev/list?ecosystem=Pub). |
| C13 | `web_fetch https://osv.dev/vulnerability/GHSA-9v85-q87q-g4vg` | archive path traversal, fixed in 3.3.8. Locked: 3.6.1 (root), 4.3.0 (mobile). Not affected. [OSV](https://osv.dev/vulnerability/GHSA-9v85-q87q-g4vg) |
| C14 | `web_fetch https://osv.dev/vulnerability/GHSA-3hpf-ff72-j67p` | shared_preferences_android affected 2.3.3 only, fixed 2.3.4. Locked 2.4.23. Not affected. [OSV](https://osv.dev/vulnerability/GHSA-3hpf-ff72-j67p) |
| C15 | `web_fetch https://github.com/advisories?query=ecosystem%3Apub` | The page was truncated before the results. Not used as evidence. |
| C16 | Classification scan of `صور لاعادة تصميم الشاشات الموضحه/picpos_login_log_server.txt` (counts only, redacted lines) | 115,169 bytes, 1,077 lines. 0 IPv4. 0 hash-like strings. About 116 user mentions. 5 "token/session" and 1 "password" keyword matches, all log-message keywords with no values (redacted output reviewed). `git check-ignore` exit 1, so not ignored. |
| C17 | Single-line interpolated `custom*(` SQL grep over `lib/data/database/daos`, `lib/services` | 5 hits, all identifier interpolation from code (PRAGMA on known tables, wipe service). |
| C18 | Broad `LIKE '%$…` / `ORDER BY $…` grep | 144 hits, mostly non-SQL string building. The SQL ones inspected (`sales_analytics_dao.dart:331,361`) are safe constants. |
| C19 | `Get-Content D:\qa\logs4\_summary.txt`, `S0_analyze.log` | See §3. |
| C20 | Log presence checks (`Select-String -SimpleMatch`) for test-name fragments in `S1_main.log`, `S3_integration.log`, `S6_pg.log` | See §3 for the limits. |

## 2. Files read (primary evidence)

**Authentication and sessions**

- `lib/services/api/api_auth_middleware.dart`
- `api_session_token.dart`
- `api_user_context.dart`
- `api_auth_handler.dart`
- `server_login_throttle.dart`
- `lan_pairing_service.dart` (lines 1-180 and 380-560)
- `lib/services/login_rate_limiter.dart`
- `lib/services/security_service.dart` (parameter grep)
- `lib/services/legacy_device_seed.dart`
- `lib/services/db_key_boot.dart` (lines 100-325)
- `lib/data/database/daos/user_dao.dart` (lines 1-60, 225-524)
- `lib/data/database/daos/permissions_dao.dart` (lines 110-323)
- `lib/data/database/database_startup.dart` (lines 610-889, 1225-1273)
- `lib/services/api/routes/api_get_users.dart` (complete)
- `lib/services/api/data/api_data_users_roles.dart` (lines 70-139)
- `lib/core/auth/bootstrap_admin.dart`
- `lib/presentation/screens/settings/widgets/edit_user_dialog.dart`
- `lib/presentation/screens/login_screen.dart` (lines 350-379)
- `lib/presentation/screens/setup_wizard/setup_finish_runner.dart` (lines 300-349)
- `setup_persistence_riverpod.dart` (lines 90-169)

**Permissions**

- `lib/core/permissions/screen_access_resolver.dart`
- `financial_figures_access.dart`
- `lib/data/providers/screen_access_selectors.dart`
- `financial_figures_providers.dart` (diff)
- `lib/presentation/screens/tables/table_action_gate.dart`
- `table_operations.dart` (lines 1-80, 870-959)
- `lib/presentation/widgets/permission_guard.dart` (lines 584-896)
- `lib/presentation/widgets/any_permission_masked_text.dart`
- Sales invoices PicPos: `sales_invoices_table.dart` (lines 20-59, 664-713) and `sales_invoice_dialogs.dart` (lines 20-248)
- `lib/presentation/parties_picpos/screens/parties_picpos_screen.dart` (lines 150-209)
- `lib/presentation/screens/parties/party_dialogs.dart` (lines 960-1079)
- `lib/data/services/excel_service.dart` (lines 902-1011)
- `lib/core/permissions/role_grant_matrix.dart` (lines 160-209)
- `lib/data/providers/branch_scope_provider.dart`
- `parties_providers.dart` (lines 85-123)
- `test/unit/api_handler_perm_gate_grep_test.dart`

**API and sync**

- `lib/services/api/routes/api_get_sync_pull.dart`
- `api_sync_pull_tables.dart` (lines 180-259)
- `api_branch_scope.dart` (lines 60-209)
- `api_get_directory.dart` (lines 1-80)
- `api_routes_read.dart`
- `lib/services/api/data/api_data_attachments.dart` (lines 60-159)
- `lib/services/delta_pull_service.dart` (lines 40-129, 650-874, 1020-1359)
- `lib/services/delta_pull_column_filter.dart`
- `lib/services/offline_sync_worker/offline_sync_worker_drain.dart` (lines 230-389)
- `lib/services/table_session_service.dart` (lines 170-229)
- `lib/data/database/daos/tables_dao.dart` (lines 610-659)

**Transport and secrets**

- `lib/services/tls_trust.dart`
- `tls_trust_client_io.dart`
- `lib/services/network_service.dart` (lines 740-819)
- `lib/presentation/settings_picpos/screens/linked_devices_section.dart` (lines 700-839)
- `lib/services/admin_snapshots/admin_signing_key.dart`
- `.env.example`
- `.gitleaks.toml`
- `.github/workflows/ci.yml` (lines 35-79)
- `docker/docker-compose.yml`
- `docs/security/db-key-design.md` (headings and key lines)

**Cloud server**

- `server/bin/server.dart`
- `server/lib/src/http/app.dart`
- `admin_routes.dart`
- `server/lib/src/security.dart`
- `service/auth_service.dart`
- `admin_service.dart` (grep)
- `picpos_cloud.dart` (grep)

**Other**

- `lib/services/cash_drawer_service_io.dart` (lines 55-242)
- `lib/services/cfd/cfd_hdmi_transport.dart` (lines 150-194)
- `lib/services/profit_margin_analysis_service.dart` (lines 50-99)

**Earlier evidence (not trusted without re-verification)**

- `D:\qa\reports\Q-review.md`
- `D:\qa\reports\FINAL-QA-VERDICT.md`

## 3. Secondary evidence: green run logs in `D:\qa\logs4` (not executed by me)

`_summary.txt` reports:

| Stage | Exit | Result | Duration |
|---|---|---|---|
| S0 analyze | 0 | 2 info-level lints (`use_build_context_synchronously` in the purchase/sales returns logic). "Clean" means no warnings or errors, not zero issues. | 0.3 min |
| S1 main | 0 | +10018 pass, ~19 skipped | 25.8 min |
| S2 scenarios | 0 | +61 pass | — |
| S3 integration | 0 | +1018 pass, ~27 skipped | — |
| S4 brand | 0 | +13 pass | — |
| S5 e2e | 0 | +2 pass in that run. The brief cites "E2E 48 pass" from an earlier full run (FINAL-QA-VERDICT); not in this log set. | — |
| S6 PostgreSQL | 0 | +92 pass | — |

**Limits:**

1. **Timing.** The logs ran on 2026-10-21 01:45–02:53. The HEAD commits are stamped 2026-10-23 03:08.
   - The relevant source and test files existed before the run (file creation times on 10/20).
   - Nothing proves the tested tree equals HEAD byte for byte. There is no tree hash in the logs.
2. **Reporter format.** The compact reporter overwrites lines with carriage returns, so per-test presence cannot be extracted reliably.
   - Fragments found: `conditional_permission` (S1), `delta_pull` (S1), `go_blockers_tls` (S1), `bootstrap_admin` (S1), `party_fk_remap` (S3), `sync_pull` (S3, S6).
   - Fragments not found: `screen_access_resolver`, `table_action_gate`, `financial_figures`, `api_handler_perm_gate`.
   - "Not found" is **not** evidence that these tests did not run.
3. **Coverage gaps.** No log covers the scenarios behind AUTHZ-001/002/003, SEC-001/002/003/004 or SYNC-001. These are untested behaviours, not test failures.

## 4. Dependency check record

**Date:** 2026-10-23 04:11 +03:00.

**Sources:**
- [OSV Pub ecosystem list](https://osv.dev/list?ecosystem=Pub)
- [GHSA-9v85-q87q-g4vg](https://osv.dev/vulnerability/GHSA-9v85-q87q-g4vg)
- [GHSA-3hpf-ff72-j67p](https://osv.dev/vulnerability/GHSA-3hpf-ff72-j67p)

**Result:** no listed Pub advisory affects the locked versions of the root app, server or mobile apps.

**Not verifiable (NOT_RUN):**
- Native SQLCipher / OpenSSL / SQLite bundled by `sqlcipher_flutter_libs 0.6.8`.
- Transitive advisories outside OSV.
- `osv-scanner` or `dart pub outdated --show-all` (tooling unavailable or prohibited).

## 5. Not run, and why

| Item | Reason |
|---|---|
| Any unit, widget or integration test, including the proposed acceptance tests in FINDINGS-A | `flutter`/`dart` prohibited (lock conflict with other workers) |
| Runtime repros of SEC-001/002/003/004, AUTHZ-001/002/003, SYNC-001/005 | Same reason; no running app or host available to this auditor |
| Gitleaks full-history scan | Tool not installed |
| Remote branch / CI status | No fetch performed (read-only; remote state unknown) |
| Print-template masking review, deep-link / `url_launcher` sweep, PDF template review | Time-boxed; listed as NOT_RUN in COVERAGE-A |
| Opening any SQLCipher DB | Not attempted (user data; read-only policy) |

## 6. Files created by this auditor

All files are under `docs/audits/2026-10-23-release-audit/axis-A-security-sync/`:

- `FINDINGS-A.md`
- `COVERAGE-A.md`
- `TEST-EVIDENCE-A.md`
- `PROJECT_BASELINE-A.md`

No product code, configuration or other audit-axis file was modified. The sibling `axis-B-data-accounting/` directory was created by another session and was left untouched.
