# Product

<!-- impeccable:product-schema 1 -->

## Platform

adaptive

<!-- Windows desktop (Flutter) is the primary surface today. A native Android cash-van app (phase I) belongs to the same product and follows Android conventions; each surface uses its own platform's patterns. -->

## Users

Small and medium-sized shops and businesses in Jordan and Egypt: supermarkets, retail, wholesale, distribution, restaurants, cafés and light manufacturing (e.g. butchery).

People who use the system every day:
- **Cashier:** quick sale at the point of sale under time pressure.
- **Accountant:** vouchers, entries, cheques, reconciliations and reports.
- **Warehouse / purchasing manager:** items, stock, transfers, purchases and returns.
- **Distribution manager:** areas, routes, reps, vans and custody.
- **Field rep:** sells, collects and issues invoices from the van (mobile app, phase I).
- **Owner / manager:** follows indicators and reports and approves policies and permissions.

## Product Purpose

An ERP + POS that covers the full business cycle, from the point of sale to the financial statements, in one system. Success means the shop runs its sales, stock, treasury and distribution day without contradictions between screens, accounts and reports, and that every number on screen agrees with the general ledger.

## Positioning

- **Arabic-first:** native right-to-left, with a full English interface chosen per user.
- **Real accounting:** double-entry bookkeeping consistent with IFRS — automatic entries, fiscal years, cost centers, FX differences and revaluation. Not a simple cash register.
- **Works without internet:** works locally on an encrypted database (SQLCipher) and syncs over the local network, and later with a central cloud server.
- **Editions per activity:** restaurants, cafés, supermarket, commercial/wholesale and unified, each enabling the screens and features its activity needs.
- **Tax e-invoicing:** compatible with JoFotara (Jordan) and ETA (Egypt).

## Operating Context

- **Branches and devices:** a desktop installer on Windows (`PicPos-Setup-<ver>.exe`). The main server device and client devices sit on the local network, paired with a code/QR.
- **Hardware:** thermal printers (58/80 mm) and A4/A5, pricing scales/PLU, barcode readers and cash drawers.
- **Documents:** printed documents follow the company language. The interface follows each user's language.
- **Daily work:** opening and closing shifts, quick sale, sales/purchase invoices and their returns, receipt/payment vouchers with paper voucher books per employee, cheques (inquiry and status actions), stock transfers, rep loading/unloading of the van, custody handover.
- **Distribution:** distribution area → route with one rep, visit days and a manually ordered customer list. A customer belongs to one route at a time, and the rep is derived from the route. Every document records the rep and route as they were when it was issued.

## Capabilities and Constraints

- **Stack:** Flutter/Dart (Windows desktop), Drift/SQLite (SQLCipher) plus optional PostgreSQL, Riverpod.
- **Dual brands:** two brands from the same code (`Brand.isPicPos`). PicPos must not show any trace of UralCash, and UralCash keeps its own behavior.
- **Permissions:** detailed permissions at the button and action level, and a manager override for sensitive operations.
- **Display, not data:** default names that the system creates show in English when unchanged; names the user entered are shown exactly as entered.
- **Coming (phase I):** an offline-first cash-van Android app.
  - Syncs over HTTPS with a central cloud server.
  - Per-device number ranges.
  - Bluetooth printing.
  - Automatic invoice sending via WhatsApp Business API to customers with registered numbers.
- **Undecided:** cloud hosting provider and its deployment details; WhatsApp Business account approval.

## Brand Commitments

- Name: **PicPos**. Logo: `assets/brand/picpos/logo.png`.
- Interface font: **Cairo** (`assets/fonts/Cairo-*.ttf`), the owner's choice. Arabic printing font: **Noto Naskh Arabic**.
- Arabic as the base language with full support for English and right-to-left/left-to-right direction.
- Light and dark modes are both required.

## Evidence on Hand

- Audit and readiness reports: `docs/audit/` (including `GO-NO-GO-2026-09-29.md`).
- Load-test report: `docs/perf/perf_report_2026-09.md`.
- Terminology glossary and translation review: `docs/i18n/glossary.md`, `docs/i18n/translation_review.csv`.
- Manual print checklist: `docs/print_manual_checklist.md`.
- The owner's reference designs for invoices, returns and the chart of accounts were shared in the session (not saved in the repo).
- No customer testimonials, published case studies or prices exist; none may be fabricated.

## Product Principles

1. **The ledger is the truth:** every number on screen or in a report must match the general ledger; no transaction may produce a difference between screens, accounts and reports.
2. **Field speed for the cashier and the rep:** the most frequent tasks are the shortest and work without internet.
3. **Clear assignment, not ambiguous assignment:** links such as customer → route → rep are explicit, tied to dates and recorded on documents, so history never changes after the fact.
4. **Arabic and English as equals:** no screen is complete if it shows a word in the wrong language or breaks under either text direction.
5. **One brand per installation:** PicPos is its own product, and a change to it must not touch UralCash, or the reverse.

## Accessibility & Inclusion

- Full right-to-left and left-to-right support; text in light and dark modes must meet WCAG contrast of at least 3.0 for large elements, as checked by the current dark-mode tests.
- Touch screens at the point of sale with an on-screen keyboard, and widths down to 1366×768 without overflow.
