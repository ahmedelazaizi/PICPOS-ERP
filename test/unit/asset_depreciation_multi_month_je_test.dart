// 🔴 إهلاكُ الأصول يُرحَّل **كلَّ شهر** — لا شهراً واحداً ثمّ صمت.
//
// ═══ العطبُ الذي وُلد منه هذا الملفّ (‏مقيس 2026-08-27، المرحلة ٤) ═══
//
// `createJournalEntry` يمنع تكرارَ الترحيل التلقائيِّ بمفتاح
// `(referenceType, referenceId)`. و`referenceId` في الإهلاك **رقمُ الأصل
// بلا فترة**. فالنتيجة:
//
//   • الشهرُ الأوّل: لا مكرَّرَ ⇒ يُرحَّل قيدٌ سليم.
//   • وكلُّ شهرٍ بعده: يُطابق القيدَ الأوّلَ فيُعَدّ «مكرَّراً» ويُبتلَع —
//     ويعيد المفتاحُ رقمَ القيد القديم، فيُخزَّن في `asset_depreciations.
//     journal_entry_id` وكأنّ الترحيلَ وقع.
//
// وصفُّ الإهلاك يُكتَب، والبطاقةُ `fixed_assets.accumulated_depreciation`
// تتقدّم، والشاشاتُ تقرأ البطاقةَ لا الأستاذ — فكلُّ شيءٍ يبدو سليماً.
//
// ═══ ولماذا لا يمسكه اختبارُ وحدة ═══
//
// اختبارُ الإهلاك الطبيعيُّ يسأل: «هل أُنشئ صفُّ إهلاكٍ؟ هل تقدّمت
// البطاقة؟» — والجوابان نعم. العطبُ في **الطرفِ الثالث** وحدَه: الأستاذ.
// ولا يُكشَف إلّا بمصالحةٍ تقارن البطاقةَ بالدفتر (‏انظر
// `test/integration/full_reconciliation_cutoff_test.dart`).
//
// ═══ والأثرُ ماليٌّ متراكم ═══
//
// مجمَّعُ الإهلاك في الأستاذ يتجمّد عند شهرٍ واحدٍ لكلّ أصل. فالأصولُ
// الثابتةُ **مضخَّمةٌ** في الميزانيّة، ومصروفُ الإهلاك **منقوصٌ** في قائمة
// الدخل ⇒ ربحٌ أعلى من حقيقته وضريبةُ دخلٍ على أساسٍ خاطئ. ويكبر الفرقُ
// كلَّ شهرٍ ولكلِّ أصل.
//
// ═══ والعلاجُ لا يفتح ثقبَ ترحيلٍ مزدوج ═══
//
// `asset_depreciation` أُدرج في `multiJeReferenceTypes` — وهي آليّةٌ قائمةٌ
// لأنواعٍ تُنتج قيداً لكلِّ حدثٍ لا لكلِّ مرجع (‏الأوراقُ التجاريّة
// ومردوداتُ البيع). وتفرّدُه محفوظٌ في موضعه الصحيح: `runMonthlyDepreciation`
// يفحص `(assetId, periodDate)` ويتخطّى المُهلَك سلفاً. والفحصُ الأخيرُ
// أدناه يثبّت ذلك — بدونه يكون الإصلاحُ استبدالَ عطبٍ بأسوأَ منه.

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/data/database/database.dart';

