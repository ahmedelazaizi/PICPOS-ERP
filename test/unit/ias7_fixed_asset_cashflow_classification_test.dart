// ═══════════════════════════════════════════════════════════════════════════
// قائمةُ التدفّقات النقديّة تُصنّف تدفّقاتِ الأصول الثابتة **خطأً**
// (‏IAS 7.14 مقابلَ IAS 7.16)
// ═══════════════════════════════════════════════════════════════════════════
//
// 🔴 المحرّكُ والتقريرُ يتكلّمان لغتَين مختلفتَين في `reference_type`:
//
//   `fixed_assets_dao_ext.dart` يكتب فعلاً:
//     'fixed_asset'            ← الاقتناء   (سطر ٢٦٧)
//     'fixed_asset_disposal'   ← الاستبعاد  (سطر ٦٣٢)
//     'asset_transfer' · 'asset_revaluation' · 'asset_depreciation'
//
//   و`accounting_reports_dao.dart` يرشّح على مجموعةٍ **أخرى**:
//     الأنشطةُ التشغيليّة (٧.١٤): NOT IN ('asset_acquisition', 'asset_disposal', …)
//     الأنشطةُ الاستثماريّة (٧.١٦): IN ('asset_acquisition', 'asset_disposal', …)
//
// و`asset_acquisition` و`asset_disposal` **لا يكتبهما شيءٌ في المستودع
// كلِّه** — قيمتان وهميّتان. فالنتيجةُ المزدوجة لكلِّ شراءٍ أو بيعِ أصلٍ
// نقداً:
//   (أ) الحركةُ لا تُستثنى من التشغيليّة فتُعَدُّ تشغيليّةً، وتسقط في
//       فرع `default:` فتُحتسَب «مقبوضاتٍ/مدفوعاتٍ أخرى»؛
//   (ب) ولا تظهر في الاستثماريّة إطلاقاً — تُقرأ صفراً.
//
// و`asset_transfer` و`asset_revaluation` مطابقان في الطرفَين، فهما سليمان
// أصلاً — العطبُ محصورٌ في الاقتناء والاستبعاد، وهما عينُ الحركتَين
// اللتَين تحملان نقداً.
//
// وصافي التغيّر في النقديّة يبقى **صحيحاً** لأنّ المبلغَ لم يضِعْ بل وقع
// في القِسم الخطأ — ولهذا لا يمسكه أيُّ فحصِ اتّزان. والمكسورُ هو الفصلُ
// بين التشغيليِّ والاستثماريِّ، وهو الغرضُ الأوّلُ من القائمة: قارئُها
// يرى شركةً تستهلك نقدَها في التشغيل بينما هي تشتري أصولاً.
//
// ⚠️ والاختبارُ يقود **المحرّكَ الحقيقيَّ** (`createFixedAsset` /
// `disposeAsset`) لا قيوداً مكتوبةً بيدي: لو نُسخت القيمةُ النصّيّةُ هنا
// لصار الاختبارُ يحرس ظنَّي بما يكتبه المحرّك لا ما يكتبه فعلاً، فيبقى
// أخضرَ لو انحرف الطرفان معاً.

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/data/database/database.dart';

