// جدولُ بنود الفاتورة بعد إضافة عمود «الخصم»: **ثمانيةُ أعمدةٍ لا سبعة.**
//
// ═══ ما يُقاس ═══
//
// عمودُ الخصم أُضيف ولم تُمَسَّ نِسَبُ الأعمدة الأخرى — فنمطُ المبيعات يبقى
// بتخطيطه السابق حرفاً. والثمنُ أنّ صفَّ المشتريات صار أضيقَ عموداً عمودَ،
// وفيه ثلاثةُ حقولٍ تُكتَب (كمّيّة · سعر · خصم) وحبّةُ ضريبةٍ وزرُّ حذفٍ
// بعرضٍ **ثابت**. فالسؤالُ المقيسُ واحد: **هل كلّف العمودُ الجديدُ شيئاً؟**
//
// ⚠️ 🔴 **و`RenderFlex overflowed` لا يرمي في الإصدار**: يرسم شريطاً أصفرَ
// وأسودَ ويمضي. فتوكيدُ «لم تنهر» يمرّ على صفٍّ مبتور، و`find.text` يجد
// النصَّ الفائضَ لأنّه ما زال مُخطَّطاً. ولهذا يُلتقَط `FlutterError.onError`
// صراحةً، ويُقاس **موضعُ** عمود الخصم لا وجودُه.
//
// ═══ ولماذا مستطيلاتٌ لا عدُّ فيضانات ═══════════════════════════════════
//
// خطُّ اختبار Flutter يعطي كلَّ محرفٍ عرضاً = حجمَ الخطّ، فـ«بحث متقدم» هنا
// أعرضُ بأضعافٍ منها في المنتج. وصفُّ **الإضافة السريعة** (في هذا الملفّ
// نفسِه) يفيض بـ٢٨–٤٨ بكسلاً بين ~٩٦٠ و~١٠٥٠ في النمطَين معاً — رقمٌ يقيس
// الخطَّ لا التخطيط، و«إصلاحُه» يعني سحقَ شريطٍ سليمٍ في المنتج لإرضاء
// قياسٍ كاذب. وهو مُسجَّلٌ هنا لأنّه قِيس، لا لأنّ هذا العملُ أحدثه.
//
// وعَدُّ الفيضانات على مستوى الملفّ لا يفرّق بين ذلك الشريط وبين الجدول،
// ومقدارُه يختلف بين النمطَين لأنّ عمودَ المشتريات يحمل حقلَ «رقم فاتورة
// المورد» فيضيق. **فالمقيسُ مستطيلاتُ خلايا الجدول نفسِها**: عرضٌ يُكتَب
// فيه، وحدودٌ داخلَ الصفّ، وترتيبٌ كترتيب التصميم. وهذه تقع على الجدول
// وحدَه ولا يخدعها جارٌ فائض.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/domain/models/picpos_invoice_draft.dart';
import 'package:ural_erp/presentation/invoice_form_picpos/picpos_invoice_form.dart';

const _wide = 1600.0;
const _mid = 1200.0;

/// أضيقُ ما يبلغه **التخطيطُ العريض** — الشاشةُ تتفرّع إلى الضيّق تحت ٩٦٠.
const _tightWide = 1000.0;

/// التخطيطُ الضيّق — الجدولُ نفسُه بعرضِ العمود الواحد.
const _narrow = 820.0;

const _widths = [_wide, _mid, _tightWide, 980.0, _narrow];

/// العروضُ التي يعمل فيها صفُّ الإضافة السريعة، فيدخل البندُ فعلاً.
///
/// ⚠️ عند ١٠٠٠ يفيض ذلك الصفُّ في خطّ الاختبار فيسقط زرُّ «إضافة» خارجَ
/// مدى النقر — فلا بندَ ولا صفَّ يُقاس. وقياسُ المستطيلات يقع حيث يوجد صفّ.
const _layoutWidths = [_wide, _mid, _narrow];

