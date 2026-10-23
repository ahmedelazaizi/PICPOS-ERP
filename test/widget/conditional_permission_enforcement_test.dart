// إنفاذُ الصلاحية المشروطة — الترتيبُ هو الميزةُ كلُّها.
//
// «مشروط» تعني: الصلاحيةُ **ممنوحةٌ** (‏كودُها في قائمة المستخدم) ويمرّ
// تنفيذُها بموافقة مسؤول. فلو فُحص المِلكُ قبل الشرط لعاد `true` فوراً ولما
// سُئل مسؤولٌ أبداً — ويصير «مشروط» مفتاحاً لا يفعل شيئاً، وهو أسوأُ من
// غيابه لأنّ المديرَ يظنّ أنّه اشترط.
//
// ⚠️ **ولذلك يُقاس هنا السلوكُ الظاهرُ لا وجودُ السطر**: هل ظهر حوارُ
// الموافقة أم لا. فطفرةٌ تعكس الشرطَين تُسقط هذه الفحوصَ حتماً.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/core/permissions/permission_codes.dart';
import 'package:picpos_erp/data/providers/providers.dart';
import 'package:picpos_erp/presentation/widgets/permission_guard.dart';

void main() {
  const code = PermissionCodes.posDiscount;

  /// يبني شجرةً بزرٍّ ينادي `ensurePermission` ويسجّل نتيجتَه.
  Future<List<bool>> pumpGate(
    WidgetTester tester,
    List<String> perms,
  ) async {
    final results = <bool>[];
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          // ⚠️ **تجاوزٌ متزامنٌ لا `async`**: `ensurePermission` تقرأ
          //    `.value` قراءةً متزامنة. ومزوِّدٌ يعود بـFuture يبقى في
          //    `loading` ما لم يستمع إليه أحدٌ ويُنتظَر — فتقرأ الدالّةُ
          //    قائمةً فارغةً ويظهر حوارُ الموافقة **لكلّ** حالة، فيمرّ
          //    الاختبارُ الثاني على وهمٍ ويسقط الأوّل.
          currentUserPermissionsProvider.overrideWith((ref) => perms),
        ],
        child: MaterialApp(
          home: Consumer(
            builder: (context, ref, _) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () async {
                    results.add(await ensurePermission(
                      ref,
                      context,
                      code,
                      actionName: 'خصم يدوي',
                    ));
                  },
                  child: const Text('نفّذ'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return results;
  }

  testWidgets('ممنوحةٌ بلا شرط ⇒ تمضي بلا سؤالِ مسؤول', (tester) async {
    final results = await pumpGate(tester, [code]);
    await tester.tap(find.text('نفّذ'));
    await tester.pumpAndSettle();

    expect(results, [true]);
    expect(find.byType(Dialog), findsNothing,
        reason: 'سُئل مسؤولٌ عن صلاحيةٍ ممنوحةٍ بلا شرط — احتكاكٌ بلا سبب.');
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets('ممنوحةٌ **مشروطةً** ⇒ يُطلَب مسؤولٌ رغم أنّها ممنوحة',
      (tester) async {
    final results = await pumpGate(
      tester,
      [code, PermissionCodes.conditionalMarker(code)],
    );
    await tester.tap(find.text('نفّذ'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // ⚠️ الجوهرُ هنا: الكودُ **في القائمة** ومع ذلك ظهر الحوار.
    expect(results, isEmpty,
        reason: 'رجعت النتيجةُ بلا حوار — أي أنّ الشرطَ لم يُفحَص، وربّما '
            'فُحص المِلكُ قبله فاختصر الطريق.');
    expect(
      find.text('صلاحية مطلوبة').evaluate().isNotEmpty ||
          find.byType(AlertDialog).evaluate().isNotEmpty ||
          find.byType(Dialog).evaluate().isNotEmpty,
      isTrue,
      reason: 'لم يظهر حوارُ موافقة المسؤول لصلاحيةٍ مشروطة.',
    );

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets('وحارسُ الودجت يُظهر المشروطَ لا يُخفيه', (tester) async {
    // التصميمُ يصف المشروطَ «يحتاج موافقةً» لا «ممنوع» — فإخفاءُ الزرّ
    // يجعله ممنوعاً في عين المشغّل.
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          currentUserPermissionsProvider.overrideWith(
            (ref) async => [code, PermissionCodes.conditionalMarker(code)],
          ),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: PermissionGuard(
              permission: code,
              actionName: 'خصم يدوي',
              child: Text('زرُّ الخصم'),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('زرُّ الخصم'), findsOneWidget,
        reason: 'أُخفي إجراءٌ مشروطٌ — والمشروطُ يُعرَض ويُسأل عنه، لا يُمنَع.');
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets('وغيرُ الممنوحةِ تبقى مخفيّةً — الشرطُ لم يُرخِ المنع',
      (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          currentUserPermissionsProvider.overrideWith((ref) async => <String>[]),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: PermissionGuard(
              permission: code,
              actionName: 'خصم يدوي',
              child: Text('زرُّ الخصم'),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('زرُّ الخصم'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });
}