void main() {
  late AppDatabase db;
  late int categoryId;

  // نافذةُ التقرير — كلُّ الحركات داخلها فالرصيدُ الافتتاحيُّ صفر.
  final from = DateTime(2026, 5, 1);
  final to = DateTime(2026, 5, 31);

  setUp(() async {
    db = AppDatabase.forTesting();
    await db.syncDefaultAccounts();
    final vehicles = await (db.select(db.accounts)
          ..where((a) => a.code.equals('1213')))
        .getSingle();
    categoryId = await db.into(db.assetCategories).insert(
          AssetCategoriesCompanion.insert(
            name: 'مركبات',
            accountId: Value(vehicles.id),
          ),
        );
  });

  tearDown(() => db.close());

  /// يزرع المشهدَ: اقتناءان نقديّان واستبعادٌ نقديٌّ واحد.
  ///
  /// الاستبعادُ عند **قيمةٍ دفتريّةٍ مساوية** عمداً (‏مكسب/خسارة = صفر):
  /// حسابا المكسب/الخسارة `4314` و`642` يزرعهما
  /// `database_seeder_accounts.dart` لا `syncDefaultAccounts()` التي تكتفي
  /// بها هذه التجهيزة. و`disposeAsset` يتخطّى رِجْلَ المكسب/الخسارة صامتاً
  /// حين لا يجد حسابَها، فيصير القيدُ غيرَ متوازنٍ ويرفضه
  /// `createJournalEntry` — فتتراجع المعاملةُ ويُخلَط عطبٌ آخرُ بالعطب
  /// المقيس هنا.
  ///
  /// (‏وهذا قيدُ تجهيزةٍ لا عطبٌ في المنتج: الزرعَ الكاملَ يُجري المسارُ
  /// الحقيقيُّ عند الإقلاع، فالمكسب/الخسارةُ تُرحَّل هناك بلا خلل.)
  Future<void> seedCashAssetFlows() async {
    // أصلٌ باقٍ: خروجُ نقدٍ ١٠٠٠٠٠ (‏مدين 1213 / دائن 1111 افتراضاً).
    await db.createFixedAsset(
      code: 'V-001',
      name: 'سيارة باقية',
      categoryId: categoryId,
      purchasePrice: 100000,
      purchaseDate: DateTime(2026, 5, 2),
      usefulLifeYears: 5,
    );

    // أصلٌ يُشترى ثمّ يُباع: خروجُ ٣٠٠٠٠ ثمّ دخولُ ٣٠٠٠٠.
    final soldId = await db.createFixedAsset(
      code: 'V-002',
      name: 'سيارة مبيعة',
      categoryId: categoryId,
      purchasePrice: 30000,
      purchaseDate: DateTime(2026, 5, 3),
      usefulLifeYears: 5,
    );
    await db.disposeAsset(
      soldId,
      disposalValue: 30000,
      disposalDate: DateTime(2026, 5, 20),
    );
  }

  test('التجهيزة: المحرّكُ يرحّل الاقتناءَ والاستبعادَ على حسابِ النقديّة',
      () async {
    await seedCashAssetFlows();
    final cash = await db.getAccountByCode('1111');
    expect(cash, isNotNull);

    // شرطٌ مسبق: لولا وجودُ رِجْلِ نقدٍ في القيدَين لما قاس الاختبارُ شيئاً
    // — الترشيحان في التقرير **كلاهما** مقيَّدٌ بحسابات النقد/البنك، فقيدٌ
    // بلا نقدٍ يُقرأ صفراً في الطرفَين ويمرّ الاختبارُ زوراً.
    final cashLines = await db.customSelect(
      'SELECT je.reference_type AS rt, jel.debit AS d, jel.credit AS c '
      'FROM journal_entry_lines jel '
      'INNER JOIN journal_entries je ON je.id = jel.entry_id '
      'WHERE jel.account_id = ${cash!.id}',
    ).get();
    final refTypes = cashLines.map((r) => r.data['rt'] as String).toSet();
    expect(refTypes.length, 2,
        reason: 'حركتان نقديّتان: اقتناءٌ واستبعاد — $refTypes');
  });

  test('شراءُ أصلٍ نقداً يقع في الأنشطة الاستثماريّة لا التشغيليّة (‏IAS 7.16)',
      () async {
    await seedCashAssetFlows();
    final cf = await db.getCashFlowStatement(from, to);
    final investing = cf['investing'] as Map<String, dynamic>;

    expect((investing['assetPurchases'] as num).toDouble(),
        closeTo(130000.0, 0.01),
        reason: 'خروجُ النقدِ لشراء أصلَين (١٠٠٠٠٠ + ٣٠٠٠٠) استثماريٌّ '
            'بنصِّ IAS 7.16 — والتقريرُ يرشّح على `asset_acquisition` '
            'التي لا يكتبها المحرّك، فيقرأ صفراً');
  });

  test('بيعُ أصلٍ نقداً يقع في الأنشطة الاستثماريّة لا التشغيليّة (‏IAS 7.16)',
      () async {
    await seedCashAssetFlows();
    final cf = await db.getCashFlowStatement(from, to);
    final investing = cf['investing'] as Map<String, dynamic>;

    expect((investing['assetDisposals'] as num).toDouble(),
        closeTo(30000.0, 0.01),
        reason: 'دخولُ نقدِ بيعِ الأصل استثماريٌّ — والترشيحُ على '
            '`asset_disposal` وهميٌّ والمحرّكُ يكتب `fixed_asset_disposal`');
    expect((investing['net'] as num).toDouble(), closeTo(-100000.0, 0.01),
        reason: 'صافي الاستثماريّة = ٣٠٠٠٠ داخل − ١٣٠٠٠٠ خارج');
  });

  test('تدفّقاتُ الأصول **لا** تتسرّب إلى الأنشطة التشغيليّة (‏IAS 7.14)',
      () async {
    await seedCashAssetFlows();
    final cf = await db.getCashFlowStatement(from, to);
    final operating = cf['operating'] as Map<String, dynamic>;

    expect((operating['totalOutflow'] as num).toDouble(), closeTo(0.0, 0.01),
        reason: 'لا نشاطَ تشغيليّاً في المشهد — وشراءُ الأصول يتسرّب هنا '
            'لأنّ `NOT IN` يستثني اسماً لا يُكتَب');
    expect((operating['totalInflow'] as num).toDouble(), closeTo(0.0, 0.01),
        reason: 'بيعُ الأصل يتسرّب هنا للسبب نفسِه');
    expect((operating['net'] as num).toDouble(), closeTo(0.0, 0.01));

    // وهذان يثبّتان **شكلَ** التسرّب: فرعُ `default:` يصنّفهما
    // «مقبوضاتٍ/مدفوعاتٍ أخرى»، فهما الحقلان اللذان يراهما المستخدم.
    expect((operating['paymentsToSuppliers'] as num).toDouble(),
        closeTo(0.0, 0.01),
        reason: 'شراءُ أصلٍ ليس دفعةً لموردٍ في القائمة');
    expect((operating['receiptsFromCustomers'] as num).toDouble(),
        closeTo(0.0, 0.01),
        reason: 'بيعُ أصلٍ ليس تحصيلاً من عميل');
  });

  test('صافي التغيّر في النقديّة صحيحٌ — العطبُ في الفصل لا في المجموع',
      () async {
    await seedCashAssetFlows();
    final cf = await db.getCashFlowStatement(from, to);

    // هذا التوكيدُ **أخضرُ قبل الإصلاح وبعده** بقصد: هو حارسُ الانحدار
    // الذي يمنع «إصلاحاً» ينقل المبلغَ إلى الاستثماريّة ويُسقطه من المجموع.
    expect((cf['netChange'] as num).toDouble(), closeTo(-100000.0, 0.01),
        reason: 'صافي التغيّر لم يكن معطوباً أصلاً — ويجب أن يبقى');
    expect((cf['openingBalance'] as num).toDouble(), closeTo(0.0, 0.01));
    expect((cf['closingBalance'] as num).toDouble(), closeTo(-100000.0, 0.01));

    final operating = cf['operating'] as Map<String, dynamic>;
    final investing = cf['investing'] as Map<String, dynamic>;
    final financing = cf['financing'] as Map<String, dynamic>;
    expect(
      (operating['net'] as num).toDouble() +
          (investing['net'] as num).toDouble() +
          (financing['net'] as num).toDouble(),
      closeTo(-100000.0, 0.01),
      reason: 'الأقسامُ الثلاثةُ تجمع إلى صافي التغيّر — اتّزانُ IAS 7',
    );
  });

  // ─── البندُ ٣: `asset_depreciation` غائبٌ عن القائمتَين ────────────────
  //
  // الإهلاكُ في المنهج **غير المباشر** إضافةٌ عكسيّةٌ غيرُ نقديّةٍ إلى الربح
  // (‏IAS 7.20). لكنّ هذا التقريرَ يبني القائمةَ بالمنهج **المباشر**: يجمع
  // رِجْلَ النقدِ الفعليّةَ من القيود ولا يبدأ من الربح إطلاقاً. فلا إضافةَ
  // عكسيّةً تُصنَع هنا، وغيابُ `asset_depreciation` عن القائمتَين **صحيحٌ**
  // لا سهوٌ — بشرطِ أن يكون قيدُ الإهلاك خالياً من النقد فعلاً.
  //
  // وهذا الشرطُ هو ما يقيسه الاختبارُ بدلاً من افتراضِه.
  test('الإهلاكُ لا يمسّ نقداً — فغيابُه عن القائمتَين بلا أثر', () async {
    await seedCashAssetFlows();
    final before = await db.getCashFlowStatement(from, to);

    final count = await db.runMonthlyDepreciation(DateTime(2026, 5, 31));
    expect(count, greaterThan(0),
        reason: 'بلا قيدِ إهلاكٍ فعليٍّ لا يقيس هذا الاختبارُ شيئاً');

    // قيدُ الإهلاكِ موجودٌ فعلاً بالاسم الذي يكتبه المحرّك.
    final depEntries = await (db.select(db.journalEntries)
          ..where((j) => j.referenceType.equals('asset_depreciation')))
        .get();
    expect(depEntries, isNotEmpty);

    // ولا رِجْلَ له على أيِّ حسابٍ في شجرة النقديّة/البنوك.
    final cash = await db.getAccountByCode('1111');
    final cashTree = await db.accountSubtreeIds(cash!.parentId ?? cash.id);
    final depLines = await (db.select(db.journalEntryLines)
          ..where((l) => l.entryId.isIn(depEntries.map((e) => e.id))))
        .get();
    expect(depLines, isNotEmpty);
    for (final line in depLines) {
      expect(cashTree.contains(line.accountId), isFalse,
          reason: 'قيدُ الإهلاك: مدين 6213 / دائن مجمَّعُ الإهلاك — ولا '
              'واحدٌ منهما نقديّ. لو صار نقديّاً لوجب تصنيفُه صراحةً');
    }

    // والقائمةُ لم تتحرّك بحرفٍ بعد الإهلاك.
    final after = await db.getCashFlowStatement(from, to);
    for (final section in ['operating', 'investing', 'financing']) {
      final b = before[section] as Map<String, dynamic>;
      final a = after[section] as Map<String, dynamic>;
      expect((a['net'] as num).toDouble(),
          closeTo((b['net'] as num).toDouble(), 0.01),
          reason: 'الإهلاكُ غيرُ نقديٍّ فلا يحرّك قسمَ $section');
    }
    expect((after['netChange'] as num).toDouble(),
        closeTo((before['netChange'] as num).toDouble(), 0.01));
  });
}
