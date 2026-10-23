# RELEASE_READINESS — PicPos 3.9.2+277 (`d69be1ea`)

**Scope of the decision:** distribution of this version to real users on each channel. The decision follows brief §14: exactly one of four decisions per channel. There is no averaged score and no readiness percentage.

## 1. Decisions

| Channel | Decision | One-line reason |
|---|---|---|
| **Windows desktop, standalone** | **Not ready — proven blockers** | The shipped artifact contains UralCash material, which the owner explicitly forbade (BRAND-001/002, artifact-proven). The candidate's own new access controls are bypassable (AUTHZ-001/002/003). The setup wizard can lock in the wrong currency irreversibly (UX-001). |
| **LAN host + clients** | **Not ready — proven blockers** | All standalone blockers, plus a known-credential system-admin account that the host re-creates and the API accepts without a password change (SEC-001 + SEC-002), and silent loss of reservation rows in a mixed-version fleet (SYNC-001). |
| **PostgreSQL server mode** | **Not ready — proven blockers** | All LAN blockers, plus the AR/AP aging report and admin snapshot SQL that does not run on PostgreSQL (RPT-003, static derivation). There is no in-app backup (BKP-004). |
| **Android apps (Van, POS, Admin)** | **Not ready — proven blockers** | The Van APK is always signed with the debug key and POS falls back to it (REL-004), so no upgradeable, trustworthy APK can be distributed. No APK was built or run on a device. *Note:* `mobile_admin` alone has correct signing, but there is no device evidence and the cloud relay is missing (SYNC-007), so on its own its evidence is insufficient. That note does not change the channel decision. |

"Proven" here means confirmed by artifact inspection (BRAND-001, BRAND-002, REL-002), or confirmed by reading the exact code path end to end with high confidence (all other blockers). **None was reproduced at runtime** (see [TEST_RESULTS.md](<TEST_RESULTS.md>)). Two blockers are explicitly provisional:
- RPT-001: the net effect needs a ≈ 10-minute repro.
- REL-005: suspected; blocks until reproduced or ruled out.

## 2. Release criteria used

They were derived from the brief and the owner decisions and applied the same way to every channel.

| # | Criterion | Applies to |
|---|---|---|
| RC1 | **Owner requirements hold in the shipped artifact.** PicPos-only identity (owner decision 1): no UralCash image, text or name in what a user installs. | W, L, PG (desktop artifact) |
| RC2 | **No confirmed defect defeats an authentication or authorization control** in a normal deployment, and no control that this release claims to add is bypassable in the same screen or flow. | all |
| RC3 | **No confirmed defect produces irreversible or customer-facing wrong financial data** in a default journey: setup currency, customer statement, printed documents. | all desktop |
| RC4 | **Data safety is proven, not assumed.** At least one real encrypted backup restore has been verified, and upgrades cannot silently lose data across the fleet. | W, L (restore); L, PG (fleet sync) |
| RC5 | **Distribution integrity.** Binaries are signed for public distribution; the build that users get comes from a reproducible, guarded pipeline; mobile APKs are release-signed. | all |
| RC6 | **Evidence.** Every blocker fix closes only with a test or repro that demonstrates it (brief §15); the green suite must run on the exact release tree. | all |

## 3. Blockers per channel (all are P0 in [FINDINGS.md](<FINDINGS.md>))

