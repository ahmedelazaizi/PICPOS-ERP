// ═══════════════════════════════════════════════════════════════════════════
// جهازُ الكاشير لا يرسل إلى البوّابة — والزرُّ يقول ذلك بدل أن يفشل صامتاً.
// ═══════════════════════════════════════════════════════════════════════════
//
// قرارُ المالك: الخادمُ وحدَه يحمل السرَّ ويرسل. و`EInvoiceConfigs` خارجَ
// المزامنة، فجهازُ الكاشير لا يملك إعداداً أصلاً ⇒ `EInvoiceServiceWrapper`
// غيرُ مضبوطٍ ⇒ كلُّ «إرسال الآن» ينتهي بـ`StateError: not configured`
// **مبتلَعاً في `catch`** ثمّ يُوسَم المستندُ «فاشلاً» بخطأٍ لا يفهمه أحد.
//
// وهذا يخالف مبدأً مكتوباً في رأس الشاشة نفسِها: «زرٌّ يظهر ولا يفعل أسوأُ من
// زرٍّ غائب». فالزرُّ يُعطَّل ويُقال السبب.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ural_erp/data/database/database.dart' as db;
import 'package:ural_erp/data/providers/auth_providers.dart';
import 'package:ural_erp/data/providers/repository_providers.dart';
import 'package:ural_erp/domain/repositories/e_invoice_repository.dart';
import 'package:ural_erp/presentation/e_invoicing_picpos/screens/e_invoicing_picpos_screen.dart';

final _queue = <Map<String, dynamic>>[
  {
    'id': 2,
    'sale_id': 42,
    'platform': 'eta',
    'document_type': 'invoice',
    'status': 'pending',
    'internal_id': 'RET-1',
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

/// مستودعُ **جهازِ كاشير**: طابورٌ يصله بالمزامنة، ولا إعدادَ عنده إطلاقاً.
class _ClientRepo implements IEInvoiceRepository {
  @override
  Stream<List<Map<String, dynamic>>> watchSubmissionsWithInvoice() =>
      Stream.value(_queue);

  @override
  Stream<List<db.EInvoiceSubmissionData>> watchSubmissions({
    String? status,
    String? platform,
  }) =>
      Stream.value(const []);

  // 🔴 لبُّ الحالة: لا إعدادَ على الجهاز — الجدولُ خارجَ المزامنة.
  @override
  Future<db.EInvoiceConfigData?> getEInvoiceConfig(String platform) async =>
      null;

  @override
  Future<db.EInvoiceConfigData?> getActiveEInvoiceConfig(String p) async => null;

  @override
  Future<List<Map<String, dynamic>>> getStatusAuditTrail(int id) async =>
      const [];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> _pump(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1920, 1400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        eInvoiceRepositoryProvider.overrideWithValue(_ClientRepo()),
        currentUserPermissionsProvider
            .overrideWith((ref) async => const ['einvoice_submit']),
      ],
      child: const MaterialApp(home: EInvoicingPicposScreen()),
    ),
  );
  await tester.pump();
  await tester.pump();
  await tester.pump();
}

void main() {
  testWidgets('مرساة: الطابورُ يصل الجهازَ فعلاً', (tester) async {
    await _pump(tester);

    expect(find.text('SL-1042'), findsWidgets,
        reason: 'بلا صفٍّ في الطابور لا معنى للتوكيد على أزراره');
  });

  testWidgets('🔴 زرُّ الإرسال معطَّلٌ على جهازٍ لا يملك اعتماد البوّابة',
      (tester) async {
    await _pump(tester);

    final send = find.widgetWithText(FilledButton, 'إرسال الآن');
    if (send.evaluate().isNotEmpty) {
      expect(tester.widget<FilledButton>(send.first).onPressed, isNull,
          reason: 'زرٌّ فعّالٌ هنا ينتهي بـStateError مبتلَعٍ ويَسِم المستندَ '
              'فاشلاً بخطأٍ لا يفهمه أحد');
    }
  });

  testWidgets('🔴 ويُقال السببُ صراحةً — الإرسالُ من الخادم', (tester) async {
    await _pump(tester);

    expect(find.textContaining('الخادم'), findsWidgets,
        reason: 'تعطيلٌ بلا سببٍ يبدو عطباً — والمستخدمُ لا يرى قرارَ الكود');
  });
}
