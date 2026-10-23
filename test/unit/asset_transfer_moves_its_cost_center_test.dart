// 🔴 تحويلُ الأصل بين مراكز التكلفة يُحرّك **البطاقةَ** كما يُحرّك الأستاذ.
//
// ═══ العطبُ الذي وُلد منه هذا الملفّ (‏مقيس 2026-09-19) ═══
//
// `transferAsset` يُعلن فوق كتابته «Update the asset's cost center
// reference» ثمّ يكتب الملاحظةَ وحدَها:
//
//     .write(FixedAssetsCompanion(notes: Value('محوّل إلى مركز تكلفة #…')))
//
// و`cost_center_id` لا يُمَسّ. فالقيدُ (`referenceType: 'asset_transfer'`)
// ينقل القيمةَ الدفتريّةَ من المركز المصدر إلى الوجهة في **الأستاذ**، بينما
// تبقى بطاقةُ الأصل معلّقةً بالمركز القديم إلى الأبد.
//
// ═══ والأثر ═══
//
// كلُّ تقريرٍ يجمع الأصولَ بمركز التكلفة يخالف الدفتر: المركزُ القديم يحمل
// أصلاً خرج منه، والجديدُ يحمل قيمةً في الأستاذ بلا أصلٍ يقابلها. والفرقُ
// لا يظهر في ميزان المراجعة — فمجموعُ المدين يساوي الدائنَ على كلّ حال،
// والطرفان في **نفس** الحساب. ولا يظهر في البطاقة وحدَها ولا في الأستاذ
// وحدَه: لا يُكشَف إلّا بمقارنةِ الاثنين، وهو ما يفعله الفحصُ الثالث أدناه.
//
// ═══ ولماذا لم يمسكه شيء ═══
//
// الدالّةُ غيرُ مكشوفةٍ في `IFixedAssetsRepository`، فلا شاشةَ تناديها ولا
// اختبارَ يمرّ بها — وُلد هذا الملفّ ليحرسها **قبل** أن تُوصَل.
//
// ═══ و`fromCostCenterId` لم يكن يُصدَّق على شيء ═══
//
// المصدرُ يأتي من المنادي ثقةً، ويُستعمل في الطرف الدائن من القيد وحدَه.
// فمنادٍ يمرّر مصدراً خاطئاً يُخرج القيمةَ من مركزٍ لم يحملها قطّ ويترك
// المركزَ الحقيقيَّ حاملاً أصلاً غادره — وهو **عينُ** العطب أعلاه بدرجةٍ
// أعلى. والبطاقةُ تعرف مركزَها، فالمصدرُ يُطابَق عليها أو يُرفَض.

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/data/database/database.dart';

