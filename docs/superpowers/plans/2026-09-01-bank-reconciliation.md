# المطابقة البنكيّة — خطّةُ التنفيذ

> **للعامل الوكيل:** مهارةٌ فرعيّةٌ مطلوبة: استعمل
> `superpowers:subagent-driven-development` (موصى به) أو
> `superpowers:executing-plans` لتنفيذ هذه الخطّة مهمّةً مهمّة. الخطواتُ
> بصيغة `- [ ]` للتتبّع.

**الهدف:** أن يستطيع المحاسبُ استيرادَ كشفِ بنكٍ ومطابقتَه آليّاً ويدويّاً
وإقفالَ جلسةٍ بفرقٍ مفسَّر — من تبويبةٍ تاسعةٍ في حاوية الحسابات.

**المعماريّة:** المحرّكُ (`bank_reconciliation_dao`) جاهزٌ ومختبَرٌ ولا
يُلمَس. تُكشَف سبعُ دوالِّ تمريرٍ عبر `IAccountingRepository`، ويُضاف زوجُ
«قالب/استيراد» في `ExcelService` على نمط مستورداته الثلاثة، وتُبنى شاشةٌ
بهويّة PicPos تصير التبويبةَ التاسعة — وتُحذف الشاشةُ القديمةُ المُحاكية.

**المواصفة:** `docs/superpowers/specs/2026-09-01-bank-reconciliation-design.md`

**التقنيّات:** Flutter · Riverpod 3 · drift · حزمة `excel` · صدفةُ PicPos.

## قيودٌ عامّة

- **المتابعةُ بالعربيّة** في النثر؛ الرموزُ والأوامرُ بالإنجليزيّة.
- **ممنوع `dart format`** — المستودعُ غير مضبوطٍ عليه.
- **خطُّ أساس `analyze`: ٦ info بالضبط**، صفرُ أخطاءٍ وتحذيرات. أيُّ زيادةٍ
  إخفاق.
- **صلاحيةُ التبويبة `settings_view`** — والحارسُ يشترط
  `tab.permission == screenPermissionMap[tab.screenId]`.
- **`ScreenId.bankReconciliation(53)` موجودٌ سلفاً** — لا يُخترَع رقمٌ جديد.
- **ممنوع `git add -A`** — كوّم بمسارٍ صريح؛ في جذر المستودع أربعةُ مجلّداتٍ
  غيرِ متتبَّعةٍ لا علاقةَ لها بالعمل.
- **الاختبارُ يُثبَت بطفرة**: أعِد العطبَ، اقِس أنّ المقصودَ سقط **وحدَه**،
  استعِد، وتحقّق بـ`md5sum`.
- **ولكلّ حارسٍ مرساةٌ** تُثبت أنّ الاستخراجَ يعمل — لا أنّ الرقمَ خرج.

---

## بنيةُ الملفّات

| الملفّ | المسؤوليّة |
|---|---|
| `lib/domain/repositories/accounting_repository.dart` | +٧ تواقيعَ في قسم Bank Reconciliation |
| `lib/data/repositories/drift_accounting_repository.dart` | +٧ تنفيذاتِ تمريرٍ خالص |
| `lib/data/services/bank_statement_row.dart` | **جديد** — تحليلُ صفِّ الكشف، دالّةٌ نقيّةٌ بلا قاعدةٍ ولا ملفّ |
| `lib/data/services/excel_service.dart` | +`exportBankStatementTemplate` و`importBankStatement` |
| `lib/presentation/accounting_picpos/bank_reconciliation_picpos_screen.dart` | **جديد** — الشاشةُ كلُّها |
| `lib/presentation/accounting_picpos/accounting_hub_picpos_screen.dart` | +تبويبةُ `bank` |
| `lib/data/providers/auth_providers.dart` | +`screenPermissionMap[bankReconciliation]` |
| `lib/core/navigation/screen_registry.dart` | +`ScreenId.bankReconciliation` في `unified` |
| `lib/presentation/screens/bank_reconciliation_screen.dart` | **يُحذَف** |

---

## Task 1: كشفُ المحرّك عبر المستودع

**Files:**
- Modify: `lib/domain/repositories/accounting_repository.dart` (قسم `// ── Bank Reconciliation ──`)
- Modify: `lib/data/repositories/drift_accounting_repository.dart` (بجوار `createReconciliation`)
- Test: `test/unit/bank_reconciliation_repository_test.dart` (جديد)

**Interfaces:**
- Consumes: `bank_reconciliation_dao` كما هو — صفرُ تغيير.
- Produces: سبعُ دوالَّ على `IAccountingRepository` تستهلكها المهامُّ ٣–٦:
  `importBankStatementLines` · `getUnmatchedStatementLines` ·
  `getStatementLines` · `autoMatchStatementLines` · `manualMatchStatement` ·
  `unmatchStatement` · `getReconciliationReport`.

- [ ] **Step 1: اكتب الاختبارَ الساقط**

`test/unit/bank_reconciliation_repository_test.dart`:

