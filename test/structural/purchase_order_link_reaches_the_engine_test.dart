// حارسُ العقد: «ربط أمر شراء» يصل المحرّكَ — **ويستهلك الأمر**.
//
// ═══ فئةُ العطب ═══
//
// قرارُ المالك 2026-09-18: الاتّجاهُ الجديد — من داخل الفاتورة ← اختَر أمرَ
// شراءٍ لسحب بنوده. فصار للأمر **مدخلان** إلى نفس الحدث: هذا، وزرُّ
// «استلام وتحويل لفاتورة» على شاشة الأوامر.
//
// 🔴 **وسحبُ البنود وحدَه ليس ربطاً.** لو نُسخت الأرقامُ إلى الجدول وحُفظت
// الفاتورةُ بلا أن يصل رقمُ الأمر المحرّكَ، بقي الأمرُ **مفتوحاً بعد أن
// دخلت بضاعتُه**. فيحوّله أحدٌ من شاشة الأوامر بعد يومٍ:
//
//   • المخزونُ يدخل مرّتَين
//   • ومتوسّطُ التكلفة يُحسَب على كمّيّةٍ ضِعفَ الحقيقة
//   • وذمّةُ المورّد تُقيَّد مرّتَين
//
// ولا يظهر شيءٌ من ذلك على شاشة: فاتورتان صحيحتان كلٌّ على حدة، ومصالحةُ
// المخزون تجد الكمّيّةَ مطابقةً لمجموع الفواتير.
//
// والسلسلةُ **ستُّ حلقات**: شريطٌ في النموذج ← حالةٌ فيه ← نداءُ الحفظ ←
// الشاشة ← معاملاتُ المستودع ← المحرّك. وكسرُ أيِّها يُنتج ذلك بالضبط.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import '../helpers/dao_source.dart';

/// نصُّ الملفّ بلا أسطر التعليق وبلا `\r` — أغلبُ الملفّات هنا CRLF.
String _code(String path) => [
      for (final line in readDaoSourceMerged(path).split('\n'))
        if (!line.trimLeft().startsWith('//')) line.replaceAll('\r', ''),
    ].join('\n');

const _formPath =
    'lib/presentation/invoice_form_picpos/picpos_invoice_form.dart';
const _linesPath =
    'lib/presentation/invoice_form_picpos/picpos_invoice_lines.dart';
const _crudPath =
    'lib/presentation/purchases_picpos/screens/purchases_picpos_crud.dart';
const _paramsPath = 'lib/domain/repositories/purchases_repository.dart';
const _repoPath = 'lib/data/repositories/purchases_repository_impl.dart';
const _ordersDaoPath = 'lib/data/database/daos/purchase_orders_dao.dart';
const _purchaseDaoPath = 'lib/data/database/daos/purchase_dao.dart';

/// جسمُ دالّةٍ بعينها — فحصُ وجودِ رمزٍ في ملفٍّ كاملٍ يكذب متى ظهر مرّتَين.
String _body(String code, String start, String end) {
  final at = code.indexOf(start);
  expect(at, greaterThan(0), reason: 'لم أجد `$start`');
  final to = code.indexOf(end, at);
  expect(to, greaterThan(at), reason: 'لم أجد نهايةَ `$start`');
  return code.substring(at, to);
}

