# Axis A — Project baseline: auth, permissions, scope and sync as implemented

| Item | Value |
|---|---|
| Repo | `D:\PICPOS-ERP` |
| Branch | `feat/tables-reservations-permissions` |
| HEAD | `d69be1eafc7d82b924723dfdbb53960b7e33acdb` (2026-10-23 03:08 +0300), version `3.9.2+277` |
| Base of candidate | `c5f5056c` (`3.9.1+276`). Candidate = 4 commits: `2eef5c0e`, `c56da2c9`, `d2272da0`, `d69be1ea` |
| Local changes | Untracked only (scratch `*.txt`, font folder, 2 Arabic design folders, 2 new plan docs, `طلب مراجعه.txt`). No tracked modification. |
| Remote | Not fetched; remote state unknown |
| Method | Read-only code reading. No runtime. Statements below describe the code, not observed runtime behaviour. |

## 1. Deployment modes

The modes are defined in `NetworkMode` ([network_service.dart:35-39](<../../../../lib/services/network_service.dart#L35-L39>)).

| Mode | Role | Data store | Network surface |
|---|---|---|---|
| `standalone` | Single device | Local SQLite + SQLCipher | None. The UI is the only entry point. |
| `server` (host) | Owns the data and serves LAN clients | SQLite + SQLCipher, or PostgreSQL (`drift_postgres`) | Embedded shelf server on `anyIPv4:<port>`. It serves HTTP by default; HTTPS only if `network_tls_enabled` ([network_service.dart:748-819](<../../../../lib/services/network_service.dart#L748-L819>)). Optional web access (`/api/web/*`, `/webdb`, static web app). |
| `client` (terminal) | Works offline against a local replica | Local SQLite + SQLCipher replica | Outbound to the host: delta pull, outbox replay (`ClientWriteInterceptor` → `ServerProxy`), WebSocket notifications |
| `mirror` | Admin laptop acting as a remote HQ console | Local replica of all branches the user is allowed | Same as client, but with device-level "mirror" scope rules |

**Cloud (separate product surface).** `server/` is a shelf + PostgreSQL service ("picpos_cloud") with three kinds of clients:

- mobile rep devices (`/mobile/*`);
- desktop links (`/desktop/*`);
- the admin mobile app "PicPos إدارة" (`/manage/*`).

It binds plain HTTP and expects TLS termination outside the process ([server.dart:63](<../../../../server/bin/server.dart#L63>)). The repository ships only a TEST docker stack.

## 2. Authentication

### 2.1 Local (all modes)

**Password login.** `authenticateUser` checks a username plus a password hash ([user_dao.dart:339-413](<../../../../lib/data/database/daos/user_dao.dart#L339-L413>)):

- It requires `is_active=1` and `is_locked=0`.
- Hashes are Argon2id (m=4096 KiB, t=3, p=1). Legacy PBKDF2-SHA256 (10k) hashes are verified and then rehashed ([security_service.dart:72, 142-215](<../../../../lib/services/security_service.dart#L142-L215>)).
- A dummy Argon2 runs on unknown users, as an enumeration defence.

**Password-only or card login.** `authenticateByPasswordOrCard` tries the input against every active user, then falls back to the card code ([user_dao.dart:460-510](<../../../../lib/data/database/daos/user_dao.dart#L460-L510>)).

- Used by the manager-override dialog, the session-lock screen and the close-shift dialogs.
- Duplicate passwords are refused at write time (`DuplicatePasswordException`).

**Lockout.** `LoginRateLimiter` allows 5 failures, then locks for 15 minutes. It is in-memory only, because the persistence hooks are never wired.

**Forced change and defaults**

- `force_password_change` is enforced by a non-dismissable dialog after a local login.
- The seeded admin is `admin`/`admin` with the flag set.
- The setup wizard replaces the admin password only in standalone mode.
- Several "self-heal" paths reset or re-create `admin`/`admin`:
  - boot structural heal ([database_startup.dart:798-889](<../../../../lib/data/database/database_startup.dart#L798-L889>));
  - fallback admin ([database_startup.dart:1240-1273](<../../../../lib/data/database/database_startup.dart#L1240-L1273>));
  - `GET /api/users` self-heal ([api_get_users.dart:163-256](<../../../../lib/services/api/routes/api_get_users.dart#L163-L256>)).

**Idle lock.** `SessionTimeoutWrapper` locks the POS after `posSessionTimeoutMinutes` (default 5).

### 2.2 LAN API (server mode)

Three layers, implemented in [api_auth_middleware.dart:214-318](<../../../../lib/services/api/api_auth_middleware.dart#L214-L318>):

1. **Transport: device bearer.**
   - Each device gets `HMAC(installSecret, deviceId)` after pairing. Pairing uses a one-time 8-character code with a 10-minute TTL and 5 attempts per IP. The random install secret lives in secure storage ([lan_pairing_service.dart](<../../../../lib/services/api/lan_pairing_service.dart>)).
   - During a 30-day "legacy transition" window, a shared bearer `sha256(legacySeed+salt)[:32]` is also accepted.
   - Exempt paths: `/api/health`, `/api/pair`, `/cfd`, `/menu`, `/ws`, `/api/table-bill`.
2. **Identity: `X-Session-Token`.**
   - An HMAC-signed `{uid, exp}` with a 30-day TTL, issued by `POST /api/auth/session` after the credential check ([api_session_token.dart](<../../../../lib/services/api/api_session_token.dart>); [api_auth_handler.dart:156-208](<../../../../lib/services/api/api_auth_handler.dart#L156-L208>)).
   - The signing key comes from `ServerSecrets` (random).
   - Stateless: there is no revocation.
   - The forged `X-User-Id` header is no longer read.
3. **Web sessions (`aud:'web'`).**
   - 12-hour TTL, a revocable `sid`, and per-user revocation (in-memory), optionally role-bound.
   - Checked by `WebSessionGuard`; requires an Origin allowlist.

### 2.3 Cloud

- **Mobile rep devices:** random device token stored as SHA-256, with a 24-hour rotation grace and per-device revoke. PIN login (PBKDF2-SHA256 120k) issues an HMAC session `{uid, did, cid, jti, exp}` with a 12-hour TTL.
- **Admin app:**
  - Pairing uses a one-time hashed code bound to `user_global_id`.
  - Login uses username + password with lockout (`failed_logins`, `locked_until`, 15 minutes) and a session revocation table.
  - Snapshots are Ed25519-signed by the desktop and verified on the phone with the public key received in the QR (fingerprint confirmed).
- **Desktop link:** a bearer + `X-Desktop-Link` row.
- **Admin key:** `X-Admin-Key` is for the test stack, with ≥ 24 characters enforced unless `ALLOW_WEAK_ADMIN_KEY=1`.
- **Tenant:** the company is always taken from the authenticated device or link row ([auth_service.dart:105-139](<../../../../server/lib/src/service/auth_service.dart#L105-L139>)).

## 3. Permissions: how they resolve

**Data model**

- Each user has one role (`users.role_id`). Codes come from `role_permissions`, each with a `grant_mode` (normal or conditional).
- `getUserPermissionCodes` returns `code` for every granted row, **plus** a `cond:<code>` marker for conditional rows ([permissions_dao.dart:251-314](<../../../../lib/data/database/daos/permissions_dao.dart#L251-L314>)).
- The system-admin role (`isSystemRole && name=='مدير النظام'`) gets every non-critical code plus a `system_admin` marker. `criticalFinancialOps` must be granted explicitly even to this role.

**UI checks**

| Check | Behaviour | Location |
|---|---|---|
| `PermissionGuard` / `hasPermissionWithAdminBypass` | `contains`, with an admin bypass that excludes critical ops | [permission_guard.dart:835-845](<../../../../lib/presentation/widgets/permission_guard.dart#L835-L845>) |
| `ensurePermission` | If the code is conditional, or the user lacks it, opens the manager-override dialog. A 60-second single-use `ManagerApprovalCache` token avoids double prompts. | [permission_guard.dart:863-890](<../../../../lib/presentation/widgets/permission_guard.dart#L863-L890>) |
| Table actions | `tableActionGate` returns allowed / needsApproval / denied | [table_action_gate.dart](<../../../../lib/presentation/screens/tables/table_action_gate.dart>) |

**Screen access (new in `c56da2c9`)**

- `canOpenScreen = bypass || any code in screenPermissionSet(id)`. The set is the primary code from `screenPermissionMap` plus `screenActionCodes[id]`.
- `strictPermissionScreens` (settings, users, roles) keep the single primary code.
- The rule grants no read or action rights by itself ([screen_access_resolver.dart](<../../../../lib/core/permissions/screen_access_resolver.dart>)).
- Menu, allowed screens and the default-screen dropdown all use `screenVisibleToUser` ([screen_access_selectors.dart](<../../../../lib/data/providers/screen_access_selectors.dart>)).

**Figure masking (new in `d2272da0`)**

- `canSeeScreenFigures(perms, screen)` requires any of `screenFigurePermissionCodes[screen]` (the view code or dedicated figure codes), with an admin bypass ([financial_figures_access.dart](<../../../../lib/core/permissions/financial_figures_access.dart>)).
- Exposed as `screenFiguresVisibilityProvider`.
- Applied widget by widget in list and card views (not in details, statements or exports — see AUTHZ-002/003).

**Service and DAO layer**

- `PermissionEnforcer.requireCriticalOp` is used only for critical financial operations (about 10 call sites).
- Everything else is enforced in the widget layer.

**API layer**

- `ApiUserCtx.requirePermission(request, db, code)` runs on mutation routes ([api_user_context.dart:47-85](<../../../../lib/services/api/api_user_context.dart#L47-L85>)). It calls `userHasPermission`, which does not distinguish conditional grants and does not check whether the user is active.
- A source-grep test guards that every mutation handler has a gate or an `EXEMPT-PER-USER` marker.
- GET handlers are not permission-gated for device sessions; web sessions use `WebHttpReadGate`.
- `resolveActor` refuses a body `userId` that differs from the session.

## 4. Branch scope: how it resolves

**Client UI: `branchScopeProvider`** ([branch_scope_provider.dart:157-292](<../../../../lib/data/providers/branch_scope_provider.dart#L157-L292>)). The order is significant:

1. **Mirror device:** the user's assigned branches. If none, full access when privileged, otherwise an empty scope (fail-closed).
2. **Cross-branch elevated** (unrestricted system admin on a live client): full access.
3. **Client with branch isolation on:** the device's `client_branch_id`.
4. **No assignments:** full access when privileged (`isFullBranchAccessUser`), otherwise an empty scope.
5. **Otherwise:** the assigned branch set (direct or by region).

Lists pass `allowedBranchIds` to DAOs (for example `watchAllPartiesForBranches`, sales invoices).

**Host API: `_resolveBranchScope`** ([api_branch_scope.dart:105-142](<../../../../lib/services/api/routes/api_branch_scope.dart#L105-L142>)):

| Caller | Transactional endpoints | Reference endpoints |
|---|---|---|
| No identity | `[-1]` (zero rows, fail-closed) | Honour the requested `branch_id`, or everything |
| Identity | Clamp to allowed branches; full access only for privileged users; mis-provisioned users get `[-1]` | Same |

- `/api/sync/pull` uses the full allowed set (FR-1) and includes rows where `branch_id IS NULL`.
- `GET /api/parties` is not scoped.

**Cloud admin:** snapshots are filtered by the mirrored permission codes and branch scope (`AdminService.codesForKind`, `branch_scope` jsonb).

## 5. Sync: as implemented

**Pull (client/mirror ← host)**

- `DeltaPullService` iterates a fixed, FK-ordered `pullTables` list ([delta_pull_service.dart:53-200](<../../../../lib/services/delta_pull_service.dart#L53-L200>)).
- For each table it calls `GET /api/sync/pull?table&since&limit&cursorTs&cursorId` (keyset paging by `(last_modified_at, id)`, 500 rows per page).
- The watermark is the **server time from the first page** and advances only after the last page.
- Per row:
  - natural-key or `global_id` matching;
  - a financial pending-outbox conflict goes to `sync_conflict_log` as `pending_review`;
  - per-table conflict policy (`ConflictResolutionService`);
  - soft-delete via `deleted_at`;
  - party FK remap (sales/purchase invoices, safe transactions, **table reservations, bookings**);
  - blob preservation;
  - **column filter to local columns (new; v196+ clients only)**;
  - in-place update when local id ≠ server id;
  - collision renumbering;
  - users credential preservation (or the predictable temp password, SEC-004);
  - `INSERT OR REPLACE`.
- Per-row failures are logged with `debugPrint` and do not stop the watermark.

**Host side of pull** ([api_get_sync_pull.dart](<../../../../lib/services/api/routes/api_get_sync_pull.dart>)):

- table allowlist;
- transactional tables need identity;
- branch predicate;
- credential columns withheld unless a session exists or the pairing window is open; `pin` is never served;
- `SELECT *` for the remaining columns;
- `journal_entry_lines` embedded.

There is no schema or version handshake.

**Push (client → host)**

- Writes on a client go through `ClientWriteInterceptor` (`lib/services/interceptor/cwi_*.dart`) to the server API, or into the `sync_outbox` while offline.
- `OfflineSyncWorker` replays the outbox in order with a stable idempotency key per item (`x-idempotency-key` is honoured by the sales, purchases and journals handlers; others dedupe by `global_id`).
- Retries are bounded; errors are classified as permanent (dead-letter with a UI) or conflict.
- On conflict:
  - non-financial tables: marked as synced, and a server-wins pull is triggered (SYNC-005);
  - financial tables: logged as `pending_review`.
- Table reservations have **no** push path (SYNC-003).

**Realtime.** A WebSocket (`/ws`, bearer-verified) notifies clients to pull.

**Cloud sync.** The desktop (`CloudSyncService` and posters) pushes master data, documents and admin snapshots to `/desktop/*` and acknowledges field documents. Mobile devices push field documents (max 50 per request, 60 per minute) and pull master data. There is no command/query relay (ADR-M2 is not implemented).

## 6. Secrets inventory (locations, no values)

| Secret | Where | Protection |
|---|---|---|
| SQLCipher key (new installs) | `flutter_secure_storage` (Windows: AES-GCM with a key in Credential Manager / DPAPI user scope), plus the non-secret `<db>.keyinfo.json` | Windows user account |
| SQLCipher key (upgraded installs) | Derived: `sha256(deviceId:pepper)`; the pepper is in source | Effectively none against local readers (SEC-005) |
| Recovery envelope | `<db>.keyinfo.json` `recoveryEnvelope` (Argon2id KEK + AES-GCM) | Recovery code |
| LAN install secret / server session key / table-bill key | Secure storage (`ural_lan_install_secret_v1`, `ServerSecrets`) | Windows user account |
| Legacy LAN bearer | Derived from the legacy seed during the transition window | None (SEC-006) |
| Desktop Ed25519 admin signing seed | `CloudLinkConfigStore` secret `cloud_link_admin_signing_seed` | Secure store |
| Cloud `TOKEN_SECRET`, `ADMIN_KEY`, DB password | Environment variables (test values in `docker-compose.yml`) | Deployment |
| User password hashes / PIN / card code | `users` table (synced to clients with restrictions) | Argon2id; PIN never served |

## 7. Open questions for the owner

1. Is renaming the built-in `admin` a supported scenario? It determines the SEC-001 fix (forbid rename, or stable identity).
2. Should `sales_view` alone reveal invoice amounts, or should `sales_amounts_view` remain the gate (AUTHZ-004)? Should `inventory_view` reveal cost (AUTHZ-009)?
3. Is a simultaneous upgrade of host and all clients enforced for 3.9.2 (SYNC-001)?
4. Is the "trusted LAN, HTTP by default" assumption acceptable for field deployments (SEC-007)?
5. Should DB-key migration become automatic or nagging after upgrade (SEC-005)?
