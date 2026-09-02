import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../data/database/database.dart';
import '../../data/repositories/drift_e_invoice_repository.dart';
import '../secure_storage_service.dart';
import 'e_invoice_auto_submitter.dart';
import 'e_invoice_service_wrapper.dart';
import 'eta_service.dart';
import 'jofotara_service.dart';

/// عاملُ تقديم الفاتورة الإلكترونيّة — **على الخادم وحدَه**.
///
/// قرارُ المالك 2026-09-02: الخادمُ وحدَه يحمل السرَّ ويرسل؛ الأجهزةُ لا تبلغ
/// البوّابةَ إطلاقاً. وهذا العاملُ هو «يرسل».
///
/// ═══ مِكنسةٌ لا خُطّافُ نداء ═══
///
/// الفواتيرُ تصل الخادمَ **بالمزامنة** من كلّ كاشير، لا بمعالج الـAPI وحدَه.
/// فخُطّافٌ عند مواضع إنشاء الفاتورة كان سيُغفل كلَّ فاتورةٍ جاءت من جهاز —
/// وهي الأغلب. والمِكنسةُ تمسح ما وصل أيّاً كان طريقُه، وتعمل بعد إعادة
/// التشغيل، وتُعيد المحاولةَ بلا حالةٍ في الذاكرة.
///
/// ═══ الاعتماديّاتُ محقونةٌ عمداً ═══
///
/// المسحُ والتقديمُ وفحصُ التفعيل دوالٌّ تُمرَّر، فيُختبَر المنطقُ بلا قاعدةٍ
/// ولا شبكة — وهو ما يجعل «لا يتوقّف بعثرة» قابلاً للقياس أصلاً.
class EInvoiceSubmissionWorker {
  final Future<bool> Function() _isEnabled;
  final Future<List<int>> Function({int limit}) _findDue;
  final Future<void> Function(int saleId) _submit;

  /// مرتجعاتٌ تنتظر إشعارَ ائتمان — كلٌّ مع أصلِه.
  ///
  /// الأصلُ **جزءٌ من العقد** لا زينة: إشعارُ الائتمان يشير إلى فاتورته،
  /// وسقفُ مبلغه منها.
  final Future<List<({int returnSaleId, int originalSaleId})>> Function(
      {int limit})? _findDueCreditNotes;
  final Future<void> Function(({int returnSaleId, int originalSaleId}) pair)?
      _submitCreditNote;

  final int batchSize;

  EInvoiceSubmissionWorker({
    required Future<bool> Function() isEnabled,
    required Future<List<int>> Function({int limit}) findDue,
    required Future<void> Function(int saleId) submit,
    Future<List<({int returnSaleId, int originalSaleId})>> Function({int limit})?
        findDueCreditNotes,
    Future<void> Function(({int returnSaleId, int originalSaleId}) pair)?
        submitCreditNote,
    this.batchSize = 25,
  })  : _isEnabled = isEnabled,
        _findDue = findDue,
        _submit = submit,
        _findDueCreditNotes = findDueCreditNotes,
        _submitCreditNote = submitCreditNote;

  /// يبني العاملَ من القاعدة ويضبط المحرّكَ من الإعداد المحفوظ.
  ///
  /// يُرجع `null` حين لا إعدادَ مُفعَّلاً على أيّ منصّة — فالخادمُ لا يعلّق
  /// نبضةً بلا عمل، والميزةُ تبقى صامتةً حتى تُعَدّ.
  ///
  /// ⚠️ **ولا يُنادى إلّا على الخادم**: هنا يُقرأ `clientSecret`. والعميلُ لا
  /// يملك `EInvoiceConfigs` أصلاً (خارجَ المزامنة بقرار المالك)، فالنداءُ
  /// عليه يُرجع `null` بطبعه — لكنّ الموضعَ الصحيح هو إقلاعُ الخادم.
  static Future<EInvoiceSubmissionWorker?> forServer(AppDatabase db) async {
    // ⚠️ عبر المستودع لا عمودِ القاعدة: `clientSecret` يعيش في **التخزين
    //    الآمن**، والمستودعُ هو الذي يدمجه في الإعداد المقروء. وقراءةُ العمود
    //    مباشرةً كانت ستضبط المحرّكَ بسرٍّ نائبٍ فيُرفَض كلُّ تقديم.
    final repo = DriftEInvoiceRepository(db, SecureStorageService());

    EInvoiceConfigData? config;
    String? platform;
    for (final p in const ['eta', 'jofotara']) {
      final c = await repo.getActiveEInvoiceConfig(p);
      if (c != null && c.isEnabled) {
        config = c;
        platform = p;
        break;
      }
    }
    if (config == null || platform == null) return null;

    final wrapper = EInvoiceServiceWrapper();
    if (platform == 'eta') {
      wrapper.configure(
        platform: EInvoicePlatform.eta,
        etaConfig: EtaConfig(
          clientId: config.clientId,
          clientSecret: config.clientSecret,
          registrationNumber: config.registrationNumber,
          activityCode: config.activityCode,
          isProduction: config.isProduction,
        ),
      );
    } else {
      wrapper.configure(
        platform: EInvoicePlatform.jofotara,
        jofotaraConfig: JofotaraConfig(
          clientId: config.clientId,
          clientSecret: config.clientSecret,
          registrationNumber: config.registrationNumber,
          isProduction: config.isProduction,
        ),
      );
    }

    final submitter = EInvoiceAutoSubmitter(repo: repo, wrapper: wrapper);
    final activePlatform = platform;
    return EInvoiceSubmissionWorker(
      isEnabled: () => submitter.isEnabled,
      findDue: ({int limit = 25}) =>
          db.findSalesNeedingEInvoiceSubmission(limit: limit),
      submit: submitter.submitSaleInvoice,
      findDueCreditNotes: ({int limit = 25}) =>
          db.findReturnsNeedingCreditNoteSubmission(limit: limit),
      submitCreditNote: (pair) => _sendCreditNoteToGateway(
        db: db,
        repo: repo,
        wrapper: wrapper,
        platform: activePlatform,
        pair: pair,
      ),
    );
  }

