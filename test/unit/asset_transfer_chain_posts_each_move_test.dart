// 🔴 سلسلةُ نقلاتٍ لأصلٍ واحد: كلُّ نقلةٍ قيدُها — لا الأولى وحدَها.
//
// ═══ العطب ═══
//
// `transferAsset` يُرحّل قيدَه بـ`referenceType: 'asset_transfer'` و
// `referenceId: assetId` و`isAutoPosted: true`. و`createJournalEntry` يُسقط
// كلَّ قيدٍ تلقائيٍّ يكرّر زوجَ `(referenceType, referenceId)` ما لم يكن
// النوعُ في [kMultiJeReferenceTypes] — و`asset_transfer` **ليس** منها.
//
// و`referenceId` رقمُ الأصل **بلا وجهة**. فالنقلةُ الأولى (CC1 ← CC2) تُرحَّل،
// وكلُّ نقلةٍ تاليةٍ لنفس الأصل تُعَدّ «مكرَّرةً» فيعيد الحارسُ رقمَ القيد
// الأوّل صامتاً ولا يُرحِّل شيئاً — بينما البطاقةُ تتقدّم إلى CC3 كالمعتاد.
//
// أي أنّها **عينُ** فئةِ العطب التي أصلحها 0f7d2787 بدرجةٍ أعمق: هناك كانت
// البطاقةُ جامدةً والأستاذُ يتحرّك، وهنا البطاقةُ تتحرّك والأستاذُ يتجمّد عند
// النقلة الأولى. والنتيجةُ واحدة — بطاقةٌ في مركزٍ ودفترٌ في آخر. ولا يكشفه
// ميزانُ المراجعة: القيدُ الغائبُ طرفاه في نفس الحساب.
//
// ونفسُ الشكل في `asset_revaluation`: قيدٌ لكلِّ **حدثِ** تقييم، ومفتاحُه رقمُ
// الأصل وحدَه ⇒ التقييمُ الثاني يُبتلَع بينما `purchase_price` يتقدّم.
//
// وهي نفسُ فئةِ عطبِ الإهلاك الموثّقةِ في `database.dart` (v168).
//
// ═══ ولماذا الإعفاءُ آمنٌ هنا ═══
//
// إعفاءُ نوعٍ من الفهرس يرفع الحمايةَ من الترحيل المزدوج، فلا بدّ من مفتاحٍ
// لكلِّ حدثٍ يحلّ محلَّها. وهو موجودٌ في الطرفَين — ويحرسه الفحصان
// الموسومان ⚓ أدناه:
//
//   • التحويل: حارسُ `fromCostCenterId == asset.costCenterId` (‏0f7d2787).
//     فبعد CC1 ← CC2 تصير البطاقةُ في CC2، وتكرارُ «CC1 ← CC2» يُرفَض قبل
//     أيّ كتابة. الضغطةُ المزدوجةُ تُرحَّل مرّةً واحدة.
//   • التقييم: `if (difference.abs() < 0.01) return;` — فالتقييمُ إلى نفس
//     القيمة العادلة لا يُنتج قيداً أصلاً.

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/data/database/database.dart';

