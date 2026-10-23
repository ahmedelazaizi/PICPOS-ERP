# Axis A — Coverage: checklist status

**Scope:** HEAD `d69be1eafc7d82b924723dfdbb53960b7e33acdb`, read-only.

**Status meanings:**

| Status | Meaning on this axis |
|---|---|
| PASS | The control was verified by reading the code at HEAD, and no defect was found in the scope read. It does **not** mean a test was executed: no test was run by this auditor. |
| FAIL | A defect was confirmed (see the finding id). |
| BLOCKED | The check could not be done; the reason is given. |
| NOT_RUN | Applicable, but deliberately not executed (for example, runtime tests not allowed because of the Flutter lock). |
| NOT_APPLICABLE | Does not apply to this product. |

**Basis of every status:**
- Static reading: git, grep and file reads.
- External sources: OSV / GitHub Advisory pages, used for the dependency check only.
- Test logs from `D:\qa\logs4`: used as secondary evidence of what others ran, with the limits in [TEST-EVIDENCE-A.md](<TEST-EVIDENCE-A.md>).

## 1. Authentication, sessions and password policy

| # | Check | Status | Reason / finding |
|---|---|---|---|
| 1.1 | Hashing algorithm and parameters | PASS with improvement | Argon2id m=4 MiB t=3 p=1 is below OWASP (SEC-010). Legacy PBKDF2 10k hashes are rehashed on login. |
| 1.2 | Constant-time compare / enumeration defence | PASS | Session HMAC, pairing code and cloud tokens use constant-time compares. A dummy Argon2 runs on unknown users (`user_dao.dart:356-369`). Exception: the legacy bearer `==` compare (SEC-006). |
| 1.3 | Default admin password handling ('admin' vs custom) | FAIL | Admin is seeded with `force_password_change=1`; the wizard sets a custom password only in standalone mode. FAIL because of SEC-001 (rename → re-created admin/admin), SEC-002 (API ignores force-change) and SEC-011 (heal without force flag). |
| 1.4 | Forced change at first login (UI) | PASS | `login_screen.dart:359-376`; the dialog is non-dismissable. |
| 1.5 | Forced change on the API path | FAIL | SEC-002. |
| 1.6 | Lockout (UI) | FAIL (partial) | 5 failures → 15 minutes in memory; persistence callbacks are never wired (SEC-009). |
| 1.7 | Lockout (API `/api/auth/*`, web session) | PASS (in-memory) | `ServerLoginThrottle`: 5 failures → 15 minutes per username or card hash. Reset on restart. |
| 1.8 | Manager override | FAIL | Self-approval (AUTHZ-001); no attempt limit (SEC-009). Password-only identification relies on the duplicate-password block (`user_dao.dart:18-39`). |
| 1.9 | Session expiry / idle lock (UI) | PASS | POS idle lock, default 5 minutes (`session_timeout_wrapper.dart:77,192`). Not executed. |
| 1.10 | API session expiry / revocation / logout | FAIL | Device tokens last 30 days with no revocation, and inactive users are not checked (SEC-003). Web tokens: 12 hours, sid/user revocation (in-memory), role-bound. |
| 1.11 | Credentials distributed to clients | FAIL | Served only to a session or inside the pairing window (PASS), but predictable temp passwords are minted on clients (SEC-004). |
| 1.12 | Cloud mobile/admin auth | PASS | Random device tokens stored hashed, rotation grace, per-request employee-active check, PIN PBKDF2 120k, login limiter, admin session revocation table. |

## 2. Authorization enforcement