| Finding | Criterion | W | L | PG | AND | Status | Why it blocks |
|---|---|---|---|---|---|---|---|
| BRAND-001 UralCash logo in the artifact | RC1 | ● | ● | ● | | CONFIRMED (artifact) | Explicit owner requirement |
| BRAND-002 UralCash strings in shipped catalogs | RC1 | ● | ● | ● | | CONFIRMED (artifact) | Explicit owner requirement |
| BRAND-004 UralCash build defaults | RC1, RC5 | ● | ● | ● | | CONFIRMED | Any build without flags is UralCash; root cause of BRAND-003 |
| BRAND-012 no artifact brand guard | RC1, RC6 | ● | ● | ● | | CONFIRMED | Without it, BRAND-001/002 cannot be shown closed |
| AUTHZ-001 self-approval of conditional grants | RC2 | ● | ● | ● | | CONFIRMED | The four-eyes control is void; the candidate's B-3 fix relies on it |
| AUTHZ-002 masking bypass via sales details | RC2 | ● | ● | ● | | CONFIRMED | A control this release adds is bypassed in one click |
| AUTHZ-003 (alias RPT-006) masking/gating bypass via statement, export, import, picker | RC2 | ● | ● | ● | | CONFIRMED | Same; plus cross-branch export and balance overwrite |
| UX-001 wizard currency silently becomes JOD, irreversibly | RC3 | ● | ● | ● | | CONFIRMED | Irreversible wrong currency and precision from the first invoice |
| UX-002 hardcoded currency literals | RC3 | ● (EGP) | ● (EGP) | ● (EGP) | | CONFIRMED | Wrong currency on every POS tile, refund and opening balance in Egypt |
| RPT-001 statement includes voided rows | RC3 | ● | ● | ● | | CONFIRMED (net effect: repro first) | Customer-facing debt overstated |
| REL-005 trial watermark on activated machines | RC3 | ● | ● | ● | | **SUSPECTED** | Customer documents may carry "trial"; blocks until reproduced |
| BKP-001 no real restore proven | RC4 | ● | ● | | | CONFIRMED (absence) | A backup button is not proof of restorability |
| REL-002 unsigned binaries | RC5 | ● (public) | ● (public) | ● (public) | | CONFIRMED (tool) | SmartScreen / AV; no tamper evidence on the only update path |
| SEC-001 host re-creates `admin/admin` | RC2 | | ● | ● | | CONFIRMED | A known-credential system admin appears silently |
| SEC-002 API ignores forced password change | RC2 | | ● | ● | | CONFIRMED | Default credentials usable remotely; server-mode setup leaves `admin/admin` |
| SYNC-001 mixed fleet drops v196 rows | RC4 | | ● (cond.) | ● (cond.) | | CONFIRMED | Silent permanent loss on upgrade unless the whole fleet is upgraded together and the watermark reset |
| RPT-003 aging SQL fails on PG | RC3 | | | ● | | CONFIRMED (static) | Standard report and admin snapshot fail in PG mode |
| REL-004 Van/POS debug signing | RC5 | | | | ● | CONFIRMED | Non-upgradeable, untrustworthy APKs |
| BRAND-003 (alias REL-001) CI tag release | RC1, RC5 | (●) | (●) | (●) | | CONFIRMED | Only if a GitHub Release (tag) is a distribution channel (owner question Q2). Until then, disable the `release` job. |

**Conditional (blocks a usage profile only, P1):**
- ACC-001: tenants with fixed assets at or near end of life.
- SYNC-003 (alias DATA-001): LAN sites that take table reservations on client terminals.

**Additional condition for PG** (not a blocker by itself): BKP-004. The release must ship with a documented, scheduled `pg_dump` procedure owned by the operator.

## 4. What would move each channel to "Ready with stated conditions"

Close the blockers in [REMEDIATION_ROADMAP.md](<REMEDIATION_ROADMAP.md>) group G0. Then re-run the full suite **on the exact release tree** and rebuild, with these checks:

| Channel | Minimum additional evidence before re-deciding | Conditions that would likely remain (declared, not blockers) |
|---|---|---|
| W | <ul><li>Artifact brand scan green.</li><li>Widget tests for AUTHZ-001/002/003 and UX-001.</li><li>RPT-001 and REL-005 repros closed.</li><li>One restore drill logged.</li><li>Signed installer (or an explicit owner decision to stay on the controlled pilot).</li><li>Clean-VM install.</li></ul> | <ul><li>JOD/EGP only.</li><li>DB-key migration prompt (SEC-005).</li><li>No updater (manual installer upgrades).</li></ul> |
| L | W evidence, plus:<ul><li>SEC-001/002 tests.</li><li>A mixed-fleet repro or watermark-reset test (SYNC-001).</li><li>A release note enforcing a simultaneous fleet upgrade.</li></ul> | <ul><li>Trusted-LAN / HTTP-by-default assumption documented (SEC-007).</li><li>Reservations entered on the host only, or SYNC-003 fixed.</li><li>SEC-003/004/008 fixed before wider rollout.</li></ul> |
| PG | L evidence, plus a PG integration test for `getArAgingReport` | Operator-run `pg_dump` (BKP-004); PG upgrade path untested (MIG-006) |
| AND | <ul><li>Fail-closed release signing in all apps.</li><li>A CI APK build.</li><li>An install and upgrade test on a physical device per app.</li></ul> | Admin app read-only (no relay, SYNC-007); POS app is an M-0 shell |

## 5. Relation to the previous verdict

`D:\qa\reports\FINAL-QA-VERDICT.md` (2026-10-20) gave **"GO conditional for a limited field pilot (owner / pilot customer); NO-GO for general release"**.

- This audit agrees with the NO-GO for general release.
- It does **not re-endorse** the pilot GO. The pilot verdict predates the figure-masking commit (`d2272da0`), which no GUI round tested (TEST_RESULTS §3). It also predates the findings AUTHZ-001/002/003, BRAND-001/002 and UX-001.

If the owner chooses to **continue an existing controlled pilot** before G0 closes, that is a risk acceptance by the owner, not a readiness decision. The minimum mitigations, all derived from findings, would be:
- Standalone mode only.
- Trusted users only: no reliance on "hide figures" or conditional approvals.
- JOD sites only, with the currency chosen explicitly.
- No customer statements printed from the app.
- An off-machine copy of the DB folder taken manually.
- No distribution from GitHub tags.
