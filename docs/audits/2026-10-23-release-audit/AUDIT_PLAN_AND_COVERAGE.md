# AUDIT_PLAN_AND_COVERAGE

## 1. Plan: axes, scope, method

The audit was split into three independent axes, each run by a separate read-only worker on the same pinned version (`d69be1ea`). A coordinator then consolidated the results (this folder). Brief §11 asked for specialised helpers: the three axis workers were those helpers, and axes A and C also used read-only sub-readers, whose claims were spot-checked (see each COVERAGE file).

| Axis | Scope (brief section) | Method | Tools actually used | Success criterion | Output |
|---|---|---|---|---|---|
| **A — security, authentication, permissions, sync** | §7 security and privacy, §5 control timing, §9 sync | Code reading at HEAD, `git diff` against the base, dependency advisory lookup | git, grep, PowerShell, OSV / GitHub Advisory pages | Every control claimed by the candidate is enforced at its execution point and cannot be bypassed by another path | [axis-A-security-sync/](<axis-A-security-sync/FINDINGS-A.md>) |
| **B — data integrity, accounting, reports, migrations, backup** | §8 database, §4 business rules, §10 accounting/report correctness | Code reading, Drift library source reading, test inventory | git, grep, PowerShell, local pub cache | Reports agree with each other and with the GL; migrations and restore are safe and proven | [axis-B-data-accounting/](<axis-B-data-accounting/FINDINGS-B.md>) |
| **C — product identity, UX, architecture, distribution, dependencies** | §2 baseline, §5 UX, §6 code and architecture, §10 distribution, the owner's PicPos-only requirement | Code reading, artifact inspection (byte scan, hashes, images), plan review | git, grep, PowerShell, `Get-AuthenticodeSignature`, `read_image`, `dart pub outdated` (once) | A shipped artifact contains only PicPos identity; the first-run journey gives no irreversible wrong result; the release pipeline is reproducible | [axis-C-product-ux-release/](<axis-C-product-ux-release/FINDINGS-C.md>) |
| **Consolidation** | §12–§16 | De-duplication, normalisation, readiness decision, roadmap, plan reconciliation | Reading; mtime check of the test-log tree | One register; one decision per channel | This folder |

**Constraint that shaped the plan:** no auditor was allowed to run `flutter`/`dart` (except one `dart pub outdated`), because a shared Flutter lock was held by other workers. The brief §3 asks to start by running existing checks; that was **not possible**. The prior green chain (2026-10-21) was used instead as secondary evidence, with its limits stated in [TEST_RESULTS.md](<TEST_RESULTS.md>).

## 2. Status legend

| Status | Meaning in this audit |
|---|---|
| PASS | The control was verified **by reading** (or artifact inspection or tool output) and no defect was found in the scope read. **It does not mean a test was executed.** Prior executed results are marked [prior]. |
| FAIL | A defect or gap was confirmed; finding ids are given. |
| BLOCKED | The check was attempted or required but could not be done; the reason is given. |
| NOT_RUN | Applicable but not executed; the reason is given. |
| NOT_APPLICABLE | Does not apply to this product. |

The axis files used "PARTIAL" (B) and "Covered" (C). Here PARTIAL is written as PASS or FAIL for the part that was read, and the unread part appears as its own NOT_RUN row.

## 3. Coverage by area (merged from COVERAGE-A/B/C)

### 3.1 Authentication, sessions, secrets (axis A)

