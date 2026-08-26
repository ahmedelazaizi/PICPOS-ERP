import '../database/database.dart';
import '../../domain/repositories/e_invoice_repository.dart';
import '../../services/secure_storage_service.dart';

class DriftEInvoiceRepository implements IEInvoiceRepository {
  final AppDatabase _db;
  final SecureStorageService _secureStorage;

  DriftEInvoiceRepository(this._db, this._secureStorage);

  @override
  Future<EInvoiceConfigData?> getEInvoiceConfig(String platform) async {
    final config = await _db.getEInvoiceConfig(platform);
    if (config == null) return null;

    // Retrieve sensitive secret from secure storage
    final secureSecret = await _secureStorage.getEInvoiceSecret(platform);

    if (secureSecret != null) {
      // Return config with secure secret
      return config.copyWith(clientSecret: secureSecret);
    } else if (config.clientSecret.isNotEmpty && config.clientSecret != '********') {
      // PROACTIVE MIGRATION: Secret exists in DB but not in SecureStorage
      await _secureStorage.setEInvoiceSecret(platform, config.clientSecret);
      
      // Clear secret from DB (replace with placeholder)
      await _db.saveEInvoiceConfig(
        platform: platform,
        clientId: config.clientId,
        clientSecret: '********', // Placeholder
        registrationNumber: config.registrationNumber,
        activityCode: config.activityCode,
        branchId: config.branchId,
        documentVersion: config.documentVersion,
        codingSystem: config.codingSystem,
        isProduction: config.isProduction,
        isEnabled: config.isEnabled,
      );
      
      return config;
    }

    return config;
  }

  @override
  Future<EInvoiceConfigData?> getActiveEInvoiceConfig(String platform) async {
    final config = await _db.getActiveEInvoiceConfig(platform);
    if (config == null) return null;
    
    // Use the secure-aware getter to ensure we have the secret
    return getEInvoiceConfig(platform);
  }

  @override
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
  }) async {
    // 1. Save sensitive secret to hardware-backed secure storage
    if (clientSecret != '********') {
      await _secureStorage.setEInvoiceSecret(platform, clientSecret);
    }

    // 2. Save non-sensitive config to SQLite (obscuring secret)
    return _db.saveEInvoiceConfig(
      platform: platform,
      clientId: clientId,
      clientSecret: '********', // Never store raw secret in DB
      registrationNumber: registrationNumber,
      activityCode: activityCode,
      branchId: branchId,
      documentVersion: documentVersion,
      codingSystem: codingSystem,
      isProduction: isProduction,
      isEnabled: isEnabled,
    );
  }

  @override
  Stream<List<EInvoiceSubmissionData>> watchSubmissions({
    String? status,
    String? platform,
  }) {
    return _db.watchSubmissions(status: status, platform: platform);
  }

  @override
  Stream<List<Map<String, dynamic>>> watchSubmissionsWithInvoice() {
    return _db.watchSubmissionsWithInvoice();
  }

  @override
  Future<List<Map<String, dynamic>>> getStatusAuditTrail(int submissionId) {
    return _db.getStatusAuditTrail(submissionId);
  }

  @override
  Future<List<EInvoiceSubmissionData>> getPendingSubmissions({String? platform}) {
    return _db.getPendingSubmissions(platform: platform);
  }

  @override
  Future<Map<String, int>> getSubmissionStats({String? platform}) {
    return _db.getSubmissionStats(platform: platform);
  }

  @override
  Future<List<EInvoiceSubmissionData>> getSubmissionsByStatus(String status) {
    return (_db.select(_db.eInvoiceSubmissions)..where((s) => s.status.equals(status))).get();
  }

  @override
  Future<EInvoiceSubmissionData?> getSubmissionBySaleId(int saleId) {
    return (_db.select(_db.eInvoiceSubmissions)..where((s) => s.saleId.equals(saleId))).getSingleOrNull();
  }

  @override

  @override
  Future<int> createSubmission({
    required int saleId,
    required String platform,
    String documentType = 'invoice',
    String? internalId,
    String? rawRequest,
  }) {
    return _db.createSubmission(
      saleId: saleId,
      platform: platform,
      documentType: documentType,
      internalId: internalId,
      rawRequest: rawRequest,
    );
  }

  @override
  Future<void> markSubmissionSuccess({
    required int submissionId,
    required String submissionUuid,
    String? documentUuid,
    String? longId,
    String? hashKey,
    String? qrCode,
    String? rawResponse,
  }) {
    return _db.markSubmissionSuccess(
      submissionId: submissionId,
      submissionUuid: submissionUuid,
      documentUuid: documentUuid,
      longId: longId,
      hashKey: hashKey,
      qrCode: qrCode,
      rawResponse: rawResponse,
    );
  }

  @override
  Future<void> markSubmissionFailed(
    int submissionId,
    String error, {
    String? rawResponse,
  }) {
    return _db.markSubmissionFailed(submissionId, error, rawResponse: rawResponse);
  }

  @override
  Future<void> updateSubmissionStatus(
    int submissionId,
    String newStatus, {
    String? errorMessage,
  }) {
    return _db.updateSubmissionStatus(submissionId, newStatus, errorMessage: errorMessage);
  }

  @override
  Future<Map<String, dynamic>> buildInvoicePayload(int saleId, String platform) {
    return _db.buildInvoicePayload(saleId, platform);
  }

  @override
  Future<void> seedTaxTypes() {
    return _db.seedTaxTypes();
  }

  @override
  Future<int> bulkGenerateEgsCodes() {
    return _db.bulkGenerateEgsCodes();
  }
}
