# TEST_RESULTS — what was actually executed, and with what result

**Rule:** a check is PASS or FAIL only if its command was run and its output was seen. Earlier QA work is cited as **[prior]**, with its status taken from its own logs. Everything else is **NOT_RUN**, with a reason.

**Bottom line:**
- No test suite was run during this audit, and no finding was reproduced at runtime.
- The only behavioural evidence is the prior green chain in `D:\qa\logs4` (2026-10-21) and three partial GUI rounds (2026-10-20).
- None of these exercises the scenarios behind the release blockers.

## 1. Commands executed during this audit (axes A, B, C and this consolidation)

All of these are read-only. No product file was modified by any audit author.

| # | Who | Command / method | Result |
|---|---|---|---|
| E1 | A, B, C, consolidation | `git rev-parse HEAD`, `git status --short`, `git log` | HEAD `d69be1ea` throughout. Untracked files only, until ≈ 04:35 (see §6). |
| E2 | A | `git diff --stat c5f5056c..HEAD -- lib server mobile* packages`, targeted `git diff` / `git show` | 107 files in those paths; masking-code change (AUTHZ-004) and margin widget pre-existing (AUTHZ-007) confirmed by diff. |
| E3 | A | `git ls-files` filter for key material; pattern `git grep` for private keys and tokens | No key material tracked; 4 hits, all fake fixtures or scan-pattern docs. |
| E4 | A | `Get-Command gitleaks` | Not installed → history scan NOT_RUN. |
| E5 | A | `web_fetch` OSV Pub list + GHSA-9v85-q87q-g4vg + GHSA-3hpf-ff72-j67p (2026-10-23 04:11 +03:00) | No listed Pub advisory affects the locked versions. Native SQLCipher/OpenSSL versions not determined. |
| E6 | A | Classification scan of `picpos_login_log_server.txt` (counts only, values redacted) | Usernames and shift amounts; no hashes, tokens or IPs → SEC-012. |
| E7 | B | Read drift 2.32.1 package source (`engines.dart`, `db_base.dart`, `migration.dart`) | Confirms MIG-001 and MIG-002. |
| E8 | B | File and test counts | 167 tables, 134 DAOs, 12 epoch files; test files: unit 691, integration 160, integration_pg 26, scenarios 14, structural 117, widget 264, data 33. |
| E9 | C | Artifact brand scan of `FlavorBuilds\PicPos` (Latin-1 + UTF-16LE) — T-C-03 | **FAIL**: `app.so` has `UralCash-ERP-Integrity-v1`, `UralCash-API-v1`, 1,503 `package:picpos_erp/` URIs and `ural_*` storage keys; `en.json` / `catalog_ar.json` contain "Ural Technology", "URAL-ERP", "Ural Cash" → BRAND-002, BRAND-005. |
| E10 | C | SHA-256 + visual check of shipped images — T-C-04 | **FAIL**: `flutter_assets\logo.PNG` = the UralCash company logo → BRAND-001. |
| E11 | C | `(Get-Item PicPos.exe).VersionInfo` — T-C-05 | **PASS**: CompanyName / ProductName / FileDescription `PicPos`, FileVersion `3.9.2+277`. |
| E12 | C | `Get-AuthenticodeSignature` (setup exe, `PicPos.exe`, `sqlite3.dll`) — T-C-06 | **FAIL** (public-release requirement): all NotSigned → REL-002. |
| E13 | C | Byte search for `sqlcipher` in the artifact `sqlite3.dll` — T-C-07 | **PASS**: 162 occurrences (local artifact only; the CI artifact is not checked). |
| E14 | C | Byte search of the installer — T-C-08 | Inconclusive: LZMA payload not unpacked. |
| E15 | C | `dart pub outdated --no-dev-dependencies` (once; exit 0, 23 s) — T-C-14 | `sqlcipher_flutter_libs` latest `0.7.0+eol`; 30 direct deps behind → DEP-001, DEP-002. Lockfiles unchanged afterwards. |
| E16 | C | Licence classification of 198 hosted packages — T-C-13 | **PASS**: BSD 127, MIT 51, Apache 18, MPL-2.0 2 (Linux-only, transitive); no GPL/LGPL/AGPL. |
| E17 | consolidation | `Get-Content D:\qa\logs4\_summary.txt`, `S0_analyze.log`; `Select-String` over `S5_e2e.log` | See §2. |
| E18 | consolidation | Tree-equivalence check (mtime of every changed and every tracked file vs the run start) | See §2.1. |
| E19 | consolidation | `Get-Item` on `D:\qa\PicPos\PicPos.exe` and `FlavorBuilds\PicPos\PicPos.exe`; count of `lib/` files newer than the QA GUI build | See §3. |

