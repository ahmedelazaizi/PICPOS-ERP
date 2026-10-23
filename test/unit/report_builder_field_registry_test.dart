// ═══════════════════════════════════════════════════════════════════════════
// كلُّ حقلٍ يعرضه منشئ التقارير لا بد أن يكون **قابلاً للاختيار فعلاً**.
// ═══════════════════════════════════════════════════════════════════════════
//
// `getAvailableFields(entity)` هي القائمةُ التي تُبنى منها مربّعاتُ اختيار
// الأعمدة في الواجهة. وكان فيها حقولٌ تُترجَم إلى أعمدةٍ **لا وجود لها**:
//
//     المُعلَن            العمودُ الحقيقي
//     price          →   sale_price
//     cost           →   cost_price
//
// فمن يختار «سعر البيع» في تقرير أصناف يحصل على
// `SqliteException(1): no such column: products.price` — التقريرُ كلُّه يفشل، لا
// العمودُ وحده. مقيسٌ تجريبياً 2026-08-09.
//
// وهذه **نفسُ فئة العطل** التي كُتب لها `report_builder_columns_test`
// (‏`payment_status` و`sale_type` كانا نصّين ثابتين باسم حقولٍ حقيقية)، لكن
// ذاك الاختبارُ فحص الحقلَين المعروفَين وحدهما. فهذا يفحص **كلَّ** حقلٍ في
// **كلِّ** كيان: القائمةُ هي العقد، والعقدُ يُفحَص كاملاً لا بالعيّنة.
//
// ⚠️ ويفشل تلقائياً لأيّ حقلٍ يُضاف مستقبلاً بلا خريطةٍ صحيحة — وهو الغرض.
// ═══════════════════════════════════════════════════════════════════════════

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/data/database/database.dart';

void main() {
  late AppDatabase db;

  /// الكياناتُ التي تعرضها الواجهةُ في منسدلة «الكيان».
  const entities = [
    'products',
    'parties',
    'sales_invoices',
    'purchase_invoices',
    'journal_entries',
  ];

  setUp(() async => db = AppDatabase.forTesting());
  tearDown(() => db.close());

  group('كلُّ حقلٍ معروضٍ قابلٌ للاختيار', () {
    for (final entity in entities) {
      test(entity, () async {
        final fields = db.getAvailableFields(entity);
        expect(fields, isNotEmpty,
            reason: 'كيانٌ في المنسدلة بلا حقول = شاشةٌ فارغة');

        final broken = <String>[];
        for (final f in fields) {
          final key = f['key']!;
          final id = await db.into(db.customReports).insert(
                CustomReportsCompanion.insert(
                  name: 'ت-$key',
                  sourceEntity: entity,
                  columns: key,
                ),
              );
          try {
            await db.executeReport(id);
          } catch (e) {
            broken.add('$key → ${e.toString().split('\n').first}');
          }
        }

        expect(broken, isEmpty,
            reason: 'حقولٌ معروضةٌ للمستخدم وتُفشل التقريرَ كلَّه:\n'
                '${broken.join('\n')}');
      });
    }
  });

  group('الحقولُ المعروضةُ تُرجِع أعمدةً بأسمائها', () {
    test('اسمُ العمود في الناتج هو المفتاحُ المعروض لا اسمُ العمود الخام',
        () async {
      await db.into(db.products).insert(ProductsCompanion.insert(
          code: 'P1', name: 'قلم', salePrice: const Value(25)));

      final id = await db.into(db.customReports).insert(
            CustomReportsCompanion.insert(
              name: 'ت',
              sourceEntity: 'products',
              columns: 'name, price, cost',
            ),
          );

      final rows = await db.executeReport(id);
      expect(rows, isNotEmpty);
      expect(rows.first.keys, containsAll(<String>['name', 'price', 'cost']),
          reason: 'الواجهةُ تبني رؤوسَ الجدول من مفاتيح الناتج، فلو رجع '
              '`sale_price` ظهر عمودٌ باسمٍ لم يختره المستخدم');
      expect(rows.first['price'], 25);
    });

    test('نوعُ الطرف يُشتقّ من صفتَيه لا من عمودٍ مفقود', () async {
      await db.into(db.parties).insert(PartiesCompanion.insert(
          name: 'عميل فقط',
          isCustomer: const Value(true),
          isSupplier: const Value(false)));
      await db.into(db.parties).insert(PartiesCompanion.insert(
          name: 'الاثنان',
          isCustomer: const Value(true),
          isSupplier: const Value(true)));

      final id = await db.into(db.customReports).insert(
            CustomReportsCompanion.insert(
                name: 'ت', sourceEntity: 'parties', columns: 'name, type'),
          );

      final rows = await db.executeReport(id);
      final byName = {for (final r in rows) r['name']: r['type']};
      expect(byName['عميل فقط'], 'عميل');
      expect(byName['الاثنان'], 'عميل ومورد',
          reason: 'الطرفُ قد يكون الاثنين — لا تُختصر إحداهما');
    });

    test('إجماليّا القيد من سطوره وحدها لا من كل السطور', () async {
      // قيدان: لو جمع الاستعلامُ الفرعيُّ سطورَ **كلِّ** القيود لظهر ٣٠٠ في
      // الاثنين. والطفرةُ التي تُسقط شرطَ الترابط تنجو بلا هذا الاختبار.
      final acc = await db.into(db.accounts).insert(AccountsCompanion.insert(
          code: '9001', name: 'حساب اختبار', accountType: 'expense'));
      Future<int> entry(String number, double amount) async {
        final id = await db.into(db.journalEntries).insert(
              JournalEntriesCompanion.insert(
                  entryNumber: number, entryDate: DateTime(2026, 8, 1)),
            );
        await db.into(db.journalEntryLines).insert(
            JournalEntryLinesCompanion.insert(
                entryId: id, accountId: acc, debit: Value(amount)));
        await db.into(db.journalEntryLines).insert(
            JournalEntryLinesCompanion.insert(
                entryId: id, accountId: acc, credit: Value(amount)));
        return id;
      }

      await entry('JE-1', 100);
      await entry('JE-2', 200);

      final id = await db.into(db.customReports).insert(
            CustomReportsCompanion.insert(
                name: 'ت',
                sourceEntity: 'journal_entries',
                columns: 'entry_number, total_debit, total_credit'),
          );

      final rows = await db.executeReport(id);
      final byNum = {for (final r in rows) r['entry_number']: r};
      expect(byNum['JE-1']!['total_debit'], 100);
      expect(byNum['JE-1']!['total_credit'], 100);
      expect(byNum['JE-2']!['total_debit'], 200,
          reason: 'شرطُ الترابط `jel.entry_id = journal_entries.id` هو ما '
              'يمنع جمعَ سطورِ كلِّ القيود في كل صفّ');
      expect(rows.length, 2, reason: 'استعلامٌ فرعيٌّ لا JOIN — لا تضاعف');
    });
  });
}
