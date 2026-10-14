# Phase M — «PicPos إدارة» (M-A) and «PicPos كاشير» (M-B) Android apps (Architecture)

> Status: M-A cloud pairing, login, and signed snapshots are implemented and [covered by E2E tests](../testing/E2E.md); Reports (M-2), Operations (M-3), and Notifications (M-4) remain placeholders. `mobile_pos` remains an M-0 preview with no connected POS client or M-5/M-6 flows, while desktop POS pairing and branch-scoped terminal allocation are implemented. The rest describes the target architecture; see [M-0 notes](M-0-NOTES.md) and [§4.1](#41-phases).
> Companion of `docs/mobile/ARCHITECTURE-I.md` (cloud server, rep app `picpos_van`, desktop↔cloud sync I-1..I-4 + K). Terms, header names and sync conventions defined there are reused here without repetition.
>
> **Owner decisions (final):** two NEW Android apps; the rep app `picpos_van` (`mobile/`) stays as is. Signed APKs first for owner review, Google Play later (AAB, signing, icons, privacy policy prepared; the owner publishes).
> - **M-A «PicPos إدارة»** — owner / finance manager / accountant, permission-based; reaches the business through the **cloud** from anywhere and **directly over the shop LAN** when the desktop is reachable. Release 1 = KPI dashboard + approvals + financial reports (PDF/Excel/share) + accounting operations + instant notifications.
> - **M-B «PicPos كاشير»** — tablet POS, works **offline**, syncs with the main desktop over the shop LAN as a **client device**.
> - Identity per `DESIGN.md` (Material 3 with PicPos tokens, Cairo UI, Noto Naskh print), AR/EN, light/dark, phone + tablet layouts.

Evidence read for this plan (read-only): `PRODUCT.md`, `DESIGN.md`, `docs/mobile/ARCHITECTURE-I.md`, `server/` (`lib/src/http/app.dart`, `lib/src/security.dart`, `lib/src/service/{auth,desktop,sync}_service.dart`, `lib/src/service/rate_limiter.dart`, `lib/src/db/migrations.dart`, `bin/server.dart`, `Dockerfile`), `docker/docker-compose.yml`, `mobile/` (`pubspec.yaml`, `lib/theme/brand_theme.dart`, `lib/l10n/strings.dart`, `lib/data/{sqflite_store,db_key,cloud_api,local_store}.dart`, `lib/sync/*`, `lib/printing/*`, `android/app/build.gradle.kts`, `AndroidManifest.xml`), `packages/*` (only `picpos_rules` is used), desktop `lib/services/api/**`, `lib/services/interceptor/cwi_*`, `lib/services/delta_pull_service.dart`, `lib/services/network_service.dart`, `lib/core/permissions/permission_codes.dart`, `lib/data/database/daos/{permissions,accounting_reports,accounting_dao_reads,accounting_dao_writes,party,treasury,treasury_voucher,commercial_papers,hr_leave,hr_payroll_posting,sales_held_orders}_dao.dart`, `lib/presentation/{pos_picpos,sales_returns_picpos,purchase_returns_picpos,accounting_picpos}/**`, `lib/presentation/widgets/permission_guard.dart`, `lib/services/manager_approval_cache.dart`, `lib/services/notification_triggers_service.dart`, `lib/services/cloud_sync/*`, root `pubspec.yaml`.

---

## 0. Facts that drive the decisions

| # | Fact (verified by reading) | Source |
|---|---|---|
| F1 | The repo has **no `android/` folder** for the desktop app `ural_erp`; the desktop pulls Windows-only plugins (`serial_port_win32`, `window_manager`), a Win32 FFI scale SDK (`lib/services/aclas_sdk_ffi.dart`), Win32 CFD transports, a Windows cash-drawer path (`lib/services/cash_drawer_service_io.dart`) and 16 `Platform.isWindows` branches in 10 files (licensing `license_service.dart`, `security_service.dart` machine seed, touch keyboard, login). | root `pubspec.yaml`, grep |
| F2 | A desktop LAN client is a **full Drift mirror** (schema v194, `lib/data/database/database.dart:1209`) kept by `DeltaPullService` (per-table watermarks, keyset `(last_modified_at, id)`) + WebSocket `data_changed` (`/ws`) + an adaptive poll; writes go through `ClientWriteInterceptor` (`lib/services/interceptor/cwi_core.dart`) to the LAN API, offline writes are queued in `sync_outbox` (`cwi_core_support.dart::tryOrQueue`). | LAN survey |
| F3 | LAN API (`lib/services/api/api_handler.dart`): flat `/api/...` routes (~150), device auth = `Bearer HMAC(installSecret, deviceId)` + `X-Device-Id` (`api_auth_middleware.dart`, `lan_pairing_service.dart`), user session = HMAC token from `POST /api/auth/session {username,password|cardCode}` verified against desktop `Users` (`api_auth_handler.dart`), per-route `ApiUserCtx.requirePermission` (`api_user_context.dart:47`), idempotency via `x-idempotency-key` + `processed_messages` and `globalId` dedup (`api_handler_base.dart:77-147`, `api_sales_handler.dart:116-169`). Plain HTTP unless TLS is configured; TLS cert fingerprint pinning exists (`TlsTrust`). Pairing QR = `{serverHost, port, pairingCode, serverFingerprint}`. | LAN survey |
| F4 | LAN sale numbering: the client numbers locally; the server keeps a number that already starts with `<branchCode>-`, otherwise prefixes it (`<BRANCH>-POS-1` / `CLT<ip>-POS-1`) (`api_sales_handler.dart:85-108`). `POST /api/sales` posts through `db.createSalesInvoice` with `sales_create` (`api_sales_handler.dart:34, 282`). | code |
| F5 | Cloud has **no** WebSocket/SSE/long-poll, **no** push code, **no** roles: actors are reps (device-bound employees), the desktop link (`X-Desktop-Link` + bearer secret, SHA-256 stored), and the test admin key. Only worker = 10 s `Timer.periodic` for the WhatsApp outbox (`server/bin/server.dart:46-53`). 6 migrations (`server/lib/src/db/migrations.dart`). | server survey |
| F6 | Desktop→cloud is **pull-based**: `CloudSyncScheduler` (`lib/services/cloud_sync/cloud_sync_service.dart`, default 5 min, 1–1440, never on a LAN client) polls `/desktop/documents/pending`, posts, acks, pushes master. **No cloud→desktop command channel exists.** | cloud_sync survey |
| F7 | Financial statements are Drift DAO SQL on desktop: `AccountingReportsDao.getTrialBalance/getIncomeStatement/getBalanceSheet/getCashFlowStatement` (`accounting_reports_dao.dart:95/231/456/560`, params `from,to,costCenterId,branchId(s),allowedBranchIds`), `getAccountLedger` (`accounting_dao_reads.dart:648`, paged), `PartyDao.getPartyStatement` (`party_dao.dart:1623`), `getArAgingReport` (`party_dao.dart:2198`), `getReceivablesAging/getPayablesAging` (`accounting_audit_dao.dart:116`). KPIs: `dashboardKpiProvider` (`lib/data/providers/dashboard_filter_provider.dart:95`, revenue/net profit from `getIncomeStatement`). | reports survey |
| F8 | Approvals that exist: return drafts `return_drafts(kind,status draft→posted/cancelled)` approved by `sales_return_approve` / `purchases_return_approve`; leave `hr_leave_requests` (`approveLeaveRequest/rejectLeaveRequest`, `hr_leave_dao.dart:354/387`, `hr_leave_approve`); payroll `draft→reviewed→approved→posted→paid` (`approvePayrollRun`/`postPayrollRun`, `hr_payroll_posting_dao.dart:12/82`); manager override = second user's password/card in `_ManagerOverrideDialog` → `ManagerApprovalCache.grant` (60 s single use) (`permission_guard.dart:566-863`, `manager_approval_cache.dart:33`); credit override `override_credit_limit` (critical, no admin bypass, `permission_codes.dart:931,988-995`); per-user discount cap `Users.maxDiscountPercent/discountLimitIsPercent`; journal maker-checker `approveJournalEntry` (`approve_journal`). | permissions survey |
| F9 | Operations: `createReceiptVoucher/createPaymentVoucher` (`treasury_repository_impl.dart:146/274`; fiscal-period check; cash non-central safes need an open shift via `drawerMovementAllowed`, `treasury_dao.dart:1573`), `createJournalEntry` (`accounting_dao_writes.dart:45`), `changePaperStatus` (`commercial_papers_dao.dart:169`, auto-posts). | reports survey |
| F10 | Desktop notifications: table `Notifications` + `NotificationTriggersService.runAllChecks` covers **only** low stock (daily) and backup reminder (`notification_triggers_service.dart:21`). No large-invoice / shortage / custody triggers. | permissions survey |
| F11 | The rep app already solves on Android: SQLCipher store with Keystore-held key (`mobile/lib/data/sqflite_store.dart`, `db_key.dart`), outbox + backoff + WorkManager (`mobile/lib/sync/*`), Bluetooth ESC/POS raster Arabic printing 58/80 with retry queue (`mobile/lib/printing/*`), camera barcode (`mobile_scanner`), DESIGN.md theme (`mobile/lib/theme/brand_theme.dart`), hand-rolled AR/EN `S` table (`mobile/lib/l10n/strings.dart`), `ChangeNotifier` state. Gaps: release signed with debug keys, no adaptive icon, `usesCleartextTraffic="true"`, applicationId `com.picpos.picpos_van`. | mobile survey |
| F12 | `packages/` holds six unused Flutter skeletons (`accounting`, `core`, `inventory`, `pos`, `shared_widgets`, `treasury`, all UralCash-era, `sdk ^3.10.4`) and the one live pure-Dart package `picpos_rules` (tax, totals, pricing, returns math, credit rule, payment method, integrity, barcode normalize, company identity, receipt QR). | mobile survey |
| F13 | Desktop users: `Users` table (`auth_tables.dart:64`), Argon2id hashes (`security_service.dart:166`), one role per user, `RolePermissions.grantMode allow|conditional` (`cond:` marker), check `userHasPermission` (`permissions_dao.dart:218`) / `getUserPermissionCodes` (`:251`). **No 2FA.** | permissions survey |

---

## 1. Decision records

### ADR-M1 — Code sharing: two new lightweight Flutter apps + shared packages (not `ural_erp` on Android)

**Decision.** Two new Flutter apps in the monorepo, `mobile_admin/` (package `picpos_admin`) and `mobile_pos/` (package `picpos_pos`), sharing:

| Package (new unless noted) | Kind | Contents | Users |
|---|---|---|---|
| `packages/picpos_rules` (existing) | pure Dart | totals/tax/pricing/returns/credit/payment-method/integrity/barcode/identity/QR | server, picpos_van, M-A (display math only), **M-B** |
| `packages/picpos_api_client` | pure Dart (`http`, `crypto`, `cryptography`) | DTOs + clients for the cloud `/manage/*` API and the LAN `/api/m1/*` API; auth header builder (`Authorization`, `X-Device-Id`, `X-Session-Token`, `X-Idempotency-Key`); error mapping (`ApiError{code,message,retryAfter}`); canonical-JSON + Ed25519 snapshot verification; transport selector (LAN-first, cloud fallback) | M-A, M-B; contract tests run it against the docker cloud and the desktop harness |
| `packages/picpos_ui` | Flutter | `PicPosTokens` (all `DESIGN.md` colours, radii, spacing), `buildPicPosTheme(brightness)` lifted from `mobile/lib/theme/brand_theme.dart`, Cairo + Noto Naskh font assets, the six getters (`context.picposCard/Field/Hairline/Text/Muted/BrandInk`), widgets: `PicPosPageHeader` (2.5 px stripe), `KpiCard`/`HubKpiCard`, `StatusPill`, `PicPosBlock`, mobile `PicPosDataList` (card rows < 600 dp, table ≥ 600 dp, tabular figures), `AmountText`, `AsOfBadge` (freshness), `EmptyState`, `PicPosDialog`, adaptive scaffold (bottom nav < 600 dp, navigation rail ≥ 600 dp, two-pane ≥ 840 dp), `L10n` infra (the `S`-table pattern with `(ar,en)` pairs + coverage test helper) | M-A, M-B (picpos_van may migrate later, optional) |
| `packages/picpos_device` | Flutter | encrypted store opener + Keystore key (from `mobile/lib/data/{sqflite_store,db_key}.dart`), outbox primitives + `Backoff` + connectivity source (from `mobile/lib/sync/sync_scheduler.dart`), printing (from `mobile/lib/printing/*`: raster renderer, `escpos.dart`, composer base, `PrintService` queue) **plus a new TCP:9100 network transport and drawer kick**, barcode scanner screen + keyboard-wedge listener, app-lock (PIN/biometric) | M-A (store, lock), M-B (all), picpos_van later |

The rep app keeps its own copies until a separate, opt-in migration (owner decision: it stays as is). The six UralCash-era skeleton packages are **not** used (Principle 5: no UralCash trace; their `core` depends on drift/riverpod/google_fonts and would drag the desktop stack in).

State management: `ChangeNotifier` + `InheritedNotifier` as in `picpos_van` (proven, zero extra deps). Local DB: `sqflite_sqlcipher` as in `picpos_van` — one SQLCipher build per APK, the same key handling, and a known-good migration path. (Drift + `sqlcipher_flutter_libs` would also run on Android, but mixing both SQLCipher stacks in shared packages risks two native libs; not needed for the M-B schema of ~15 tables.)

**Rejected: compile `ural_erp` for Android with a tablet POS shell.** Justification:
1. **Platform debt (F1):** no Android project; Windows-only plugins and FFI must be conditionally removed; licensing and DB-key derivation use a Windows machine seed (`license_service.dart:108`, `security_service.dart:438`); every one of these is a change inside the desktop that ships to both brands (risk to Principle 5 and to UralCash).
2. **Wrong client model (F2):** a desktop LAN client is a full 194-version Drift mirror with dozens of delta-pulled tables, a WebSocket, a `sync_outbox` and server-side re-numbering. On a tablet this means a large DB, long first sync, the full migration chain on every app update, and the same `ClientWriteInterceptor` surface (sales, purchases, parties, users, settings…) a cashier never needs.
3. **Size and startup:** the desktop bundles all editions, PDF templates, audio, Supabase, Postgres drivers and hundreds of screens; the tablet POS needs one flow. Expected release APK: ~20–30 MB (M-B) vs. far larger for the whole desktop, with slower cold start.
4. **UX:** desktop POS screens are designed for 1366×768 + keyboard + mouse (`DESIGN.md` Layout); a touch tablet POS needs a different layout anyway (items grid, large targets), so the reusable part is the rules, not the widgets.
5. **Accounting parity is not lost:** posting stays on the desktop (the LAN server posts every M-B sale with the same `createSalesInvoice` path as desktop clients — F4), and client-side math uses `picpos_rules`, already pinned against the desktop by `docs/mobile/fixtures/pricing_parity.json`.

What **is** reused from the desktop, by contract (not by compiling its code): LAN pairing, device token, user session, permission codes and their server-side checks, idempotency key + `globalId` dedup, `{rows, hasMore, serverTime}` delta-pull shape, `/ws` `data_changed` events, the numbering rule of F4, posting paths, report DAOs.

### ADR-M2 — M-A data access: desktop computes, cloud relays; LAN goes direct to the same executor

Principle: **the ledger is the truth** → every number M-A shows is computed by the desktop's existing DAOs over the desktop ledger. The cloud **never** computes an accounting figure and holds no journal mirror.

**Rejected: a ledger mirror in the cloud** (replicate `journal_entries`/lines, compute reports in Postgres). It duplicates `accounting_reports_dao.dart` (trial balance hierarchy, cost centers, branch scope, FX, closing entries) in a second engine — two engines drift, which is exactly the failure Principle 1 forbids; it also uploads the full ledger to an Internet host.

**Chosen design — three channels, one desktop executor:**

```
 M-A ──HTTPS──▶ cloud /manage/*  ──(queue rows)──▶ /desktop/relay/next (long-poll) ──▶ Desktop
  │                   ▲                                                              MobileGateway
  │                   └──────── /desktop/relay/results, /desktop/snapshots, /desktop/events ◀──┘  (executor)
  │                                                                                     ▲
  └──LAN (TLS, pinned)── /api/m1/admin/* on the desktop LAN server ─────────────────────┘ same executor
```

1. **Pushed snapshots (fast, available when the desktop is off).** The desktop builds and pushes on every cloud-sync run (default 5 min, `CloudSyncScheduler`) and on demand:
   - `kpi.today` / `kpi.month` per branch and total: net sales, invoice count, returns, **gross profit** (revenue − COGS from the income-statement sections; the desktop dashboard shows net profit only — the gross figure must come from the same `getIncomeStatement` grouping, verified by a parity test), discounts given.
   - `cash.position`: balance of every cash and bank **account in the GL** (not safe running totals) per safe/bank, + rep custody safes.
   - `parties.position`: AR / AP totals, top 20 debtors/creditors, aging buckets (0–30/31–60/61–90/90+) from `getArAgingReport` / `getPayablesAging`.
   - `branches.performance`, `reps.performance` (sales, collections, returns, visits, custody balance — from the distribution/rep DAOs; source to be pinned in M-1).
   - `approvals.inbox`: a projection of pending items from the real source tables (F8), each with `ref`, `version`, summary and amount.
   Snapshots replace the previous one of the same `(kind, scope)`; daily `kpi.today` snapshots are kept 35 days (month/day comparisons); everything else keeps only the latest.
2. **Queries on demand (reports).** M-A posts a query `{queryId, type, params}`; the desktop's relay worker long-polls `GET /desktop/relay/next?waitMs=25000`, runs it through `MobileGateway` (a new desktop service calling the existing DAOs with the **requesting user's** branch scope and permissions), and posts the JSON result. Results are cached 24 h per `(type, canonical params, user scope)`; a repeat request with the same params is served from cache when `< 10 min` old unless `fresh=true`.
3. **Commands (approvals and accounting operations).** M-A posts `{commandId, type, params, expectedVersion}`; the cloud stores it `queued`; the desktop executes it through the **existing posting code** (table in §2.3), records it in a desktop raw table `remote_commands(command_id PK, type, user_global_id, status, result_json, executed_at)` (same pattern as `cloud_sync_documents`, I-3) for exactly-once execution, and acks `{done | rejected{code}}`. The phone sees the result via `GET /manage/commands/{id}` and a notification.
4. **LAN direct.** When the phone is on the shop network and the desktop answers `/api/m1/info` within 1.5 s with the pinned TLS fingerprint, M-A calls `/api/m1/admin/query` and `/api/m1/admin/command` on the LAN server — **the same `MobileGateway` executor and the same `remote_commands` table**, so a command first tried on LAN and retried via cloud (or vice versa) executes once (`commandId` is the idempotency key across both transports).