void main() {
  late AppDatabase db;
  late int cc1; // المركزُ الذي يولد فيه الأصل
  late int cc2; // الوجهةُ الأولى — ووسيطُ السلسلة
  late int cc3; // الوجهةُ الثانية
  late int assetId;
  late int assetAccountId;

  // ١٢٠٠٠ تكلفةً − ٢٠٠٠ مجمَّعَ إهلاكٍ = ١٠٠٠٠ قيمةً دفتريّة. والتحويلُ لا
  // يمسّ أيّاً منهما، فالنقلتان تحملان نفسَ المبلغ.
  const bookValue = 10000.0;

  /// مركزُ التكلفة كما تراه **البطاقة**.
  Future<int?> cardCostCenter() async =>
      (await (db.select(db.fixedAssets)..where((a) => a.id.equals(assetId)))
              .getSingle())
          .costCenterId;

  /// القيمةُ الدفتريّةُ كما تراها **البطاقة**.
  Future<double> cardBookValue() async {
    final a =
        await (db.select(db.fixedAssets)..where((x) => x.id.equals(assetId)))
            .getSingle();
    return a.purchasePrice - a.accumulatedDepreciation;
  }

  /// قيودُ [refType] لهذا الأصل كما يراها **الأستاذ**.
  Future<List<JournalEntryData>> entriesOf(String refType) =>
      (db.select(db.journalEntries)
            ..where((e) =>
                e.referenceType.equals(refType) &
                e.referenceId.equals(assetId)))
          .get();

  Future<List<JournalEntryLine>> linesOf(String refType) async {
    final ids = (await entriesOf(refType)).map((e) => e.id).toList();
    if (ids.isEmpty) return const [];
    return (db.select(db.journalEntryLines)..where((l) => l.entryId.isIn(ids)))
        .get();
  }

  /// صافي الحركة (‏مدين − دائن) لكلِّ مركز تكلفة عبر كلّ قيود [refType].
  ///
  /// هذا هو المقياسُ الذي يقابل البطاقةَ بالأستاذ: المركزُ الذي تقف فيه
  /// البطاقةُ يجب أن يكون صافيه القيمةَ الدفتريّةَ داخلةً، والوسيطُ صفراً.
  Future<Map<int?, double>> netByCostCenter(String refType) async {
    final net = <int?, double>{};
    for (final l in await linesOf(refType)) {
      net[l.costCenterId] = (net[l.costCenterId] ?? 0) + l.debit - l.credit;
    }
    return net;
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

    cc1 = await db.createCostCenter(code: 'CC-1', name: 'المركزُ الأوّل');
    cc2 = await db.createCostCenter(code: 'CC-2', name: 'المركزُ الوسيط');
    cc3 = await db.createCostCenter(code: 'CC-3', name: 'المركزُ الأخير');

    final assetAcc = (await db.getAccountByCode('1213'))!;
    assetAccountId = assetAcc.id;
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
      costCenterId: cc1,
      contraAccountId: (await db.getAccountByCode('2111'))!.id,
    );

    // مجمَّعُ إهلاكٍ غيرُ صفريّ عمداً: القيمةُ الدفتريّةُ تصير ١٠٠٠٠ ≠ التكلفة
    // ١٢٠٠٠ ≠ صفر، فتوكيدُ المبالغ أدناه لا يمرّ بالمصادفة على أيٍّ منهما.
    await (db.update(db.fixedAssets)..where((a) => a.id.equals(assetId)))
        .write(
            const FixedAssetsCompanion(accumulatedDepreciation: Value(2000)));
  });

  tearDown(() => db.close());

  // ═══ مراسي القياس — قبلَ أيِّ حكم ═══════════════════════════════════════

  test('⚓ مرساة: النقلةُ الأولى تُرحَّل وقياسُها يقرأ ما رُحِّل', () async {
    // بلا هذه المرساةِ قد يسقط الفحصُ الرئيسُ لأنّ `netByCostCenter` لا يقرأ
    // شيئاً أصلاً — لا لأنّ القيدَ الثانيَ ابتُلع.
    expect(await entriesOf('asset_transfer'), isEmpty);

    await db.transferAsset(assetId,
        newCostCenterId: cc2, fromCostCenterId: cc1);

    expect(await entriesOf('asset_transfer'), hasLength(1));
    expect(await cardCostCenter(), cc2);

    final net = await netByCostCenter('asset_transfer');
    expect(net[cc1], closeTo(-bookValue, 0.005),
        reason: 'القيمةُ خرجت من المركز الأوّل');
    expect(net[cc2], closeTo(bookValue, 0.005),
        reason: 'ودخلت الوجهةَ — وهذا ما يقرؤه المقياسُ نفسُه');
  });

  test('⚓ وتكرارُ نفس النقلة يُرفَض ولا يُرحَّل ثانيةً', () async {
    // هذا هو المفتاحُ لكلِّ حدثٍ الذي يحلّ محلَّ فهرس إزالة التكرار حين
    // يُعفى `asset_transfer` منه. لو سقط هذا الحارسُ صارت الضغطةُ المزدوجةُ
    // تُرحّل نقلتَين متطابقتَين ⇒ ضِعفُ القيمة في الوجهة وسالبُها في المصدر.
    await db.transferAsset(assetId,
        newCostCenterId: cc2, fromCostCenterId: cc1);

    await expectLater(
      db.transferAsset(assetId, newCostCenterId: cc2, fromCostCenterId: cc1),
      throwsA(isA<Exception>()),
      reason: 'البطاقةُ في #$cc2 بعد النقلة الأولى، فمصدرٌ #$cc1 لم يعد '
          'يحملها — يُرفَض قبل أيّ كتابة.',
    );

    expect(await entriesOf('asset_transfer'), hasLength(1));
    expect(await cardCostCenter(), cc2);
  });

  // ═══ العطب ═══════════════════════════════════════════════════════════════

  test('🔴 نقلتان متتاليتان ⇒ قيدان — لا قيدٌ واحد', () async {
    await db.transferAsset(assetId,
        newCostCenterId: cc2, fromCostCenterId: cc1);
    await db.transferAsset(assetId,
        newCostCenterId: cc3, fromCostCenterId: cc2);

    expect(
      await entriesOf('asset_transfer'),
      hasLength(2),
      reason:
          '`asset_transfer` ليس في `kMultiJeReferenceTypes`، و`referenceId` '
          'رقمُ الأصل بلا وجهة ⇒ النقلةُ الثانيةُ تُعَدّ تكراراً للأولى، '
          'فيعيد `createJournalEntry` رقمَ القيد الأوّل صامتاً ولا يُرحِّل. '
          'والبطاقةُ تتقدّم إلى #$cc3 على كلّ حال.',
    );
  });

  test('🔴 وصافي الحركة لكلِّ مركزٍ يوافق البطاقةَ', () async {
    await db.transferAsset(assetId,
        newCostCenterId: cc2, fromCostCenterId: cc1);
    await db.transferAsset(assetId,
        newCostCenterId: cc3, fromCostCenterId: cc2);

    final net = await netByCostCenter('asset_transfer');
    final card = await cardCostCenter();

    expect(card, cc3, reason: 'مرساةٌ: البطاقةُ وصلت المركزَ الأخير');

    expect(
      net[card] ?? 0,
      closeTo(bookValue, 0.005),
      reason: 'البطاقةُ في المركز #$card والأستاذُ يقول إنّ صافيَ ما دخله '
          '${net[card] ?? 0} لا $bookValue — فكلُّ تقريرٍ يجمع الأصولَ بمركز '
          'التكلفة يخالف الدفتر، ولا يظهر في ميزان المراجعة لأنّ طرفَي القيد '
          'الغائب في نفس الحساب.',
    );

    expect(
      net[cc2] ?? 0,
      closeTo(0, 0.005),
      reason: 'المركزُ الوسيط #$cc2 دخلته القيمةُ ثمّ غادرته، فصافيه صفر. '
          'وبقاؤه موجباً ⇒ النقلةُ الثانيةُ لم تُرحَّل والقيمةُ عالقةٌ فيه '
          'إلى الأبد.',
    );

    expect(net[cc1] ?? 0, closeTo(-bookValue, 0.005),
        reason: 'والمركزُ الأوّل خرجت منه مرّةً واحدة');
  });

  test('🔴 وتقييمان متتاليان ⇒ قيدان، ومجموعُهما يوافق البطاقةَ', () async {
    // ١٠٠٠٠ → ١١٠٠٠ (‏فائضٌ ١٠٠٠) ثمّ ١١٠٠٠ → ١٢٥٠٠ (‏فائضٌ ١٥٠٠).
    await db.revalueAsset(assetId, newFairValue: 11000);
    await db.revalueAsset(assetId, newFairValue: 12500);

    expect(
      await entriesOf('asset_revaluation'),
      hasLength(2),
      reason: '`asset_revaluation` قيدٌ لكلِّ حدثِ تقييمٍ ومفتاحُه رقمُ الأصل '
          'وحدَه ⇒ التقييمُ الثاني يُبتلَع بينما `purchase_price` يتقدّم.',
    );

    expect(await cardBookValue(), closeTo(12500, 0.005),
        reason: 'مرساةٌ: البطاقةُ وصلت القيمةَ العادلةَ الأخيرة');

    final assetDebits = (await linesOf('asset_revaluation'))
        .where((l) => l.accountId == assetAccountId)
        .fold<double>(0, (s, l) => s + l.debit - l.credit);

    expect(
      assetDebits,
      closeTo(2500, 0.005),
      reason: 'البطاقةُ ارتفعت ٢٥٠٠ (١٠٠٠ + ١٥٠٠) والأستاذُ سجّل $assetDebits '
          '⇒ حسابُ الأصول في الدفتر أقلُّ من البطاقة بفارق التقييم الثاني.',
    );
  });

  test('⚓ وتقييمٌ إلى نفس القيمة العادلة لا يُرحَّل ثانيةً', () async {
    // المفتاحُ لكلِّ حدثٍ في طرف التقييم: `difference.abs() < 0.01` يعود
    // باكراً، فالضغطةُ المزدوجةُ لا تُنتج قيداً ثانياً حتّى بعد الإعفاء.
    await db.revalueAsset(assetId, newFairValue: 11000);
    await db.revalueAsset(assetId, newFairValue: 11000);

    expect(await entriesOf('asset_revaluation'), hasLength(1));
    expect(await cardBookValue(), closeTo(11000, 0.005));
  });
}
