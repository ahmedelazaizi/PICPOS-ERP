// لوحةُ الحجوزات — **تركيبُها** لا قطعُها.
//
// ═══ ⚠️ لماذا تُبنى الشاشةُ كاملةً هنا ═══
//
// شاشةُ الخزينة شُحنت **بيضاء** وكلُّ اختبارات ودجتاتها خضراء: العطبُ لم يكن
// في أيّ ودجت بل في **تركيبها** (`stretch` جوّه `Column` يطلب ارتفاعاً لا
// نهائيّاً). وفي بناء الإصدار لا تظهر شاشةٌ حمراءُ بل بياض — فلا يُلاحَظ.
//
// فهذه الاختباراتُ تضخّ `BookingsPicPosScreen` نفسَها داخلَ `MaterialApp`
// وتتحقّق أنّ الشجرةَ بُنيت بلا استثناء، ثمّ تقرأ نصّاً حقيقيّاً منها.
//
// ولا قاعدةَ بيانات: يُبدَّل `bookingsBoardProvider` بمجرىً ثابت. فلا
// `db.close()` ولا مؤقّتُ drift معلَّقٌ في المنطقة الوهميّة.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/data/providers/providers.dart';
import 'package:picpos_erp/domain/models/picpos_booking_view.dart';
import 'package:picpos_erp/presentation/bookings_picpos/screens/bookings_picpos_screen.dart';
import 'package:picpos_erp/presentation/bookings_picpos/widgets/bookings_settings_view.dart';

const _allBookingPerms = <String>[
  'bookings_view',
  'bookings_reports',
  'bookings_settings',
];

