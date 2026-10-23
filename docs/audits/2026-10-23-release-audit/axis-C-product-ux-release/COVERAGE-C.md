# Axis C: Coverage (product identity, UX, architecture, distribution)

**Version:** `d69be1ea`. **Method legend:** CR = code read, AS = automated scan (grep/byte scan), AR = artifact inspection, IMG = image review, PR = prior QA evidence, TOOL = executed tool.
Readers (read-only sub-agents) were used for three independent questions: distribution & activation; UX currency & journeys; architecture & tests. Their reports were spot-checked. Re-verified items: brand.dart, CI lines 620-700, CurrencyInfo, SystemCurrencyNotifier, trial and licence path, NumberUtils, the login footer, the wizard title, `sales_return_provider:171`, and the analyzer log. Items that were not re-verified are marked Confidence Medium in FINDINGS-C.

## 1. Brand / identity (owner requirement 2026-10-23)

| Area | Method | Status | Findings |
|---|---|---|---|
| `lib/` (all literals and comments) | AS + CR | Covered | BRAND-005, BRAND-009 |
| `assets/` (i18n, fonts, invoice_templates, brand, audio) | AS + IMG + AR | Covered | BRAND-001, BRAND-002. Invoice templates: 0 brand hits. Fonts are OFL. |
| `windows/` (CMakeLists, Runner.rc, main.cpp, manifest, icons) | AS + CR + hash | Covered | BRAND-004, BRAND-008 |
| `installer/` (setup.iss, info-ar-*, wizard BMPs, make_wizard_images.py) | AS + CR | Covered (BMPs judged by name and generator, not viewed) | BRAND-007, REL-007 |
| Android: `mobile/`, `mobile_admin/`, `mobile_pos/` (ids, labels, icons, manifests) | AS + CR + IMG | Covered | Brand clean. REL-004 |
| `packages/` | AS | Covered | BRAND-010 |
| `server/`, `docker/` | AS | Covered (`server/` 1 comment; `docker/` 0 hits) | — |
| `tool/`, `tools/`, `scripts/`, `*.bat` | AS + CR | Covered | BRAND-007, BRAND-010 |
| `.github/` | CR | Covered | BRAND-003 |
| `docs/` (81 files) | AS (counts only) | Partially covered: not read one by one | BRAND-010 |
| README, ARCHITECTURE, PRODUCT, DESIGN, `.env.example`, `.gitignore`, `.impeccable` | AS | Covered | BRAND-010 |
| `web/` (root web entry assets) | AS + IMG | Covered | Names are PicPos; icons are the default Flutter logo |
| `web_app/` | AS | Covered | BRAND-010 |
| `supabase/`, `db/legacy_migrations` | AS | Covered | BRAND-010 |
| pubspec names and descriptions (all) | CR | Covered | BRAND-006, BRAND-010 |
| Test fixtures (`test/`) | AS (counts) | Partially covered | 73 files mention brand words; they are tests of the dual-brand split and go with BRAND-009/012 |
| Build outputs (`FlavorBuilds\PicPos`) | AR (byte scan) | Covered | BRAND-001/002/005 |
| Installer payload | AR | **Not covered** (compressed; no unpacker) | T-C-08 |
| DB / log / backup / AppData / registry names | CR + observation | Covered | BRAND-011 (PASS) |
| Brand class and `isPicPos` forks | CR | Covered | BRAND-009 |
| Dual-brand guard tests | CR + PR | Covered | BRAND-012 |
| Printed documents (receipt / PDF) for brand text | CR only (`documentCompanyFallback`) | **Not covered at runtime** | Covered by axis B / printing QA if any |

## 2. UX / journeys

| Topic | Method | Status | Findings |
|---|---|---|---|
| First-run vs periodic setup vs daily use | CR + PR + plan review | Covered | UX-001, UX-004, UX-005, UX-010 |
| Currency correctness (JOD/EGP) | CR | Covered (all `lib/` literals) | UX-001, UX-002, UX-003 |
| Navigation clarity and duplicates | CR (reader) + IMG | Partially covered (not clicked through) | UX-006, UX-007 |
| Terminology consistency | IMG + CR | Partially covered | UX-006 |
| Confirmation of high-impact actions | CR (sample of 10) | Sampled | UX-008 |
| RTL / Arabic | CR + PR | Partially covered | UX-009 |
| Loading / error / empty states | PR (skeletons observed in G1b) | Not systematically covered | — |
| Keyboard / focus / contrast / small screens / zoom | IMG only | **NOT_RUN** (no instrumented run) | T-C-25 |
| Warehouse-app plan | Plan + code anchors | Covered | UX-011 |
| Security-control timing (where checks are enforced) | — | Out of axis (security axis) | Fail-open note in ARCH-001 |

## 3. Architecture

| Topic | Method | Status | Findings |
|---|---|---|---|
| God-file ratchet | CR | Covered (not executed) | ARCH-007 |
| Duplicated business rules | CR (reader) | Covered at the location level; no numeric divergence demonstrated | ARCH-002 |
| Swallowed exceptions | AS (counts) + CR sample | Covered | ARCH-001 |
| Async-gap / BuildContext | PR (analyze log) + CR | Covered | ARCH-004 |
| Provider lifecycle / stale caches | CR (reader) | Sampled | ARCH-003 |
| Dead code / unused deps | AS | Covered for root deps | DEP-004 |
| i18n mechanism | CR | Covered | BRAND-002 (unused `catalog_ar.json`). Arabic text as key, `en.json` fallback to Arabic; about 11.1k EN entries |
| Test quality | CR sample (about 4 files) + counts | Partially covered | ARCH-005 |
| CI content | CR | Covered | ARCH-006 |

## 4. Distribution

| Topic | Method | Status | Findings |
|---|---|---|---|
| Inno installer (AppId, publisher, upgrade, VC++, PG) | CR | Covered | REL-002, REL-003, REL-007 |
| Signing / SmartScreen | TOOL (`Get-AuthenticodeSignature`) | Covered | REL-002 |
| VC++ redist pinning | CR | Covered: PASS (bundled, version- and SHA-pinned, signature checked in `fetch_prereqs.ps1`) | — |
| Update mechanism and backup before upgrade | CR | Covered | REL-003 |
| Version pins | CR | Covered | REL-008 |
| SQLCipher enforcement | CR + AR | Covered | REL-001 (CI), PASS (local) |
| Android signing, network config, permissions, ids | CR | Covered | REL-004 |
| Size | AR | Measured: desktop 82.4 MB unpacked, installer 47.7 MB; APK sizes NOT_RUN | — |
| Licences | TOOL (local pub cache) | Root lockfile covered | DEP-003 |
| Activation / licence mechanism | CR | Covered | REL-005, REL-006 |
| Dependency freshness | TOOL (`dart pub outdated`) | Covered | DEP-001, DEP-002 |
| Clean-VM install, upgrade, uninstall, downgrade | — | **NOT_RUN** | T-C-22, T-C-24 |

## Coverage limits and their impact
1. **No runtime launch.** REL-005 (watermark) and UX-005 (company name) remain predictions or suspicions.
2. **Installer payload not unpacked.** BRAND-001/002 are proven on the Release folder, and their presence in the installer is inferred from `[Files]`.
3. **Readers' inventories** were spot-checked, not re-derived line by line (UX-007, ARCH-002, ARCH-003), and are marked Medium confidence.
4. **`docs/` (81 brand-bearing files) and `test/` (73)** were counted, not individually classified. Both are class (b)/(c) and are not shipped.
