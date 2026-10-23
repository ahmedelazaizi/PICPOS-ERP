// ═══════════════════════════════════════════════════════════════════════════
// رحلةُ المستند الضريبيّ من طرفٍ لطرف — ببوّابةِ ETA وهميّة.
// ═══════════════════════════════════════════════════════════════════════════
//
// ═══ ما تقيسه هذه الرحلة ═══
//
// كلُّ قطعةٍ كانت مُختبَرةً وحدَها: المسحُ · بناءُ الحمولة · القرارُ · العامل.
// ولا واحدٌ منها يقول إنّ **الرحلةَ كلَّها تصل**: فاتورةٌ تُحفَظ ⇒ يمسحها
// الخادمُ ⇒ يبني حمولتَها ⇒ يصادق ⇒ يقدّم ⇒ يعود بمعرّفٍ وQR ⇒ **يُختَم على
// صفِّ التقديم** ⇒ فيقرؤه الكاشيرُ ويطبع الرمزَ الضريبيَّ على الإيصال.
//
// وهي الفجوةُ التي أُغلقت هنا: البوّابةُ وهميّةٌ محقونةٌ عبر `http.Client`
// الذي يقبله `EtaService` أصلاً — بلا شبكةٍ حقيقيّةٍ ولا سرٍّ حقيقيّ.
//
// ⚠️ **والمرساةُ الحاسمة**: الرمزُ الذي يصل الورقةَ هو `qrCode` الذي أصدرته
// البوّابةُ حرفاً بحرف — لا رقمُ الفاتورة ولا نصٌّ مُختلَق. فتُقاس رحلةُ الرمز
// إلى `resolveReceiptQrForSale` في نهاية الملفّ.

import 'dart:convert';

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:picpos_erp/data/database/database.dart';
import 'package:picpos_erp/data/services/receipt_qr_resolver.dart';
import 'package:picpos_erp/domain/models/einvoice_document_status.dart';
import 'package:picpos_erp/domain/models/receipt_qr_decision.dart';
import 'package:picpos_erp/services/e_invoicing/e_invoice_auto_submitter.dart';
import 'package:picpos_erp/services/e_invoicing/e_invoice_service_wrapper.dart';
import 'package:picpos_erp/services/e_invoicing/e_invoice_submission_worker.dart';
import 'package:picpos_erp/services/e_invoicing/eta_service.dart';
import 'package:picpos_erp/services/secure_storage_service.dart';
import 'package:picpos_erp/data/repositories/drift_e_invoice_repository.dart';


