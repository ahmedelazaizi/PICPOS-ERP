---
name: PicPos
description: Arabic-first ERP + POS for Windows desktop — flat hairline surfaces on a cool blue-grey canvas, one confident brand blue.
colors:
  brand-blue: "#0250D3"
  brand-navy: "#012258"
  brand-sky: "#4A80E8"
  brand-ink-dark: "#7DA6F5"
  canvas: "#F2F5FA"
  card: "#FFFFFF"
  field-fill: "#F4F7FC"
  hairline: "#DCE3EE"
  ink: "#000000"
  ink-secondary: "#374151"
  ink-muted: "#6B7280"
  canvas-dark: "#0A1220"
  card-dark: "#121C2E"
  field-fill-dark: "#18243A"
  hairline-dark: "#243247"
  ink-dark: "#FFFFFF"
  ink-muted-dark: "#94A3B8"
  sidebar-slate: "#1E293B"
  success: "#22C55E"
  success-deep: "#16A34A"
  warning: "#F59E0B"
  warning-deep: "#D97706"
  error: "#EF4444"
  error-deep: "#DC2626"
  switch-track-off: "#C7D2E1"
  checkbox-outline: "#B6C2D4"
typography:
  display-large:
    fontFamily: "Cairo"
    fontSize: "30px"
    fontWeight: 700
  display-medium:
    fontFamily: "Cairo"
    fontSize: "25px"
    fontWeight: 700
  display-small:
    fontFamily: "Cairo"
    fontSize: "21px"
    fontWeight: 700
  headline-medium:
    fontFamily: "Cairo"
    fontSize: "19px"
    fontWeight: 700
  headline-small:
    fontFamily: "Cairo"
    fontSize: "17px"
    fontWeight: 700
  title-large:
    fontFamily: "Cairo"
    fontSize: "16px"
    fontWeight: 700
  title-medium:
    fontFamily: "Cairo"
    fontSize: "15px"
    fontWeight: 700
  title-small:
    fontFamily: "Cairo"
    fontSize: "14px"
    fontWeight: 700
  body-large:
    fontFamily: "Cairo"
    fontSize: "15px"
    fontWeight: 600
    lineHeight: 1.65
  body-medium:
    fontFamily: "Cairo"
    fontSize: "14px"
    fontWeight: 600
    lineHeight: 1.65
  body-small:
    fontFamily: "Cairo"
    fontSize: "13px"
    fontWeight: 600
    lineHeight: 1.6
  label-large:
    fontFamily: "Cairo"
    fontSize: "14px"
    fontWeight: 700
  label-medium:
    fontFamily: "Cairo"
    fontSize: "13px"
    fontWeight: 700
  label-small:
    fontFamily: "Cairo"
    fontSize: "12px"
    fontWeight: 700
  kpi-value:
    fontFamily: "Cairo"
    fontSize: "25px"
    fontWeight: 800
    lineHeight: 1.1
    fontFeature: "tnum"
  block-title:
    fontFamily: "Cairo"
    fontSize: "14.5px"
    fontWeight: 800
  table-cell:
    fontFamily: "Cairo"
    fontSize: "13px"
    fontWeight: 700
    fontFeature: "tnum"
  table-meta:
    fontFamily: "Cairo"
    fontSize: "11.5px"
    fontWeight: 800
  print-body:
    fontFamily: "Noto Naskh Arabic"
    fontWeight: 400
rounded:
  check: "5px"
  sm: "8px"
  chip: "9px"
  control: "10px"
  control-lg: "11px"
  tile: "12px"
  card: "14px"
  block: "17px"
  dialog: "18px"
  pill: "999px"
spacing:
  xs: "4px"
  sm: "8px"
  md: "12px"
  lg: "16px"
  table-gutter: "18px"
  page-gutter: "20px"
  xl: "24px"
  strip-gutter: "26px"
  xxl: "32px"
  section: "48px"
  page: "64px"