```dart
// المستودعُ كان يكشف ٣ دوالَّ من ١٠ — فالاستيرادُ والمطابقةُ والتقريرُ
// محجوبةٌ عن كلّ شاشة. وهذا يقيس **الوصولَ** لا المنطق: المنطقُ مختبَرٌ في
// `bank_reconciliation_posted_and_match_test`.
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/data/database/database.dart';
import 'package:picpos_erp/data/repositories/drift_accounting_repository.dart';
import 'package:picpos_erp/domain/entities/accounting_entities.dart';

void main() {
  late AppDatabase db;
  late DriftAccountingRepository repo;
  late int bankId;
  late int cashId;

  setUp(() async {
    db = AppDatabase.forTesting();
    repo = DriftAccountingRepository(db);
    cashId = (await db.getAccountByCode('1110'))!.id;
    bankId = await db.createAccount(
        code: '1120', name: 'البنك', accountType: 'asset');
  });

  tearDown(() => db.close());

  test('مرساة: المستودعُ يبني على نفس القاعدة', () async {
    expect(await repo.getReconciliationSessions(), isEmpty);
  });

  test('🔴 الاستيرادُ يصل المحرّكَ عبر المستودع', () async {
    final n = await repo.importBankStatementLines(
      bankAccountId: bankId,
      batchId: 'B-1',
      lines: [
        {
          'date': DateTime(2026, 5, 10),
          'reference': 'R1',
          'description': 'إيداع',
          'debit': 0.0,
          'credit': 500.0,
          'balance': 500.0,
        }
      ],
    );

    expect(n, 1);
    expect(await repo.getUnmatchedStatementLines(bankId), hasLength(1));
  });

  test('🔴 المطابقةُ الآليّةُ تصل المحرّكَ عبر المستودع', () async {
    await db.createJournalEntry(
      description: 'إيداع',
      date: DateTime(2026, 5, 10),
      lines: [
        JournalLine(accountId: bankId, debit: 500),
        JournalLine(accountId: cashId, credit: 500),
      ],
    );
    await repo.importBankStatementLines(
      bankAccountId: bankId,
      batchId: 'B-2',
      lines: [
        {
          'date': DateTime(2026, 5, 11),
          'reference': 'R2',
          'description': 'إيداع',
          'debit': 0.0,
          'credit': 500.0,
          'balance': 500.0,
        }
      ],
    );

    expect(await repo.autoMatchStatementLines(bankId), 1);
    expect(await repo.getUnmatchedStatementLines(bankId), isEmpty);
  });

  test('🔴 اليدويّةُ والنزعُ والتقريرُ تصل كلُّها', () async {
    await db.createJournalEntry(
      description: 'إيداع',
      date: DateTime(2026, 5, 10),
      lines: [
        JournalLine(accountId: bankId, debit: 900),
        JournalLine(accountId: cashId, credit: 900),
      ],
    );
    final jeLine = await (db.select(db.journalEntryLines)
          ..where((l) => l.accountId.equals(bankId))
          ..limit(1))
        .getSingle();

    await repo.importBankStatementLines(
      bankAccountId: bankId,
      batchId: 'B-3',
      lines: [
        {
          'date': DateTime(2026, 5, 20),
          'reference': 'R3',
          'description': 'إيداع بعيدُ التاريخ',
          'debit': 0.0,
          'credit': 900.0,
          'balance': 900.0,
        }
      ],
    );
    final stmt = (await repo.getUnmatchedStatementLines(bankId)).single;

    await repo.manualMatchStatement(
        statementLineId: stmt.id, journalLineId: jeLine.id);
    expect(await repo.getUnmatchedStatementLines(bankId), isEmpty);

    await repo.unmatchStatement(stmt.id);
    expect(await repo.getUnmatchedStatementLines(bankId), hasLength(1));

    final reconId = await repo.createReconciliation(
      bankAccountId: bankId,
      periodStart: DateTime(2026, 5, 1),
      periodEnd: DateTime(2026, 5, 31),
      statementBalance: 900,
    );
    final report = await repo.getReconciliationReport(reconId);
    expect(report['bookBalance'], 900.0);
    expect(report['unmatchedBankLines'], hasLength(1));
  });

  test('وأسطرُ فترةٍ تُقرأ بالمدى', () async {
    await repo.importBankStatementLines(
      bankAccountId: bankId,
      batchId: 'B-4',
      lines: [
        {
          'date': DateTime(2026, 5, 10),
          'reference': 'داخل',
          'description': '',
          'debit': 0.0,
          'credit': 10.0,
          'balance': 10.0,
        },
        {
          'date': DateTime(2026, 7, 10),
          'reference': 'خارج',
          'description': '',
          'debit': 0.0,
          'credit': 20.0,
          'balance': 30.0,
        },
      ],
    );

    final rows = await repo.getStatementLines(
      bankAccountId: bankId,
      from: DateTime(2026, 5, 1),
      to: DateTime(2026, 5, 31),
    );
    expect(rows.map((r) => r.reference), ['داخل']);
  });
}
```

- [ ] **Step 2: شغّله وتأكّد أنّه يسقط**

```bash
flutter test test/unit/bank_reconciliation_repository_test.dart
```

المتوقَّع: إخفاقُ **ترجمة** — `The method 'importBankStatementLines' isn't
defined for the type 'DriftAccountingRepository'`.

- [ ] **Step 3: أضِف التواقيعَ السبعةَ إلى الواجهة**

في `lib/domain/repositories/accounting_repository.dart` مباشرةً بعد
`Future<void> completeReconciliation(int reconciliationId);`:

```dart
  // ⚠️ السبعُ أدناه كانت **محجوبةً**: المحرّكُ يحملها منذ البداية والمستودعُ
  //    يكشف ثلاثاً، فبقيت المطابقةُ الفعليّةُ غيرَ مبلوغةٍ من أيّ شاشة.
  //    ولا يُستثنى شيءٌ «لأنّه غيرُ مستعمَلٍ الآن» — ذلك عينُ ما أماتها.

  /// يُدرج أسطرَ كشفٍ مستورَدة. كلُّ سطرٍ خريطةٌ بمفاتيح
  /// `date` · `reference` · `description` · `debit` · `credit` · `balance`.
  Future<int> importBankStatementLines({
    required int bankAccountId,
    required List<Map<String, dynamic>> lines,
    required String batchId,
  });

  /// أسطرُ الكشف غيرُ المطابَقة لحسابٍ بنكيّ.
  Future<List<BankStatementLine>> getUnmatchedStatementLines(int bankAccountId);

  /// أسطرُ الكشف في مدىً — مطابَقةً كانت أو لا.
  Future<List<BankStatementLine>> getStatementLines({
    required int bankAccountId,
    required DateTime from,
    required DateTime to,
  });

  /// مطابقةٌ آليّةٌ بالمبلغ و±٣ أيّام. تعيد عددَ ما طوبق.
  Future<int> autoMatchStatementLines(int bankAccountId);

  /// مطابقةٌ يدويّة. **ترمي `StateError`** إن كان سطرُ القيد مطابَقاً سلفاً
  /// لسطرِ كشفٍ آخر — والرسالةُ تسمّيه.
  Future<void> manualMatchStatement({
    required int statementLineId,
    required int journalLineId,
  });

  /// نزعُ مطابقةِ سطرِ كشف.
  Future<void> unmatchStatement(int statementLineId);

  /// تقريرُ جلسةٍ: الأرصدةُ والفرقُ والمطابَقُ وغيرُ المطابَق من الجانبَين.
  /// المفاتيح: `reconciliation` · `statementBalance` · `bookBalance` ·
  /// `difference` · `matchedCount` · `unmatchedCount` · `matchedLines` ·
  /// `unmatchedBankLines` · `outstandingBookEntries`.
  Future<Map<String, dynamic>> getReconciliationReport(int reconciliationId);
```

- [ ] **Step 4: أضِف التنفيذاتِ السبعةَ — تمريرٌ خالصٌ بلا منطق**

في `lib/data/repositories/drift_accounting_repository.dart` بعد
`completeReconciliation`:

```dart
  @override
  Future<int> importBankStatementLines({
    required int bankAccountId,
    required List<Map<String, dynamic>> lines,
    required String batchId,
  }) =>
      _db.importBankStatementLines(
        bankAccountId: bankAccountId,
        lines: lines,
        batchId: batchId,
      );

  @override
  Future<List<BankStatementLine>> getUnmatchedStatementLines(
          int bankAccountId) =>
      _db.getUnmatchedStatementLines(bankAccountId);

  @override
  Future<List<BankStatementLine>> getStatementLines({
    required int bankAccountId,
    required DateTime from,
    required DateTime to,
  }) =>
      _db.getStatementLines(
        bankAccountId: bankAccountId,
        from: from,
        to: to,
      );

  @override
  Future<int> autoMatchStatementLines(int bankAccountId) =>
      _db.autoMatchStatementLines(bankAccountId);

  @override
  Future<void> manualMatchStatement({
    required int statementLineId,
    required int journalLineId,
  }) =>
      _db.manualMatchStatement(
        statementLineId: statementLineId,
        journalLineId: journalLineId,
      );

  @override
  Future<void> unmatchStatement(int statementLineId) =>
      _db.unmatchStatement(statementLineId);

  @override
  Future<Map<String, dynamic>> getReconciliationReport(int reconciliationId) =>
      _db.getReconciliationReport(reconciliationId);
```

- [ ] **Step 5: شغّل الاختبارَ وتأكّد أنّه يمرّ**

```bash
flutter test test/unit/bank_reconciliation_repository_test.dart
```

المتوقَّع: ‏٥ ناجحة.

- [ ] **Step 6: تأكّد أنّ التحليلَ لم يتحرّك**

