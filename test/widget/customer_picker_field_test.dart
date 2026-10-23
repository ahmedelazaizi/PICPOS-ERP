// CustomerPickerField: بحثٌ بـdebounce، أسهم/Enter، بطاقة العميل، الإضافة
// السريعة (تُعيد المعرّف)، وضعُ الضيف و«ترقية»، RTL، والصلاحيات، ومنعُ تكرار
// الهاتف. ولا قاعدةَ بيانات: المزوّداتُ تُستبدَل (فتحُ drift في اختبار ودجت يعلّق).
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/data/providers/customer_picker_providers.dart';
import 'package:ural_erp/data/providers/providers.dart';
import 'package:ural_erp/domain/models/party_reservation_entry.dart';
import 'package:ural_erp/presentation/parties_picpos/dialogs/party_phone_dedupe.dart';
import 'package:ural_erp/presentation/shared_widgets/customer_picker/customer_picker_field.dart';
import 'package:ural_erp/presentation/shared_widgets/customer_picker/customer_picker_value.dart';

Party _party(int id, String name,
        {String? phone = '01000000000',
        double balance = 0,
        double creditLimit = 0,
        bool active = true,
        DateTime? deletedAt}) =>
    Party(
      id: id,
      code: 'C-$id',
      name: name,
      phone: phone,
      address: 'المعادي',
      isCustomer: true,
      isSupplier: false,
      isDeliveryCompany: false,
      isFavorite: false,
      balance: balance,
      creditLimit: creditLimit,
      paymentTermsDays: 0,
      earlyPaymentDiscountPct: 0,
      earlyPaymentDiscountDays: 0,
      fixedDiscount: 0,
      priceLevel: 'default',
      isActive: active,
      deletedAt: deletedAt,
      createdAt: DateTime(2026, 1, 1),
      isGlobal: true,
      isSystemDefault: false,
      rowVersion: 0,
    );

final _all = [
  _party(1, 'سارة أحمد', phone: '01011112222', balance: 150, creditLimit: 100),
  _party(2, 'سامي علي', phone: '01033334444'),
  _party(3, 'خالد', phone: null),
];

class _Harness extends StatefulWidget {
  const _Harness({
    required this.onValue,
    this.initial = CustomerPickerValue.empty,
    this.quickAdd,
    this.width = 420,
  });

  final CustomerPickerValue initial;
  final ValueChanged<CustomerPickerValue> onValue;
  final CustomerQuickAdd? quickAdd;
  final double width;

  @override
  State<_Harness> createState() => _HarnessState();
}

class _HarnessState extends State<_Harness> {
  late CustomerPickerValue v = widget.initial;

  @override
  Widget build(BuildContext context) => MaterialApp(
        // الاتجاهُ داخل `home`: MaterialApp يعيد ضبطَه من اللغة الافتراضيّة.
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(
            body: Align(
              alignment: Alignment.topCenter,
              child: SizedBox(
                width: widget.width,
                child: CustomerPickerField(
                  value: v,
                  quickAdd: widget.quickAdd ??
                      (ctx, ref, {initialName, initialPhone}) async => null,
                  onChanged: (n) {
                    setState(() => v = n);
                    widget.onValue(n);
                  },
                ),
              ),
            ),
          ),
        ),
      );
}

// `Override` غيرُ مُصدَّر من flutter_riverpod 3 — نوعٌ ديناميكيّ (انظر attachments_test_overrides).
dynamic _overrides({
  List<String> perms = const ['customers_view', 'customers_add'],
  List<Party>? phoneMatches,
  Map<int, Party>? byId,
}) =>
    [
      currentUserPermissionsProvider.overrideWith((ref) async => perms),
      customerPickerSearchProvider.overrideWith((ref, q) async => _all
          .where((p) =>
              p.name.contains(q) || (p.phone ?? '').contains(q))
          .toList()),
      customersByPhoneProvider
          .overrideWith((ref, phone) async => phoneMatches ?? const []),
      customerPickerPartyProvider.overrideWith((ref, id) async =>
          (byId ?? {for (final p in _all) p.id: p})[id]),
      customerReservationCountProvider.overrideWith((ref, id) async => 2),
      partyReservationsProvider.overrideWith((ref, id) async => [
            PartyReservationEntry(
                kind: 'table',
                id: 1,
                at: DateTime(2026, 5, 1, 19),
                status: 'confirmed',
                place: 'طاولة 3'),
          ]),
    ];

Future<void> _pump(WidgetTester tester, Widget w,
    {dynamic overrides}) async {
  await tester.pumpWidget(
      ProviderScope(overrides: overrides ?? _overrides(), child: w));
  await tester.pumpAndSettle();
}

Future<void> _type(WidgetTester tester, String text) async {
  await tester.enterText(find.byKey(const ValueKey('customer_picker_query')), text);
  await tester.pump(); // قبل انقضاء الـdebounce
}

