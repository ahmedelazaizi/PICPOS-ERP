// حمولةُ مزامنة الاستبدال — واحدةٌ لا اثنتان.
//
import 'package:picpos_erp/services/client_write_interceptor.dart';
// **قرارُ المالك ٥:** حمولةٌ واحدةٌ يفكّها الخادمُ إلى مستندَين في معاملةٍ
// واحدة. وحمولتان مرتبطتان تفتحان نافذةَ انفصالٍ طرفاً لطرف: يصل المردودُ
// ويسقط البيعُ فيبقى العميلُ دائناً ببضاعةٍ أخذها.
//
// **ولماذا `returnLegs` قائمةٌ لا مستندٌ واحد:** `processSalesReturn` يقبل
// `isDamaged` **للنداء كلِّه لا للسطر**، فوسمٌ مختلطٌ (بعضُ المرتجَع معيبٌ
// وبعضُه سليم) يُقسَم إلى نداءين داخل معاملة الاستبدال ⇒ سندَي مردودٍ لا
// سنداً واحداً. فحمولةٌ تحمل مردوداً واحداً تُسقط الشقَّ الثاني صامتاً.

import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/domain/models/exchange_sync_payload.dart';

Map<String, dynamic> _returnLeg({
  required bool damaged,
  double total = 100,
}) =>
    <String, dynamic>{
      'globalId': damaged ? 'ret-damaged' : 'ret-sound',
      'originalInvoiceId': 7,
      'isDamaged': damaged,
      'items': <Map<String, dynamic>>[
        {'productId': 1, 'quantity': 1, 'unitPrice': total, 'total': total},
      ],
      'total': total,
    };

Map<String, dynamic> _sale({double total = 130}) => <String, dynamic>{
      'globalId': 'sale-gid',
      'items': <Map<String, dynamic>>[
        {'productId': 2, 'quantity': 1, 'unitPrice': total, 'total': total},
      ],
      'total': total,
      'paid': total,
    };