| # | Check | Status | Reason / finding |
|---|---|---|---|
| 2.1 | Rule "any permission opens the screen" (`screen_access_resolver.dart`) | FAIL (consequences) | The resolver is correct as specified (strict screens: settings, users, roles). Its consequences expose list data: B-1 → AUTHZ-002, B-2 → AUTHZ-003. |
| 2.2 | Menu / allowed screens / dropdown single source (B-6) | PASS | `screen_access_selectors.dart` funnels through `screenVisibleToUser`. Not executed. |
| 2.3 | Figures masking — list and cards | PASS with regression | Masking was added on sales, parties, inventory, products and others. Regression: `sales_view` now reveals amounts (AUTHZ-004). |
| 2.4 | Figures masking — secondary views (details, statements, exports, print) | FAIL | AUTHZ-002 (details and margin), AUTHZ-003 (statement and export), AUTHZ-007 (margin for every cashier). The print button is gated by `sales_print`; whether print output masks amounts was not checked → NOT_RUN for print content. |
| 2.5 | Conditional grants (`cond:`) — table gates (B-3) | PASS (UI) / FAIL (approval) | `table_action_gate.dart` routes to approval; the approval itself is self-approvable (AUTHZ-001). |
| 2.6 | Conditional grants — API | FAIL | AUTHZ-005. |
| 2.7 | API mutation gates (`requirePermission`) and grep guard | PASS | `api_handler_perm_gate_grep_test.dart` enforces a gate or an `EXEMPT-PER-USER` marker on every mutation handler in 6 handler files plus 3 host files. Not executed by this auditor. |
| 2.8 | API read gates | FAIL | AUTHZ-006 (GET has no permission gate on device sessions). |
| 2.9 | Service/DAO-layer enforcement | FAIL (architecture) | Only critical financial ops use `PermissionEnforcer` (AUTHZ-010); booking actions are UI-only (AUTHZ-008). |
| 2.10 | Bypass via search results / deep links | NOT_RUN | No deep-link intent filters were found in the mobile manifests (only `exported=true` launcher activities). Desktop search-to-detail paths were not traced. Shortcut bypass (`F5`) is documented as fixed by `ensurePermission` funnels (not verified per screen). |
| 2.11 | Bypass via exports | FAIL | Parties export (AUTHZ-003). Other screens' exports were not traced → partial. |
| 2.12 | Bypass via printing | NOT_RUN | Print templates were not reviewed for masking. |
| 2.13 | Web mirror `/webdb` policy | PASS (partial read) | Origin check, web-session tokens (12h, sid revocation, role binding), `WebHttpReadGate` on GETs, and a write allowlist with POS paths denied (`api_auth_middleware.dart:57-266`). The `/webdb` channel internals were not read line by line. |
| 2.14 | Branch scope — client UI providers | PASS | `branchScopeProvider` is fail-closed for unassigned users; parties and invoices lists are scoped. |
| 2.15 | Branch scope — exports / secondary paths | FAIL | Parties export is unscoped (AUTHZ-003). |
| 2.16 | Branch scope — API | FAIL (partial) | Transactional GETs and sync pull are scoped and fail-closed; `GET /api/parties` is unscoped (SEC-008). |
| 2.17 | Branch scope — reports / analytics DAOs | PASS (sampled) | `allowedBranchIds` / `_buildAuthScopeFilter` present (for example `sales_analytics_dao.dart:326-359`). Full report sweep is out of scope (axis B). |
| 2.18 | Cross-tenant isolation in the cloud server | PASS | The company is derived from the authenticated device/link; device-of-other-company is refused; scoped revoke. See the FINDINGS-A positive controls. |
| 2.19 | Bootstrap-admin invariants | FAIL | Role, disable and lock are guarded; rename is not guarded, which triggers SEC-001. |

## 3. Secrets

