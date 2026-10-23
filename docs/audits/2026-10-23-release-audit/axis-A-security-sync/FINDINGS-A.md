# Axis A — Findings: security, authentication, permissions, sync

| Item | Value |
|---|---|
| Repo / branch | `D:\PICPOS-ERP` / `feat/tables-reservations-permissions` |
| HEAD audited | `d69be1eafc7d82b924723dfdbb53960b7e33acdb` (`chore(release): QA fixes, i18n keys, docs, version 3.9.2+277`) |
| Candidate range | `c5f5056c..d69be1ea` (4 commits, 2026-10-23 03:08 +0300) |
| Working tree | Untracked scratch files and folders only; no tracked file modified |
| Method | Read-only: git, file reading, grep, PowerShell. No `flutter`/`dart` command was run. No test was executed by this auditor. |
| Evidence tags | **[V]** = verified by reading the cited code at HEAD. **[I]** = inferred (runtime behaviour not executed). **[R]** = reported by an earlier audit and not re-verified. |

## How to read this file

- **Type**: Confirmed defect, Suspicion (needs verification), Missing requirement, or Improvement.
- **Severity** is the impact if the issue is exploited or triggered. **Priority** is the order of remediation.
  - Severity scale: Critical / High / Medium / Low / Info.
  - Priority scale: P0 (before release) / P1 (before scale-out) / P2 (important) / P3 (optional).
- **Release-blocking rule used on this axis:** a finding blocks the release when either:
  - (a) it is a confirmed defect with a plausible trigger in a normal deployment that defeats an authentication or authorization control; or
  - (b) it is a control that this candidate claims to add or fix, but the control is bypassable in the same screen or flow.
- Line numbers are at HEAD `d69be1ea`. "Repro" steps are proposed reproductions. **None were executed** (see [TEST-EVIDENCE-A.md](<TEST-EVIDENCE-A.md>)).

## Summary

| ID | Title | Type | Sev | Prio | Blocks release |
|---|---|---|---|---|---|
| SEC-001 | Renaming the bootstrap admin makes the host silently re-create `admin`/`admin` with the system-admin role | Confirmed defect | High | P0 | **Yes**, chained with SEC-002 |
| SEC-002 | `POST /api/auth/session` and `/api/auth/verify-admin` ignore `force_password_change` | Confirmed defect | High | P0 | **Yes** |
| SEC-003 | Device session tokens last 30 days, cannot be revoked, and `userHasPermission` ignores `is_active`/`is_locked` | Confirmed defect | Medium | P1 | No |
| SEC-004 | Clients mint a predictable temporary password `<username>123` for synced users that arrive without credentials | Confirmed defect | High | P1 | No (pre-existing, documented open item) |
| SEC-005 | Upgraded installs stay on the derivable legacy SQLCipher key unless an admin opts in | Confirmed (design gap) | Medium | P1 | No |
| SEC-006 | The legacy shared LAN bearer is enabled for 30 days on every new server install | Confirmed defect | Medium | P2 | No |
| SEC-007 | LAN transport is cleartext by default; TLS without a pin accepts any certificate | Confirmed (design) | Medium | P2 | No |
| SEC-008 | Tokenless reads of `parties`/`accounts`/`users` rows; `GET /api/parties` ignores branch scope | Confirmed defect | Medium | P1 | No |
| SEC-009 | Lockout is not persisted; the manager-override dialog has no attempt limit | Confirmed defect | Medium | P2 | No |
| SEC-010 | Argon2id parameters (m=4 MiB, t=3) are below the OWASP minimum while hashes are distributed to clients | Improvement | Low | P2 | No |
| SEC-011 | Boot "structural heal" resets admin to `admin` without setting `force_password_change` | Confirmed defect | Low | P2 | No |
| SEC-012 | An untracked operational log sits at the repo root and is not git-ignored | Confirmed | Low | P1 | No (do not commit) |
| SEC-013 | The Gitleaks CI job is advisory (`continue-on-error`) and no local scan was possible | Improvement | Low | P3 | No |
| SEC-014 | The cloud server binds plain HTTP; production TLS/deployment is not defined in the repo | Missing requirement | Info | P2 | No |
| SEC-015 | Cash-drawer fallback passes the printer name through `cmd /c`; predictable temp file | Suspicion | Low | P3 | No |
| SEC-016 | xlsx/zip decoding has no size or entry limits | Improvement | Low | P3 | No |
| SEC-017 | Prior claim "admin QR carries a long-lived signing key" is **refuted**: it carries the Ed25519 *public* key; the key has no rotation path | Improvement | Info | P3 | No |
| AUTHZ-001 | Conditional grants can be self-approved: the requester types their own password in the manager-override dialog | Confirmed defect | High | P0 | **Yes** |
| AUTHZ-002 | Sales-invoice figure masking is bypassed by "View details" (totals, paid, remaining, prices, profit margin); B-1 still open | Confirmed defect | High | P0 | **Yes** |
| AUTHZ-003 | Parties screen: statement, Export (all branches, balances) and Import (overwrites balance) are ungated; B-2 still open | Confirmed defect | High | P0 | **Yes** |
| AUTHZ-004 | `sales_view` now reveals amounts that `sales_amounts_view` used to hide (regression in `d2272da0`) | Confirmed regression | Medium | P1 | No (owner decision) |
| AUTHZ-005 | The host API treats conditional grants as full grants (no approval on the API path) | Confirmed defect | Medium | P1 | No |
| AUTHZ-006 | GET read endpoints have no permission gate; the grep guard covers mutations only | Confirmed (design gap) | Medium | P2 | No |
| AUTHZ-007 | The invoice details dialog shows per-invoice profit margin with no cost/profit permission (default cashier included) | Confirmed defect | Medium | P1 | No |
| AUTHZ-008 | Booking create/status/cancel are enforced in the UI only (B-4) | Confirmed | Low | P2 | No |
| AUTHZ-009 | `inventory_view` reveals unit cost even without `products_cost_view` | Suspicion (design) | Low | P2 | No |
| AUTHZ-010 | Local authorization is enforced at the widget layer; the service/DAO layer covers only about 10 critical ops | Info (architecture) | Info | P2 | No |
| SYNC-001 | Mixed fleet: v195 clients drop v196 `table_reservations` rows permanently (D-1 only partly fixed) | Confirmed defect | High | P0 | **Yes, conditional** |
| SYNC-002 | Delta-pull row failures are swallowed while the watermark advances (silent loss class) | Confirmed defect | Medium | P1 | No |
| SYNC-003 | Client-created table reservations are never pushed to the host (D-3) | Confirmed defect | Medium | P1 | No |
| SYNC-004 | No host-side phone dedupe, so duplicate customers are created across devices (D-4) | Confirmed | Low | P2 | No |
| SYNC-005 | Non-financial push conflicts matched by error string are marked "synced" and the local change is dropped | Confirmed defect | Medium | P1 | No |
| SYNC-006 | The client DB receives all scoped rows regardless of the user's permissions; figure masking is UI-only | Info (design) | Info | P3 | No |
| SYNC-007 | The cloud command/query relay (ADR-M2) is not implemented; documentation only | Missing requirement | Info | P2 | No |

