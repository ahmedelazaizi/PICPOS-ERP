# Login leftovers — fixes (2026-10-26)

Branch `feat/tables-reservations-permissions`. No Drift/schema change, no build_runner, nothing committed.
Owner decisions kept: main = source of truth; legacy shared bearer token untouched; offline grace default 7 days; shadow stays the default (no install is locked out by this work).

## 1. Offline-login ENFORCE switch + expiry warning — fixed
- Root cause: `offline_login_mode` could only be flipped from code (`AuthSessionGate.setMode`); the shadow decisions were only written to the diagnostic log; no user-facing countdown.
- Files: `services/auth/shadow_login_log.dart` (bounded log, key `offline_login_shadow_log_v1`, device-local, ≤200 entries / 90 days), `services/auth/offline_login_standing.dart` (N-days-left / expired from the existing stamps + grace, injected clock), `data/providers/offline_login_providers.dart`, `presentation/settings_picpos/screens/offline_login_mode_tile.dart` (shown inside `DeviceReprovisionSection`, branch devices only, gated by `settings_edit`, PicPosDialog confirmation with the 30-day "would have refused" summary), `presentation/widgets/offline_login_expiry_banner.dart` + `shell_banners.dart` (replace the `LegacyDbKeyBanner` line in `app_shell.dart`, net −26 bytes), gate writes the log (`auth_session_gate.dart`, +2 lines), key added to `kDeviceLocalSettingKeys`.
- Tests (written first; compile-red then green): `test/unit/auth/offline_login_enforce_support_test.dart`, `test/unit/auth/shadow_log_gate_test.dart`, `test/widget/settings/offline_login_enforce_widgets_test.dart` (AR/EN × light/dark, confirm via PicPosDialog, permission-denied, banner states, providers on a real DB).
- Banner shows regardless of connectivity (the stamp is what ages); "expired" text asks to connect to the main.

## 2. HQ first-run record + single mode entry — fixed (record), fixed/changed (entries)
- Root cause: the HQ path wrote its settings into PostgreSQL but the device record lived only in the local SQLite, so after the restart into PG the boot did `ADOPT-BACKFILL` and no self-check ran.
- Fix: `ServerSetupWriter.apply` now writes `device_provisioning_v1` (mode=server, deviceKind=server, port, `pgConfigured=true` (new JSON field, no schema), `selfCheckPending`, `setupCompletedAt` kept on re-run) plus all derived keys inside the final transaction, `setup_completed` last. `SelfCheckId.database` (blocking) covers the HQ path; `noDefaultAdmin` is blocking for the server too.
- `database_settings_widget.dart` and `main_desktop.dart` now call `ModeActivator.commit` (removed from the legacy allow-list in `mode_change_single_entry_test.dart`). Behaviour change, deliberate: a REMOTE PostgreSQL host no longer silently flips the device to `client` (that needs pairing + first sync) — the user is told to use "Re-provision this device". Local PG → server and SQLite → standalone go through ModeActivator.
- Tests: `test/unit/setup/server_setup_writer_record_test.dart` (in-memory SQLite committer path: record, derived keys, boot adoption without backfill, gate → selfCheck, HQ self-check pass/fail), static guard updated.
- Not covered: no real PostgreSQL run (SQL text unchanged; PG runner not run).

## 3. Duplicate `admin` cleanup — fixed
- Root cause: an old sync inserted the main's admin under its own id next to the seeded id 1; prevention existed only for the "no row at that id" case, so an existing stray was updated and stayed active.
- Fix: `services/auth/admin_duplicate_repair.dart` (`repairDuplicateAdmins`, idempotent, transactional): id 1 stays the single active admin, adopts hash/salt/force flag/global id and the credential stamp (original time kept) from the stray that carries the main's data; strays are renamed `__dup_<id>_admin` and deactivated, never deleted (FK check test). Runs after a users sync and at boot for client/mirror records (`ProvisioningApplier`). `UserSyncStrategy` now always maps host `admin` (id≠1) onto row 1 so a retired stray is never revived. `CredentialStampStore.moveStamp` added.
- Tests: `test/unit/sync/duplicate_admin_repair_test.dart` (8, incl. resurrection-by-sync and boot hook), existing `synced_admin_identity_test.dart` still green.

## 4. Self-check items — fixed
- `deltaPull` (60 s budget enforced by the runner; real probe = one `fetchDelta('settings')` page) and `mainMatch` (company_global_id / system_currency / business_profile vs the main's `/api/settings` via the device token). States: pass / fail with reason / skip when no port; main down ⇒ fail, never a fake pass; both non-blocking. Labels in `first_run_self_check_screen.dart`. Tests: `test/unit/deployment/self_check_delta_and_match_test.dart` (11).
- Limit: the delta probe proves the authenticated pull endpoint answers in time, not that every table is current.

## 5. Dead `BranchAccountVerifier` — fixed
- The class and `test/unit/setup/branch_account_verifier_test.dart` removed (`git rm`, staged deletion). The file `branch_account_verifier.dart` stays because it still defines the live `BranchAccountVerifierPort`/`AccountVerification` used by `FirstUserVerifier`; header comment rewritten.

## 6. `test/repro_mirror`
- `r3_mirror_modes_test.dart` → `test/unit/sync/mirror_modes_predicates_test.dart`; `r5_r6_offline_forcechange_test.dart` → `test/security/host_password_endpoint_test.dart` (13 tests pass); the three repro files deleted. None still failing.

## Notes
- Foreign file: `lib/domain/repositories/purchase_orders_repository.dart` (warehouse worker) had a stray CR inside a doc comment (`\r` + `eceived_quantity`) that broke compilation of every test; I restored the single word `received_quantity` and touched nothing else.
- i18n: 20 keys appended to `assets/i18n/en.json`.