| Check | Status | Findings / reason |
|---|---|---|
| Hashing algorithm and parameters | PASS (with improvement) | SEC-010 |
| Constant-time compares, enumeration defence | PASS | Exception: the legacy bearer `==` (SEC-006) |
| Default admin handling | FAIL | SEC-001, SEC-002, SEC-011 |
| Forced password change in the UI | PASS | `login_screen.dart:359-376` |
| Forced password change on the API | FAIL | SEC-002 |
| UI lockout | FAIL | SEC-009 (not persisted) |
| API lockout | PASS (in memory) | Reset on restart |
| Manager override | FAIL | AUTHZ-001, SEC-009 |
| Idle lock (UI) | PASS | Not executed |
| API session expiry / revocation / logout | FAIL | SEC-003 |
| Credentials distributed to clients | FAIL | SEC-004 |
| Cloud mobile/admin auth | PASS | — |
| SQLCipher key design | PASS (new installs) / FAIL (upgrades) | SEC-005 |
| Recovery envelope | PASS (design read) | Code path not executed |
| Pairing QR contents | PASS | SEC-017 (prior claim refuted) |
| Hard-coded credentials, `.env.example`, committed key material | PASS | Fake fixtures only |
| Gitleaks configuration | PASS (with improvement) | SEC-013 |
| Gitleaks history scan | BLOCKED | Tool not installed |
| Untracked sensitive files | FAIL (hygiene) | SEC-012, REL-009 |
| TLS pinning when pinned / default | PASS / FAIL | SEC-007 |
| `badCertificateCallback => true` anywhere | PASS | — |
| Android manifests (cleartext, backup) | PASS | — |
| Root `android/` manifest | NOT_APPLICABLE | Desktop target is Windows |
| Cloud server TLS | FAIL (missing requirement) | SEC-014 |
| Raw SQL interpolation | PASS (sampled) | Multi-line SQL sampled, not exhaustive |
| Network-supplied identifiers in sync | PASS | — |
| Attachments path handling | PASS | — |
| xlsx/zip handling | PASS (with improvement) | SEC-016 |
| Process execution | PASS (with suspicion) | SEC-015 |
| Deep links / `url_launcher` sweep | NOT_RUN | Time-boxed |
| PDF / print templates | NOT_RUN | Not reviewed |
| Dependency advisories (OSV, Pub) | PASS | Checked 2026-10-23 04:11 +03:00. Absence from OSV is not proof. |
| Native SQLCipher/OpenSSL CVE status | NOT_RUN | Version not determinable without a build |

### 3.2 Authorization and branch scope (axis A)

| Check | Status | Findings / reason |
|---|---|---|
| Screen-access resolver ("any permission opens the screen") | FAIL (consequences) | AUTHZ-002, AUTHZ-003 |
| Menu, allowed screens and dropdown use a single source | PASS | Not executed |
| Figure masking in lists and cards | PASS (with regression) | AUTHZ-004 |
| Figure masking in details, statements, exports | FAIL | AUTHZ-002, AUTHZ-003 (alias RPT-006), AUTHZ-007 |
| Figure masking in print output | NOT_RUN | Print templates not reviewed |
| Conditional grants: UI table gates / approval | PASS / FAIL | AUTHZ-001 |
| Conditional grants: API | FAIL | AUTHZ-005 |
| API mutation gates + grep guard | PASS | Guard test not executed by auditors; [prior] S1 green |
| API read gates | FAIL | AUTHZ-006 |
| Service/DAO-layer enforcement | FAIL (architecture) | AUTHZ-010, AUTHZ-008 |
| Bypass via search results / deep links | NOT_RUN | Desktop search-to-detail paths not traced |
| Web mirror policy | PASS (partial read) | `/webdb` internals not read |
| Branch scope: client providers | PASS | — |
| Branch scope: exports / secondary paths | FAIL | AUTHZ-003 |
| Branch scope: API | FAIL (partial) | SEC-008 |
| Branch scope: report DAOs | PASS (sampled) | — |
| Cloud cross-tenant isolation | PASS | — |
| Bootstrap-admin invariants | FAIL | SEC-001 |
| Device pairing permission | FAIL (gap, noted during consolidation; recorded under AUTHZ-010) | UI-only `system_admin` check in `linked_devices_section.dart:54-86`; `LanPairingService.issuePairingCode`/`revoke` take no actor; no dedicated code. Addressed in the warehouse plan (§B.4, W0 G-6). |

### 3.3 Sync (axis A, with B overlap)