```bash
flutter analyze lib/domain/repositories/accounting_repository.dart lib/data/repositories/drift_accounting_repository.dart test/unit/bank_reconciliation_repository_test.dart
```

المتوقَّع: `No issues found!`

- [ ] **Step 7: كوّم**

```bash
git add lib/domain/repositories/accounting_repository.dart lib/data/repositories/drift_accounting_repository.dart test/unit/bank_reconciliation_repository_test.dart
git commit -m "feat(accounting): كشفُ محرّك المطابقة البنكيّة عبر المستودع"
```

---

## Task 2: تحليلُ صفِّ الكشف — دالّةٌ نقيّة

**Files:**
- Create: `lib/data/services/bank_statement_row.dart`
- Test: `test/unit/bank_statement_row_test.dart`

**Interfaces:**
- Consumes: لا شيء — نقيّةٌ تماماً.
- Produces: `BankStatementRowResult parseBankStatementRow(List<dynamic> cells)`
  تستهلكها المهمّةُ ٣.

- [ ] **Step 1: اكتب الاختبارَ الساقط**

`test/unit/bank_statement_row_test.dart`:

```dart
// تحليلُ صفِّ الكشف نقيٌّ عن قصد — كـ`reportCellValue` و`reportBranchLabel`:
// موضعُ الكذب المحتمل يجب أن يُقاس بلا قاعدةٍ ولا نظامِ ملفّات.
//
// ⚠️ **«مدين/دائن» من منظور البنك**: المحرّكُ يقلبهما عند المطابقة (مدينُ
// البنك = دائنُ دفترنا). فالتحليلُ ينقل ما في العمودَين كما هو، والقالبُ
// يحمل سطرَ الشرح.
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/data/services/bank_statement_row.dart';

void main() {
  test('مرساة: صفٌّ سليمٌ يُقبَل بحقوله', () {
    final r = parseBankStatementRow(
        [DateTime(2026, 5, 10), 'REF-1', 'إيداع نقدي', 0, 500]);

    expect(r.error, isNull, reason: 'الصفُّ السليمُ يجب أن يُقبَل');
    expect(r.line!['reference'], 'REF-1');
    expect(r.line!['credit'], 500.0);
    expect(r.line!['debit'], 0.0);
    expect(r.line!['date'], DateTime(2026, 5, 10));
  });

  test('التاريخُ نصّاً `yyyy-MM-dd` يُقبَل', () {
    final r = parseBankStatementRow(['2026-05-10', 'R', '', 0, 5]);
    expect(r.error, isNull);
    expect(r.line!['date'], DateTime(2026, 5, 10));
  });

  test('🔴 تاريخٌ فاسدٌ يُرفَض بسببه لا يُطرَح', () {
    final r = parseBankStatementRow(['العاشر من مايو', 'R', '', 0, 5]);
    expect(r.line, isNull);
    expect(r.error, contains('التاريخ'));
  });

  test('🔴 مدينٌ ودائنٌ معاً يُرفَض', () {
    final r = parseBankStatementRow([DateTime(2026, 5, 10), 'R', '', 100, 50]);
    expect(r.line, isNull);
    expect(r.error, contains('مدين'));
  });

  test('🔴 صفرٌ في الاثنين يُرفَض — سطرٌ بلا حركة', () {
    final r = parseBankStatementRow([DateTime(2026, 5, 10), 'R', '', 0, 0]);
    expect(r.line, isNull);
    expect(r.error, isNotNull);
  });

  test('صفٌّ أقصرُ من خمسةِ أعمدةٍ يُرفَض ولا يرمي', () {
    final r = parseBankStatementRow([DateTime(2026, 5, 10), 'R']);
    expect(r.line, isNull);
    expect(r.error, isNotNull);
  });

  test('المبلغُ السالبُ يُرفَض — الإشارةُ يحملها العمود', () {
    final r = parseBankStatementRow([DateTime(2026, 5, 10), 'R', '', 0, -5]);
    expect(r.line, isNull);
    expect(r.error, isNotNull);
  });
}
```

- [ ] **Step 2: شغّله وتأكّد أنّه يسقط**

```bash
flutter test test/unit/bank_statement_row_test.dart
```

المتوقَّع: إخفاقُ تحميل — `Target of URI doesn't exist: bank_statement_row.dart`.

- [ ] **Step 3: اكتب الدالّة**

`lib/data/services/bank_statement_row.dart`:

```dart
/// نتيجةُ تحليلِ صفٍّ من قالب كشف البنك.
///
/// إمّا [line] خريطةً جاهزةً لـ`importBankStatementLines`، وإمّا [error]
/// سبباً نصّيّاً يُعرَض للمحاسب. لا ثالثَ لهما، ولا يُطرَح صفٌّ بصمت.
class BankStatementRowResult {
  const BankStatementRowResult.ok(this.line) : error = null;
  const BankStatementRowResult.bad(this.error) : line = null;

  final Map<String, dynamic>? line;
  final String? error;
}

/// يحلّل صفَّ خلايا من قالب الكشف: التاريخ · المرجع · البيان · مدين · دائن.
///
/// ⚠️ **«مدين/دائن» من منظور البنك** — يُنقَلان كما هما، والمحرّكُ يقلبهما
/// عند المطابقة.
///
/// نقيّةٌ عن قصد: تُقاس بلا قاعدةٍ ولا نظامِ ملفّات، كـ`reportCellValue`.
BankStatementRowResult parseBankStatementRow(List<dynamic> cells) {
  if (cells.length < 5) {
    return const BankStatementRowResult.bad('الصفُّ ناقصٌ — يلزم خمسةُ أعمدة');
  }

  final date = _asDate(cells[0]);
  if (date == null) {
    return const BankStatementRowResult.bad('التاريخُ غيرُ مقروء');
  }

  final debit = _asAmount(cells[3]);
  final credit = _asAmount(cells[4]);
  if (debit == null || credit == null) {
    return const BankStatementRowResult.bad('المبلغُ غيرُ مقروءٍ أو سالب');
  }
  if (debit > 0 && credit > 0) {
    return const BankStatementRowResult.bad(
        'مدينٌ ودائنٌ في صفٍّ واحد — الحركةُ في عمودٍ واحدٍ لا اثنين');
  }
  if (debit == 0 && credit == 0) {
    return const BankStatementRowResult.bad('صفٌّ بلا حركة');
  }

  return BankStatementRowResult.ok({
    'date': date,
    'reference': cells[1]?.toString().trim(),
    'description': cells[2]?.toString().trim(),
    'debit': debit,
    'credit': credit,
    'balance': 0.0,
  });
}

DateTime? _asDate(dynamic v) {
  if (v is DateTime) return DateTime(v.year, v.month, v.day);
  final s = v?.toString().trim() ?? '';
  if (s.isEmpty) return null;
  final parsed = DateTime.tryParse(s);
  if (parsed == null) return null;
  return DateTime(parsed.year, parsed.month, parsed.day);
}

/// `null` = غيرُ مقروءٍ أو سالب. والإشارةُ يحملها **العمود** لا الرقم.
double? _asAmount(dynamic v) {
  if (v == null) return 0;
  if (v is num) return v < 0 ? null : v.toDouble();
  final s = v.toString().trim();
  if (s.isEmpty) return 0;
  final n = double.tryParse(s.replaceAll(',', ''));
  if (n == null || n < 0) return null;
  return n;
}
```

