# English catalog Arabic-value allowlist

`assets/i18n/en.json` must not contain Arabic letters in English values except for the exact values below. `test/unit/i18n_catalog_quality_test.dart` enforces this list.

- `[أإآ]` is a normalization regular-expression token, not UI copy.
- `ء`, `ؤ`, `ئ`, `ا`, `ب`, `ة`, `ت`, `ث`, `ج`, `ح`, `خ`, `د`, `ذ`, `ر`, `ز`, `س`, `ش`, `ص`, and `ض` are literal keys on the intentionally Arabic on-screen keyboard. They must remain Arabic in every UI locale.

Arabic-Indic digits (`٠`–`٩`, `۰`–`۹`, `٫`) and the Arabic comma inside the digit-normalization pattern `[0-9.٠-٩٫،,]` are not letters, so the letter check does not flag them; those keys are digit-normalization tokens or sample figures, and the English sweep (`test/widget/i18n_all_screens_english_sweep_test.dart`) still fails if any of them reaches an English screen.

The language-picker label `العربية` is intentionally visible in Arabic UI surfaces, but its English catalog value is `Arabic`, so it does not require a catalog exception.
