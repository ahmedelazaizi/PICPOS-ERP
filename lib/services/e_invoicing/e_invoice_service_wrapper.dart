import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'eta_service.dart';
import 'jofotara_service.dart';

// ═══════════════════════════════════════════════════════════════════════════
// UNIFIED E-INVOICE SERVICE WRAPPER — طبقة التوحيد
// ═══════════════════════════════════════════════════════════════════════════

/// Supported e-invoicing platforms
enum EInvoicePlatform { eta, jofotara }

/// Unified submission result (platform-agnostic)
class UnifiedSubmissionResult {
  final bool success;
  final EInvoicePlatform platform;
  final String? submissionId;
  final String? documentUuid;

  /// المعرّفُ الطويلُ من ETA — وهو ما يُشتقّ منه الـQR.
  ///
  /// ⚠️ كان **يسقط هنا**: الغلافُ يولّد الـQR منه ثمّ يهمله، فعمودُ
  /// `e_invoice_submissions.long_id` يبقى فارغاً أبداً — والشاشةُ تعرضه
  /// «—» على كلّ مستندٍ مقبول.
  final String? longId;
  final String? qrCode;
  final String? errorMessage;
  final String? rawResponse;

  UnifiedSubmissionResult({
    required this.success,
    required this.platform,
    this.submissionId,
    this.documentUuid,
    this.longId,
    this.qrCode,
    this.errorMessage,
    this.rawResponse,
  });
}

/// Unified document status
class UnifiedDocumentStatus {
  final String status;
  final EInvoicePlatform platform;
  final List<Map<String, dynamic>> errors;

  UnifiedDocumentStatus({
    required this.status,
    required this.platform,
    this.errors = const [],
  });

  bool get isValid =>
      status.toLowerCase() == 'valid' || status.toLowerCase() == 'accepted';
  bool get isRejected =>
      status.toLowerCase() == 'rejected' || status.toLowerCase() == 'invalid';
  bool get isPending =>
      status.toLowerCase() == 'pending' || status.toLowerCase() == 'submitted';
}

/// Unified line item for cross-platform invoicing
class UnifiedLineItem {
  final String description;
  final String itemCode;
  final String itemCodeType; // 'EGS', 'GPC', 'GS1'
  final String unitType;
  final double quantity;
  final double unitPrice;
  final double discount;
  final String taxType; // T1, T2, etc.
  final String taxSubtype; // V009, etc.
  final double taxRate;

  const UnifiedLineItem({
    required this.description,
    required this.itemCode,
    this.itemCodeType = 'EGS',
    this.unitType = 'EA',
    required this.quantity,
    required this.unitPrice,
    this.discount = 0,
    this.taxType = 'T1',
    this.taxSubtype = 'V009',
    required this.taxRate,
  });

  double get netAmount => (quantity * unitPrice) - discount;
  double get taxAmount => netAmount * taxRate / 100;
  double get totalAmount => netAmount + taxAmount;

  Map<String, dynamic> toMap() => {
    'description': description,
    'itemCode': itemCode,
    'itemType': itemCodeType,
    'unitType': unitType,
    'quantity': quantity,
    'unitPrice': unitPrice,
    'discount': discount,
    'taxType': taxType,
    'taxSubtype': taxSubtype,
    'taxRate': taxRate,
  };
}

/// Unified invoice model — platform-agnostic
class UnifiedInvoice {
  final String internalId;
  final String
  invoiceType; // 'invoice', 'credit_note', 'debit_note', 'export', 'receipt'
  final String? documentVersion; // '0.9' or '1.0' (ETA only)
  final DateTime issueDate;
  final Map<String, dynamic> seller;
  final Map<String, dynamic>? buyer;
  final List<UnifiedLineItem> items;
  final String? paymentMethod;
  final String? originalInvoiceId; // For credit/debit notes

  UnifiedInvoice({
    required this.internalId,
    this.invoiceType = 'invoice',
    this.documentVersion,
    required this.issueDate,
    required this.seller,
    this.buyer,
    required this.items,
    this.paymentMethod,
    this.originalInvoiceId,
  });

