// حارسُ العقد: الاستحقاقُ **صيغةٌ واحدةٌ** يقرؤها المحرّكُ والشاشةُ معاً.
//
// ═══ فئةُ العطب ═══
//
// قرارُ المالك 2026-09-18: «تاريخ الاستحقاق» **مرآةٌ مشتقّة** لا حقلٌ
// يُكتَب (ح‑١). ولكي تعرض الشاشةُ ما سيُحفَظ **بالضبط** كان أمامها طريقان:
// أن تنادي القاعدةَ — يمنعه `presentation_db_import_guard` — أو أن تكتب
// القاعدةَ بيدها.
//
// 🔴 **ومرآةٌ تحسب بنفسها ليست مرآة.** انحرافُ نسخةِ الشاشة بيومٍ واحدٍ
// يعني أن يقرأ المستخدمُ «٨ أكتوبر» ويُختَم على المستند غيرُه — وعلى
// `due_date` وحدَه تُبنى أعمارُ الدين وتنبيهاتُ التأخّر وتقاريرُ الاستحقاق
// وشرائحُ «١—٣٠ / ٣١—٦٠ / فوق ٦٠». ولا يكشفه فحصُ اتّزانٍ ولا مصالحة:
// المبالغُ كلُّها صحيحة، والتصنيفُ الزمنيُّ وحدَه كاذب.
//
// وهي عينُ عائلةِ `resolvePurchaseReturnSettlement` و`resolvePurchaseLineNets`
// و`SalesReturnRefundSplit`: أطرافٌ تُجيب سؤالاً واحداً ولا يعرف بعضُها
// بعضاً.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import '../helpers/dao_source.dart';

/// نصُّ الملفّ بلا أسطر التعليق وبلا `\r` — أغلبُ الملفّات هنا CRLF.
String _code(String path) => [
      for (final line in readDaoSourceMerged(path).split('\n'))
        if (!line.trimLeft().startsWith('//')) line.replaceAll('\r', ''),
    ].join('\n');

const _formulaPath = 'lib/domain/models/invoice_due_date.dart';

/// القُرّاءُ المُلزَمون — بمساراتهم، فنقلُ أحدهم يُسقط المرساةَ بدل أن يمرّ
/// صامتاً.
const _readers = <String>[
  // المحرّك: يُختَم به `due_date` على المستند.
  'lib/data/database/daos/party_dao.dart',
  // الشاشة: تعرضه قبل الحفظ.
  'lib/presentation/invoice_form_picpos/picpos_invoice_form.dart',
];

