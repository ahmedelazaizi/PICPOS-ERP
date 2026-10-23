// شريطُ ترشيح المشتريات: **يلتفّ ولا يفيض** — وقرارُ «مركز التكلفة يظلّ
// ظاهراً» لا يُصان إلّا بهذا.
//
// ═══ ما كان ═══
//
// الشريطُ كان `Row` واحداً غيرَ قابلٍ للتمرير يحمل: بحثاً بعرضٍ ثابتٍ ٢٦٠،
// وحبّةَ مدىً زمنيّ، وثلاثَ قوائمَ (الفرع · المخزن · **مركز التكلفة**)،
// و`Spacer`، وثلاثَ شرائحِ حالةٍ بعدّادات. ومجموعُها يتجاوز عرضَ نافذةٍ
// متوسّطة.
//
// و`Spacer` داخلَ `Row` مكتظٍّ **يأخذ صفراً** ثمّ يُبتَر ما بعده. فأوّلُ ما
// يضيع هو آخرُ القوائم — **مركزُ التكلفة** — وهو بعينه ما نصّ قرارُ المالك
// 2026-09-18 على بقائه ظاهراً في الشريط الأساسيّ.
//
// ⚠️ **و`RenderFlex overflowed` لا يرمي في الإصدار**: يرسم شريطاً أصفرَ
// وأسودَ ويمضي. فتوكيدُ «لم تنهر» يمرّ على شريطٍ مبتور — ولذلك يُلتقَط
// `FlutterError.onError` صراحةً.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/data/database/database.dart';
import 'package:picpos_erp/data/providers/auth_providers.dart';
import 'package:picpos_erp/data/providers/inventory_providers.dart';
import 'package:picpos_erp/domain/repositories/inventory_repository.dart'
    show WarehouseData;
import 'package:picpos_erp/presentation/purchases_picpos/screens/purchases_picpos_screen.dart';
import 'package:picpos_erp/presentation/screens/purchases/purchase_invoices_controller.dart';

/// متحكّمٌ لا يلمس قاعدةً — `build` تُستبدَل كاملةً فلا يُشغَّل تحميلُ الأصل.
class _FrozenController extends PurchaseInvoicesController {
  @override
  PurchaseInvoicesScreenState build() => PurchaseInvoicesScreenState(
        isLoading: false,
        statusFilter: 'all',
        statusCounts: const {'paid': 12, 'partial': 5, 'unpaid': 31},
      );
}

Branche _branch(int id, String name) => Branche(
      id: id,
      name: name,
      isActive: true,
      isSystemDefault: false,
      rowVersion: 0,
    );

CostCenter _cc(int id, String name) => CostCenter(
      id: id,
      code: 'CC$id',
      name: name,
      isActive: true,
      createdAt: DateTime(2026),
      rowVersion: 0,
    );

final _barKey = GlobalKey();

const _wide = 1400.0;
const _mid = 900.0;
const _narrow = 520.0;

