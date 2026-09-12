// طابورُ طلباتِ الضيوف — نصفُ البند الأوّل الثاني (أمرُ المالك 2026-09-12).
//
// ═══ لماذا طابورٌ في الذاكرة لا جدولٌ في القاعدة ═══
//
// طلبُ الضيف **ليس مستنداً ماليّاً** حتى يعتمده النادل؛ وعند الاعتماد يمرّ
// بمسار `addOrUpdateTableOrderItem` فيُكتَب صفّاً حقيقيّاً بلقطة ضريبته.
// فصفٌّ يعيش دقائقَ ثم يُستهلَك لا يستحقّ جدولاً ولا هجرةً ولا ثمانيَ قوائمِ
// مزامنة — وفقدانُه بإعادة تشغيلٍ يعادل نقرةً يعيدها الضيف.
//
// ═══ وما يجب أن يحرسه الطابورُ نفسُه ═══
//
// مصدرُه **هاتفٌ غيرُ مصادَقٍ** على شبكة المحلّ. فبلا سقفٍ يملؤه من يكرّر
// الإرسال حتى تختنق الذاكرة — وهو أرخصُ هجومٍ على الإطلاق: زرٌّ يُضغط.
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/services/guest_order_requests.dart';

void main() {
  late GuestOrderRequests queue;

  setUp(() => queue = GuestOrderRequests.forTesting());

  List<GuestOrderLine> lines([int n = 1]) => [
        for (var i = 0; i < n; i++)
          GuestOrderLine(productId: i + 1, quantity: 1),
      ];

  group('الإدراجُ والاستهلاك', () {
    test('طلبٌ يدخل فيُرى معلَّقاً', () {
      final id = queue.enqueue(
        tableId: 1,
        orderId: 7,
        tableName: 'ط١',
        lines: lines(2),
      );
      expect(id, isNotNull);
      expect(queue.pending, hasLength(1));
      expect(queue.pending.single.orderId, 7);
      expect(queue.pending.single.lines, hasLength(2));
    });

    test('ويُستهلَك مرّةً واحدةً — اعتمادان لا يُنتجان صنفَين', () {
      final id = queue.enqueue(
        tableId: 1,
        orderId: 7,
        tableName: 'ط١',
        lines: lines(),
      )!;
      expect(queue.take(id), isNotNull);
      expect(queue.take(id), isNull,
          reason: 'نقرتان على «اعتماد» تُضاعفان الطلبَ على حساب الضيف');
      expect(queue.pending, isEmpty);
    });

    test('ومعرِّفٌ مجهولٌ لا يُستهلَك', () {
      expect(queue.take(9999), isNull);
    });

    test('والرفضُ يُسقطه كما يُسقطه الاعتماد', () {
      final id = queue.enqueue(
        tableId: 1,
        orderId: 7,
        tableName: 'ط١',
        lines: lines(),
      )!;
      expect(queue.reject(id), isTrue);
      expect(queue.pending, isEmpty);
      expect(queue.reject(id), isFalse);
    });
  });

  group('السقوفُ — والمصدرُ هاتفٌ غيرُ مصادَق', () {
    test('سقفٌ لكلّ طاولةٍ يمنع إغراقَ شاشة النادل', () {
      int? last;
      for (var i = 0; i < GuestOrderRequests.maxPerOrder + 3; i++) {
        last = queue.enqueue(
          tableId: 1,
          orderId: 7,
          tableName: 'ط١',
          lines: lines(),
        );
      }
      expect(last, isNull, reason: 'تجاوزُ السقف قُبل');
      expect(queue.pending, hasLength(GuestOrderRequests.maxPerOrder));
    });

    test('وطاولةٌ ممتلئةٌ لا تمنع غيرَها', () {
      for (var i = 0; i < GuestOrderRequests.maxPerOrder; i++) {
        queue.enqueue(tableId: 1, orderId: 7, tableName: 'ط١', lines: lines());
      }
      expect(
        queue.enqueue(tableId: 2, orderId: 8, tableName: 'ط٢', lines: lines()),
        isNotNull,
        reason: 'سقفُ طاولةٍ أغلق الطابورَ كلَّه',
      );
    });

    test('وسقفٌ للبنود داخلَ الطلب الواحد', () {
      expect(
        queue.enqueue(
          tableId: 1,
          orderId: 7,
          tableName: 'ط١',
          lines: lines(GuestOrderRequests.maxLinesPerRequest + 1),
        ),
        isNull,
      );
    });

    test('وطلبٌ بلا بنودٍ لا يُقبَل', () {
      expect(
        queue.enqueue(tableId: 1, orderId: 7, tableName: 'ط١', lines: const []),
        isNull,
      );
    });

    test('وكمّيّةٌ غيرُ موجبةٍ تُرفَض', () {
      expect(
        queue.enqueue(
          tableId: 1,
          orderId: 7,
          tableName: 'ط١',
          lines: [const GuestOrderLine(productId: 1, quantity: 0)],
        ),
        isNull,
      );
      expect(
        queue.enqueue(
          tableId: 1,
          orderId: 7,
          tableName: 'ط١',
          lines: [const GuestOrderLine(productId: 1, quantity: -2)],
        ),
        isNull,
        reason: 'كمّيّةٌ سالبةٌ تُنقص حسابَ الضيف من هاتفه',
      );
    });
  });

  group('العمرُ والإغلاق', () {
    test('إغلاقُ الطلب يُسقط ما عُلِّق عليه', () {
      queue.enqueue(tableId: 1, orderId: 7, tableName: 'ط١', lines: lines());
      queue.enqueue(tableId: 2, orderId: 8, tableName: 'ط٢', lines: lines());

      queue.dropForOrder(7);
      expect(queue.pending, hasLength(1));
      expect(queue.pending.single.orderId, 8,
          reason: 'طلبٌ معلَّقٌ على طاولةٍ أُغلقت يُعتمَد على حسابِ الضيف '
              'التالي الذي يجلس عليها');
    });
  });

  group('الإيقاظ', () {
    test('كلُّ تغييرٍ يوقظ الشاشةَ — ولو تطابق المحتوى', () {
      var woke = 0;
      void listener() => woke++;
      queue.addListener(listener);
      addTearDown(() => queue.removeListener(listener));

      final a = queue.enqueue(
        tableId: 1,
        orderId: 7,
        tableName: 'ط١',
        lines: lines(),
      )!;
      expect(woke, 1);

      // طلبٌ ثانٍ مطابقٌ حرفاً — ضيفٌ ضغط مرّتين على نفس الصنف.
      queue.enqueue(tableId: 1, orderId: 7, tableName: 'ط١', lines: lines());
      expect(woke, 2, reason: 'المساواةُ ابتلعت الطلبَ الثاني');

      queue.take(a);
      expect(woke, 3);
    });

    test('ومحاولةٌ مرفوضةٌ لا توقظ — لا شيء تغيّر', () {
      var woke = 0;
      void listener() => woke++;
      queue.addListener(listener);
      addTearDown(() => queue.removeListener(listener));

      queue.enqueue(tableId: 1, orderId: 7, tableName: 'ط١', lines: const []);
      expect(woke, 0);
    });
  });
}
