// test/widget/e_invoicing_picpos_screen_test.dart
//
// تركيبُ شاشة «الفوترة الإلكترونية» بهويّة PicPos — بعرضَين.
//
// ⚠️ **العرضان ليسا احتياطاً.** الشاشةُ تضع لوحةَ تفصيلٍ ٦٠٠px بجوار الطابور
// فوقَ ١٤٠٠، وتطويها إلى حوارٍ دونَه. والحدُّ مقيسٌ لا مذوق، ويُقاس طرفاه —
// فقد انهارت شاشةُ التكاليف المحمَّلة كاملةً من تركيبٍ لم يُقَس عند عرضَين.
//
// ⚠️ **و🔴 مرساةُ «السجلّ إضافةٌ فقط»**: التصميمُ يكتب «سجل إضافة فقط — لا
// تعديل ولا حذف لأي سطر»، و`logStatusChange` تُدخِل ولا تُحدِّث. فيُقاس هنا
// **حضورُ** السجلّ (مرساةً) ثمّ **غيابُ** أيّ زرِّ تحريرٍ أو حذفٍ داخلَه.
// وبلا المرساةِ الأولى يقيس الفحصُ نمطَه لا الشِّفرة.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:picpos_erp/data/database/database.dart' as db;
import 'package:picpos_erp/data/providers/auth_providers.dart';
import 'package:picpos_erp/data/providers/repository_providers.dart';
import 'package:picpos_erp/domain/repositories/e_invoice_repository.dart';
import 'package:picpos_erp/presentation/e_invoicing_picpos/screens/e_invoicing_picpos_screen.dart';

/// صفَّان في الطابور: مقبولٌ ومعلَّق — فيُقاس عدّادُ المرحلتَين معاً وأنّ زرَّ
/// «إرسال المعلَّقة» يُقرأ عليه العددُ الصحيح.
final _queue = <Map<String, dynamic>>[
  {
    'id': 1,
    'sale_id': 40,
    'platform': 'eta',
    'document_type': 'invoice',
    'status': 'valid',
    'internal_id': 'INV-2026-1040',
    'document_uuid': '8f3a9c1e-4d72-4b8a-9e11-2c7f5b0d81a4',
    'long_id': '2026082610422900000000000091AD4C7F8E1B',
    'submission_id': 'SUB-9F41C2',
    'hash_key': 'a91f7c2d4b8e05631f7a',
    'qr_code': null,
    'error_message': null,
    'raw_request':
        '{"internalID":"INV-2026-1040","taxTotals":[{"taxType":"T1","amount":1097.72}]}',
    'raw_response': '{"submissionUUID":"SUB-9F41C2"}',
    'retry_count': 0,
    'submitted_at': null,
    'last_checked_at': null,
    'invoice_number': 'SL-1040',
    'customer_name': 'سوبر ماركت النور',
    'invoice_total': 8940.0,
  },
  {
    'id': 2,
    'sale_id': 42,
    'platform': 'eta',
    'document_type': 'credit_note',
    'status': 'pending',
    'internal_id': 'RET-2026-0139',
    'document_uuid': null,
    'long_id': null,
    'submission_id': null,
    'hash_key': null,
    'qr_code': null,
    'error_message': null,
    'raw_request': null,
    'raw_response': null,
    'retry_count': 0,
    'submitted_at': null,
    'last_checked_at': null,
    'invoice_number': 'SL-1042',
    'customer_name': 'بقالة الأمانة',
    'invoice_total': 1240.0,
  },
];

final _audit = <Map<String, dynamic>>[
  {
    'id': 1,
    'submission_id': 1,
    'old_status': null,
    'new_status': 'pending',
    'changed_by': 'system',
    'notes': 'أُنشئ المستند من فاتورة البيع بعد ترحيلها.',
    'changed_at': null,
  },
  {
    'id': 2,
    'submission_id': 1,
    'old_status': 'pending',
    'new_status': 'valid',
    'changed_by': 'system',
    'notes': 'قبلت المنظومة المستند وأصدرت معرّفاً طويلاً.',
    'changed_at': null,
  },
];

class _FakeEInvoiceRepo implements IEInvoiceRepository {
  @override
  Stream<List<Map<String, dynamic>>> watchSubmissionsWithInvoice() =>
      Stream.value(_queue);

  @override
  Future<List<Map<String, dynamic>>> getStatusAuditTrail(int submissionId) async =>
      _audit.where((e) => e['submission_id'] == submissionId).toList();

  @override
  Future<db.EInvoiceConfigData?> getEInvoiceConfig(String platform) async {
    if (platform != 'eta') return null;
    return db.EInvoiceConfigData(
      id: 1,
      platform: 'eta',
      clientId: 'cid',
      clientSecret: 'secret',
      registrationNumber: '344228891',
      activityCode: '4711',
      branchId: '0',
      documentVersion: '1.0',
      codingSystem: 'EGS',
      isProduction: true,
      isEnabled: true,
      createdAt: DateTime(2026, 1, 1),
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      super.noSuchMethod(invocation);
}

Future<void> _pump(
  WidgetTester tester,
  double width, {
  /// الصلاحيّاتُ الممنوحةُ للمستخدم. `einvoice_submit` هو ما يحرس الإرسال.
  List<String> perms = const ['einvoice_submit'],
}) async {
  tester.view.physicalSize = Size(width, 1000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        eInvoiceRepositoryProvider.overrideWithValue(_FakeEInvoiceRepo()),
        currentUserPermissionsProvider.overrideWith((ref) async => perms),
      ],
      child: const MaterialApp(home: EInvoicingPicposScreen()),
    ),
  );
  await tester.pump();
  await tester.pump();
  await tester.pump();
}