void main() {
  test('مرساةٌ — الصيغةُ موجودةٌ ومكشوفة', () {
    expect(
      _code(_formulaPath).contains('DateTime? resolveDueDateFromTerms('),
      isTrue,
      reason: 'الصيغةُ اختفت — فلا لُحمةَ تُحرَس',
    );
  });

  test('والقارئان يقرآنها فعلاً — المحرّكُ والشاشة', () {
    for (final path in _readers) {
      expect(_code(path).contains('resolveDueDateFromTerms('), isTrue,
          reason: '$path لا يقرأ الصيغةَ — فهو يحسب بنفسه أو توقّف عن الحساب');
    }
  });

  test('ولا نسخةٌ يدويّةٌ من القاعدة خارجَ الصيغة', () {
    // ⚠️ **النمطُ على التركيب لا على `Duration` وحدَها**: `Duration(days:)`
    // تتكرّر في المستودع لأغراضٍ كثيرة، والمقصودُ هنا جمعُ مهلةِ السداد على
    // تاريخٍ — أي `Duration(days: <شيءٌ فيه terms/days>)` بعد `add`.
    final bad = RegExp(
      r'\.add\(\s*Duration\(\s*days:\s*\w*([Tt]erms|termsDays)\w*\s*\)\s*\)',
    );
    final offenders = <String>[];
    for (final f in Directory('lib').listSync(recursive: true)) {
      if (f is! File || !f.path.endsWith('.dart')) continue;
      final path = f.path.replaceAll(r'\', '/');
      if (path == _formulaPath) continue;
      if (bad.hasMatch(_code(f.path))) offenders.add(path);
    }
    expect(offenders, isEmpty,
        reason: 'اشتقاقٌ مكتوبٌ بيده خارجَ `resolveDueDateFromTerms`: '
            '${offenders.join(", ")}. وانحرافُ نسخةٍ بيومٍ يقلب شريحةَ '
            'التقادم بلا أن يختلَّ مبلغٌ واحد.');
  });

  test('ومرساةُ النمط — يمسك النسخةَ اليدويّةَ لو عادت', () {
    // بلا هذه المرساة يمرّ الفحصُ أعلاه أخضرَ لأنّ نمطَه صار لا يطابق شيئاً
    // إطلاقاً، لا لأنّ المستودعَ نظيف.
    const planted = 'return invoiceDate.add(Duration(days: paymentTerms));';
    final bad = RegExp(
      r'\.add\(\s*Duration\(\s*days:\s*\w*([Tt]erms|termsDays)\w*\s*\)\s*\)',
    );
    expect(bad.hasMatch(planted), isTrue,
        reason: 'النمطُ ما عاد يطابق الاشتقاقَ اليدويَّ نفسَه');
  });

  test('والشاشةُ تعرضه مقفولاً — لا حقلَ تاريخٍ يُكتَب', () {
    // 🔴 حقلٌ يُملأ ويُتجاهَل يعد بأجلٍ لا يقع: المحرّكُ يشتقُّه من مهلة
    // الطرف ولا يقرأ ما يكتبه المستخدم.
    final money = _code(
        'lib/presentation/invoice_form_picpos/picpos_invoice_money.dart');
    final at = money.indexOf('Widget _dueDate(');
    expect(at, greaterThan(0), reason: 'المرآةُ غيرُ مبنيّةٍ أصلاً');
    final end = money.indexOf('\n  Widget _methods(', at);
    expect(end, greaterThan(at), reason: 'لم أجد نهايةَ الدالّة');
    final body = money.substring(at, end);

    expect(body.contains('showDatePicker'), isFalse,
        reason: 'منتقي تاريخٍ في كتلة الاستحقاق — يختار المستخدمُ ويُختَم '
            'على المستند غيرُه');
    expect(body.contains('TextField'), isFalse,
        reason: 'حقلٌ يُكتَب فيه الاستحقاق — والمحرّكُ لا يقرؤه');
    expect(body.contains('state._dueDate'), isTrue,
        reason: 'المرآةُ لا تقرأ المشتقَّ أصلاً');
    expect(body.contains('lockSimple'), isTrue,
        reason: 'القفلُ لا يظهر — فيبدو الحقلُ قابلاً للتحرير');
  });

  test('وبلا مهلةٍ تقول «بلا مهلة متفقة» لا تاريخَ الفاتورة', () {
    final money = _code(
        'lib/presentation/invoice_form_picpos/picpos_invoice_money.dart');
    expect(money.contains('بلا مهلة متفقة'), isTrue,
        reason: 'الفراغُ يُعرَض تاريخاً — فيوهم بأجلٍ متّفقٍ مدّتُه صفر، '
            'والعمودُ في القاعدة يبقى فارغاً');
  });

  test('والمهلةُ تصل الشاشةَ من الطرفَين معاً — مورّداً وعميلاً', () {
    // بلا التمرير تقول الشاشةُ «بلا مهلة متفقة» لطرفٍ له مهلةٌ فعلاً،
    // والمحرّكُ يختم الاستحقاقَ رغم ذلك — فالمرآةُ تكذب في الاتّجاه المعاكس.
    for (final path in [
      'lib/presentation/purchases_picpos/screens/purchases_picpos_crud.dart',
      'lib/presentation/sales_invoices_picpos/screens/sales_invoice_dialogs.dart',
    ]) {
      expect(_code(path).contains('paymentTermsDays:'), isTrue,
          reason: '$path لا يمرّر مهلةَ الطرف إلى المنتقي');
    }
  });
}
