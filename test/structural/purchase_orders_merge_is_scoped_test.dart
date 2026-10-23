// حارسُ العقد: أوامرُ الشراء لا تُحمَّل في نطاقٍ لا تعيش فيه.
//
// ═══ فئةُ العطب ═══
//
// قرارُ المالك 2026-09-18 دمجَ أوامرَ الشراء في قائمة «الاستعلام عن
// المشتريات» ومرشِّحَ «نوع المستند» معها. لكنّ `ScreenId.purchaseOrders`
// يعيش في **نطاقٍ واحدٍ فقط** (`ScreenRegistry.unified`).
//
// فبلا تسييج:
//   • تُقرأ أوامرُ الشراء في مطعمٍ أو سوبرماركت — مستنداتٌ لا شاشةَ لها ولا
//     طريقةَ لإنشائها ولا لتعديلها، تظهر في القائمة بلا أفعال.
//   • ويظهر مرشِّحٌ بنوعٍ ثالثٍ **يُرجِع صفراً دائماً**، فيبدو معطَّلاً.
//
// ⚠️ **وهذا ليس فرضاً نظريّاً**: الشاشةُ نفسُها تعرض اليومَ زرَّ «طلبات
// الشراء» يفتح `PurchaseOrdersScreen` بمسارٍ مباشرٍ يتجاوز السجلَّ — فالنطاقُ
// يُتجاوَز في هذا الملفّ أصلاً، وهو ما يجعل الحارسَ ضروريّاً لا احتياطاً.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/core/navigation/screen_id.dart';
import 'package:picpos_erp/core/navigation/screen_registry.dart';

const _controllerPath =
    'lib/presentation/screens/purchases/purchase_invoices_controller.dart';

String _code(String raw) => [
      for (final line in raw.split('\n'))
        if (!line.trimLeft().startsWith('//')) line,
    ].join('\n');

void main() {
  test('أوامرُ الشراء في `unified` وحدَه — فالتسييجُ مبرَّر', () {
    // ⚠️ **يُشتقُّ من السجلّ لا يُكتَب هنا.** لو أُضيفت الشاشةُ غداً إلى
    // نطاقٍ ثانٍ سقط هذا الفحصُ وطالبَ بمراجعة التسييج — بدل أن يبقى
    // الشرطُ يمنع ميزةً صارت مشروعة.
    expect(ScreenRegistry.unified.contains(ScreenId.purchaseOrders), isTrue,
        reason: 'خرجت من `unified` — فالتسييجُ صار يمنعها في كلّ مكان');

    final others = <String, List<ScreenId>>{
      'restaurant': ScreenRegistry.restaurant,
      'supermarket': ScreenRegistry.supermarket,
      'supermarketPro': ScreenRegistry.supermarketPro,
      'supermarketPlus': ScreenRegistry.supermarketPlus,
      'commercial': ScreenRegistry.commercial,
      'lite': ScreenRegistry.lite,
      'litePicpos': ScreenRegistry.litePicpos,
      'restaurantPicpos': ScreenRegistry.restaurantPicpos,
    };
    final leaked = [
      for (final MapEntry(key: name, value: ids) in others.entries)
        if (ids.contains(ScreenId.purchaseOrders)) name,
    ];
    expect(leaked, isEmpty,
        reason: 'أوامرُ الشراء صارت في نطاقاتٍ أخرى ($leaked) — '
            'راجع تسييجَ `_loadPurchaseOrders` قبل أن تُصدّق الأخضر');
  });

  test('والمتحكّمُ يفحص النطاقَ قبل أن يقرأ', () {
    final code = _code(File(_controllerPath).readAsStringSync());
    final at = code.indexOf('Future<void> _loadPurchaseOrders() async {');
    expect(at, greaterThan(0), reason: 'المُحمِّلُ اختفى — راجع الدمجَ كلَّه');

    // الفحصُ في **جسم الدالّة** لا في الملفّ: وجودُ الرمز في ملفٍّ يكذب
    // متى ظهر مرّتَين، وهو درسٌ مسجَّلٌ في حارسِ تابات الشاشات.
    final body = code.substring(at, code.indexOf('\n  }', at));
    expect(body.contains('AppConfig.allowedScreenIds'), isTrue,
        reason: 'المُحمِّلُ لا يسأل عن النطاق — فيقرأ أوامرَ شراءٍ في مطعم');
    expect(body.contains('ScreenId.purchaseOrders'), isTrue,
        reason: 'يسأل عن النطاق بلا أن يسمّي الشاشةَ التي يحرسها');
    expect(body.contains('return'), isTrue,
        reason: 'يفحص ولا يخرج — فحصٌ بلا أثر');
  });

  test('والمرشِّحُ لا يُعرَض بلا نطاقه', () {
    final bar = _code(
      File('lib/presentation/purchases_picpos/screens/purchases_filter_bar.dart')
          .readAsStringSync(),
    );
    expect(bar.contains('ordersInScope'), isTrue,
        reason: 'حبّةُ «نوع المستند» بلا تسييج — نوعٌ ثالثٌ يُرجِع صفراً '
            'دائماً فيبدو معطَّلاً');
    expect(bar.contains('if (ordersInScope)'), isTrue,
        reason: 'الرايةُ محسوبةٌ ولا تحرس شيئاً');
  });
}