components:
  button-primary:
    backgroundColor: "{colors.brand-blue}"
    textColor: "{colors.card}"
    typography: "{typography.title-small}"
    rounded: "{rounded.control}"
    padding: "10px 20px"
    height: "42px"
  button-primary-form:
    backgroundColor: "{colors.brand-blue}"
    textColor: "{colors.card}"
    rounded: "{rounded.control-lg}"
    padding: "0 22px"
    height: "44px"
  button-outlined:
    backgroundColor: "transparent"
    textColor: "{colors.brand-navy}"
    rounded: "{rounded.control}"
    padding: "10px 20px"
    height: "42px"
  button-outlined-dark:
    backgroundColor: "transparent"
    textColor: "{colors.ink-dark}"
    rounded: "{rounded.control}"
    padding: "10px 20px"
    height: "42px"
  button-text:
    backgroundColor: "transparent"
    textColor: "{colors.brand-blue}"
    rounded: "{rounded.sm}"
    padding: "6px 14px"
    height: "38px"
  input:
    backgroundColor: "{colors.field-fill}"
    textColor: "{colors.ink}"
    typography: "{typography.body-medium}"
    rounded: "{rounded.control}"
    padding: "13px 14px"
  input-dark:
    backgroundColor: "{colors.field-fill-dark}"
    textColor: "{colors.ink-dark}"
    rounded: "{rounded.control}"
    padding: "13px 14px"
  page-header:
    backgroundColor: "{colors.card}"
    textColor: "{colors.ink}"
    typography: "{typography.headline-small}"
    padding: "14px 20px"
  page-header-dark:
    backgroundColor: "{colors.card-dark}"
    textColor: "{colors.ink-dark}"
    padding: "14px 20px"
  card:
    backgroundColor: "{colors.card}"
    rounded: "{rounded.card}"
  card-dark:
    backgroundColor: "{colors.card-dark}"
    rounded: "{rounded.card}"
  data-table:
    backgroundColor: "{colors.card}"
    textColor: "{colors.ink}"
    typography: "{typography.table-cell}"
    rounded: "{rounded.block}"
    padding: "11px 18px"
  data-table-column-header:
    backgroundColor: "{colors.field-fill}"
    textColor: "{colors.ink-muted}"
    typography: "{typography.table-meta}"
    padding: "11px 18px"
  data-table-filter-chip:
    backgroundColor: "{colors.field-fill}"
    textColor: "{colors.ink}"
    rounded: "{rounded.chip}"
    padding: "0 12px"
    height: "32px"
  data-table-filter-chip-selected:
    backgroundColor: "rgba(2, 80, 211, 0.08)"
    textColor: "{colors.brand-blue}"
    rounded: "{rounded.chip}"
    padding: "0 12px"
    height: "32px"
  filter-pill:
    backgroundColor: "{colors.field-fill}"
    textColor: "{colors.ink}"
    rounded: "{rounded.control-lg}"
    padding: "0 13px"
    height: "40px"
  status-pill:
    rounded: "{rounded.pill}"
    padding: "4px 10px"
  status-pill-draft:
    backgroundColor: "rgba(245, 158, 11, 0.12)"
    textColor: "{colors.warning}"
    rounded: "{rounded.pill}"
    padding: "4px 10px"
  status-pill-posted:
    backgroundColor: "rgba(34, 197, 94, 0.12)"
    textColor: "{colors.success}"
    rounded: "{rounded.pill}"
    padding: "4px 10px"
  status-pill-cancelled:
    backgroundColor: "rgba(239, 68, 68, 0.12)"
    textColor: "{colors.error}"
    rounded: "{rounded.pill}"
    padding: "4px 10px"
  kpi-card:
    backgroundColor: "{colors.card}"
    textColor: "{colors.ink}"
    typography: "{typography.kpi-value}"
    rounded: "{rounded.card}"
    padding: "14px 16px"
  stat-tile:
    backgroundColor: "{colors.card}"
    rounded: "{rounded.tile}"
    padding: "12px"
  dialog:
    backgroundColor: "{colors.card}"
    rounded: "{rounded.dialog}"
    width: "760px"
  dialog-footer:
    backgroundColor: "{colors.field-fill}"
    padding: "13px 20px"
  form-grid-cell:
    backgroundColor: "transparent"
    rounded: "{rounded.control-lg}"
    padding: "6px 14px"
    height: "64px"
  report-tab:
    textColor: "{colors.ink-muted}"
    padding: "0 16px"
    height: "50px"
  report-tab-active:
    textColor: "{colors.brand-blue}"
    padding: "0 16px"
    height: "50px"
  action-bar:
    backgroundColor: "{colors.card}"
    padding: "10px 20px"
  sidebar:
    backgroundColor: "{colors.sidebar-slate}"
    textColor: "{colors.ink-dark}"
    width: "200px"
  sidebar-collapsed:
    backgroundColor: "{colors.sidebar-slate}"
    width: "56px"
  screen-tab:
    padding: "0 10px"
    height: "38px"
    width: "190px"