**Counts by severity:**

| Severity | Count | IDs |
|---|---|---|
| Critical | 0 | — |
| High | 7 | SEC-001, SEC-002, SEC-004, AUTHZ-001, AUTHZ-002, AUTHZ-003, SYNC-001 |
| Medium | 13 | — |
| Low | 9 | — |
| Info | 5 | — |
| **Total** | **34** | — |

**Release-blocking findings:** SEC-001 with SEC-002, AUTHZ-001, AUTHZ-002, AUTHZ-003, and SYNC-001 (conditional).

### Prior-audit items re-verified at HEAD

| Prior ID | Claim | Status at HEAD | Evidence |
|---|---|---|---|
| B-1 | Action-only codes open Sales invoices | **Still open**. List amounts are now masked, but the details dialog bypasses the mask → AUTHZ-002 | [screen_access_resolver.dart:111-117](<../../../../lib/core/permissions/screen_access_resolver.dart#L111-L117>) [V] |
| B-2 | Action-only codes open customers/parties/suppliers | **Still open**. Card balances are now masked; statement, export and import are not → AUTHZ-003 | [screen_access_resolver.dart:93-110](<../../../../lib/core/permissions/screen_access_resolver.dart#L93-L110>) [V] |
| B-3 | Conditional grants bypass approval in table gates | **Fixed in UI**: `tableActionGate`/`ensureTableAction` route `cond:` codes to approval. Undermined by AUTHZ-001 (self-approval) and AUTHZ-005 (API) | [table_action_gate.dart:29-65](<../../../../lib/presentation/screens/tables/table_action_gate.dart#L29-L65>); [table_operations.dart:936-945](<../../../../lib/presentation/screens/tables/table_operations.dart#L936-L945>) [V] |
| B-4 | Booking gates UI-only | **Still open** → AUTHZ-008 | — |
| D-1 | Mixed-fleet column filtering | **Partly fixed**: the filter exists in v196+ clients only; no handshake; rows lost on v195 clients → SYNC-001 | [delta_pull_column_filter.dart](<../../../../lib/services/delta_pull_column_filter.dart>) [V] |
| D-2 | `party_id` not remapped | **Fixed** (`table_reservations` and `bookings` added) | [delta_pull_service.dart:1075-1110](<../../../../lib/services/delta_pull_service.dart#L1075-L1110>) [V] |
| D-3 | No push for reservations | **Still open** → SYNC-003 | — |
| D-4 | Phone dedupe local only | **Still open** → SYNC-004 | — |
| QR admin key | "QR carries a long-lived signing key" | **Refuted**. The QR carries the Ed25519 public key plus a one-time 10-minute code → SEC-017 | — |
| Cloud relay | Missing | **Confirmed missing** → SYNC-007 | — |

---

## SEC — Authentication, sessions, secrets, transport

### SEC-001 — Renaming the bootstrap admin makes the host re-create `admin`/`admin` with the system-admin role

**Classification**

- Type: Confirmed defect.
- Axis: A / auth.
- Severity: High. Priority: P0.
- Confidence: High. The code was read end to end [V]; the behaviour was not executed.
- Affected: HEAD `d69be1ea`, server (host) mode, SQLite or PostgreSQL.

**Location**

- [edit_user_dialog.dart:55-62, 140-149](<../../../../lib/presentation/screens/settings/widgets/edit_user_dialog.dart#L55-L62>): the username is editable for any user, including id 1.
- [user_dao.dart:225-259](<../../../../lib/data/database/daos/user_dao.dart#L225-L259>): `updateUserInfo` guards the bootstrap admin's role, but not its username.
- [api_data_users_roles.dart:76-130](<../../../../lib/services/api/data/api_data_users_roles.dart#L76-L130>): "username stays editable" for the bootstrap admin.
- [api_get_users.dart:8, 163-256](<../../../../lib/services/api/routes/api_get_users.dart#L163-L256>): `_ensureBootstrapAdminOnce()` runs on the first `GET /api/users` of every host process. If no row has `username='admin'` (and id 1 is not `__dup_1_admin`), it inserts `admin` with `hashPasswordArgon2('admin')`, `roleId: 1`, `isActive: true` and `forcePasswordChange: true`.

**Preconditions:** the owner renames the built-in admin (for example to `owner`), the host runs in server mode, and any paired client syncs (which calls `GET /api/users`).

**Repro**

1. Rename user id 1 from `admin` to `owner` in Users management.
2. Restart the host.
3. Let a client sync.
4. On the host, query `SELECT id, username, role_id, force_password_change FROM users WHERE username='admin'`.

**Expected vs actual**

- Expected: the rename is respected; no new privileged account appears.
- Actual: a second system-admin account `admin`, with the publicly known password `admin`, appears silently. The owner never logs into it, so the forced change never happens.

**Evidence** ([api_get_users.dart:233-251](<../../../../lib/services/api/routes/api_get_users.dart#L233-L251>), excerpt):

```dart
// Genuinely missing — INSERT ... The default password is 'admin'
final passwordHash = await SecurityService.hashPasswordArgon2('admin');
... username: 'admin', roleId: const Value(1), forcePasswordChange: const Value(true),
```

**Impact**

- An attacker can log in with the known default credentials and get a system-admin session.
  - Locally on the host, a forced change applies, so the attacker sets their own password and owns the account.
  - Via the API, the forced change is skipped (SEC-002), so the attacker gets a 30-day API admin session without any change.
- Full takeover of permissions, users and settings.

**Root cause:** the self-heal identifies "admin missing" by username only, and the rename path does not mark the renamed row as the bootstrap admin.

**Remediation**

- Identify the bootstrap admin by a stable marker (id 1 or a setting holding its `global_id`), not by username.
- Never auto-create a known-password account on a database that already has users. Log and alert instead.
- Optionally forbid renaming id 1.
- Effort: S (about 0.5–1 day). Dependencies: none.

**Acceptance:** an integration test renames id 1, calls `GET /api/users`, and asserts that no row `username='admin'` is created and the user count is unchanged.

**Release-blocking:** Yes, together with SEC-002. A known-credential admin appears without the owner's knowledge in a normal "custom admin username" setup.

### SEC-002 — `POST /api/auth/session` and `/api/auth/verify-admin` ignore `force_password_change`

**Classification:** Confirmed defect. Severity High, priority P0. Confidence High [V].

**Location**

- [api_auth_handler.dart:156-208](<../../../../lib/services/api/api_auth_handler.dart#L156-L208>): mints `ApiSessionToken.mint(result.user.id)` right after `authenticateUser`, without reading `user.forcePasswordChange`.
- [api_auth_handler.dart:76-126](<../../../../lib/services/api/api_auth_handler.dart#L76-L126>): mirror pairing does the same.
- The local UI does enforce the change: [login_screen.dart:359-376](<../../../../lib/presentation/screens/login_screen.dart#L359-L376>).

**Preconditions**

- Any account with a default or temporary password and the flag set. Examples:
  - The seeded admin on a server-mode install. The wizard sets the admin password only for standalone ([setup_finish_runner.dart:316-327](<../../../../lib/presentation/screens/setup_wizard/setup_finish_runner.dart#L316-L327>)).
  - The SEC-001 re-created admin.
  - Users reset with "force change".
- The caller holds a device bearer (a paired device, or the legacy token inside its window, see SEC-006).

**Repro:** on a host whose admin still has the flag, `POST /api/auth/session {"username":"admin","password":"admin"}` with a paired-device bearer. Expect 403 "password change required"; the code returns 200 with a 30-day token.

**Expected vs actual:** a forced-change account should not receive an API session (or should receive a session scoped only to the change-password call). Actually, a full 30-day session is issued.

**Impact:** API administration (users, roles, settings, all write routes gated by `requirePermission`) with default credentials.

**Remediation**

- Reject `force_password_change` users in both handlers, or return a restricted "must change password" token.
- Effort: XS–S.

**Acceptance:** a unit test where a user has `force_password_change=1` and calls `/api/auth/session` expects 403 or a restricted token; `/api/auth/verify-admin` expects 403.

**Release-blocking:** Yes. It makes the default credential remotely usable.

### SEC-003 — Device session tokens: 30-day TTL, no revocation, and `userHasPermission` ignores `is_active`/`is_locked`

**Classification:** Confirmed defect. Severity Medium, priority P1. Confidence High [V].

**Location**

- [api_session_token.dart:33, 88-125](<../../../../lib/services/api/api_session_token.dart#L88-L125>): `_ttl = Duration(days: 30)`, stateless; `verify` checks only the signature and `exp`. There is no `iat` and no revocation list (unlike web tokens, `:143-162`).
- [permissions_dao.dart:218-248](<../../../../lib/data/database/daos/permissions_dao.dart#L218-L248>): no `isActive`/`isLocked` check.
- [api_user_context.dart:47-85](<../../../../lib/services/api/api_user_context.dart#L47-L85>): the only per-request identity check.

**Repro:** issue a session for user U, deactivate or lock U (or change their password), then call any gated `POST` with the old token. It is expected to fail and, by reading, would pass.

**Impact:** a dismissed employee, or a stolen token from a paired device, keeps write access for up to 30 days. Logout does not end the session server-side.

**Remediation**

- Add `iat` to the token and keep a per-user "tokens valid after" timestamp, bumped on deactivate, lock, password change and logout.
- Check active/locked status in `requirePermission`.
- Consider a shorter TTL with refresh.
- Effort: S.

**Acceptance:** tests for deactivate → 401, lock → 401, password change → old token 401.

**Release-blocking:** No (pre-existing; requires the device bearer).

### SEC-004 — Clients mint the predictable temporary password `<username>123`

**Classification:** Confirmed defect. Severity High, priority P1. Confidence High [V] for the code; trigger frequency [I].

**Location**

- [delta_pull_service.dart:1280-1309](<../../../../lib/services/delta_pull_service.dart#L1280-L1309>): `final tempPassword = '${username}123';` then sets `force_password_change=1`.
- Same convention in [user_sync_strategy.dart:131](<../../../../lib/services/sync/strategies/user_sync_strategy.dart#L131>).
- The code comment itself flags this as an owner-open item.
- The host withholds hashes unless the caller has a session or the pairing window is open ([api_get_sync_pull.dart:238-252](<../../../../lib/services/api/routes/api_get_sync_pull.dart#L238-L252>)). Any users row that arrives through a tokenless (pre-login) pull, with no local credentials, therefore gets the guessable password.

**Repro**

1. Create user `ahmed` on the host after a client was paired.
2. On the client, restart so that the pre-login pull runs.
3. Log in on the client with `ahmed123`.
4. Expected: rejected. By reading: accepted, followed by a forced change.

**Impact**

- Local account takeover on client terminals, including privileged roles (for example a new manager).
- The attacker then sees everything in the client DB under that role.
- Server writes still need a host session (real password) [I].

**Remediation**

- Never mint known passwords. Store the row locked (`is_locked=1`, or an empty hash that fails closed) until real credentials arrive, and show "sync credentials from server".
- Effort: S.

**Acceptance:** a test that pulls a users row without credentials asserts that login with `<username>123` fails and the row is marked locked or pending.

**Release-blocking:** No (pre-existing, documented). It is P1 before scale-out.

### SEC-005 — Upgraded installs stay on the derivable legacy SQLCipher key

**Classification:** Confirmed (design gap). Severity Medium, priority P1. Confidence High [V].

**Location**

- [legacy_device_seed.dart:35-46](<../../../../lib/services/legacy_device_seed.dart#L35-L46>): the key is `sha256(deviceId + ":" + pepper)`. The pepper is in source; the deviceId is the Windows device id.
- [db_key_boot.dart:183](<../../../../lib/services/db_key_boot.dart#L183>): "No automatic migration, ever" — migration runs only on an explicit admin request.
- Fresh installs get a random `rawV2` key ([db_key_manager.dart:310-345](<../../../../lib/services/db_key_manager.dart#L310-L345>)).
- Pre-migration copies are kept for 30 days ([db_backup_sidecars.dart:48-63](<../../../../lib/services/db_backup_sidecars.dart#L48-L63>)).

**Impact**

- Anyone who copies the DB (or a backup) and can read the machine's device id (any local user or malware) can decrypt it.
- The DB holds password hashes, PINs, card codes and all business data.

**Remediation:** prompt the owner persistently after upgrade until migrated, and optionally schedule automatic migration with the existing safe M1–M8 flow. Delete pre-v2 copies after a confirmed M8.

**Acceptance:** after the upgrade the UI shows a non-dismissable banner while `keyinfo.kind` is legacy; a test asserts that the banner condition holds.

**Release-blocking:** No (pre-existing, owner decision "no automatic migration").

### SEC-006 — The legacy shared LAN bearer is enabled for 30 days on every new server install

**Classification:** Confirmed defect. Severity Medium, priority P2. Confidence High [V].

**Location**

- [lan_pairing_service.dart:19, 515-541](<../../../../lib/services/api/lan_pairing_service.dart#L515-L541>): the transition start is stamped at the first server start; `defaultTransitionDays = 30`.
- [network_service.dart:779-783](<../../../../lib/services/network_service.dart#L779-L783>): the legacy token is generated if allowed.
- [api_auth_middleware.dart:141-151, 289](<../../../../lib/services/api/api_auth_middleware.dart#L141-L151>): `sha256(seed+'UralCash-API-v1')[:32]`, compared with `==` (not constant-time). The seed is SEC-005's derivable device seed.

**Impact**

- A fresh install has no legacy devices, yet accepts a derivable shared bearer for 30 days.
- Anyone able to learn the host device id can call all bearer-only endpoints, for example tokenless master reads (SEC-008) and `/api/auth/session` brute force (throttled to 5 per 15 minutes per username).

**Remediation**

- Do not open the window when `lan_paired_devices` is empty on first start.
- Use a constant-time comparison.
- Show the remaining window on the devices screen.

**Acceptance:** on a fresh install, `legacyAllowed()` is false.

**Release-blocking:** No.

### SEC-007 — LAN transport is cleartext by default; TLS without a pin accepts any certificate

**Classification:** Confirmed (design). Severity Medium, priority P2. Confidence High [V].

**Location**

- [network_service.dart:61, 258](<../../../../lib/services/network_service.dart#L258>): `_tlsEnabled` defaults to `false`.
- [tls_trust.dart:164-166](<../../../../lib/services/tls_trust.dart#L164-L166>): `if (expected == null) return true;` — when no pin exists, any certificate is accepted (TOFU by design).
- Cloud calls use the default `http.Client()` with system CA validation ([cloud_link_api.dart:44](<../../../../lib/services/cloud_sync/cloud_link_api.dart#L44>)).
- Mobile release builds are HTTPS-only (`cleartextTrafficPermitted="false"` plus `UrlPolicy.release`).

**Impact:** on a shared or hostile LAN, a passive sniffer reads bearer and session tokens, synced data and (inside the pairing window) password hashes. An active attacker can MITM unpinned TLS.

**Remediation:** enable TLS by default with a generated self-signed certificate, and pin the fingerprint during pairing for all clients (the mechanism already exists). Document the trusted-LAN assumption meanwhile.

**Acceptance:** a new server install serves HTTPS, and a client paired in the window has a pin stored.

**Release-blocking:** No (documented assumption; mobile apps are already HTTPS-only).

### SEC-008 — Tokenless reads of master data, and `GET /api/parties` ignores branch scope

**Classification:** Confirmed defect. Severity Medium, priority P1. Confidence High [V].

**Location**

- [api_get_sync_pull.dart:48-57](<../../../../lib/services/api/routes/api_get_sync_pull.dart#L48-L57>): only tables in `_transactionalPullTables` require identity.
  - [api_sync_pull_tables.dart:192-259](<../../../../lib/services/api/routes/api_sync_pull_tables.dart#L192-L259>) does not list `parties`, `accounts`, `users` or `products`. These are served with no session.
  - For `users`, credential columns are dropped, but usernames and roles are served.
- [api_get_directory.dart:10-47](<../../../../lib/services/api/routes/api_get_directory.dart#L10-L47>): `GET /api/parties` returns every party (`balance`, `creditLimit`, phone, tax id) with no identity or branch filter (the comment at [api_routes_read.dart:58-60](<../../../../lib/services/api/routes/api_routes_read.dart#L58-L60>) acknowledges this).

**Impact:** any holder of a device bearer (paired device, legacy window) reads the full customer/supplier ledger summary of all branches without logging in. Branch isolation does not apply to parties.

**Remediation:** require identity for parties balances (serve a balance-free projection pre-login), and apply `_resolveBranchScope` to parties via `branch_id`/assignment.

**Acceptance:** a tokenless `GET /api/parties` or `/api/sync/pull?table=parties` returns no `balance`/`credit_limit`; a branch-restricted session receives only in-scope parties.

**Release-blocking:** No.

### SEC-009 — Lockout is not persisted; the manager-override dialog has no attempt limit

**Classification:** Confirmed defect. Severity Medium, priority P2. Confidence High [V].

**Location**

- [login_rate_limiter.dart:15-41, 97-101](<../../../../lib/services/login_rate_limiter.dart#L15-L41>): "SEC02 persistence" relies on `onLockoutPersist`/`onLockoutLoad`. A grep of `lib/` finds no assignment and no call to `loadPersistedLockouts()`, so the lockout resets on app restart.
- [permission_guard.dart:597-671](<../../../../lib/presentation/widgets/permission_guard.dart#L597-L671>): the override dialog takes a password only (no username) and has no rate limiter. Each try is verified against every active user ([user_dao.dart:484-510](<../../../../lib/data/database/daos/user_dao.dart#L484-L510>)).
- [server_login_throttle.dart](<../../../../lib/services/api/server_login_throttle.dart>) is in-memory as well.

**Impact:**

- The 5-attempt lockout is bypassed by restarting the app.
- A cashier can guess passwords repeatedly in the override dialog. Argon2 at about 40 ms × N users slows this, but there is no cap.

**Remediation:** wire the persistence callbacks to `settings`, and apply `LoginRateLimiter` (keyed by the requesting user and device) to the override and close-shift password dialogs.

**Acceptance:** 5 failures, restart, then still locked; 5 failed overrides, then the dialog is locked for 15 minutes.

**Release-blocking:** No.

### SEC-010 — Argon2id parameters below the OWASP minimum

**Classification:** Improvement. Severity Low, priority P2. Confidence High [V].

**Location:** [security_service.dart:142-144](<../../../../lib/services/security_service.dart#L142-L144>) uses m=4096 KiB, t=3, p=1; the legacy PBKDF2 path uses 10,000 iterations (`:72`). Hashes are shipped to clients (pairing window or session).

**Impact:** offline cracking of leaked hashes is cheaper than recommended.

**Remediation:** raise to at least 19 MiB with t=2 (OWASP) and rehash on login (the mechanism already exists).

**Acceptance:** a new hash's PHC string shows `m>=19456`.

**Release-blocking:** No.

### SEC-011 — Boot structural heal resets admin to `admin` without forcing a change

**Classification:** Confirmed defect. Severity Low, priority P2. Confidence High [V].

**Location:** [database_startup.dart:850-864](<../../../../lib/data/database/database_startup.dart#L850-L864>) runs `UPDATE users SET password_hash=?, password_salt=?, is_active=1` (no `force_password_change`) when the admin hash or salt is structurally broken. The `:639-667` post-seed path is similar.

**Impact:** a corrupted row (or one corrupted by a sync defect) silently becomes `admin`/`admin` with no forced rotation.

**Remediation:** also set `force_password_change=1` and log a SECURITY entry. Effort: XS.

**Acceptance:** a unit test on the heal asserts the flag is set.

**Release-blocking:** No.

### SEC-012 — Untracked operational log at the repo root

**Classification:** Confirmed. Severity Low, priority P1 (hygiene). Confidence High [V].

**Location:** `صور لاعادة تصميم الشاشات الموضحه/picpos_login_log_server.txt` (115 KB, 1,077 lines). It is untracked, and `git check-ignore` exits 1, so it is not ignored.

**Content classification** (values not reproduced): user ids and usernames (about 116 matches), shift cash amounts and timestamps. No password, hash, token value or IP address was found by pattern scan; the "token/password" matches are log keywords.

**Impact:** personal and business data would leak if the folder were committed (it is a likely candidate in a broad `git add`).

**Remediation:** move it out of the repo or add the folders to `.gitignore`; stage explicitly.

**Acceptance:** `git status --porcelain` does not list the folder, or it is ignored.

**Release-blocking:** No, provided it is not committed.

### SEC-013 — Gitleaks is advisory only

**Classification:** Improvement. Severity Low, priority P3.

**Location:** [ci.yml:53-74](<../../../../.github/workflows/ci.yml#L53-L74>) sets `continue-on-error: true`. The blocking `secrets` job checks file types only (`tool/check_no_secrets.ps1`). `gitleaks` is not installed locally, so no history scan was run in this audit (NOT_RUN). A pattern `git grep` found only fake fixtures (see TEST-EVIDENCE-A).

**Remediation:** make Gitleaks blocking on PRs to the release branches.

**Release-blocking:** No.

### SEC-014 — Cloud server binds plain HTTP; production TLS and deployment are not defined

**Classification:** Missing requirement. Severity Info, priority P2.

**Location:** [server.dart:63](<../../../../server/bin/server.dart#L63>) calls `io.serve(..., InternetAddress.anyIPv4, port)` with no `SecurityContext`. [docker-compose.yml:1](<../../../../docker/docker-compose.yml#L1>) is a TEST stack with test-only secrets, bound to loopback.

**Positive controls verified:** `TOKEN_SECRET` must be ≥ 32 characters, and `ADMIN_KEY` must be ≥ 24 characters unless `ALLOW_WEAK_ADMIN_KEY=1` ([picpos_cloud.dart:44-68](<../../../../server/lib/picpos_cloud.dart#L44-L68>)).

**Remediation:** document and ship a production deployment (TLS reverse proxy, secret sourcing, DB TLS `DB_SSL=true`).

**Release-blocking:** No for the desktop release; Yes before any cloud production use.

### SEC-015 — Cash-drawer fallback passes the printer name through `cmd /c`

**Classification:** Suspicion. Severity Low, priority P3.

**Location:** [cash_drawer_service_io.dart:145-151](<../../../../lib/services/cash_drawer_service_io.dart#L145-L151>) runs `Process.run('cmd', ['/c','copy','/b', tmp, '\\\\localhost\\$printer'])`. `cmd` re-parses metacharacters (`&`, `|`) in the printer name. Also: fixed temp path `drawer_cmd.bin` in the system temp folder (`:56`).

**Exploit condition:** a printer name containing metacharacters, set by a local admin (low likelihood) [I].

**Remediation:** use the spooler path only, or validate the name; use a unique temp file.

**Release-blocking:** No.

### SEC-016 — xlsx/zip decoding has no size or entry limits

**Classification:** Improvement. Severity Low, priority P3.

**Location:** [excel_service.dart:326, 761, 975, 1202, 1220](<../../../../lib/data/services/excel_service.dart#L975>) (`Excel.decodeBytes`); [xlsx_sanitizer.dart:19](<../../../../lib/data/services/xlsx_sanitizer.dart#L19>) (`ZipDecoder().decodeBytes`). Files are user-picked locally.

**Impact:** local denial of service through a zip bomb. No zip-slip, because nothing is extracted to disk.

**Remediation:** cap the file size and uncompressed total before decoding.

**Release-blocking:** No.

### SEC-017 — The admin QR carries the desktop's public signing key (prior claim refuted); no rotation path

**Classification:** Improvement. Severity Info, priority P3. Confidence High [V].

**Location**

- [linked_devices_section.dart:799-816](<../../../../lib/presentation/settings_picpos/screens/linked_devices_section.dart#L799-L816>): the QR JSON is `{v, cloudUrl, cloudCode, desktopSigningKey}`.
- The value is `signer.publicKeyBase64()` ([cloud_link_controller.dart:202-209](<../../../../lib/services/cloud_sync/cloud_link_controller.dart#L202-L209>)), which is the Ed25519 **public** key ([signature.dart:73-88](<../../../../packages/picpos_api_client/lib/src/signature.dart#L73-L88>)).
- The seed stays in the desktop secret store ([admin_signing_key.dart:11-21](<../../../../lib/services/admin_snapshots/admin_signing_key.dart#L11-L21>)).
- The code is single-use, valid for 10 minutes, stored hashed, and rate-limited at 5 per IP per 10 minutes ([admin_service.dart:82-98, 287-359](<../../../../server/lib/src/service/admin_service.dart#L287-L359>)).
- The mobile app confirms the key fingerprint ([admin_session.dart:132-155](<../../../../mobile_admin/lib/admin_session.dart#L132-L155>)).

**Statement:** the plan text ([2026-10-18 plan §A](<../../../plans/2026-10-18-tables-reservations-permissions-plan.md>), line 65) and FINAL-QA-VERDICT line 43 call this a "long-lived secret". That is incorrect: exposing the QR exposes no secret.

**Residual:** there is no rotation or revocation path for a compromised desktop seed.

**Remediation:** add a "rotate signing key" flow that re-pushes the public key and invalidates paired admin devices.

**Release-blocking:** No.

---

## AUTHZ — Authorization enforcement

### AUTHZ-001 — Conditional grants can be self-approved in the manager-override dialog

**Classification**

- Type: Confirmed defect.
- Severity: High. Priority: P0.
- Confidence: High by reading [V]. Not executed.
- Affects every `cond:` gate, including the new table gates (the B-3 fix) and booking gates.

**Location**

- [permission_guard.dart:863-890](<../../../../lib/presentation/widgets/permission_guard.dart#L863-L890>): `ensurePermission` → `requestManagerApproval` for a `cond:` code.
- [permission_guard.dart:609-657](<../../../../lib/presentation/widgets/permission_guard.dart#L609-L657>): the approver is whoever's password matches (`authenticateByPasswordOrCard`), then `userPermissions.contains(widget.permission)`. There is no check that the approver differs from the requester, and none that the approver's grant is unconditional.
- [permissions_dao.dart:288-292](<../../../../lib/data/database/daos/permissions_dao.dart#L288-L292>): a conditional holder's list contains both `code` and `cond:code`.

**Repro**

1. Role R holds `tables_merge` with `grant_mode=conditional`.
2. Log in as a cashier with role R and merge tables.
3. The approval dialog appears; type the cashier's **own** password.
4. Expected: "approver must be a different user with an unconditional grant". By reading, the action is approved.

A second user with the same conditional grant can also approve.

**Impact:** the "requires manager approval" control (four-eyes) is ineffective for every conditional permission.

**Root cause:** the approver check reuses the plain `contains` used for holders.

**Remediation**

- In `_verifyPassword`, reject `userWithRole.user.id == currentUser.id`.
- Require `hasPermissionWithAdminBypass(perms, code) && !isConditionalIn(perms, code)` for the approver.
- Effort: XS–S.

**Acceptance:** widget tests for (a) self password → denied, (b) another conditional holder → denied, (c) an unconditional holder or system admin → approved.

**Release-blocking:** Yes. The candidate's B-3 fix depends on this dialog.

### AUTHZ-002 — Sales-invoice figure masking bypassed by "View details" (B-1 still open)

**Classification:** Confirmed defect. Severity High, priority P0. Confidence High [V].

**Location**

- [screen_access_resolver.dart:111-117](<../../../../lib/core/permissions/screen_access_resolver.dart#L111-L117>): `sales_create`, `sales_edit`, `sales_delete` or `sales_print` opens the screen.
- The list masks totals ([sales_invoices_table.dart:600-604, 741-742](<../../../../lib/presentation/sales_invoices_picpos/screens/sales_invoices_table.dart#L600-L604>)).
- The eye button is ungated ([sales_invoices_table.dart:672-677](<../../../../lib/presentation/sales_invoices_picpos/screens/sales_invoices_table.dart#L672-L677>)) and opens `_showInvoiceDetailsInner`. That dialog renders unit prices, line totals, subtotal, discount, tax, total, paid and remaining, plus `ProfitMarginAnalysisWidget`, with no permission check ([sales_invoice_dialogs.dart:42-233](<../../../../lib/presentation/sales_invoices_picpos/screens/sales_invoice_dialogs.dart#L42-L233>)).

**Repro:** with role `{pos_access, sales_create}`, open Sales invoices. The totals show `—`; click the eye icon on any invoice and all amounts appear.

**Expected vs actual:** masked amounts stay masked in every view of the same data. Actually, they are fully visible, including all historical invoices in scope.

**Impact:** the candidate's stated control ("hide monetary figures without view permission", commit `d2272da0`) is bypassed in one click. Sales history and margins are visible to POS-only roles.

**Remediation:** gate the details dialog's money blocks and margin widget with `canSeeScreenFigures(..., salesInvoices)` (and AUTHZ-007), or require `sales_view` to open details. Add a structural test that every money widget on figure-masked screens uses the mask.

**Acceptance:** a widget test where role `{sales_create}` opens details asserts no numeric amounts and no margin card.

**Release-blocking:** Yes (rule b).

### AUTHZ-003 — Parties screen: statement, Export and Import are ungated (B-2 still open)

**Classification:** Confirmed defect. Severity High, priority P0. Confidence High [V].

**Location**

- [parties_picpos_screen.dart:164-202](<../../../../lib/presentation/parties_picpos/screens/parties_picpos_screen.dart#L164-L202>): "كشف حساب عميل/مورد", "تصدير" and "استيراد" have no guard. Only "إضافة" is guarded (`:204-212`).
- `PartyStatementPicposScreen` has no permission references (grep: 0 matches).
- Export, [excel_service.dart:902-965](<../../../../lib/data/services/excel_service.dart#L902-L965>):
  - writes **every** customer or supplier with phone, address, credit limit and `balance`;
  - calls `getParties(...)`, which has no branch-scope parameter ([parties_repository_impl.dart:202](<../../../../lib/data/repositories/parties_repository_impl.dart#L202>)).
- Import, [excel_service.dart:968-1011](<../../../../lib/data/services/excel_service.dart#L968-L1011>): creates parties and, for existing names, writes `balance: openingBalance` directly (`:1001-1007`). There is no journal entry and no `customers_add`/`customers_edit` check.

**Repro**

1. With role `{customers_add}` (or `customer_message_send`, `customers_edit`, `customers_delete`), open Customers. Balances show `—`.
2. Click "كشف حساب عميل" → full statement.
3. Click "تصدير" → xlsx with all branches' balances.
4. Click "استيراد" with a crafted sheet → party balances overwritten.

**Impact**

- Data exposure across branches, defeating both the new masking and branch isolation.
- Integrity: the party balance cache diverges from the AR/AP ledger with no JE. This is data-axis relevant; see axis B.

**Root cause:** these entry points predate F.2. Previously reaching them required `customers_view`; F.2 widened who reaches them.

**Remediation**

- Gate statements with `customers_view`/`suppliers_view` (or the figure rule).
- Gate export with view plus a dedicated export code, and branch-scope it.
- Gate import with `customers_add` + `customers_edit`, and stop writing `balance` on update (route opening balances through the opening-balance JE path).

**Acceptance:** widget tests for role `{customers_add}`: statement/export are disabled or need approval; import refuses balance overwrite; export rows ⊆ branch scope.

**Release-blocking:** Yes (rule b; plus an integrity side effect).

### AUTHZ-004 — `sales_view` now reveals amounts previously hidden by `sales_amounts_view`

**Classification:** Confirmed regression introduced in `d2272da0`. Severity Medium, priority P1. Confidence High [V].

**Location**

- [any_permission_masked_text.dart:6-10](<../../../../lib/presentation/widgets/any_permission_masked_text.dart#L6-L10>): `kSalesFiguresCodes = [salesView, salesAmountsView]`.
- Used in [sales_invoices_table.dart:603-604, 741-742](<../../../../lib/presentation/sales_invoices_picpos/screens/sales_invoices_table.dart#L741-L742>) and [sales_summary_cards.dart:58-62, 269-273](<../../../../lib/presentation/sales_invoices_picpos/screens/sales_summary_cards.dart#L269-L273>).
- The base `c5f5056c` used `PermissionGuard(permission: PermissionCodes.salesAmountsView)` (diff verified).
- `sales_amounts_view` is labelled "عرض المبالغ في الفواتير" ([permission_categories.dart:144](<../../../../lib/presentation/screens/role_management/data/permission_categories.dart#L144>)).

**Impact:** a custom role where the admin deliberately removed `sales_amounts_view` but kept `sales_view` now sees totals, the hero card and the KPI cards. Default roles hold both codes, so they are unaffected.

**Remediation:** keep `sales_amounts_view` as the sole amount code (or require both), and record the owner decision.

**Acceptance:** a test where role `{sales_view}` sees totals masked.

**Release-blocking:** No (owner decision needed); add it to the release note if kept.

### AUTHZ-005 — Host API treats conditional grants as full grants

**Classification:** Confirmed defect. Severity Medium, priority P1. Confidence High [V].

**Location**

- [permissions_dao.dart:117-131](<../../../../lib/data/database/daos/permissions_dao.dart#L117-L131>): `roleHasPermission` returns `mapping != null` regardless of `grant_mode`.
- [api_user_context.dart:77](<../../../../lib/services/api/api_user_context.dart#L77>).
- The cloud server's `AdminContext.has` explicitly accepts `cond:` ([admin_service.dart:43-44](<../../../../server/lib/src/service/admin_service.dart#L43-L44>)). That path is read-only snapshots, so it is acceptable there.

**Impact:** a client holding a session can perform conditional actions through the API without approval. The UI approval runs only on the requesting device.

**Remediation:** return 403 `approval_required` for conditional grants unless the request carries an approval proof (a signed approval token minted when a manager approves).

**Acceptance:** an API test where a conditional-grant user posting to a gated route gets 403.

**Release-blocking:** No.

### AUTHZ-006 — GET read endpoints have no permission gate

**Classification:** Confirmed (design gap). Severity Medium, priority P2. Confidence High [V].

**Location**

- [api_handler_perm_gate_grep_test.dart:16-17, 124-134](<../../../../test/unit/api_handler_perm_gate_grep_test.dart#L124-L134>): `_get*` handlers are skipped by design ("Spec 077 §3 Non-goals").
- [api_routes_read.dart:15-63](<../../../../lib/services/api/routes/api_routes_read.dart#L15-L63>): 45 GET routes, including journals, safe-transactions, payments, users and roles. They are branch-scoped where a column exists (`failClosedOnNoIdentity: true`), but not permission-scoped.
- Web-session GETs do have an allowlist gate (`WebHttpReadGate`, [api_auth_middleware.dart:258-261](<../../../../lib/services/api/api_auth_middleware.dart#L258-L261>)).

**Impact:** any logged-in device user (for example a cashier) can read journals and treasury for their branches over the API.

**Remediation:** apply the WebHttpReadGate table policy to device sessions as well, and extend the grep guard to GET handlers with an explicit allowlist.

**Release-blocking:** No.

### AUTHZ-007 — Invoice details show profit margin without a cost/profit permission

**Classification:** Confirmed defect (pre-existing). Severity Medium, priority P1. Confidence High [V].

**Location:** [sales_invoice_dialogs.dart:140-159](<../../../../lib/presentation/sales_invoices_picpos/screens/sales_invoice_dialogs.dart#L140-L159>) renders `ProfitMarginAnalysisWidget` unconditionally; the widget has no guard ([profit_margin_analysis_service.dart:55-99](<../../../../lib/services/profit_margin_analysis_service.dart#L55-L99>)).

**Context:** the default cashier role holds `sales_view` ([role_grant_matrix.dart:188-189](<../../../../lib/core/permissions/role_grant_matrix.dart#L188-L189>)). The same matrix withholds `dashboard_profit` from every role precisely because margin is sensitive (`:155-162`).

**Impact:** every cashier sees margin percentages and per-line profit (cost is derivable).

**Remediation:** guard the widget with `products_cost_view` or `dashboard_profit`.

**Acceptance:** a widget test where the cashier role sees no margin card.

**Release-blocking:** No (pre-existing), but it is fixed by the same change as AUTHZ-002.

### AUTHZ-008 — Booking actions enforced in the UI only (B-4)

**Classification:** Confirmed. Severity Low, priority P2. Confidence Medium [V]/[I].

**Location:** the only API route is `postBookingApplyDeposit`, gated by `bookings_deposit` ([api_data_operations.dart:380-382](<../../../../lib/services/api/data/api_data_operations.dart#L380-L382>)). Create, status and cancel are local DAO calls behind `booking_permission_gates.dart`.

**Impact:** any other future entry point is ungated. Today the risk is limited to the local UI, which is gated.

**Remediation:** enforce in the booking service (`PermissionEnforcer`).

**Release-blocking:** No.

### AUTHZ-009 — `inventory_view` reveals unit cost regardless of `products_cost_view`

**Classification:** Suspicion (design). Severity Low, priority P2.

**Location:** [financial_figures_access.dart:21](<../../../../lib/core/permissions/financial_figures_access.dart#L21>) lists `inventory_view` among the figure codes for the inventory screen. [stock_movements_table_picpos.dart:514-520](<../../../../lib/presentation/inventory_picpos/widgets/stock_movements_table_picpos.dart>) masks unit cost with that any-of rule.

**Note:** this is not a regression (base showed cost unconditionally), but `products_cost_view` exists precisely to hide cost.

**Remediation:** require `products_cost_view` for cost columns. Owner decision.

**Release-blocking:** No.

### AUTHZ-010 — Local authorization is widget-level by architecture

**Classification:** Info (architecture). Priority P2.

**Evidence:** `PermissionEnforcer` is used in about 10 DAO/repository call sites, all critical financial ops (grep). Everything else relies on `PermissionGuard`/`ensurePermission` in widgets. The resolver itself states it "grants neither read nor action" ([screen_access_resolver.dart:14-18](<../../../../lib/core/permissions/screen_access_resolver.dart#L14-L18>)).

**Consequence:** every ungated button is a bypass (AUTHZ-002, AUTHZ-003). Widening screen access (F.2) multiplies this.

**Remediation:** a structural test that each screen in `screenActionCodes` has no ungated money or export/import entry, and gradual service-layer enforcement.

**Release-blocking:** No.

---

## SYNC — Client/host/cloud synchronisation

### SYNC-001 — Mixed fleet: v195 clients drop v196 `table_reservations` rows permanently (D-1 partly fixed)

**Classification:** Confirmed defect. Severity High, priority P0. Confidence High [V] for the code path. Runtime against a real v195 client: NOT_RUN.

**Location**

- The filter exists only in new clients ([delta_pull_column_filter.dart](<../../../../lib/services/delta_pull_column_filter.dart>), wired at [delta_pull_service.dart:1120](<../../../../lib/services/delta_pull_service.dart#L1120>)).
- The host still sends `SELECT *` ([api_get_sync_pull.dart:179](<../../../../lib/services/api/routes/api_get_sync_pull.dart#L179>)).
- No schema or min-version handshake (grep `minClient|schema_version|x-app-version` in `lib/`: none relevant).
- A v195 client's upsert fails with "no such column party_id", is swallowed (`debugPrint`, [delta_pull_service.dart:1321-1329](<../../../../lib/services/delta_pull_service.dart#L1321-L1329>)), and the watermark still advances ([:740-758](<../../../../lib/services/delta_pull_service.dart#L740-L758>)).
- The v196 backfill bumps `last_modified_at` on linked rows [R per Q-review A/D-1], so all of them are affected.
- After the client upgrades, those rows are not re-fetched. No migration resets the `_watermark__table_reservations` key; the only recovery is the manual reset in [sync_management_dialog.dart:679](<../../../../lib/presentation/widgets/sync_management_dialog.dart#L679>).

**Repro:** host on 3.9.2 and a client on 3.9.1. Create or update a reservation on the host and pull on the client. Expected: the row is applied or a version error is shown. Actually: the row is silently skipped. Then upgrade the client: the row is still missing.

**Impact:** reservations (and any future added column on any table) silently missing on clients, with no alert. FINAL-QA-VERDICT condition 5 admits this was not tested against a real v196 host.

**Remediation**

- **Release now:**
  - Enforce "upgrade host and all clients together" in the release note.
  - Have the v196 migration reset the `table_reservations` watermark on clients (cheap, idempotent).
- **Next:** add a host-side `X-Client-Schema` check and refuse pulls with a clear upgrade message, and stop advancing the watermark when any row in a page failed (SYNC-002).

**Acceptance**

- An integration test: a v195-shaped client DB pulls a v196 row → the error is surfaced and the watermark is not advanced.
- After the v196 migration, the watermark for `table_reservations` is reset.

**Release-blocking:** Yes, conditional. It is acceptable only with an enforced simultaneous fleet upgrade plus a watermark reset (or a documented manual reset step).

### SYNC-002 — Delta-pull row failures are swallowed while the watermark advances

**Classification:** Confirmed defect. Severity Medium, priority P1. Confidence High [V].

**Location:** [delta_pull_service.dart:1321-1329](<../../../../lib/services/delta_pull_service.dart#L1321-L1329>) (main upsert), `:1131-1139` (in-place update), `:1053-1065` (soft delete, logged); watermark at `:740-758`. Comments in `pullTables` already document FK-order failures being "dropped silently" (`:76-77, 121-124`).

**Impact:** any constraint, FK-order, type or schema error loses rows permanently on that client with no user-visible alert. This is the root cause behind SYNC-001.

**Remediation:** count per-page failures; if any occur, do not advance the watermark, persist the failing ids to a retry table, and raise a diagnostic banner.

**Acceptance:** a unit test where one bad row in a page leaves the watermark unchanged and records a failure entry.

**Release-blocking:** No.

### SYNC-003 — Client-created table reservations are never pushed (D-3)

**Classification:** Confirmed defect (pre-existing). Severity Medium, priority P1. Confidence High [V].

**Location:** [table_session_service.dart:192-221](<../../../../lib/services/table_session_service.dart#L192-L221>) → [tables_dao.dart:621-646](<../../../../lib/data/database/daos/tables_dao.dart#L621-L646>): a local insert only. There is no `ClientWriteInterceptor` path or API route for reservations (grep in `lib/services`: only pull lists).

**Impact:** reservations made on a client terminal are invisible to the host and other terminals, so double booking is possible. A later pull may also collide on id (renumbering exists, [delta_pull_service.dart:1150-1170](<../../../../lib/services/delta_pull_service.dart#L1150-L1170>)).

**Remediation:** interceptor plus a host route carrying `global_id` and `party_global_id`; or block reservation creation on clients with a message.

**Release-blocking:** No (pre-existing), but it should be in the release note for multi-terminal restaurants.

### SYNC-004 — No host-side phone dedupe; duplicate customers across devices (D-4)

**Classification:** Confirmed. Severity Low, priority P2. Confidence Medium [V]: grep `normalizePhone|phoneKey` in `lib/services` returns 0 matches.

**Impact:** duplicate parties when two offline terminals create the same phone. The `party_dedup_suspects` tooling exists for manual merging.

**Remediation:** a host-side normalised-phone lookup in `createParty` that returns the existing party or records a suspect.

**Release-blocking:** No.

### SYNC-005 — Non-financial push conflicts are marked "synced" and the local change is dropped

**Classification:** Confirmed defect. Severity Medium, priority P1. Confidence High [V].

**Location:** [offline_sync_worker_drain.dart:255-334](<../../../../lib/services/offline_sync_worker/offline_sync_worker_drain.dart#L255-L334>).

- Any error string containing `409`, `Conflict`, `UNIQUE constraint`, `duplicate` or `already exists` on a non-financial table triggers `markAsSyncSuccess`, a server-wins pull and a `sync_conflict_log` row (`server_wins_pull_triggered`).
- Financial tables go to `pending_review` instead.

**Impact:** a client edit to a party, product or user that hits a uniqueness clash on the host is silently discarded (the UI says synced). Error-string matching is fragile (any message containing "duplicate").

**Remediation:** use a structured error code from the host; surface non-idempotent conflicts in the sync-failures UI instead of marking them as success.

**Acceptance:** a test where a party update conflicting on name is not marked synced and appears in the failures list.

**Release-blocking:** No.

### SYNC-006 — Client DB holds all scoped data regardless of user permissions

**Classification:** Info (design). Priority P3.

**Evidence:** `/api/sync/pull` scopes by branch and identity but not by per-table permission ([api_get_sync_pull.dart:32-180](<../../../../lib/services/api/routes/api_get_sync_pull.dart#L32-L180>)). Figure masking is a UI concern (SEC-008, AUTHZ-010).

**Consequence:** anyone with OS access to a client terminal and the DB key (SEC-005) reads all branch data. This is accepted by the offline-first design; document it.

**Release-blocking:** No.

### SYNC-007 — The cloud relay (ADR-M2 `/manage/commands` → `/desktop/relay/next`) is not implemented

**Classification:** Missing requirement. Severity Info, priority P2. Confidence High [V].

**Evidence**

- Server routes are only those in [app.dart:66-202](<../../../../server/lib/src/http/app.dart#L66-L202>) and [admin_routes.dart:28-95](<../../../../server/lib/src/http/admin_routes.dart#L28-L95>). There is no relay route and no `relay_queue` (grep `relay` in `server/lib`: 0 matches).
- The design lives in [ARCHITECTURE-M.md](<../../../mobile/ARCHITECTURE-M.md>) ADR-M2.

**Impact:** "PicPos إدارة" works from snapshots only (read-only); there are no remote commands or on-demand reports. This is not a defect, provided marketing and docs do not claim the feature.

**Release-blocking:** No.

---

## Positive controls verified (no finding)

- **Cloud tenant isolation:**
  - The company is always derived from the authenticated device or desktop link row, never from the body (`authenticateDevice` [auth_service.dart:105-139](<../../../../server/lib/src/service/auth_service.dart#L105-L139>)).
  - Pairing refuses a device id belonging to another company (`:80-82`).
  - Revoke is company-scoped for desktop callers (`:160-169`).
  - Employee active status is re-checked on every request (`:126`).
  - Tokens are random and stored as SHA-256, with rotation grace.
  - Login is limited to 10 attempts per device per 10 minutes; push to 60 per device per minute; admin key to 10 failures per IP per 10 minutes, compared in constant time.
  - A body-size limit is installed before auth ([app.dart:58-61](<../../../../server/lib/src/http/app.dart#L58-L61>)).
  - The 500 handler returns `internal_error` only (no stack trace to the client).
- **LAN pairing:**
  - 8-character one-time code, 10-minute TTL, 5 attempts per IP per 10 minutes, constant-time comparison.
  - Per-device token `HMAC(installSecret, deviceId)` with a random 32-byte install secret in secure storage; per-device revoke ([lan_pairing_service.dart:66-155, 394-422](<../../../../lib/services/api/lan_pairing_service.dart#L394-L422>)).
- **Identity:** the forged `X-User-Id` header is removed; identity comes only from the HMAC session token, and a body/session actor mismatch returns 403 ([api_user_context.dart:103-129](<../../../../lib/services/api/api_user_context.dart#L103-L129>)).
- **Users rows:** `pin` is never served; credentials are served only to a session or inside the pairing window ([api_get_sync_pull.dart:238-252](<../../../../lib/services/api/routes/api_get_sync_pull.dart#L238-L252>)).
- **Branch scope on transactional reads** is fail-closed (`-1` sentinel) for no identity and for mis-provisioned users ([api_branch_scope.dart:105-142](<../../../../lib/services/api/routes/api_branch_scope.dart#L105-L142>)). The client `branchScopeProvider` mirrors it ([branch_scope_provider.dart:157-292](<../../../../lib/data/providers/branch_scope_provider.dart#L157-L292>)).
- **SQL:** the pull table name comes from an allowlist ([api_get_sync_pull.dart:38-43](<../../../../lib/services/api/routes/api_get_sync_pull.dart#L38-L43>)); the client-side column filter now also restricts network-supplied column names to real local columns. Sampled DAO dynamic SQL interpolates only constants or placeholder lists.
- **Attachments** are stored as DB blobs (no filesystem path from the network); size, MIME and count are validated and the SHA is recomputed server-side ([api_data_attachments.dart:82-146](<../../../../lib/services/api/data/api_data_attachments.dart#L82-L146>)).
- **Mobile apps:** release manifests set `usesCleartextTraffic="false"`, a network security config with no cleartext, and `allowBackup="false"`.
- **Dependencies:** no Pub advisory listed on OSV (12 total, checked 2026-10-23 04:11 +03:00) affects the locked versions (see TEST-EVIDENCE-A §4).