## 2. Prior automated chain — `D:\qa\logs4` (run 2026-10-21 01:45:59 → 02:53:41, local time) [prior]

| Stage | What | Exit | Logged result | Duration | Status |
|---|---|---|---|---|---|
| S0 | `analyze` (log header: `Analyzing lib, test...`) | 0 | `2 issues found` — both **info** `use_build_context_synchronously` (`purchase_returns_picpos_logic.dart:48`, `sales_returns_picpos_logic.dart:84`). "Clean" means no errors or warnings, not zero issues (ARCH-004). | 0.3 min | PASS [prior] with 2 infos |
| S1 | Main suite (unit / data / structural / services / domain / widget / static / core / presentation / security) | 0 | `+10018 ~19: All other tests passed!` | 25.8 min | PASS [prior] |
| S2 | `test/scenarios` | 0 | `+61 ~1` | 0.6 min | PASS [prior] |
| S3 | `test/integration` (concurrency 1) | 0 | `+1018 ~27` | 16.3 min | PASS [prior] |
| S4 | Brand guard `brand_picpos_test` (`APP_BRAND=picpos`) | 0 | `+13: All tests passed!` | 0.1 min | PASS [prior]. It does not scan the artifact (BRAND-012). |
| S5 | E2E `tool/run_e2e.ps1` (PG on port 55432) | 0 | Final table: server 17, packages 8, mobile 6, mobile_admin 8 (+1 skip), mobile_pos 2 (+6 skip), root 5, web 2 → **`نجح 48 · تخطّى 7 · فشل 0`**. The `+2` in `_summary.txt` is only the last suite's line. | 1.8 min | PASS [prior] |
| S6 | `integration_pg` (postgres:16 container) | 0 | `+92: All tests passed!` | 22.8 min | PASS [prior] |

Skipped tests (19 + 1 + 27 + 7) were not inventoried.

### 2.1 Does that run correspond to HEAD `d69be1ea`?

**Facts**
- The logs carry no commit SHA or tree hash.
- The last commit before the run is `c5f5056c` (2026-10-17). The four candidate commits were created on 2026-10-23 03:08, after the run. So the run tested an **uncommitted working tree**.
- A `git diff --stat` "between the log time and HEAD" is therefore not possible in git terms: there is no commit at the log time.
- The closest git statement: `git diff --shortstat c5f5056c..HEAD` = **156 files changed, +10,090 / −1,064**. That is the content which existed as uncommitted changes when the run happened.

**Timestamp check (run during this consolidation)**
- All 156 files changed in `c5f5056c..HEAD` have a last-write time **before** the run start (2026-10-21 01:45:59).
- At the first check, every tracked file had a last-write time before the run start. The newest tracked `lib/`/`test/` file was `lib/presentation/fixed_assets_picpos/screens/fixed_assets_picpos_screen.dart` at 2026-10-21 01:45:20, 39 seconds before S0 started.
- The 9 tracked files with non-ASCII paths were re-checked with `core.quotepath=off`; all are before the run start.
- (Later, at 04:35–04:39 on 2026-10-23, another session modified 14 tracked files; see §6. Those edits post-date HEAD and do not affect this comparison.)

**Conclusion:** the tracked content at HEAD is, with high likelihood, the content the 2026-10-21 chain ran on. Committing does not change file contents or timestamps, so the four commits were made without code change after the run.

