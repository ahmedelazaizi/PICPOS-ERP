// زرُّ الإجراء داخل صفٍّ قابلٍ للتحديد — أيُّهما يلتقط النقرة؟
//
// ── البلاغ الميدانيّ (2026-08-20) ───────────────────────────────────────────
// «في شاشة فواتير المبيعات، عند الضغط على زر معاينة الفاتورة بدلاً منها
// بيتم تحديد الصف ولا يفتح المعاينة.»
//
// ── لماذا اختبارٌ لا قراءةُ كود ───────────────────────────────────────────
// `AppDataTable` يبني على `DataTable2` (حزمةٌ خارجيّة، تحويلٌ لأجل الأداء).
// وقراءةُ مصدرها تُظهر أنها تلفّ **كلَّ خليّة** بـ
// `TableRowInkWell(onTap: onRowTap ?? onSelectChanged)` متى كانت الخليّةُ
// بلا `onTap` خاصّ (data_table_2.dart:613-617).
//
// لكنّ ذلك وحدَه لا يحسم النتيجة: في ساحة إيماءات Flutter يفوز المتعرِّفُ
// الأعمقُ عادةً، فالمفروضُ أن يبتلع `IconButton` النقرةَ ولا يصل الصفُّ
// شيء. فالسؤالُ سلوكيٌّ لا نصّيّ، وجوابُه لا يُؤخذ إلا بالتشغيل.
//
// هذا الاختبار يقيس السلوكَ الفعليّ ولا يفترضه.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/presentation/widgets/common/app_data_table.dart';