Future<void> _settleDebounce(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 300));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('debounce: لا نتائج قبل 250ms ثم تظهر المطابقة', (tester) async {
    await _pump(tester, _Harness(onValue: (_) {}));
    await _type(tester, 'سا');
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byKey(const ValueKey('customer_picker_results')), findsNothing);
    await _settleDebounce(tester);
    expect(find.byKey(const ValueKey('customer_result_1')), findsOneWidget);
    expect(find.byKey(const ValueKey('customer_result_2')), findsOneWidget);
    expect(find.byKey(const ValueKey('customer_result_3')), findsNothing);
    // العنصران الثابتان في آخر القائمة.
    expect(find.byKey(const ValueKey('customer_result_new')), findsOneWidget);
    expect(find.byKey(const ValueKey('customer_result_guest')), findsOneWidget);
    expect(find.textContaining('+ عميل جديد: "سا"'), findsOneWidget);
  });

  testWidgets('اختيار عميل ⇒ onChanged بالمعرّف + بطاقة العميل', (tester) async {
    CustomerPickerValue? last;
    await _pump(tester, _Harness(onValue: (v) => last = v));
    await _type(tester, 'سارة');
    await _settleDebounce(tester);
    await tester.tap(find.byKey(const ValueKey('customer_result_1')));
    await tester.pumpAndSettle();

    expect(last, const CustomerPickerValue(
        partyId: 1, name: 'سارة أحمد', phone: '01011112222'));
    final card = find.byKey(const ValueKey('customer_picker_card'));
    expect(card, findsOneWidget);
    expect(find.descendant(of: card, matching: find.text('سارة أحمد')), findsOneWidget);
    expect(find.descendant(of: card, matching: find.text('01011112222')), findsOneWidget);
    expect(find.descendant(of: card, matching: find.text('المعادي')), findsOneWidget);
    expect(find.text('عليه دين'), findsOneWidget);
    expect(find.textContaining('تجاوز الحد الائتماني'), findsOneWidget);
    expect(find.text('الحجوزات: 2'), findsOneWidget);
    expect(find.textContaining('طاولة 3'), findsOneWidget);
    expect(find.byKey(const ValueKey('customer_picker_query')), findsNothing);

    // تغيير العميل يعيد البحث.
    await tester.tap(find.byKey(const ValueKey('customer_picker_clear')));
    await tester.pumpAndSettle();
    expect(last, CustomerPickerValue.empty);
    expect(find.byKey(const ValueKey('customer_picker_query')), findsOneWidget);
  });

  testWidgets('لوحة المفاتيح: السهم ينزل والـEnter يختار المحدَّد', (tester) async {
    CustomerPickerValue? last;
    await _pump(tester, _Harness(onValue: (v) => last = v));
    await tester.tap(find.byKey(const ValueKey('customer_picker_query')));
    await _type(tester, 'سا');
    await _settleDebounce(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();
    expect(last?.partyId, 2, reason: 'العنصر الثاني بعد سهم للأسفل');
  });

  testWidgets('عميل جديد: يمرّر النصَّ ويختار المعرّف المُعاد', (tester) async {
    String? gotName, gotPhone;
    CustomerPickerValue? last;
    await _pump(
      tester,
      _Harness(
        onValue: (v) => last = v,
        quickAdd: (ctx, ref, {initialName, initialPhone}) async {
          gotName = initialName;
          gotPhone = initialPhone;
          return 2;
        },
      ),
    );
    await _type(tester, 'اسم غير موجود');
    await _settleDebounce(tester);
    await tester.tap(find.byKey(const ValueKey('customer_result_new')));
    await tester.pumpAndSettle();
    expect(gotName, 'اسم غير موجود');
    expect(gotPhone, isNull);
    expect(last?.partyId, 2);
    expect(last?.name, 'سامي علي');

    // رقمٌ بدل اسم ⇒ initialPhone.
    await tester.tap(find.byKey(const ValueKey('customer_picker_clear')));
    await tester.pumpAndSettle();
    await _type(tester, '0109998888');
    await _settleDebounce(tester);
    await tester.tap(find.byKey(const ValueKey('customer_result_new')));
    await tester.pumpAndSettle();
    expect(gotPhone, '0109998888');
    expect(gotName, isNull);
  });

  testWidgets('إلغاء الإضافة السريعة لا يغيّر القيمة', (tester) async {
    CustomerPickerValue? last;
    await _pump(
      tester,
      _Harness(
        onValue: (v) => last = v,
        quickAdd: (ctx, ref, {initialName, initialPhone}) async => null,
      ),
    );
    await _type(tester, 'لا شيء');
    await _settleDebounce(tester);
    await tester.tap(find.byKey(const ValueKey('customer_result_new')));
    await tester.pumpAndSettle();
    expect(last, isNull);
    expect(find.byKey(const ValueKey('customer_picker_query')), findsOneWidget);
  });

  testWidgets('ضيف بلا تسجيل: اسمٌ وهاتفٌ نصّاً بلا partyId ثم ترقية', (tester) async {
    CustomerPickerValue? last;
    String? upName, upPhone;
    await _pump(
      tester,
      _Harness(
        onValue: (v) => last = v,
        quickAdd: (ctx, ref, {initialName, initialPhone}) async {
          upName = initialName;
          upPhone = initialPhone;
          return 1;
        },
      ),
    );
    await _type(tester, 'زائر');
    await _settleDebounce(tester);
    await tester.tap(find.byKey(const ValueKey('customer_result_guest')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('customer_guest_name')), findsOneWidget);
    expect(last?.partyId, isNull);
    expect(last?.name, 'زائر');

    await tester.enterText(
        find.byKey(const ValueKey('customer_guest_phone')), '01555556666');
    await tester.pump();
    expect(last, const CustomerPickerValue(name: 'زائر', phone: '01555556666'));
    expect(last!.isGuest, isTrue);

    await tester.tap(find.byKey(const ValueKey('customer_guest_upgrade')));
    await tester.pumpAndSettle();
    expect(upName, 'زائر');
    expect(upPhone, '01555556666');
    expect(last?.partyId, 1, reason: 'الترقية تختار الطرف المُنشأ');
  });

  testWidgets('RTL: زرُّ التغيير على طرف النهاية (يسار) والتخطيط لا يفيض', (tester) async {
    await _pump(
      tester,
      _Harness(
        width: 360,
        initial: const CustomerPickerValue(partyId: 1, name: 'سارة أحمد'),
        onValue: (_) {},
      ),
    );
    expect(tester.takeException(), isNull);
    final clear = tester.getCenter(find.byKey(const ValueKey('customer_picker_clear')));
    final name = tester.getCenter(find.text('سارة أحمد'));
    expect(clear.dx, lessThan(name.dx),
        reason: 'في RTL يقع زرُّ الإزالة يسار الاسم');
  });

  testWidgets('طرفٌ محذوف: «عميل محذوف» واللقطةُ تبقى', (tester) async {
    await _pump(
      tester,
      _Harness(
        initial: const CustomerPickerValue(partyId: 9, name: 'لقطة قديمة'),
        onValue: (_) {},
      ),
      overrides: _overrides(byId: {
        9: _party(9, 'اسم حيّ', active: false, deletedAt: DateTime(2026, 2, 2)),
      }),
    );
    expect(find.text('عميل محذوف'), findsOneWidget);
    expect(find.text('لقطة قديمة'), findsOneWidget);
    expect(find.text('اسم حيّ'), findsNothing);
  });

  testWidgets('بلا customers_add: «عميل جديد» معطَّل ولا يستدعي الإضافة', (tester) async {
    var called = false;
    await _pump(
      tester,
      _Harness(
        onValue: (_) {},
        quickAdd: (ctx, ref, {initialName, initialPhone}) async {
          called = true;
          return 1;
        },
      ),
      overrides: _overrides(perms: const ['customers_view']),
    );
    await _type(tester, 'سا');
    await _settleDebounce(tester);
    await tester.tap(find.byKey(const ValueKey('customer_result_new')),
        warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(called, isFalse);
  });

  testWidgets('بلا customers_view: لا بحث في العملاء — ضيفٌ فقط', (tester) async {
    await _pump(tester, _Harness(onValue: (_) {}),
        overrides: _overrides(perms: const <String>[]));
    expect(find.byKey(const ValueKey('customer_picker_query')), findsNothing);
    expect(find.byKey(const ValueKey('customer_guest_name')), findsOneWidget);
    expect(find.byKey(const ValueKey('customer_guest_back')), findsNothing);
  });

  group('checkPhoneDuplicate', () {
    Future<PhoneDedupeResult?> run(
        WidgetTester tester, List<Party> matches, String tap) async {
      PhoneDedupeResult? result;
      await tester.pumpWidget(ProviderScope(
        overrides: _overrides(phoneMatches: matches),
        child: MaterialApp(
          home: Consumer(
            builder: (ctx, ref, _) => Scaffold(
              body: TextButton(
                onPressed: () async =>
                    result = await checkPhoneDuplicate(ctx, ref, '0101 111 2222'),
                child: const Text('go'),
              ),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();
      if (tap.isNotEmpty) {
        await tester.tap(find.byKey(ValueKey(tap)));
        await tester.pumpAndSettle();
      }
      return result;
    }

    testWidgets('لا تطابق ⇒ يتابع بلا حوار', (tester) async {
      final r = await run(tester, const [], '');
      expect(r?.cancelled, isFalse);
      expect(r?.existingId, isNull);
      expect(find.byType(AlertDialog), findsNothing);
    });

    testWidgets('تطابق ⇒ «هذا الرقم مسجَّل باسم X» والاستخدام يعيد المعرّف', (tester) async {
      final r = await run(tester, [_all.first], 'use_existing_1');
      expect(r?.existingId, 1);
    });

    testWidgets('«إنشاء على أي حال» يتابع بلا معرّف', (tester) async {
      final r = await run(tester, [_all.first], 'create_anyway');
      expect(r?.cancelled, isFalse);
      expect(r?.existingId, isNull);
    });

    testWidgets('نصُّ العنوان يسمّي العميل الموجود', (tester) async {
      await run(tester, [_all.first], '');
      expect(find.textContaining('هذا الرقم مسجَّل باسم سارة أحمد'), findsOneWidget);
    });
  });
}
