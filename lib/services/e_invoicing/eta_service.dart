// ignore_for_file: avoid_dynamic_calls
import 'dart:convert';
import 'package:http/http.dart' as http;

// ═══════════════════════════════════════════════════════════════════════════
// ETA EGYPT E-INVOICING SERVICE — منظومة الفاتورة الإلكترونية المصرية
// ═══════════════════════════════════════════════════════════════════════════

/// Configuration for ETA service
class EtaConfig {
  final String clientId;
  final String clientSecret;
  final String registrationNumber;
  final String? activityCode;
  final String? branchId;
  final String documentVersion; // '0.9' or '1.0'
  final String codingSystem; // 'EGS', 'GPC', 'GS1'
  final bool isProduction;

  const EtaConfig({
    required this.clientId,
    required this.clientSecret,
    required this.registrationNumber,
    this.activityCode,
    this.branchId,
    this.documentVersion = '0.9',
    this.codingSystem = 'EGS',
    this.isProduction = false,
  });

  /// Identity server URL
  String get identityUrl => isProduction
      ? 'https://id.eta.gov.eg/connect/token'
      : 'https://id.preprod.eta.gov.eg/connect/token';

  /// API base URL
  String get apiBaseUrl => isProduction
      ? 'https://api.invoicing.eta.gov.eg/api/v1'
      : 'https://api.preprod.invoicing.eta.gov.eg/api/v1';
}

/// OAuth2 token with expiry tracking
class EtaToken {
  final String accessToken;
  final DateTime expiresAt;

  EtaToken({required this.accessToken, required this.expiresAt});

  bool get isExpired => DateTime.now().isAfter(expiresAt);
}

/// Result from ETA document submission
class EtaSubmissionResult {
  final bool success;
  final String? submissionId;
  final List<EtaDocumentResult> acceptedDocuments;
  final List<EtaDocumentResult> rejectedDocuments;
  final String? errorMessage;
  final String? rawResponse;

  EtaSubmissionResult({
    required this.success,
    this.submissionId,
    this.acceptedDocuments = const [],
    this.rejectedDocuments = const [],
    this.errorMessage,
    this.rawResponse,
  });
}

/// Individual document result within a submission
class EtaDocumentResult {
  final String internalId;
  final String? uuid;
  final String? longId;
  final String? hashKey;

  EtaDocumentResult({
    required this.internalId,
    this.uuid,
    this.longId,
    this.hashKey,
  });
}

/// Document validation status from ETA
class EtaDocumentStatus {
  final String status; // 'Valid', 'Invalid', 'Rejected', 'Cancelled'
  final String? validationStepStatus;
  final List<Map<String, dynamic>> validationErrors;

  EtaDocumentStatus({
    required this.status,
    this.validationStepStatus,
    this.validationErrors = const [],
  });
}

/// ETA Egypt E-Invoicing Service
///
/// Handles OAuth2 authentication, document submission (V0.9/V1.0),
/// status polling, and cancellation for the Egyptian Tax Authority.
class EtaService {
  final EtaConfig config;
  final http.Client _httpClient;
  EtaToken? _cachedToken;

  EtaService({required this.config, http.Client? httpClient})
    : _httpClient = httpClient ?? http.Client();

  // ─────────────────────────────────────────────────────────────────────────
  // AUTHENTICATION — المصادقة (OAuth2 Client Credentials)
  // ─────────────────────────────────────────────────────────────────────────

  /// Get a valid access token (with caching)
  Future<String> getAccessToken() async {
    if (_cachedToken != null && !_cachedToken!.isExpired) {
      return _cachedToken!.accessToken;
    }

    final response = await _httpClient.post(
      Uri.parse(config.identityUrl),
      headers: {'Content-Type': 'application/x-www-form-urlencoded'},
      body: {
        'grant_type': 'client_credentials',
        'client_id': config.clientId,
        'client_secret': config.clientSecret,
        'scope': 'InvoicingAPI',
      },
    );

    if (response.statusCode != 200) {
      throw EtaAuthException(
        'فشل المصادقة مع ETA: ${response.statusCode}',
        response.body,
      );
    }

    final data = json.decode(response.body);
    final expiresIn = data['expires_in'] as int? ?? 3600;
    _cachedToken = EtaToken(
      accessToken: data['access_token'] as String,
      expiresAt: DateTime.now().add(Duration(seconds: expiresIn - 60)),
    );

    return _cachedToken!.accessToken;
  }

