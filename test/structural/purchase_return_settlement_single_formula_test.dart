// حارسُ العقد: قسمةُ تسوية المردود **صيغةٌ واحدةٌ** يقرؤها الجميع.
//
// ═══ فئةُ العطب ═══
//
// قسمةُ المردود بين ذمّة المورّد والنقد كانت مكتوبةً بيدها في **خمسة
// مواضع**: مسارا `processPurchaseReturn` (عميل/محلّيّ) · `_reversePurchaseReturn`
// · `postPurchaseReturn` · `postPurchaseReturnEdit`.
//
// وقرارُ المالك 2026-09-18 أنّ «طريقة التسوية» **مرآةٌ مشتقّةٌ لا قائمةُ
// اختيار** كان سيجعل الواجهةَ **سادسةً**.
//
// 🔴 **ومرآةٌ تحسب بنفسها ليست مرآة.** انحرافُ نسخةِ الواجهة بمقدارٍ واحدٍ
// يعرض «الرصيد بعد التسوية» رقماً لا يقع — ويعتمده المستخدمُ في قرارِ سداد.
// وانحرافُ نسخةِ الخادم عن نسخة العميل يُنتج رصيدَ مورّدٍ مختلفاً على
// الجهازَين، ولا يمسكه فحصُ اتّزانٍ لأنّ كلَّ قيدٍ متّزنٌ وحدَه.
//
// وهي عينُ عائلةِ `kInvestingJeReferenceTypes`: أطرافٌ تقرأ وتكتب ولا يعرف
// بعضُها بعضاً.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// نصُّ الملفّ بلا أسطر التعليق وبلا `\r` — الملفّاتُ هنا CRLF.
String _code(String path) => [
      for (final line in File(path).readAsStringSync().split('\n'))
        if (!line.trimLeft().startsWith('//')) line.replaceAll('\r', ''),
    ].join('\n');

const _formulaPath = 'lib/domain/models/purchase_return_settlement.dart';

/// الصيغتان **المشروعتان** — كلٌّ لجانبها.
///
/// ⚠️ **والثانيةُ اكتشفها هذا الحارسُ في أوّل تشغيل**: `SalesReturnRefundSplit`
/// كانت هناك من قبل، بنفس العلّة المكتوبةِ في رأسها حرفاً — «نسختان تُجيبان
/// سؤالاً واحداً وتنحرفان يوماً». فالنمطُ ليس اختراعاً هنا بل عرفُ البيت،
/// والاستثناءُ **بالمسار** لا بالمجلّد: `domain/models` يحمل حساباتٍ كثيرةً
/// وإعفاؤه كلَّه يفتح البابَ لنسخةٍ سادسةٍ تتسلّل إليه.
const _canonicalFormulas = <String>{
  _formulaPath,
  'lib/domain/models/sales_return_refund_split.dart',
};

/// المواضعُ التي كانت تكتب الصيغةَ بيدها — بمساراتها، فنقلُ أحدها يُسقط
/// المرساةَ بدل أن يمرَّ صامتاً.
const _readers = <String>[
  'lib/data/repositories/purchases_repository_impl.dart',
  'lib/services/api/api_purchase_handler.dart',
  'lib/presentation/providers/purchase_return_provider.dart',
];