**Limits**
- Timestamps can be preserved or reset by tools; this is circumstantial evidence, not a content hash.
- Untracked files that existed during the run (for example temporary tests) and were later deleted cannot be detected.
- Build outputs (`.dart_tool`, generated files) were not compared.
- FINAL-QA-VERDICT (2026-10-20) quotes **10009** for the main suite. The 2026-10-21 log says **10018**, so the tree still changed between the verdict and this log run (the masking work, see §3).

### 2.2 What this chain does **not** prove

From TEST-EVIDENCE-A/B/C:
- No test covers the scenarios of AUTHZ-001/002/003, SEC-001/002/003/004, SYNC-001/003, RPT-001, ACC-001, MIG-001, BKP-001 or UX-001. These are untested behaviours, not test failures.
- A large share of the 10,018 are source-text scans (ARCH-005). The brand guards were green while the logo and catalog leaked (BRAND-012).
- No PG test covers `getArAgingReport` (RPT-003). No restore test opens a real SQLCipher backup (BKP-001).

## 3. Prior GUI QA rounds — `D:\qa\reports` [prior]

**Build used**
- `D:\qa\PicPos\PicPos.exe`, written 2026-10-20 16:18:06, FileVersion `3.9.2+277`. G1b recorded the visible version as 3.9.1, so it may have run an earlier copy.
- **23 tracked `lib/` files were modified after that build**, between 2026-10-20 23:11 and 2026-10-21 01:45. Examples: `financial_figures_access.dart`, `any_permission_masked_text.dart`, `sales_invoices_table.dart`, `parties_picpos_screen.dart`. This is the figure-masking work of commit `d2272da0`.
- **So no GUI round exercised figure masking, and none ran on the HEAD build** (`FlavorBuilds\PicPos`, 2026-10-23 03:14).

**Tooling limits (reported by the rounds themselves)**
- UI Automation exposes only one `FLUTTERVIEW` pane; input was coordinate clicks and SendKeys.
- G1 saw UI and data changes not caused by its inputs (another actor on the desktop).
- G2 could not type Arabic into fields.