void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late int whId;
  late List<String> hitPaths;

  /// حكمُ البوّابة عند الاستطلاع — يُبدَّل لكلّ حالة.
  var gatewayVerdict = 'Valid';

  /// بوّابةُ ETA وهميّة: مصادقةٌ ثمّ قبولُ المستند بمعرّفٍ وQR.
  ///
  /// وتسجّل المساراتِ المطروقة، فيُقاس أنّ الرحلةَ مرّت بالمصادقة فعلاً لا
  /// أنّها قفزت إلى التقديم بمفتاحٍ فارغ.
  MockClient gateway({bool reject = false}) => MockClient((req) async {
        hitPaths.add(req.url.path);

        if (req.url.path.contains('/connect/token')) {
          return http.Response(
              jsonEncode({'access_token': 'tok-123', 'expires_in': 3600}), 200);
        }

        // استطلاعُ حالةِ مستند: GET /documents/<uuid>/raw أو ما شابه.
        if (req.method == 'GET' && req.url.path.contains('/documents/')) {
          return http.Response(
              jsonEncode({'status': gatewayVerdict, 'validationResults': {}}),
              200);
        }

        if (req.url.path.contains('documentsubmissions')) {
          if (reject) {
            return http.Response(
                jsonEncode({
                  'submissionId': null,
                  'acceptedDocuments': [],
                  'rejectedDocuments': [
                    {'internalId': 'INV-E2E-1', 'error': 'حقلٌ ناقص'}
                  ],
                }),
                202);
          }
          return http.Response(
              jsonEncode({
                'submissionId': 'SUB-E2E',
                'acceptedDocuments': [
                  {
                    'uuid': 'DOC-UUID-E2E',
                    'longId': 'LONG-E2E',
                    'internalId': 'INV-E2E-1',
                    'hashKey': 'HASH-E2E',
                  }
                ],
                'rejectedDocuments': [],
              }),
              202);
        }

        return http.Response('{}', 404);
      });

  // ⚠️ **التخزينُ الآمنُ قناةٌ منصّيّة** — وبلا وهميٍّ لها يرمي
  //    `MissingPluginException`، فيبتلعه `submitSaleInvoice` في `catch`
  //    ويعود بلا أثر: صفرُ نداءٍ شبكيٍّ وصفرُ خطأٍ ظاهر. وهو أوّلُ ما أمسكه
  //    هذا الاختبارُ فعلاً. و`null` تعني «لا سرَّ في الخزنة» فيُقرأ من
  //    الإعداد — نفسُ مسار المستودع الحقيقيّ.
  const secureChannel =
      MethodChannel('plugins.it_nomads.com/flutter_secure_storage');

  setUp(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureChannel, (call) async {
      if (call.method == 'readAll') return <String, String>{};
      return null;
    });

    hitPaths = <String>[];
    gatewayVerdict = 'Valid';
    db = AppDatabase.forTesting();
    await db.saveEInvoiceConfig(
      platform: 'eta',
      clientId: 'cid',
      clientSecret: 'secret',
      registrationNumber: '100-200-300',
      isEnabled: true,
    );

    final branchId = await db.into(db.branches).insert(
        BranchesCompanion.insert(name: 'ف', globalId: const Value('br-e2e')));
    whId = await db.into(db.warehouses).insert(WarehousesCompanion.insert(
        name: 'م', branchId: Value(branchId), globalId: const Value('wh-e2e')));
  });

  tearDown(() => db.close());

  Future<int> seedSale() async {
    final productId = await db.into(db.products).insert(
        ProductsCompanion.insert(
            code: 'P-E2E', name: 'صنف', taxRate: const Value(14)));
    final saleId = await db.into(db.salesInvoices).insert(
        SalesInvoicesCompanion.insert(
      invoiceNumber: 'INV-E2E-1',
      warehouseId: whId,
      userId: 1,
      invoiceDate: DateTime(2026, 9, 1, 10, 30),
      subtotal: const Value(100),
      tax: const Value(14),
      total: const Value(114),
    ));
    await db.into(db.salesInvoiceItems).insert(
        SalesInvoiceItemsCompanion.insert(
      invoiceId: saleId,
      productId: productId,
      quantity: 1,
      unitPrice: 100,
      total: 100,
      taxRate: const Value(14),
      taxAmount: const Value(14),
    ));
    return saleId;
  }

  /// عاملٌ حقيقيٌّ بكلّ طبقاته — والبوّابةُ وحدَها وهميّة.
  ///
  /// [poll] يفصل الاستطلاعَ عن التقديم، فتُقاس **مساهمتُه** وحدَها: بلا
  /// استطلاعٍ يقف المستندُ عند `submitted` ولا رمزَ ضريبيَّ يُطبع.
  EInvoiceSubmissionWorker worker({bool reject = false, bool poll = true}) {
    final repo = DriftEInvoiceRepository(db, SecureStorageService());
    final wrapper = EInvoiceServiceWrapper()
      ..configure(
        platform: EInvoicePlatform.eta,
        etaConfig: const EtaConfig(
          clientId: 'cid',
          clientSecret: 'secret',
          registrationNumber: '100-200-300',
        ),
        httpClient: gateway(reject: reject),
      );
    final submitter = EInvoiceAutoSubmitter(repo: repo, wrapper: wrapper);
    return EInvoiceSubmissionWorker(
      isEnabled: () async => true,
      findDue: ({int limit = 25}) =>
          db.findSalesNeedingEInvoiceSubmission(limit: limit),
      submit: submitter.submitSaleInvoice,
      // ⚠️ عتبةٌ في المستقبل = «استطلعْ كلَّ ما لم يُحسَم الآن». والتباعُدُ
      //    الحقيقيُّ (عشرُ دقائق) مقيسٌ في `einvoice_status_poll_query_test`
      //    — ولا يُقاس هنا لأنّ drift يخزّن الوقتَ بدقّة **الثانية**، فتقديمٌ
      //    واستطلاعٌ في نفس الثانية يتساويان فلا يمرّ `<`.
      findDueStatusChecks: !poll
          ? null
          : ({int limit = 25}) => db.findSubmissionsAwaitingStatus(
              limit: limit,
              notCheckedSince: DateTime.now().add(const Duration(days: 1))),
      checkStatus: !poll ? null : (pair) async {
        final remote = await wrapper.checkStatus(pair.documentUuid);
        final canonical = canonicalEInvoiceStatus(remote.status);
        if (canonical == null) {
          await db.touchSubmissionChecked(pair.submissionId);
          return;
        }
        await db.updateSubmissionStatusWithAudit(pair.submissionId, canonical,
            changedBy: 'server');
      },
    );
  }

  test('مرساة: الفاتورةُ تنتظر تقديماً قبل أن يعمل العامل', () async {
    final saleId = await seedSale();

    expect(await db.findSalesNeedingEInvoiceSubmission(limit: 10),
        contains(saleId));
    expect(await db.getSubmissionBySaleId(saleId), isNull,
        reason: 'وجودُ صفٍّ سلفاً يُبطل كلَّ ما بعده');
  });

  test('🔴 الرحلةُ كاملةً: مسحٌ ⇒ مصادقةٌ ⇒ تقديمٌ ⇒ معرّفٌ وQR على الصفّ',
      () async {
    final saleId = await seedSale();

    final done = await worker(poll: false).runOnce();

    expect(done, 1);
    // مرّت بالمصادقة فعلاً — لا قفزَ إلى التقديم بمفتاحٍ فارغ.
    expect(hitPaths.any((p) => p.contains('/connect/token')), isTrue);
    expect(hitPaths.any((p) => p.contains('documentsubmissions')), isTrue);

    final row = await db.getSubmissionBySaleId(saleId);
    expect(row, isNotNull, reason: 'لا صفَّ تقديمٍ ⇒ الرحلةُ لم تصل');
    expect(row!.documentUuid, 'DOC-UUID-E2E');
    expect(row.submissionId, 'SUB-E2E');
    expect(row.longId, 'LONG-E2E');
    // 🔴 التقديمُ وحدَه يقف عند `submitted` — البوّابةُ قبلت **الاستلام** لا
    //    المستند. وهذا بعينه ما كان يبقى إلى الأبد بلا استطلاع.
    expect(row.status, 'submitted');
  });

  test('🔴 والاستطلاعُ وحدَه ينقله إلى `valid` — وبدونه يقف أبداً', () async {
    final saleId = await seedSale();

    await worker(poll: false).runOnce();
    expect((await db.getSubmissionBySaleId(saleId))!.status, 'submitted',
        reason: 'مرساة: بلا استطلاعٍ لا يتحرّك');

    await worker().runOnce();

    expect((await db.getSubmissionBySaleId(saleId))!.status, 'valid',
        reason: 'الاستطلاعُ هو ما يجلب حكمَ البوّابة — ولا رمزَ ضريبيَّ '
            'يُطبع قبله');
    expect(hitPaths.any((p) => p.contains('/documents/')), isTrue,
        reason: 'لم يُسأل عن المستند أصلاً');
  });

  test('🔴 وحكمٌ مجهولٌ لا يُجمّد المستندَ — يبقى للاستطلاع', () async {
    final saleId = await seedSale();
    await worker(poll: false).runOnce();

    gatewayVerdict = 'SomethingBrandNew';
    await worker().runOnce();

    expect((await db.getSubmissionBySaleId(saleId))!.status, 'submitted',
        reason: 'ترجمةُ المجهول إلى حكمٍ نهائيٍّ تُجمّد المستندَ خطأً');
  });

  test('🔴 ورفضُ البوّابة عند الاستطلاع يُسجَّل', () async {
    final saleId = await seedSale();
    await worker(poll: false).runOnce();

    gatewayVerdict = 'Rejected';
    await worker().runOnce();

    expect((await db.getSubmissionBySaleId(saleId))!.status, 'rejected');
  });

  test('🔴 والحمولةُ المرسَلةُ تحمل بنودَ الفاتورة وتاريخَها الحقيقيّ',
      () async {
    final saleId = await seedSale();
    await worker().runOnce();

    final row = await db.getSubmissionBySaleId(saleId);
    final sent = jsonDecode(row!.rawRequest!) as Map<String, dynamic>;

    expect((sent['items'] as List), hasLength(1),
        reason: 'مستندٌ بلا بنودٍ إقرارٌ خاطئ — وهو ما كانت تبنيه الشاشة');
    expect(sent['issueDate'], startsWith('2026-09-01'),
        reason: 'تاريخُ الفاتورة لا ساعةُ الإرسال');
    expect(((sent['items'] as List).first as Map)['taxRate'], 14.0);
  });

  test('🔴 ثمّ يقرأ الكاشيرُ الرمزَ الضريبيَّ الذي وُلِّد من ردّ البوّابة',
      () async {
    final saleId = await seedSale();
    await worker().runOnce();

    final row = await db.getSubmissionBySaleId(saleId);
    // 🔴 الرمزُ **مولَّدٌ من الردّ** لا مكتوبٌ بيد الاختبار: ETA تشتقّه من
    //    `uuid` و`longId`. فلو سقط أحدُهما لخرج الإيصالُ بلا رمزٍ ضريبيّ.
    expect(row!.qrCode, isNotNull,
        reason: 'الرمزُ يُشتقّ من المعرّفَين — وسقوطُ أحدِهما يُفقده');
    final generatedQr = row.qrCode!;

    // والاعتمادُ من **استطلاع الخادم** لا بيدِ الاختبار.
    expect(row.status, 'valid',
        reason: 'الدورةُ الواحدةُ تقدّم ثمّ تستطلع — فيصل الحكمُ فوراً');

    final qr = await resolveReceiptQrForSale(
      db,
      saleId: saleId,
      sale: ReceiptSaleSummary.fromSale(
        invoiceNumber: 'INV-E2E-1',
        issuedAt: DateTime(2026, 9, 1, 10, 30),
        total: 114,
        companyName: 'شركة',
      ),
    );

    expect(qr.kind, ReceiptQrKind.fiscal);
    expect(qr.payload, generatedQr,
        reason: 'الرمزُ المطبوعُ هو ما وُلِّد من ردّ البوّابة حرفاً بحرف — لا '
            'رقمُ الفاتورة ولا نصٌّ مُختلَق');
    expect(qr.payload, isNot('INV-E2E-1'),
        reason: 'رقمُ الفاتورة كان هو السلوكَ القديم');
    expect(qr.disclaimer, isEmpty);
  });

  test('🔴 ورفضُ البوّابة يُسجَّل ولا يُعدّ نجاحاً', () async {
    final saleId = await seedSale();

    final done = await worker(reject: true).runOnce();

    // العاملُ لم يرمِ، والصفُّ يحمل الإخفاق.
    expect(done, 1, reason: 'المستندُ عولج — والنتيجةُ رفضٌ مُسجَّل');
    final row = await db.getSubmissionBySaleId(saleId);
    expect(row!.status, 'invalid');
    expect(row.documentUuid, isNull);

    // ولا رمزَ ضريبيٌّ يُطبع على مستندٍ مرفوض.
    final qr = await resolveReceiptQrForSale(
      db,
      saleId: saleId,
      sale: ReceiptSaleSummary.fromSale(
        invoiceNumber: 'INV-E2E-1',
        issuedAt: DateTime(2026, 9, 1, 10, 30),
        total: 114,
        companyName: 'شركة',
      ),
    );
    expect(qr.kind, ReceiptQrKind.none,
        reason: 'رمزٌ ضريبيٌّ على مستندٍ رفضته المصلحةُ أسوأُ من لا رمز');
  });

  test('ولا يُقدَّم المستندُ مرّتين — دورةٌ ثانيةٌ لا تجد شيئاً', () async {
    await seedSale();
    final w = worker();

    expect(await w.runOnce(), 1);
    expect(await w.runOnce(), 0,
        reason: 'تقديمٌ ثانٍ يُنتج مستندَين ضريبيَّين لفاتورةٍ واحدة');
  });
}
