// J3 — «عميل نقدي» في شاشة «فاتورة جديدة» (PicPos): اسمُ العميل لمرّةٍ
// واحدة يُسلَّم قبل الحفظ، و«حفظ كعميل دائم» ينقل الفاتورةَ إلى العميل
// الجديد قبل الحفظ. ولطرفٍ عاديٍّ لا حقولَ ولا اسم.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/domain/models/picpos_invoice_draft.dart';
import 'package:ural_erp/presentation/invoice_form_picpos/picpos_invoice_form.dart';

void main() {
  const parties = [
    PicPosPartyOption(id: 1, name: 'عميل نقدي', isCashParty: true),
    PicPosPartyOption(id: 5, name: 'شركة النيل'),
  ];

  Future<
      ({
        List<int?> saved,
        List<({String? name, String? phone})> oneTime,
        List<String> created,
      })> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final saved = <int?>[];
    final oneTime = <({String? name, String? phone})>[];
    final created = <String>[];
    await tester.pumpWidget(MaterialApp(
      builder: (context, child) =>
          Directionality(textDirection: TextDirection.rtl, child: child!),
      home: Scaffold(
        body: PicPosInvoiceForm(
          kind: PicPosInvoiceKind.sales,
          parties: parties,
          products: const [
            PicPosProductOption(id: 1, name: 'صنف تجريبي', salePrice: 10, costPrice: 6),
          ],
          warehouses: const [PicPosWarehouseOption(id: 2, name: 'المخزن')],
          costCenters: const [],
          systemTaxRate: 0,
          invoiceNumberPreview: 'INV-1',
          initialWarehouseId: 2,
          onCancel: () {},
          onOneTimeCustomerChanged: oneTime.add,
          onSaveAsPermanentCustomer: (context, {required name, phone}) async {
            created.add('$name|$phone');
            return PicPosPartyOption(id: 99, name: name);
          },
          onSave: ({
            required partyId,
            required supplierInvoiceNumber,
            required date,
            required subtotal,
            required discount,
            required tax,
            required net,
            required paid,
            required notes,
            required items,
            required warehouseId,
            required costCenterId,
            required paymentMethod,
            required printAfterSave,
            required sourceOrderId,
          }) async =>
              saved.add(partyId),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    return (saved: saved, oneTime: oneTime, created: created);
  }

  Future<void> pickParty(WidgetTester tester, String name) async {
    await tester.tap(find.text('اختر العميل'));
    await tester.pumpAndSettle();
    await tester.tap(find.text(name).last);
    await tester.pumpAndSettle();
  }

  Future<void> addLineAndSave(WidgetTester tester) async {
    await tester.enterText(find.byKey(quickAddSearchKey), 'صنف تجريبي');
    await tester.tap(find.text('إضافة'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('مراجعة واعتماد'));
    await tester.pumpAndSettle();
  }

  testWidgets('cash customer: the typed name/phone reach the save', (tester) async {
    final r = await pump(tester);
    expect(find.byKey(const Key('picpos_one_time_customer')), findsNothing);
    await pickParty(tester, 'عميل نقدي');
    expect(find.byKey(const Key('picpos_one_time_customer')), findsOneWidget);
    await tester.enterText(find.byKey(const Key('picpos_one_time_name')), ' سليمان ');
    await tester.enterText(find.byKey(const Key('picpos_one_time_phone')), '0791234567');
    await addLineAndSave(tester);
    expect(r.saved, [1]);
    expect(r.oneTime.single, (name: 'سليمان', phone: '0791234567'));
  });

  testWidgets('«حفظ كعميل دائم» switches the invoice to the new customer', (tester) async {
    final r = await pump(tester);
    await pickParty(tester, 'عميل نقدي');
    final button = find.byKey(const Key('picpos_save_permanent_customer'));
    expect(tester.widget<OutlinedButton>(button).onPressed, isNull,
        reason: 'needs a typed name first');
    await tester.enterText(find.byKey(const Key('picpos_one_time_name')), 'محل الوادي');
    await tester.pump();
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(r.created, ['محل الوادي|null']);
    expect(find.byKey(const Key('picpos_one_time_customer')), findsNothing,
        reason: 'the invoice is no longer on the cash customer');
    await addLineAndSave(tester);
    expect(r.saved, [99]);
    expect(r.oneTime.single, (name: null, phone: null));
  });

  testWidgets('an ordinary customer has no one-time name', (tester) async {
    final r = await pump(tester);
    await pickParty(tester, 'شركة النيل');
    expect(find.byKey(const Key('picpos_one_time_customer')), findsNothing);
    await addLineAndSave(tester);
    expect(r.saved, [5]);
    expect(r.oneTime.single, (name: null, phone: null));
  });
}