| Round | When | Scenario results (from the report) | Usable evidence |
|---|---|---|---|
| [G1](<D:/qa/reports/G1.md>) | 2026-10-20 13:31–13:36 | Smoke PASS (partial); wizard, navigation, import, parties, purchases, sales, vouchers, reports BLOCKED (input isolation lost). | Startup and login logs show `COMMIT-OK`, `RECONCILE-OK`; inconsistent admin-password diagnostics (needs review, not a defect). |
| [G1b](<D:/qa/reports/G1b.md>) | 2026-10-20 13:40–14:55 | Wizard PASS (partial: standalone, JOD, VAT 16%). Navigation sweep partial (≈ 23 screens opened, no overflow seen). Product import **FAIL** (`0 new, 1 update, 353 errors`, green toast). Customer create + duplicate prompt PASS (partial). Purchases, sales, vouchers, tables, users BLOCKED. Stability: no crash, ≈ 281–312 MiB. | Screenshots `D:\qa\shots\G1b\*`. Report cards showed `ج.م` on a JOD install (later fixed, G1b-#2 → UX-002). Cost-field float artefact (fixed per FINAL-QA-VERDICT). |
| [G2](<D:/qa/reports/G2.md>) | 2026-10-20 ≈ 17:00 | Wizard FAIL (partial): company name stayed `Test Company` (UX-005, probably the tool). Import BLOCKED/FAIL (partial, no verifiable result). Tables: section created, "add table" visible, no standalone back button in the hall designer (needs review). Sales, purchases, treasury, users BLOCKED. Stability: no crash. | Screenshots `D:\qa\shots\G2\*` (named in the report). |

**Claims in [FINAL-QA-VERDICT](<D:/qa/reports/FINAL-QA-VERDICT.md>) that this audit did not re-verify**
- Release build with SQLCipher OK. The artifact does contain SQLCipher (E13).
- Owner's real DB upgraded v195 → v196 with `failedGroups=0`, `RECONCILE-OK`.
- Product re-import idempotency fixed.

These remain [prior] claims.

## 4. Check status: NOT_RUN and BLOCKED, with reasons

| Check | Status | Reason |
|---|---|---|
| Any unit/widget/integration/PG/E2E suite at HEAD | NOT_RUN | Audit authors were forbidden to run `flutter`/`dart` (shared Flutter lock with other workers); the consolidation scope also excluded it. |
| Runtime reproduction of **any** finding, including all P0 blockers | NOT_RUN | Same reason; no running host, client or isolated test DB was available to the auditors. Every repro step in FINDINGS is proposed only. |
| REL-005 watermark repro (fresh launch → print preview) | NOT_RUN | Needs an app launch; this is the finding's blocking condition. |
| RPT-001 void → statement repro | NOT_RUN | Needs a test DB; ≈ 10-minute repro recommended before fixing. |
| Clean-machine install, upgrade-over-previous, uninstall, downgrade | NOT_RUN | Needs a clean VM (T-C-22, T-C-24). |
| Backup → restore drill on a real encrypted DB | NOT_RUN | Needs a runtime and an isolated copy; BKP-001 records that none exists in the test suite either. |
| Real old-DB upgrade fixture (N-2) | NOT_RUN | No fixture exists (MIG-007); the owner-DB upgrade is a [prior] claim. |
| Mixed-fleet sync against a real v195 client / v196 host | NOT_RUN | Needs two running installs (also not done by prior QA). |
| PG execution of `getArAgingReport` | NOT_RUN | Needs a PG run. |
| Android: APK build, signing verification, install and run on a physical device | NOT_RUN | Needs flutter and a device; signing was assessed from Gradle files only (REL-004). |
| Installer payload brand scan | BLOCKED | No unpacker (innounp) available; presence inferred from `[Files]`. |
| Gitleaks full-history scan | BLOCKED | Tool not installed. |
| `osv-scanner`; native SQLCipher/OpenSSL CVE status | NOT_RUN | Tool unavailable; native versions not determinable without a build. |
| CI status of HEAD on GitHub | NOT_RUN | No remote access; no fetch. |
| Print / PDF template masking and brand text | NOT_RUN | Not reviewed (axis A §2.12, axis C coverage). |
| Keyboard, focus, contrast, DPI 125/150 %, small screens | NOT_RUN | No instrumented UI run (T-C-25). |
| Performance (large DB, long sessions, migrations on large data) | NOT_RUN | Out of the static scope. |
| File-size ratchet test | NOT_RUN | Needs `flutter test`. |

## 5. Files added by the audit

Only documentation under `docs/audits/2026-10-23-release-audit/`; see the [README](<README.md#files>). No test, script or tool was added to the repo. One tool output was saved outside the repo: `%TEMP%\pub_outdated_C.txt` (axis C).

## 6. Working-tree change observed during consolidation (context, not audited)

At 2026-10-23 04:35–04:39 another session modified **14 tracked files** relative to HEAD (`git diff --stat HEAD`: 102 insertions, 60 deletions):
- `assets/i18n/en.json`, `pubspec.yaml`
- `lib/core/config/brand.dart`, `lib/main.dart`
- `lib/presentation/screens/login_screen.dart`, `setup_wizard_screen.dart`
- `lib/services/api/api_auth_handler.dart`, `api_session_token.dart`, `api_user_context.dart`, `routes/api_get_users.dart`
- `lib/services/developer_auth_service.dart`
- `windows/CMakeLists.txt`, `windows/runner/Runner.rc`, `windows/runner/main.cpp`

It also added untracked `lib/core/config/support_env.dart` and `test/security/default_admin_session_test.dart`.

The edits kept growing while this consolidation finished. At ≈ 04:55, **43 tracked files** were modified, adding among others:
- `.github/workflows/ci.yml`, `build_picpos.bat`, `build_installer_picpos.bat`, `build_release.bat`
- `lib/presentation/widgets/permission_guard.dart`
- the sales-invoice dialogs and table
- `parties_picpos_screen.dart`, `excel_service.dart`
- `financial_figures_access.dart`, `database_startup.dart`
- several tests

The file names suggest work on G0 items: BRAND-002/003/004/005/009, SEC-001/002/003/011, AUTHZ-001/002/003. **This audit did not read, run or verify these changes.** All findings remain bound to HEAD `d69be1ea`. Per brief §15, a finding is closed only with verification evidence, not because code changed.