  /// Test connection to ETA servers
  Future<bool> testConnection() async {
    try {
      await getAccessToken();
      return true;
    } catch (_) {
      return false;
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // DOCUMENT SUBMISSION — إرسال المستندات
  // ─────────────────────────────────────────────────────────────────────────

  /// Submit a single invoice to ETA
  Future<EtaSubmissionResult> submitInvoice(
    Map<String, dynamic> invoicePayload,
  ) async {
    return submitDocuments([invoicePayload]);
  }

  /// Submit batch of documents (up to 200 per batch per ETA specs)
  /// Includes auto-retry with exponential backoff (up to 3 attempts)
  Future<EtaSubmissionResult> submitDocuments(
    List<Map<String, dynamic>> documents,
  ) async {
    if (documents.isEmpty) {
      return EtaSubmissionResult(
        success: false,
        errorMessage: 'لا توجد مستندات للإرسال',
      );
    }

    final token = await getAccessToken();
    final url = '${config.apiBaseUrl}/documentsubmissions'; // Corrected URL

    // Convert documents to ETA format
    final etaDocuments = <Map<String, dynamic>>[];
    for (final doc in documents) {
      etaDocuments.add(_buildEtaDocument(doc));
    }

    final body = jsonEncode({'documents': etaDocuments});

    // Retry with exponential backoff (3 attempts)
    const maxRetries = 3;
    for (int attempt = 1; attempt <= maxRetries; attempt++) {
      try {
        final response = await _httpClient.post( // Changed _client to _httpClient
          Uri.parse(url),
          headers: {
            'Authorization': 'Bearer $token',
            'Content-Type': 'application/json',
            'Content-Length': body.length.toString(),
          },
          body: body,
        );

        if (response.statusCode == 202 || response.statusCode == 200) {
          final data = jsonDecode(response.body) as Map<String, dynamic>;
          final submissionId = data['submissionId'] as String?;
          final acceptedDocs =
              (data['acceptedDocuments'] as List?)
                  ?.map(
                    (d) => EtaDocumentResult(
                      uuid: d['uuid'] as String? ?? '',
                      longId: d['longId'] as String?,
                      internalId: d['internalId'] as String? ?? '', // Added null check
                      hashKey: d['hashKey'] as String?,
                    ),
                  )
                  .toList() ??
              [];

          final rejectedDocs =
              (data['rejectedDocuments'] as List?)
                  ?.map(
                    (d) => EtaDocumentResult(
                      internalId: d['internalId'] as String? ?? '',
                    ),
                  )
                  .toList() ??
              [];

          return EtaSubmissionResult(
            success: rejectedDocs.isEmpty,
            submissionId: submissionId,
            acceptedDocuments: acceptedDocs,
            rejectedDocuments: rejectedDocs,
            rawResponse: response.body, // Added rawResponse
          );
        }

        // If it's a server error (5xx), retry
        if (response.statusCode >= 500 && attempt < maxRetries) {
          await Future.delayed(Duration(seconds: attempt * 2)); // backoff
          continue;
        }

        // Auth errors — don't retry
        if (response.statusCode == 401) {
          _cachedToken = null; // Force re-auth
          throw EtaAuthException('انتهت صلاحية التوكن');
        }

        return EtaSubmissionResult(
          success: false,
          errorMessage: 'خطأ ETA ${response.statusCode}: ${response.body}',
          rawResponse: response.body, // Added rawResponse
        );
      } catch (e) {
        if (e is EtaAuthException) rethrow;
        if (attempt == maxRetries) {
          return EtaSubmissionResult(
            success: false,
            errorMessage: 'فشل الإرسال بعد $maxRetries محاولات: $e',
          );
        }
        await Future.delayed(Duration(seconds: attempt * 2));
      }
    }

    return EtaSubmissionResult(
      success: false,
      errorMessage: 'فشل الإرسال — استنفدت المحاولات',
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // STATUS POLLING — متابعة حالة المستند
  // ─────────────────────────────────────────────────────────────────────────

  /// Check submission status by submission ID
  Future<EtaDocumentStatus> checkSubmissionStatus(String submissionId) async {
    final token = await getAccessToken();

    final response = await _httpClient.get(
      Uri.parse('${config.apiBaseUrl}/documentsubmissions/$submissionId'),
      headers: {'Authorization': 'Bearer $token'},
    );

    if (response.statusCode != 200) {
      throw EtaApiException('فشل استعلام حالة المستند', response.body);
    }

    final data = json.decode(response.body);
    return EtaDocumentStatus(
      status: data['overallStatus'] as String? ?? 'Unknown',
      validationStepStatus: data['validationStepStatus'] as String?,
    );
  }

  /// Check document status by UUID (more detailed)
  Future<EtaDocumentStatus> checkDocumentStatus(String documentUuid) async {
    final token = await getAccessToken();

    final response = await _httpClient.get(
      Uri.parse('${config.apiBaseUrl}/documents/$documentUuid/raw'),
      headers: {'Authorization': 'Bearer $token'},
    );

    if (response.statusCode != 200) {
      throw EtaApiException('فشل استعلام المستند', response.body);
    }

    final data = json.decode(response.body);
    final errors = <Map<String, dynamic>>[];

    if (data['validationResults'] != null) {
      for (final step
          in (data['validationResults']['validationSteps'] as List? ?? [])) {
        if (step['status'] != 'Valid') {
          errors.add({
            'step': step['name'],
            'status': step['status'],
            'error': step['error'],
          });
        }
      }
    }

    return EtaDocumentStatus(
      status: data['status'] as String? ?? 'Unknown',
      validationErrors: errors,
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // CANCELLATION — إلغاء الفاتورة (خلال 72 ساعة)
  // ─────────────────────────────────────────────────────────────────────────

  /// Cancel a document (within 72-hour grace period)
  Future<bool> cancelDocument(String documentUuid, String reason) async {
    final token = await getAccessToken();

    final response = await _httpClient.put(
      Uri.parse('${config.apiBaseUrl}/documents/state/$documentUuid/state'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
      body: json.encode({'status': 'cancelled', 'reason': reason}),
    );

    return response.statusCode == 200;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // DOCUMENT BUILDING — بناء المستند بصيغة ETA
  // ─────────────────────────────────────────────────────────────────────────

  /// Convert internal invoice payload to ETA document format
  Map<String, dynamic> _buildEtaDocument(Map<String, dynamic> payload) {
    final items = (payload['items'] as List<Map<String, dynamic>>?) ?? [];
    final seller = payload['seller'] as Map<String, dynamic>? ?? {};
    final buyer = payload['buyer'] as Map<String, dynamic>?;

    // Build ETA invoice lines
    final invoiceLines = items.asMap().entries.map((entry) {
      final i = entry.key;
      final item = entry.value;

      final quantity = (item['quantity'] as num?)?.toDouble() ?? 1;
      final unitPrice = (item['unitPrice'] as num?)?.toDouble() ?? 0;
      final discount = (item['discount'] as num?)?.toDouble() ?? 0;
      final salesTotal = quantity * unitPrice;
      final netTotal = salesTotal - discount;
      final taxRate = (item['taxRate'] as num?)?.toDouble() ?? 0;
      final taxAmount =
          (item['taxAmount'] as num?)?.toDouble() ?? netTotal * taxRate / 100;

      return {
        'description': item['description'] ?? '',
        'itemType': item['itemType'] ?? 'EGS',
        'itemCode': item['itemCode'] ?? '',
        'unitType': item['unitType'] ?? 'EA',
        'quantity': quantity,
        'internalCode': '${i + 1}',
        'salesTotal': _round(salesTotal),
        'total': _round(salesTotal),
        'valueDifference': 0.0,
        'totalTaxableFees': 0.0,
        'netTotal': _round(netTotal),
        'itemsDiscount': _round(discount),
        'unitValue': {'currencySold': 'EGP', 'amountEGP': _round(unitPrice)},
        'discount': {
          'rate': discount > 0 ? _round(discount / salesTotal * 100) : 0,
          'amount': _round(discount),
        },
        'taxableItems': [
          {
            'taxType': item['taxType'] ?? 'T1',
            'subType': item['taxSubtype'] ?? 'V009',
            'amount': _round(taxAmount),
            'rate': taxRate,
          },
        ],
      };
    }).toList();

    // Calculate totals
    final totalSalesAmount = _round(
      invoiceLines.fold<double>(
        0,
        (sum, line) => sum + ((line['salesTotal'] as num?)?.toDouble() ?? 0),
      ),
    );
    final totalDiscountAmount = _round(
      invoiceLines.fold<double>(
        0,
        (sum, line) => sum + ((line['itemsDiscount'] as num?)?.toDouble() ?? 0),
      ),
    );
    final netAmount = _round(totalSalesAmount - totalDiscountAmount);

    // Build tax totals
    final taxTotals = <Map<String, dynamic>>[];
    final taxGroups = <String, double>{};
    for (final line in invoiceLines) {
      for (final tax in (line['taxableItems'] as List<Map<String, dynamic>>)) {
        final key = tax['taxType'] as String;
        taxGroups[key] =
            (taxGroups[key] ?? 0) + ((tax['amount'] as num?)?.toDouble() ?? 0);
      }
    }
    for (final entry in taxGroups.entries) {
      taxTotals.add({'taxType': entry.key, 'amount': _round(entry.value)});
    }

    final totalTaxAmount = _round(
      taxGroups.values.fold<double>(0, (a, b) => a + b),
    );
    final totalAmount = _round(netAmount + totalTaxAmount);

    // Build main document
    final document = <String, dynamic>{
      'issuer': {
        'type': 'B', // Business
        'id': seller['registrationNumber'] ?? config.registrationNumber,
        'name': seller['name'] ?? '',
        'address': {
          'branchID': seller['branchId'] ?? config.branchId ?? '0',
          'country': 'EG',
          'governate': '',
          'regionCity': '',
          'street': '',
          'buildingNumber': '',
        },
      },
      'documentType': _mapDocumentType(payload['documentType'] as String?),
      'documentTypeVersion': config.documentVersion,
      'dateTimeIssued':
          payload['issueDate'] ?? DateTime.now().toUtc().toIso8601String(),
      'taxpayerActivityCode':
          seller['activityCode'] ?? config.activityCode ?? '',
      'internalID': payload['internalId'] ?? '',
      'invoiceLines': invoiceLines,
      'totalSalesAmount': totalSalesAmount,
      'totalDiscountAmount': totalDiscountAmount,
      'netAmount': netAmount,
      'taxTotals': taxTotals,
      'totalAmount': totalAmount,
      'extraDiscountAmount': 0.0,
      'totalItemsDiscountAmount': totalDiscountAmount,
    };

    // Add receiver (buyer) if exists
    if (buyer != null &&
        buyer['taxNumber'] != null &&
        (buyer['taxNumber'] as String).isNotEmpty) {
      document['receiver'] = {
        'type': 'B',
        'id': buyer['taxNumber'],
        'name': buyer['name'] ?? '',
        'address': {
          'country': 'EG',
          'governate': '',
          'regionCity': '',
          'street': buyer['address'] ?? '',
          'buildingNumber': '',
        },
      };
    }

    // Add payment info
    document['payment'] = {
      'bankName': '',
      'bankAddress': '',
      'bankAccountNo': '',
      'bankAccountIBAN': '',
      'swiftCode': '',
      'terms': '',
    };

    // Add delivery info
    document['delivery'] = {
      'approach': '',
      'packaging': '',
      'dateValidity': '',
      'exportPort': '',
      'grossWeight': 0,
      'netWeight': 0,
      'terms': '',
    };

    return document;
  }

  /// Map internal document type to ETA type code
  String _mapDocumentType(String? type) {
    switch (type?.toLowerCase()) {
      case 'credit_note':
        return 'C'; // Credit Note
      case 'debit_note':
        return 'D'; // Debit Note
      case 'export':
        return 'EX'; // Export Invoice
      case 'receipt':
        return 'R'; // Receipt (B2C)
      default:
        return 'I'; // Invoice
    }
  }

  /// Round to 5 decimal places (ETA precision requirement)
  double _round(double value) => double.parse(value.toStringAsFixed(5));

  // ─────────────────────────────────────────────────────────────────────────
  // QR CODE — رمز الاستجابة السريعة
  // ─────────────────────────────────────────────────────────────────────────

  /// Generate QR code content for ETA receipt
  /// Uses the UUID + long ID format returned from submission
  static String generateQrContent({
    required String uuid,
    required String longId,
  }) {
    // ETA QR code typically contains the document URL
    return 'https://invoicing.eta.gov.eg/documents/$uuid/share/$longId';
  }

  /// Dispose HTTP client
  void dispose() => _httpClient.close();
}

// ═══════════════════════════════════════════════════════════════════════════
// EXCEPTIONS
// ═══════════════════════════════════════════════════════════════════════════

class EtaAuthException implements Exception {
  final String message;
  final String? details;
  EtaAuthException(this.message, [this.details]);
  @override
  String toString() =>
      'EtaAuthException: $message${details != null ? ' ($details)' : ''}';
}

class EtaApiException implements Exception {
  final String message;
  final String? details;
  EtaApiException(this.message, [this.details]);
  @override
  String toString() =>
      'EtaApiException: $message${details != null ? ' ($details)' : ''}';
}