void main() {
  late AppDatabase db;
  late int ccFrom; // مركزُ التكلفة الذي يحمل الأصلَ عند الإنشاء
  late int ccTo; // الوجهة
  late int ccOther; // مركزٌ ثالثٌ لا علاقة له بالأصل
  late int assetId;

  /// مركزُ التكلفة كما تراه **البطاقة**.
  Future<int?> cardCostCenter() async =>
      (await (db.select(db.fixedAssets)..where((a) => a.id.equals(assetId)))
              .getSingle())
          .costCenterId;

  /// قيودُ التحويل لهذا الأصل كما يراها **الأستاذ**.
  Future<List<JournalEntryData>> transferEntries() =>
      (db.select(db.journalEntries)
            ..where((e) =>
                e.referenceType.equals('asset_transfer') &
                e.referenceId.equals(assetId)))
          .get();

  Future<List<JournalEntryLine>> transferLines() async {
    final entries = await transferEntries();
    expect(entries, hasLength(1), reason: 'قيدُ تحويلٍ واحدٌ متوقَّع');
    return (db.select(db.journalEntryLines)
          ..where((l) => l.entryId.equals(entries.single.id)))
        .get();
  }

  setUp(() async {
    db = AppDatabase.forTesting();
    await db.syncDefaultAccounts();

    // `transferAsset` يؤرّخ قيدَه بـ`DateTime.now()`، فالسنةُ المالية تُبنى
    // على سنةِ التشغيل لا على سنةٍ مكتوبةٍ في الاختبار.
    final now = DateTime.now();
    await db.into(db.fiscalYears).insert(
          FiscalYearsCompanion.insert(
            name: '${now.year}',
            startDate: DateTime(now.year, 1, 1),
            endDate: DateTime(now.year, 12, 31, 23, 59, 59),
          ),
        );

    ccFrom = await db.createCostCenter(code: 'CC-1', name: 'فرعُ المصدر');
    ccTo = await db.createCostCenter(code: 'CC-2', name: 'فرعُ الوجهة');
    ccOther = await db.createCostCenter(code: 'CC-3', name: 'فرعٌ ثالث');

    final assetAcc = (await db.getAccountByCode('1213'))!;
    final categoryId = await db.createAssetCategory(
      name: 'آلاتٌ',
      accountId: assetAcc.id,
      depreciationAccountId: (await db.getAccountByCode('1219'))!.id,
    );

    assetId = await db.createFixedAsset(
      code: 'FA-1',
      name: 'آلةٌ',
      categoryId: categoryId,
      purchasePrice: 12000,
      purchaseDate: DateTime(now.year, 1, 1),
      usefulLifeYears: 5,
      costCenterId: ccFrom,
      contraAccountId: (await db.getAccountByCode('2111'))!.id,
    );

    // مجمَّعُ إهلاكٍ غيرُ صفريّ عمداً: القيمةُ الدفتريّةُ تصير ١٠٠٠٠ ≠ التكلفة
    // ١٢٠٠٠ ≠ صفر، فتوكيدُ مبلغِ القيد أدناه لا يمرّ بالمصادفة على أيٍّ من
    // الرقمَين الآخرَين.
    await (db.update(db.fixedAssets)..where((a) => a.id.equals(assetId)))
        .write(const FixedAssetsCompanion(accumulatedDepreciation: Value(2000)));
  });

  tearDown(() => db.close());

  test('⚓ مرساة: البطاقةُ تبدأ في المركز المصدر', () async {
    // بلا هذه المرساةِ قد يمرّ الفحصُ التالي (أو يسقط) لسببٍ لا علاقةَ له
    // بالتحويل: تجهيزةٌ لا تكتب مركزَ التكلفة أصلاً.
    expect(await cardCostCenter(), ccFrom);
    expect(ccTo, isNot(ccFrom));
    expect(await transferEntries(), isEmpty);
  });

  test('🔴 وبعد التحويل تشير البطاقةُ إلى المركز الجديد', () async {
    await db.transferAsset(assetId,
        newCostCenterId: ccTo, fromCostCenterId: ccFrom);

    expect(await cardCostCenter(), ccTo,
        reason: 'الأستاذُ نقل القيمةَ الدفتريّةَ إلى المركز #$ccTo والبطاقةُ '
            'ما زالت في #$ccFrom ⇒ كلُّ تقريرٍ يجمع الأصولَ بمركز التكلفة '
            'يخالف الدفتر: القديمُ يحمل أصلاً غادره والجديدُ قيمةً بلا أصل.');
  });

  test('🔴 والقيدُ يوافق البطاقةَ: مدينُه مركزُها ودائنُه المصدر', () async {
    await db.transferAsset(assetId,
        newCostCenterId: ccTo, fromCostCenterId: ccFrom);

    final lines = await transferLines();
    expect(lines, hasLength(2));
    final debitLine = lines.singleWhere((l) => l.debit > 0);
    final creditLine = lines.singleWhere((l) => l.credit > 0);

    // ١٢٠٠٠ تكلفةً − ٢٠٠٠ مجمَّعَ إهلاكٍ = ١٠٠٠٠ قيمةً دفتريّة.
    expect(debitLine.debit, closeTo(10000, 0.005),
        reason: 'المنقولُ ليس القيمةَ الدفتريّة');
    expect(creditLine.credit, closeTo(10000, 0.005));
    expect(debitLine.accountId, creditLine.accountId,
        reason: 'طرفا التحويل في نفس حساب الأصول — المتغيّرُ مركزُ التكلفة');

    expect(creditLine.costCenterId, ccFrom);
    expect(debitLine.costCenterId, await cardCostCenter(),
        reason: 'الأستاذُ أدخل القيمةَ مركزَ التكلفة #${debitLine.costCenterId} '
            'والبطاقةُ تقول #${await cardCostCenter()} — الطرفان يتناقضان، '
            'ولا يكشفه ميزانُ المراجعة لأنّ مدينَه يساوي دائنَه.');
  });

  test('🔴 ومصدرٌ يخالف البطاقةَ يُرفَض ولا يترك أثراً', () async {
    await expectLater(
      db.transferAsset(assetId,
          newCostCenterId: ccTo, fromCostCenterId: ccOther),
      throwsA(isA<Exception>()),
      reason: 'مصدرٌ لم يحمل الأصلَ قطّ يُقبَل ثقةً ⇒ القيدُ يُخرج القيمةَ '
          'من مركزٍ لم تدخله، ويبقى المركزُ الحقيقيُّ حاملاً أصلاً غادره.',
    );

    expect(await cardCostCenter(), ccFrom,
        reason: 'الرفضُ يجب أن يكون قبل أيّ كتابة');
    expect(await transferEntries(), isEmpty,
        reason: 'قيدٌ رُحِّل ثمّ رُفض التحويل ⇒ أستاذٌ يحمل نقلاً لم يقع');
  });
}
