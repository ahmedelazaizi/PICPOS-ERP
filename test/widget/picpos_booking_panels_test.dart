// لوحُ الحجز الجديد وحوارُ التفويتر — **تركيبُهما وأثرُهما**.
//
// ═══ ما يُقاس هنا ولا يمسكه اختبارُ وحدة ═══
//
// حوارُ التفويتر لا يُنشئ فاتورةً؛ يرفع **علامةً** تُخبر مسارَ الدفع أنّ
// البيعةَ القادمةَ تفويترُ حجزٍ لا بيعةٌ عاديّة. وخطأُ رفعِ العلامة يقع في
// اتّجاهين وكلاهما مال:
//   • تُرفَع رغم فشل الحارس ⇒ حجزٌ معلَّقٌ بلا سلّةٍ يلتصق بأوّل بيعةٍ
//     تالية فيُخصَم عربونٌ من زبونٍ آخر.
//   • لا تُرفَع عند النجاح ⇒ يبقى العربونُ في الالتزام ويُحاسَب العميلُ
//     مرّتين — وهو بلاغُ المالك الأصليّ.
import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/data/providers/providers.dart';
import 'package:ural_erp/domain/models/picpos_booking_view.dart';
import 'package:ural_erp/presentation/bookings_picpos/widgets/booking_invoice_dialog.dart';
import 'package:ural_erp/presentation/bookings_picpos/widgets/new_booking_panel.dart';