void main() {
  test('‏١ — الشريطُ لا يُعرَض إلّا بشروطه الثلاثة', () {
    // زرٌّ بلا أوامرَ، أو بلا من يجلب بنودَها، أو على فاتورة مبيعات —
    // ثلاثتُها زرٌّ لا يفعل شيئاً.
    final gate = _body(
      _code(_formPath),
      'bool get _canLinkPurchaseOrder =>',
      ';',
    );
    expect(gate.contains('!widget.kind.isSales'), isTrue,
        reason: 'أمرُ شراءٍ يُعرَض على فاتورة مبيعات');
    expect(gate.contains('widget.onPullPurchaseOrder != null'), isTrue,
        reason: 'زرٌّ بلا من يجلب البنود');
    expect(gate.contains('widget.purchaseOrders.isNotEmpty'), isTrue,
        reason: 'زرٌّ بلا أوامرَ يربطها');
    // 🔴 ولا ربطَ على فاتورةٍ قائمة: `updatePurchaseInvoice` لا يستهلك أمراً،
    // فالسحبُ يترك الأمرَ مفتوحاً ليدخل ثانيةً. والشرطُ في **الودجت** لا عند
    // المنادي وحدَه — شرطُ المنادي عُرفٌ يُنسى.
    expect(gate.contains('!widget.isEdit'), isTrue,
        reason: 'شريطُ الربط يُعرَض على فاتورةٍ قائمة');

    expect(_code(_linesPath).contains('class _PicPosOrderLinkBar'), isTrue,
        reason: 'الشريطُ نفسُه اختفى');
  });

  test('‏٢ — والربطُ يضبط المورّدَ مع البنود', () {
    // 🔴 فاتورةٌ على مورّدٍ آخرَ تستهلك أمرَ هذا المورّد تقيّد الذمّةَ على
    // الطرف الخطأ — ولا يكشفه فحصُ اتّزان.
    final fn = _body(
      _code(_formPath),
      'Future<void> _linkPurchaseOrder(',
      '\n  void _unlinkPurchaseOrder(',
    );
    expect(fn.contains('_partyId = order.supplierId'), isTrue,
        reason: 'المورّدُ لا يتبع الأمرَ المربوط');
    expect(fn.contains('_sourceOrderId = picked'), isTrue,
        reason: 'الرابطُ لا يُسجَّل — فالسحبُ نسخُ أرقامٍ لا ربط');
  });

  test('‏٣ — والرابطُ في عقد الحفظ ويُمرَّر من حالته', () {
    final code = _code(_formPath);
    final contract = _body(
        code, 'typedef PicPosInvoiceSaveCallback', '});');
    expect(contract.contains('required int? sourceOrderId'), isTrue,
        reason: 'عقدُ الحفظ لا يحمل الرابطَ — فلا سبيلَ لأن يصل المحرّك');
    expect(code.contains('sourceOrderId: _sourceOrderId'), isTrue,
        reason: 'الحالةُ لا تُمرَّر — يُحفَظ `null` مهما رُبط');
  });

  test('‏٤ — والشاشةُ تمرّره حلقةً حلقة', () {
    // 🔴 **ولا يُفحَص وجودُ الرمز في الملفّ.** أوّلُ صياغةٍ بحثت عن
    // `sourceOrderId: sourceOrderId` في `purchases_picpos_crud.dart` كلِّه،
    // وهو يظهر **مرّتَين**: من ردّ النداء إلى دالّة الحفظ، ومن دالّة الحفظ
    // إلى معاملات المستودع. فطفرةٌ حذفت الأولى مرّت خضراء لأنّ الثانية
    // أبقت المطابقة. والمقيسُ الآن كلُّ حلقةٍ في جسمها.
    final code = _code(_crudPath);

    final callback = _body(
      code,
      'onSave: ({',
      'if (dialogContext.mounted) Navigator.pop(dialogContext);',
    );
    expect(callback.contains('required int? sourceOrderId'), isTrue,
        reason: 'ردُّ النداء لا يستقبل الرابطَ أصلاً');
    expect(callback.contains('sourceOrderId: sourceOrderId'), isTrue,
        reason: 'الشاشةُ تتلقّى الرابطَ وتُسقطه قبل مسار الحفظ');

    // ⚠️ مرساةُ النهاية **شيفرةٌ لا تعليق**: `_code` يُسقط أسطرَ التعليق،
    // فمرساةٌ عليها تعطي `-1` ويسقط الفحصُ لسببٍ لا علاقةَ له بما يُقاس.
    final save = _body(
      code,
      'Future<void> _handleSavePurchaseSimple({',
      'if (printAfterSave && savedInvoiceId > 0)',
    );
    expect(save.contains('int? sourceOrderId'), isTrue,
        reason: 'مسارُ الحفظ بلا معاملٍ للرابط');
    expect(save.contains('sourceOrderId: sourceOrderId'), isTrue,
        reason: 'مسارُ الحفظ يستقبل الرابطَ ولا يضعه في معاملات الإنشاء');

    expect(_code(_paramsPath).contains('final int? sourceOrderId;'), isTrue,
        reason: '`CreatePurchaseInvoiceParams` بلا وعاءٍ للرابط');
    expect(_code(_repoPath).contains('sourceOrderId: params.sourceOrderId'),
        isTrue,
        reason: 'المستودعُ لا يمرّره إلى المحرّك');
  });

  test('‏٥ — والمحرّكُ يفحص الأهليّةَ **ثمّ** يختم الاستهلاك', () {
    final code = _code(_purchaseDaoPath);
    expect(code.contains('await _requireConsumablePurchaseOrder(sourceOrderId)'),
        isTrue,
        reason: 'أمرٌ مستهلَكٌ يُربَط ثانيةً — فاتورتان بنفس البضاعة');
    expect(
        code.contains('await _markPurchaseOrderConverted(sourceOrderId, invoiceId)'),
        isTrue,
        reason: 'الأمرُ يبقى مفتوحاً بعد أن دخلت بضاعتُه');

    // الترتيبُ مقصود: الفحصُ قبل أن يتحرّك شيء، والختمُ بعد أن يُعرَف الرقم.
    expect(code.indexOf('_requireConsumablePurchaseOrder(sourceOrderId)'),
        lessThan(code.indexOf('_markPurchaseOrderConverted(sourceOrderId')),
        reason: 'الختمُ قبل الفحص — يُكتَب رابطٌ لأمرٍ غيرِ مؤهَّل');
  });

  test('‏٦ — والمدخلان يقرآن قاعدةَ الاستهلاك نفسَها', () {
    // 🔴 نسختان من «هل استُهلك؟» تنحرفان يوماً، وثمنُ الانحراف بضاعةٌ تدخل
    // مرّتَين.
    final orders = _code(_ordersDaoPath);
    expect(
      orders.contains(
          'Future<PurchaseOrderData> _requireConsumablePurchaseOrder('),
      isTrue,
      reason: 'قاعدةُ الأهليّة اختفت — فلا لُحمةَ تُحرَس',
    );
    final convert =
        _body(orders, 'Future<int> convertPOToInvoice(', '\n  }');
    expect(convert.contains('_requireConsumablePurchaseOrder(orderId)'), isTrue,
        reason: 'زرُّ شاشة الأوامر يكتب فحصَه بيده');
    expect(convert.contains("po.status == 'cancelled'"), isFalse,
        reason: 'الفحصُ اليدويُّ القديمُ عاد بجوار القاعدة — نسختان');
  });

  test('‏٧ — والأهليّةُ تُقاس بالرابط لا بالحالة', () {
    // الحالةُ وسمٌ يُبدَّل بـ`updatePurchaseOrderStatus` بلا أن يقع شيء،
    // والرابطُ هو **واقعةُ** الاستهلاك.
    // ⚠️ المرساةُ دالّةٌ تالية، لا سطرُ توثيق: `_code` يُسقط التعليقات.
    final fn = _body(
      _code(_ordersDaoPath),
      'Future<PurchaseOrderData> _requireConsumablePurchaseOrder(',
      '\n  Future<void> _markPurchaseOrderConverted(',
    );
    expect(fn.contains('po.convertedToInvoiceId != null'), isTrue,
        reason: 'الأمرُ المستهلَكُ يمرّ — بضاعةٌ تدخل مرّتَين');
    expect(fn.contains("po.status == 'cancelled'"), isTrue,
        reason: 'الأمرُ الملغى صار يُحوَّل');
  });

  test('‏٨ — والقائمةُ لا تُحمَّل خارجَ نطاقها ولا تعرض مستهلَكاً', () {
    final code = _code(_crudPath);
    expect(
      code.contains(
          'AppConfig.allowedScreenIds.contains(ScreenId.purchaseOrders)'),
      isTrue,
      reason: 'أوامرُ الشراء تُحمَّل في نطاقٍ لا شاشةَ لها ولا مستند',
    );
    expect(code.contains('if (o.convertedToInvoiceId != null) continue'), isTrue,
        reason: 'أمرٌ مستهلَكٌ يُعرَض للربط — وعدٌ بسحبٍ يرفضه المحرّكُ عند '
            'الحفظ');
    expect(code.contains("if (o.status == 'cancelled') continue"), isTrue,
        reason: 'أمرٌ ملغىً يُعرَض للربط');
  });
}