  /// يقدّم إشعارَ ائتمانٍ لمرتجعٍ واحد.
  ///
  /// ⚠️ **عبر `createCreditNoteSubmission` لا `createSubmission`**: الأولى
  /// وحدَها تفرض السقفَ الضريبيَّ (مبلغُ الإشعار لا يتجاوز الفاتورةَ الأصليّة)
  /// وتضع `documentUuid` الأصلِ مرجعاً. والمسارُ القديم
  /// (`EInvoiceAutoSubmitter.submitCreditNote`) كان ينادي `createSubmission`
  /// مباشرةً — فالسقفُ الذي يسمّيه الكودُ «مخالفةً ضريبيّة» **لا يُبلَغ
  /// أبداً**، ولا مرجعَ للأصل في المستند.
  static Future<void> _sendCreditNoteToGateway({
    required AppDatabase db,
    required DriftEInvoiceRepository repo,
    required EInvoiceServiceWrapper wrapper,
    required String platform,
    required ({int returnSaleId, int originalSaleId}) pair,
  }) async {
    final payload =
        await repo.buildInvoicePayload(pair.returnSaleId, platform);
    payload['documentType'] = 'credit_note';

    // يرمي على المخالف — والعاملُ يحصر ويمضي إلى ما بعده.
    final submissionId = await db.createCreditNoteSubmission(
      returnSaleId: pair.returnSaleId,
      originalSaleId: pair.originalSaleId,
      platform: platform,
      rawRequest: jsonEncode(payload),
    );

    final result =
        await wrapper.submitInvoice(UnifiedInvoice.fromPayload(payload));
    if (result.success) {
      await repo.markSubmissionSuccess(
        submissionId: submissionId,
        submissionUuid: result.submissionId ?? '',
        documentUuid: result.documentUuid,
        longId: result.longId,
        qrCode: result.qrCode,
        rawResponse: result.rawResponse,
      );
    } else {
      await repo.markSubmissionFailed(
        submissionId,
        result.errorMessage ?? 'فشل غير معروف',
        rawResponse: result.rawResponse,
      );
    }
  }

  /// يمسح دفعةً ويقدّمها. يُرجع عددَ ما **نجح** لا ما حوول.
  ///
  /// ولا يرمي أبداً: العاملُ يعمل في خلفيّة خادمٍ حيّ، ورميُه يُسقط ما
  /// يستضيفه.
  Future<int> runOnce() async {
    try {
      if (!await _isEnabled()) return 0;
    } catch (e) {
      debugPrint('[EInvoiceWorker] تعذّر فحصُ التفعيل: $e');
      return 0;
    }

    final List<int> due;
    try {
      due = await _findDue(limit: batchSize);
    } catch (e) {
      debugPrint('[EInvoiceWorker] تعذّر مسحُ الطابور: $e');
      return 0;
    }

    var done = 0;
    for (final saleId in due) {
      // ⚠️ الحصرُ **داخلَ** الحلقة: طابورٌ فيه مستندٌ معطوبٌ كان سيحجب كلَّ
      //    ما بعده إلى الأبد لو خرجنا عند أوّل إخفاق — فلا تصل المصلحةَ
      //    فاتورةٌ واحدة، ولا سببَ ظاهرٌ لأنّ الإخفاقَ يُسجَّل على ذلك
      //    المستند وحدَه.
      try {
        await _submit(saleId);
        done++;
      } catch (e) {
        debugPrint('[EInvoiceWorker] فاتورة #$saleId — إخفاقٌ: $e');
      }
    }

    done += await _sweepCreditNotes();
    return done;
  }

  /// مرتجعاتُ المبيعات — مسارٌ مستقلٌّ لأنّ إشعارَ الائتمان يحتاج أصلَه.
  ///
  /// ومعزولٌ عن مسحِ الفواتير: تعثّرُه لا يُسقط ما قُدِّم منها.
  Future<int> _sweepCreditNotes() async {
    final find = _findDueCreditNotes;
    final send = _submitCreditNote;
    if (find == null || send == null) return 0;

    final List<({int returnSaleId, int originalSaleId})> due;
    try {
      due = await find(limit: batchSize);
    } catch (e) {
      debugPrint('[EInvoiceWorker] تعذّر مسحُ إشعارات الائتمان: $e');
      return 0;
    }

    var done = 0;
    for (final pair in due) {
      try {
        await send(pair);
        done++;
      } catch (e) {
        // السقفُ الضريبيُّ يرمي على المخالف (‏مبلغٌ يتجاوز الأصل) — ولا
        // يوقف الطابور.
        debugPrint(
            '[EInvoiceWorker] مرتجع #${pair.returnSaleId} — إخفاقٌ: $e');
      }
    }
    return done;
  }
}
