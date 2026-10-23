# Release audit 2026-10-23 — PicPos ERP 3.9.2+277

This is the engineering review of quality and release readiness requested in the owner's audit brief (`طلب مراجعه.txt`, §1–§16). It ends with reports and a remediation plan. **Product fixes are a later phase:** no product code, configuration or build file was changed by this audit.

## Verdict in one paragraph

Every channel is **Not ready — proven blockers**: Windows standalone, LAN host + clients, PostgreSQL server mode, and the Android apps. The blockers are confirmed by artifact inspection or by reading the exact code path. **None was reproduced at runtime**, and two are provisional pending a short repro (RPT-001, REL-005). The main reasons:
- UralCash material inside the PicPos artifact.
- The candidate's own new access controls can be bypassed (self-approval, figure masking).
- An irreversible wrong-currency outcome in the setup wizard.
- A silently re-created `admin/admin` account that the LAN API accepts.
- Mixed-fleet sync loss.
- PG-incompatible report SQL.
- Debug-signed Android APKs.
- No proven restore.

Details: [RELEASE_READINESS.md](<RELEASE_READINESS.md>).

## Scope

- **In scope:** the whole product at one pinned commit.
  - Windows desktop app in all modes: standalone, server (SQLite or PostgreSQL), client, mirror.
  - Embedded LAN API.
  - Cloud server (`server/`).
  - Android apps (`mobile/`, `mobile_admin/`, `mobile_pos/`).
  - Installer and CI.
  - Dependencies.
  - The two plan documents of 2026-10-23.
- **Axes:**
  - A: security, authentication, permissions, sync.
  - B: data integrity, accounting, reports, migrations, backup.
  - C: product identity (PicPos-only), UX, architecture, distribution, dependencies.