**Integrity of figures.** At link time the desktop generates an **Ed25519** key pair (`cryptography` is already a desktop dependency); the public key goes to the cloud with the link and to the phone inside the pairing QR (so the phone pins it without trusting the cloud). Every snapshot and query result is signed over its canonical JSON (UTF-8, sorted keys, no whitespace, **amounts as decimal strings** at company `decimal_places`, timestamps ISO-8601 UTC). The phone verifies before display; a bad signature shows «تعذّر التحقق من البيانات» and nothing else. The cloud therefore cannot alter a figure undetected.

**Freshness and latency targets.**

| Data | Channel | Freshness shown | Target |
|---|---|---|---|
| Dashboard KPIs | snapshot (cloud) / live (LAN) | `AsOfBadge` with the desktop's `asOf`; amber after 15 min, red after 60 min; "pull to refresh" sends query `kpi.refresh` | LAN < 1 s; relay p50 < 3 s, p95 < 10 s while the desktop is online |
| Reports | query | computed-at time on the report header | same as above; desktop offline → last cached result ≤ 24 h with a banner, else `desktop_offline` |
| Approvals inbox | snapshot + `approval.*` events | per item `asOf`; executing a command re-validates `expectedVersion` on the desktop | — |
| Commands | queue | `queued → executing → done/rejected/expired` | executed within seconds while the desktop is online; expiry 24 h (operations) / 7 days (approvals) |

