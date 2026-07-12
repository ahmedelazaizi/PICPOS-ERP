# URAL-ERP Architecture — God File Decomposition Plan

> **Version:** 1.0 — March 2026
> **Status:** Active — P1 for next release cycle

---

## Current God Files (> 40K)

| File | Size | Decomposition Target |
|---|---|---|
| `pos_table_service_screen.dart` | 59K | 6 widgets + 1 controller |
| `users_management_screen.dart` | 52K | 4 widgets + 1 state manager |

These files are **too risky to split mid-trial release**. They are documented here
for the next major release cycle.

---

## `pos_table_service_screen.dart` — Target Decomposition

```
lib/presentation/pos/
├── pos_table_service_screen.dart    ← Shell (~200 lines)
├── widgets/
│   ├── service_header_bar.dart       ← Header + search
│   ├── service_item_list.dart        ← Product grid/list
│   ├── service_cart_panel.dart       ← Cart + totals
│   ├── service_payment_sheet.dart    ← Payment modal
│   ├── service_actions_bar.dart      ← Hold/print/discount
│   └── service_customer_panel.dart   ← Customer selector
└── controllers/
    └── pos_service_controller.dart   ← Business logic
```

---

## `users_management_screen.dart` — Target Decomposition

```
lib/presentation/screens/users/
├── users_management_screen.dart   ← Shell (~200 lines)
├── widgets/
│   ├── user_list_panel.dart        ← User table + filters
│   ├── user_form_dialog.dart       ← Create/edit user
│   ├── user_permissions_panel.dart  ← Permission tree
│   └── role_management_panel.dart   ← Role CRUD
└── providers/
    └── users_state_provider.dart    ← State management
```

---

## Completed Decompositions

| File | Original | After | Date |
|---|---|---|---|
| `tables_screen.dart` | 68K | 7K + 4 part files | 2026-03-16 |

---

## Architectural Principles

1. **No UI → DB Direct Access** — All screens use Repository providers only
2. **Part files** for large screens — `part of` directive for phased decomposition
3. **Widget extraction** first, controller extraction second
4. **Max file target:** < 500 lines per widget, < 1000 lines per screen
