# FINDINGS — unified register (release audit 2026-10-23)

| Item | Value |
|---|---|
| Version audited | `feat/tables-reservations-permissions` @ `d69be1eafc7d82b924723dfdbb53960b7e33acdb`, app `3.9.2+277` |
| Sources merged | [FINDINGS-A.md](<axis-A-security-sync/FINDINGS-A.md>) (34), [FINDINGS-B.md](<axis-B-data-accounting/FINDINGS-B.md>) (39), [FINDINGS-C.md](<axis-C-product-ux-release/FINDINGS-C.md>) (43) = 116 axis entries |
| Unified entries | **113** (3 merges, listed in §1) |
| Method | Static reading, artifact inspection, and one tool run (`dart pub outdated`). **No finding was reproduced at runtime.** See [TEST_RESULTS.md](<TEST_RESULTS.md>). |

This file decides each finding's severity, priority, verification status and whether it blocks release. If an axis file says something different on those fields, this file wins. The full record for each finding (repro steps, expected vs actual, evidence excerpt, impact, root cause, remediation, effort, acceptance) is in the axis section linked in the **Detail** column. Release blockers and merged entries have their consolidated record in §3 of this file.

## 0. How to read

**Verification status**

| Status | Meaning |
|---|---|
| `CONFIRMED-BY-READING` | The defect or gap was established by reading the exact code path at HEAD, by inspecting the shipped artifact, or from tool output. No runtime reproduction was done. The **Basis** column names which. |
| `SUSPECTED-NEEDS-REPRO` | At least one link in the causal chain is inferred. The finding must be reproduced before it is fixed or used to block. |

**Severity** is the impact if the issue triggers: Critical / High / Medium / Low / Info. It is the same scale in all three axes, so axis values were kept, with one exception: SYNC-003 was raised from Medium to High (see §1).

**Priority**, normalised across axes:

| Priority | Meaning (brief §14 group) |
|---|---|
| P0 | Release blocker: must be fixed, or explicitly waived by the owner, before release on at least one channel named in the row. |
| P1 | Must be fixed before wider rollout. |
| P2 | Important improvement, next cycle. |
| P3 | Optional / backlog. |

**Normalisation rules applied**

1. If an axis said a finding was "conditional" on a whole release channel (for example "PG server mode"), it was made a channel blocker: **P0** for that channel.
2. If the condition was a usage profile inside a channel (for example "tenants with fixed assets", or "reservations taken on client terminals"), the finding stays **P1 / Conditional**.
3. Findings that block only general (public) distribution, not the owner-controlled pilot, are **P0** here. The decision in [RELEASE_READINESS.md](<RELEASE_READINESS.md>) is about distribution to real users. The axis files had REL-002 at P1 and BKP-001 at P1.

**Channels:** `W` Windows desktop standalone · `L` LAN host + clients (SQLite host) · `PG` PostgreSQL server mode · `AND` Android apps (Van, POS, Admin) · `CI` tag-driven GitHub Release · `CLOUD` cloud server · `REPO` repository hygiene or tooling only.

**ID scheme.** IDs are stable and keep their axis prefix: `SEC`/`AUTHZ`/`SYNC` from axis A; `RPT`/`ACC`/`DATA`/`MIG`/`BKP` from axis B; `BRAND`/`UX`/`ARCH`/`REL`/`DEP` from axis C. When findings were merged, the most complete one keeps its ID as the canonical ID and the others become **aliases**. Aliases still resolve to the canonical entry in every document. Prior-QA IDs (`B-n`, `D-n`, `C-n` from `D:\qa\reports\Q-review.md` / `FINAL-QA-VERDICT.md`) are listed as aliases too.

## 1. De-duplication and conflict resolution log

| Canonical | Aliases merged | Why merged / how resolved |
|---|---|---|
| **AUTHZ-003** | RPT-006, B-2 | Both report that figure masking (commit `d2272da0`) is bypassed by secondary outputs of the same data: party statement, party export/import, product exports, the customer picker and the statement export. The locations of both are kept in §3. **Blocking resolved as Yes.** RPT-006 was "conditional on masking being advertised as a control", and the candidate commit's own message advertises it ("hide monetary figures without view permission"). If the owner drops that claim from the release, the finding falls to P1 (owner question Q4). |
| **SYNC-003** | DATA-001, D-3 | Same defect: client-created table reservations are never pushed to the host. **Severity raised from Medium (A) to High (B)**, because double booking and lost reservations are user-visible in multi-terminal restaurants. P1, Conditional (blocks LAN deployments that take reservations on client terminals). |
| **BRAND-003** | REL-001 | Same CI `release` job (`ci.yml:641-698`), same fix (use the shared build script) and same acceptance check. It builds UralCash by default (brand), skips the SQLCipher DLL swap, and stamps `run_number` as the build number. Severity is Critical (from BRAND-003). |

Partial overlaps were cross-referenced, not merged, because they need different fixes:

- AUTHZ-002 (sales details dialog) and AUTHZ-007 (margin card for every cashier): same dialog, different permissions. One change fixes both.
- AUTHZ-003 (gating of party import) and DATA-003 (the import overwrites `parties.balance` with no journal entry, even for authorised users).
- SYNC-001 (mixed-fleet loss) and SYNC-002 (root cause: swallowed row failures while the watermark advances).
- REL-003 (update path) overlaps MIG-004 (non-blocking pre-migration backup), MIG-001 (no newer-DB guard) and SYNC-001 (no version handshake). REL-003 keeps only the updater and installer-side gaps.
- BRAND-005 (UralCash salts in the binary) relates to SEC-005 (pepper of the legacy DB key) and SEC-006 (salt of the legacy bearer). The values must stay byte-identical; only the literals may go.
- BRAND-012 (brand guard does not scan the artifact) and ARCH-006 (CI gaps): BRAND-012 owns the brand scan; ARCH-006 owns the other CI jobs.
- UX-002 (currency literals) has alias **G1b-#2** for the report cards. The cards were fixed before HEAD (FINAL-QA-VERDICT line 24); the 15+ remaining sites are open.

Conflicts between sources, resolved by evidence:

| Conflict | Resolution |
|---|---|
| UX-011 item (2) says the admin-QR pairing key is "long-lived" (from FINAL-QA-VERDICT line 43). SEC-017 refutes this: the QR carries the Ed25519 **public** key plus a one-time 10-minute code. | SEC-017 wins: it read `linked_devices_section.dart:799-816`, `cloud_link_controller.dart:202-209` and `signature.dart:73-88`. The warehouse prerequisite is restated as "pairing hardening" (SEC-003, SEC-006, SEC-007, SEC-008, plus P7 QR payload v2, which is not done). See [the warehouse plan](<../../plans/2026-10-23-warehouse-app-plan.md>). |
| FINAL-QA-VERDICT line 11 says analyze was "clean". `D:\qa\logs4\S0_analyze.log` reports `2 issues found` (info level, `use_build_context_synchronously`). | The log wins: exit 0, but 2 infos. ARCH-004 stays open. Whether CI treats infos as fatal is not verified. |
| TEST-EVIDENCE-A and TEST-EVIDENCE-C quote S5 E2E as "+2". TEST-EVIDENCE-B and the brief quote 48. | `S5_e2e.log` has seven suites. The `_summary.txt` tail captured only the last suite (`+2`). The log's final table says `المجموع: نجح 48 · تخطّى 7 · فشل 0`. 48 is correct (see TEST_RESULTS). |
| Prior item A-7 "no pre-upgrade backup". | Incorrect at HEAD: `runOnUpgrade` takes one, but it is best-effort (MIG-004). |

## 2. Summary

**Counts by severity (unified):** Critical 1 · High 24 · Medium 47 · Low 34 · Info 7 = **113**.
**Verification status:** 13 `SUSPECTED-NEEDS-REPRO`, 100 `CONFIRMED-BY-READING`, 0 reproduced at runtime.

**Release blockers (P0) by channel:**