- [ ] **Step 4: شغّل الاختبارَ وتأكّد أنّه يمرّ**

```bash
flutter test test/unit/bank_statement_row_test.dart
```

المتوقَّع: ‏٧ ناجحة.

- [ ] **Step 5: أثبت الحارسَ بطفرة**

انسخ الملفَّ احتياطاً، ثمّ اجعل شرطَ «مدينٌ ودائنٌ معاً» يقبل دائماً
(`if (false && debit > 0 && credit > 0)`)، وشغّل:

```bash
flutter test test/unit/bank_statement_row_test.dart
```

المتوقَّع: يسقط اختبارُ «مدينٌ ودائنٌ معاً» **وحدَه**. ثمّ استعِد الملفَّ
وتحقّق بـ`md5sum` أنّه عاد كما كان، وأعِد التشغيلَ فتعود السبعُ خضراء.

- [ ] **Step 6: كوّم**

```bash
git add lib/data/services/bank_statement_row.dart test/unit/bank_statement_row_test.dart
git commit -m "feat(accounting): تحليلُ صفِّ كشف البنك — دالّةٌ نقيّةٌ بأسبابِ رفضٍ منطوقة"
```

---

## Task 3: قالبُ Excel واستيرادُه

**Files:**
- Modify: `lib/data/services/excel_service.dart`
- Test: `test/unit/bank_statement_import_test.dart`

**Interfaces:**
- Consumes: `parseBankStatementRow` من المهمّة ٢ ·
  `importBankStatementLines` من المهمّة ١.
- Produces: `BankStatementRowsSummary` (‏`lines` و`errors`) · وعلى
  `ExcelService`: `Future<String?> exportBankStatementTemplate()` و
  `Future<BankStatementRowsSummary?> pickAndParseBankStatement()`
  تستهلكهما المهمّةُ ٥.

⚠️ **`ExcelService` يأخذ مستوداتٍ لا قاعدة** (‏`ExcelService(productRepo,
partyRepo, branchRepo, purchasesRepo, {...})`)، فالتحليلُ وحدَه هنا
والكتابةُ في الشاشة بـ`repo.importBankStatementLines` من المهمّة ١.

- [ ] **Step 1: اكتب الاختبارَ الساقط**

`test/unit/bank_statement_import_test.dart`:

```dart
// الاستيرادُ يُبلّغ بعددَي المُدرَج والمرفوض — والصفُّ المرفوضُ يُقال بسببه.
// ⚠️ القياسُ على **دالّةِ التجميع** لا على `_pickFile`: اختيارُ الملفّ
// إضافةٌ من نظام التشغيل لا منطق.
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/data/services/excel_service.dart';

void main() {
  test('مرساة: صفوفٌ سليمةٌ كلُّها تُقبَل', () {
    final r = summarizeBankStatementRows([
      [DateTime(2026, 5, 1), 'A', '', 0, 100],
      [DateTime(2026, 5, 2), 'B', '', 50, 0],
    ]);

    expect(r.lines, hasLength(2));
    expect(r.errors, isEmpty);
  });

  test('🔴 الصفُّ المرفوضُ يُعَدُّ ويُقال سببُه', () {
    final r = summarizeBankStatementRows([
      [DateTime(2026, 5, 1), 'A', '', 0, 100],
      ['تاريخٌ فاسد', 'B', '', 0, 50],
      [DateTime(2026, 5, 3), 'C', '', 0, 0],
    ]);

    expect(r.lines, hasLength(1), reason: 'السليمُ وحدَه يُدرَج');
    expect(r.errors, hasLength(2), reason: 'والمرفوضان يُعَدّان لا يُطرَحان');
    expect(r.errors.first, contains('٢'), reason: 'ورقمُ الصفِّ في الرسالة');
  });

  test('صفُّ الرؤوس وسطرُ الشرح يُتخطّيان', () {
    final r = summarizeBankStatementRows([
      ['⚠️ مدين/دائن من منظور البنك', '', '', '', ''],
      ['التاريخ', 'المرجع', 'البيان', 'مدين', 'دائن'],
      [DateTime(2026, 5, 1), 'A', '', 0, 100],
    ], skipRows: 2);

    expect(r.lines, hasLength(1));
    expect(r.errors, isEmpty);
  });
}
```

- [ ] **Step 2: شغّله وتأكّد أنّه يسقط**

```bash
flutter test test/unit/bank_statement_import_test.dart
```

المتوقَّع: إخفاقُ ترجمة — `summarizeBankStatementRows` غيرُ معرَّفة.

- [ ] **Step 3: أضِف دالّةَ التجميع النقيّة**

في `lib/data/services/excel_service.dart` بجوار `reportCellValue` (خارجَ
الصنف — نفسُ نمط الدوالّ النقيّة هناك):

```dart
/// حصيلةُ تحليل صفوف قالب الكشف: ما يصلح للإدراج، وأسبابُ ما رُفض.
class BankStatementRowsSummary {
  const BankStatementRowsSummary(this.lines, this.errors);
  final List<Map<String, dynamic>> lines;
  final List<String> errors;
}

/// يحلّل صفوفَ ورقةِ الكشف. [skipRows] عددُ الصفوف العلويّة التي تُتخطّى
/// (سطرُ الشرح ثمّ صفُّ الرؤوس = ٢ في القالب).
///
/// نقيّةٌ خارجَ الصنف كـ[reportCellValue] — تُقاس بلا ملفٍّ ولا قاعدة.
BankStatementRowsSummary summarizeBankStatementRows(
  List<List<dynamic>> rows, {
  int skipRows = 0,
}) {
  final lines = <Map<String, dynamic>>[];
  final errors = <String>[];
  for (var i = skipRows; i < rows.length; i++) {
    final r = parseBankStatementRow(rows[i]);
    if (r.line != null) {
      lines.add(r.line!);
    } else {
      errors.add('الصفُّ ${_arabicDigits(i + 1)}: ${r.error}');
    }
  }
  return BankStatementRowsSummary(lines, errors);
}

String _arabicDigits(int n) =>
    '$n'.replaceAllMapped(RegExp(r'\d'), (m) => '٠١٢٣٤٥٦٧٨٩'[int.parse(m[0]!)]);
```

وأضِف الاستيرادَ في رأس الملفّ:

```dart
import 'bank_statement_row.dart';
```

- [ ] **Step 4: شغّل الاختبارَ وتأكّد أنّه يمرّ**

```bash
flutter test test/unit/bank_statement_import_test.dart
```

المتوقَّع: ‏٣ ناجحة.

- [ ] **Step 5: أضِف القالبَ والاستيرادَ على الصنف**

في صنف `ExcelService`، بعد `exportPurchaseInvoicesTemplate`:

