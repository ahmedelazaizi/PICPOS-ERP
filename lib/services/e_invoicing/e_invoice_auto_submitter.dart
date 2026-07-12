import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'e_invoice_service_wrapper.dart';
import '../../domain/repositories/e_invoice_repository.dart';

// ═══════════════════════════════════════════════════════════════════════════
// E-INVOICE AUTO SUBMITTER — الإرسال التلقائي للفوترة الإلكترونية
// ═══════════════════════════════════════════════════════════════════════════
//
// This service bridges the gap between invoice creation and e-invoice
// submission. It is called:
//   1. After POS checkout (processCheckout in CheckoutController)
//   2. After regular sales invoice save
//   3. After sales return (credit note)
//
// Flow:
//   saleId → buildInvoicePayload(saleId, platform)
//         → createSubmission(saleId, platform)
//         → wrapper.submitInvoice(UnifiedInvoice)
//         → markSubmissionSuccess / markSubmissionFailed
//
// The submission is fire-and-forget (non-blocking). If it fails, the
// invoice is queued for manual retry via the Dashboard.
// ═══════════════════════════════════════════════════════════════════════════

class EInvoiceAutoSubmitter {
  final IEInvoiceRepository _repo;
  final EInvoiceServiceWrapper _wrapper;

  EInvoiceAutoSubmitter({
    required IEInvoiceRepository repo,
    required EInvoiceServiceWrapper wrapper,
  })  : _repo = repo,
        _wrapper = wrapper;

  /// Check if e-invoicing is configured and enabled
  Future<bool> get isEnabled async {
    if (!_wrapper.isConfigured) return false;
    final platform = _wrapper.activePlatform == EInvoicePlatform.eta
        ? 'eta'
        : 'jofotara';
    final config = await _repo.getActiveEInvoiceConfig(platform);
    return config != null && config.isEnabled;
  }

  /// Get the active platform name ('eta' or 'jofotara')
  String get _platformName =>
      _wrapper.activePlatform == EInvoicePlatform.eta ? 'eta' : 'jofotara';

  // ─────────────────────────────────────────────────────────────────────────
  // AUTO-SUBMIT INVOICE — إرسال الفاتورة تلقائياً
  // ─────────────────────────────────────────────────────────────────────────

  /// Submit a sales invoice to the active e-invoicing platform.
  /// Called after POS checkout or regular sales invoice save.
  ///
  /// This method is non-blocking — errors are caught and logged.
  /// Failed submissions are queued with status 'pending' or 'invalid'.
  Future<void> submitSaleInvoice(int saleId) async {
    try {
      if (!await isEnabled) return;

      final platform = _platformName;

      // Check: already submitted?
      final existing = await _repo.getSubmissionBySaleId(saleId);
      if (existing != null &&
          existing.status != 'invalid' &&
          existing.status != 'rejected') {
        return; // Already submitted or valid
      }

      // 1. Build payload from the sale data
      final payload = await _repo.buildInvoicePayload(saleId, platform);

      // 2. Create submission record (pending)
      final submissionId = await _repo.createSubmission(
        saleId: saleId,
        platform: platform,
        documentType: 'invoice',
        internalId: payload['internalId'] as String?,
        rawRequest: jsonEncode(payload),
      );

      // 3. Build UnifiedInvoice and submit
      final invoice = _buildUnifiedInvoice(payload);
      final result = await _wrapper.submitInvoice(invoice);

      // 4. Update submission record with result
      if (result.success) {
        await _repo.markSubmissionSuccess(
          submissionId: submissionId,
          submissionUuid: result.submissionId ?? '',
          documentUuid: result.documentUuid,
          qrCode: result.qrCode,
          rawResponse: result.rawResponse,
        );
        debugPrint('✅ فاتورة #$saleId — إرسال ناجح للفوترة الإلكترونية');
      } else {
        await _repo.markSubmissionFailed(
          submissionId,
          result.errorMessage ?? 'فشل غير معروف',
          rawResponse: result.rawResponse,
        );
        debugPrint(
          '⚠️ فاتورة #$saleId — فشل الإرسال: ${result.errorMessage}',
        );
      }
    } catch (e) {
      // Non-blocking — log and continue
      debugPrint('❌ خطأ في الإرسال التلقائي للفاتورة #$saleId: $e');
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // AUTO-SUBMIT CREDIT NOTE — إرسال إشعار دائن (مرتجع)
  // ─────────────────────────────────────────────────────────────────────────

  /// Submit a credit note (return) to the active e-invoicing platform.
  /// Called after processing a sales return.
  Future<void> submitCreditNote(int returnSaleId) async {
    try {
      if (!await isEnabled) return;

      final platform = _platformName;

      // Build payload
      final payload = await _repo.buildInvoicePayload(returnSaleId, platform);
      payload['documentType'] = 'credit_note';

      // Create submission
      final submissionId = await _repo.createSubmission(
        saleId: returnSaleId,
        platform: platform,
        documentType: 'credit_note',
        internalId: payload['internalId'] as String?,
        rawRequest: jsonEncode(payload),
      );

      // Submit
      final invoice = _buildUnifiedInvoice(payload);
      final result = await _wrapper.submitInvoice(invoice);

      if (result.success) {
        await _repo.markSubmissionSuccess(
          submissionId: submissionId,
          submissionUuid: result.submissionId ?? '',
          documentUuid: result.documentUuid,
          qrCode: result.qrCode,
          rawResponse: result.rawResponse,
        );
        debugPrint('✅ مرتجع #$returnSaleId — إرسال ناجح');
      } else {
        await _repo.markSubmissionFailed(
          submissionId,
          result.errorMessage ?? 'فشل غير معروف',
          rawResponse: result.rawResponse,
        );
      }
    } catch (e) {
      debugPrint('❌ خطأ في إرسال المرتجع #$returnSaleId: $e');
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // HELPERS — أدوات مساعدة
  // ─────────────────────────────────────────────────────────────────────────

  /// Convert raw payload map to UnifiedInvoice
  UnifiedInvoice _buildUnifiedInvoice(Map<String, dynamic> payload) {
    final items = (payload['items'] as List<Map<String, dynamic>>?) ?? [];
    final seller = payload['seller'] as Map<String, dynamic>? ?? {};

    return UnifiedInvoice(
      internalId: payload['internalId'] as String? ?? '',
      invoiceType: payload['documentType'] as String? ?? 'invoice',
      issueDate: DateTime.tryParse(payload['issueDate'] as String? ?? '') ??
          DateTime.now(),
      seller: seller,
      buyer: payload['buyer'] as Map<String, dynamic>?,
      items: items
          .map((item) => UnifiedLineItem(
                description: item['description'] as String? ?? '',
                itemCode: item['itemCode'] as String? ?? '',
                itemCodeType: item['itemType'] as String? ?? 'EGS',
                unitType: item['unitType'] as String? ?? 'EA',
                quantity: (item['quantity'] as num?)?.toDouble() ?? 1,
                unitPrice: (item['unitPrice'] as num?)?.toDouble() ?? 0,
                discount: (item['discount'] as num?)?.toDouble() ?? 0,
                taxType: item['taxType'] as String? ?? 'T1',
                taxSubtype: item['taxSubtype'] as String? ?? 'V009',
                taxRate: (item['taxRate'] as num?)?.toDouble() ?? 14,
              ))
          .toList(),
      paymentMethod: payload['paymentMethod'] as String? ?? 'cash',
    );
  }
}