void main() {
  late AppDatabase db;
  late int accumAccountId;
  late int assetId;

  /// مجمَّعُ الإهلاك كما يراه **الأستاذ** (‏دائنٌ موجب).
  Future<double> ledgerAccumulated() async {
    final r = await db.customSelect(
      'SELECT COALESCE(SUM(l.credit), 0) - COALESCE(SUM(l.debit), 0) AS v '
      'FROM journal_entry_lines l JOIN journal_entries e ON e.id = l.entry_id '
      'WHERE l.account_id = ? AND e.is_posted = 1 AND e.is_deleted = 0',
      variables: [Variable.withInt(accumAccountId)],
    ).getSingle();
    return (r.data['v'] as num).toDouble();
  }

  /// مجمَّعُ الإهلاك كما تراه **البطاقة**.
  Future<double> cardAccumulated() async =>
      (await (db.select(db.fixedAssets)..where((a) => a.id.equals(assetId)))
              .getSingle())
          .accumulatedDepreciation;

  Future<List<AssetDepreciationData>> depreciationRows() =>
      db.select(db.assetDepreciations).get();

  setUp(() async {
    db = AppDatabase.forTesting();
    await db.syncDefaultAccounts();
    await db.into(db.fiscalYears).insert(
          FiscalYearsCompanion.insert(
            name: '2026',
            startDate: DateTime(2026, 1, 1),
            endDate: DateTime(2026, 12, 31),
          ),
        );

    final assetAcc = (await db.getAccountByCode('1213'))!;
    accumAccountId = (await db.getAccountByCode('1219'))!.id;
    final categoryId = await db.createAssetCategory(
      name: 'آلاتٌ',
      accountId: assetAcc.id,
      depreciationAccountId: accumAccountId,
    );

    // ١٢٠٠٠ على ٥ سنوات بالقسط الثابت = ٢٠٠ شهريّاً بالضبط.
    assetId = await db.createFixedAsset(
      code: 'FA-1',
      name: 'آلةٌ',
      categoryId: categoryId,
      purchasePrice: 12000,
      purchaseDate: DateTime(2026, 1, 1),
      usefulLifeYears: 5,
      contraAccountId: (await db.getAccountByCode('2111'))!.id,
    );
  });

  tearDown(() => db.close());

  test('⚓ مرساة: الشهرُ الأوّل يُرحَّل فعلاً', () async {
    // بلا هذه المرساةِ يمرّ كلُّ فحصٍ أدناه أخضرَ لو كان الإهلاكُ لا يُرحّل
    // شيئاً أصلاً — «متساويان عند صفر» يُشبه «متساويان».
    await db.runMonthlyDepreciation(DateTime(2026, 3, 28));
    expect(await ledgerAccumulated(), closeTo(200, 0.005));
    expect(await cardAccumulated(), closeTo(200, 0.005));
  });

  test('🔴 وثلاثةُ أشهرٍ تُرحَّل ثلاثةَ قيودٍ — لا قيداً واحداً', () async {
    for (final m in [3, 4, 5]) {
      await db.runMonthlyDepreciation(DateTime(2026, m, 28));
    }

    final entries = await (db.select(db.journalEntries)
          ..where((e) => e.referenceType.equals('asset_depreciation')))
        .get();
    expect(entries, hasLength(3),
        reason: 'قيدٌ واحدٌ لثلاثةِ أشهر ⇒ مفتاحُ الإزالة ابتلع الشهرَين '
            'التاليَين. والأصلُ يبقى مُهلَكاً في بطاقته ومضخَّماً في '
            'الميزانيّة إلى الأبد.');

    // وكلُّ صفِّ إهلاكٍ يشير إلى قيدِه هو — لا إلى قيدِ الشهر الأوّل.
    final rows = await depreciationRows();
    expect(rows, hasLength(3));
    final jeIds = rows.map((r) => r.journalEntryId).toSet();
    expect(jeIds, hasLength(3),
        reason: 'صفوفُ إهلاكٍ تتشارك رقمَ قيدٍ واحدٍ ⇒ اثنان منها يدّعيان '
            'ترحيلاً لم يقع، فيبدو الدفترُ مكتملاً وهو ليس كذلك.');
  });

  test('🔴 والأستاذُ يساوي البطاقةَ بعد ثلاثةِ أشهر', () async {
    for (final m in [3, 4, 5]) {
      await db.runMonthlyDepreciation(DateTime(2026, m, 28));
    }
    final ledger = await ledgerAccumulated();
    final card = await cardAccumulated();

    expect(card, closeTo(600, 0.005), reason: '٣ × ٢٠٠');
    expect(ledger, closeTo(card, 0.005),
        reason: 'الأستاذُ ${ledger.toStringAsFixed(2)} والبطاقةُ '
            '${card.toStringAsFixed(2)} — الفرقُ أصولٌ مضخَّمةٌ في الميزانيّة '
            'ومصروفٌ منقوصٌ في قائمة الدخل.');
  });

  test('🔴 وإعادةُ تشغيلِ نفسِ الشهر لا تُرحّل مرّتين', () async {
    // الفحصُ الذي يجعل الإصلاحَ إصلاحاً: رفعُ الحمايةِ من مفتاح
    // `(referenceType, referenceId)` لا يجوز أن يفتح ترحيلاً مزدوجاً.
    // الحارسُ الحقيقيُّ هو `(assetId, periodDate)` في `runMonthlyDepreciation`.
    await db.runMonthlyDepreciation(DateTime(2026, 3, 28));
    await db.runMonthlyDepreciation(DateTime(2026, 3, 28));
    await db.runMonthlyDepreciation(DateTime(2026, 3, 28));

    expect(await depreciationRows(), hasLength(1),
        reason: 'صفُّ إهلاكٍ مكرَّرٌ لنفس الشهر');
    expect(await ledgerAccumulated(), closeTo(200, 0.005),
        reason: 'إهلاكٌ مضاعفٌ لشهرٍ واحد ⇒ الإصلاحُ استبدل عطباً بأسوأَ '
            'منه: أصولٌ منقوصةٌ ومصروفٌ مضخَّم.');
    expect(await cardAccumulated(), closeTo(200, 0.005));
  });

  test('وكلُّ قيدٍ بمبلغِ شهرِه ومؤرَّخٌ به', () async {
    for (final m in [3, 4, 5]) {
      await db.runMonthlyDepreciation(DateTime(2026, m, 28));
    }
    final entries = await (db.select(db.journalEntries)
          ..where((e) => e.referenceType.equals('asset_depreciation'))
          ..orderBy([(e) => OrderingTerm.asc(e.entryDate)]))
        .get();

    expect(entries.map((e) => e.entryDate.month).toList(), [3, 4, 5],
        reason: 'قيدُ الإهلاك مؤرَّخٌ بغير شهرِه ⇒ يقع في الفترة الخطأ '
            'وتخرج قائمةُ الدخل الشهريّةُ مشوّهة.');

    for (final e in entries) {
      final lines = await (db.select(db.journalEntryLines)
            ..where((l) => l.entryId.equals(e.id)))
          .get();
      final credit = lines
          .where((l) => l.accountId == accumAccountId)
          .fold<double>(0, (a, l) => a + l.credit);
      expect(credit, closeTo(200, 0.005), reason: 'القيد #${e.id}');
    }
  });
}