```dart
  /// قالبُ كشف البنك — خمسةُ أعمدةٍ وسطرُ شرحٍ فوقها.
  ///
  /// ⚠️ سطرُ الشرح **ليس زينة**: «مدين/دائن» من منظور البنك، والمحرّكُ
  /// يقلبهما عند المطابقة. ومن يلصق عمودَيه معكوسَين لا يطابق شيئاً ولا
  /// يعرف لماذا.
  Future<String?> exportBankStatementTemplate() async {
    try {
      final excel = Excel.createExcel();
      final sheet = excel['كشف البنك'];
      if (excel.sheets.containsKey('Sheet1')) excel.delete('Sheet1');

      sheet.appendRow([
        TextCellValue('⚠️ «مدين» = خروجُ مالٍ من حسابك عند البنك · '
            '«دائن» = دخولُه. الحركةُ في عمودٍ واحدٍ لا اثنين.'),
      ]);
      sheet.appendRow([
        TextCellValue('التاريخ'),
        TextCellValue('المرجع'),
        TextCellValue('البيان'),
        TextCellValue('مدين'),
        TextCellValue('دائن'),
      ]);
      sheet.appendRow([
        TextCellValue('2026-05-10'),
        TextCellValue('REF-1'),
        TextCellValue('إيداع نقدي'),
        TextCellValue('0'),
        TextCellValue('500'),
      ]);

      return await _saveExcel(excel, 'bank_statement_template');
    } catch (e) {
      return null;
    }
  }

  /// يختار ملفَّ كشفٍ ويحلّله — **ولا يكتب في القاعدة**.
  ///
  /// ⚠️ **الكتابةُ على المُنادي عن قصد**: `ExcelService` يأخذ مستوداتٍ لا
  /// قاعدة، وحقنُ `IAccountingRepository` فيه لأجل دالّةٍ واحدةٍ يوسّع
  /// اعتمادَه على كلّ مُنشئيه. فيُعيد الحصيلةَ، وتكتبها الشاشةُ بالمستودع
  /// الذي بيدها أصلاً.
  ///
  /// `null` = لم يُختَر ملفّ (إلغاءُ المستخدم) — وهو ليس خطأً.
  Future<BankStatementRowsSummary?> pickAndParseBankStatement() async {
    final file = await _pickFile();
    if (file == null) return null;
    final excel = Excel.decodeBytes(file);
    final sheet = excel.tables[excel.tables.keys.first]!;
    final rows =
        sheet.rows.map((r) => r.map((c) => c?.value).toList()).toList();
    return summarizeBankStatementRows(rows, skipRows: 2);
  }
```

⚠️ **ولا `try/catch` يبتلع هنا**: ملفٌّ تالفٌ يجب أن يصل خبرُه المستخدمَ،
والشاشةُ تلتقط الرمْيَ وتعرض نصَّه. (‏`importProducts` القديمةُ تبتلع — لا
تنسخ ذلك.)

- [ ] **Step 6: تحقّق من التحليل**

```bash
flutter analyze lib/data/services/excel_service.dart lib/data/services/bank_statement_row.dart test/unit/bank_statement_import_test.dart
```

المتوقَّع: `No issues found!`

- [ ] **Step 7: كوّم**

```bash
git add lib/data/services/excel_service.dart test/unit/bank_statement_import_test.dart
git commit -m "feat(accounting): قالبُ كشف البنك واستيرادُه — بعددَي المُدرَج والمرفوض"
```

---

## Task 4: الشاشة — الرأسُ والجلسةُ والمؤشّرات

**Files:**
- Create: `lib/presentation/accounting_picpos/bank_reconciliation_picpos_screen.dart`
- Test: `test/widget/bank_reconciliation_picpos_screen_test.dart`

**Interfaces:**
- Consumes: `IAccountingRepository` (المهمّة ١) ·
  `treasuryRepositoryProvider.getSafesList()` ·
  `SafeData.{id, name, safeType, bankName, accountNumber, linkedAccountId, isActive}`.
- Produces: `BankReconciliationPicposScreen` — ودجتٌ بلا وسائطَ مطلوبة،
  تستهلكها المهمّةُ ٧.

- [ ] **Step 1: اكتب اختبارَ التركيب الساقط**

`test/widget/bank_reconciliation_picpos_screen_test.dart`:

```dart
// ⚠️ **العرضان ليسا احتياطاً**: القائمتان المتجاورتان أوّلُ ما ينهار ضيقاً،
// وشاشاتٌ كاملةٌ انهارت من تركيبٍ لم يُقَس عند عرضَين.
//
// ⚠️ **وخزنةٌ بلا حسابٍ مرتبطٍ تُقصى بسطرٍ يشرح** — بلا حسابٍ لا دفترَ
// يُطابَق عليه، والصمتُ يجعلها تبدو مفقودة.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/data/providers/repository_providers.dart';
import 'package:picpos_erp/domain/repositories/treasury_repository.dart';
import 'package:picpos_erp/presentation/accounting_picpos/bank_reconciliation_picpos_screen.dart';

// TODO_FOR_IMPLEMENTER: استعمل نفسَ نمطِ المزيَّفات في
// `test/widget/analytics_picpos_screen_test.dart` — صنفٌ يُنفّذ الواجهةَ
// ويعيد بياناتٍ ثابتة، مع `noSuchMethod`. ونفّذ الدوالَّ المستعملةَ
// **صريحةً**: `noSuchMethod` ترمي فيتعلّق المنتظِر.

Future<void> pump(WidgetTester tester, double width, {
  required List<SafeData> safes,
}) async {
  tester.view.physicalSize = Size(width, 1100);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        treasuryRepositoryProvider.overrideWithValue(_FakeTreasury(safes)),
        accountingRepositoryProvider.overrideWithValue(_FakeAccounting()),
      ],
      child: const MaterialApp(home: BankReconciliationPicposScreen()),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  for (final width in [1280.0, 1920.0]) {
    testWidgets('الشاشةُ تُرسَم بلا فيضان عند ${width.toInt()}', (tester) async {
      await pump(tester, width, safes: [_bankSafe(1, linked: 5)]);

      expect(tester.takeException(), isNull);
      expect(find.text('المطابقة البنكية'), findsWidgets);
    });
  }

  testWidgets('🔴 خزنةٌ بلا حسابٍ مرتبطٍ تُقصى بسطرٍ يشرح', (tester) async {
    await pump(tester, 1920, safes: [
      _bankSafe(1, linked: 5, name: 'البنك الأهلي'),
      _bankSafe(2, linked: null, name: 'بنك بلا ربط'),
    ]);

    expect(find.text('البنك الأهلي'), findsWidgets,
        reason: 'مرساة: المربوطةُ تظهر');
    expect(find.text('بنك بلا ربط'), findsNothing,
        reason: 'بلا حسابٍ لا دفترَ يُطابَق عليه');
    expect(find.textContaining('حساب'), findsWidgets,
        reason: 'والإقصاءُ يُشرَح لا يُصمَت عليه');
  });
}
```

- [ ] **Step 2: شغّله وتأكّد أنّه يسقط**

```bash
flutter test test/widget/bank_reconciliation_picpos_screen_test.dart
```

المتوقَّع: إخفاقُ تحميل — الشاشةُ غيرُ موجودة.

- [ ] **Step 3: ابنِ الشاشةَ — الرأسُ والمؤشّرات**

`lib/presentation/accounting_picpos/bank_reconciliation_picpos_screen.dart`:

بنيةٌ إلزاميّة (املأ العرضَ بأدوات الصدفة):

- `ConsumerStatefulWidget` باسم `BankReconciliationPicposScreen`.
- حالةٌ: `int? _safeId` · `int? _accountId` · `DateTimeRange _period`
  (افتراضُه الشهرُ الماضي) · `int? _sessionId`.