void main() {
  // ── المحاكاةُ المطابقةُ للشاشة الحقيقيّة ────────────────────────────────
  //
  // البلاغُ الثاني (2026-08-20) حسم الاتّجاه: «زرُّ التعديل يُظلَّل ويُظهر
  // تلميحَه عند الاقتراب، أمّا العينُ فلا ردَّ فعلَ لها إطلاقاً، والنقرُ
  // عليها كالنقر على أيّ مكانٍ في الصفّ».
  //
  // وغيابُ التظليل **والتلميح** معاً يُخرج المسألةَ من المنطق إلى التخطيط:
  // الزرُّ لا يستقبل مؤشِّراً أصلاً. وفي Flutter ما يقع خارجَ حدود أبيه
  // يُرسَم ولا يُختبَر بالإصابة — فتعبر النقرةُ إلى الصفّ تحته.
  //
  // والفارقُ عن الاختبار الأول أعمدةٌ عشرةٌ بلا `minWidth`: `DataTable2`
  // يقسم العرضَ بالتساوي، فتضيق خليّةُ الإجراءات عن أربعة أزرارٍ عرضُ
  // كلٍّ منها 48 (192 مجموعاً).
  testWidgets(
    'خليّةُ إجراءاتٍ بأربعة أزرارٍ في جدولٍ عشاريِّ الأعمدة لا تُخرج زرّاً '
    'خارج حدودها',
    (tester) async {
      tester.view.physicalSize = const Size(1600, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final tapped = <String>[];
      var rowSelectionToggles = 0;

      Widget iconBtn(String id, IconData icon) => IconButton(
            key: Key('btn-$id'),
            icon: Icon(icon, size: 18),
            tooltip: id,
            onPressed: () => tapped.add(id),
          );

      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => Directionality(
            textDirection: TextDirection.rtl,
            child: child!,
          ),
          home: Scaffold(
            body: Column(
              children: [
                Expanded(
                  child: AppDataTable(
                    // نفسُ إعداد الشاشة: تحديدٌ بمربّعات، وبلا `minWidth`.
                    showCheckboxColumn: true,
                    columns: const [
                      DataColumn(label: Text('رقم الفاتورة')),
                      DataColumn(label: Text('العميل')),
                      DataColumn(label: Text('التاريخ')),
                      DataColumn(label: Text('الإجمالي')),
                      DataColumn(label: Text('المدفوع')),
                      DataColumn(label: Text('المتبقي')),
                      DataColumn(label: Text('الحالة')),
                      DataColumn(label: Text('الفرع / المخزن')),
                      DataColumn(label: Text('مركز التكلفة')),
                      // نفسُ إعلان الشاشة بعد الإصلاح. أعِدْها
                      // `DataColumn(label: Text('الإجراءات'))` وسيسقط هذا
                      // الاختبارُ بـ`['edit','print','delete']` — أي أنّ
                      // العينَ ماتت، وهو العطبُ الأصليّ بعينه.
                      DataColumn2(label: Text('الإجراءات'), fixedWidth: 210),
                    ],
                    rows: [
                      DataRow(
                        selected: false,
                        onSelectChanged: (_) => rowSelectionToggles++,
                        cells: [
                          const DataCell(Text('SINV-5')),
                          const DataCell(Text('عميل نقدي')),
                          const DataCell(Text('2026-08-20')),
                          const DataCell(Text('48.930')),
                          const DataCell(Text('48.930')),
                          const DataCell(Text('0.000')),
                          const DataCell(Text('مدفوع')),
                          const DataCell(Text('الفرع الرئيسي')),
                          const DataCell(Text('—')),
                          DataCell(
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                iconBtn('view', Icons.visibility),
                                iconBtn('edit', Icons.edit),
                                iconBtn('print', Icons.print),
                                iconBtn('delete', Icons.delete),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // كلُّ زرٍّ على حدة — أيُّها يستقبل النقرة وأيُّها تعبر منه إلى الصفّ.
      for (final id in ['view', 'edit', 'print', 'delete']) {
        await tester.tap(find.byKey(Key('btn-$id')), warnIfMissed: false);
        await tester.pumpAndSettle();
      }

      expect(
        tapped,
        ['view', 'edit', 'print', 'delete'],
        reason: 'زرٌّ أو أكثرُ لم يستقبل النقرة — وقع خارج حدود خليّته',
      );
      expect(
        rowSelectionToggles,
        0,
        reason: 'نقرةٌ تسرّبت إلى الصفّ فحُدِّد بدل أن يعمل الزرّ',
      );
    },
  );

  testWidgets(
    'نقرةٌ على زرِّ إجراءٍ داخل صفٍّ قابلٍ للتحديد تُشغِّل الزرَّ وحدَه',
    (tester) async {
      var viewTaps = 0;
      var rowSelectionToggles = 0;

      await tester.pumpWidget(
        MaterialApp(
          // الشاشةُ الحقيقيّةُ كلُّها RTL — واتّجاهُ النصّ يقلب ترتيبَ أبناء
          // الـ`Row` أفقيّاً، فيغيّر أيَّ زرٍّ يقع تحت أيّ إحداثيّ.
          builder: (context, child) => Directionality(
            textDirection: TextDirection.rtl,
            child: child!,
          ),
          home: Scaffold(
            // `DataTable2` يُوَلِّد ListView مُفَرْدَناً فيلزمه ارتفاعٌ محدود —
            // وهو ما يوفّره `Expanded` هنا كما يوفّره الأب في الشاشة الحقيقيّة.
            body: Column(
              children: [
                Expanded(
                  child: AppDataTable(
                  showCheckboxColumn: true,
                  minWidth: 400,
                  columns: const [
                    DataColumn(label: Text('رقم')),
                    DataColumn(label: Text('الإجراءات')),
                  ],
                  rows: [
                    DataRow(
                      selected: false,
                      onSelectChanged: (_) => rowSelectionToggles++,
                      cells: [
                        const DataCell(Text('SINV-4')),
                        // نفسُ بنية خليّة الإجراءات في الشاشة: `Row` بـ
                        // `MainAxisSize.min` وأربعةُ أزرار، والعينُ أوّلُها.
                        DataCell(
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                key: const Key('view-btn'),
                                icon: const Icon(Icons.visibility, size: 18),
                                tooltip: 'عرض التفاصيل',
                                onPressed: () => viewTaps++,
                              ),
                              IconButton(
                                icon: const Icon(Icons.edit, size: 18),
                                tooltip: 'تعديل',
                                onPressed: () {},
                              ),
                              IconButton(
                                icon: const Icon(Icons.print, size: 18),
                                tooltip: 'طباعة',
                                onPressed: () {},
                              ),
                              IconButton(
                                icon: const Icon(Icons.delete, size: 18),
                                tooltip: 'حذف',
                                onPressed: () {},
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('view-btn')));
      await tester.pumpAndSettle();

      // المتوقَّع: الزرُّ يعمل، والصفُّ لا يُحدَّد.
      expect(viewTaps, 1, reason: 'زرُّ المعاينة لم يُشغَّل بالنقر عليه');
      expect(
        rowSelectionToggles,
        0,
        reason: 'النقرةُ تسرّبت إلى الصفّ فحُدِّد بدل أن تُفتح المعاينة',
      );
    },
  );
}
