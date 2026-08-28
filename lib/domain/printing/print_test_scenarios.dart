// حالاتُ الاختبار في المعاينة التجريبيّة — **بياناتٌ خالصة**.
//
// ── كلُّ حالةٍ تكسر افتراضاً مختلفاً في القالب ────────────────────────────
// وليست عيّناتٍ للزينة: القالبُ يُكتب على فاتورةٍ متوسّطةٍ ثمّ يُطبع على
// فاتورةٍ باثنين وأربعين صنفاً، فيُدهَس نطاقُ المجاميع أو تُقصّ الحافّة. وهذه
// الحالاتُ هي التي تُخرج ذلك **قبل** أن يقع على ورق عميل.
//
// ── ولماذا لا حالتا «حراريّ 80mm» و«58mm» كما في التصميم ────────────────
// الورقُ خاصّةُ **القالب** لا خاصّةُ البيانات: `template.paperWidth` هو الذي
// يقرّره، والمعاينةُ ترسم القالبَ المختار كما هو. فحالةٌ اسمُها «حراريّ» تعني
// إمّا تجاهلَ القالب المعروض — وهي حينئذٍ معاينةٌ لشيءٍ آخر — أو تبديلَ
// القالب من تحت المستخدم. والاختيارُ الصحيحُ أن يُنتقى القالبُ الحراريُّ
// نفسُه من قائمة القوالب، فيُفحص بكلِّ حالةِ بياناتٍ من هذه الخمس.
//
// نقيّ: لا `package:flutter` ولا قاعدةَ بيانات.
library;

import 'print_values.dart';

/// حالةُ بياناتٍ واحدة.
class PrintScenario {
  final String id;
  final String name;

  /// ما الذي تختبره — يُعرض تحت الاسم.
  final String probe;

  /// حالةٌ حدّيّةٌ يُتوقَّع منها كشفُ عطب.
  final bool risky;

  final PrintPayload payload;
  final List<Map<String, dynamic>> items;

  const PrintScenario({
    required this.id,
    required this.name,
    required this.probe,
    required this.payload,
    required this.items,
    this.risky = false,
  });
}

const _company = (
  name: 'شركة بيك بوس للتجارة',
  address: 'المعادي — شارع ٩، القاهرة',
  phone: '0100 123 4567',
  taxId: '344-228-891',
);

final _date = DateTime.utc(2026, 8, 25);

Map<String, dynamic> _item(
  String name,
  double qty,
  double price, {
  String code = '',
  double discount = 0,
  double tax = 0,
}) {
  final gross = qty * price - discount;
  return {
    'name': name,
    'code': code,
    'quantity': qty,
    'price': price,
    'discount': discount,
    'tax': tax,
    'total': gross + tax,
  };
}

final _base = <Map<String, dynamic>>[
  _item('سكر معبأ ١ كجم', 40, 22, code: 'P-1001'),
  _item('زيت عافية ١ لتر', 24, 68, code: 'P-1002'),
  _item('أرز مصري ٥ كجم', 12, 145, code: 'P-1003'),
  _item('شاي العروسة ٢٥٠ج', 18, 58, code: 'P-1004'),
  _item('لبن جهينة ١ لتر', 30, 34, code: 'P-1005'),
];

/// ستّةٌ وتسعون محرفاً — يختبر الالتفافَ والقصّ في خليّةٍ واحدة.
const _longName = 'مجموعة توابل وأعشاب مشكّلة معبأة في عبوات زجاجية محكمة '
    'الغلق — تشكيلة رمضان الكبرى ٢٤ صنفاً';

double _sumOf(List<Map<String, dynamic>> items) =>
    items.fold(0.0, (a, i) => a + ((i['total'] as num?)?.toDouble() ?? 0));

PrintPayload _payload({
  required String number,
  required List<Map<String, dynamic>> items,
  String? customer,
  String? notes,
  double discount = 0,
  double taxRate = 0.14,
}) {
  final subtotal = _sumOf(items);
  final tax = (subtotal - discount) * taxRate;
  final total = subtotal - discount + tax;
  return PrintPayload(
    invoiceNumber: number,
    date: _date,
    companyName: _company.name,
    companyAddress: _company.address,
    companyPhone: _company.phone,
    companyTaxId: _company.taxId,
    customerName: customer,
    customerPhone: customer == null ? null : '0111 222 3333',
    customerAddress: customer == null ? null : 'مدينة نصر — القاهرة',
    cashierName: 'محمد سالم',
    notes: notes,
    paymentMethod: 'آجل ٣٠ يوماً',
    subtotal: subtotal,
    discount: discount,
    tax: tax,
    deliveryFee: 0,
    total: total,
    paid: total,
    remaining: 0,
  );
}

/// اثنان وأربعون صنفاً — يختبر أنّ النطاقات **تدفع ولا تدهس**.
List<Map<String, dynamic>> _manyItems() => [
      for (var i = 0; i < 42; i++)
        _item(
          '${_base[i % _base.length]['name']} — دفعة ${i + 1}',
          (i % 7 + 1).toDouble(),
          (20 + i * 3).toDouble(),
          code: 'P-${2000 + i}',
        ),
    ];

/// الحالاتُ الخمس — بالترتيب الذي تُعرض به.
List<PrintScenario> buildPrintScenarios() {
  final many = _manyItems();
  final longText = [
    {..._base[0], 'name': _longName},
    _base[1],
    _base[2],
  ];
  final refund = [_item('سكر معبأ ١ كجم', -6, 22, code: 'P-1001')];

  return [
    PrintScenario(
      id: 'normal',
      name: 'فاتورة عادية',
      probe: '٥ أصناف · كل الحقول ممتلئة',
      items: _base,
      payload: _payload(
        number: 'INV-2026-1040',
        items: _base,
        customer: 'سوبر ماركت النور',
        notes: 'التسليم بمخزن العميل',
        discount: 55,
      ),
    ),
    PrintScenario(
      id: 'overflow',
      name: 'جدول يتجاوز الصفحة',
      probe: '٤٢ صنفاً — يختبر أن النطاقات تدفع ولا تدهس',
      risky: true,
      items: many,
      payload: _payload(
        number: 'INV-2026-1041',
        items: many,
        customer: 'سوبر ماركت النور',
        discount: 120,
      ),
    ),
    PrintScenario(
      id: 'long_text',
      name: 'اسم صنف طويل جداً',
      probe: '٩٦ حرفاً في خليّة — يختبر الالتفاف والقصّ',
      risky: true,
      items: longText,
      payload: _payload(
        number: 'INV-2026-1042',
        items: longText,
        customer: 'مطاعم الشرق',
      ),
    ),
    PrintScenario(
      id: 'empty',
      name: 'حقول فارغة',
      probe: 'بلا عميلٍ ولا ملاحظاتٍ ولا خصم — يختبر ألّا تُطبع تسميةٌ معلَّقة',
      risky: true,
      items: _base.take(3).toList(),
      payload: _payload(
        number: 'INV-2026-1044',
        items: _base.take(3).toList(),
      ),
    ),
    PrintScenario(
      id: 'negative',
      name: 'مرتجع بقيم سالبة',
      probe: 'كمياتٌ ومبالغُ سالبة — يختبر تنسيقَ الأرقام والإشارة',
      risky: true,
      items: refund,
      payload: _payload(
        number: 'CRN-2026-0031',
        items: refund,
        customer: 'سوبر ماركت النور',
      ),
    ),
  ];
}
