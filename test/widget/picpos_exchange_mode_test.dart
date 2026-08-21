// سطحُ وضع الاستبدال — الأرقامُ الثلاثة.
//
// **ما يحرسه هذا الملفّ:** أن الترويسةَ تعرض ما يُمرَّر إليها ولا تشتقّ الفرقَ
// بنفسها. اشتقاقُ الفرق في الودجت — ولو بطرحٍ بسيط — يُنشئ حاسباً ثانياً
// يفترق عن المنفَّذ عند أوّل تقريب، وهو العطبُ الذي عرض «١٠٠» وأخرج «١١٤».

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/domain/models/exchange_settlement.dart';
import 'package:ural_erp/presentation/pos_picpos/widgets/picpos_exchange_mode_banner.dart';

Widget _wrap(Widget child) => MaterialApp(
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(body: child),
      ),
    );

void main() {
  group('ترويسةُ وضع الاستبدال', () {
    testWidgets('تعرض الأرقامَ الثلاثةَ ورقمَ الفاتورة', (tester) async {
      await tester.pumpWidget(_wrap(const PicPosExchangeModeBanner(
        invoiceNumber: 'SINV-42',
        refundTotal: 50,
        replacementTotal: 130,
        direction: ExchangeCashDirection.collect,
        difference: 80,
      )));

      expect(find.text('وضع الاستبدال'), findsOneWidget);
      expect(find.text('SINV-42'), findsOneWidget);
      // الثلاثةُ حاضرةٌ نصّاً — المرتجعُ والبديلُ والفرق.
      expect(find.textContaining('المرتجع'), findsOneWidget);
      expect(find.textContaining('البديل'), findsOneWidget);
      expect(find.textContaining('يُحصَّل'), findsOneWidget);
    });

    testWidgets('البديلُ الأرخصُ يُعرض ردّاً لا رقماً سالباً', (tester) async {
      await tester.pumpWidget(_wrap(const PicPosExchangeModeBanner(
        invoiceNumber: 'SINV-42',
        refundTotal: 130,
        replacementTotal: 50,
        direction: ExchangeCashDirection.refund,
        difference: 80,
      )));

      expect(find.textContaining('يُرَدّ'), findsOneWidget);
      expect(find.textContaining('يُحصَّل'), findsNothing);
      // الإشارةُ في الاتّجاه لا في الرقم — لا سالبَ يظهر للكاشير.
      expect(find.textContaining('−'), findsNothing);
      expect(find.textContaining('-80'), findsNothing);
    });

    testWidgets('التساوي يقول «لا فرق» ولا يعرض مبلغاً', (tester) async {
      await tester.pumpWidget(_wrap(const PicPosExchangeModeBanner(
        invoiceNumber: 'SINV-42',
        refundTotal: 100,
        replacementTotal: 100,
        direction: ExchangeCashDirection.none,
        difference: 0,
      )));

      expect(find.text('لا فرق'), findsOneWidget);
      expect(find.textContaining('يُحصَّل'), findsNothing);
      expect(find.textContaining('يُرَدّ'), findsNothing);
    });

    testWidgets('الترويسةُ تعرض ما يُمرَّر ولا تشتقّ الفرقَ بنفسها',
        (tester) async {
      // فرقٌ **لا يساوي** طرحَ الإجماليَّين: لو اشتقّت الودجت الرقمَ لعرضت
      // ٨٠، ولو عرضت الممرَّرَ لعرضت ٥. والمنفَّذُ على الدرج هو الممرَّر.
      await tester.pumpWidget(_wrap(const PicPosExchangeModeBanner(
        invoiceNumber: 'SINV-42',
        refundTotal: 50,
        replacementTotal: 130,
        direction: ExchangeCashDirection.collect,
        difference: 5,
      )));

      expect(find.textContaining('5'), findsWidgets);
      expect(find.textContaining('يُحصَّل'), findsOneWidget);
    });
  });
}