| Check | Status | Findings / reason |
|---|---|---|
| Version / column compatibility | FAIL | SYNC-001, SYNC-002 |
| `party_id` remap for reservations and bookings (D-2) | PASS | [prior] S3 log fragment `party_fk_remap` |
| Idempotency (`global_id`, idempotency key) | PASS (read) | — |
| Conflict policy | FAIL | SYNC-005 |
| Deletes, tombstones, resurrection | PASS (read) | Resurrection scenario NOT_RUN |
| Offline replay ordering, retry, dead-letter | PASS (read) | — |
| Reservations push | FAIL | SYNC-003 (alias DATA-001) |
| Duplicate customers across devices | FAIL | SYNC-004 |
| Time skew (server-time watermark) | PASS (read) | — |
| Cloud replay protection, rate limits | PASS | — |
| Pull scope vs permissions | Info | SYNC-006 |
| Cloud relay | FAIL (missing requirement) | SYNC-007 |
| Mixed-fleet runtime test | NOT_RUN | Needs two running installs |

### 3.4 Data, accounting, reports, migrations, backup (axis B)

| Check | Status | Findings / reason |
|---|---|---|
| PK/FK/UNIQUE/CHECK | FAIL (minor) | DATA-004 |
| Soft-delete consistency in reports | FAIL | RPT-001, RPT-002, RPT-004, RPT-005, RPT-007 |
| Analytics engine data sources | PASS | Prior ratio defects (C-7) not re-verified → NOT_RUN |
| Money types and rounding | PASS (decision FA-04) / FAIL (minor) | ACC-010 |
| Dates and time zones | FAIL | RPT-005, RPT-009 |
| PG vs SQLite divergences | FAIL | RPT-003 |
| Double entry at write time | PASS | — |
| Auto-posting per module | FAIL | ACC-001, ACC-002, ACC-004, ACC-005, DATA-005 |
| Treasury transfer, purchase void, landed-cost posting bodies | NOT_RUN | Call sites only |
| Zero-cost / COGS policy | PASS | Silent COGS drop with missing accounts noted |
| Period closing / locking | PASS | ACC-009 (minor) |
| Reversal / void | PASS (latent issue) | ACC-008 |
| Tax amounts | FAIL | RPT-004, RPT-008, DATA-006 |
| E-invoice (JoFotara / ETA) payload amounts | NOT_RUN | Not reviewed |
| Deposits / advances | FAIL | ACC-004 |
| Party balance vs GL | FAIL | DATA-003, ACC-007, DATA-005 |
| Inventory vs GL | PASS | — |
| Cross-screen report consistency | FAIL | RPT-001, RPT-004, RPT-005, RPT-008 |
| Migration strategy | FAIL | MIG-002, MIG-003, MIG-004 |
| v196 backfill vs plan | FAIL (minor) | DATA-002, MIG-005 |
| Upgrade from an old DB with data | NOT_RUN | No fixture (MIG-007); owner-DB upgrade is a [prior] claim |
| Downgrade / forward compatibility | FAIL | MIG-001 |
| SQLCipher key at open | PASS | — |
| PG schema parity / `ensureSchemaDefaults` | PASS (static) / NOT_RUN (runtime) | MIG-006 |
| Failure mid-migration | FAIL | MIG-002 |
| Backup creation, checkpoint, retention | FAIL | BKP-003, MIG-004 |
| Restore path | FAIL | BKP-002 |
| Restore actually tested | FAIL (missing) | BKP-001 |
| Backup protection (key sidecar) | NOT_RUN | BKP-005 (needs security analysis) |
| PG backup | FAIL (missing) | BKP-004 |
| XLSX import | FAIL | DATA-003, DATA-006, DATA-008 |
| Export accuracy and masking | FAIL | AUTHZ-003 (alias RPT-006), DATA-007 |
| PDF report figure accuracy | NOT_RUN | — |
| Attachments | PASS | — |
| Manufacturing BOM cost roll-up | NOT_RUN | Posting accounts only |
| Payroll | PASS | — |
| Fixed assets | FAIL | ACC-001, ACC-002, ACC-003 |
| Remote backup runtime | NOT_RUN | Config test only |