- مزوّدٌ `FutureProvider.autoDispose` للخزائن البنكيّة يرشِّح
  `s.safeType == 'bank' && s.isActive && s.linkedAccountId != null`،
  **ويحتفظ بعدد المُقصى** ليُعرَض سطرُ الشرح.
- `PicPosScreenScaffold` بعنوان «المطابقة البنكية».
- الرأس: `PicPosOptionPicker` للخزنة · `PicPosReportBar` للفترة · حقلُ
  «رصيد كشف البنك» · زرُّ «جلسة جديدة» يُنادي
  `repo.createReconciliation(...)` ويحفظ `_sessionId`.
- سطرُ الشرح تحت المنتقى حين `excluded > 0`:
  `'خزنةٌ بنكيّةٌ أو أكثرُ بلا حسابٍ مرتبطٍ — لا يمكن مطابقتُها'`.
- `PicPosHubKpiRow` بأربع بطاقات: رصيدُ الدفتر · رصيدُ الكشف · الفرق ·
  مطابَق/غيرُ مطابَق — من `repo.getReconciliationReport(_sessionId!)`.
- بلا جلسةٍ مفتوحة: `PicPosEmptyState` يقول «اختر خزنةً وفترةً ثمّ أنشئ جلسة».

⚠️ **ولا تُدخل `databaseProvider`** في أيّ مزوّدٍ هنا: اختبارُ الودجت يتجاوز
المستودعَ لا القاعدة، فتنفتح قاعدةٌ حقيقيّةٌ ويتعلّق `pumpAndSettle`.

- [ ] **Step 4: شغّل الاختبارَ وتأكّد أنّه يمرّ**

```bash
flutter test test/widget/bank_reconciliation_picpos_screen_test.dart
```

المتوقَّع: ‏٣ ناجحة.

- [ ] **Step 5: كوّم**

```bash
git add lib/presentation/accounting_picpos/bank_reconciliation_picpos_screen.dart test/widget/bank_reconciliation_picpos_screen_test.dart
git commit -m "feat(accounting): شاشةُ المطابقة البنكيّة — الرأسُ والجلسةُ والمؤشّرات"
```

---

## Task 5: الشاشة — الاستيرادُ والمطابقةُ الآليّة

**Files:**
- Modify: `lib/presentation/accounting_picpos/bank_reconciliation_picpos_screen.dart`
- Modify: `test/widget/bank_reconciliation_picpos_screen_test.dart`

**Interfaces:**
- Consumes: `exportBankStatementTemplate` و`importBankStatement` (المهمّة ٣) ·
  `autoMatchStatementLines` (المهمّة ١).
- Produces: لا شيءَ جديدٌ للمهامّ التالية.

- [ ] **Step 1: أضِف الاختبارَ الساقط**

أضِف إلى ملفّ الاختبار:

```dart
  testWidgets('🔴 «مطابقة آلية» تُنادي المحرّكَ وتقول العدد', (tester) async {
    final repo = _CapturingAccounting(autoMatchResult: 3);
    await pumpWithRepo(tester, 1920, repo: repo);

    await tester.tap(find.text('مطابقة آلية'));
    await tester.pumpAndSettle();

    expect(repo.autoMatchCalls, 1, reason: 'الزرُّ كان يُظهر إشعاراً فقط');
    expect(find.textContaining('٣'), findsWidgets,
        reason: 'والعددُ يُقال — «تمّت» بلا رقمٍ لا تُخبر بشيء');
  });

  testWidgets('🔴 إخفاقُ الاستيراد يُقال بسببه', (tester) async {
    final repo = _CapturingAccounting();
    await pumpWithRepo(tester, 1920, repo: repo,
        importResult: ImportResult(
            success: false, message: 'لا صفَّ صالحاً في الملف', errors: 4));

    await tester.tap(find.text('استيراد كشف'));
    await tester.pumpAndSettle();

    expect(find.textContaining('لا صفَّ صالحاً'), findsWidgets,
        reason: 'الرسالةُ تصل المستخدمَ ولا تُبتلَع في «تعذّرت العمليّة»');
  });
```

- [ ] **Step 2: شغّله وتأكّد أنّه يسقط**

```bash
flutter test test/widget/bank_reconciliation_picpos_screen_test.dart
```

المتوقَّع: سقوطُ الاختبارَين الجديدَين — الزرّان غيرُ موجودَين.

- [ ] **Step 3: أضِف الشريطَ الثلاثيّ**

في الشاشة، فوقَ القائمتين:

- `تنزيل القالب` → `excelService.exportBankStatementTemplate()`؛ يعرض المسارَ
  عند النجاح ورسالةَ تعذّرٍ عند `null`.
- `استيراد كشف` → `excelService.importBankStatement(_accountId!)`؛ **يعرض
  `result.message` كما هو** ثمّ يُنعش التقرير.
- `مطابقة آلية` → `repo.autoMatchStatementLines(_accountId!)`؛ يعرض
  `'طوبق $n سطراً'` بالأرقام العربيّة ثمّ يُنعش التقرير.

الثلاثةُ مُعطَّلةٌ حين `_accountId == null`.

- [ ] **Step 4: شغّل الاختبارَ وتأكّد أنّه يمرّ**

```bash
flutter test test/widget/bank_reconciliation_picpos_screen_test.dart
```

المتوقَّع: ‏٥ ناجحة.

- [ ] **Step 5: كوّم**

```bash
git add lib/presentation/accounting_picpos/bank_reconciliation_picpos_screen.dart test/widget/bank_reconciliation_picpos_screen_test.dart
git commit -m "feat(accounting): استيرادُ الكشف والمطابقةُ الآليّةُ من الشاشة"
```

---

## Task 6: الشاشة — القائمتان والمطابقةُ اليدويّة

**Files:**
- Modify: `lib/presentation/accounting_picpos/bank_reconciliation_picpos_screen.dart`
- Modify: `test/widget/bank_reconciliation_picpos_screen_test.dart`

**Interfaces:**
- Consumes: `manualMatchStatement` و`unmatchStatement` (المهمّة ١) ·
  مفاتيحَ `getReconciliationReport`: `unmatchedBankLines` ·
  `outstandingBookEntries` · `matchedLines`.
- Produces: لا شيءَ جديد.

- [ ] **Step 1: أضِف الاختباراتِ الساقطة**

```dart
  testWidgets('🔴 «طابق» تُعطَّل حتى يُختار سطرٌ من كلّ جانب', (tester) async {
    await pumpWithReport(tester, 1920);

    final btn = tester.widget<ElevatedButton>(
        find.widgetWithText(ElevatedButton, 'طابق'));
    expect(btn.onPressed, isNull, reason: 'بلا اختيارٍ لا مطابقة');

    await tester.tap(find.text('REF-1'));
    await tester.pump();
    final half = tester.widget<ElevatedButton>(
        find.widgetWithText(ElevatedButton, 'طابق'));
    expect(half.onPressed, isNull, reason: 'جانبٌ واحدٌ لا يكفي');

    await tester.tap(find.text('قيد الإيداع'));
    await tester.pump();
    final both = tester.widget<ElevatedButton>(
        find.widgetWithText(ElevatedButton, 'طابق'));
    expect(both.onPressed, isNotNull);
  });

  testWidgets('🔴 مطابقةٌ مكرّرةٌ تُعرَض رسالتُها لا تُبتلَع', (tester) async {
    final repo = _CapturingAccounting(
        manualMatchThrows: StateError(
            'سطرُ القيد رقم 7 مطابَقٌ سلفاً لسطر الكشف رقم 3.'));
    await pumpWithReport(tester, 1920, repo: repo);

    await tester.tap(find.text('REF-1'));
    await tester.tap(find.text('قيد الإيداع'));
    await tester.pump();
    await tester.tap(find.widgetWithText(ElevatedButton, 'طابق'));
    await tester.pumpAndSettle();

    expect(find.textContaining('مطابَقٌ سلفاً'), findsWidgets,
        reason: 'نصُّ المحرّك يسمّي السطرَ الآخر — وهو ما يحتاجه المحاسب');
  });

  testWidgets('و«نزع» يُنادي المحرّك', (tester) async {
    final repo = _CapturingAccounting();
    await pumpWithReport(tester, 1920, repo: repo);

    await tester.tap(find.text('نزع').first);
    await tester.pumpAndSettle();

    expect(repo.unmatchCalls, 1);
  });
```

