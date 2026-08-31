// ═══════════════════════════════════════════════════════════════════════════
// ٦‑٢ (النصفُ الثاني) — إخفاقُ تعديلِ الإضافات يجب أن يراه المستخدم
// ═══════════════════════════════════════════════════════════════════════════
//
// في `modifier_management_widget.dart` كان مسارُ **القراءة** وحدَه محروساً
// بـ`try`، وكلُّ عمليّاتِ التعديل الخمسِ عاريةً: الإضافةُ والحذفُ وحذفُ العنصر
// والربطُ وإضافةُ العنصر. وهي تُنادى **بعد** `Navigator.pop`، فالحوارُ يُغلَق
// ثمّ يُرمى الاستثناءُ في الفراغ: لا صفَّ يُضاف ولا رسالةَ تظهر — نجاحٌ وهميّ.
//
// وهذا هو بالضبط ما كان يقع على PostgreSQL حيث كان `modifier_groups` ناقصَ
// خمسةِ أعمدةٍ يكتبها `createModifierGroup` (عولج في `ensureModifierTables`).
//
// [runModifierMutation] هي الحارسُ الثاني، وهذا الاختبارُ يقيسها على السلوك
// الظاهر: رسالةٌ عند الإخفاق، وصمتٌ عند النجاح، وقيمةُ عودةٍ يبني عليها
// المُنادي قرارَ إعادة التحميل.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/presentation/widgets/settings/modifier_management_widget.dart';

void main() {
  /// يبني مضيفاً فيه `ScaffoldMessenger` ويعيد سياقَه.
  Future<BuildContext> pumpHost(WidgetTester tester) async {
    late BuildContext ctx;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (c) {
              ctx = c;
              return const SizedBox.shrink();
            },
          ),
        ),
      ),
    );
    return ctx;
  }

  testWidgets('إخفاقُ العمليّة يُظهر رسالةً للمستخدم ويعود false',
      (tester) async {
    final ctx = await pumpHost(tester);

    final ok = await runModifierMutation(
      ctx,
      () async => throw Exception('column "type" does not exist'),
      failureMessage: 'تعذّرت إضافة المجموعة',
    );
    await tester.pump(); // يُظهر الـSnackBar

    expect(ok, isFalse, reason: 'المُنادي يجب ألّا يُعيد التحميلَ على إخفاق');

    final snack = find.byType(SnackBar);
    expect(snack, findsOneWidget,
        reason: 'الإخفاقُ كان يُبتلَع صامتاً قبل الإصلاح');

    // النصُّ يحمل سببَ الإخفاق لا عبارةً عامّةً — وإلّا تعذّر تشخيصُه ميدانيّاً.
    expect(
      find.textContaining('تعذّرت إضافة المجموعة'),
      findsOneWidget,
    );
    expect(find.textContaining('column "type" does not exist'), findsOneWidget);
  });

  testWidgets('النجاحُ لا يُظهر رسالةً ويعود true', (tester) async {
    final ctx = await pumpHost(tester);

    var ran = false;
    final ok = await runModifierMutation(
      ctx,
      () async => ran = true,
      failureMessage: 'تعذّرت إضافة المجموعة',
    );
    await tester.pump();

    expect(ran, isTrue, reason: 'مرساة: العمليّةُ نُفِّذت فعلاً');
    expect(ok, isTrue);
    expect(find.byType(SnackBar), findsNothing,
        reason: 'حارسٌ ضدّ إصلاحٍ زائد — لا رسالةَ على نجاح');
  });
}