void main() {
  test('مرساةٌ — الصيغةُ موجودةٌ ومكشوفة', () {
    final code = _code(_formulaPath);
    expect(
      code.contains('PurchaseReturnSettlement resolvePurchaseReturnSettlement('),
      isTrue,
      reason: 'الصيغةُ اختفت — فلا لُحمةَ تُحرَس',
    );
  });

  test('والقُرّاءُ الثلاثةُ يقرؤونها فعلاً', () {
    for (final path in _readers) {
      expect(_code(path).contains('resolvePurchaseReturnSettlement('), isTrue,
          reason: '$path لا يقرأ الصيغةَ — فهو يحسب بنفسه أو توقّف عن الحساب');
    }
  });

  test('ولا نسخةٌ يدويّةٌ من القسمة خارجَ الصيغة', () {
    // ⚠️ **النمطُ على القسمة لا على `clamp` وحدَها**: `clamp` تتكرّر في
    // المستودع لأغراضٍ كثيرة، والمقصودُ هنا قصُّ مبلغِ مردودٍ عند المتبقّي.
    final bad = RegExp(
      r'clamp\(\s*0\.0\s*,\s*(old)?[Rr]emaining\s*\)',
    );
    final offenders = <String>[];
    for (final f in Directory('lib').listSync(recursive: true)) {
      if (f is! File || !f.path.endsWith('.dart')) continue;
      final path = f.path.replaceAll(r'\', '/');
      if (_canonicalFormulas.contains(path)) continue;
      if (bad.hasMatch(_code(f.path))) offenders.add(path);
    }
    expect(offenders, isEmpty,
        reason: 'قسمةٌ مكتوبةٌ بيدها خارجَ `resolvePurchaseReturnSettlement`: '
            '${offenders.join(", ")}. وانحرافُ نسخةٍ واحدةٍ يُنتج رصيدَ '
            'مورّدٍ مختلفاً على جهازَين بلا أن يختلَّ قيدٌ واحد.');
  });

  test('ولا أحدَ يبني النتيجةَ بيده خارجَ الصيغة', () {
    // 🔴 **وهذا الفحصُ وُلد من طفرةٍ نجت.** الفحصُ أعلاه يبحث عن
    // `clamp(0.0, remaining)`، فطفرةٌ كتبت القسمةَ `g < rem ? g : rem`
    // مرّت أمامَه خضراء — وهي عينُ العطب: الواجهةُ تحسب بنفسها.
    //
    // فالمقيسُ الآن أضيقُ وأمتنُ معاً: **من يبني `PurchaseReturnSettlement(`
    // مباشرةً** لا يمرّ، أيّاً كانت صياغةُ قسمته. والبناءُ المشروعُ واحدٌ —
    // داخلَ الصيغة نفسِها.
    final ctor = RegExp(r'\bPurchaseReturnSettlement\s*\(');
    final offenders = <String>[];
    for (final f in Directory('lib').listSync(recursive: true)) {
      if (f is! File || !f.path.endsWith('.dart')) continue;
      final path = f.path.replaceAll(r'\', '/');
      if (path == _formulaPath) continue;
      if (ctor.hasMatch(_code(f.path))) offenders.add(path);
    }
    expect(offenders, isEmpty,
        reason: 'بناءٌ مباشرٌ لنتيجة التسوية خارجَ '
            '`resolvePurchaseReturnSettlement`: ${offenders.join(", ")}. '
            'ومرآةٌ تحسب بنفسها ليست مرآة.');
  });

  test('ومرساةُ النمط — يمسك نسخةً يدويّةً لو عادت', () {
    // بلا هذه المرساة يمرّ الحارسُ أخضرَ لأنّ نمطَه صار لا يطابق شيئاً
    // إطلاقاً، لا لأنّ المستودعَ نظيف.
    const planted = 'final ap = gross.clamp(0.0, oldRemaining).toDouble();';
    final bad = RegExp(r'clamp\(\s*0\.0\s*,\s*(old)?[Rr]emaining\s*\)');
    expect(bad.hasMatch(planted), isTrue,
        reason: 'النمطُ ما عاد يطابق القسمةَ اليدويّةَ نفسَها');
  });

  test('والواجهةُ لا تعرض «طريقة التسوية» قائمةً تُختار', () {
    // 🔴 المحرّكُ لا يستشير اختيارَ المستخدم: قائمةٌ تُعرَض ولا تُقرأ أسوأُ
    // من غيابها — يختار «استرداد نقدي» فيُخفَّض رصيدُ الذمّة ولا يصله شيء.
    // المرحلة C2: المرآةُ انتقلت مع الاستمارة المعاد تصميمُها.
    final ui = _code(
      'lib/presentation/purchase_returns_picpos/screens/'
      'purchase_returns_picpos_form.dart',
    );
    // ⚠️ **وجسمُ الدالّة وحدَه لا ما بعدها.** أوّلُ صياغةٍ قطعت من اسم
    // الدالّة إلى آخر الملفّ، فالتقطت قائمةَ «سبب المردود» المشروعةَ أسفلَه
    // وسقطت على شيءٍ سليم. فحصُ وجودِ رمزٍ في مدىً واسعٍ يكذب.
    final at = ui.indexOf('Widget _buildSettlementMirror');
    expect(at, greaterThan(0), reason: 'المرآةُ غيرُ مبنيّةٍ أصلاً');
    final end = ui.indexOf('\n  Widget _buildReturnFooter', at);
    expect(end, greaterThan(at), reason: 'لم أجد نهايةَ الدالّة');
    final body = ui.substring(at, end);
    expect(body.contains('DropdownButtonFormField'), isFalse,
        reason: 'قائمةٌ منسدلةٌ في كتلة التسوية — والمحرّكُ لا يقرؤها');
    expect(body.contains('notifier.settlement'), isTrue,
        reason: 'المرآةُ لا تقرأ القسمةَ المشتركة');
  });
}
