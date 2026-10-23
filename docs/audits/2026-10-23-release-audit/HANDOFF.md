# HANDOFF — release audit 2026-10-23

Read this file to resume the work in a later session without the conversation history.

## 1. Done

- [x] Three read-only axis audits (A security/sync, B data/accounting, C product/UX/release) at `d69be1ea`, each with FINDINGS / COVERAGE / TEST-EVIDENCE / PROJECT_BASELINE.
- [x] Consolidation:
  - One register of 113 findings (3 merges, conflicts resolved by evidence).
  - Normalised severity and priority.
  - Verification status and blocking status per finding.
  - A merged baseline and a merged coverage table.
- [x] Tree-equivalence check between the prior green test chain (`D:\qa\logs4`, 2026-10-21) and HEAD, by file timestamps. Result: equivalent with high likelihood; limits in [TEST_RESULTS §2.1](<TEST_RESULTS.md#21-does-that-run-correspond-to-head-d69be1ea>).
- [x] Release decision per channel (brief §14): all four are **Not ready — proven blockers**.
- [x] Remediation roadmap: G0–G3, 16 Spec groups plus 2 feature Specs, traceability skeleton.
- [x] Both 2026-10-23 plans reconciled with the owner decisions and the audit, each with a change log at the top:
  - First-run plan: activation removed; PicPos-only, with the old wizard deleted; currency, admin and password items added.
  - Warehouse plan: device-pairing permission model, four personas → roles, W0 gating items.

## 2. Not done

- [ ] **Any runtime verification.** No finding is reproduced, no suite was re-run at HEAD, and there was no clean-VM install, restore drill, Android device test, PG run or mixed-fleet run. Reason: `flutter`/`dart` were prohibited for the auditors (shared lock), and no isolated environment was available.
- [ ] Repros that decide two provisional blockers: RPT-001 (≈ 10 min) and REL-005 (≈ 10 min). These are roadmap G0.1.
- [ ] Specs (`SPEC-01` …) are proposed only; none is written.
- [ ] Installer payload unpacking and Gitleaks history scan (tools unavailable).
- [ ] Not reviewed:
  - print/PDF templates (masking and brand text);
  - e-invoice payload amounts;
  - deep-link and `url_launcher` sweep;
  - landed-cost, treasury-transfer and purchase-void posting bodies;
  - mobile and server lockfile licences.
- [ ] The owner has not yet answered the questions in §4.

## 3. Blockers and caveats for whoever resumes

1. **The working tree is moving.** From 2026-10-23 04:35 another session modified tracked files (14 at 04:39, 43 by ≈ 04:55) and added untracked files (see [TEST_RESULTS §6](<TEST_RESULTS.md#6-working-tree-change-observed-during-consolidation-context-not-audited>)). The file names suggest G0 remediation (BRAND, SEC-001/002/003, AUTHZ-001/002/003, CI). This audit did not read or verify them.
   - **Before using any finding, re-check whether HEAD or the tree has changed** (`git rev-parse HEAD; git status --short`).
   - Record each change in the [traceability table](<REMEDIATION_ROADMAP.md#6-traceability-skeleton-finding--spec--task--change--verification--closure>) only after it is committed and verified.
2. Line numbers in the findings are at `d69be1ea`. Re-locate them with grep before editing code.
3. Prior QA numbers (10018 / 61 / 1018 / 13 / 48 / 92) apply to the 2026-10-21 tree. A release needs a fresh run on the exact tree that is built (G0.13).
4. The GUI rounds G1/G1b/G2 ran on a build that predates the figure-masking commit. No GUI evidence covers masking.

## 4. Open owner questions

Each question names the decision it unblocks. Questions the owner already answered on 2026-10-23 are not repeated: PicPos-only; activation stays in Settings; warehouse app for staff paired by the responsible admin; real estate later; review first.

| # | Question | Unblocks |
|---|---|---|
| Q1 | Was any PicPos customer installed before the brand split (2026-07-26) or from a UralCash-default build? | BRAND-011: build a one-time importer, or nothing |
| Q2 | Is the GitHub Release (tag) a distribution channel today? | BRAND-003 / REL-001 severity; disable the `release` job now |
| Q3 | Is "trusted LAN, HTTP by default" acceptable for field deployments, or must TLS + pinning be the default? | SEC-007; LAN release conditions; warehouse app TLS (W1) |
| Q4 | Is "hide monetary figures" (commit `d2272da0`) presented to customers as an access control in 3.9.2? | AUTHZ-003 / RPT-006 stays a P0 blocker (yes) or falls to P1 (no) |
| Q5 | Should `sales_view` alone reveal invoice amounts, or should `sales_amounts_view` remain the gate? Should `inventory_view` reveal cost? | AUTHZ-004, AUTHZ-009, SPEC-04 rules |
| Q6 | In non-demo builds, what should activation gate: the watermark only, or limits too? | REL-005 fix, SPEC-12 |
| Q7 | Is the home country fixed per install, so foreign country codes can be kept in the phone key? | DATA-002 |
| Q8 | Is renaming the built-in `admin` a supported scenario? | SEC-001 fix (forbid rename, or stable identity); whether the first-run plan may let the admin username be edited |
| Q9 | DB-key migration after upgrade: automatic (with the safe M1–M8 flow) or a persistent prompt? | SEC-005 |
| Q10 | Is PostgreSQL server mode shipped to customers in 3.9.2? | Whether the PG channel decision matters now (RPT-003, BKP-004) |
| Q11 | Will a simultaneous upgrade of host and all clients be enforced for 3.9.2 (release note + support procedure)? | SYNC-001 release-now mitigation |
| Q12 | Code-signing certificate: OV or EV, and who procures it? | REL-002 (G0.12) lead time |
| Q13 | Warehouse app: one new permission `devices_pair_manage` for all device kinds (recommended), or a separate `devices_pair_warehouse`? Confirm the persona → role mapping, including new roles «مشرف مخزن» and «موظف مخزن». | Warehouse plan W0/W1 (§E-12, §E-13 there) |
| Q14 | First-run plan: confirm the remaining recommended defaults (E2 profile mapping, E5–E11); E1/E3/E4 are superseded. | FR-SETUP Spec |
| Q15 | Until G0 closes, should the existing controlled pilot continue? This would be a risk acceptance with the mitigations in RELEASE_READINESS §5. | Pilot operations |

## 5. How to resume

1. Confirm the version: `git rev-parse HEAD` and `git status --short`.
   - If HEAD ≠ `d69be1ea` or tracked files differ, list the changes and map them to finding IDs.
   - Do **not** mark anything closed without verification evidence.
2. Get answers to Q2, Q4, Q8, Q10 and Q11 first; they change blocker scope.
3. When `flutter` may be run in an isolated copy (never on the owner's live data), do G0.1: repro RPT-001 and REL-005, and update their status in [FINDINGS.md](<FINDINGS.md>) §3/§4 and in [RELEASE_READINESS.md](<RELEASE_READINESS.md>).
4. Write Specs in the order SPEC-01 (B0 guard first) → SPEC-03 → SPEC-04 → SPEC-05 → SPEC-02 → SPEC-06 → SPEC-07 → SPEC-09 → SPEC-11 → SPEC-12, using the brief §15 template listed in [REMEDIATION_ROADMAP.md §5](<REMEDIATION_ROADMAP.md#5-proposed-spec-groups-brief-15>).
5. After the fixes, run G0.13:
   - analyze with 0 issues;
   - the full chain on the release commit;
   - the artifact brand scan;
   - a clean-VM install, upgrade and uninstall;
   - one restore drill.

   Then re-decide each channel in RELEASE_READINESS.md.
6. Keep the documentation updated in place. Fill the traceability table; do not create parallel registers.

## 6. Files written by the consolidation

- `docs/audits/2026-10-23-release-audit/`: `README.md`, `PROJECT_BASELINE.md`, `AUDIT_PLAN_AND_COVERAGE.md`, `FINDINGS.md`, `TEST_RESULTS.md`, `RELEASE_READINESS.md`, `REMEDIATION_ROADMAP.md`, `HANDOFF.md`.
- Edited (surgical, change log at the top of each): `docs/plans/2026-10-23-first-run-setup-redesign-plan.md`, `docs/plans/2026-10-23-warehouse-app-plan.md`.
- Nothing was committed. Axis files and product code are unchanged by the consolidation.
