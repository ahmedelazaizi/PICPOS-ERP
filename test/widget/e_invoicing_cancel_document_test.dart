// ═══════════════════════════════════════════════════════════════════════════
// إلغاءُ المستند لدى البوّابة — والسببُ المكتوبُ لغيابه كان **باطلاً**.
// ═══════════════════════════════════════════════════════════════════════════
//
// رأسُ الشاشة كان يقول: «الإلغاءُ في المنظومة مسارُ شبكةٍ لا تملكه هذه
// الشاشة (`EInvoiceServiceWrapper` لا يكشف إلغاءً)، فلا يُعرَض زرٌّ يظهر ولا
// يفعل».
//
// وهو **غيرُ صحيح**: `EInvoiceServiceWrapper.cancelDocument` موجودةٌ وتنادي
// `EtaService.cancelDocument` التي تُرسل PUT حقيقيّاً إلى
// `/documents/state/{uuid}/state`. فالقدرةُ مبنيّةٌ ولم تكن مكشوفة.
//
// ═══ وثلاثةُ شروطٍ تحكم الزرَّ ═══
//
// ١) **صلاحيّةُ `einvoice_cancel`** — إلغاءُ مستندٍ ضريبيٍّ معتمَدٍ أثرٌ لا
//    يُعطى لكلّ من يرسل.
// ٢) **اعتمادُ البوّابة على هذا الجهاز** — قرارُ المالك: الأجهزةُ لا تبلغ
//    البوّابة. وكاشيرٌ بلا سرٍّ ينتهي بـ`StateError` مبتلَع.
// ٣) **المستندُ معتمَدٌ (`valid`)** — لا يُلغى ما لم يُقبل: معلَّقٌ أو مرفوضٌ
//    لا شيءَ لدى البوّابة يُلغى.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ural_erp/data/database/database.dart' as db;
import 'package:ural_erp/data/providers/auth_providers.dart';
import 'package:ural_erp/data/providers/repository_providers.dart';
import 'package:ural_erp/domain/repositories/e_invoice_repository.dart';
import 'package:ural_erp/presentation/e_invoicing_picpos/screens/e_invoicing_picpos_screen.dart';

Map<String, dynamic> _row({
  required int id,
  required String status,
  String? documentUuid,
}) =>
    {
      'id': id,
      'sale_id': 40 + id,
      'platform': 'eta',
      'document_type': 'invoice',
      'status': status,
      'internal_id': 'INV-$id',
      'document_uuid': documentUuid,
      'long_id': 'LONG-$id',
      'submission_id': 'SUB-$id',
      'hash_key': null,
      'qr_code': null,
      'error_message': null,
      'raw_request': null,
      'raw_response': null,
      'retry_count': 0,
      'submitted_at': null,
      'last_checked_at': null,
      'invoice_number': 'SL-$id',
      'customer_name': 'عميل $id',
      'invoice_total': 100.0,
    };

class _Repo implements IEInvoiceRepository {
  _Repo({required this.rows, required this.withConfig});

  final List<Map<String, dynamic>> rows;
  final bool withConfig;

  @override
  Stream<List<Map<String, dynamic>>> watchSubmissionsWithInvoice() =>
      Stream.value(rows);

  @override
  Stream<List<db.EInvoiceSubmissionData>> watchSubmissions({
    String? status,
    String? platform,
  }) =>
      Stream.value(const []);

  @override
  Future<db.EInvoiceConfigData?> getActiveEInvoiceConfig(String p) =>
      getEInvoiceConfig(p);

  @override
  Future<db.EInvoiceConfigData?> getEInvoiceConfig(String platform) async {
    if (!withConfig || platform != 'eta') return null;
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
  Future<List<Map<String, dynamic>>> getStatusAuditTrail(int id) async =>
      const [];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> _pump(
  WidgetTester tester, {
  required List<Map<String, dynamic>> rows,
  bool withConfig = true,
  List<String> perms = const ['einvoice_submit', 'einvoice_cancel'],
}) async {
  tester.view.physicalSize = const Size(1920, 1400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        eInvoiceRepositoryProvider
            .overrideWithValue(_Repo(rows: rows, withConfig: withConfig)),
        currentUserPermissionsProvider.overrideWith((ref) async => perms),
      ],
      child: const MaterialApp(home: EInvoicingPicposScreen()),
    ),
  );
  await tester.pump();
  await tester.pump();
  await tester.pump();
}

final _accepted = [_row(id: 1, status: 'valid', documentUuid: 'DOC-1')];

void main() {
  testWidgets('مرساة: المستندُ المعتمَدُ يصل الشاشةَ فعلاً', (tester) async {
    await _pump(tester, rows: _accepted);

    expect(find.text('SL-1'), findsWidgets,
        reason: 'بلا صفٍّ لا معنى للتوكيد على أزراره');
  });

  testWidgets('🔴 زرُّ الإلغاء معروضٌ لمستندٍ معتمَدٍ بصلاحيّةٍ واعتماد',
      (tester) async {
    await _pump(tester, rows: _accepted);

    expect(find.widgetWithText(OutlinedButton, 'إلغاء المستند'), findsWidgets,
        reason: 'القدرةُ مبنيّةٌ في `cancelDocument` ولم تكن مكشوفة');
  });

  testWidgets('🔴 ومحجوبٌ بلا صلاحيّة `einvoice_cancel`', (tester) async {
    await _pump(tester, rows: _accepted, perms: const ['einvoice_submit']);

    expect(find.widgetWithText(OutlinedButton, 'إلغاء المستند'), findsNothing,
        reason: 'صلاحيّةُ الإرسال لا تعطي حقَّ إلغاء مستندٍ معتمَد');
  });

  testWidgets('🔴 ومحجوبٌ على جهازٍ لا يملك اعتمادَ البوّابة', (tester) async {
    await _pump(tester, rows: _accepted, withConfig: false);

    expect(find.widgetWithText(OutlinedButton, 'إلغاء المستند'), findsNothing,
        reason: 'الأجهزةُ لا تبلغ البوّابة — والزرُّ هنا ينتهي بـStateError '
            'مبتلَع');
  });

  testWidgets('🔴 ولا يُعرَض لمستندٍ لم يُقبل بعد', (tester) async {
    await _pump(tester, rows: [_row(id: 2, status: 'pending')]);

    expect(find.widgetWithText(OutlinedButton, 'إلغاء المستند'), findsNothing,
        reason: 'لا شيءَ لدى البوّابة يُلغى قبل القبول');
  });

  testWidgets('ولا لمستندٍ مرفوض', (tester) async {
    await _pump(tester,
        rows: [_row(id: 3, status: 'rejected', documentUuid: 'DOC-3')]);

    expect(find.widgetWithText(OutlinedButton, 'إلغاء المستند'), findsNothing);
  });
}
