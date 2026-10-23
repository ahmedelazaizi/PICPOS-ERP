// ═══════════════════════════════════════════════════════════════════════════
// كلُّ عاملٍ تعرضه واجهةُ الفلتر لا بد أن يقبله المحرِّك — القائمةُ واحدة.
// ═══════════════════════════════════════════════════════════════════════════
//
// واجهةُ الفلتر تبني منسدلةَ العامل من [getFilterOperators]، والمحرِّك يرفض
// أيَّ عاملٍ خارج قائمته. فلو كانت القائمتان اثنتين لأمكن أن تعرض الواجهةُ
// عاملاً يُنتج تقريراً **مرفوضاً بالكامل** — والمستخدم يرى صفراً من الصفوف
// بلا سببٍ ظاهر، لا رسالةَ خطأ ولا حقلاً معطَّلاً.
//
// وهذه نفسُ فئةِ العطل التي كُتب لها `report_builder_field_registry_test`:
// قائمةٌ تعرضها الواجهةُ وتخالف ما ينفّذه المحرِّك. وذاك فحص **الحقول**،
// وهذا يفحص **العوامل** — وحاصلُ ضربِهما هو ما يستطيع المستخدمُ بناءه فعلاً.
//
// ⚠️ ويفشل تلقائياً لأيّ عاملٍ أو حقلٍ يُضاف مستقبلاً لأحد الطرفين وحده.
// ═══════════════════════════════════════════════════════════════════════════

import 'dart:convert';

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/data/database/database.dart';

void main() {
  late AppDatabase db;

  const entities = [
    'products',
    'parties',
    'sales_invoices',
    'purchase_invoices',
    'journal_entries',
  ];

  /// قيمةٌ تليق بالنوع — الغرضُ فحصُ القبول لا فحصُ النتيجة.
  Object sampleFor(String type) => switch (type) {
        'number' => 1,
        'date' => '2026-08-10',
        'boolean' => true,
        _ => 'س',
      };

  setUp(() async => db = AppDatabase.forTesting());
  tearDown(() => db.close());

  test('كلُّ نوعِ حقلٍ معروضٍ له عواملُ معروضة', () {
    final types = <String>{};
    for (final e in entities) {
      for (final f in db.getAvailableFields(e)) {
        types.add(f['type']!);
      }
    }
    expect(types, isNotEmpty);
    for (final t in types) {
      expect(db.getFilterOperators(t), isNotEmpty,
          reason: 'نوعٌ «$t» بلا عوامل ⇒ حقلٌ لا يمكن الفلترةُ به وهو معروض');
    }
  });

  group('كلُّ (حقل × عامل) تعرضه الواجهةُ يقبله المحرِّك', () {
    for (final entity in entities) {
      test(entity, () async {
        final fields = db.getAvailableFields(entity);
        final rejected = <String>[];

        for (final f in fields) {
          final key = f['key']!;
          final type = f['type']!;
          for (final op in db.getFilterOperators(type)) {
            final id = await db.into(db.customReports).insert(
                  CustomReportsCompanion.insert(
                    name: 'ت-$key-${op['op']}',
                    sourceEntity: entity,
                    columns: key,
                    filters: Value(jsonEncode([
                      {
                        'field': key,
                        'op': op['op'],
                        'value': sampleFor(type),
                      }
                    ])),
                  ),
                );
            try {
              await db.executeReport(id);
            } catch (e) {
              rejected.add('$key ${op['op']} → '
                  '${e.toString().split('\n').first}');
              continue;
            }
            // ‏«صفرُ صفوفٍ» ليس دليلاً — الجداولُ فارغة. الدليلُ أن الاستعلامَ
            // **نُفِّذ**: سجلُّ التشغيل لا يُكتَب على المسار المرفوض.
            final ran = await (db.select(db.savedReportRuns)
                  ..where((r) => r.reportId.equals(id)))
                .get();
            if (ran.isEmpty) rejected.add('$key ${op['op']} → رُفض التقرير');
          }
        }

        expect(rejected, isEmpty,
            reason: 'عواملُ تعرضها الواجهةُ ويرفضها المحرِّك:\n'
                '${rejected.join('\n')}');
      });
    }
  });

  test('عاملٌ خارج القائمة المعروضة يبقى مرفوضاً', () async {
    // الحارسُ أعلاه يثبت أن المعروضَ مقبول؛ وهذا يثبت أن القائمة **تحصر**
    // فعلاً، وإلا لمرّ كلُّ شيء ومرّ الحارسُ معه بلا معنى.
    final id = await db.into(db.customReports).insert(
          CustomReportsCompanion.insert(
            name: 'ت',
            sourceEntity: 'products',
            columns: 'name',
            filters: Value(jsonEncode([
              {'field': 'name', 'op': 'REGEXP', 'value': 'س'}
            ])),
          ),
        );
    await db.executeReport(id);
    expect(await db.select(db.savedReportRuns).get(), isEmpty);
  });
}
