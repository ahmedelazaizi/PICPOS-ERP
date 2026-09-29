# Arabic literal codemod skip list

`tool/i18n/wrap_arabic_literals.dart` only scans the UI roots requested for Phase 10a. It skips literals that are not UI copy. Adjacent and literal-plus concatenations are merged into one `tr(...)` template before these rules are applied:

- map keys, switch/case expressions, annotation arguments, default parameter values, and import/part directives;
- literal groups that cannot be represented as a single UI template are reported as `unsupported_literal`;
- `print`, `debugPrint`, logger/diagnostic calls, thrown exception expressions, and assertion messages;
- SQL-like text, setting keys, permission/data codes, URLs, file paths, and identifier-like ASCII values;
- generated or embedded-print paths: `lib/services/print*`, PDF/ESC-POS generators, and invoice template paths;
- non-UI implementation roots: `lib/core/utils/**` and `lib/presentation/widgets/touch_keyboard/**`;
- normalization tokens consisting only of one character, digits, punctuation, or Arabic number separators;
- literals used by `RegExp`, `replaceAll`, `replaceAllMapped`, `replaceFirst`, `split`, `contains`, `startsWith`, `endsWith`, `indexOf`, `codeUnitAt`, or equality comparisons;
- literals on a line or immediately after a line comment containing `i18n-ignore`;
- `description`/`notes` arguments passed to `createSafeTransaction`, `createJournalEntry`, or `insert*` write calls, because persisted ledger/audit text must remain in the company language;
- `lib/core/i18n` itself, so the runtime catalog and tools are never rewritten.

Skipped literals are counted by category in the codemod summary. The codemod is idempotent: existing `tr(...)` calls are never considered string literals to wrap. `--unwrap-non-ui` removes legacy wrappers from the non-UI contexts above, while `--make-locale-getters` converts locale-sensitive top-level/static finals into getters so they are evaluated after a locale change.