Desktop liveness: the cloud records `desktop_links.last_seen_at` on every desktop call; M-A shows «جهاز المكتب غير متصل منذ …» when it is > 2 min old.

**Security.** TLS only; the cloud stores snapshots/results in Postgres (business data at rest on the owner's host, retention above, deletion on unlink); per-user scope is enforced twice — the cloud filters what it returns by the mirrored permissions and branch scope, and the **desktop re-checks** `userHasPermission` and `allowedBranchIds` when it executes (desktop is authoritative; a permission revoked on desktop is effective at the next command even before the mirror updates). End-to-end encryption of payloads (cloud as a blind relay) is possible later with the same key material — open question Q6.

### ADR-M3 — Auth: desktop users, a separate mobile credential, device pairing, optional TOTP

- **Who can use M-A:** a desktop user (`Users`) whose role has the new code `mobile_admin_access` (§3.3) and whom an admin has **enabled for mobile** on the desktop (Users screen → «تفعيل تطبيق الإدارة»).
- **Credential:** a **mobile password** (≥ 8 chars) set on the desktop, separate from the desktop password. The desktop hashes it as `pbkdf2$120000$salt$hash` (the cloud's existing format, `server/lib/src/security.dart:32-67`) and pushes `POST /desktop/users` `{globalId, username, displayName, locale, mobileEnabled, mobilePasswordHash, permissions[], conditional[], branchScope, require2fa, version}`. The desktop's Argon2 hash **never leaves the desktop**; the cloud never sees a desktop password. Changing the mobile password from the phone is a command (`user.change_mobile_password`, the phone sends a fresh PBKDF2 hash, never the plaintext) executed by the desktop and mirrored back; the old password stays valid until then.
- **Permission mirror:** `permissions[]` = the user's codes from `getUserPermissionCodes` filtered to the M-A/M-B set (§3.3), including `cond:` markers; pushed on change and on every sync run. Used by the cloud to filter, by the app to show/hide; **re-checked by the desktop at execution**.
- **Pairing (one QR, both channels):** desktop (admin with `users_manage`, existing user-management permission) → «ربط جوال» for a user → the desktop asks the cloud for a pairing code (`POST /desktop/pairing-codes {kind:'admin', userGlobalId}`, extension of the existing endpoint) and opens a LAN pairing offer; it shows one QR: `{v:1, cloudUrl, cloudCode, lanHost, lanPort, lanCode, lanTlsFingerprint, desktopSigningKey (Ed25519 pub, base64), company}`. The phone pairs with both (`POST /manage/pair`, `POST /api/pair`), stores the cloud device token and the LAN device token in the Keystore-backed store, and pins the LAN TLS fingerprint and the signing key. Same code rules as today (8 chars, no look-alikes, 10 min, single use, 5 attempts/IP/10 min). Manual entry (code + URL) is the fallback when the camera cannot scan.
- **Login:** cloud `POST /manage/login {username, password, totp?}` with the device token → session token (same HMAC format `{uid,did,cid,exp}`, 12 h); LAN `POST /api/m1/auth/session` verifies the **same mobile credential** on the desktop. Rate limits as I-1 (login 10/device/10 min) + per-user lockout after 5 failures for 15 min (same policy as `LoginRateLimiter`).
- **App lock:** after login, re-open requires a local 4–6-digit app PIN or biometric (`local_auth`); the session sits in the encrypted store. Idle lock 5 min.
- **Step-up:** commands of class `financial` (vouchers, journals, payroll post, cheque status, credit override) require a re-entered password or TOTP within the last 5 minutes (`X-Step-Up` token from `POST /manage/step-up`). Approvals of drafts/leave require the session only.
- **2FA (optional, recommended for the owner):** TOTP (RFC 6238, 30 s, 6 digits) enrolled from the phone after first login; the secret is generated and stored by the **cloud** (encrypted with a server key), because the Internet-facing login is the one that needs it; `require2fa` per user is set on the desktop and mirrored. The LAN login does not ask for TOTP (physical presence on the shop LAN + paired device + password).
- **Revocation:** unpair on desktop or `devices.revoked_at` → 401 `device_revoked` → app wipes local data (same as picpos_van). Disabling the user on desktop revokes all their devices at the next users push.
- **M-B auth:** LAN pairing (`/api/pair`) bound to a **terminal**, not to a person; cashiers log in with username + PIN via `/api/m1/auth/session` (desktop `Users.pin`, Argon2, `permissions_dao.dart:360`). For offline user switching the tablet keeps, per user who logged in online on that tablet in the last 7 days, a local PBKDF2 verifier of the PIN + the last permission set + `maxDiscountPercent`; offline sessions are tagged and the server re-checks permissions when the queued documents are posted.

### ADR-M4 — Notifications: desktop event producers → cloud fan-out → FCM wake-up + in-app inbox

**Evaluation.**

| Option | Instant when app closed | Battery / Android limits | Infra | Verdict |
|---|---|---|---|---|
| In-app polling (`/manage/notifications?since=`) | No (WorkManager ≥ 15 min, Doze defers) | fine | none | keep as **fallback + source of truth** |
| WebSocket / SSE | Only with a foreground service (permanent notification) | poor | cloud has none (F5); sticky connections + proxy config | rejected for release 1 |
| **FCM** (HTTP v1) | **Yes** (high-priority data messages) | system-managed | owner's Firebase project, `google-services.json`, service-account key on the server | **recommended** |

**Decision:** FCM is the wake-up channel; the cloud inbox (`notification_events`) is the source of truth the app reads on open/tap, so a lost push loses nothing. Provider abstraction like WhatsApp (`PushProvider` with `MockPushProvider` for the docker test stack — records sends in a table — and `FcmPushProvider`, disabled until `PUSH_PROVIDER=fcm` + `FCM_SERVICE_ACCOUNT_JSON` are set). Devices without Google Play services fall back to foreground polling (30 s while open) + WorkManager (15 min). The test server works without Firebase (mock + polling); real pushes need the owner's Firebase project.

**Producers (desktop, PicPos brand only).** A desktop raw table `mobile_events(event_id UUIDv7 PK, type, severity, branch_id, ref_table, ref_id, params_json, occurred_at, pushed_at)` written **after commit** by thin hooks; the relay worker pushes unpushed rows immediately (`POST /desktop/events`), the sync run catches up.

| Event `type` | Trigger point (existing code) | Default threshold (owner can change in desktop settings) |
|---|---|---|
| `sales.large_invoice` | after `createSalesInvoice` / `completeSalesTransaction` commit | total ≥ 1,000 (company currency) |
| `sales.unusual_discount` | same; discount % of gross | ≥ 15 % or above the cashier's `maxDiscountPercent` (i.e. a manager override was used) |
| `shift.cash_variance` | after `closeShiftWithAudit` (`treasury_dao.dart:459`, variance from `_settleShift`) | \|variance\| ≥ 5 |
| `custody.overrun` | cloud-side on an expense flagged `overCustody` (K-1) + desktop custody check on posting | any |
| `stock.low` | extend `NotificationTriggersService` low-stock check (`notification_triggers_service.dart:21`) to emit one digest event | product `min_stock` (existing); at most one digest per 6 h |
| `approval.pending` | new return draft, leave `submitted`, payroll `reviewed`/`approved`, override request, field customer created | any |
| `command.result` | after a remote command executes | always to the requester |

**Fan-out (cloud):** recipients = active M-A users whose mirrored permissions match the event (table in §3.3) and branch scope contains `branch_id`, minus user preferences (`notification_prefs` per type: push/inbox/off, quiet hours). Push payload is **data-only, no amounts or names** (`{eventId, type, branchName}` + a localized generic title, e.g. «فاتورة كبيرة — فرع وسط البلد»); details are fetched after login/app-lock, so a lock-screen preview leaks nothing financial (owner may opt into amounts — Q5).

### ADR-M5 — M-B LAN client: thin offline POS on a versioned LAN adapter

**Protocol reuse.** M-B reuses the LAN server's pairing (`POST /api/pair` → HMAC device token), device-auth middleware, `ApiUserCtx.requirePermission`, `x-idempotency-key` + `globalId` dedup, `/ws` `data_changed` events (to trigger pulls) and the `{rows, hasMore, serverTime}` keyset pull shape. It does **not** reuse `ClientWriteInterceptor` or the full delta pull: those assume a full local Drift mirror with server-matching integer ids. Instead the desktop gains a small **versioned adapter namespace `/api/m1/pos/*`** (§2.4) whose handlers translate `globalId` references to local ids and call the **same** internals as the existing handlers — `createSalesInvoice` for sales (as `POST /api/sales` does), `processSalesReturn` for returns, `TreasuryDao.openShift` / `closeShiftWithAudit` for shifts. No second posting path. Rationale: a stable, documented contract for a non-desktop client, independent of the desktop client's internal payload shape, testable by contract tests.

**Local data (SQLCipher, `picpos_device`):** products (+ units, barcodes, sale/wholesale price, tax flags, category, image URL optional), price lists, customers of the branch (balance, credit limit, price level, `system_role`), payment methods allowed, safes of the branch, company profile (identity lines, decimals, `prices_include_tax`, default tax), the logged-in users' cached verifiers, local invoices/returns of this terminal (for reprint and offline returns), held orders, outbox, print queue. Bootstrap + delta pull scoped to the terminal's branch.

**Offline queue.** Each sale/return gets a client UUIDv7 `globalId` and a terminal number **before** the confirm screen; stored in the outbox with `occurredAt`, `shiftGlobalId`, `userGlobalId`, `offline: true|false`. Push in creation order, one doc per request with `x-idempotency-key = globalId`; per-doc results `accepted | duplicate | rejected{code}` (same semantics as the rep app, ARCHITECTURE-I §5). Rejected docs stay in «تحتاج مراجعة» (needs attention); since goods have already left the shop, resolution is a manager action on the desktop (post with override, or record a correcting document) — never a silent drop. Backoff 5 s → 5 min cap on LAN; immediate retry on `/ws` reconnect.

**Numbering.** POS pairing requires an explicit positive `branchId`; the desktop never selects a default branch. At pairing the desktop assigns the next never-before-assigned per-branch **terminal code** (`T01`, `T02`…, stored with the device on `lan_paired_devices` and retained in the allocation registry even after revocation); M-B numbers `{branchCode}-{terminalCode}-{seq6}` (e.g. `CAI-T03-000042`), returns `{branchCode}-{terminalCode}-R{seq6}`. Because the number already starts with `<branchCode>-`, the LAN server keeps it unchanged (F4); uniqueness is by construction (terminal codes are unique), gaps are visible in `NumberingGapReport` (`database.dart:330`). Pairing is **refused** for a missing/inactive branch or a branch without a code (the `CLT<ip>` fallback is collision-prone, as the code itself warns). The desktop still re-signs with `resignSalesInvoice` / its integrity service.

**Shift and drawer.** Open shift **requires the LAN** (`/api/m1/pos/shifts/open` with the opening float count; the server is the authority on "one open shift per drawer"); sales during the shift may be offline; close requires the LAN **and an empty outbox** (the app blocks close until every document is accepted or resolved), then sends the denomination count; the desktop computes expected cash (`getShiftClosingAggregates`) and posts the variance (`closeShiftWithAudit`). Blind close follows the user's `pos_closing_view_details`. The cash drawer opens through the receipt printer (`ESC p 0 25 250` = `1B 70 00 19 FA`), automatically after a cash payment when the desktop's drawer policy is on, manually with `pos_open_drawer`.

**Business rules on the tablet** (all re-checked by the desktop on posting): totals/tax/pricing via `picpos_rules`; discount up to `maxDiscountPercent` with `pos_discount`, above it a manager override (another user's PIN verified **online** via `/api/m1/pos/override`; offline → blocked with a clear message); credit sales check the last-synced balance + this terminal's pending credit (`exceedsCreditLimit`), over-limit needs `override_credit_limit` (critical code, online only); price edit `pos_price_edit`; returns per existing rules (quantity ≤ sold − returned, pro-rata value, `pos_return`; offline only against invoices of this terminal still in local storage, otherwise online lookup); cash customer one-time name/phone → `adhocCustomerName/adhocCustomerPhone` (`sales_invoices.adhoc_*`) on the cash-customer system party; customer selection `pos_customer_select` code per `ensureSelectCustomerPermission` (exact code pinned in M-5).

**Stock offline:** the tablet does not reserve stock; it warns from the last-synced quantity; the desktop's negative-stock policy decides at posting (a rejection lands in «تحتاج مراجعة»).

**Printing.** `picpos_device` printing (from `mobile/lib/printing/`): Arabic rendered as raster (Noto Naskh) → `GS v 0`, 58/80 mm; transports: Bluetooth Classic SPP (existing `print_bluetooth_thermal`) **and** network TCP 9100 (new, `dart:io` `Socket`); receipt content = company identity lines + QR rule from `picpos_rules` (same decisions as I-4); printing never blocks the sale (persisted retry queue). USB printers: out of scope for release 1.

**Out of scope (owner decision):** scales (serial/Aclas SDK), customer-facing display, kitchen printers, card-terminal integration (card payment = manual reference), held-order sync across devices (held orders are local to the tablet in release 1). Parsing price-embedded scale **labels** (EAN-13 prefix 2x) is a small optional port of `ScaleBarcodeHandler` into `picpos_rules` — off by default (Q8).

---

## 2. API contracts

Conventions: JSON, UTF-8; amounts as **decimal strings**; timestamps ISO-8601 UTC in payloads, `since`/`serverTime` epoch ms (as the cloud already does); every write takes `X-Idempotency-Key`; errors `{error:{code,message}}` with HTTP 400/401/403/404/409/422/429/503.

### 2.1 Cloud — new migration 7 `m_admin_relay`

Tables (all with `company_id`): `admin_users(global_id, username, display_name, locale, mobile_enabled, password_hash, permissions jsonb, branch_scope jsonb, require_2fa, totp_secret_enc, failed_logins, locked_until, version)`, `admin_devices(device_id, user_global_id, token_hash, previous_token_hash, token_rotated_at, fcm_token, platform, app_version, revoked_at, last_seen_at)` (or `devices.kind='admin'` — decided in M-1 by test convenience), `snapshots(kind, scope, as_of, payload jsonb, signature, received_at, PK(company_id,kind,scope,as_of_day))`, `relay_queue(id uuid, kind query|command, type, params jsonb, user_global_id, device_id, status queued|delivered|done|rejected|expired, expected_version, created_at, delivered_at, expires_at, result jsonb, result_signature, reason)`, `notification_events`, `notification_deliveries(event_id, user_global_id, channel, status, sent_at)`, `notification_prefs`; `desktop_links.signing_public_key`, `desktop_links.last_seen_at`. Pairing codes gain `kind` and `user_global_id`.

### 2.2 Cloud — `/manage/*` (M-A)

| Method + path | Auth | Request | Response |
|---|---|---|---|
| `POST /manage/pair` | none (rate-limited) | `{code, deviceId, deviceName, appVersion}` | `{deviceToken, user:{globalId,username,displayName}, company:{name,decimals,currency}, desktopSigningKey}` |
| `POST /manage/login` | device | `{username, password, totp?}` | `{sessionToken, expiresAt, user:{…, permissions[], branchScope[], require2fa}}` or 401 `totp_required` |
| `POST /manage/step-up` | session | `{password}` or `{totp}` | `{stepUpToken, expiresAt(+5 min)}` |
| `POST /manage/token/rotate` | device | — | `{deviceToken}` (grace as I-2) |
| `PUT /manage/push-token` | session | `{fcmToken, locale}` | 204 |
| `POST /manage/2fa/enroll` · `/confirm` | session + step-up | — · `{totp}` | `{otpauthUri}` · 204 |
| `GET /manage/snapshots?kinds=kpi.today,cash.position&branch=` | session | — | `{desktop:{lastSeenAt}, items:[{kind, scope, asOf, payload, signature}]}` |
| `POST /manage/queries` | session | `{queryId, type, params, fresh?}` | 200 `{status:'done', asOf, payload, signature, cached:true}` or 202 `{status:'queued'}` |
| `GET /manage/queries/{id}?waitMs=20000` | session | — | `{status, asOf?, payload?, signature?, reason?}` (long-poll) |
| `POST /manage/commands` | session (+`X-Step-Up` for financial) | `{commandId, type, params, expectedVersion?}` | 202 `{status:'queued', expiresAt}`; same `commandId` again → current status |
| `GET /manage/commands/{id}?waitMs=` | session | — | `{status, result?, reason?}` |
| `GET /manage/notifications?since=&limit=` · `POST /manage/notifications/read` | session | — · `{eventIds[]}` | `{items[], serverTime}` · 204 |
| `GET/PUT /manage/notification-prefs` | session | `{types:{<type>:{channel:'push'|'inbox'|'off'}}, quietHours?}` | same |

Example — query and result:

```json
POST /manage/queries
{"queryId":"0190f3c2-…","type":"report.trial_balance",
 "params":{"from":"2026-01-01","to":"2026-01-31","branchIds":[2],"costCenterId":null,"level":"leaf"}}

GET /manage/queries/0190f3c2-…?waitMs=20000
{"status":"done","asOf":"2026-02-01T08:12:03Z",
 "payload":{"currency":"JOD","decimals":3,"rows":[{"accountCode":"1101","name":"الصندوق","nameEn":null,
   "openingDebit":"0.000","openingCredit":"0.000","debit":"1250.500","credit":"300.000",
   "closingDebit":"950.500","closingCredit":"0.000"}],"totals":{"debit":"…","credit":"…"},"balanced":true},
 "signature":"ed25519:base64…"}
```

Example — command:

```json
POST /manage/commands   (X-Step-Up: …)
{"commandId":"0190f3c9-…","type":"voucher.receipt.create",
 "params":{"partyGlobalId":"…","amount":"150.000","safeGlobalId":"…","paymentMethod":"cash",
           "bookGlobalId":"…","bookNumber":"004512","date":"2026-02-01","notes":"دفعة على الحساب",
           "costCenterId":null,"branchId":2}}
→ 202 {"status":"queued","expiresAt":"2026-02-02T08:13:00Z"}
GET /manage/commands/0190f3c9-… → {"status":"done","result":{"voucherNumber":"RV-2291","journalEntryId":88412}}
```

**Query types (release 1):** `kpi.refresh{branchId?}`, `report.trial_balance{from,to,branchIds?,costCenterId?,level}`, `report.account_ledger{accountId,from,to,costCenterId?,branchId?,page,pageSize≤500}`, `report.income_statement{from,to,branchIds?,costCenterId?,compareTo?}`, `report.balance_sheet{asOf,branchIds?}`, `report.party_statement{partyGlobalId,from,to,branchId?}`, `report.aging{asOf,kind:'ar'|'ap'}`, `lookup.accounts{q}`, `lookup.parties{q,kind}`, `lookup.safes`, `lookup.cost_centers`, `lookup.voucher_books{type}`, `lookup.cheques{status,dueBefore?}`, `approvals.detail{ref}`.

**Command types (release 1) → desktop execution path:**

| Command | Desktop path (existing) | Permission re-checked | Class |
|---|---|---|---|
| `approve.sales_return_draft{draftId}` / `cancel.…` | same steps as `approveReturn()` in `sales_returns_picpos_drafts.dart:164` (post the return, `markPosted`) — extracted into a UI-free service first | `sales_return_approve` | approval |
| `approve.purchase_return_draft{draftId}` / `cancel.…` | `purchase_returns_picpos_drafts.dart:134` equivalent | `purchases_return_approve` | approval |
| `leave.approve|reject{requestId,note}` | `approveLeaveRequest` / `rejectLeaveRequest` (`hr_leave_dao.dart:354/387`) | `hr_leave_approve` or direct manager | approval |
| `payroll.approve{runId}` · `payroll.post{runId}` | `approvePayrollRun` · `postPayrollRun` (`hr_payroll_posting_dao.dart:12/82`) | `hr_payroll_approve` · `hr_payroll_post` | approval · financial |
| `override.approve|reject{requestId}` | resolves a remote override request → `ManagerApprovalCache.grant` for that request's scope only | `override_credit_limit` (credit) / `pos_discount` + cap (discount) / `pos_price_edit` (price) | financial |
| `field_customer.approve|reject{customerGlobalId}` | activate/deactivate the rep-created customer posted by `cloud_customer_poster.dart` | `customers_add` | approval |
| `voucher.receipt.create` · `voucher.payment.create` | `createReceiptVoucher` · `createPaymentVoucher` (`treasury_repository_impl.dart:146/274`) + `assignVoucherBookLeaf` | `treasury_receipts_create` · `treasury_payments_create` | financial |
| `journal.create{date,lines[{accountId,debit,credit,costCenterId?,memo}],memo}` | `createJournalEntry` (`accounting_dao_writes.dart:45`); maker-checker honored (`approve_journal`) | `accounting_journal` | financial |
| `cheque.change_status{paperId,newStatus,counterAccountId?,endorsedToPartyGlobalId?,notes}` | `changePaperStatus` (`commercial_papers_dao.dart:169`) | `commercial_papers_manage` | financial |
| `user.change_mobile_password{newHash}` | desktop users store | self | — |

Rejection codes: `permission_denied`, `stale` (expectedVersion ≠ current), `expired`, `period_closed`, `shift_required` (cash safe needs an open shift — mobile vouchers should target bank/central safes; the app filters safes accordingly), `book_leaf_invalid`, `validation_failed{field}`, `not_found`, `executor_error`. Remote override requests are created by the desktop (or M-B via LAN) as `approval.pending` events with a 3-minute expiry; the waiting POS dialog shows «بانتظار موافقة المدير من الجوال…» with cancel.

Note on ids: drafts, leave requests, payroll runs, papers and accounts are referenced by **desktop-local ids** inside `params`/`ref`; the cloud treats them as opaque, which is safe because only the same desktop executes them (one company = one desktop link). Parties/safes/books use `globalId` as the existing master push already does.

### 2.3 Cloud — `/desktop/*` additions

| Method + path | Request | Response |
|---|---|---|
| `POST /desktop/link/signing-key` | `{publicKey}` (once, or on rotation) | 204 |
| `POST /desktop/users` | `{users:[{globalId, username, displayName, locale, mobileEnabled, mobilePasswordHash?, permissions[], branchScope[], require2fa, version}]}` (desktop wins, `version` monotonic) | `{applied, skipped}` |
| `POST /desktop/snapshots` | `{items:[{kind, scope, asOf, payload, signature}]}` | `{stored}` |
| `GET /desktop/relay/next?waitMs=25000&max=20` | — (long-poll; returns at once when rows exist; marks them `delivered`) | `{items:[{id, kind, type, params, user:{globalId}, deviceId, createdAt, expiresAt, expectedVersion}]}` |
| `POST /desktop/relay/results` | `{results:[{id, status:'done'|'rejected', payload?, signature?, reason?}]}` | per item `recorded|unknown|already_final` |
| `POST /desktop/events` | `{events:[{eventId, type, severity, branchId, branchName, occurredAt, params}]}` (idempotent by `eventId`) | `{accepted}` |
| `POST /desktop/pairing-codes` (extended) | `{kind:'rep'|'admin', employeeGlobalId?|userGlobalId?, pin?}` | `{code, expiresAt}` |

Relay implementation: a single API instance waits on an in-process notifier (+ Postgres `LISTEN/NOTIFY` once replicas exist, like the rate-limiter note in `rate_limiter.dart`); delivered-but-unacked items return to `queued` after 2 min (desktop crash), executed-once is guaranteed by the desktop's `remote_commands` table, not by the queue. Desktop side: new `CloudRelayWorker` beside `CloudSyncScheduler`, same link credential, same "never on a LAN client" rule, runs only while the link is configured.

### 2.4 Desktop LAN — `/api/m1/*` additions

Plain HTTP stays possible for existing desktop clients; **M-A and M-B require TLS** (self-signed cert, fingerprint pinned from the pairing QR, `TlsTrust`). M-A refuses LAN without TLS and falls back to the cloud.

| Method + path | Auth | Purpose |
|---|---|---|
| `GET /api/m1/info` | none | `{serverId, companyName, appVersion, apiLevel:1, tls:true, branches:[{id,code,name}]}` — reachability probe |
| `POST /api/pair` (extended body) | none | optional `{deviceKind:'admin'|'pos', branchId?}`; `branchId` is required and positive for `deviceKind:'pos'` (optional for other kinds); POS success adds `{branchId, branchCode, terminalCode}` |
| `POST /api/m1/auth/session` | device | `{username, password}` (M-A mobile password) or `{username, pin}` (M-B) → `{sessionToken, user:{globalId, displayName, locale, permissions[], maxDiscountPercent, discountLimitIsPercent, branchId}}` |
| `POST /api/m1/admin/query` · `POST /api/m1/admin/command` | device + session | same bodies/results as the cloud `/manage/queries` · `/manage/commands`, executed synchronously by `MobileGateway` (command returns the final status) |
| `GET /api/m1/admin/snapshots?kinds=` | device + session | live-built snapshots (signed) |
| `GET /api/m1/pos/bootstrap` | device + session | company profile, branch, safes of the branch, payment methods, settings (drawer policy, print policy, negative-stock, rounding), `serverTime` |
| `GET /api/m1/pos/pull?since=&cursor=&entity=` | device + session | keyset `{rows, hasMore, cursor, serverTime}` for `products, barcodes, units, price_lists, customers, users_lite` scoped to the branch; tombstones via `deletedAt` |
| `GET /api/m1/pos/shifts/current` · `POST /api/m1/pos/shifts/open` · `POST /api/m1/pos/shifts/close` | device + session | `{shiftGlobalId, openedAt, openingFloat}` · `{globalId, openingFloat, counts?}` (`pos_shift_open`) · `{shiftGlobalId, counts:{"10":"3",…}, cardTotal?, notes}` (`pos_shift_close`) → `{expected, counted, variance, journalEntryId}` |
| `POST /api/m1/pos/sales` | device + session | one sale (below); `X-Idempotency-Key = globalId`; `sales_create`/`pos_save` + payment-method code; → `{status:'accepted'|'duplicate', serverId, invoiceNumber}` or 422 `{code}` |
| `POST /api/m1/pos/returns` | device + session | `{globalId, number, originalInvoiceGlobalId|originalNumber, lines[{productGlobalId, qty}], refund:{method, safeGlobalId?}, shiftGlobalId}` (`pos_return`) |
| `GET /api/m1/pos/invoices/lookup?number=` | device + session | returnable lines (sold − returned) for online returns |
| `POST /api/m1/pos/override` | device + session | `{action:'discount'|'credit'|'price', managerUsername, managerPin, context}` → `{approvalToken, expiresAt(60 s)}` (wraps the `ManagerApprovalCache` semantics) |
| `GET /api/m1/pos/customers/{globalId}/balance` | device + session | live balance + credit limit |

Sale payload:

```json
{"globalId":"0190f4…","number":"CAI-T03-000042","occurredAt":"2026-02-01T10:21:09Z","offline":true,
 "shiftGlobalId":"…","userGlobalId":"…","terminalCode":"T03",
 "customer":{"globalId":"…","adhocName":"أبو خالد","adhocPhone":"+9627…"},
 "pricesIncludeTax":true,
 "lines":[{"productGlobalId":"…","unitGlobalId":"…","qty":"2","unitPrice":"1.250","discount":"0.000","taxRate":"0.16"}],
 "headerDiscount":"0.000","overrideToken":null,
 "totals":{"subtotal":"2.155","discount":"0.000","tax":"0.345","total":"2.500"},
 "payments":[{"method":"cash","amount":"5.000","change":"2.500"}],
 "integrity":{"v":"v2","clientHash":"…"}}
```

The handler recomputes totals with the desktop's own rules (`totals_mismatch` if > 0.01, as I-3), resolves `globalId`s, and calls `createSalesInvoice` within the shift; an `offline:true` sale keeps `occurredAt` as the invoice date when the period is open.

---

## 3. Screens and permissions

### 3.1 M-A «PicPos إدارة» — screen map

Navigation: phone (< 600 dp) bottom bar with 5 destinations; tablet (≥ 600 dp) navigation rail; ≥ 840 dp list/detail two-pane (approvals, reports, notifications). Every screen: `PicPosPageHeader` with title and `AsOfBadge`; connection chip «محلي/سحابي/غير متصل».

| Area | Screens |
|---|---|
| Onboarding | Welcome → scan pairing QR (or manual code + URL) → login (password, TOTP) → set app PIN / biometric → language & theme |
| 1. الرئيسية (Home) | KPI dashboard: branch filter, today / month toggle; cards: net sales, invoices, gross profit, returns, discounts; cash & banks list; AR / AP totals + aging bar; branch ranking; rep ranking; pending-approvals strip. Tablet: 4-column KPI grid + side panels |
| 2. الموافقات (Approvals) | Inbox tabs: returns (sales/purchase), leave, payroll, overrides (live, with countdown), field customers; detail sheet with lines/amounts, approve / reject with note; result toast + history |
| 3. التقارير (Reports) | Report list → parameters sheet (period, branch, cost center, account/party picker) → report viewer (trial balance, account ledger with paging, income statement, balance sheet, party statement, AR/AP aging); export PDF (Noto Naskh, A4, company header) / Excel (`.xlsx`) → Android share sheet; recent reports (cached) |
| 4. المحاسبة (Accounting) | Receipt voucher, payment voucher (party, amount, safe/bank, book + leaf suggestion, date, notes); journal entry (balanced-lines editor, totals bar, cost center); cheques list by status with actions (deposit, collect, bounce, endorse, return) per allowed transitions; command status list |
| 5. المزيد (More) | Notifications inbox; notification preferences; devices & security (2FA, change mobile password, app lock); connection (LAN/cloud status, desktop last seen); language, theme; about / privacy policy |

### 3.2 M-B «PicPos كاشير» — screen map

Primary: tablet landscape ≥ 840 dp — items grid (categories rail + grid + search/barcode field) on the start side, cart + totals + pay on the end side (mirrors in LTR). Phone / portrait: cart-first with a full-screen item picker sheet.

| Area | Screens |
|---|---|
| Setup | Pair with desktop (QR from desktop «ربط جهاز كاشير») → branch/terminal confirmation → printer setup (Bluetooth list / IP:port, 58/80, test page, drawer test) |
| Login | User tiles of the branch → PIN pad; offline badge when the session is offline-verified |
| Shift | Open shift (opening float, denomination keypad) · shift status · close shift (count, blind mode, variance result, print Z report) |
| Sale | Items grid, search, barcode (camera button + HID wedge), quantity / price / line discount (per permission), customer picker (incl. cash customer one-time name/phone), header discount, hold / recall held orders, pay sheet (cash with change, card ref, credit, split), print / reprint, drawer |
| Returns | Return by invoice number/scan → lines → refund method; return without invoice is **not** offered unless the desktop rule allows it |
| Sync | Outbox list (pending / accepted / needs attention with reason), last pull, connection to desktop, print queue |
| Settings | Language, theme, printer, about |

### 3.3 Permission matrix (existing codes from `lib/core/permissions/permission_codes.dart`)

Only codes the desktop actually enforces are used: codes listed in `PermissionCodes.nonToggleable` (`permission_codes.dart:1020-1093`) are mapped to the code that really gates the screen (`reports_customers`/`reports_inventory`/`reports_profit` → `reports_view`, `reports_shifts` → `reports_sales`, `dashboard_sales_total` → `dashboard_sales_today`, `accounting_view` → `settings_view`). A structural test in M-0 fails if the mobile matrix references a non-toggleable code.

New codes (added on desktop in M-0, granted by default to roles that hold the codes in brackets so no access widens): `mobile_admin_access` [`dashboard_access`], `mobile_pos_access` [`pos_access`], `reports_financial_statements` [`settings_view` — today the accounting screens are gated by it, `permission_codes.dart:1040`].

| M-A feature | Required code(s) |
|---|---|
| Open app | `mobile_admin_access` |
| KPI sales / invoices (today and month — one card with a period filter, as on desktop) | `dashboard_sales_today` |
| Gross profit KPI | `dashboard_profit` |
| Cash & banks | `treasury_view` |
| AR/AP & aging | `reports_view` |
| Branch / rep performance | `reports_sales` (+ branch scope) |
| Trial balance, income statement, balance sheet, account ledger | `reports_financial_statements` |
| Party statement | `reports_view` |
| Export / share | `reports_export` |
| Approve sales / purchase return drafts | `sales_return_approve` / `purchases_return_approve` |
| Leave | `hr_leave_approve` (or direct manager, as desktop) |
| Payroll approve / post | `hr_payroll_approve` / `hr_payroll_post` |
| Credit-limit override | `override_credit_limit` (critical: no admin bypass) |
| Discount / price override | `pos_discount` + approver's `maxDiscountPercent` ≥ requested / `pos_price_edit` |
| Field customers | `customers_add` |
| Receipt / payment vouchers | `treasury_receipts_create` / `treasury_payments_create` |
| Journal entries | `accounting_journal` (approval of others' entries: `approve_journal`) |
| Cheque status actions | `commercial_papers_manage` |
| Notifications: large invoice, discount | `dashboard_alerts` + `reports_sales` |
| Notifications: shift variance | `reports_sales` |
| Notifications: custody, low stock | `treasury_view`, `inventory_view` |
| Notifications: pending approvals | the approve code of that item |

| M-B feature | Required code(s) |
|---|---|
| Open app / sell | `mobile_pos_access`, `pos_access`, `pos_save` (server: `sales_create`) |
| Payment methods | `pos_payment_cash`, `pos_payment_card`, `pos_payment_credit`, `pos_payment_multiple` |
| Discounts | `pos_discount` + `Users.maxDiscountPercent` |
| Price edit | `pos_price_edit` |
| Hold / recall / delete held | `pos_hold_order`, `pos_restore_held`, `pos_delete_held` |
| Returns | `pos_return` |
| Open / close shift | `pos_shift_open`, `pos_shift_close` |
| Drawer | `pos_open_drawer` |
| Add customer | `pos_customer_add` |
| Credit over limit | `override_credit_limit` (manager override) |

`cond:` (conditional) grants are honoured: the app treats the action as "needs manager approval every time" (M-A: step-up; M-B: override flow), as the desktop does.

---

## 4. Roadmap, tests, release engineering

### 4.1 Phases

| Phase | Scope | Acceptance criteria |
|---|---|---|
| **M-0 Foundations** | `packages/picpos_ui`, `picpos_api_client`, `picpos_device` (extracted copies; picpos_van untouched); `mobile_admin/` + `mobile_pos/` skeletons (themes, AR/EN, light/dark, adaptive scaffold); Android projects with `applicationId`s, adaptive icons, release signing from `key.properties`, `usesCleartextTraffic=false` + network-security-config allowing only pinned LAN TLS; desktop: new permission codes, «تفعيل تطبيق الإدارة» + mobile password, Ed25519 link key, TLS on by default for M-* pairing; CI job building both APKs | `dart test` packages green; `flutter test` both apps green incl. golden screenshots (AR/EN × light/dark × phone 411×891 / tablet 1280×800); `flutter build apk --release` signed with a test keystore; structural test: no `Colors.white`/teal literals in the new apps (port of `dark_mode_guard_test`) |
| **M-1 M-A read-only via cloud** | cloud migration 7, `/manage/pair|login|step-up|snapshots`, `/desktop/users|snapshots|signing-key`, desktop snapshot builder, M-A onboarding + dashboard + approvals inbox (view only) | live test: desktop harness pushes users + snapshots to docker cloud → M-A client pairs, logs in, verifies signature, sees KPIs equal to desktop DAO results for a seeded ledger; revoked user → 401 + wipe |
| **M-2 Reports (relay + LAN)** | relay queue + long-poll, `CloudRelayWorker`, `MobileGateway` queries, `/api/m1/info|auth/session|admin/query`, transport selector, report viewers, PDF/Excel export + share | each report's payload equals the desktop DAO output for the same params (golden JSON per report); the same query via LAN and via cloud returns byte-identical canonical payloads; desktop offline → cached result with banner; p95 relay < 10 s on the docker stack |
| **M-3 Approvals & operations** | commands (§2.2 table), `remote_commands`, step-up, UI-free extraction of the draft-approval steps, remote override request from desktop POS | for every command type: executed once under retry/duplicate across LAN+cloud; GL after a mobile receipt voucher == GL after the same voucher entered on desktop (I-3-style golden comparison); `stale`, `expired`, `permission_denied`, `period_closed` paths tested |
| **M-4 Notifications** | `mobile_events` producers, `/desktop/events`, fan-out, prefs, `MockPushProvider` + `FcmPushProvider`, M-A inbox + FCM handling + POST_NOTIFICATIONS consent | each event type fires once per trigger in desktop integration tests; recipients follow permission + branch scope; mock provider records the push; with the owner's Firebase project, a real device receives a push < 30 s |
| **M-A 1.0 review build** | signed APK for owner review | owner checklist (§4.4) passed on a real phone and tablet |
| **M-5 M-B online POS** | pairing with terminal code, `/api/m1/pos/bootstrap|pull|shifts|sales`, sale UI, payments, cash customer, printing BT + network, drawer kick | sale from M-B posts identical GL/stock/integrity as the same sale on a desktop LAN client (golden comparison in the desktop harness); 58/80 receipts rendered at 384/576 dots; drawer command bytes asserted |
| **M-6 M-B offline & returns** | outbox, offline login, offline sales, held orders, returns, manager override, needs-attention flow, close-shift drain | kill-app-mid-push and lost-response tests: each doc accepted exactly once; 200 offline sales then reconnect → all accepted in order, shift closes with correct variance; return-quantity and credit rules rejected identically to desktop |
| **M-B 1.0 review build** | signed APK for owner review | owner checklist on a real tablet with BT and LAN printers + drawer |
| **M-7 Play readiness** | AAB, store listings AR/EN, screenshots, privacy policy page, Data safety forms, target-API check, Play App Signing enrolment (owner) | `flutter build appbundle --release` for both; pre-launch report clean; owner submits |

M-1..M-4 (M-A) and M-5..M-6 (M-B) can run as two parallel tracks after M-0; the owner's "everything in release 1" for M-A means no M-A store release before M-4.

### 4.2 Test strategy

- **Unit (pure Dart):** `picpos_api_client` (canonical JSON, Ed25519 verify, header builder, error mapping, transport selection with fake clocks), `picpos_rules` additions (scale label parse if enabled), relay/command state machines.
- **Widget + golden:** every screen in AR (RTL) and EN (LTR), light and dark, phone and tablet sizes, no overflow; goldens generated on one pinned platform in CI (Linux `flutter test --update-goldens` only on deliberate change) with bundled Cairo/Noto Naskh so text renders; contrast checks ≥ 3.0 (≥ 4.5 for POS card values) as in `DESIGN.md`; l10n coverage test (every key has `ar` and `en`).
- **Cloud integration (docker):** new `server/test/m_*_test.dart` on the existing Postgres harness (`server/test/support/harness.dart`): pairing kinds, login/lockout/TOTP, permission-filtered snapshots, relay long-poll wake-up, re-queue after 2 min, expiry, idempotent results/events, fan-out + mock push. Docker smoke script extended.
- **LAN integration (desktop harness):** desktop `flutter test` integration suites (pattern of `test/integration/cloud_sync_i3_test.dart`) that start the real `ApiHandler` on an in-memory/temporary SQLCipher `AppDatabase` on a random port with a test TLS cert, then drive it with `picpos_api_client` (pure Dart, so it runs inside the desktop test process): M-B bootstrap/pull/shift/sale/return/override contracts and the GL golden comparisons; M-A `/api/m1/admin/*` query/command parity.
- **End-to-end relay:** desktop harness + docker cloud + `picpos_api_client` as M-A: query and command through the cloud (enabled with `CLOUD_URL`, skipped otherwise, like `mobile/test/live_cloud_test.dart`).
- **Device checks (manual, recorded):** printing on 58/80 BT and network printers + drawer, camera scan, offline day on the tablet, FCM on a real phone, Doze behaviour.

### 4.3 Release engineering

| Item | M-A | M-B |
|---|---|---|
| Folder / Dart package | `mobile_admin/` · `picpos_admin` | `mobile_pos/` · `picpos_pos` |
| `applicationId` (permanent once on Play) | `com.picpos.admin` | `com.picpos.pos` |
| Display name | «PicPos إدارة» / "PicPos Admin" | «PicPos كاشير» / "PicPos Cashier" |
| Form factors | phone + tablet, portrait (tablet also landscape) | tablet landscape primary, phone allowed |
| minSdk / target | 24 / Flutter default ≥ the Play target-API requirement at submission (API 35 for 2025 submissions — recheck) | same |
| Android permissions | INTERNET, ACCESS_NETWORK_STATE, POST_NOTIFICATIONS, CAMERA (QR pairing), USE_BIOMETRIC | INTERNET, ACCESS_NETWORK_STATE, ACCESS_WIFI_STATE, CAMERA, BLUETOOTH_CONNECT/SCAN (`neverForLocation`), legacy BLUETOOTH/BLUETOOTH_ADMIN ≤ API 30 |

- **Versioning:** `pubspec.yaml` `version: x.y.z+N`; `versionName` semver per app, `versionCode = N` strictly increasing from CI build numbers, independent per app; the LAN/cloud `apiLevel` is checked at login (`/api/m1/info.apiLevel`, cloud `minAppVersion`) with a clear "update the desktop/app" message.
- **Signing:** one **upload keystore per app** (`picpos-admin-upload.jks`, `picpos-pos-upload.jks`, RSA 4096, validity 30 y), referenced by `android/key.properties` (`storeFile, storePassword, keyAlias, keyPassword`) which is **git-ignored** (`flutter create` adds `key.properties`, `*.jks`, `*.keystore` to `android/.gitignore` as in `mobile/android/.gitignore`; the root `.gitignore` has no such rule today, so a CI step fails the build if any `*.jks|*.keystore|key.properties|google-services.json` is tracked). CI reads the keystore from a base64 secret. Never commit keystores, passwords or the Firebase service account.
- **Review APKs vs Play:** with **Play App Signing**, Play re-signs with its app-signing key, so an APK side-loaded from our upload key has a different signature than the Play build → testers must uninstall once when moving to the Play version (data is re-synced; local data is a cache except M-B's unsent outbox → drain before uninstall). Alternative: export the app-signing key to Play (keeps the signature) — Q3.
- **Builds:** review: `flutter build apk --release --split-per-abi` (arm64-v8a + armeabi-v7a); Play: `flutter build appbundle --release`; R8 shrink on with keep rules for plugins; `--obfuscate --split-debug-info` and archive the symbols per version.
- **Icons:** adaptive icons (foreground = `assets/brand/picpos/logo.png` mark on a safe 66 dp zone, background `#FFFFFF`; Android 13 monochrome layer); M-A badge = small chart glyph, M-B badge = receipt glyph, both brand blue `#0250D3`; generated with `flutter_launcher_icons`; 512×512 Play icon + 1024×500 feature graphic.
- **Privacy policy (one page, AR/EN, hosted at an owner URL):** data processed on behalf of the business (customers' names/phones/balances, invoices, ledger figures, employee names); purpose: operating the business's own system; storage: the business's desktop and its cloud server; on-device encrypted cache (SQLCipher) wiped on unpair; push tokens used only to deliver notifications via Google FCM; no ads, no analytics SDK, no sale of data; camera used only for scanning QR/barcodes (not stored); Bluetooth only for printers; retention per §ADR-M2; deletion by the business administrator (unpair / disable user) or by request to the support email.
- **Data safety form (draft):** *Collected*: Personal info — name, phone number (of the business's customers, M-A reports / M-B cash customer), user IDs (username); Financial info — purchase history / other financial info (business transactions); Device or other IDs (FCM token, device id — M-A). *Shared*: none (FCM as a service provider is not "sharing"). *Encrypted in transit*: yes. *Deletion request*: yes (via business administrator). *Not collected*: location, contacts, photos, audio, health, web history. Camera and Bluetooth declared as permissions without data collection.

### 4.4 Owner review checklist (for each review APK)
Install, pair, log in (AR and EN, light and dark), main flows per §3, offline behaviour (M-B), printing + drawer (M-B), notifications (M-A), uninstall/re-pair. Signed-off list kept in `docs/mobile/` with the APK SHA-256.

### 4.5 What the owner must provide

1. **Firebase project** (owner-owned Google account): Android app registrations `com.picpos.admin` (and `com.picpos.pos` only if POS notifications are wanted later), `google-services.json`, an FCM service-account key for the cloud server (secret store, never git).
2. **Keystore custody decision:** who generates and holds the upload keystores and passwords (recommended: the owner holds the master copy in a password manager + offline backup; the build machine/CI gets a copy as a secret).
3. **Google Play developer account** (later): organisation account (D-U-N-S required) or personal; the Play App Signing choice; store listing texts approval; support email; privacy-policy URL hosting.
4. **Confirmation of `applicationId`s** (`com.picpos.admin`, `com.picpos.pos`) — permanent on Play; ideally the owner controls the `picpos.com` domain or chooses another reverse-domain.
5. **Thresholds** for notifications (§ADR-M4 defaults) and the list of users to enable for M-A.
6. **Test hardware:** one Android phone and one tablet (Android ≥ 7), a Bluetooth and a network ESC/POS printer with a cash drawer, the shop Wi-Fi with the desktop server.
7. **Production cloud** (I-6 checklist in `ARCHITECTURE-I.md` §12) before M-A is used outside the test stack.

---

## 5. Risks and open questions (defaults proposed)

| # | Risk / question | Default |
|---|---|---|
| R1 | Desktop offline → M-A shows only snapshots; commands wait. | Show `asOf` + "desktop offline since"; commands queue until expiry (24 h ops / 7 d approvals). |
| R2 | Desktop changes touch shared code of both brands. | All new desktop features (`MobileGateway`, relay worker, `/api/m1/*`, events, mobile users) are gated by `Brand.isPicPos`; UralCash gets no route and no setting. |
| R3 | Draft-approval logic lives in screen code (`sales_returns_picpos_drafts.dart:164`); a mobile path must not fork it. | Extract a UI-free service used by both the desktop screen and `MobileGateway` (M-3), covered by a test before the extraction. |
| R4 | LAN API security gaps seen while reading: plain HTTP by default, pairing attempt IP taken from `x-forwarded-for`/`host`, SQL interpolation in `lan_pairing_service.dart` (lines ~237/287/327). | M-* require TLS + pinning; the two LAN issues are reported for a separate fix, not changed here. |
| R5 | Offline sales rejected later (stock/credit) after goods left. | Tablet blocks credit-over-limit and over-cap discounts offline; stock rejections go to «تحتاج مراجعة» for a manager decision. |
| R6 | Gross-profit and rep-performance sources not yet pinned (dashboard shows net profit only). | Pin in M-1 with a parity test against `getIncomeStatement` and the distribution DAOs. |
| Q1 | Mobile password separate from desktop password? | Yes (never replicate desktop hashes). |
| Q2 | 2FA mandatory for anyone? | Optional; recommended on for the owner and anyone with `override_credit_limit` / `hr_payroll_post`. |
| Q3 | Play App Signing with a Google-generated key (testers reinstall once) or upload our own app-signing key? | Google-generated key; review testers reinstall once. |
| Q4 | Can M-B work without the desktop for a whole day? | Yes for sales/returns of its own invoices after the shift was opened online; shift open/close needs the desktop. |
| Q5 | Amounts in push notification text? | No (generic title, details in-app). |
| Q6 | End-to-end encryption so the cloud cannot read reports? | Not in release 1 (TLS + signatures + retention); revisit with production hosting. |
| Q7 | Notifications for M-B (POS)? | None in release 1. |
| Q8 | Scale-label barcodes (price-embedded EAN-13) on M-B? | Off; scale hardware out of scope as decided. |
| Q9 | Held orders shared between tablet and desktop? | Local to the tablet in release 1. |