| # | Check | Status | Reason / finding |
|---|---|---|---|
| 3.1 | SQLCipher key design (`*.keyinfo.json`, rawV2, slots) | PASS (new installs) / FAIL (upgrades) | New installs get a random 256-bit key in secure storage, with a non-secret keyinfo sidecar and a recovery envelope (Argon2id KEK + AES-GCM, per the design doc). Upgrades stay on the derivable legacy key (SEC-005). |
| 3.2 | Recovery envelope | PASS (design read) | `docs/security/db-key-design.md` §5. Code path not executed. |
| 3.3 | Pairing QR contents | PASS | LAN: host, port, one-time code, fingerprint. Admin: cloud URL, one-time code, **public** key. The prior claim is refuted (SEC-017). |
| 3.4 | Server secrets separation | PASS | `ServerSecrets` holds random independent keys; the legacy bearer exists only in its window (SEC-006). |
| 3.5 | Hard-coded credentials in source | PASS with notes | Literal `'admin'` default (by design, see 1.3); test-only secrets in `docker-compose.yml` (marked TEST); legacy pepper in `legacy_device_seed.dart` (documented as "not a secret"). Pattern `git grep` for private keys and API tokens finds only fake fixtures. |
| 3.6 | `.env.example` | PASS | Placeholders only (Supabase URL and anon key). |
| 3.7 | Gitleaks config and CI | PASS with improvement | `.gitleaks.toml` extends the defaults, with a 3-file fixture allowlist; the CI job is advisory (SEC-013). |
| 3.8 | Gitleaks history scan | NOT_RUN | `gitleaks` is not installed locally; the CI result was not accessible (no remote access). |
| 3.9 | Committed key material (`*.jks`, `*.keystore`, `key.properties`, `*.pem`, `google-services.json`) | PASS | `git ls-files` shows none (only `lib/services/db_keyinfo_file.dart`, which is code). |
| 3.10 | Untracked sensitive files at the repo root | FAIL (hygiene) | SEC-012 (operational log). Path only; values redacted. |
| 3.11 | Server login logs committed | PASS | Not tracked. |

## 4. Transport

| # | Check | Status | Reason / finding |
|---|---|---|---|
| 4.1 | TLS pinning (TlsTrust) | PASS (when pinned) / FAIL (default) | Pinned → strict fingerprint match. Unpinned → any certificate accepted; the LAN default is HTTP (SEC-007). |
| 4.2 | `badCertificateCallback => true` anywhere | PASS | All four former sites replaced by `TlsTrust` (grep). |
| 4.3 | Cloud HTTPS certificate validation (desktop) | PASS | Default `http.Client()` with system CAs. |
| 4.4 | Android manifests — `mobile`, `mobile_admin`, `mobile_pos` | PASS | Release: `usesCleartextTraffic=false`, NSC with no cleartext, `allowBackup=false`. Debug NSC allows cleartext (debug build only). |
| 4.5 | Root `android/` app manifest | NOT_RUN | Not found at `android/app/src/main` by the scan (the desktop app is the Windows target). |
| 4.6 | Cloud server TLS | NOT_APPLICABLE in code / missing requirement | It binds plain HTTP and expects external termination (SEC-014). |
| 4.7 | Desktop LAN server TLS | FAIL (default off) | SEC-007. |

## 5. Input validation and injection

| # | Check | Status | Reason / finding |
|---|---|---|---|
| 5.1 | Raw SQL interpolation in DAOs / services | PASS (sampled) | Single-line grep: only identifier interpolation from code constants or allowlists (for example `data_wipe_service`, sales analytics `sortColumn` from a boolean). Multi-line SQL was sampled, not exhaustively read. |
| 5.2 | Sync identifiers from the network (table/column names) | PASS | The table comes from an allowlist on host and client; columns are filtered to local columns (new). Residual: the filter falls back to the raw row on exception (`delta_pull_column_filter.dart:58-61`). Low risk. |
| 5.3 | LIKE escaping | PASS (partial) | `report_builder_dao` escapes; other LIKE uses bind parameters. Wildcard injection there is functional only, not a security issue. |
| 5.4 | File paths — attachments | PASS | Blobs in the DB; no filesystem write from the network name. |
| 5.5 | File paths — backup/restore | NOT_RUN | Restore verification is a design-doc claim (§4.3). Axis B covers restore. |
| 5.6 | xlsx / zip handling | PASS with improvement | archive 3.6.1 / 4.3.0 is above the fixed 3.3.8 (zip-slip CVE). No extraction to disk. No size caps (SEC-016). |
| 5.7 | PDF / print templates | NOT_RUN | Not reviewed. |
| 5.8 | Process execution | PASS with suspicion | Argument lists are used; a `cmd /c` printer-name path exists (SEC-015). |
| 5.9 | Deep links / URL handling | PASS (limited) | No intent-filter deep links in the mobile manifests. `url_launcher` call sites were not traced → partial. |

## 6. Sync