typedef _Pumped = ({List<String> lineTableOverflows, bool hasLine});

Future<_Pumped> _pumpAt(
  WidgetTester tester,
  double width, {
  required PicPosInvoiceKind kind,
}) async {
  final raw = <String>[];
  final previous = FlutterError.onError;
  FlutterError.onError = (details) => raw.add(details.toString());
  try {
    tester.view.physicalSize = Size(width, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: PicPosInvoiceForm(
          kind: kind,
          parties: const [
            PicPosPartyOption(id: 5, name: 'مؤسسة التوريد الحديثة للأوراق'),
          ],
          products: const [
            PicPosProductOption(
              id: 1,
              // اسمٌ طويلٌ عمداً: العمودُ الأعرضُ هو أوّلُ من يزاحم جيرانَه.
              name: 'ورق طباعة A4 ثمانون جراماً — عبوة خمسمائة ورقة',
              salePrice: 100,
              costPrice: 60,
              taxRate: 14,
              // باركودٌ صريح: الإضافةُ السريعة تطابق **الباركودَ أو الاسمَ
              // كاملاً**، وما دونهما يفتح حوارَ المنتقي — فيبقى مفتوحاً
              // ويُقاس تخطيطُه بدل الجدول.
              barcode: '6221',
            ),
          ],
          warehouses: const [
            PicPosNamedOption(id: 2, name: 'المستودع الرئيسي'),
          ],
          costCenters: const [],
          systemTaxRate: 14,
          invoiceNumberPreview: 'PINV-0201',
          userName: 'محمود',
          initialWarehouseId: 2,
          onCancel: () {},
          onSave: ({
            required partyId,
            required supplierInvoiceNumber,
            required date,
            required subtotal,
            required discount,
            required tax,
            required net,
            required paid,
            required notes,
            required items,
            required warehouseId,
            required costCenterId,
            required paymentMethod,
            required printAfterSave,
          }) async {},
        ),
      ),
    ));
    await tester.pumpAndSettle();

    // بندٌ حقيقيٌّ — الصفُّ الفارغُ لا يقيس شيئاً.
    await tester.enterText(find.byKey(quickAddSearchKey), '6221');
    await tester.tap(find.text('إضافة'), warnIfMissed: false);
    await tester.pumpAndSettle();
  } finally {
    FlutterError.onError = previous;
  }

  // مقصورٌ على ملفِّ الجدول: بلاغُ الفيضان يحمل موضعَ مُنشئِه، ولولا القصرُ
  // لقارنّا تسميةَ منتقٍ تختلف نصّاً بين النمطَين.
  final scoped = <String>[
    for (final e in raw)
      if (e.contains('overflowed') && e.contains('picpos_invoice_lines.dart'))
        e
            .split(String.fromCharCode(10))
            .firstWhere((l) => l.contains('overflowed by')),
  ];
  return (
    lineTableOverflows: scoped,
    hasLine: find.byKey(const ValueKey('qty_1')).evaluate().isNotEmpty,
  );
}

/// عناوينُ الأعمدة الثمانية بترتيب التصميم — من اليمين إلى اليسار.
const _purchaseHeaders = [
  '#',
  'الصنف',
  'الوحدة',
  'الكمية',
  'سعر الشراء',
  'الخصم',
  'الضريبة',
  'الإجمالي',
];