| Channel | Blocking findings |
|---|---|
| W, L, PG (all desktop) | BRAND-001, BRAND-002, BRAND-004, BRAND-012, AUTHZ-001, AUTHZ-002, AUTHZ-003, UX-001, RPT-001, REL-005 (until reproduced), REL-002 (public distribution), BKP-001 (general availability); UX-002 for EGP installs |
| L, PG additionally | SEC-001 (with SEC-002), SEC-002, SYNC-001 (conditional: mixed fleet) |
| PG additionally | RPT-003 |
| AND | REL-004 (Van and POS APKs) |
| CI | BRAND-003 (alias REL-001) |

**Conditional (P1, blocks only a usage profile):** ACC-001 (fixed assets near end of life) and SYNC-003 (reservations entered on LAN client terminals).

## 3. Consolidated records — release blockers and merged entries

All "Repro" steps below are proposed and **NOT_RUN**. Effort sizes come from the axis files (XS < 0.5 d, S ≈ 0.5–1 d, M ≈ 2–4 d) and are uncertain.

### SEC-001 — Renaming the bootstrap admin makes the host re-create `admin`/`admin` with the system-admin role
- **Axis / type:** A, security, Confirmed defect. **Severity** High · **Priority** P0 · **Status** CONFIRMED-BY-READING (code read end to end) · **Channels** L, PG.
- **Location:** `lib/services/api/routes/api_get_users.dart:163-256` (`_ensureBootstrapAdminOnce`, insert at :233-251); `lib/presentation/screens/settings/widgets/edit_user_dialog.dart:55-62,140-149`; `lib/data/database/daos/user_dao.dart:225-259`; `lib/services/api/data/api_data_users_roles.dart:76-130`.
- **Preconditions / repro:** rename user id 1 → restart the host → let a client sync (`GET /api/users`) → query `users WHERE username='admin'`.
- **Expected / actual:** the rename is respected / a second system-admin `admin` with password `admin` appears silently.
- **Impact:** full takeover with known credentials. Through the API, no password change is forced (SEC-002).
- **Root cause:** the self-heal identifies the admin by username only.
- **Remediation:** identify the bootstrap admin by a stable marker (id 1 or a stored `global_id`); never auto-create a known-password account when users exist. Effort S.
- **Acceptance:** an integration test renames id 1, calls `GET /api/users`, and finds no new `admin` row and an unchanged user count.
- **Blocks:** Yes (L, PG), together with SEC-002. **Detail:** [A:94](<axis-A-security-sync/FINDINGS-A.md#L94>).

### SEC-002 — `POST /api/auth/session` and `/api/auth/verify-admin` ignore `force_password_change`
- A, Confirmed defect · High · P0 · CONFIRMED-BY-READING · L, PG.
- **Location:** `lib/services/api/api_auth_handler.dart:156-208` and `:76-126`. The local UI does enforce the change (`login_screen.dart:359-376`).
- **Repro:** with a paired-device bearer, `POST /api/auth/session {"username":"admin","password":"admin"}` while the admin still has the flag. Expected 403; the code issues a 30-day token.
- **Impact:** API administration with default credentials. Server-mode installs keep `admin/admin` because the wizard sets the admin password only in standalone mode (`setup_finish_runner.dart:316-327`).
- **Remediation:** reject flagged users in both handlers, or issue a change-password-only token. Effort XS–S.
- **Acceptance:** a unit test where a flagged user gets 403 or a restricted token from both handlers.
- **Blocks:** Yes (L, PG). **Detail:** [A:153](<axis-A-security-sync/FINDINGS-A.md#L153>).

### AUTHZ-001 — Conditional grants can be self-approved in the manager-override dialog
- A, Confirmed defect · High · P0 · CONFIRMED-BY-READING · W, L, PG.
- **Location:** `lib/presentation/widgets/permission_guard.dart:863-890` (`ensurePermission`) and `:609-657` (the approver is whoever's password matches; no approver ≠ requester check, no unconditional-grant check); `permissions_dao.dart:288-292`.
- **Repro:** a role with `tables_merge` in conditional mode → merge tables → type the cashier's own password → approved.
- **Impact:** the four-eyes control is void for every `cond:` permission, including the candidate's B-3 table gates and the booking gates.
- **Remediation:** reject approver == requester and require an unconditional grant (or system admin). Effort XS–S.
- **Acceptance:** widget tests: own password → denied; another conditional holder → denied; unconditional holder → approved.
- **Blocks:** Yes. The candidate's B-3 fix depends on this dialog. **Detail:** [A:464](<axis-A-security-sync/FINDINGS-A.md#L464>).

### AUTHZ-002 (alias B-1) — Sales-invoice figure masking bypassed by "View details"
- A, Confirmed defect · High · P0 · CONFIRMED-BY-READING · W, L, PG.
- **Location:** `lib/core/permissions/screen_access_resolver.dart:111-117`; the eye button is ungated at `sales_invoices_table.dart:672-677`; the dialog renders every amount plus `ProfitMarginAnalysisWidget` at `sales_invoice_dialogs.dart:42-233`.
- **Repro:** role `{pos_access, sales_create}` → Sales invoices (totals masked) → eye icon → all amounts shown.
- **Remediation:** gate money blocks and the margin widget with `canSeeScreenFigures(…salesInvoices)`; this also fixes AUTHZ-007. Effort S.
- **Acceptance:** widget test: role `{sales_create}` opens details and sees no amounts and no margin card.
- **Blocks:** Yes (rule b: a control this candidate adds is bypassable in the same screen). **Detail:** [A:502](<axis-A-security-sync/FINDINGS-A.md#L502>).

### AUTHZ-003 (aliases RPT-006, B-2) — Figure masking and gating bypassed through statements, exports, imports and the customer picker
- A+B, Confirmed defect · High · P0 · CONFIRMED-BY-READING · W, L, PG.
- **All locations (from both axes):**
  - Parties screen: statement, "تصدير" and "استيراد" are ungated; only "إضافة" is guarded (`lib/presentation/parties_picpos/screens/parties_picpos_screen.dart:164-202`, guard at :204-212).
  - `PartyStatementPicposScreen` has no permission references.
  - Party export writes every party with balance and credit limit, unscoped by branch: `lib/data/services/excel_service.dart:902-965` (balance cells :930, :953); `parties_repository_impl.dart:202` has no branch parameter.
  - Party import: `excel_service.dart:968-1011` creates parties and overwrites `balance` (:1001-1007) with no `customers_add`/`customers_edit` check (integrity side → DATA-003).
  - The products template export writes prices and cost (`excel_service.dart:288-295`), as does the CSV `exportProducts` (`lib/services/csv_import_export_service.dart:37`).
  - Customer picker card shows the balance unmasked: `lib/presentation/shared_widgets/customer_picker/customer_picker_card.dart:101`.
  - Statement export uses `party.balance`: `party_statement_export_picpos.dart:84`.
  - `maskedFinancialFigure` is documented for exports, but no export uses it: `lib/core/permissions/financial_figures_access.dart:44-45`.
  - `screenFiguresVisibilityProvider` is used in 7 presentation files only.
- **Repro:** role `{customers_add}` → Customers (balances masked) → statement → full ledger; export → xlsx with all branches' balances; import a crafted sheet → balances overwritten.
- **Impact:** cross-branch data exposure that defeats the new masking and branch isolation; a balance cache that diverges from the GL.
- **Root cause:** F.2 widened screen access; secondary entry points and output services were never wired to the figure predicate. Authorization is widget-level (AUTHZ-010).
- **Remediation:**
  - Gate the statement with the view codes.
  - Gate export with view plus a dedicated export code, and branch-scope it.
  - Gate import with add + edit, and stop writing `balance` on update (DATA-003).
  - Pass figure visibility into the export and print services and the picker card.
  - Effort M.
- **Acceptance:**
  - Widget/service tests for role `{customers_add}`: statement and export are disabled or need approval; exported rows ⊆ branch scope; balance and price cells are masked or absent in party/product exports, the picker and the statement print.
  - A structural test: every money widget or export on a figure-masked screen uses the predicate.
- **Blocks:** Yes. Downgrade to P1 only if the owner removes "hide monetary figures" from the release claims (Q4). **Detail:** [A:524](<axis-A-security-sync/FINDINGS-A.md#L524>), [B:158](<axis-B-data-accounting/FINDINGS-B.md#L158>).

### SYNC-001 (alias D-1) — Mixed fleet: v195 clients drop v196 `table_reservations` rows permanently
- A, Confirmed defect · High · P0 · CONFIRMED-BY-READING (runtime against a real v195 client NOT_RUN) · L, PG.
- **Location:** the column filter exists only in new clients (`lib/services/delta_pull_column_filter.dart`, wired at `delta_pull_service.dart:1120`); the host sends `SELECT *` (`api_get_sync_pull.dart:179`); there is no schema/version handshake; row failures are swallowed (`delta_pull_service.dart:1321-1329`) while the watermark advances (:740-758).
- **Repro:** host 3.9.2 + client 3.9.1 → host creates or updates a reservation → client pulls → row silently skipped; still missing after the client upgrades.
- **Remediation (release now):** a release note that enforces a simultaneous fleet upgrade, plus a v196 migration that resets the `table_reservations` watermark on clients. **Next:** a host-side schema check (`X-Client-Schema`) and SYNC-002.
- **Acceptance:** an integration test where a v195-shaped client pulls a v196 row → error surfaced, watermark not advanced; the watermark is reset after the v196 migration.
- **Blocks:** Yes, conditional. Acceptable only with an enforced simultaneous upgrade plus the watermark reset (or a documented manual reset). **Detail:** [A:670](<axis-A-security-sync/FINDINGS-A.md#L670>).

### SYNC-003 (aliases DATA-001, D-3) — Table reservations made on a LAN client never reach the host
- A+B, Confirmed defect · **High** (normalised) · P1 · CONFIRMED-BY-READING (no push path; later overwrite or orphaning by pull is unverified) · L, PG.
- **All locations:**
  - `createReservation`/`updateReservationStatus`/`cancelReservation`/`deleteReservation` write locally only: `lib/data/database/daos/tables_dao.dart:621-714`; entry via `table_session_service.dart:192-221`.
  - The repository has no client branch: `restaurant_repository_impl.dart:127-148`, compared with `saveFloorPlanLayout`, which uses `ClientWriteInterceptor.dispatchWrite` (:106-116).
  - `table_reservations` appears only in pull lists (`api_sync_pull_tables.dart:72,231`; `delta_pull_service.dart:200,344,456`). `bookings` does have a CWI path (`cwi_sync_foundation.dart:214`).
  - Id-collision renumbering on a later pull: `delta_pull_service.dart:1150-1170`.
- **Impact:** double bookings and lost reservations across terminals; incomplete customer reservation history on the host.
- **Remediation:** a CWI submit plus a host route idempotent by `global_id` (mirroring bookings), or block reservation writes in client mode with a message. Effort M.
- **Acceptance:** E2E: the client creates and cancels a reservation → the host row exists with the same `global_id` and status within one sync cycle, including after offline → online replay.
- **Blocks:** Conditional. Blocks LAN deployments that take reservations on client terminals; otherwise release-note it. **Detail:** [A:715](<axis-A-security-sync/FINDINGS-A.md#L715>), [B:144](<axis-B-data-accounting/FINDINGS-B.md#L144>).

### RPT-001 — Party statement includes voided/soft-deleted invoices and deleted payments
- B, Confirmed defect · High · P0 · CONFIRMED-BY-READING (inclusion: high confidence; net effect per void flow: medium, so run the ~10-minute repro first) · W, L, PG.
- **Location:** `lib/data/database/daos/party_transactions_dao.dart:29-34, 71-76, 112-119`, opening-balance queries ≈ :421-475; `parties_repository_impl.dart:114-160` (`getCalculatedPartyBalance`), consumed by `reconciliation_service.dart:129`.
- **Repro:** credit sale 100 → void (`status='voided', is_deleted=1`) → open the statement → closing balance is 100 above the card and GL.
- **Impact:** a customer-facing document overstates debt.
- **Remediation:** add `is_deleted`/`deleted_at` filters to every statement and opening query; longer term, build the statement from the GL sub-account. Effort S.
- **Acceptance:** a test with a voided credit sale, a voided cash sale, a voided purchase and a soft-deleted receipt: statement closing = `parties.balance` = GL sub-account.
- **Blocks:** Yes. Downgrade to Medium if the repro shows that the void flow adds an offsetting row. **Detail:** [B:87](<axis-B-data-accounting/FINDINGS-B.md#L87>).

### RPT-003 — `getArAgingReport` SQL is SQLite-only and fails on PostgreSQL
- B, Confirmed defect (static derivation; PG execution NOT_RUN) · High · **P0 for PG** · CONFIRMED-BY-READING · PG.
- **Location:** `lib/data/database/daos/party_reconciliation_dao.dart:57-64, 107-114`; rewrite rules `pg_compat_sql.dart:48-57, 139-149`; callers `report_providers.dart:46` and `admin_snapshot_builder.dart:72-73`.
- **Actual (derived):**
  - In `julianday(COALESCE(...), 'unixepoch')`, the comma inside `COALESCE` defeats the rewrite rule, and the generic rule then produces a row constructor.
  - Scalar `MAX(x, 0)` does not exist on PG.
- **Remediation:** rebuild it on the portable `_agedBalances` (:196-200), and add a PG test. Effort S.
- **Acceptance:** a `test/integration_pg` case where AR and AP match the SQLite result on the same fixture.
- **Blocks:** Yes for the PG channel. **Detail:** [B:127](<axis-B-data-accounting/FINDINGS-B.md#L127>).

### BKP-001 — No test or drill restores a real encrypted backup
- B, Missing requirement · High · P0 (general availability) · CONFIRMED-BY-READING (the test inventory shows only fake openers and payloads) · W, L.
- **Evidence:** `test/unit/pending_restore_test.dart:13-16` (fake opener, file starts with `OK`); `test/integration/data_wipe_service_test.dart:656-723` (`'fake sqlite payload'`); no restore drill in FINAL-QA-VERDICT; this audit ran no drill (NOT_RUN).
- **Remediation:** an integration test (encrypted DB with data → backup → mutate → restore → simulated reboot → assert rows and key) and a manual drill on a copy of a real install. Effort M.
- **Acceptance:** the test passes in CI and a drill log exists in `docs/handoff/`.
- **Blocks:** Yes for general availability (the brief: a backup button is not proof of restorability). The owner-controlled pilot is outside this decision. **Detail:** [B:173](<axis-B-data-accounting/FINDINGS-B.md#L173>).

### BRAND-001 — UralCash company logo shipped inside every PicPos build and installer
- C, Defect · High · P0 · CONFIRMED-BY-READING (artifact: SHA-256 match + visual) · W, L, PG.
- **Location:** `pubspec.yaml:139-141` (`- logo.PNG`); shipped as `FlavorBuilds\PicPos\data\flutter_assets\logo.PNG` (141,097 bytes, hash = repo `logo.PNG`); presence in the installer is inferred from `installer/setup.iss:246` (payload not unpacked).
- **Remediation:** delete `logo.PNG` from pubspec and from the repo, together with the UralCash `Brand.logoAsset` branch (owner decision 1: remove, do not keep). Effort S.
- **Acceptance:** the artifact scan (BRAND-012) finds no file whose hash equals the UralCash images.
- **Blocks:** Yes (owner requirement, 2026-10-23). **Detail:** [C:88](<axis-C-product-ux-release/FINDINGS-C.md#L88>).

### BRAND-002 — Shipped i18n catalogs contain UralCash strings; `catalog_ar.json` shipped but unused
- C, Defect · High · P0 · CONFIRMED-BY-READING (artifact scan T-C-03) · W, L, PG.
- **Location:** `assets/i18n/en.json:4340, 8743, 9874`; `assets/i18n/catalog_ar.json:4048, 8245, 9325`; declared at `pubspec.yaml:137-138`. `catalog_ar.json` has no reference in `lib/` and maps Arabic keys to source `file:line` (1.1 MB).
- **Remediation:** after BRAND-009, regenerate `en.json` without the three keys; remove `catalog_ar.json` from assets (check first which tests read it). Effort S.
- **Acceptance:** the artifact scan finds 0 forbidden terms in `flutter_assets/**`, and `catalog_ar.json` is absent from the output.
- **Blocks:** Yes. **Detail:** [C:104](<axis-C-product-ux-release/FINDINGS-C.md#L104>).

### BRAND-003 (alias REL-001) — CI release job publishes a UralCash-branded, non-SQLCipher Windows build named "PicPos-ERP"
- C, Defect · **Critical** · P0 · CONFIRMED-BY-READING (workflow read; not executed) · CI.
- **All locations:**
  - `.github/workflows/ci.yml:641-645`: `flutter build windows --release --build-number=${{ github.run_number }}` with no `APP_BRAND` define (0 occurrences of `APP_BRAND`/`BRAND_` in workflows).
  - `ci.yml:648-698`: zip + GitHub Release on `v*.*.*` tags.
  - Compare `build_picpos.bat:114-133` (SQLCipher DLL swap + `findstr sqlcipher`), which CI lacks.
  - The run number overrides pubspec `+277`, so the exe version ≠ installer `AppVersion` (`installer_version_matches_pubspec_test`).
  - `cipher_version` probe (`connection_io.dart:70-118`) refuses plain sqlite3, so the CI artifact may fail to open its DB (inferred).
- **Impact:** a tag push ships a wrong-brand product with a separate data namespace; an "upgrade" from it looks like data loss.
- **Remediation:** make CI call the shared build script with the PicPos brand, the SQLCipher check and the artifact brand scan. **Until then, disable the `release` job.** Effort S.
- **Acceptance:** a CI run on a test tag produces `PicPos.exe` (CompanyName `PicPos`), FileVersion = pubspec, `sqlite3.dll` contains `sqlcipher`, and the brand scan exits 0.
- **Blocks:** Yes for any tag-driven release. **Detail:** [C:122](<axis-C-product-ux-release/FINDINGS-C.md#L122>), [C:599](<axis-C-product-ux-release/FINDINGS-C.md#L599>).

### BRAND-004 — Every brand default is UralCash
- C, Defect · High · P0 · CONFIRMED-BY-READING · W, L, PG, CI.
- **Location:** `lib/core/config/brand.dart:37-40` (`defaultValue: 'uralcash'`); `windows/CMakeLists.txt:14-36`; `windows/runner/Runner.rc:79-87`; `windows/runner/main.cpp:15`; `README.md:95`.
- **Impact:** `flutter run`, IDE runs, CI and any forgotten flag produce UralCash. The shipped 3.9.2 artifact itself is PicPos (T-C-05 PASS), because it was built with `build_picpos.bat`.
- **Remediation:** flip every default to PicPos, or delete the UralCash branch (owner decision 1 → delete). Effort S.
- **Acceptance:** `flutter build windows --release` with no defines yields `PicPos.exe`, CompanyName and title `PicPos`.
- **Blocks:** Yes (root cause of BRAND-003; owner requirement). **Detail:** [C:140](<axis-C-product-ux-release/FINDINGS-C.md#L140>).

### BRAND-012 — Brand guards do not cover the shipped artifact; CI never runs the PicPos guard
- C, Requirement gap · High · P0 · CONFIRMED-BY-READING · W, L, PG, CI.
- **Location:**
  - `test/unit/brand_isolation_test.dart` runs with the default (uralcash) brand.
  - `test/unit/brand_picpos_test.dart` is skipped unless `APP_BRAND=picpos` (:33, :275).
  - `build_picpos.bat:88-90` and `build_installer_picpos.bat:47-48` only check that `UralCash.exe` is absent.
  - The guards were green while BRAND-001/002 shipped.
- **Remediation:** add `tool/check_brand_artifact.ps1` (hash deny-list, byte scan in Latin-1 and UTF-16LE, VersionInfo assertion), call it from `build_picpos.bat` and from CI, and run `brand_picpos_test` in CI. Effort S.
- **Acceptance:** the scan fails on today's artifact (`logo.PNG`, `en.json`) and passes after BRAND-001/002/005.
- **Blocks:** Yes (needed to prove BRAND-001/002 closed). **Detail:** [C:280](<axis-C-product-ux-release/FINDINGS-C.md#L280>).

### UX-001 — Setup wizard offers SAR/AED/KWD/USD, the engine silently turns them into JOD, and the choice is final
- C, Defect · High · P0 · CONFIRMED-BY-READING (not run) · W, L, PG.
- **Location:** six chips at `lib/presentation/screens/setup_wizard/step_company_info.dart:51-58` (re-verified for this report); `CurrencyInfo.fromCode` knows only `EGP` and defaults to JOD (`lib/core/constants/app_constants.dart:215-223`); `SystemCurrencyNotifier.setCurrency` stores the raw code but applies JOD (`lib/data/providers/providers.dart:422-436`); the choice is locked after the first financial movement (:425-431).
- **Impact:** wrong currency symbol and 3-decimal precision on every document for 4 of the 6 chips, with no recovery short of reinstalling.
- **Remediation:** offer only JOD and EGP; make `fromCode` throw on unknown codes. Effort S. The redesign plan adopts this.
- **Acceptance:** a widget test shows exactly the supported chips; `fromCode('SAR')` throws; `system_currency` ∈ {JOD, EGP} after setup.
- **Blocks:** Yes (irreversible data error at first run). **Detail:** [C:323](<axis-C-product-ux-release/FINDINGS-C.md#L323>).

### UX-002 (alias G1b-#2) — Currency literals `ج.م` / `د.أ` / `JOD` hardcoded in 15+ screens and dialogs
- C, Defect · High · P0 for EGP installs (POS), P1 otherwise · CONFIRMED-BY-READING · W, L, PG.
- **Location (all kept):**
  - `fixed_assets_picpos_screen.dart:1034,1041`, `asset_locations_picpos_screen.dart:141`
  - `opex_picpos_screen.dart:571,890,1004,1011,1018,1185`, `opex_picpos_allocate_dialog.dart:319-320`
  - `activity_log_items_picpos.dart:288,326`, legacy `activity_log_items.dart:268,306`
  - `product_card.dart:462` (every POS tile), `customer_selector_v2.dart:240`
  - `pos_expense_dialog.dart:471`, `pos_deleted_items_dialog.dart:77`, `pos_previous_expenses_dialog.dart:165,245,283`
  - `pos_opening_balance_dialog.dart:111`, `picpos_opening_balance_dialog.dart:130`
  - `return_details_panel.dart:276,403,542,654,711,796`
  - `app_localizations.dart:53,88`, `quick_sale_policy.dart:489,505,671`, `en.json:141`
  - The report cards (G1b-#2) were fixed before HEAD.
- **Impact:** Egyptian cashiers see `د.أ` on product tiles, refunds and opening balance; Jordanian users see `ج.م` on fixed assets and OPEX. The amounts are right; the labels are wrong.
- **Remediation:** use the canonical getter; add a structural guard against currency literals under `lib/presentation/**`. Effort S–M.
- **Acceptance:** the guard passes; a widget test with EGP renders `ج.م` on `ProductCard` and `ReturnDetailsPanel`.
- **Blocks:** Yes for any EGP deployment. **Detail:** [C:341](<axis-C-product-ux-release/FINDINGS-C.md#L341>).

### REL-002 — Installer, exe and DLLs unsigned (SmartScreen "unknown publisher")
- C, Requirement gap · High · P0 (public distribution) · CONFIRMED-BY-READING (tool: `Get-AuthenticodeSignature` = NotSigned on the setup exe, `PicPos.exe` and `sqlite3.dll`) · W, L, PG.
- **Location:** signing is optional: `installer/setup.iss:190-195`, `build_installer_picpos.bat:72-76`, `tool/sign_file.cmd` (exits 0 with no identity).
- **Remediation:** obtain an OV/EV certificate; make a release build fail when no identity is set. Effort S (plus certificate procurement lead time, unknown).
- **Acceptance:** all three files report Valid; a release build without an identity fails.
- **Blocks:** Yes for public distribution. Acceptable for the owner-controlled pilot, which already shows a warning text. **Detail:** [C:608](<axis-C-product-ux-release/FINDINGS-C.md#L608>).

### REL-004 — Android release signing: Van always uses the debug key, POS falls back to it
- C, Defect · High · P0 (AND) · CONFIRMED-BY-READING · AND.
- **Location:** `mobile/android/app/build.gradle.kts:36-38` (always debug); `mobile_pos/android/app/build.gradle.kts:16-20,60` (fallback); `mobile_admin/android/app/build.gradle.kts:29-45,84-88` fails closed (the correct pattern).
- **Impact:** debug-signed APKs cannot be updated by a properly signed build later (uninstall, data loss); anyone with the shared debug key can ship an "update".
- **Remediation:** copy `mobile_admin`'s `validateReleaseSigning` into the other apps; add a CI APK release build that fails on debug signing (ARCH-006). Effort S.
- **Acceptance:** `flutter build apk --release` fails without `key.properties` in all 3 apps; `apksigner verify --print-certs` shows the release certificate.
- **Blocks:** Yes for distributing the Van or POS APKs. **Detail:** [C:638](<axis-C-product-ux-release/FINDINGS-C.md#L638>).

### REL-005 — Trial watermark and activation cache depend on whether Settings was opened
- C, Defect · High · P0 · **SUSPECTED-NEEDS-REPRO** (code path read; runtime not reproduced; no receipt was printed in G1/G1b/G2) · W, L, PG.
- **Location:** `lib/core/trial/trial_state.dart:7-16`, `trial_policy.dart:80-90`; the startup refresh is guarded by `AppConfig.isDemo` (`app_main_screen_lifecycle.dart:27-30`); the cache is filled only when `activationStatusProvider` is watched (Settings › About, `add_product_dialog.dart:893`); banner printing at `thermal_receipt_generator.dart:1137` and `template_pdf_renderer.dart:204`.
- **Predicted actual:** after a fresh launch, receipts carry the trial banner even on an activated machine, until Settings is opened.
- **Repro to run:** fresh launch of an activated build → POS sale → print preview → check for the banner; open Settings › About; print again; compare.
- **Remediation:** call `refreshActivationStatus()` unconditionally at startup; the owner decides what activation gates in non-demo builds (Q6). Effort XS.
- **Acceptance:** a test with startup, no Settings visit and an activated key gives `showWatermark == false`.
- **Blocks:** Yes until the repro is run (customer-facing documents). If the repro shows no banner, close it as not reproduced. **Detail:** [C:654](<axis-C-product-ux-release/FINDINGS-C.md#L654>).

## 4. Full register (113 entries)

Columns: **Status** C = CONFIRMED-BY-READING, S = SUSPECTED-NEEDS-REPRO. **Basis**: code = code read; art = artifact inspected; tool = tool output; tests = test inventory; plan = plan document. **Blocks**: Yes / Cond. / No, with the scope.

### 4.1 Axis A — security, authorization, sync (34)

| ID | Aliases | Title | Type | Sev | Pri | Status (basis) | Channels | Blocks? (reason) | Detail |
|---|---|---|---|---|---|---|---|---|---|
| SEC-001 | — | Renaming bootstrap admin → host re-creates `admin`/`admin` | Defect | High | P0 | C (code) | L, PG | **Yes** — see §3 | [A:94](<axis-A-security-sync/FINDINGS-A.md#L94>) |
| SEC-002 | — | API session ignores `force_password_change` | Defect | High | P0 | C (code) | L, PG | **Yes** — see §3 | [A:153](<axis-A-security-sync/FINDINGS-A.md#L153>) |
| SEC-003 | — | Device tokens: 30-day TTL, no revocation, no active/locked check | Defect | Medium | P1 | C (code) | L, PG, AND (warehouse) | No — pre-existing, needs a device bearer. **W0 gate** for the warehouse app | [A:186](<axis-A-security-sync/FINDINGS-A.md#L186>) |
| SEC-004 | — | Clients mint predictable temp password `<username>123` | Defect | High | P1 | C (code) | L | No — pre-existing, documented; P1 before scale-out | [A:211](<axis-A-security-sync/FINDINGS-A.md#L211>) |
| SEC-005 | — | Upgraded installs keep the derivable legacy SQLCipher key | Design gap | Medium | P1 | C (code) | W, L | No — owner rule "no automatic migration" | [A:244](<axis-A-security-sync/FINDINGS-A.md#L244>) |
| SEC-006 | — | Legacy shared LAN bearer enabled 30 days on every new server install | Defect | Medium | P2 | C (code) | L, PG | No | [A:266](<axis-A-security-sync/FINDINGS-A.md#L266>) |
| SEC-007 | — | LAN cleartext by default; unpinned TLS accepts any cert | Design | Medium | P2 | C (code) | L, PG | No — trusted-LAN assumption must be documented (Q3) | [A:291](<axis-A-security-sync/FINDINGS-A.md#L291>) |
| SEC-008 | — | Tokenless reads of parties/accounts/users; `GET /api/parties` unscoped | Defect | Medium | P1 | C (code) | L, PG, AND | No. **W0 gate** for the warehouse app | [A:310](<axis-A-security-sync/FINDINGS-A.md#L310>) |
| SEC-009 | — | Lockout not persisted; override dialog has no attempt limit | Defect | Medium | P2 | C (code) | W, L, PG | No | [A:329](<axis-A-security-sync/FINDINGS-A.md#L329>) |
| SEC-010 | — | Argon2id m=4 MiB t=3 below OWASP | Improvement | Low | P2 | C (code) | all | No | [A:350](<axis-A-security-sync/FINDINGS-A.md#L350>) |
| SEC-011 | — | Boot heal resets admin to `admin` without force-change | Defect | Low | P2 | C (code) | W, L, PG | No | [A:364](<axis-A-security-sync/FINDINGS-A.md#L364>) |
| SEC-012 | — | Untracked operational log (usernames, shift cash) in a repo folder | Hygiene | Low | P1 | C (code: file scan) | REPO | No, provided it is not committed | [A:378](<axis-A-security-sync/FINDINGS-A.md#L378>) |
| SEC-013 | — | Gitleaks CI job advisory; no local history scan | Improvement | Low | P3 | C (code) | REPO | No | [A:394](<axis-A-security-sync/FINDINGS-A.md#L394>) |
| SEC-014 | — | Cloud server plain HTTP; production TLS/deployment undefined | Missing req. | Info | P2 | C (code) | CLOUD | No for desktop; **Yes before any cloud production use** | [A:404](<axis-A-security-sync/FINDINGS-A.md#L404>) |
| SEC-015 | — | Cash-drawer fallback passes printer name through `cmd /c` | Suspicion | Low | P3 | S (code) | W, L | No | [A:416](<axis-A-security-sync/FINDINGS-A.md#L416>) |
| SEC-016 | — | xlsx/zip decoding has no size/entry limits | Improvement | Low | P3 | C (code) | W, L | No | [A:428](<axis-A-security-sync/FINDINGS-A.md#L428>) |
| SEC-017 | "QR long-lived key" (prior) | Admin QR carries the **public** key (prior claim refuted); no rotation path | Improvement | Info | P3 | C (code) | AND, CLOUD | No | [A:440](<axis-A-security-sync/FINDINGS-A.md#L440>) |
| AUTHZ-001 | — | Conditional grants self-approvable in manager override | Defect | High | P0 | C (code) | W, L, PG | **Yes** — see §3 | [A:464](<axis-A-security-sync/FINDINGS-A.md#L464>) |
| AUTHZ-002 | B-1 | Sales masking bypassed by "View details" | Defect | High | P0 | C (code) | W, L, PG | **Yes** — see §3 | [A:502](<axis-A-security-sync/FINDINGS-A.md#L502>) |
| AUTHZ-003 | B-2, **RPT-006** | Masking/gating bypass: statements, exports, import, picker | Defect | High | P0 | C (code) | W, L, PG | **Yes** — see §3 | [A:524](<axis-A-security-sync/FINDINGS-A.md#L524>), [B:158](<axis-B-data-accounting/FINDINGS-B.md#L158>) |
| AUTHZ-004 | — | `sales_view` now reveals amounts that `sales_amounts_view` hid (regression `d2272da0`) | Regression | Medium | P1 | C (code + diff) | W, L, PG | No — owner decision (Q5); release note if kept | [A:561](<axis-A-security-sync/FINDINGS-A.md#L561>) |
| AUTHZ-005 | — | Host API treats conditional grants as full grants | Defect | Medium | P1 | C (code) | L, PG | No | [A:580](<axis-A-security-sync/FINDINGS-A.md#L580>) |
| AUTHZ-006 | — | GET read endpoints have no permission gate (device sessions) | Design gap | Medium | P2 | C (code) | L, PG | No | [A:598](<axis-A-security-sync/FINDINGS-A.md#L598>) |
| AUTHZ-007 | — | Invoice details show profit margin to every cashier | Defect | Medium | P1 | C (code + base diff) | W, L, PG | No — pre-existing; fixed with AUTHZ-002 | [A:614](<axis-A-security-sync/FINDINGS-A.md#L614>) |
| AUTHZ-008 | B-4 | Booking create/status/cancel enforced in UI only | Defect | Low | P2 | C (code) | W, L, PG | No | [A:630](<axis-A-security-sync/FINDINGS-A.md#L630>) |
| AUTHZ-009 | — | `inventory_view` reveals unit cost without `products_cost_view` | Suspicion (design) | Low | P2 | S (code) | W, L, PG | No — owner decision (Q5) | [A:642](<axis-A-security-sync/FINDINGS-A.md#L642>) |
| AUTHZ-010 | — | Local authorization is widget-level (≈10 service-layer sites). Instance added in consolidation: LAN device pairing/revoke is guarded only by a UI `system_admin` check (`linked_devices_section.dart:54-86`); `LanPairingService.issuePairingCode`/`revoke` take no actor (`lan_pairing_service.dart:93, 503`) | Info (arch.) | Info | P2 | C (code) | W, L, PG | No. The pairing instance is a W0 gate (G-6) of the warehouse plan | [A:654](<axis-A-security-sync/FINDINGS-A.md#L654>) |
| SYNC-001 | D-1 | Mixed fleet: v195 clients drop v196 reservation rows permanently | Defect | High | P0 | C (code) | L, PG | **Yes (cond.)** — see §3 | [A:670](<axis-A-security-sync/FINDINGS-A.md#L670>) |
| SYNC-002 | — | Delta-pull row failures swallowed while the watermark advances | Defect | Medium | P1 | C (code) | L, PG | No | [A:701](<axis-A-security-sync/FINDINGS-A.md#L701>) |
| SYNC-003 | D-3, **DATA-001** | Client-created reservations never pushed to host | Defect | **High** | P1 | C (code) | L, PG | **Cond.** — blocks LAN sites taking reservations on clients | [A:715](<axis-A-security-sync/FINDINGS-A.md#L715>), [B:144](<axis-B-data-accounting/FINDINGS-B.md#L144>) |
| SYNC-004 | D-4 | No host-side phone dedupe → duplicate customers | Defect | Low | P2 | C (code: grep) | L, PG | No | [A:727](<axis-A-security-sync/FINDINGS-A.md#L727>) |
| SYNC-005 | — | Non-financial push conflicts marked "synced", local change dropped | Defect | Medium | P1 | C (code) | L, PG | No | [A:737](<axis-A-security-sync/FINDINGS-A.md#L737>) |
| SYNC-006 | — | Client DB holds all scoped rows regardless of permissions | Info (design) | Info | P3 | C (code) | L, PG | No — document it | [A:754](<axis-A-security-sync/FINDINGS-A.md#L754>) |
| SYNC-007 | — | Cloud command/query relay (ADR-M2) not implemented | Missing req. | Info | P2 | C (code: grep) | AND, CLOUD | No, provided docs and marketing do not claim it | [A:764](<axis-A-security-sync/FINDINGS-A.md#L764>) |

### 4.2 Axis B — data, accounting, reports, migrations, backup (37)

| ID | Aliases | Title | Type | Sev | Pri | Status (basis) | Channels | Blocks? (reason) | Detail |
|---|---|---|---|---|---|---|---|---|---|
| RPT-001 | — | Party statement includes voided/soft-deleted rows | Defect | High | P0 | C (code) | W, L, PG | **Yes** — see §3 | [B:87](<axis-B-data-accounting/FINDINGS-B.md#L87>) |
| ACC-001 | — | Straight-line depreciation never stops at salvage/end of life | Defect | High | P1 | C (code) | W, L, PG | **Cond.** — tenants with fixed assets near end of life | [B:115](<axis-B-data-accounting/FINDINGS-B.md#L115>) |
| RPT-003 | — | `getArAgingReport` SQL fails on PostgreSQL | Defect | High | **P0 (PG)** | C (code) | PG | **Yes (PG)** — see §3 | [B:127](<axis-B-data-accounting/FINDINGS-B.md#L127>) |
| BKP-001 | — | No test or drill restores a real encrypted backup | Missing req. | High | **P0 (GA)** | C (tests) | W, L | **Yes (GA)** — see §3 | [B:173](<axis-B-data-accounting/FINDINGS-B.md#L173>) |
| DATA-003 | — | Party XLSX re-import overwrites `parties.balance` with no JE | Defect | High | P1 | C (code) | W, L, PG | No — detectable and repairable at startup | [B:186](<axis-B-data-accounting/FINDINGS-B.md#L186>) |
| MIG-001 | — | No forward-compat guard: a newer DB/backup opens and is re-stamped v196 | Defect | High | P1 | C (code + drift source) | W, L | No — required before any rollback guidance | [B:202](<axis-B-data-accounting/FINDINGS-B.md#L202>) |
| ACC-002 | — | Depreciation row/card advance without JE; failures swallowed | Defect | Medium | P2 | C (code) | W, L, PG | No | [B:218](<axis-B-data-accounting/FINDINGS-B.md#L218>) |
| ACC-004 | C-6 (prior) | Booking deposit can land on party AR or revenue `4299`; guest deposits | Defect | Medium | P2 | C (code) | W, L, PG | No | [B:229](<axis-B-data-accounting/FINDINGS-B.md#L229>) |
| ACC-005 | — | FX revaluation entry and reversal not atomic | Defect | Medium | P2 | C (code) | W, L, PG | No | [B:245](<axis-B-data-accounting/FINDINGS-B.md#L245>) |
| ACC-006 | — | Cash flow: manual JEs in operating, labelled customer/supplier | Defect | Medium | P2 | C (code) | W, L, PG | No | [B:255](<axis-B-data-accounting/FINDINGS-B.md#L255>) |
| RPT-002 | — | Aged AR/AP "as of" uses current `paid`; returned purchases aged | Defect | Medium | P2 | C (code) | W, L, PG | No | [B:263](<axis-B-data-accounting/FINDINGS-B.md#L263>) |
| RPT-004 | — | Tax report (GL), hierarchical TB, posting recon ignore `is_deleted` | Defect | Medium | P2 | C (code) | W, L, PG | No | [B:277](<axis-B-data-accounting/FINDINGS-B.md#L277>) |
| RPT-005 | — | Sales summary: inclusive next-midnight bound, unfiltered `paid` | Defect | Medium | P2 | C (code) | W, L, PG | No | [B:288](<axis-B-data-accounting/FINDINGS-B.md#L288>) |
| RPT-007 | — | Budget actuals include drafts; secondary aggregates miss filters | Defect | Medium | P2 | C (code) | W, L, PG | No | [B:298](<axis-B-data-accounting/FINDINGS-B.md#L298>) |
| DATA-002 | — | Phone normalisation drops country code → cross-country merges | Owner rule risk | Medium | P2 | C (code) | W, L, PG | No — owner decision (Q7) | [B:310](<axis-B-data-accounting/FINDINGS-B.md#L310>) |
| DATA-005 | — | Sales JE posted after the invoice transaction commits | Design risk | Medium | P2 | C (code) | W, L, PG | No | [B:318](<axis-B-data-accounting/FINDINGS-B.md#L318>) |
| DATA-006 | — | Purchase XLSX import does not normalise/validate tax rate | Defect | Medium | P2 | C (code) | W, L, PG | No | [B:326](<axis-B-data-accounting/FINDINGS-B.md#L326>) |
| MIG-002 | — | Migrations not transactional (the comment says they are) | Defect | Medium | P2 | C (code + drift source) | W, L | No | [B:333](<axis-B-data-accounting/FINDINGS-B.md#L333>) |
| MIG-003 | — | `_safeMigrate` swallows "no such column" | Suspicion | Medium | P2 | S (code) | W, L | No | [B:342](<axis-B-data-accounting/FINDINGS-B.md#L342>) |
| MIG-004 | REL-003 (backup part), A-7 (prior, corrected) | Pre-migration backup best-effort, un-checkpointed, rotated out | Defect | Medium | P2 | C (code) | W, L | No | [B:348](<axis-B-data-accounting/FINDINGS-B.md#L348>) |
| MIG-006 | — | PG upgrade path untested; legacy unique indexes may not exist | Suspicion | Medium | P2 | S (code) | PG | No | [B:356](<axis-B-data-accounting/FINDINGS-B.md#L356>) |
| MIG-007 | — | No upgrade test from a real old encrypted DB with data | Missing req. | Medium | P2 | C (tests) | W, L | No | [B:364](<axis-B-data-accounting/FINDINGS-B.md#L364>) |
| BKP-002 | — | Restore validates key + `quick_check` only; no schema-version check | Defect | Medium | P2 | C (code) | W, L | No | [B:372](<axis-B-data-accounting/FINDINGS-B.md#L372>) |
| BKP-003 | — | Backups local-only; checkpoint failure → incomplete backup | Defect | Medium | P2 | C (code) | W, L | No | [B:378](<axis-B-data-accounting/FINDINGS-B.md#L378>) |
| BKP-004 | — | PostgreSQL mode has no in-app backup | Missing req. | Medium | P2 | C (code) | PG | No — but the PG release needs a documented operator backup (condition in RELEASE_READINESS) | [B:387](<axis-B-data-accounting/FINDINGS-B.md#L387>) |
| DATA-004 | — | Missing DB-level constraints on ledger/catalogue tables | Improvement | Low | P3 | C (code) | all | No | [B:392](<axis-B-data-accounting/FINDINGS-B.md#L392>) |
| DATA-007 | — | CSV export has no formula-injection escaping | Defect | Low | P3 | C (code) | W, L, PG | No | [B:402](<axis-B-data-accounting/FINDINGS-B.md#L402>) |
| DATA-008 | — | Imported barcode not trimmed before uniqueness check | Suspicion | Low | P3 | S (code) | W, L, PG | No | [B:407](<axis-B-data-accounting/FINDINGS-B.md#L407>) |
| ACC-003 | — | Depreciation duplicate guard keys on exact date (API path) | Suspicion | Low | P3 | S (code) | L, PG | No | [B:413](<axis-B-data-accounting/FINDINGS-B.md#L413>) |
| ACC-007 | — | `getArReconciliation` compares active cards with whole AR subtree | Defect | Low | P3 | C (code) | W, L, PG | No | [B:421](<axis-B-data-accounting/FINDINGS-B.md#L421>) |
| ACC-008 | — | Generic `reverseTransaction` would skip 2nd+ reversals (no callers) | Latent defect | Low | P3 | C (code) | — | No | [B:427](<axis-B-data-accounting/FINDINGS-B.md#L427>) |
| ACC-009 | — | JE number year from `now()`; voucher period pre-check with `now()` | Defect | Low | P3 | C (code) | W, L, PG | No | [B:432](<axis-B-data-accounting/FINDINGS-B.md#L432>) |
| ACC-010 | — | Balance tolerance 0.01 regardless of currency decimals | Improvement | Low | P3 | C (code) | W, L, PG | No | [B:439](<axis-B-data-accounting/FINDINGS-B.md#L439>) |
| RPT-008 | — | Tax screen header (GL) and detail (invoices) from different sources | Improvement | Low | P3 | C (code) | W, L, PG | No | [B:444](<axis-B-data-accounting/FINDINGS-B.md#L444>) |
| RPT-009 | — | Dead audit/aging queries reference non-existent columns | Improvement | Low | P3 | C (code) | — | No | [B:449](<axis-B-data-accounting/FINDINGS-B.md#L449>) |
| MIG-005 | — | v196 backfill divergences from plan | Suspicion | Low | P3 | S (code) | W, L | No | [B:454](<axis-B-data-accounting/FINDINGS-B.md#L454>) |
| BKP-005 | — | Key sidecar beside every backup (recovery wrapper not analysed) | Suspicion | Low | P3 | S (code) | W, L | No — needs security analysis | [B:464](<axis-B-data-accounting/FINDINGS-B.md#L464>) |

### 4.3 Axis C — product identity, UX, architecture, distribution, dependencies (42)

| ID | Aliases | Title | Type | Sev | Pri | Status (basis) | Channels | Blocks? (reason) | Detail |
|---|---|---|---|---|---|---|---|---|---|
| BRAND-001 | — | UralCash logo shipped in every PicPos build/installer | Defect | High | P0 | C (art) | W, L, PG | **Yes** — see §3 | [C:88](<axis-C-product-ux-release/FINDINGS-C.md#L88>) |
| BRAND-002 | — | Shipped i18n catalogs contain UralCash strings; `catalog_ar.json` unused | Defect | High | P0 | C (art) | W, L, PG | **Yes** — see §3 | [C:104](<axis-C-product-ux-release/FINDINGS-C.md#L104>) |
| BRAND-003 | **REL-001** | CI release job ships UralCash-branded, non-SQLCipher build | Defect | Critical | P0 | C (code) | CI | **Yes** — see §3 | [C:122](<axis-C-product-ux-release/FINDINGS-C.md#L122>), [C:599](<axis-C-product-ux-release/FINDINGS-C.md#L599>) |
| BRAND-004 | — | Every brand default is UralCash (Dart, CMake, Runner.rc, main.cpp) | Defect | High | P0 | C (code) | W, L, PG, CI | **Yes** — see §3 | [C:140](<axis-C-product-ux-release/FINDINGS-C.md#L140>) |
| BRAND-005 | — | UralCash salts, keys, env-var names compiled into the binary | Defect | Medium | P1 | C (art) | W, L, PG | No (not user-visible); needed for owner decision 1. Values must stay byte-identical | [C:156](<axis-C-product-ux-release/FINDINGS-C.md#L156>) |
| BRAND-006 | — | Dart package `picpos_erp` + description "UralCash ERP" | Improvement | Medium | P2 | C (code) | REPO | No | [C:182](<axis-C-product-ux-release/FINDINGS-C.md#L182>) |
| BRAND-007 | — | UralCash installer branch, art, build script in PicPos tree | Defect | Medium | P1 | C (code) | REPO, W | No. Owner decision 1: **remove** | [C:200](<axis-C-product-ux-release/FINDINGS-C.md#L200>) |
| BRAND-008 | — | UralCash icons in `windows/runner/resources` and repo root | Defect | Medium | P1 | C (hash) | REPO, W | No | [C:217](<axis-C-product-ux-release/FINDINGS-C.md#L217>) |
| BRAND-009 | — | UralCash-only code paths in `lib/` (incl. legacy setup wizard title) | Defect | Medium | P1 | C (code) | REPO | No. Owner decision 1: **remove** | [C:226](<axis-C-product-ux-release/FINDINGS-C.md#L226>) |
| BRAND-010 | — | Non-shipped repo content still UralCash (customer PG guide: P1) | Improvement | Low | P2 | C (code) | REPO | No | [C:250](<axis-C-product-ux-release/FINDINGS-C.md#L250>) |
| BRAND-011 | — | Pre-split (UralCash-named) installs not migrated | Open question | Info | P1 | C (code) | W, L | No — owner question Q1 | [C:266](<axis-C-product-ux-release/FINDINGS-C.md#L266>) |
| BRAND-012 | — | Brand guards do not scan the artifact; CI skips PicPos guard | Req. gap | High | P0 | C (code) | W, L, PG, CI | **Yes** — see §3 | [C:280](<axis-C-product-ux-release/FINDINGS-C.md#L280>) |
| UX-001 | — | Wizard currency chips silently become JOD; choice is final | Defect | High | P0 | C (code) | W, L, PG | **Yes** — see §3 | [C:323](<axis-C-product-ux-release/FINDINGS-C.md#L323>) |
| UX-002 | G1b-#2 | Currency literals hardcoded in 15+ screens | Defect | High | P0 (EGP) / P1 | C (code) | W, L, PG | **Yes for EGP installs** — see §3 | [C:341](<axis-C-product-ux-release/FINDINGS-C.md#L341>) |
| UX-003 | — | `NumberUtils.formatAmount` freezes symbol/decimals on first use | Defect | Medium | P1 | C (code) | W, L, PG | No | [C:374](<axis-C-product-ux-release/FINDINGS-C.md#L374>) |
| UX-004 | — | Irreversible currency preselected (EGP + 14%) | Improvement | Medium | P1 | C (code + screenshot) | W, L, PG | No | [C:381](<axis-C-product-ux-release/FINDINGS-C.md#L381>) |
| UX-005 | G2-#1 | Company name entered in wizard not persisted | Suspicion | Medium | P1 | S (prior GUI; tool limitation likely) | W, L, PG | No — verify | [C:391](<axis-C-product-ux-release/FINDINGS-C.md#L391>) |
| UX-006 | — | English "Dashboard" label in Arabic UI | Defect | Low | P2 | C (code + screenshot) | W, L, PG | No | [C:396](<axis-C-product-ux-release/FINDINGS-C.md#L396>) |
| UX-007 | — | Overlapping sidebar destinations; duplicated HR header | Improvement | Medium | P2 | C (code, medium confidence) | W, L, PG | No | [C:407](<axis-C-product-ux-release/FINDINGS-C.md#L407>) |
| UX-008 | — | "Clear PLU" without confirmation | Defect | Low | P2 | C (code, medium confidence) | W, L, PG | No | [C:420](<axis-C-product-ux-release/FINDINGS-C.md#L420>) |
| UX-009 | — | Hardcoded `TextDirection.rtl` breaks English layout | Defect | Low | P2 | C (code) | W, L, PG | No | [C:427](<axis-C-product-ux-release/FINDINGS-C.md#L427>) |
| UX-010 | — | First-run redesign plan conflicts with owner decisions/code | Req. gap (plan) | Medium | P0 (plan, before Specs) | C (plan) | plan | No. **Plan reconciled 2026-10-23** in [the first-run plan](<../../plans/2026-10-23-first-run-setup-redesign-plan.md>); closure needs owner review | [C:436](<axis-C-product-ux-release/FINDINGS-C.md#L436>) |
| UX-011 | — | Warehouse-app plan prerequisites missing | Req. gap (plan) | Low | P1 | C (plan); item (2) corrected by SEC-017 | plan, AND | No. **Plan reconciled 2026-10-23** in [the warehouse plan](<../../plans/2026-10-23-warehouse-app-plan.md>) | [C:477](<axis-C-product-ux-release/FINDINGS-C.md#L477>) |
| ARCH-001 | — | 439 `catch (_)` / 209 empty catches incl. money and sync paths; `sales_return_provider.dart:171` fail-open scope | Defect | Medium | P1 | C (code: counts + sample) | all | No | [C:499](<axis-C-product-ux-release/FINDINGS-C.md#L499>) |
| ARCH-002 | — | Tax/totals/rounding/WAC rules duplicated | Defect risk | Medium | P2 | S (no numeric divergence shown) | all | No | [C:519](<axis-C-product-ux-release/FINDINGS-C.md#L519>) |
| ARCH-003 | — | Static caches not invalidated by sync/settings change | Defect risk | Medium | P2 | S (code) | L, PG | No | [C:536](<axis-C-product-ux-release/FINDINGS-C.md#L536>) |
| ARCH-004 | — | 2 analyzer infos at HEAD; CI analyze possibly red | Defect / suspicion | Low | P1 | S for the CI part (the 2 infos are confirmed by log) | CI | No | [C:546](<axis-C-product-ux-release/FINDINGS-C.md#L546>) |
| ARCH-005 | — | Large share of tests are source-text scans | Improvement | Medium | P2 | C (sample) | REPO | No | [C:557](<axis-C-product-ux-release/FINDINGS-C.md#L557>) |
| ARCH-006 | — | CI does not build APKs/installer, run brand guard, analyze `test/`, 9 packages, `integration_pg` | Req. gap | High | P1 | C (code) | CI, AND | No (BRAND-003 is the blocking part) | [C:567](<axis-C-product-ux-release/FINDINGS-C.md#L567>) |
| ARCH-007 | — | God-file ratchet in place; mobile/server not covered | Info | Low | P3 | C (code) | REPO | No | [C:588](<axis-C-product-ux-release/FINDINGS-C.md#L588>) |
| REL-002 | — | Installer/exe/DLLs unsigned | Req. gap | High | P0 (public) | C (tool) | W, L, PG | **Yes (public)** — see §3 | [C:608](<axis-C-product-ux-release/FINDINGS-C.md#L608>) |
| REL-003 | (overlaps MIG-001, MIG-004, SYNC-001) | No updater; installer takes no backup; fleet version not enforced | Req. gap | Medium | P1 | C (code) | W, L, PG | No | [C:620](<axis-C-product-ux-release/FINDINGS-C.md#L620>) |
| REL-004 | — | Android Van always debug-signed; POS falls back to debug | Defect | High | P0 (AND) | C (code) | AND | **Yes (Van/POS APKs)** — see §3 | [C:638](<axis-C-product-ux-release/FINDINGS-C.md#L638>) |
| REL-005 | — | Trial watermark depends on whether Settings was opened | Defect | High | P0 | **S** (code) | W, L, PG | **Yes until reproduced** — see §3 | [C:654](<axis-C-product-ux-release/FINDINGS-C.md#L654>) |
| REL-006 | — | Activation mechanism as implemented (machine-bound Ed25519, in Settings) | Info | Low | P2 | C (code) | W, L, PG | No | [C:671](<axis-C-product-ux-release/FINDINGS-C.md#L671>) |
| REL-007 | — | Installer info text stale; PG downloaded at install time | Defect | Low | P2 | C (code) | W, PG | No | [C:689](<axis-C-product-ux-release/FINDINGS-C.md#L689>) |
| REL-008 | — | Version identity inconsistent (README, AppConfig, mobile `0.1.0+1`) | Defect | Low | P2 | C (code) | all | No | [C:696](<axis-C-product-ux-release/FINDINGS-C.md#L696>) |
| REL-009 | — | Activation private key in working tree (untracked, ignored) | Hygiene | Low | P1 | C (git) | REPO | No | [C:705](<axis-C-product-ux-release/FINDINGS-C.md#L705>) |
| DEP-001 | — | `sqlcipher_flutter_libs` EOL upstream (`0.7.0+eol`) | Req. gap | Medium | P1 | C (tool) | W, L | No | [C:717](<axis-C-product-ux-release/FINDINGS-C.md#L717>) |
| DEP-002 | — | Major versions behind; discontinued transitives | Improvement | Low | P2 | C (tool) | all | No | [C:724](<axis-C-product-ux-release/FINDINGS-C.md#L724>) |
| DEP-003 | — | Licences: no GPL/LGPL/AGPL in root lockfile | Info | Info | — | C (tool) | W | No | [C:734](<axis-C-product-ux-release/FINDINGS-C.md#L734>) |
| DEP-004 | — | Unused dependencies and dead code | Improvement | Low | P3 | C (code) | REPO | No | [C:741](<axis-C-product-ux-release/FINDINGS-C.md#L741>) |

## 5. Prior-audit items: status at HEAD

| Prior ID (source) | Status at HEAD | Canonical finding |
|---|---|---|
| B-1 (Q-review) | Still open | AUTHZ-002 |
| B-2 | Still open | AUTHZ-003 |
| B-3 | Fixed in UI; undermined | AUTHZ-001, AUTHZ-005 |
| B-4 | Still open | AUTHZ-008 |
| D-1 | Partly fixed | SYNC-001 |
| D-2 | Fixed | — |
| D-3 | Still open | SYNC-003 |
| D-4 | Still open | SYNC-004 |
| C-1, C-2 (approve JE; CF/IS/BS `is_deleted`) | Fixed | — |
| C-6 (booking deposit) | Still open | ACC-004 |
| A-1 (v196 backfill retry) | Fixed | — |
| A-7 ("no pre-upgrade backup") | Incorrect; backup exists but is best-effort | MIG-004 |
| "Admin QR long-lived key" (FINAL-QA-VERDICT:43) | Refuted | SEC-017 |
| G1b-#2 (report cards `ج.م`) | Fixed before HEAD; other sites open | UX-002 |
| G1b-#1 (import: 353 errors with a green toast) | Reported fixed in FINAL-QA-VERDICT ("re-import of the same product file"); not re-verified by this audit | — (verify in G-round re-run) |
| G2-#1 (Arabic company name) | Suspicion | UX-005 |