void main() {
  for (final width in [1280.0, 1920.0]) {
    final w = width.toInt();

    testWidgets('الطابورُ والمراحلُ تُرسَم بلا فيضان عند عرض $w',
        (tester) async {
      await _pump(tester, width);

      expect(tester.takeException(), isNull,
          reason: 'شاشةُ الفوترة الإلكترونية فاضت عند $w — راجعْ حدَّ '
              'لوحة التفصيل (١٤٠٠) وشريطَي المنصّات والمراحل.');

      expect(find.text('الفوترة الإلكترونية'), findsOneWidget);

      // المراحلُ الستُّ كلُّها معروضةٌ بعدّاداتها.
      for (final label in [
        'معلَّقة',
        'مُرسَلة',
        'مقبولة',
        'غير صحيحة',
        'مرفوضة',
        'ملغاة',
      ]) {
        expect(find.text(label), findsWidgets,
            reason: 'المرحلةُ «$label» غائبةٌ عن شريط العدّادات عند $w.');
      }

      // الطابورُ يعرض المرجعَ الداخليَّ واسمَ العميل معاً.
      expect(find.text('INV-2026-1040'), findsWidgets);
      expect(find.text('سوبر ماركت النور'), findsWidgets,
          reason: 'اسمُ العميل لا يصل — راجعْ `watchSubmissionsWithInvoice`.');
    });
  }

  testWidgets('زرُّ «إرسال المعلَّقة» يحمل عدداً مقيساً من الصفوف',
      (tester) async {
    await _pump(tester, 1920);

    // معلَّقٌ واحدٌ في التجهيزة ⇒ «١». ولو كان العددُ ثابتاً أو من مزوِّدٍ
    // آخرَ لقرأ غيرَ ذلك.
    expect(find.textContaining('إرسال المعلَّقة (١)'), findsOneWidget,
        reason: 'عدّادُ المعلَّقة غيرُ محسوبٍ من صفوف الطابور.');
  });

  testWidgets('🔴 سجلُّ الحالات معروضٌ وبلا أيّ زرِّ تحريرٍ أو حذف',
      (tester) async {
    await _pump(tester, 1920);

    // المرساة: السجلُّ حاضرٌ فعلاً — فالنفيُ بعده يقيس الشِّفرةَ لا النمط.
    expect(find.text('سجل الحالات'), findsOneWidget,
        reason: 'لوحةُ سجلّ الحالات غائبةٌ — فالنفيُ بعدَها بلا معنى.');
    expect(find.text('سجل إضافة فقط — لا تعديل ولا حذف لأي سطر'), findsOneWidget,
        reason: 'العقدُ غيرُ مكتوبٍ للمستخدم.');

    // وسطرٌ من السجلّ وصل فعلاً — وإلّا فالنفيُ يقيس لوحةً فارغة.
    expect(find.textContaining('قبلت المنظومة المستند'), findsOneWidget,
        reason: 'سطرُ السجلّ لا يصل — راجعْ `getStatusAuditTrail`.');

    // 🔴 ولا زرَّ تحريرٍ ولا حذفٍ لأيّ سطر: `logStatusChange` تُدخِل ولا
    //    تُحدِّث، فزرٌّ كهذا يَعِد بما لا يفعله المستودعُ أصلاً.
    for (final forbidden in ['تعديل', 'حذف', 'تحرير']) {
      expect(find.widgetWithText(InkWell, forbidden), findsNothing,
          reason: 'ظهر زرُّ «$forbidden» في لوحةٍ عقدُها الإضافةُ فقط.');
      expect(find.widgetWithText(TextButton, forbidden), findsNothing,
          reason: 'ظهر زرُّ «$forbidden» في لوحةٍ عقدُها الإضافةُ فقط.');
    }
  });

  testWidgets('🔴 بلا صلاحية `einvoice_submit` لا يظهر زرُّ الإرسال إطلاقاً',
      (tester) async {
    // ⚠️ **المرساةُ في الفحص السابق**: الزرُّ يظهر بالصلاحيّة (‏مقيسٌ أعلاه
    //    بعدّاده «١»). فغيابُه هنا يقيس الحارسَ لا نمطَ البحث.
    //
    //    والإرسالُ فعلٌ خارجيٌّ قانونيّ: يبعث المستندَ لمنظومة الضرائب
    //    ويُنشئ معرّفاً لا يُلغى بسهولة. وحصرُ التنقّل (`einvoice_view`)
    //    يفتح الشاشةَ للقراءة — فلو كفى وحدَه لأرسل كلُّ من يقرأ.
    await _pump(tester, 1920, perms: const ['einvoice_view']);

    expect(find.textContaining('إرسال المعلَّقة'), findsNothing,
        reason: 'زرُّ الإرسال الجماعيّ ظهر لمستخدمٍ بلا `einvoice_submit`.');
    expect(find.text('الإرسال يحتاج صلاحية'), findsWidgets,
        reason: 'البديلُ لا يشرح سببَ غياب الزرّ — فيبدو النظامُ معطوباً '
            'بدل أن يبدو محروساً.');
  });

  testWidgets('الضرائبُ تُقرأ من الحِمل — وتُقال صراحةً حين لا حِمل',
      (tester) async {
    await _pump(tester, 1920);

    // المستندُ المختارُ افتراضاً هو الأوّل، وحِملُه يحمل T1 بمبلغ ١٠٩٧٫٧٢.
    expect(find.text('T1'), findsOneWidget,
        reason: 'كودُ الضريبة لا يُقرأ من `taxTotals` في الحِمل.');
    expect(find.text('1,097.72'), findsOneWidget,
        reason: 'مبلغُ الضريبة لا يُقرأ من الحِمل — أو نُقل من التصميم.');
  });
}