- [ ] **Step 2: شغّله وتأكّد أنّه يسقط**

```bash
flutter test test/widget/bank_reconciliation_picpos_screen_test.dart
```

المتوقَّع: سقوطُ الثلاثة الجديدة.

- [ ] **Step 3: ابنِ القائمتين**

- فوق ١١٠٠ عرضاً: `Row` بقائمتَي `PicPosDataTable` متساويتَي العرض —
  يميناً `unmatchedBankLines` (التاريخ · المرجع · البيان · مدين · دائن)،
  ويساراً `outstandingBookEntries` (التاريخ · البيان · مدين · دائن).
- تحت ١١٠٠: `Column` — واحدةٌ فوق الأخرى.
- حالةُ الاختيار: `int? _pickedStmtId` و`int? _pickedJeLineId`؛ النقرُ على
  صفٍّ يبدّل الاختيارَ ويلوّنه.
- زرُّ `طابق`: `onPressed` = `null` ما لم يُختَر الاثنان. وعند الضغط:

```dart
try {
  await repo.manualMatchStatement(
    statementLineId: _pickedStmtId!,
    journalLineId: _pickedJeLineId!,
  );
  _clearPicks();
  _refresh();
} catch (e) {
  // ⚠️ نصُّ المحرّك كما هو: يسمّي سطرَ الكشف الآخر، و«تعذّرت العمليّة»
  //    تُخفي بالضبط ما يحتاجه المحاسبُ ليقرّر.
  _toast(e is StateError ? e.message : '$e');
}
```

- قائمةٌ ثالثةٌ للمطابَق (`matchedLines`) لكلّ صفٍّ زرُّ `نزع` يُنادي
  `unmatchStatement` ثمّ يُنعش.
- زرُّ `إقفال الجلسة` → `completeReconciliation`؛ **يعمل ولو بقي فرق**،
  وحوارُ تأكيدٍ يعرض الفرقَ صراحةً.

- [ ] **Step 4: شغّل الاختبارَ وتأكّد أنّه يمرّ**

```bash
flutter test test/widget/bank_reconciliation_picpos_screen_test.dart
```

المتوقَّع: ‏٨ ناجحة.

- [ ] **Step 5: كوّم**

```bash
git add lib/presentation/accounting_picpos/bank_reconciliation_picpos_screen.dart test/widget/bank_reconciliation_picpos_screen_test.dart
git commit -m "feat(accounting): القائمتان المتجاورتان والمطابقةُ اليدويّةُ والنزع"
```

---

## Task 7: التبويبةُ التاسعةُ وحذفُ القديمة

**Files:**
- Modify: `lib/presentation/accounting_picpos/accounting_hub_picpos_screen.dart`
- Modify: `lib/data/providers/auth_providers.dart`
- Modify: `lib/core/navigation/screen_registry.dart`
- Modify: `test/unit/accounting_hub_wiring_test.dart`
- Delete: `lib/presentation/screens/bank_reconciliation_screen.dart`

**Interfaces:**
- Consumes: `BankReconciliationPicposScreen` (المهمّة ٤).
- Produces: `AccountingTab.bank`.

- [ ] **Step 1: حدّث الحارسَ ليتبع القرار**

⚠️ **هذا ليس إسكاتَ حارس**: قائمةُ الأسماء **عقدٌ** يُحدَّث بقرارٍ موثَّق —
كما تبعت الثامنةُ قرارَ 2026-08-27. في
`test/unit/accounting_hub_wiring_test.dart`:

```dart
    test('عددُها وترتيبُها كالتصميم ثمّ الثامنُ والتاسعُ في ذيلها', () {
      // ⚠️ التاسعةُ انحرافٌ **ثانٍ** عن التصميم بقرارِ مالك 2026-09-01:
      //    المطابقةُ البنكيّةُ مدخلٌ واحدٌ في الحاوية لا مدخلٌ جانبيٌّ عاشر.
      expect(AccountingTab.values.map((t) => t.name).toList(),
          ['coa', 'cc', 'je', 'gl', 'tb', 'tpl', 'map', 'fs', 'bank']);
    });
```

وأضِف `'المطابقة البنكية'` في ذيل قائمة `label`.

- [ ] **Step 2: شغّله وتأكّد أنّه يسقط**

```bash
flutter test test/unit/accounting_hub_wiring_test.dart
```

المتوقَّع: سقوطُ اختبارَي الأسماء والعناوين — `bank` غيرُ موجودة.

- [ ] **Step 3: أضِف التبويبةَ والصلاحيةَ والنطاق**

في `accounting_hub_picpos_screen.dart` بعد `fs`:

```dart
  /// تاسعٌ لا يعرفه التصميم — قرارُ مالك 2026-09-01.
  ///
  /// المحرّكُ كان جاهزاً والمستودعُ يحجبه، والشاشةُ القديمةُ محاكاةً بحوارَين
  /// كاذبَين. والبديلُ مدخلٌ جانبيٌّ عاشرٌ في مجموعةٍ فيها تسعةٌ — فاختير
  /// إبقاءُ المدخل واحداً.
  bank('المطابقة البنكية', PhosphorIconsBold.bank, 'settings_view',
      ScreenId.bankReconciliation);
```

وفي `build()`:

```dart
        AccountingTab.bank => const BankReconciliationPicposScreen(),
```

وفي `auth_providers.dart` بجوار `ScreenId.accountingHub`:

```dart
  // نفسُ صلاحيّة الحاوية وستٍّ من تبويباتها — والحارسُ يشترط التطابق.
  ScreenId.bankReconciliation: 'settings_view',
```

وفي `screen_registry.dart` بجوار أخواتها المحاسبيّات:

```dart
    ScreenId.bankReconciliation,
```

- [ ] **Step 4: احذف الشاشةَ القديمة**

```bash
git rm lib/presentation/screens/bank_reconciliation_screen.dart
```

ثمّ تأكّد أنّها بلا مرجع:

```bash
grep -rn "BankReconciliationScreen" lib test --include=*.dart
```

المتوقَّع: لا مطابقة.

- [ ] **Step 5: شغّل الحارسَ وتأكّد أنّه يمرّ**

```bash
flutter test test/unit/accounting_hub_wiring_test.dart
```

- [ ] **Step 6: كوّم**