  /// من حمولة `buildInvoicePayload` — **المصنعُ الوحيد**.
  ///
  /// كان كلُّ منادٍ يبني المستندَ بيده، فبنته الشاشةُ في موضعَين
  /// `items: []` و`issueDate: DateTime.now()` بعد أن جلبت الحمولةَ الصحيحةَ
  /// ورمتها: مستندٌ بلا بنودٍ وبتاريخ اليوم يصل مصلحةَ الضرائب عن فاتورةٍ
  /// حُرِّرت أمس. إقرارٌ خاطئ، لا إخفاقُ إرسال.
  ///
  /// والقراءةُ **متساهلةٌ في النوع**: الحمولةُ تُخزَّن نصّاً في `rawRequest`،
  /// فمسارُ إعادةِ محاولةٍ يقرؤها مفكوكةً من JSON بقوائمَ `List<dynamic>` —
  /// وقالبٌ صارمٌ كان يرمي استثناءً يبتلعه `catch` فيُعدّ إخفاقاً بلا سبب.
  factory UnifiedInvoice.fromPayload(Map<String, dynamic> payload) {
    double num_(Object? v, [double fallback = 0]) =>
        v is num ? v.toDouble() : fallback;
    String str(Object? v, String fallback) =>
        v is String && v.isNotEmpty ? v : fallback;

    final rawItems = payload['items'];
    final items = <UnifiedLineItem>[];
    if (rawItems is List) {
      for (final entry in rawItems) {
        if (entry is! Map) continue;
        final m = entry.cast<String, dynamic>();
        items.add(UnifiedLineItem(
          description: str(m['description'], ''),
          itemCode: str(m['itemCode'], ''),
          itemCodeType: str(m['itemType'], 'EGS'),
          unitType: str(m['unitType'], 'EA'),
          quantity: num_(m['quantity'], 1),
          unitPrice: num_(m['unitPrice']),
          discount: num_(m['discount']),
          taxType: str(m['taxType'], 'T1'),
          taxSubtype: str(m['taxSubtype'], 'V009'),
          taxRate: num_(m['taxRate'], 14),
        ));
      }
    }

    final seller = payload['seller'];
    final buyer = payload['buyer'];

    return UnifiedInvoice(
      internalId: str(payload['internalId'], ''),
      invoiceType: str(payload['documentType'], 'invoice'),
      documentVersion: payload['documentVersion'] as String?,
      // تاريخُ الفاتورة لا ساعةُ الإرسال. و`DateTime.now()` احتياطٌ أخيرٌ
      // لحمولةٍ بلا تاريخٍ صالحٍ أصلاً.
      issueDate: DateTime.tryParse(str(payload['issueDate'], '')) ??
          DateTime.now(),
      seller: seller is Map ? seller.cast<String, dynamic>() : <String, dynamic>{},
      buyer: buyer is Map ? buyer.cast<String, dynamic>() : null,
      items: items,
      paymentMethod: payload['paymentMethod'] as String?,
      originalInvoiceId: payload['originalInvoiceId'] as String?,
    );
  }

  double get subtotal => items.fold(0, (sum, item) => sum + item.netAmount);
  double get totalTax => items.fold(0, (sum, item) => sum + item.taxAmount);
  double get totalAmount => subtotal + totalTax;

  /// Convert to generic payload map for service consumption
  Map<String, dynamic> toPayload() => {
    'internalId': internalId,
    'documentType': invoiceType,
    'documentVersion': documentVersion,
    'issueDate': issueDate.toUtc().toIso8601String(),
    'seller': seller,
    'buyer': buyer,
    'items': items.map((e) => e.toMap()).toList(),
    'subtotal': subtotal,
    'tax': totalTax,
    'total': totalAmount,
    'paymentMethod': paymentMethod,
    if (originalInvoiceId != null) 'originalInvoiceId': originalInvoiceId,
  };
}

/// Unified E-Invoice Service Wrapper
///
/// Abstracts the differences between ETA (Egypt) and JOFOTARA (Jordan)
/// APIs behind a single interface. Determined by platform configuration.
class EInvoiceServiceWrapper {
  EtaService? _etaService;
  JofotaraService? _jofotaraService;
  EInvoicePlatform? _activePlatform;

  /// Initialize the wrapper with platform-specific configuration
  void configure({
    EInvoicePlatform? platform,
    EtaConfig? etaConfig,
    JofotaraConfig? jofotaraConfig,

    /// عميلُ HTTP بديلٌ — **للاختبار وحدَه**.
    ///
    /// `EtaService` يقبل واحداً محقوناً أصلاً، لكنّ هذا المُنشئَ كان يبتلعه
    /// فلا سبيلَ إلى قياس رحلةِ المستند من طرفٍ لطرفٍ بلا شبكةٍ حقيقيّة.
    /// و`null` تعني عميلَ الشبكة المعتاد، فلا يتغيّر شيءٌ في الإنتاج.
    @visibleForTesting http.Client? httpClient,
  }) {
    _activePlatform = platform;

    if (etaConfig != null) {
      _etaService = EtaService(config: etaConfig, httpClient: httpClient);
      _activePlatform ??= EInvoicePlatform.eta;
    }

    if (jofotaraConfig != null) {
      _jofotaraService = JofotaraService(config: jofotaraConfig);
      _activePlatform ??= EInvoicePlatform.jofotara;
    }
  }

