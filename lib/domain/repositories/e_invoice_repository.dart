import '../../data/database/database.dart';

abstract class IEInvoiceRepository {
  Future<EInvoiceConfigData?> getEInvoiceConfig(String platform);
  Future<EInvoiceConfigData?> getActiveEInvoiceConfig(String platform);
  Future<int> saveEInvoiceConfig({
    required String platform,
    required String clientId,
    required String clientSecret,
    required String registrationNumber,
    String? activityCode,
    String? branchId,
    String documentVersion = '0.9',
    String codingSystem = 'EGS',
    bool isProduction = false,
    bool isEnabled = false,
  });

  Stream<List<EInvoiceSubmissionData>> watchSubmissions({
    String? status,
    String? platform,
  });

  /// Submission queue joined to its sales invoice and customer, so the queue
  /// screen renders invoice number / customer / value without an N+1 read.
  Stream<List<Map<String, dynamic>>> watchSubmissionsWithInvoice();

  /// Append-only status trail for one submission, oldest first.
  ///
  /// The log is never edited or deleted — `logStatusChange` only inserts.
  Future<List<Map<String, dynamic>>> getStatusAuditTrail(int submissionId);

  Future<List<EInvoiceSubmissionData>> getPendingSubmissions({String? platform});
  Future<Map<String, int>> getSubmissionStats({String? platform});

  Future<List<EInvoiceSubmissionData>> getSubmissionsByStatus(String status);
  Future<EInvoiceSubmissionData?> getSubmissionBySaleId(int saleId);
  Future<int> createSubmission({
    required int saleId,
    required String platform,
    String documentType = 'invoice',
    String? internalId,
    String? rawRequest,
  });

  Future<void> markSubmissionSuccess({
    required int submissionId,
    required String submissionUuid,
    String? documentUuid,
    String? longId,
    String? hashKey,
    String? qrCode,
    String? rawResponse,
  });

  Future<void> markSubmissionFailed(
    int submissionId,
    String error, {
    String? rawResponse,
  });

  Future<void> updateSubmissionStatus(
    int submissionId,
    String newStatus, {
    String? errorMessage,
  });

  Future<Map<String, dynamic>> buildInvoicePayload(int saleId, String platform);

  Future<void> seedTaxTypes();
  Future<int> bulkGenerateEgsCodes();
}
