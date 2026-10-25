# Fleet E2E results (2026-10-25)

Suite: `flutter test test/e2e_fleet --concurrency=1` (also `tool/run_e2e.ps1 -Only fleet`).
Topology: MAIN (real router + rate limiter + auth middleware over real HTTP on loopback, in-memory DB),
ACCOUNTANT + CASHIER (clients of B1), MIRROR (manager console), each with its OWN in-memory
`AppDatabase`, installed only through production services (`ServerSetupWriter`, `ClientLinkService`,
`FirstUserVerifier`, `ModeActivator`, `AuthRepositoryImpl` with gate/offline policy/stamps; clock injected).
Harness: `test/helpers/fleet_harness.dart` (+ shared `lan_host_harness.dart`).

Last run (this tree, branch `feat/tables-reservations-permissions` @ 148f7cc3 + uncommitted):
**38 passed, 3 skipped (KNOWN-DEFECT), 0 failed**, ≈10.5 min (`run_e2e.ps1`: fleet row `PASS 38/3/0 680 s`;
the whole script: 86 passed, 14 skipped, 0 failed, exit 0).

## Scenario table

| Scenario | Tests | Result | Evidence |
|---|---|---|---|
| F1 install order | F1.1–F1.4 | PASS | main provisioned first; codes bound to kind+branch; accountant+cashier pair as client B1, mirror as mirror; on every device the seeded admin is disabled, only the main's users sign in, wrong password / other-branch user rejected |
| F2 data flow | F2.1–F2.3 | PASS | cashier sale reaches the main once; accountant sees it after sync; mirror reads all branches, branch device only its own |
| F3 offline | F3.1–F3.4 | PASS | main's HTTP server stopped: stored-credential login inside grace; unknown user rejected; beyond grace rejected in ENFORCE, only reported in SHADOW; main back: outbox replays idempotently (one invoice) |
| F4 changes on main | F4.1–F4.5 | PASS | new user, password change, deactivation, branch removal, role change: online refusal is immediate; offline the old state only inside grace |
| F5 forced password change | F5.1–F5.2 | PASS | temp password → change on main → works on another device; policy enforced on the main |
| F6 mirror | F6.1–F6.5 | PASS | per-device token (not the legacy bearer); `mirror_console` required (403 `mirror_console_denied`); B1+B2 manager sees both branches, nothing outside scope; writes refused without permission / pushed with it / offline refused, nothing queued; offline grace login |
| F7 revocation | F7.1–F7.3 | PASS | revoked device 401 `device_revoked` on every route and on login; its queued sale never lands; other devices untouched |
| F8 re-provision | F8.1–F8.3 | PASS | `resetProvisioning` + mirror install ⇒ `network_mode=mirror`, record `mirror`, `MirrorState.isConfigured`, main sees the device as `mirror`, reboot (`reconcileWithDb`) stays mirror, manager signs in; a mirror commit without pairing ⇒ `MIRROR_NOT_PAIRED` (never client); mirror→client drops the mirror identity |
| F9 security | F9.1–F9.4 PASS, F9.5 KNOWN-DEFECT | PASS / KNOWN-DEFECT | token confined to its kind (warehouse/mirror), stolen token under another id dead; admin hash never delivered to non-admin sessions; legacy bearer telemetry; device lockout survives restart. F9.5 = FLEET-6 |
| F10 settings adoption | F10.1–F10.3 | PASS | company/currency/profile/tax/grace arrive and are applied; per-device keys and secrets never overwritten/shipped; new grace governs offline login |
| F11 defects | F11.1, F11.2 KNOWN-DEFECT; F11.3, F11.4 PASS | see below | |

## Status update (follow-up fix pass) — FLEET-1, 3, 6 FIXED

Fleet suite after the fixes: **41 passed, 0 skipped, 0 failed** (`flutter test test/e2e_fleet --concurrency=1`,
≈11 min). The KNOWN-DEFECT skips for F11.1, F11.2 and F9.5 are removed; the `FLEET_RUN_KNOWN_DEFECTS` switch stays
in `fleet_harness.dart` (`knownDefect`) for future pins. The route stubs in the harness are gone (the real routes answer).

- **FLEET-1 FIXED** — `GET /api/pos-terminals` (`_getPosTerminals`, `routes/api_get_directory.dart`; registered in
  `routes/api_routes_read.dart`): reference data, scoped by `_resolveBranchScope` (client → its branch, multi-branch
  manager/mirror → all his branches, full-access → all). A mirror may READ it
  (`LanDeviceRoutePolicy.allows(..., method:)`); registering a terminal stays `403 device_scope`.
- **FLEET-3 FIXED** — `GET /api/sale-bom-consumptions` (`_getSaleBomConsumptions`): transactional, fail-closed without
  identity (`failClosedOnNoIdentity: true`), rows whose `branch_id` or parent sale's branch is in scope.
- **Guard** — `test/unit/sync_strategy_endpoints_exist_test.dart` parses every `apiEndpoint` of the sync strategies and
  asserts a registered GET route in `test/golden/api_routes.txt`. It found exactly these two; no other strategy points
  at a missing route. Golden updated (`GET /api/pos-terminals`, `GET /api/sale-bom-consumptions`).