void main() {
  group('حمولةُ مزامنة الاستبدال', () {
    test('حمولةٌ **واحدة** تحمل الشقَّين ومفتاحَ الربط', () {
      final payload = buildExchangeSyncPayload(
        exchangeKey: 'exch-key-1',
        originalInvoiceId: 7,
        originalInvoiceGlobalId: 'orig-gid',
        originalInvoiceNumber: 'SINV-7',
        returnLegs: [_returnLeg(damaged: false)],
        sale: _sale(),
      );

      // شقُّ المردود وشقُّ البيع في **نفس** الخريطة — لا مستندان مرسَلان.
      expect(payload['returnLegs'], isA<List<dynamic>>());
      expect((payload['returnLegs'] as List).length, 1);
      expect(payload['sale'], isA<Map<String, dynamic>>());

      // مفتاحُ الربط حاضرٌ ومطابقٌ لمفتاح الـidempotency.
      expect(payload['exchangeKey'], 'exch-key-1');
      expect(payload['globalId'], 'exch-key-1');

      // مُعرِّفاتُ الأصلية الثلاثة تُرحَّل كي يحلَّها الخادمُ ولو تباعدت
      // أرقامُ العميل والخادم.
      expect(payload['originalInvoiceId'], 7);
      expect(payload['originalInvoiceGlobalId'], 'orig-gid');
      expect(payload['originalInvoiceNumber'], 'SINV-7');
    });

    test('الوسمُ المختلط يضع شقَّي المردود في **نفس** الحمولة', () {
      final payload = buildExchangeSyncPayload(
        exchangeKey: 'exch-key-2',
        originalInvoiceId: 7,
        returnLegs: [
          _returnLeg(damaged: false, total: 60),
          _returnLeg(damaged: true, total: 40),
        ],
        sale: _sale(),
      );

      final legs = payload['returnLegs'] as List;
      expect(legs.length, 2,
          reason: 'شقُّ المعيب وشقُّ السليم كلاهما داخل الحمولة الواحدة');
      expect((legs[0] as Map)['isDamaged'], isFalse);
      expect((legs[1] as Map)['isDamaged'], isTrue);
    });

    test('كلُّ شقِّ مردودٍ يحمل مفتاحَ الاستبدال — الربطُ لا يتوقّف على الترتيب',
        () {
      final payload = buildExchangeSyncPayload(
        exchangeKey: 'exch-key-3',
        originalInvoiceId: 7,
        returnLegs: [
          _returnLeg(damaged: false),
          _returnLeg(damaged: true),
        ],
        sale: _sale(),
      );

      for (final leg in payload['returnLegs'] as List) {
        expect((leg as Map)['exchangeKey'], 'exch-key-3');
      }
      expect((payload['sale'] as Map)['exchangeKey'], 'exch-key-3');
    });

    test('استبدالٌ بلا شقِّ مردودٍ مرفوضٌ — ليس استبدالاً', () {
      expect(
        () => buildExchangeSyncPayload(
          exchangeKey: 'k',
          originalInvoiceId: 7,
          returnLegs: const [],
          sale: _sale(),
        ),
        throwsArgumentError,
      );
    });

    test('استبدالٌ بلا شقِّ بيعٍ مرفوضٌ — ذاك مردودٌ لا استبدال', () {
      expect(
        () => buildExchangeSyncPayload(
          exchangeKey: 'k',
          originalInvoiceId: 7,
          returnLegs: [_returnLeg(damaged: false)],
          sale: const <String, dynamic>{},
        ),
        throwsArgumentError,
      );
    });

    test('وسمُ الربط واحدٌ على الشكلَين — نصٌّ مشتركٌ لا اشتقاقان', () {
      // الشكلُ «أ» (قلبُ الأصلية) والشكلُ «ب» (مستندُ مردودٍ منفصل) يحملان
      // نفسَ `|exch:` — وإلّا عجز الخادمُ عن ربط ما بناه العميل.
      expect(exchangeLinkTag('K'), '|exch:K');
      expect(exchangeSaleTag(12), '|exsale:12');
      expect(exchangeReturnTag(7), '|exret:7');
    });
  });

  group('مُجمِّعُ شقوق الاستبدال', () {
    test('يلتقط الشقوقَ بترتيبها ويبني حمولةً واحدة', () {
      final collector = ExchangeLegCollector();
      collector.addReturnLeg(_returnLeg(damaged: false, total: 60));
      collector.addReturnLeg(_returnLeg(damaged: true, total: 40));
      collector.setSale(_sale());

      final payload = collector.build(
        exchangeKey: 'k-1',
        originalInvoiceId: 7,
      );
      expect((payload['returnLegs'] as List).length, 2);
      expect((payload['sale'] as Map)['total'], 130);
    });

    test('لا شيءَ التُقط ⇒ لا حمولة — الوضعُ المستقلُّ لا يزامن', () {
      final collector = ExchangeLegCollector();
      expect(collector.isEmpty, isTrue);
      expect(collector.hasBothLegs, isFalse);
    });

    test('شقُّ مردودٍ بلا بيعٍ ليس حمولةً صالحة', () {
      final collector = ExchangeLegCollector()
        ..addReturnLeg(_returnLeg(damaged: false));
      expect(collector.hasBothLegs, isFalse,
          reason: 'الإرسالُ يُمتنع بدل أن يُنشئ نصفَ استبدالٍ على الخادم');
    });

    test('بيعان في استبدالٍ واحدٍ خطأُ برمجةٍ يُرفَض لا يُبتلَع', () {
      final collector = ExchangeLegCollector()..setSale(_sale());
      expect(() => collector.setSale(_sale()), throwsStateError);
    });
  });

  group('نطاقُ تجميع الاستبدال', () {
    test('المُجمِّعُ مرئيٌّ داخل النطاق ومعدومٌ خارجَه', () async {
      expect(ClientWriteInterceptor.activeExchangeCollector, isNull,
          reason: 'خارجَ النطاق يمرّ كلُّ بيعٍ ومردودٍ عاديٍّ بلا تغيير');

      final collector = ExchangeLegCollector();
      await ClientWriteInterceptor.runWithExchangeCollector(collector, () async {
        expect(
          identical(ClientWriteInterceptor.activeExchangeCollector, collector),
          isTrue,
        );
      });

      expect(ClientWriteInterceptor.activeExchangeCollector, isNull);
    });

    test('استثناءٌ داخل النطاق لا يترك المُجمِّعَ متسرِّباً', () async {
      final collector = ExchangeLegCollector();
      await expectLater(
        ClientWriteInterceptor.runWithExchangeCollector(
          collector,
          () async => throw StateError('فشلٌ داخل شقّ الاستبدال'),
        ),
        throwsStateError,
      );

      // هذه هي حجّةُ `Zone` على الحقل الساكن: حقلٌ ساكنٌ يُفتَح ولا يُغلَق عند
      // الرمي يبتلع مزامنةَ **كلِّ** بيعٍ تالٍ صامتاً — والفواتيرُ تُحفظ
      // محلّياً ولا تصل الخادمَ أبداً.
      expect(ClientWriteInterceptor.activeExchangeCollector, isNull);
    });
  });
}