```bash
git add lib/presentation/accounting_picpos/accounting_hub_picpos_screen.dart lib/data/providers/auth_providers.dart lib/core/navigation/screen_registry.dart test/unit/accounting_hub_wiring_test.dart lib/presentation/screens/bank_reconciliation_screen.dart
git commit -m "feat(accounting): المطابقةُ البنكيّةُ تبويبةً تاسعةً — وحذفُ الشاشة المحاكية"
```

---

## Task 8: اختبارُ الدورة الكاملة

**Files:**
- Test: `test/integration/bank_reconciliation_cycle_test.dart`

**Interfaces:**
- Consumes: كلَّ ما سبق.

- [ ] **Step 1: اكتب الاختبار**

```dart
// الدورةُ كاملةً على كشفٍ كلُّ أسطره لها ما يقابلها في الدفتر.
// ⚠️ والمقيسُ **قيمةٌ محسوبةٌ يدويّاً** لا «> صفر»: مصالحةٌ قد تتّفق عند
// رقمٍ خاطئٍ وتمرّ خضراء.
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/data/database/database.dart';
import 'package:picpos_erp/data/repositories/drift_accounting_repository.dart';
import 'package:picpos_erp/domain/entities/accounting_entities.dart';

void main() {
  late AppDatabase db;
  late DriftAccountingRepository repo;
  late int bankId;
  late int cashId;

  setUp(() async {
    db = AppDatabase.forTesting();
    repo = DriftAccountingRepository(db);
    cashId = (await db.getAccountByCode('1110'))!.id;
    bankId = await db.createAccount(
        code: '1120', name: 'البنك', accountType: 'asset');
  });

  tearDown(() => db.close());

  test('🔴 دورةٌ كاملة: استيرادٌ ← آليّةٌ ← يدويّةٌ ← إقفال', () async {
    // قيدان: أحدُهما داخلَ نافذة ±٣ أيّام والآخرُ خارجَها.
    for (final (d, amount) in [
      (DateTime(2026, 5, 10), 500.0),
      (DateTime(2026, 5, 1), 300.0),
    ]) {
      await db.createJournalEntry(
        description: 'إيداع',
        date: d,
        lines: [
          JournalLine(accountId: bankId, debit: amount),
          JournalLine(accountId: cashId, credit: amount),
        ],
      );
    }

    await repo.importBankStatementLines(
      bankAccountId: bankId,
      batchId: 'CYCLE',
      lines: [
        {'date': DateTime(2026, 5, 11), 'reference': 'A', 'description': '',
         'debit': 0.0, 'credit': 500.0, 'balance': 500.0},
        {'date': DateTime(2026, 5, 25), 'reference': 'B', 'description': '',
         'debit': 0.0, 'credit': 300.0, 'balance': 800.0},
      ],
    );

    // مرساة: الاستيرادُ وقع فعلاً.
    expect(await repo.getUnmatchedStatementLines(bankId), hasLength(2));

    // الآليّةُ تمسك الأوّلَ وحدَه (±٣ أيّام).
    expect(await repo.autoMatchStatementLines(bankId), 1);
    final left = await repo.getUnmatchedStatementLines(bankId);
    expect(left, hasLength(1));
    expect(left.single.reference, 'B');

    // واليدويّةُ تُغلق الثاني.
    final id = await repo.createReconciliation(
      bankAccountId: bankId,
      periodStart: DateTime(2026, 5, 1),
      periodEnd: DateTime(2026, 5, 31),
      statementBalance: 800,
    );
    final report = await repo.getReconciliationReport(id);
    final jeLineId =
        (report['outstandingBookEntries'] as List).first.data['id'] as int;

    await repo.manualMatchStatement(
        statementLineId: left.single.id, journalLineId: jeLineId);

    expect(await repo.getUnmatchedStatementLines(bankId), isEmpty,
        reason: 'الدورةُ تنتهي بصفرِ غيرِ مطابَق');

    // والفرقُ = رصيدُ الكشف − رصيدُ الدفتر، محسوباً يدويّاً: 800 − 800 = 0.
    final finalReport = await repo.getReconciliationReport(id);
    expect(finalReport['bookBalance'], 800.0);
    expect(finalReport['difference'], 0.0);

    await repo.completeReconciliation(id);
    final row = await (db.select(db.bankReconciliations)
          ..where((r) => r.id.equals(id)))
        .getSingle();
    expect(row.status, 'completed');
  });
}
```

- [ ] **Step 2: شغّله**

```bash
flutter test test/integration/bank_reconciliation_cycle_test.dart
```

المتوقَّع: ناجح. إن سقط، **اقرأ الرقمَ ولا تُعدّل التوقّع** حتى تعرف الجذر.

- [ ] **Step 3: كوّم**

```bash
git add test/integration/bank_reconciliation_cycle_test.dart
git commit -m "test(accounting): دورةُ المطابقة البنكيّة كاملةً بأرقامٍ محسوبةٍ يدويّاً"
```

---

## Task 9: البوّابةُ وسويّةُ PostgreSQL

- [ ] **Step 1: شغّل البوّابةَ في الخلفيّة**

```bash
rm -rf build/native_assets && nohup bash scripts/gate.sh > /tmp/gate.log 2>&1 &
```

- [ ] **Step 2: احكم بالختم لا برمز الخروج**

```bash
grep -ac "البوابة كلها خضراء" /tmp/gate.log
grep -ac "البوابة حمراء" /tmp/gate.log
```

المتوقَّع: ‏`1` ثمّ `0`. وخطُّ الأساس: `analyze` ٦ info · unit ٥٤٤٠+ ·
widget ١٥٠٧+ · integration ٧٦٣+.

- [ ] **Step 3: شغّل سويّةَ PostgreSQL — لا تفترضها**

```bash
rm -rf build/native_assets && dart run scripts/run_pg_tests.dart
```

المتوقَّع: ‏٦١ ناجحةً فأكثر · صفر `[E]`.

- [ ] **Step 4: حدّث `HANDOFF-NEXT.md`**

احذف بندَ «`BankReconciliationScreen` بلا مرجع» من §٥، وأضِف السطرَ إلى §٣
بأرقام البوّابة المقيسة.

---

## المراجعةُ الذاتيّة

**تغطيةُ المواصفة:** §٣‑١ ⇒ المهمّة ١ · §٣‑٢ ⇒ ٢ و٣ · §٣‑٣ و§٤ ⇒ ٤–٦ ·
§٥ ⇒ اختباراتُ ٣ و٤ و٦ · §٦ ⇒ ١–٨ · §٧ ⇒ ٧ · §٨ خارجُ النطاقِ صراحةً.
لا فجوة.

**العناصرُ المؤجَّلة:** موضعٌ واحدٌ مقصود — `TODO_FOR_IMPLEMENTER` في اختبار
المهمّة ٤ يحيل إلى نمطِ مزيَّفٍ **قائمٍ** في
`test/widget/analytics_picpos_screen_test.dart` بدل نسخِ ٦٠ سطراً هنا. وهو
إحالةٌ إلى كودٍ موجود لا وصفٌ لكودٍ غائب.

**اتّساقُ الأنواع:** `parseBankStatementRow` → `BankStatementRowResult`
(المهمّة ٢) تستهلكها `summarizeBankStatementRows` (٣) بنفس الاسم.
و`importBankStatement` تعيد `ImportResult` القائمةَ بحقولها الخمسة.
و`getReconciliationReport` تُقرأ بمفاتيحها المعلَنةِ في المهمّة ١ في المهامّ
٦ و٨.