Future<({double height, List<String> layoutErrors})> _measure(
  WidgetTester tester,
  double width,
) async {
  final errors = <String>[];
  final previous = FlutterError.onError;
  FlutterError.onError = (details) => errors.add(details.exceptionAsString());
  try {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          purchaseInvoicesControllerProvider
              .overrideWith(_FrozenController.new),
          allBranchesProvider.overrideWith(
            (ref) => Stream.value([
              _branch(1, 'الفرع الرئيسي'),
              _branch(2, 'فرع مدينة نصر'),
            ]),
          ),
          allWarehousesProvider.overrideWith(
            (ref) => Stream.value(const [
              WarehouseData(id: 1, name: 'المخزن الرئيسي', isDefault: true),
              WarehouseData(id: 2, name: 'مخزن التوزيع', isDefault: false),
            ]),
          ),
          allCostCentersProvider.overrideWith(
            (ref) => Stream.value([
              _cc(1, 'إدارة المبيعات'),
              _cc(2, 'إدارة التشغيل'),
            ]),
          ),
        ],
        child: MaterialApp(
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: Scaffold(
              body: Center(
                child: SizedBox(
                  width: width,
                  child: PurchasesFilterBar(
                    key: _barKey,
                    searchController: TextEditingController(),
                    searchFocusNode: FocusNode(),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    // إطارٌ ثانٍ: مجاري الفروع والمخازن ومراكز التكلفة تصل بعد الأوّل،
    // وقياسُ الإطار الأوّل يقيس شريطاً بلا قوائمَ — أي لا يقيس شيئاً.
    await tester.pump();
    await tester.pump();
  } finally {
    FlutterError.onError = previous;
  }
  return (
    height: tester.getSize(find.byKey(_barKey)).height,
    layoutErrors: errors,
  );
}

void main() {
  testWidgets('مرساةٌ — القوائمُ الثلاثُ وصلت فعلاً', (tester) async {
    await _measure(tester, _wide);
    // بلا هذه المرساة يمرّ كلُّ ما تحتها على شريطٍ فارغ: القوائمُ تختفي
    // بنفسها حين تكون واحدةً أو صفراً (`length <= 1` / `isEmpty`).
    expect(find.text('الفرع'), findsOneWidget);
    expect(find.text('المخزن'), findsOneWidget);
    expect(find.text('مركز التكلفة'), findsOneWidget,
        reason: 'مركزُ التكلفة غائبٌ — والقرارُ أنّه يظلّ ظاهراً');
  });

  testWidgets('ولا يفيض على أيّ عرض', (tester) async {
    for (final w in const [_wide, _mid, _narrow]) {
      final m = await _measure(tester, w);
      expect(m.layoutErrors, isEmpty, reason: 'فاض عند العرض $w');
    }
  });

  testWidgets('ويلتفّ فعلاً — الارتفاعُ يزيد كلّما ضاق', (tester) async {
    final wide = await _measure(tester, _wide);
    final mid = await _measure(tester, _mid);
    final narrow = await _measure(tester, _narrow);

    // ⚠️ **ولا يُقاس `mid` مقابلَ `wide`.** خطُّ اختبار Flutter يجعل عرضَ
    // كلِّ محرفٍ = حجمَ الخطّ، فالنصُّ العربيُّ أعرضُ كثيراً مما يُرسَم في
    // المنتج: الشريطُ يلتفّ هنا عند ١٤٠٠ أصلاً (١٤٨ = ١٤٨). فالقياسُ على
    // طرفَي المدى حيث الفرقُ حقيقيٌّ لا أثرٌ للخطّ فيه.
    expect(mid.height, greaterThanOrEqualTo(wide.height));
    expect(narrow.height, greaterThan(wide.height),
        reason: 'الارتفاعُ لم يزد بين $_wide و$_narrow ⇒ لم يقع التفافٌ '
            'إضافيّ، فالمحتوى خرج من الحدّ صامتاً');
  });

  testWidgets('ومركزُ التكلفة داخلَ حدود الشريط لا خارجَها', (tester) async {
    // ⚠️ **و`findsOneWidget` وحدَها لا تكفي — أثبتته طفرةٌ نجت منها.**
    // الودجتُ الفائضةُ تبقى في الشجرة وتُخطَّط ويجدها `find.text` كاملةً؛
    // الفيضُ يمنع رؤيتَها لا وجودَها. فأُعيدت الطفرةُ (‏`Row` + `Spacer`)
    // وبقي هذا التوكيدُ أخضرَ بينما الشريطُ يفيض ١١٠ بكسل.
    //
    // فالمقيسُ الآن **الحدودُ**: مستطيلُ «مركز التكلفة» داخلَ مستطيل
    // الشريط. وهو عينُ قرارِ المالك 2026-09-18 — أنّه يظلّ **ظاهراً**.
    await _measure(tester, _narrow);
    final bar = tester.getRect(find.byKey(_barKey));
    final pill = tester.getRect(find.text('مركز التكلفة'));
    expect(pill.left, greaterThanOrEqualTo(bar.left - 0.5),
        reason: 'مركزُ التكلفة خرج من حدّ الشريط الأيسر — مبتورٌ عملياً');
    expect(pill.right, lessThanOrEqualTo(bar.right + 0.5),
        reason: 'مركزُ التكلفة خرج من حدّ الشريط الأيمن — مبتورٌ عملياً');
  });
}