  /// Whether the service is configured and ready
  bool get isConfigured =>
      _activePlatform != null &&
      (_etaService != null || _jofotaraService != null);

  /// Active platform
  EInvoicePlatform? get activePlatform => _activePlatform;

  // ─────────────────────────────────────────────────────────────────────────
  // UNIFIED OPERATIONS
  // ─────────────────────────────────────────────────────────────────────────

  /// Test connection to the active platform
  Future<bool> testConnection() async {
    switch (_activePlatform) {
      case EInvoicePlatform.eta:
        return _etaService!.testConnection();
      case EInvoicePlatform.jofotara:
        return _jofotaraService!.testConnection();
      default:
        throw StateError('E-Invoice service not configured');
    }
  }

  /// Submit a unified invoice to the active platform
  Future<UnifiedSubmissionResult> submitInvoice(UnifiedInvoice invoice) async {
    final payload = invoice.toPayload();

    switch (_activePlatform) {
      case EInvoicePlatform.eta:
        return _submitToEta(payload);
      case EInvoicePlatform.jofotara:
        return _submitToJofotara(payload);
      default:
        throw StateError('E-Invoice service not configured');
    }
  }

  /// Check document status on the active platform
  Future<UnifiedDocumentStatus> checkStatus(String documentId) async {
    switch (_activePlatform) {
      case EInvoicePlatform.eta:
        final status = await _etaService!.checkDocumentStatus(documentId);
        return UnifiedDocumentStatus(
          status: status.status,
          platform: EInvoicePlatform.eta,
          errors: status.validationErrors,
        );
      case EInvoicePlatform.jofotara:
        final status = await _jofotaraService!.checkInvoiceStatus(documentId);
        return UnifiedDocumentStatus(
          status: status.status,
          platform: EInvoicePlatform.jofotara,
          errors: status.rejectionReason != null
              ? [
                  {'reason': status.rejectionReason},
                ]
              : [],
        );
      default:
        throw StateError('E-Invoice service not configured');
    }
  }

  /// Cancel/reverse a document
  Future<bool> cancelDocument(String documentId, String reason) async {
    switch (_activePlatform) {
      case EInvoicePlatform.eta:
        return _etaService!.cancelDocument(documentId, reason);
      case EInvoicePlatform.jofotara:
        // JOFOTARA uses credit notes for cancellation
        debugPrint('JOFOTARA: Use submitCreditNote for cancellation');
        return false;
      default:
        throw StateError('E-Invoice service not configured');
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // PLATFORM-SPECIFIC SUBMISSION
  // ─────────────────────────────────────────────────────────────────────────

  Future<UnifiedSubmissionResult> _submitToEta(
    Map<String, dynamic> payload,
  ) async {
    final result = await _etaService!.submitInvoice(payload);

    if (result.success && result.acceptedDocuments.isNotEmpty) {
      final doc = result.acceptedDocuments.first;
      final qr = doc.uuid != null && doc.longId != null
          ? EtaService.generateQrContent(uuid: doc.uuid!, longId: doc.longId!)
          : null;

      return UnifiedSubmissionResult(
        success: true,
        platform: EInvoicePlatform.eta,
        submissionId: result.submissionId,
        documentUuid: doc.uuid,
        longId: doc.longId,
        qrCode: qr,
        rawResponse: result.rawResponse,
      );
    }

    return UnifiedSubmissionResult(
      success: false,
      platform: EInvoicePlatform.eta,
      errorMessage: result.errorMessage ?? 'فشل إرسال الفاتورة إلى ETA',
      rawResponse: result.rawResponse,
    );
  }

  Future<UnifiedSubmissionResult> _submitToJofotara(
    Map<String, dynamic> payload,
  ) async {
    final result = await _jofotaraService!.submitInvoice(payload);

    return UnifiedSubmissionResult(
      success: result.success,
      platform: EInvoicePlatform.jofotara,
      submissionId: result.invoiceId,
      documentUuid: result.invoiceHash,
      qrCode: result.qrCode,
      errorMessage: result.errorMessage,
      rawResponse: result.rawResponse,
    );
  }

  /// Dispose all services
  void dispose() {
    _etaService?.dispose();
    _jofotaraService?.dispose();
  }
}
