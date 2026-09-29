import 'package:ural_erp/core/i18n/tr.dart';
import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../domain/models/quick_sale_policy.dart';

// «ما يراه الكاشير» — لوحةُ المعاينة في §٤.
//
// المصدرُ `buildPreview()` في
// `invoice_templates/design/PicPos Quick Sale Settings.dc.html`.
//
// ═══ لماذا محاكاةٌ داكنةٌ دائماً ═══
//
// هذه ليست سطحَ واجهةٍ يتبع وضعَ المستخدم، بل **صورةٌ لشاشةٍ أخرى**: شاشةُ
// الكاشير كما ستبدو. والتصميمُ يرسمها بألوانها الخاصّة (`#0B1220` وما فوقه)
// في الوضعَين معاً — تماماً كما تبقى معاينةُ الورق المطبوع بيضاءَ في الوضع
// الغامق. فتلوينُها بألوان الثيم كان سيجعلها تعرض شيئاً غيرَ ما يراه الكاشير.
//
// ولهذا لا `context.picpos*` هنا: الألوانُ مقصودةٌ ومثبَّتةٌ بحكم كونها
// محاكاةً لا سطحاً.

const _canvas = Color(0xFF0B1220);
const _card = Color(0xFF111A2B);
const _field = Color(0xFF161F33);
const _line = Color(0xFF243247);
const _ink = Color(0xFFE2E8F2);
const _muted = Color(0xFF7C8AA3);

/// أسطرُ السلّة المعروضةُ في المحاكاة — بياناتُ التصميم نفسُها.
List<(String, String, String)> get _lines => [
  (tr('أرز مصري ٥ كجم'), tr('٢'), tr('٣١٥.٠٠')),
  (tr('زيت عافية ١.٨ل'), tr('١'), tr('١٨٩.٥٠')),
  (tr('جبنة رومي — وزن'), tr('٠.٤٦'), tr('١٠٤.١٠')),
];

String _ar(Object n) =>
    '$n'.replaceAllMapped(RegExp(r'\d'), (m) => '٠١٢٣٤٥٦٧٨٩'[int.parse(m[0]!)]);

/// محاكاةُ شاشة الكاشير بحسب الخطوة والإعدادات الحالية.
class QuickSaleCashierPreview extends StatelessWidget {
  final String stepId;
  final QuickSalePolicyValues values;

  const QuickSaleCashierPreview({
    super.key,
    required this.stepId,
    required this.values,
  });

  QuickSaleRow _row(String id) =>
      kQuickSaleRows.firstWhere((r) => r.id == id);

  bool _on(String id) => values.isOn(_row(id));

  String _opt(String id) {
    final row = _row(id);
    return row.options[values.indexOf(row)];
  }

  List<String> get _methods =>
      values.pickOf(kQuickSalePicks.firstWhere((p) => p.id == 'methods'));

  bool get _fastPath => _on('skipdlg') && _methods.length == 1;