- **Method:** static reading, artifact inspection, one tool run (`dart pub outdated`), and the prior QA logs used as secondary evidence. See [AUDIT_PLAN_AND_COVERAGE.md](<AUDIT_PLAN_AND_COVERAGE.md>).
- **Not executed:** any runtime reproduction, clean-machine install, restore drill, Android device test, or test-suite re-run. Reasons are in [AUDIT_PLAN_AND_COVERAGE.md §5](<AUDIT_PLAN_AND_COVERAGE.md#5-what-was-not-executed-and-why>).

## Version and environment

| Item | Value |
|---|---|
| Repo / branch | `D:\PICPOS-ERP` / `feat/tables-reservations-permissions` |
| Commit audited | `d69be1eafc7d82b924723dfdbb53960b7e33acdb` (2026-10-23 03:08 +0300), app `3.9.2+277`, `schemaVersion` 196 |
| Candidate range | `c5f5056c..d69be1ea` (4 commits) |
| Artifact inspected | `FlavorBuilds\PicPos\` (2026-10-23 03:14) and `installer\output\PicPos-Setup-3.9.2.277.exe` (03:15), assumed to be built from HEAD |
| Prior evidence | `D:\qa\logs4\` (automated chain, 2026-10-21); `D:\qa\reports\` (GUI rounds G1/G1b/G2 and FINAL-QA-VERDICT, 2026-10-20) |
| Machine | Owner's Windows dev machine, PowerShell. Local Flutter at `D:\Cash\develop\flutter` (not run by the auditors). |
| Remote | Not fetched; remote and CI state unknown |
| Audit dates | 2026-10-23 ≈ 03:30–04:45 (+03:00) |
| Working tree | Untracked files only during the axis audits. From ≈ 04:35 another session began modifying tracked product files: 14 at 04:39, 43 by ≈ 04:55, apparently remediation of G0 items. These changes are outside the audit and not verified ([TEST_RESULTS §6](<TEST_RESULTS.md#6-working-tree-change-observed-during-consolidation-context-not-audited>)). **All findings are bound to the commit above, not to the current working tree.** |

## How to read the reports

1. Start with **[RELEASE_READINESS.md](<RELEASE_READINESS.md>)**: the decision per channel, the criteria used, the blockers, and what would change the decision.
2. **[FINDINGS.md](<FINDINGS.md>)** is the single register (113 entries).
   - §3 holds the full record for every release blocker and merged entry.
   - §4 lists all entries, with links to the axis file that holds the full record (repro, evidence, impact, root cause, remediation, acceptance).
   - FINDINGS.md is authoritative for severity, priority, verification status and blocking.
3. **[REMEDIATION_ROADMAP.md](<REMEDIATION_ROADMAP.md>)**: ordered work groups G0–G3, Spec groups, and the traceability table.
4. **[TEST_RESULTS.md](<TEST_RESULTS.md>)**: what was actually executed, and what was not.
5. **[PROJECT_BASELINE.md](<PROJECT_BASELINE.md>)**: how the system works as read; assumptions.
6. **[HANDOFF.md](<HANDOFF.md>)**: how to resume; open owner questions.

**Verification labels:**
- `CONFIRMED-BY-READING`: code path, artifact or tool output; no runtime repro.
- `SUSPECTED-NEEDS-REPRO`.

**Check statuses:** PASS / FAIL / BLOCKED / NOT_RUN / NOT_APPLICABLE. A PASS from this audit means "verified by reading"; it never means a test was executed unless the row is marked [prior].

## ID scheme

- **Finding IDs** are stable and carry their axis prefix:
  - `SEC`, `AUTHZ`, `SYNC` (axis A).
  - `RPT`, `ACC`, `DATA`, `MIG`, `BKP` (axis B).
  - `BRAND`, `UX`, `ARCH`, `REL`, `DEP` (axis C).
  - Duplicates were merged under one **canonical** ID; the others are **aliases** that resolve to it: RPT-006 → AUTHZ-003, DATA-001 → SYNC-003, REL-001 → BRAND-003.
  - Prior QA IDs (`B-1`, `D-3`, `C-6`, `G1b-#2`, …) are also listed as aliases.
- **Work items:** `G0.n` (blockers) in the roadmap; groups `G1`–`G3`.
- **Specs:** `SPEC-01` … `SPEC-16`, plus the feature Specs `FR-SETUP` and `WH-APP`.
- **Release criteria:** `RC1` … `RC6`.
- **Owner questions:** `Q1` … `Q15` (in HANDOFF).
- **Prior test stages:** `S0` … `S6` (`D:\qa\logs4`); axis C checks are `T-C-nn`.

## Files

**Consolidated deliverables (this folder):**
- [README.md](<README.md>) — this index.
- [PROJECT_BASELINE.md](<PROJECT_BASELINE.md>)
- [AUDIT_PLAN_AND_COVERAGE.md](<AUDIT_PLAN_AND_COVERAGE.md>)
- [FINDINGS.md](<FINDINGS.md>)
- [TEST_RESULTS.md](<TEST_RESULTS.md>)
- [RELEASE_READINESS.md](<RELEASE_READINESS.md>)
- [REMEDIATION_ROADMAP.md](<REMEDIATION_ROADMAP.md>)
- [HANDOFF.md](<HANDOFF.md>)

**Axis working files (source evidence; not edited by the consolidation):**
- Axis A: [FINDINGS-A](<axis-A-security-sync/FINDINGS-A.md>), [COVERAGE-A](<axis-A-security-sync/COVERAGE-A.md>), [TEST-EVIDENCE-A](<axis-A-security-sync/TEST-EVIDENCE-A.md>), [PROJECT_BASELINE-A](<axis-A-security-sync/PROJECT_BASELINE-A.md>).
- Axis B: [FINDINGS-B](<axis-B-data-accounting/FINDINGS-B.md>), [COVERAGE-B](<axis-B-data-accounting/COVERAGE-B.md>), [TEST-EVIDENCE-B](<axis-B-data-accounting/TEST-EVIDENCE-B.md>), [PROJECT_BASELINE-B](<axis-B-data-accounting/PROJECT_BASELINE-B.md>).
- Axis C: [FINDINGS-C](<axis-C-product-ux-release/FINDINGS-C.md>), [COVERAGE-C](<axis-C-product-ux-release/COVERAGE-C.md>), [TEST-EVIDENCE-C](<axis-C-product-ux-release/TEST-EVIDENCE-C.md>), [PROJECT_BASELINE-C](<axis-C-product-ux-release/PROJECT_BASELINE-C.md>).

**Plans reconciled with the owner decisions and this audit** (outside this folder; each starts with a change log):
- [docs/plans/2026-10-23-first-run-setup-redesign-plan.md](<../../plans/2026-10-23-first-run-setup-redesign-plan.md>)
- [docs/plans/2026-10-23-warehouse-app-plan.md](<../../plans/2026-10-23-warehouse-app-plan.md>)

Nothing was committed. No tests, scripts or tools were added to the repository. Axis C saved one tool output outside the repo (`%TEMP%\pub_outdated_C.txt`).