| # | Check | Status | Reason / finding |
|---|---|---|---|
| 6.1 | Version / column compatibility (v196 `party_id`, column filter) | FAIL | SYNC-001 (D-1 partly fixed), SYNC-002. |
| 6.2 | `party_id` remap for reservations / bookings (D-2) | PASS | Fixed at HEAD. Integration log `S3_integration` mentions `party_fk_remap` (8 lines). Not executed by this auditor. |
| 6.3 | Idempotency by `global_id` / idempotency key | PASS (read) | The outbox reuses a stable idempotency key per item; the host reads `x-idempotency-key` for sales, purchases and journals; attachments dedupe by `global_id`. Treasury vouchers rely on `global_id` (comment at `api_data_treasury.dart:377`). |
| 6.4 | Conflict policy | PASS with defect | Per-table policy plus financial pending-review; non-financial conflicts are dropped (SYNC-005). |
| 6.5 | Deletes / tombstones / resurrection | PASS (read) / NOT_RUN | Soft-delete `deleted_at` is applied after the conflict check; financial pending changes are kept. A resurrection scenario was not executed. |
| 6.6 | Offline replay ordering / retry / dead-letter | PASS (read) | Bounded retries, dead-letter with a UI, permanent-error classification. |
| 6.7 | Reservations push (D-3) | FAIL | SYNC-003. |
| 6.8 | Duplicate customers across devices (D-4) | FAIL (low) | SYNC-004. |
| 6.9 | Time skew | PASS (read) | The watermark uses `serverTime` from the first page; keyset cursor (ts, id). Client clock is not used for the watermark. Not executed. |
| 6.10 | Cloud replay protection / rate limiting | PASS | One-time hashed pairing codes (`FOR UPDATE`, `used_at`), push limiter 60/min, `documents_required_max_50`, body limit. Field-document dedupe by `global_id` per the server service (not read line by line). |
| 6.11 | Pull scope vs. permissions | Info | SYNC-006. |
| 6.12 | Cloud relay | FAIL (missing requirement) | SYNC-007. |
| 6.13 | WebSocket client | PASS (limited) | Uses `TlsTrust.ioClient()` (`websocket_sync_client.dart:147`); `/ws` verifies the bearer via `verifyCredential`. Message handling not read. |
| 6.14 | Mixed-fleet runtime test against a real v196 host | NOT_RUN | Requires running apps; also not done by QA (FINAL-QA-VERDICT §5). |

## 7. Dependency vulnerability posture

| # | Check | Status | Reason / finding |
|---|---|---|---|
| 7.1 | Pub advisories (OSV, 12 Pub entries) vs lockfiles | PASS | Checked 2026-10-23 04:11 +03:00. archive (fixed 3.3.8) → 3.6.1 / 4.3.0. http (fixed 0.13.3) → 1.6.0. shared_preferences_android (2.3.3 only) → 2.4.23. dio / jose / serverpod / agent_dart: not used. |
| 7.2 | crypto 3.0.7, cryptography 2.9.0, shelf 1.4.2, shelf_router 1.1.4, excel 4.0.6, pdf 3.12.0, printing 5.14.3, file_picker 11.0.2, flutter_secure_storage 9.2.4 / 11.2.0, postgres 3.5.9 / 3.5.18, drift 2.32.1, sqlite3 3.3.1 | PASS (no listed advisory) | Absence from OSV is not proof of absence. |
| 7.3 | Native SQLCipher / OpenSSL / SQLite versions bundled by `sqlcipher_flutter_libs 0.6.8` | NOT_RUN | The native version could not be determined without building or reading the plugin cache; CVE status unverified. |
| 7.4 | Webview packages | NOT_APPLICABLE | No `webview_*` package in the root lockfile. |
| 7.5 | `pub outdated` / `osv-scanner` run | NOT_RUN | `dart`/`flutter` commands are prohibited for this auditor; `osv-scanner` is not installed. |

## 8. Prior-audit items

See the FINDINGS-A table "Prior-audit items re-verified at HEAD". Summary:

| Status | Items |
|---|---|
| Still open | B-1, B-2, B-4, D-3, D-4 |
| Fixed | B-3 (UI), D-2 |
| Partly fixed | D-1 |
| Refuted | QR long-lived key |
| Confirmed missing | Cloud relay |