  String get _tag => switch (stepId) {
        'scan' => tr('شاشة المسح'),
        'cart' => tr('السلة والخصم'),
        'pay' => _fastPath ? tr('مسار سريع بلا حوار') : tr('حوار الدفع'),
        'print' => _on('autoprint') ? tr('طباعة تلقائية') : tr('طباعة بالطلب'),
        _ => _on('quickclose') ? tr('إغلاق سريع متاح') : tr('إغلاق بمصادقة'),
      };

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: _canvas,
        border: Border.all(color: _line),
        borderRadius: BorderRadius.circular(14),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          _header(),
          Padding(
            padding: const EdgeInsets.all(12),
            child: switch (stepId) {
              'pay' => _payMock(),
              'print' => _printMock(),
              'shift' => _shiftMock(),
              _ => _posMock(),
            },
          ),
        ],
      ),
    );
  }

  Widget _header() => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: const BoxDecoration(
          color: _card,
          border: Border(bottom: BorderSide(color: _line)),
        ),
        child: Row(children: [
          const Icon(PhosphorIconsBold.deviceMobile, size: 15, color: _muted),
          const SizedBox(width: 8),
           Expanded(
            child: Text(tr('ما يراه الكاشير'),
                style: const TextStyle(
                    fontSize: 12, fontWeight: FontWeight.w800, color: _ink)),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
            decoration: BoxDecoration(
              color: const Color(0xFF4A80E8).withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(_tag,
                style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF9EC1FF))),
          ),
        ]),
      );

  // ── شاشةُ المسح والسلّة ────────────────────────────────────────────────
  Widget _posMock() {
    final onScan = stepId == 'scan';
    final cap = _ar(values.numberOf(_row('disccap')).round());

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
        decoration: BoxDecoration(
          color: _field,
          border: Border.all(
              color: onScan ? const Color(0xFF4A80E8) : _line, width: 1.5),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(children: [
          Icon(PhosphorIconsBold.barcode,
              size: 15, color: onScan ? const Color(0xFF4A80E8) : _muted),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _on('askqty')
                  ? tr('امسح الباركود ثم أدخل الكمية…')
                  : tr('امسح الباركود أو ابحث بالاسم…'),
              style: const TextStyle(fontSize: 11, color: _muted),
            ),
          ),
        ]),
      ),
      const SizedBox(height: 10),
      Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          for (var i = 0; i < 6; i++)
            Container(
              width: 62,
              height: 44,
              decoration: BoxDecoration(
                color: _field,
                border: Border.all(color: _line),
                borderRadius: BorderRadius.circular(8),
              ),
            ),
        ],
      ),
      const SizedBox(height: 10),
      Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: _field,
          border: Border.all(
              color: onScan ? _line : const Color(0xFFF59E0B), width: 1.5),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(children: [
          for (final line in _lines)
            Padding(
              padding: const EdgeInsets.only(bottom: 5),
              child: Row(children: [
                Expanded(
                  child: Text(line.$1,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 10.5, color: _ink)),
                ),
                Text(line.$2,
                    style: const TextStyle(fontSize: 10.5, color: _muted)),
                const SizedBox(width: 10),
                Text(line.$3,
                    style: const TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w800,
                        color: _ink)),
              ]),
            ),
          const Divider(height: 12, color: _line),
          Row(children: [
            Expanded(
              child: Text(tr('الخصم ({cap}٪)', {'cap': cap}),
                  style: const TextStyle(fontSize: 10.5, color: _muted)),
            ),
             Text(tr('−١٩٥.٠٠'),
                style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFFF59E0B))),
          ]),
          const SizedBox(height: 6),
           Row(children: [
            Expanded(
              child: Text(tr('الإجمالي'),
                  style: const TextStyle(fontSize: 11, color: _muted)),
            ),
            Text(tr('١,٤١٣.٦٠'),
                style: const TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w800,
                    color: Colors.white)),
          ]),
        ]),
      ),
      const SizedBox(height: 10),
      Row(children: [
        _action(PhosphorIconsBold.percent, tr('خصم {cap}٪', {'cap': cap}), const Color(0xFFF59E0B)),
        const SizedBox(width: 6),
        _action(
          PhosphorIconsBold.pause,
          _on('hold') ? tr('تعليق') : tr('تعليق (مطفأ)'),
          _on('hold') ? const Color(0xFF4A80E8) : const Color(0xFF3A465C),
        ),
        const SizedBox(width: 6),
        _action(PhosphorIconsBold.money, tr('دفع'), const Color(0xFF22C55E)),
      ]),
    ]);
  }

  Widget _action(IconData icon, String label, Color tint) => Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 7),
          decoration: BoxDecoration(
            color: tint.withValues(alpha: 0.12),
            border: Border.all(color: tint.withValues(alpha: 0.35)),
            borderRadius: BorderRadius.circular(9),
          ),
          child: Column(children: [
            Icon(icon, size: 13, color: tint),
            const SizedBox(height: 3),
            Text(label,
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 9, fontWeight: FontWeight.w700, color: tint)),
          ]),
        ),
      );

  // ── حوارُ الدفع ────────────────────────────────────────────────────────
  Widget _payMock() {
    final labels = {
      'cash': tr('نقدي'),
      'card': tr('بطاقة'),
      'click': tr('محفظة'),
      'credit': tr('آجل'),
      'split': tr('متعدّد'),
    };

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
       Text(tr('المطلوب'),
          style: const TextStyle(fontSize: 11, color: _muted)),
      const SizedBox(height: 2),
       Text(tr('١,٤١٣.٦٠'),
          style: const TextStyle(
              fontSize: 30, fontWeight: FontWeight.w800, color: Colors.white)),
      const SizedBox(height: 12),
      if (_fastPath)
        Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: const Color(0xFF22C55E),
            borderRadius: BorderRadius.circular(11),
          ),
          // ⚠️ `Flexible` لا نصٌّ حرّ: اسمُ الطريقة يتبدّل («محفظة / كليك»
          // أطولُ من «نقدي»)، والعمودُ ثابتُ العرض ٣٤٠. وقد فاض هذا الصفُّ
          // ١٩px فعلاً في اختبار التركيب قبل التقييد.
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            const Icon(PhosphorIconsBold.lightning,
                size: 16, color: Colors.white),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                  tr('تحصيل {p0} · إتمام فوري', {'p0': labels[_methods.first] ?? 'نقدي'}),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: Colors.white)),
            ),
          ]),
        )
      else ...[
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final id in _methods)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                decoration: BoxDecoration(
                  color: _field,
                  border: Border.all(color: _line),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Text(labels[id] ?? id,
                    style: const TextStyle(fontSize: 11, color: _ink)),
              ),
          ],
        ),
        if (_on('quickamt')) ...[
          const SizedBox(height: 10),
          Row(children: [
            for (final amount in  [tr('٥٠'), tr('١٠٠'), tr('٢٠٠'), tr('٥٠٠')])
              Expanded(
                child: Container(
                  margin: const EdgeInsetsDirectional.only(end: 5),
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  decoration: BoxDecoration(
                    color: _field,
                    border: Border.all(color: _line),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(amount,
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 11, color: _ink)),
                ),
              ),
          ]),
        ],
      ],
    ]);
  }

  // ── الإيصال ────────────────────────────────────────────────────────────
  Widget _printMock() {
    final auto = _on('autoprint');

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Container(
        padding: const EdgeInsets.all(11),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(children: [
           Text(tr('بيك بوس ماركت'),
              style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: Colors.black)),
          const SizedBox(height: 6),
          for (final line in _lines)
            Row(children: [
              Expanded(
                child: Text(line.$1,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 9, color: Colors.black87)),
              ),
              Text(line.$3,
                  style: const TextStyle(fontSize: 9, color: Colors.black87)),
            ]),
          const Divider(height: 10),
           Row(children: [
            Expanded(
                child: Text(tr('المطلوب'),
                    style: const TextStyle(fontSize: 10, color: Colors.black))),
            Text(tr('١,٤١٣.٦٠'),
                style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: Colors.black)),
          ]),
        ]),
      ),
      const SizedBox(height: 10),
      Text(
        auto ? tr('{p0} · تلقائي — قالب {p1}', {'p0': _opt('copies'), 'p1': _opt('tpl')})
            : tr('بانتظار نقرة الكاشير'),
        style: const TextStyle(fontSize: 10.5, color: _muted),
      ),
      const SizedBox(height: 8),
      Row(children: [
        _chip(PhosphorIconsBold.printer, tr('إعادة طباعة'), true),
        const SizedBox(width: 6),
        _chip(PhosphorIconsBold.wallet,
            _on('drawer') ? tr('فتح الدرج') : tr('الدرج مقفول'), _on('drawer')),
        const SizedBox(width: 6),
        _chip(PhosphorIconsBold.paperPlaneTilt,
            _on('digital') ? tr('إرسال') : tr('الإرسال مخفي'), _on('digital')),
      ]),
    ]);
  }

  Widget _chip(IconData icon, String label, bool on) => Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 7),
          decoration: BoxDecoration(
            color: on
                ? const Color(0xFF0250D3).withValues(alpha: 0.15)
                : Colors.transparent,
            border: Border.all(color: on ? const Color(0xFF4A80E8) : _line),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(children: [
            Icon(icon, size: 12, color: on ? const Color(0xFF9EC1FF) : _muted),
            const SizedBox(height: 3),
            Text(label,
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 8.5,
                    color: on ? const Color(0xFF9EC1FF) : _muted)),
          ]),
        ),
      );

  // ── إغلاقُ الوردية ─────────────────────────────────────────────────────
  Widget _shiftMock() {
    final blind = _on('blind');

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
       Text(tr('إغلاق الوردية'),
          style: const TextStyle(
              fontSize: 13, fontWeight: FontWeight.w800, color: Colors.white)),
      const SizedBox(height: 2),
       Text(tr('أحمد فؤاد · ٦س ١٢د'),
          style: const TextStyle(fontSize: 10.5, color: _muted)),
      const SizedBox(height: 10),
      for (final stat in [
        (tr('مبيعات الوردية'), tr('٤٢,٩١٠')),
        (tr('المتوقع في الدرج'), blind ? '—' : tr('١٢,٤٠٠')),
      ])
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Row(children: [
            Expanded(
              child: Text(stat.$1,
                  style: const TextStyle(fontSize: 10.5, color: _muted)),
            ),
            Text(stat.$2,
                style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: Colors.white)),
          ]),
        ),
      if (blind)
         Text(tr('إغلاق أعمى — المتوقع مخفيٌّ حتى يُدخِل الكاشير العدّة'),
            style: const TextStyle(fontSize: 9.5, height: 1.5, color: _muted)),
      const SizedBox(height: 8),
      if (_on('quickclose'))
        Container(
          padding: const EdgeInsets.symmetric(vertical: 9),
          decoration: BoxDecoration(
            color: const Color(0xFFEF4444).withValues(alpha: 0.15),
            border: Border.all(color: const Color(0xFFEF4444)),
            borderRadius: BorderRadius.circular(9),
          ),
          child:  Text(tr('إغلاق سريع (بلا مصادقة)'),
              textAlign: TextAlign.center,
              style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFFFF9B9B))),
        ),
    ]);
  }
}
