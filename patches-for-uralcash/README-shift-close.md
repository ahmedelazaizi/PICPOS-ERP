# Patch: shift-close activation (`ScreenId.shiftClose`)

## What this fixes

`ScreenId.shiftClose(56)` (`lib/core/navigation/screen_id.dart`) has been dead
weight on **both** UralCash and PicPos for a while: it is listed in
`ScreenRegistry`'s profile lists (`restaurant`, `supermarket`,
`supermarketPro`, `supermarketPlus`, `commercial`, and the shared `lite`
profile PicPos inherits) but was never wired up at any of the three layers
that make a `ScreenId` actually reachable:

1. **`AppScreen` enum** (`lib/core/enums/app_screen.dart`) had no matching
   `shiftClose` value — `ScreenId` and `AppScreen` are two independent,
   hand-kept-in-sync enums, and this one had drifted.
2. **`screenPermissionMap`** (`lib/data/providers/auth_providers.dart`) had no
   entry for it, so `userAllowedScreensProvider` could never surface its
   index for any user, admin or not.
3. **`userNavItemsProvider`'s `allNavItems`** (same file) had no `NavItemDef`
   for it, so there was no sidebar menu item to click even independent of
   permissions.

This is a **pre-existing UralCash-origin gap**, not something introduced by
or unique to the PicPos redesign — `ScreenId.shiftClose` was already listed
in every one of UralCash's own non-`unified` profiles. This patch closes the
gap for both products at once, following this repo's own convention that a
logical bug/gap in an UralCash-origin file gets fixed in its own isolated,
patchable commit.

## What the patch does NOT do

It does not add any UI affordance inside UralCash's existing POS header —
UralCash already has a working close-shift button there
(`lib/presentation/pos/widgets/pos_header.dart:383-421`,
`_buildShiftCloseButton()`), gated on `PermissionCodes.posShiftClose`. This
patch only makes the **separate, sidebar-reachable** `ScreenId.shiftClose`
screen resolvable — a second, independent entry point (useful for e.g. an
admin who wants to open/close a shift without going through the POS screen,
or as a dedicated screen a role can be scoped to without granting POS access
outright).

It contains **zero** brand-conditional code and **zero** PicPos-only files.
The new `ShiftCloseScreen` is deliberately plain/neutral — no PicPos shell,
no brand branch of any kind — so it patches onto UralCash unmodified. A
PicPos-identity fork (matching PicPos's visual shell) is a separate,
follow-up change and is NOT part of this patch.

## Files touched

| File | Change |
|---|---|
| `lib/core/enums/app_screen.dart` | Adds `shiftClose(56)` to the `AppScreen` enum (matches `ScreenId.shiftClose`'s value). Inert by itself. |
| `lib/data/providers/auth_providers.dart` | Adds `ScreenId.shiftClose: PermissionCodes.posShiftClose` to `screenPermissionMap`, and a `NavItemDef` (index 56, same permission, icon `PhosphorIconsBold.lockKey`, label "إغلاق الوردية") to `userNavItemsProvider`'s `allNavItems`, grouped with the other "المالية والمحاسبة" (treasury/accounting) items. |
| `lib/presentation/screens/shift_close_screen.dart` | **New file.** A small screen that shows the current user's shift status by reusing `posClosingControllerProvider`/`PosClosingState` as-is, opens `PosCashierClosingDialog.show(context)` (existing, unmodified) to close a shift, opens a new shift via `treasuryRepositoryProvider.openShift(...)` + the `ClientWriteInterceptor.openShift(...)` server mirror (mirroring `_enforceShiftForCashier` in `app_main_screen.dart`), and deep-links to the existing `ShiftsReportScreen` for full history — it does **not** re-implement `getShiftsReportPaginated`. |
| `lib/app_main_screen.dart` | Adds one `ScreenConfig(appScreen: AppScreen.shiftClose, builder: (_) => const ShiftCloseScreen(), ...)` entry to `_getAllScreens()`, plus the corresponding import. |

## Applying the patch

```
git apply patches-for-uralcash/shift-close-activation.diff
```

(Generated with `git diff <base>..<head> -- <these 4 files>`, not
`git format-patch` — apply with `git apply`, not `git am`.)

### ⚠️ `app_main_screen.dart` hunk may need manual reconciliation

The `app_main_screen.dart` hunk was generated against PICPOS-ERP's current
`_getAllScreens()` ordering (it's inserted right after the
`purchaseReturns`/`salesReturns` `ScreenConfig` entries and right before
`syncConflicts`). If UralCash's `app_main_screen.dart` has diverged — a
different screen order, additional screens not present here, or the
surrounding lines edited independently since the two codebases split — the
hunk context may not match and `git apply` can fail or offer a fuzzy/partial
match. In that case, apply the other three files first, then add the
`shift_close_screen.dart` import and the `ScreenConfig(appScreen:
AppScreen.shiftClose, builder: (_) => const ShiftCloseScreen(), label:
'إغلاق الوردية', icon: PhosphorIconsBold.lockKey)` entry by hand anywhere
inside `_getAllScreens()` — order doesn't matter functionally, only that the
`ScreenConfig` exists once.

### Reused as-is — nothing new to wire up

`ShiftCloseScreen` calls only machinery that already exists in UralCash,
unmodified:

- `posClosingControllerProvider` / `PosClosingController` / `PosClosingState`
  (`lib/presentation/pos/providers/pos_closing_controller.dart`)
- `PosCashierClosingDialog.show(context)`
  (`lib/presentation/pos/widgets/pos_cashier_closing_dialog.dart`)
- `PosOpeningBalanceDialog`
  (`lib/presentation/pos/widgets/pos_opening_balance_dialog.dart`)
- `treasuryRepositoryProvider.{openShift, getCurrentOpenShift}` and
  `ClientWriteInterceptor.openShift(...)`
- `ShiftsReportScreen`
  (`lib/presentation/screens/reports/shifts_report_screen.dart`)
- `PermissionCodes.posShiftClose`
  (`lib/core/permissions/permission_codes.dart`)

None of these are touched by the patch — it only adds the missing
enum/permission-map/nav-item/route wiring plus the one new neutral screen
file that calls them.

## Verification run on the PicPos side (this repo)

- `flutter analyze lib` — zero issues.
- `test/widget/picpos_shift_close_screen_test.dart` — builds
  `const ShiftCloseScreen()`, passes.
- `flutter test --concurrency=1 test/unit/brand_isolation_test.dart` (UralCash
  identity guardrail) — green, unaffected (no nav/screen-count assertions).
- `flutter test --dart-define=APP_BRAND=picpos test/unit/brand_picpos_test.dart`
  (PicPos identity guardrail) — green, unaffected.
- `test/unit/spec_151_track3_branch_scope_test.dart` (shift-report
  branch-scope DAO test) — green, unaffected (it exercises
  `getShiftsReportPaginated` directly at the DAO layer, not the nav/screen
  plumbing this patch touches).

No existing test in this repo pins a nav-item count or an allowed-screen
count, so none needed updating for this activation.