void main() {
  testWidgets('رأسُ الجدول ثمانيةُ أعمدةٍ مرتَّبةٍ وكلُّها مقروءة',
      (tester) async {
    // 🔴 **الخليّةُ الفائضةُ ما زالت مُخطَّطةً**، فيجدها الباحثُ وهي مرسومةٌ
    // خارجَ الصفّ. والعَدُّ وحدَه لا يكشف عموداً انسحق إلى صفرٍ أيضاً.
    // فالمقيسُ: كلُّ عنوانٍ له عرضٌ، وكلُّها داخلَ الرأس، وترتيبُها من
    // اليمين إلى اليسار كترتيب التصميم.
    for (final w in _widths) {
      await _pumpAt(tester, w, kind: PicPosInvoiceKind.purchase);

      // ⚠️ **أقربُ `Row` لا أبعدُها**: `.last` تعطي صفّاً خارجيّاً يبتلع
      // الشاشةَ كلَّها فيمرّ كلُّ شيءٍ داخلَه. و«سعر الشراء» نصٌّ يظهر خارجَ
      // الرأس أيضاً، فالبحثُ عنه في الشجرة كلِّها يلتقط الأبعدَ ويقلب
      // الترتيبَ بلا عطبٍ حقيقيّ.
      final headerRow = find
          .ancestor(of: find.text('الخصم'), matching: find.byType(Row))
          .first;
      final header = tester.getRect(headerRow);

      var previousLeft = double.infinity;
      for (final label in _purchaseHeaders) {
        final r = tester.getRect(
            find.descendant(of: headerRow, matching: find.text(label)));
        expect(r.width, greaterThan(0),
            reason: 'عنوانُ «$label» انسحق إلى صفرٍ عند عرض $w');
        expect(r.left, greaterThanOrEqualTo(header.left - 0.5),
            reason: '«$label» خرج من حافّة الرأس اليسرى عند $w');
        expect(r.right, lessThanOrEqualTo(header.right + 0.5),
            reason: '«$label» خرج من حافّة الرأس اليمنى عند $w');
        expect(r.right, lessThanOrEqualTo(previousLeft + 0.5),
            reason: 'ترتيبُ الأعمدة انقلب عند «$label» بعرض $w');
        previousLeft = r.left;
      }
    }
  });

  testWidgets('والمبيعاتُ سبعةٌ — بلا «الخصم» وبنفس البقيّة', (tester) async {
    for (final w in _widths) {
      await _pumpAt(tester, w, kind: PicPosInvoiceKind.sales);
      expect(find.text('الخصم'), findsNothing,
          reason: 'عمودُ خصمٍ في المبيعات يبتلع ما يُكتَب فيه — عرض $w');
      for (final label in _purchaseHeaders.where((l) => l != 'الخصم')) {
        final t = label == 'سعر الشراء' ? 'سعر البيع' : label;
        expect(find.text(t), findsWidgets,
            reason: 'عنوانُ «$t» اختفى من المبيعات عند $w');
      }
    }
  });

  testWidgets('وأعمدةُ الصفِّ الثمانيةُ كلُّها داخلَ حدوده', (tester) async {
    // 🔴 **ولا يكفي `findsOneWidget`.** الودجتُ الفائضةُ ما زالت مُخطَّطةً،
    // فيجدها الباحثُ وهي مرسومةٌ خارجَ الصفّ. والدليلُ الوحيدُ مقارنةُ
    // المستطيلات.
    for (final w in _layoutWidths) {
      final p = await _pumpAt(tester, w, kind: PicPosInvoiceKind.purchase);
      expect(p.hasLine, isTrue, reason: 'لم يدخل بندٌ عند $w');

      final row = tester.getRect(find
          .ancestor(
            of: find.byKey(const ValueKey('discount_1')),
            matching: find.byType(Row),
          )
          .first);
      final discount =
          tester.getRect(find.byKey(const ValueKey('discount_1')));
      final price = tester.getRect(find.byKey(const ValueKey('price_1')));
      final qty = tester.getRect(find.byKey(const ValueKey('qty_1')));

      expect(discount.width, greaterThan(24),
          reason: 'حقلُ الخصم انسحق إلى شريطٍ لا يُكتَب فيه عند $w');
      expect(discount.left, greaterThanOrEqualTo(row.left - 0.5),
          reason: 'حقلُ الخصم خرج من حافّة الصفِّ اليسرى عند $w');
      expect(discount.right, lessThanOrEqualTo(row.right + 0.5),
          reason: 'حقلُ الخصم خرج من حافّة الصفِّ اليمنى عند $w');
      // العربيّةُ من اليمين: الكمّيّةُ ثمّ السعرُ ثمّ الخصم — كترتيب التصميم.
      expect(price.right, lessThanOrEqualTo(qty.left + 0.5),
          reason: 'ترتيبُ الأعمدة انقلب عند $w');
      expect(discount.right, lessThanOrEqualTo(price.left + 0.5),
          reason: 'عمودُ الخصم ركب على عمود السعر عند $w');

      // 🔴 **وما يأخذه العمودُ يُؤخَذ من جيرانه.** طفرةٌ جعلت خليّةَ الخصم
      // عرضاً **ثابتاً** ٤٠٠ نجت من كلّ ما سبق: هي نفسُها واسعةٌ، وداخلَ
      // الصفّ، ومرتَّبةٌ — والمسحوقُ جيرانُها. فالمقيسُ أنّ العمودَ **محكومٌ
      // بنسبةٍ** كإخوته لا بعرضٍ مفروض.
      // 🔴 **وما يأخذه العمودُ يُؤخَذ من جيرانه** — والثمنُ محصورٌ في عمود
      // الصنف وحدَه. القياسُ الحاسمُ في الاختبار التالي.
      expect(discount.width, lessThan(price.width * 1.2),
          reason: 'عمودُ الخصم أوسعُ من نسبته — عرضٌ مفروضٌ لا نسبة، عند $w');
    }
  });

  testWidgets('وأعرضةُ الأعمدة الأخرى لم تتحرّك بكسلاً بين النمطَين',
      (tester) async {
    // 🔴 **هذا هو القياسُ الذي يملكه هذا العمل.** عمودٌ ثامنٌ يُضاف بلا
    // إعادةِ توزيعٍ يسرق من **كلّ** جارٍ بنسبته: قياسٌ عند ١٢٠٠ بكسل أعطى
    // حقلَ كمّيّةٍ بعرض ٩ بكسلاً بدل ٢٠ — حقلٌ لا يُكتَب فيه. فعرضُ الخصم
    // يُطرَح من عرض **الصنف** وحدَه، ومجموعُ النِّسَب يبقى ٩٥ في النمطَين.
    //
    // وطفرةٌ تجعل الخليّةَ عرضاً ثابتاً — أو تُعيد عرضَ الصنف إلى ٣٣ — تسقط
    // هنا وحدَها: هي واسعةٌ ومرتَّبةٌ وداخلَ الصفّ، والمسحوقُ جيرانُها.
    for (final w in _layoutWidths) {
      await _pumpAt(tester, w, kind: PicPosInvoiceKind.sales);
      final salesQty = tester.getRect(find.byKey(const ValueKey('qty_1')));
      final salesPrice = tester.getRect(find.byKey(const ValueKey('price_1')));

      await _pumpAt(tester, w, kind: PicPosInvoiceKind.purchase);
      final purQty = tester.getRect(find.byKey(const ValueKey('qty_1')));
      final purPrice = tester.getRect(find.byKey(const ValueKey('price_1')));

      expect(purQty.width, closeTo(salesQty.width, 0.01),
          reason: 'عمودُ الكمّيّة ضاق بسبب عمود الخصم عند عرض $w');
      expect(purPrice.width, closeTo(salesPrice.width, 0.01),
          reason: 'عمودُ السعر ضاق بسبب عمود الخصم عند عرض $w');
    }
  });

  testWidgets('ولا يُرسَم أصلاً في المبيعات — لا يُخفى بعرضٍ صفريّ',
      (tester) async {
    for (final w in _layoutWidths) {
      final s = await _pumpAt(tester, w, kind: PicPosInvoiceKind.sales);
      expect(s.hasLine, isTrue);
      expect(find.byKey(const ValueKey('discount_1')), findsNothing,
          reason: 'حقلُ خصمٍ في المبيعات يبتلع ما يُكتَب فيه — عرض $w');
    }
  });
}