void main() {
  final day = DateTime(2026, 9, 1);

  BookingBoardRow row({
    int id = 1,
    String customer = 'أحمد محمد',
    String? phone = '0791234567',
    String status = 'confirmed',
    double deposit = 0,
    String? resource = 'محمد علي',
    int? resourceId = 1,
    int? invoiceId,
    int hour = 10,
    double price = 120,
  }) =>
      BookingBoardRow(
        id: id,
        startsAt: day.add(Duration(hours: hour)),
        endsAt: day.add(Duration(hours: hour, minutes: 45)),
        customerName: customer,
        customerPhone: phone,
        status: status,
        depositAmount: deposit,
        depositStatus: 'held',
        serviceName: 'قصّ شعر',
        servicePrice: price,
        resourceId: resource == null ? null : resourceId,
        resourceName: resource,
        resourceRole: 'حلاق أول',
        invoiceId: invoiceId,
      );

  Future<void> pump(
    WidgetTester tester,
    List<BookingBoardRow> rows, {
    Size size = const Size(1920, 1080),
    List<String> perms = _allBookingPerms,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          // الوجهتان `التقارير`/`الإعدادات` تُخفيان حتى تصل صلاحياتُ المستخدم
          // (بوّاباتُ الحجوزات)؛ فالتجهيزةُ تمنح الأكواد صراحةً. تجاوزٌ متزامن
          // كي لا يبقى المزوّد loading.
          currentUserPermissionsProvider.overrideWith((ref) => perms),
          bookingsBoardProvider.overrideWith((ref) => Stream.value(rows)),
          bookingBoardDayProvider.overrideWith(() => _FixedDay(day)),
          // ⚠️ لا بدّ من تبديل هذين أيضاً: بلا قاعدةٍ يبقيان `loading` أبداً،
          // فتدور دائرةُ الانتظار بلا نهايةٍ و`pumpAndSettle` تنتهي بمهلة —
          // عطلٌ في التجهيزة يُقرأ عطلاً في الشاشة.
          bookingResourcesProvider
              .overrideWith((ref) => Stream.value([_resource()])),
          bookingServicesProvider
              .overrideWith((ref) => Stream.value([_service()])),
          bookingCustomersProvider.overrideWith((ref) => Stream.value([
                const BookingCustomerRow(
                  name: 'سارة محمود',
                  phone: '0798765432',
                  visits: 26,
                  spend: 18450,
                  favouriteService: 'صبغة شعر',
                ),
              ])),
          bookingRemindersProvider.overrideWith((ref) => Stream.value([
                BookingReminderRow(
                  id: 1,
                  bookingId: 1,
                  customerName: 'خالد يوسف',
                  customerPhone: '0791112233',
                  serviceName: 'جلسة ليزر',
                  bookingStartsAt: day.add(const Duration(hours: 17)),
                  scheduledAt: day.add(const Duration(hours: 16)),
                  channel: 'whatsapp',
                  state: 'scheduled',
                  offsetMinutes: 60,
                ),
              ])),
          bookingReminderOffsetProvider.overrideWith((ref) async => 60),
        ],
        child: const MaterialApp(home: BookingsPicPosScreen()),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('الشاشةُ تُبنى — لا بياضَ ولا استثناء', () {
    testWidgets('بصفوفٍ: العنوانُ والأعمدةُ والصفُّ كلُّها حاضرة',
        (tester) async {
      await pump(tester, [row()]);

      expect(tester.takeException(), isNull,
          reason: 'استثناءُ تخطيطٍ هنا يعني شاشةً بيضاءَ في الإصدار');
      expect(find.text('الحجوزات'), findsOneWidget);
      expect(find.text('الوقت'), findsOneWidget);
      expect(find.text('الإجراءات'), findsOneWidget);
      expect(find.text('أحمد محمد'), findsOneWidget);
      expect(find.text('قصّ شعر'), findsOneWidget);
    });

    testWidgets('بلا صفوفٍ: حالةٌ فارغةٌ تشرح ولا تكذب', (tester) async {
      await pump(tester, const []);
      expect(tester.takeException(), isNull);
      expect(find.textContaining('لا حجوزات'), findsOneWidget);
    });

    // ⚠️ الفيضُ الذي أمسكه هذا الملفُّ أوّلَ مرّةٍ كان **مستقلّاً عن عرض
    // الشاشة** (‏4.8 بكسل عند ١٦٠٠ و١٩٢٠ سواءً) — خليّةٌ ثابتةُ العرض لا
    // حسابُ أعمدة. فيُقاس العرضانِ معاً: أحدُهما وحدَه لا يفرّق بين
    // السببين، والتشخيصُ الخاطئُ كان سيُوسّع الأعمدةَ بلا فائدة.
    testWidgets('على شاشةٍ أضيق (١٢٨٠) لا يفيض شيء', (tester) async {
      await pump(tester, [row()], size: const Size(1280, 800));
      expect(tester.takeException(), isNull);
      expect(find.text('أحمد محمد'), findsOneWidget);
    });
  });

  group('العدّاداتُ تُحسب من نفس الصفوف المعروضة', () {
    testWidgets('العدُّ يطابق طولَ القائمة', (tester) async {
      await pump(tester, [row(id: 1), row(id: 2, hour: 11), row(id: 3, hour: 12)]);
      expect(find.text('حجوزات اليوم'), findsOneWidget);
      expect(find.text('3'), findsWidgets,
          reason: 'رقمٌ يخالف الجدولَ تحته أسوأُ من غياب الرقم');
    });

    testWidgets('«لم يحضر» يُعَدّ ولا يدخل الإيراد المتوقّع', (tester) async {
      await pump(tester, [
        row(id: 1, status: 'no_show', price: 500),
        row(id: 2, hour: 11, status: 'confirmed', price: 100),
      ]);
      expect(find.text('لم يحضر'), findsWidgets);
      // الإيرادُ المتوقَّعُ = ١٠٠ وحدَها؛ ٥٠٠ ملغاةٌ بحكم `occupiesTime`.
      expect(find.textContaining('100.'), findsWidgets);
      expect(find.textContaining('600.'), findsNothing,
          reason: 'مَن لم يحضر لا يُتوقَّع إيرادُه');
    });
  });

  group('الحالةُ والفعلُ يُعرضان بحقّهما', () {
    testWidgets('«مكتمل» له تسميةٌ ولا يُرسم فارغاً', (tester) async {
      await pump(tester, [row(status: 'completed')]);
      expect(find.text('مكتمل'), findsOneWidget,
          reason: 'التصميمُ لا يسمّيها والقيدُ يقبلها — فبلا تسميةٍ تُرسم فراغاً');
      expect(find.text('تفويتر'), findsOneWidget);
    });

    testWidgets('المفوتَرُ لا يعرض «تفويتر» بل شارةَ إتمام', (tester) async {
      await pump(tester, [row(status: 'completed', invoiceId: 7)]);
      expect(find.text('تفويتر'), findsNothing,
          reason: 'تفويترٌ ثانٍ يُطبّق العربونَ مرّتين');
      expect(find.text('مُفوتَر'), findsOneWidget);
    });

    testWidgets('السلسلةُ تعرض فعلَها الصحيح', (tester) async {
      await pump(tester, [row(status: 'pending')]);
      expect(find.text('تأكيد'), findsOneWidget);
    });
  });

  group('حجزٌ بلا موظَّفٍ يظهر ويُقال عنه', () {
    testWidgets('«بلا إسناد» بدل فراغ', (tester) async {
      await pump(tester, [row(resource: null)]);
      expect(tester.takeException(), isNull);
      expect(find.text('بلا إسناد'), findsOneWidget);
    });
  });

  group('الوجهاتُ تتبدّل ولا تنهار', () {
    testWidgets('كلُّ وجهةٍ تُفتَح بلا استثناءِ تخطيط', (tester) async {
      await pump(tester, [row(), row(id: 2, hour: 11, resource: null)]);

      // ⚠️ ولا يكفي «لم تنهر»: وجهةٌ تُفتَح فارغةً تمرّ بذلك الشرط وحدَه.
      // فلكلِّ وجهةٍ نصٌّ **من محتواها هي** يُقاس حضورُه.
      const marker = <BookingsDestination, String>{
        BookingsDestination.board: 'الإجراءات',
        BookingsDestination.waitlist: 'الخدمة المطلوبة',
        BookingsDestination.resources: 'حجوزات اليوم',
        BookingsDestination.services: 'المدة',
        BookingsDestination.customers: 'الخدمة المفضلة',
        BookingsDestination.reminders: 'موعد الحجز',
        BookingsDestination.reports: 'الخدماتُ الأعلى إيراداً',
        BookingsDestination.settings: 'مهلة التذكير الافتراضية',
      };

      for (final d in BookingsDestination.values) {
        await tester.tap(find.text(d.label));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull,
            reason: 'وجهةُ «${d.label}» تنهار عند فتحها');
        expect(find.text(marker[d]!), findsWidgets,
            reason: 'وجهةُ «${d.label}» فُتحت بلا محتواها — و«لم تنهر» وحدَها '
                'تمرّ على وجهةٍ فارغة');
      }
    });

    testWidgets('بلا bookings_reports/settings: تبويباهما لا يظهران',
        (tester) async {
      await pump(tester, [row()], perms: const ['bookings_view']);

      expect(find.text(BookingsDestination.board.label), findsWidgets);
      expect(find.text(BookingsDestination.reports.label), findsNothing,
          reason: 'مستخدمٌ بلا bookings_reports يرى تبويبَ التقارير');
      expect(find.text(BookingsDestination.settings.label), findsNothing);
    });

    testWidgets('يملك bookings_reports وحده: التقارير تظهر والإعدادات لا',
        (tester) async {
      await pump(tester, [row()],
          perms: const ['bookings_view', 'bookings_reports']);

      expect(find.text(BookingsDestination.reports.label), findsOneWidget);
      expect(find.text(BookingsDestination.settings.label), findsNothing);
    });

    testWidgets('قائمةُ الانتظارِ تعرض غيرَ المُسنَدين وحدَهم',
        (tester) async {
      await pump(tester, [
        row(customer: 'مُسنَد'),
        row(id: 2, hour: 11, customer: 'منتظِر', resource: null),
      ]);
      await tester.tap(find.text('قائمة الانتظار'));
      await tester.pumpAndSettle();

      expect(find.text('منتظِر'), findsOneWidget);
      expect(find.text('مُسنَد'), findsNothing,
          reason: 'المُسنَدُ ليس منتظِراً — وخلطُهما يُفقد القائمةَ معناها');
    });

    testWidgets('البحثُ يمسّ اللوحةَ فعلاً', (tester) async {
      await pump(tester, [
        row(customer: 'أحمد محمد'),
        row(id: 2, hour: 11, customer: 'سارة محمود'),
      ]);
      await tester.enterText(find.byType(TextField).first, 'سارة');
      await tester.pumpAndSettle();

      expect(find.text('سارة محمود'), findsOneWidget);
      expect(find.text('أحمد محمد'), findsNothing,
          reason: 'مربعُ بحثٍ لا يُرشِّح أسوأُ من غيابه');
    });
  });
}

class _FixedDay extends BookingBoardDayNotifier {
  _FixedDay(this._day);
  final DateTime _day;
  @override
  DateTime build() => _day;
}

BookingResource _resource() => BookingResource(
      id: 1,
      name: 'محمد علي',
      colorHex: '#0250D3',
      role: 'حلاق أول',
      kind: 'staff',
      shiftStartMinutes: 600, // 10:00 ص
      shiftEndMinutes: 1200, // 08:00 م
      isActive: true,
      sortOrder: 0,
      createdAt: DateTime(2026, 1, 1),
      rowVersion: 0, // v167
    );

BookingService _service() => BookingService(
      id: 1,
      name: 'قصّ شعر',
      durationMinutes: 45,
      bufferMinutes: 10,
      price: 120,
      colorHex: '#0250D3',
      isActive: true,
      sortOrder: 0,
      createdAt: DateTime(2026, 1, 1),
      rowVersion: 0, // v167
    );