### 3.5 Product identity, UX, architecture, distribution (axis C)

| Check | Status | Findings / reason |
|---|---|---|
| Brand: `lib/`, `assets/`, `windows/`, `installer/`, `packages/`, `tool(s)/`, scripts, `.github/`, root files, `web_app/`, `supabase/` | FAIL | BRAND-001 … BRAND-010 |
| Brand: mobile apps, `server/`, `docker/`, `web/` | PASS | `web/` uses the default Flutter icon (noted) |
| Brand: `docs/` (81 files), `test/` (73 files) | PASS (counted only) | Not classified one by one; not shipped |
| Brand: shipped artifact (`FlavorBuilds\PicPos`) | FAIL | BRAND-001, BRAND-002, BRAND-005 |
| Brand: installer payload | BLOCKED | Not unpacked |
| Brand: printed receipts / PDF | NOT_RUN | No runtime |
| Runtime identifiers (DB, backup, AppData, logs, AppId) | PASS | BRAND-011 open question |
| Brand guard tests | FAIL | BRAND-012 |
| First-run vs periodic setup vs daily use | FAIL | UX-001, UX-004, UX-005 (suspected), UX-010 |
| Currency correctness | FAIL | UX-001, UX-002, UX-003 |
| Navigation clarity, terminology | FAIL (partial read) | UX-006, UX-007; not clicked through |
| High-impact confirmations | FAIL (sampled 10) | UX-008 |
| RTL / Arabic | FAIL (partial) | UX-009 |
| Loading / error / empty states | NOT_RUN | Not systematically covered |
| Keyboard, focus, contrast, zoom, small screens | NOT_RUN | No instrumented run |
| Warehouse-app plan | FAIL (plan gaps) | UX-011, now reconciled |
| God-file ratchet | PASS (read) | ARCH-007; the test itself NOT_RUN |
| Duplicated business rules | FAIL (risk) | ARCH-002 |
| Swallowed exceptions | FAIL | ARCH-001 |
| Async gap / BuildContext | FAIL | ARCH-004 |
| Provider lifecycle / stale caches | FAIL (sampled) | ARCH-003 |
| Dead code / unused dependencies | FAIL (minor) | DEP-004 |
| i18n mechanism | FAIL | BRAND-002 |
| Test quality | FAIL (sampled) | ARCH-005 |
| CI content | FAIL | ARCH-006, BRAND-003 |
| Installer (AppId, upgrade, VC++, PG component) | FAIL (minor) | REL-003, REL-007; VC++ pinning PASS |
| Signing / SmartScreen | FAIL | REL-002 |
| Version pins / identity | FAIL | REL-008 |
| SQLCipher enforcement | PASS (local artifact) / FAIL (CI) | BRAND-003 (alias REL-001) |
| Android signing / manifests | FAIL / PASS | REL-004 |
| Size | PASS (measured) | Desktop 82.4 MB, installer 47.7 MB; APK size NOT_RUN |
| Licences (root lockfile) | PASS | DEP-003; mobile and server lockfiles NOT_RUN |
| Activation | FAIL | REL-005 (suspected), REL-006 (info) |
| Dependency freshness | FAIL | DEP-001, DEP-002 |

## 4. Journey coverage (brief §4)