- **FLEET-6 FIXED** — `ServerLoginThrottle` persists `{key:[count,lastMs]}` write-behind under the host-local setting
  `server_login_throttle_v1` (added to `kDeviceLocalSettingKeys`, filtered from `GET /api/settings`), reloaded by
  `ServerLoginThrottle.configure(db)` from the `ApiHandler` constructor. Bounded (500 entries) and entries older than
  the 15-min lockout window are dropped on write/load. No schema change. Unit test:
  `test/unit/api/server_login_throttle_persistence_test.dart` (restart on the same DB); F9.5 un-skipped and passing.
- **online_login_lifecycle_test (mirror console)** — fixture issue, product check untouched: the host fixture already
  grants `mirror_console` to the manager role, but the paired test device never received the role→permission rows that
  `_requireConsole` reads locally. `pairDevice` now copies them (as the real role-permission sync does); the
  "refused by the host" assertion uses a stale device copy for the accountant's role, and a new test pins the
  device-side refusal with a truthful copy.

## Defects as originally found (historical; product code was NOT touched in that pass)

### FLEET-1 — no `GET /api/pos-terminals` (was skipped: `KNOWN-DEFECT-FLEET-1`, test F11.1) — FIXED, see above
- Client sync strategy `lib/services/sync/strategies/pos_terminal_sync_strategy.dart:27` pulls `/api/pos-terminals`;
  the router only registers `POST /api/pos-terminals/register` (`lib/services/api/routes/api_routes_write.dart:10`).
- Evidence (`FLEET_RUN_KNOWN_DEFECTS=1`): `404 {"error":"Not found","path":"/api/pos-terminals",...,"method":"GET"}`.
- Fix: add a read route returning `{pos_terminals:[...], count}` scoped to the device's branch (clients) / all (mirror).

### FLEET-3 — no `GET /api/sale-bom-consumptions` (`KNOWN-DEFECT-FLEET-3`, F11.2)
- Same pattern: `lib/services/sync/strategies/sale_bom_consumption_sync_strategy.dart:27`, no read route; 404 as above.
- Fix: add the read route (branch-scoped through the parent sale).

### FLEET-6 — main login throttle is memory-only (`KNOWN-DEFECT-FLEET-6`, F9.5)
- `lib/services/api/server_login_throttle.dart:25` `static final Map<String,_Attempt> _attempts`: a restart of the
  main clears a brute-force lockout (the device-side `LoginLockoutStore` does persist: F9.4 passes).
- Not executed with `FLEET_RUN_KNOWN_DEFECTS=1` in this pass (static evidence only).
- Fix: persist attempts/lockouts (settings table or `LoginLockoutStore`-style store) and reload at start.

### Resolved in the tree while the fleet was built (kept as regression pins, NOT skipped)
- FLEET-2 (`/api/user-branch-access` not scoped): now scoped — F11.3 passes with the shim OFF.
- FLEET-5 (first-user verification delivered users without branch-access rows): F11.4 passes with
  `closeAccessGap:false`. The harness still calls the extra credential pull (harmless).

## Test-side corrections made in this pass (not product defects)
- F6.4: after a successful mirror write the production path pulls the main's state back
  (`lib/services/interceptor/cwi_core_support.dart:243-244`, `_refreshAfterWrite`), so the mirror legitimately holds a
  COPY of the invoice the main accepted. The test now asserts: no row the main refused, no outbox row, only accepted
  globalIds locally. Refusals (no permission, offline) still assert "nothing local, nothing queued".
- F9.1: a `warehouse` code needs branch + TLS fingerprint (`lan_pairing_kinds.dart:24-33`); the test issued it without.
- f02/f04/f07/f09/f10: duplicate `library` directive, unused imports, missing `database_barrel.dart` import
  (`getUserByUsername`/`getSettingValue` are extensions exported there).

## Outside my scope — breakage seen in files I may not edit
`test/integration/online_login_lifecycle_test.dart` (group "mirror console (multi-branch manager)", 2 tests) FAILS in the
current tree: `AuthRepositoryImpl._requireConsole` (`lib/data/repositories/auth_repository_impl.dart:240-251`, uncommitted
M2 work by the concurrent worker) rejects `mgr1` with "هذا الجهاز كونسول مدير الفروع؛ حسابك غير مخوَّل له" because the
fixture's manager role does not hold `mirror_console`. Fix on the owner of that test: grant `mirror_console` to the
fixture's manager role (as the fleet harness does). The other 16 tests of that file, and
`first_run_pairing_to_login_real_host_test.dart` / `lan_device_credentials_flow_test.dart` (18 together, run with
`--concurrency=1`) pass. Run together at default concurrency the first-run test hit its 30 s default timeout
(CPU contention) — run those files with `--concurrency=1`.

## Harness limits
- Process-wide singletons (`NetworkService`, `ServerProxy`, `MirrorState`, prefs, device id, `SyncInterceptor`) are
  swapped per device with `Fleet.use`; only one device is "live" at a time (no concurrent devices).
- The main is in-process; `hostIsolation()` makes it behave as a server while it handles a request.
- Loopback HTTP only: no TLS (warehouse codes are issued with a placeholder fingerprint), no real network faults
  (outage = `stopServing`), SQLite in memory (no Postgres, no encryption at rest).
- The mirror read-only timer / `MirrorConnectivity` (M2 widget guard) is not driven; offline mirror writes are
  asserted at the interceptor level.
- Time is injected only into the credential stamps and the offline policy; the rest of the app uses the wall clock.
- Transient `sqlite3.dll PathExistsException` crashes of `flutter test` occur when another flutter process runs; the
  `run_e2e.ps1` retry covers them.