void main() {
  final day = DateTime(2026, 9, 1);
  late AppDatabase db;
  late int serviceId;

  setUp(() async {
    db = AppDatabase.forTesting();
    serviceId = await db.into(db.bookingServices).insert(
          BookingServicesCompanion.insert(
            name: 'قصّ شعر',
            durationMinutes: const Value(45),
            price: const Value(500),
          ),
        );
  });

  tearDown(() => db.close());

  BookingBoardRow row({double deposit = 300}) => BookingBoardRow(
        id: 1,
        startsAt: day.add(const Duration(hours: 10)),
        endsAt: day.add(const Duration(hours: 10, minutes: 45)),
        customerName: 'أحمد محمد',
        status: 'completed',
        depositAmount: deposit,
        depositStatus: 'held',
        serviceId: 1,
        serviceName: 'قصّ شعر',
        servicePrice: 500,
        resourceName: 'محمد علي',
      );

  Future<ProviderContainer> pumpDialog(
    WidgetTester tester, {
    required int bookingId,
    double deposit = 300,
  }) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final container = ProviderContainer(
      overrides: [databaseProvider.overrideWithValue(db)],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Scaffold(
            body: BookingInvoiceDialog(
              row: BookingBoardRow(
                id: bookingId,
                startsAt: row(deposit: deposit).startsAt,
                endsAt: row(deposit: deposit).endsAt,
                customerName: 'أحمد محمد',
                status: 'completed',
                depositAmount: deposit,
                depositStatus: 'held',
                serviceName: 'قصّ شعر',
                servicePrice: 500,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return container;
  }

  group('حوارُ التفويتر يُبنى ويحسب', () {
    testWidgets('يعرض المتبقّي = السعر − العربون', (tester) async {
      await pumpDialog(tester, bookingId: 1);
      expect(tester.takeException(), isNull);
      expect(find.text('المتبقّي على العميل'), findsOneWidget);
      expect(find.textContaining('200'), findsWidgets,
          reason: '٥٠٠ − ٣٠٠ = ٢٠٠ — ولو عُرض ٥٠٠ لَدفع العميلُ عربونَه مرّتين');
    });

    testWidgets('يقول صراحةً إنّ الفاتورةَ تُصدَر من نقطة البيع',
        (tester) async {
      await pumpDialog(tester, bookingId: 1);
      expect(find.textContaining('نقطة البيع'), findsWidgets);
    });
  });

  group('العلامةُ تُرفَع بالنجاح وحدَه', () {
    testWidgets('خدمةٌ بلا صنفٍ مربوطٍ ⇒ خطأٌ ظاهرٌ ولا علامة', (tester) async {
      final bookingId = await db.createBooking(
        customerName: 'أحمد محمد',
        serviceId: serviceId,
        startsAt: DateTime.now().add(const Duration(days: 1)),
        createdBy: 1,
      );
      final container = await pumpDialog(tester, bookingId: bookingId);

      await tester.tap(find.text('متابعة في نقطة البيع'));
      await tester.pumpAndSettle();

      expect(container.read(bookingInvoicingProvider), isNull,
          reason: 'علامةٌ تُرفَع رغم فشل الحارس تلتصق بأوّل بيعةٍ تالية '
              'فتخصم عربوناً من زبونٍ آخر');
      expect(find.textContaining('غير مربوطة بصنف'), findsOneWidget,
          reason: 'السببُ يُسمّى — «فشل» وحدَها لا تُعالَج');
    });

    testWidgets('خدمةٌ مربوطةٌ ⇒ تُرفَع العلامةُ ويُغلَق الحوار',
        (tester) async {
      final productId = await db.into(db.products).insert(
            ProductsCompanion.insert(
              name: 'قصّ شعر',
              code: 'SRV-T',
              productType: const Value('service'),
            ),
          );
      await (db.update(db.bookingServices)
            ..where((s) => s.id.equals(serviceId)))
          .write(BookingServicesCompanion(productId: Value(productId)));

      final bookingId = await db.createBooking(
        customerName: 'أحمد محمد',
        serviceId: serviceId,
        startsAt: DateTime.now().add(const Duration(days: 1)),
        createdBy: 1,
      );
      final container = await pumpDialog(tester, bookingId: bookingId);

      await tester.tap(find.text('متابعة في نقطة البيع'));
      await tester.pumpAndSettle();

      expect(container.read(bookingInvoicingProvider), bookingId,
          reason: 'بلا العلامةِ يبقى العربونُ في الالتزام ويُحاسَب العميلُ '
              'مرّتين');
    });
  });

  group('لوحُ الحجز الجديد يُبنى ويمنع بحقّ', () {
    Future<void> pumpPanel(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            databaseProvider.overrideWithValue(db),
            bookingServicesProvider.overrideWith(
              (ref) => Stream.value([
                BookingService(
                  id: 1,
                  name: 'قصّ شعر',
                  durationMinutes: 45,
                  bufferMinutes: 10,
                  price: 500,
                  colorHex: '#0250D3',
                  isActive: true,
                  sortOrder: 0,
                  createdAt: DateTime(2026, 1, 1),
                ),
              ]),
            ),
            bookingResourcesProvider
                .overrideWith((ref) => Stream.value(const [])),
          ],
          child: MaterialApp(home: Scaffold(body: NewBookingPanel(onDay: day))),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('يُبنى بلا استثناءِ تخطيط', (tester) async {
      await pumpPanel(tester);
      expect(tester.takeException(), isNull);
      expect(find.text('حجز جديد'), findsWidgets);
      expect(find.text('اسم العميل'), findsOneWidget);
    });

    testWidgets('بلا خدمةٍ ⇒ الحفظُ ممنوعٌ ويُقال السبب', (tester) async {
      await pumpPanel(tester);
      expect(find.text('اختر الخدمة'), findsWidgets,
          reason: 'المنعُ يسمّي ما ينقص لا «غير مكتمل»');
      // ‏`PicPosDialog` يبني إجراءَه الأساسيَّ بـ`ElevatedButton.icon`.
      final save = tester.widget<ElevatedButton>(
        find.widgetWithText(ElevatedButton, 'حفظ الحجز'),
      );
      expect(save.onPressed, isNull,
          reason: 'زرٌّ يبدو صالحاً ثمّ يفشل أسوأُ من زرٍّ معطَّل');
    });

    testWidgets('المدّةُ تُعرَض من الخدمة ولا تُكتب', (tester) async {
      await pumpPanel(tester);
      // ‏`DropdownButtonFormField` يبني `DropdownButton<int>` داخليّاً —
      // والنقرُ على نصّ التلميح لا يفتح القائمة.
      await tester.tap(find.byType(DropdownButton<int>).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('قصّ شعر').last);
      await tester.pumpAndSettle();

      expect(find.textContaining('45 دقيقة'), findsOneWidget,
          reason: 'المدّةُ تُخزَّن ولا تُحسَب — وحقلٌ يقبل تحريراً ثمّ '
              'يُتجاهَل أسوأُ من حقلٍ مقفول');
    });
  });
}