| Journey | Reading | Automated [prior] | GUI [prior] | Runtime this audit |
|---|---|---|---|---|
| First-run setup (standalone) | Read (UX-001/004/010) | S1 widget tests | G1b PASS (partial); G2 FAIL (partial) | NOT_RUN |
| First-run setup (server / client / mirror) | Read (SEC-002, UX-010) | Some unit tests | Not exercised | NOT_RUN |
| Login, forced change, lockout | Read | S1 | G1/G1b partial | NOT_RUN |
| POS sale (cash, credit, return, void) | Read (RPT-001, DATA-005) | S2 scenarios, S3 `pos_full_sale_flow_test` | BLOCKED in all rounds | NOT_RUN |
| Purchases / suppliers | Read | S2, S3 | BLOCKED | NOT_RUN |
| Treasury vouchers | Read | S2 | BLOCKED | NOT_RUN |
| Financial reports / statements / exports | Read (RPT-*) | S2 `sc_k_trial_balance` etc. | TB opened, empty | NOT_RUN |
| Product import | Read (DATA-006/008) | [prior] idempotency test | G1b FAIL (353 errors); G2 unverifiable | NOT_RUN |
| Customers + dedupe | Read (DATA-002) | S1/S3 | G1b PASS (partial) | NOT_RUN |
| Tables / reservations / bookings | Read (SYNC-003, ACC-004, AUTHZ-008) | S1/S3 | G2 partial | NOT_RUN |
| Users, roles, permissions, masking | Read (AUTHZ-*) | S1 | BLOCKED; the masking build was never GUI-tested | NOT_RUN |
| LAN pairing and sync (host ↔ client) | Read (SEC-*, SYNC-*) | S3, S6 | Not exercised | NOT_RUN |
| Backup / restore | Read (BKP-*) | Fake-payload tests only | Not exercised | NOT_RUN |
| Upgrade / migration | Read (MIG-*) | Synthetic v195 test | Owner DB v195→v196 [prior claim] | NOT_RUN |
| Mobile apps (Van, Admin, POS) | Read (REL-004, SEC-017) | S5 E2E 48 passed | No device | NOT_RUN |
| Printing (58/80 mm) | Read (REL-005) | — | No receipt printed in any round | NOT_RUN |

## 5. What was NOT executed, and why

These items are stated plainly because they bound every conclusion in [RELEASE_READINESS.md](<RELEASE_READINESS.md>).

1. **No runtime reproduction of any finding.** Every finding is confirmed by reading, by artifact inspection or by tool output, or it is suspected. Reason: `flutter`/`dart` were prohibited for the auditors (shared lock), and no isolated running host, client or test DB was available.
2. **No clean-machine install** (fresh install, upgrade over 3.9.1, uninstall, downgrade). Reason: no clean VM. Impact: REL-002/003/007 are unchecked in practice; SmartScreen and AV behaviour are inferred.
3. **No backup → restore drill.** Reason: needs a runtime and an isolated copy of a real encrypted install. Impact: restorability is unproven (BKP-001), and the brief says a backup button is not proof.
4. **No Android device testing.** No APK was built, signed, installed or run on a phone or handheld. Reason: no flutter and no device. Impact: the AND channel's readiness rests on Gradle files and the [prior] E2E only.
5. **No test suite re-run at HEAD.** The [prior] 2026-10-21 chain is used with the equivalence limits in TEST_RESULTS §2.1.
6. **No PostgreSQL execution** of the suspected-incompatible SQL (RPT-003), and no PG upgrade from an older server schema (MIG-006).
7. **No mixed-fleet sync run** (v195 client vs v196 host).
8. **No performance or load measurement**, and no long-session stability run beyond the [prior] GUI observations.
9. **No accessibility instrumentation**: keyboard, focus, contrast, DPI and zoom.
10. **No remote or CI status check**: no fetch, no GitHub access.
11. **No installer payload unpacking** and **no Gitleaks history scan**: tools unavailable.

## 6. Recommended verification order when execution becomes possible

In risk and cost order, each item ≤ 1 day:

1. ≈ 10-minute repros of RPT-001 and REL-005; they decide whether these stay blockers.
2. Unit or widget repro tests for AUTHZ-001/002/003 and SEC-001/002.
3. Clean-VM install of `PicPos-Setup-3.9.2.277.exe` with the artifact brand scan (BRAND-012 script) on the installed folder.
4. A restore drill on a copy of a real encrypted DB.
5. A PG run of `getArAgingReport`.
6. A mixed-fleet sync on two machines.
7. An APK release build per app on a device.