---

# Design System: PicPos

<!-- Extracted from code on branch go/full-remediation @ 55cc57dd (release 3.6.0+270).
     Normative sources: lib/core/theme/picpos_theme.dart, lib/core/theme/app_colors.dart,
     lib/core/design_system/*, lib/presentation/picpos_shell/*, test/structural/dark_mode_*.
     Items marked "(inferred)" are interpretation, not code fact. The North Star and color
     display names were not confirmed with the owner (the Impeccable Step 3 interview was
     not run in this pass). -->

## Overview

**Creative North Star: "The Ledger Desk"** *(inferred; not yet confirmed by the owner)*

PicPos is a working surface for cashiers and accountants who spend the whole day in it, so it is built to read as calm, flat and exact rather than decorative. The theme file states the intent itself: PicPos is deliberately the visual inverse of its sibling brand. It is flat, uses hairline borders, has corners of 12–16 px, casts **no shadows**, has a light top bar with a brand-blue bottom stripe, sets type one step larger (13–15 px), and uses filled, borderless fields. Every surface is a white (or deep-navy) card resting on a cool blue-grey canvas, separated by a 1 px hairline instead of a drop shadow. The comment in `picpos_theme.dart` gives the reason: a shadow on a cashier's screen all day reads as noise.

Density is high but legible. Tables are the bulk of the product, so rows are tall enough to hit with a mouse or a finger (44–54 px), numbers always use tabular figures, and Arabic body text gets generous line height (1.6–1.65) so diacritics and dots don't collide. The only saturated colour is the brand blue from the logo (`brand-blue`). It marks the single primary action, the active tab, the focused field, the selected row and the 2.5 px stripe under every page header.

The system is Arabic-first and bidirectional. Every screen frame sets `Directionality` from the user's language (`en` gives LTR, otherwise RTL), and spacing, alignment and accent borders are directional, so the same layout mirrors cleanly. Light and dark modes are both first-class. Dark mode is a **blue-navy** world (`canvas-dark`, `card-dark`), not neutral grey, so the brand stays present in both.

**Key Characteristics:**
- Flat surfaces with zero elevation; separation comes from 1 px hairlines and tonal steps (canvas → card → field).
- One brand blue on a cool blue-grey neutral ramp; semantic green/amber/red appear only as status.
- Cairo for all UI, with two theme weights (700 for headings and labels, 600 for body); shell widgets add 800 for numbers and titles.
- Rounded but not soft: 10 px controls, 14 px cards, 17–18 px blocks and dialogs, pills for status.
- Filled, borderless inputs that draw a 2 px blue frame only on focus.
- Directional by construction: `EdgeInsetsDirectional`, `AlignmentDirectional`, `BorderDirectional`.

## Colors

A cool, blue-tinted neutral system carrying a single logo-derived brand blue, with conventional semantic status colours.

### Primary
- **Logo Blue** (`brand-blue`): the brand voice, taken from the logo file. It is the filled primary button, focused-input frame, page-header bottom stripe (2.5 px), active tab underline, selected-row tint (α 0.06), selected-chip tint (α 0.08), table accent bar (3.5×15 px), scrollbar thumb (α 0.35 at rest, 0.75 on hover, 1.0 while dragged) and checkbox/switch "on". It is also the seed for `ColorScheme.fromSeed`.
- **Ledger Navy** (`brand-navy`): authority without saturation. Used for light-mode app-bar foreground, icon colour (21 px), outlined-button text, dialog titles, the solid **DataTable heading row** (both modes, white 13/700 text), tooltips, snackbars and date-picker headers.
- **Signal Sky** (`brand-sky`): the brand blue lifted for dark backgrounds. It is dark-mode `colorScheme.primary`, text-button colour, tab label/indicator and focused border. `AppColors.info` resolves to this same value for PicPos.
- **Night Ink Blue** (`brand-ink-dark`): `context.picposBrandInk` in dark mode, for brand-coloured *text and icons* on `card-dark` (light mode uses `brand-blue`).

### Secondary
- **Slate Rail** (`sidebar-slate`): the side navigation background (`AppColors.secondary`), shared with the sibling brand's shell.

### Neutral (light)
- **Morning Paper Canvas** (`canvas`): scaffold background. It's derived from the brand blue so white cards appear to "float" without shadows.
- **Card White** (`card`): cards, page header, data tables, dialogs, popup menus, app bar.
- **Field Wash** (`field-fill`): theme input fill, chip background and dialog footer/field fill, and the light value of `context.picposField` (`PicPosTheme.lightFieldFill`). Shell widgets use it for table column-title rows, totals rows, filter chips and pills, and read-only form cells. A pale blue that sets a writable area apart from the white card around it without a frame.
- **Theme Hairline** (`hairline`): every light border and divider: the theme's `dividerColor` and `dividerTheme`, cards, dialogs, outlined-button side at 1.5 px, chips, tab divider, and the light value of `context.picposHairline` (`PicPosTheme.lightHairline`) used by every `picpos_shell` widget border.
- *(Retired: `field-slate` #F8FAFC and `border-slate` #E2E8F0. They were `AppColors.surface` / `AppColors.border`, which still exist for the sibling brand but no longer feed the PicPos getters.)*
- **Ink** (`ink`): light-mode primary text, deliberately pure black for maximum readability.
- **Ink Secondary** (`ink-secondary`): `bodySmall`, labels and input labels, dialog body text.
- **Ink Muted** (`ink-muted`): light-mode `picposMuted`. Used for hints, column titles, sub-lines and unselected tabs.

### Neutral (dark)
- **Midnight Canvas** (`canvas-dark`), **Navy Card** (`card-dark`, which also equals `AppColors.cardDark` for PicPos), **Deep Field** (`field-fill-dark`), **Navy Hairline** (`hairline-dark`, which also equals `AppColors.borderDark` for PicPos), **White Ink** (`ink-dark`; secondary text is `white70`, unselected tabs `white54`) and **Mist Muted** (`ink-muted-dark`).

### Status
- **Posted Green** (`success`, dark `success-deep`), **Draft Amber** (`warning`, dark `warning-deep`), **Void Red** (`error`, dark `error-deep`). The theme-aware getters `AppColors.statusSuccess/Warning/Error/Info(context)` pick the deep variant in dark mode. Status pills draw the tone at α 0.12 fill, α 0.30–0.40 border and full-strength text. Trend arrows use `success`/`error`.
- Control one-offs: `switch-track-off` (light switch track) and `checkbox-outline` (light checkbox border).

### Named Rules
**The One Blue Rule.** The brand blue is the only saturated hue that is not a status. It marks *the* primary action, focus, selection and the page-header stripe. Tint it with alpha (0.04–0.14) for selected and soft states instead of introducing new blues.

**The Six Getters Rule.** Inside PicPos screens, surfaces and text come from `context.picposCard`, `picposField`, `picposHairline`, `picposText`, `picposMuted` and `picposBrandInk` (defined in `picpos_surface.dart`), or from the Theme (`cardColor`, `dividerColor`, `colorScheme`). Never use a light constant that stays light in dark mode.

**The Navy-Not-Grey Rule.** Dark mode is built on blue-navy (`canvas-dark` / `card-dark` / `field-fill-dark` / `hairline-dark`), never neutral grey, so the brand survives the mode switch.

## Typography

**UI Font:** Cairo (bundled: Regular, 500, 600, 700, 800, 900; served through `GoogleFonts.cairo` with `allowRuntimeFetching = false`)
**Numeric/Mono:** Cairo (`AppTypography.mono`), fallback Consolas, Courier New, monospace
**Print Font:** Noto Naskh Arabic (Regular/Bold) for PDF and thermal output; Cairo is only a symbol fallback

**Character:** Cairo's geometric Kufi-influenced forms keep Arabic and Latin on one consistent, sturdy line. The system runs it heavy (600 body, 700 headings, 800 for figures) because the owner asked for "bold and consistent for clarity".

### Hierarchy
- **Display** (700, 30 / 25 / 21 px): rarely used; large screen titles and hero numbers.
- **Headline** (700, 19 px `headlineMedium`, 17 px `headlineSmall`): the page-header title is `headlineSmall`, and app-bar and dialog titles are 17/700. Document headers use 19–20/800.
- **Title** (700, 16 / 15 / 14 px): section headers (15, bold) and card titles.
- **Body** (600, 15 / 14 px at line-height 1.65; `bodySmall` 13 px at 1.6 in muted ink): the text in tables, lists and cards. `bodyMedium` 14 px is the default reading size.
- **Label** (700, 14 / 13 / 12 px; medium and small use muted ink): button labels (14), chips (12/600), tooltips (12).
- **Shell micro-scale** (from `picpos_shell`): block titles 14.5/800; table cells 13/700 (800 when bold or end-aligned); column titles and chip labels 11.5/800; sub-lines 10.5–11.5/600; KPI values 19–25/800 at line-height 1.1–1.2. These sizes are set at the call site, not in the TextTheme.

### Named Rules
**The Two-Weights Rule.** The theme uses exactly two weights: 700 for headings and labels, 600 for body. All three on 700 erases hierarchy, and 400 reads faint next to bold headings. *(Drift: shell widgets add 800 for figures and titles; treat 800 as the "figure" weight and keep body text at 600.)*

**The Tabular Figures Rule.** Every amount, quantity, count and date range uses `FontFeature.tabularFigures()` so columns of numbers align.

**The Naskh-for-Paper Rule.** Printed and PDF documents use Noto Naskh Arabic as the base font. Never make Cairo the print base: it lacks 16 Arabic presentation forms (see `base_generator.dart`).

## Layout

- **Shell:** a side navigation (200 px expanded, 56 px collapsed, 0 when hidden; 200 ms width animation) plus a top bar of screen tabs (38 px high, tabs at most 190 px wide, horizontally scrollable because eight Arabic tabs overflow at 1366 px). The content area is the canvas.
- **Screen frame (`PicPosScreenScaffold`):** `Directionality` from locale, then page header, then optional sub-header (filter strip, report tabs), then optional toolbar, then body with directional padding 16/12/16/12.
- **Spacing rhythm:** a 4 px base (`Spacing` xs 4, sm 8, md 12, lg 16, xl 24, xxl 32, section 48, page 64). Shell widgets also use 18 px table gutters, 20 px page-header and dialog gutters, and 26 px gutters for filter and report strips. Typical gaps inside components are 6–13 px, and grids of cards use a 13 px gap.
- **Responsive model:** content-driven `LayoutBuilder` thresholds, not global breakpoints.
  - Form field grid: 4 columns at ≥1000 px, 3 at ≥640 px, otherwise 2.
  - Invoice and return forms: side-by-side panels and 20 px gutters at ≥960 px, otherwise stacked panels and 12 px gutters.
  - KPI row: 4 columns at ≥720 px, otherwise 2.
  - Dialog rows stack below 520 px.
  - Hub KPI tiles wrap at a minimum of 190 px, status-board columns at 250 px, entity cards at 340 px.
  - Data tables keep a 760 px minimum width and scroll horizontally below it.
- **Wrap over Row:** headers, action bars, filter strips and toolbars lay out with `Wrap` (spacing 8–12) so groups reflow instead of overflowing.
- **Target size:** the minimum supported window is **1366×768 with no overflow**. Redesign widget tests pump at `Size(1366, 768)`, and many screens also test a wide/narrow pair (`1500×900` / `820×760`).

## Elevation & Depth

PicPos is **flat by policy**. Every themed surface (`Card`, `AppBar`, `Dialog`, `PopupMenu`, FAB, buttons, date picker) sets `elevation: 0` and `surfaceTintColor: transparent`, and no widget in `lib/presentation/picpos_shell/` declares a `BoxShadow`. Depth comes from three tonal layers (canvas → card → field) plus 1 px hairlines. State uses alpha tints of the brand blue (hover/selected 0.06–0.14) and the 2–3 px blue strokes on focus, active tab and the header stripe.

### Shadow Vocabulary
- **Sidebar edge** (`BoxShadow(color: black α0.15, blurRadius: 6, offset: (-1, 0))`): the only shadow in the PicPos chrome, on the shared side navigation in `app_shell.dart`. Its offset is not mirrored for LTR.

### Named Rules
**The Hairline-Not-Shadow Rule.** Separate surfaces with a 1 px hairline (`picposHairline` / theme `dividerColor`) and a tonal step. If you are reaching for a shadow, use a border.

**The Stripe Rule.** Brand presence at the top of a screen is a 2.5 px `brand-blue` bottom border on a light (or navy) header. It is never a saturated filled bar.

## Shapes

Gently rounded rectangles with a clear ladder by size:

- 5 px: checkboxes.
- 8 px: text buttons, tooltips, table pills, quantity inputs.
- 9 px: table filter chips and in-cell buttons.
- 10 px: controls (buttons, inputs, list tiles, popup menus, snackbars, FAB).
- 11 px: form-grade buttons, filter pills, form-grid cells.
- 12 px: stat tiles, status-board cards, totals bar.
- 14 px: cards, KPI cards, panel boxes.
- 17 px: data-table and entity-card blocks.
- 18 px: dialogs and the date picker.
- Pill (999): status pills, toggle chips, badges and the theme `Chip` (`StadiumBorder`).

Borders are 1 px. Outlined buttons and selectable choices use 1.5 px, focus 2 px, tab indicators 2.5–3 px. Accent marks are small rectangles: a 3.5×15 px brand bar before block titles, and a 3 px *start-side* stripe on hub KPI cards (`BorderDirectional`, so it follows RTL/LTR). Icon badges are rounded squares with an α 0.09–0.12 tint (30–46 px, radius 9–14). Empty states are the only circle.

## Components

### Buttons
Confident and square-shouldered, with no lift.
- **Shape:** gently rounded (10 px theme; 11 px in document action bars).
- **Primary:** `brand-blue` fill, white 14/700 text, min 76×42, padding 10/20 (`ElevatedButton`). Document forms use `FilledButton` at min height 44, padding h18–22, radius 11, icon 16, label 13/800. The invoice primary carries an `F9` shortcut badge (onPrimary α 0.16, radius 5, 9.5/700).
- **Outlined (secondary):** transparent, 1.5 px hairline side, `brand-navy` text (white in dark), 14/600. In forms: min height 44, padding h14, radius 11, label 12.5/700.
- **Text:** `brand-blue` (`brand-sky` in dark), 13/700, min 56×38, radius 8. Used for Cancel and Preview.
- **Dialog footer set:** Cancel is a `TextButton` at 40 high in muted ink. Secondary is outlined, 40 high, card fill. Primary is elevated, 40 high, padding h20, 13.5/800, tinted with the dialog accent. Busy state swaps the icon for a 2 px spinner of the same size.
- **Semantic variants (`AppButton`):** primary / secondary (outlined) / danger (`error`, `error-deep` in dark) / warning. Foreground switches between white and black by estimated brightness.
- **Hover / Focus:** Material default ink ripple and overlay only; no custom hover styling in the shell.

### Chips
- **Theme chip:** stadium shape, `field-fill` background, 1 px hairline, 12/600 navy label, padding 12/6. Selected is `brand-blue` α 0.14 (α 0.30 in dark).
- **Table filter chip:** height 32, radius 9. Selected: blue α 0.08 fill, blue border, brand-ink text. Unselected: field fill, hairline border. Label 11.5/700 with a count at 10.5/800.
- **Filter pill (strip):** height 40, radius 11, 15 px icon, 12.5/700 label. When active it takes a `tone` (α 0.08 fill, tone border and text).
- **Status pill:** fully round, padding 4/10, tone α 0.12 fill, α 0.30–0.40 border, 6 px dot, label 11/700–800 in the tone. Presets: draft is `warning`, posted is `success`, cancelled is `error`, editing and transfer are `info`.
- **Toggle chip:** fully round, padding 6/11, selected tone α 0.12 with a tone border.

### Cards / Containers
- **Corner Style:** 14 px (content card, KPI card, form card, panel box); 17 px for table and entity blocks; 12 px for stat tiles and status cards.
- **Background:** `picposCard` (white or `card-dark`); nested and read-only regions use `picposField`.
- **Shadow Strategy:** none (see Elevation & Depth).
- **Border:** 1 px `picposHairline` on all sides.
- **Internal Padding:** 12–16 px (stat tile 12, KPI card 14/16, form card 14, entity header 16).
- **Block header:** a 3.5×15 px brand bar, 10–11 px gap, then title at 14.5/800 and subtitle at 11.5/600 muted. Header actions are end-aligned in a `Wrap` (spacing 7).

### Inputs / Fields
- **Style:** filled `field-fill` (`field-fill-dark` in dark), **no visible border** at rest, radius 10, content padding 13/14, dense, hint 13 muted, label 13 secondary.
- **Focus:** 2 px `brand-blue` frame (`brand-sky` in dark).
- **Error:** 1.5 px `error` frame at rest, 2 px when focused.
- **Form field grid (`PicPosFormGrid`):** 64 px cells, 1 px hairline, radius 11, gap 10. Each cell holds a 9.5/800 muted label with an 11 px icon (required `*` in `error`) above a 12.5/700 tabular value. Read-only cells take the `picposField` fill.
- **Dialog field:** 42 px high, field fill, radius 10, no border. Label 11/700 muted above it.

### Navigation
- **Side menu:** `sidebar-slate` background, 200/56 px width, 56 px header with the logo.
  - Group headers: 36 px high, 11/600–700 white text, letter-spacing 0.3, accordion caret.
  - Items: 34–40 px high, radius 6–10, icons 15–20.
  - Selected item: `brand-blue` α 0.25–0.30 with a 5 px blue dot or a 1.5 px border. Hover: white α 0.08 gradient.
- **Screen tabs:** 38 px high, max 190 px wide, 12/700 (active) or 12/500 text, 14 px icon. Active: blue α 0.12 fill with a 2 px blue bottom border. Hover: divider α 0.12.
- **Report tabs:** 50 px high, padding h16, 16 px icon, 13/800 (on) or 13/700 text. Active: 2.5 px `brand-blue` bottom border with brand-ink text; inactive text is muted. Count badges are fully round.
- **Theme TabBar:** 14/700 selected or 14/500 unselected, with a 3 px underline indicator spanning the tab.

### Page Header (signature)
`PicPosPageHeader`: a light (`picposCard`) bar with a **2.5 px `brand-blue` bottom border**, padding 14/20.
- **Start side:** optional back button (blue icon on α 0.08), then a 22 px icon in a blue α 0.10 badge (radius 12), then title (`headlineSmall`) and subtitle (`bodySmall`) on one line each.
- **End side:** a 28:72 split puts the search field (max 320 px) and actions there, in a reverse horizontal scroller.

### Data Table (signature)
`PicPosDataTable`: one card block (radius 17, hairline, min width 760). From top to bottom:
- **Header:** padding 14/18, with the block header and filter chips.
- **Column-title row:** `picposField`, 11.5/800 muted.
- **Rows:** padding 11/18 with hairline separators. Selected rows take blue α 0.06; tap feedback is an `InkWell`. There is no zebra striping.
- **Totals row:** `picposField`, 13.5/800 tabular.
- **Cell kinds:** text (+ 30 px tinted icon tile), status pill (tone α 0.09, radius 8), progress bar (7 px), trend (green/red arrow) and outlined in-cell button (30 high, 1.5 px tone border).
- **Plain `DataTable`:** the theme gives a solid **`brand-navy` heading row** with white 13/700 text, 46 px heading, 44–54 px rows and 24 px column spacing.

### Stat / KPI Cards
- **Stat tile:** radius 12, padding 12. A 13 px icon sits in a tint badge (radius 7), then a 19/bold label/value in the accent colour, then a ±% line in green or red.
- **KPI card (row):** 68 px tall, radius 14. A 34 px tinted icon box sits beside an 11/600 muted label and a 19/800 tabular value.
- **Hub KPI card:** padding 14/16, radius 14, with a **3 px start-side tone stripe**. It shows a 15 px icon and label, a 25/800 tabular value, and a trend delta.

### Action Bar
Document action bar on `cardColor`, with a 1 px top `dividerColor` border and directional padding 10/20 (12 below 960 px). A `Wrap` with space-between holds two groups: **primary first** (Save, Save & Print, Save Draft), then Preview and **Back**. Back's caret flips with text direction. The generic `PicPosFormActionBar` places Back at the start and draft and primary at the end.

### Dialog
`PicPosDialog`: transparent Material frame, card at radius 18 with a hairline border, default width 760 (680 for danger confirms, 560 for pickers, 520 for confirms), max height screen − 48.
- **Header:** padding 15/20, a 36 px accent icon tile, title 16/800 and a 32 px close box.
- **Body:** padding 16/20, gap 13.
- **Footer:** `picposField` fill, padding 13/20.

Danger confirms require typing a word, and list "will be deleted" in red and "will remain" in green.

## Do's and Don'ts

### Do:
- **Do** take every surface and text colour from `context.picposCard` / `picposField` / `picposHairline` / `picposText` / `picposMuted` / `picposBrandInk` or the Theme (`cardColor`, `dividerColor`, `colorScheme`). `test/structural/dark_mode_surface_tokens_test.dart` enforces this across the PicPos screen folders.
- **Do** branch any unavoidable literal on `isDark ?` / `Brightness.dark` on the same line, or annotate it with a `// dark-ok: <reason>` marker. These are the only escapes `dark_mode_guard_test.dart` accepts.
- **Do** keep text contrast at ≥ 3.0 against its background in dark mode (`dark_mode_smoke_test.dart`), and ≥ 4.5 for POS card labels and values (`picpos_pos_dark_mode_test.dart`).
- **Do** use directional geometry (`EdgeInsetsDirectional`, `AlignmentDirectional`, `BorderDirectional`, `Positioned.directional`) and flip back/forward carets by `TextDirection`, as the invoice and return action bars do.
- **Do** route every user-visible string through `tr()` and every user-entered or seeded data name through `trData()`. Every `tr` key must exist in `assets/i18n/en.json` (`i18n_coverage_test.dart`).
- **Do** verify new screens at `Size(1366, 768)` with no overflow. Prefer `Wrap` for header, toolbar and action groups, and give tables a minimum width with horizontal scroll.
- **Do** use `FontFeature.tabularFigures()` for every number, and Cairo through the theme for all UI text.
- **Do** keep elevation at 0 and separate with hairlines. Express selection and hover as brand-blue alpha tints (0.06–0.14).
- **Do** keep the brand blue `#0250D3` / navy `#012258` exactly as defined; `brand_picpos_test.dart` pins them.

### Don't:
- **Don't** paint surfaces with `Colors.white`, `Color(0xFFFFFFFF)`, `Colors.grey.shade50/100/200`, or any hex whose channels are all ≥ `0xD8` (`dark_mode_guard_test.dart`).
- **Don't** use `AppColors.card` / `surface` / `border` / `background` / `posCard` / `posBackground`, or the hexes `#F4F7FC`, `#F8F9FA`, `#F8FAFC`, `#E2E8F0`, as literals in scoped PicPos screens. They stay light in dark mode (`dark_mode_surface_tokens_test.dart`). Use the theme or the `picpos*` getters, which resolve them per mode.
- **Don't** colour text with `Colors.black` / `black87` / `black54` or a dark hex (every channel ≤ `0x80`) inside a `TextStyle`. It disappears on `card-dark`.
- **Don't** add `BoxShadow`s or non-zero elevation to PicPos surfaces, and don't fill the top bar with saturated brand colour. Use the 2.5 px stripe.
- **Don't** introduce any trace of the sibling brand. Its teal (`#2B737F`, `#134657`, `#469CA5`, `#1E4A5A`) is forbidden in PicPos colour slots (`brand_picpos_test.dart`).
- **Don't** build regexes or descriptions from translated text (`RegExp(tr(...))`, `description: tr(...)`), per `i18n_runtime_safety_test.dart`.
- **Don't** make Cairo the base font of printed or PDF documents. Use Noto Naskh Arabic.

### Known drift (observed, not yet rules)
- `AppColors.primary` is used for foreground icons where `picposBrandInk` would be dark-aware.
- `picposMuted` is duplicated as a free function in `picpos_kpi_row.dart` and `picpos_dialog.dart`.

### Resolved drift
- **One hairline, one field fill.** `picposHairline` and `picposField` now resolve to the theme's own light tokens (`hairline` #DCE3EE, `field-fill` #F4F7FC) through `PicPosTheme.lightHairline` / `lightFieldFill`. `picposDialogField` uses the same fill. The PicPos theme also sets `dividerColor` to the hairline (before, Material derived a darker `outline` grey). Dark values are unchanged, and the sibling brand's `AppColors.border` / `surface` were not touched. Guarded by `test/widget/picpos_shell_known_drift_test.dart`.
- **Fixed light-grey text.** `PicPosStatTile`, `PicPosSectionHeader`, `PicPosEmptyState`, `PicPosFormActionBar` and `PicPosTotalsBar` take their muted and secondary text from `picposMuted` (and `white70` for secondary text in dark). Dark contrast is ≥ 4.5 on `card-dark`.
- **Untranslated shell defaults.** Default labels («رجوع», «إلغاء», «تأكيد», «تطبيق», «الملف الكامل», «سيُحذف», «سيبقى كما هو») are now `null` defaults resolved with `tr()` at render time, so English shows Back / Cancel / Confirm / Apply.
- **Back arrows.** `PicPosPageHeader` uses `Icons.arrow_back` and `PicPosFormActionBar` uses `Icons.chevron_left`. Both carry `matchTextDirection`, so they point to the line start in both directions: → in RTL and ← in LTR. The old `arrow_forward` / `chevron_right` pointed to the line end in both directions.
