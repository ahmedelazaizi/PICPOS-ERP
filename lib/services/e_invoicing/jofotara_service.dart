// ignore_for_file: avoid_dynamic_calls
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../core/constants/app_constants.dart';

// ═══════════════════════════════════════════════════════════════════════════
// JOFOTARA JORDAN E-INVOICING SERVICE — منظومة الفوترة الإلكترونية الأردنية
// ═══════════════════════════════════════════════════════════════════════════

/// Configuration for JOFOTARA service
class JofotaraConfig {
  final String clientId;
  final String clientSecret;
  final String registrationNumber; // رقم التسجيل الضريبي الأردني
  final bool isProduction;

  const JofotaraConfig({
    required this.clientId,
    required this.clientSecret,
    required this.registrationNumber,
    this.isProduction = false,
  });

  /// Auth endpoint
  String get authUrl => isProduction
      ? 'https://api.jofotara.gov.jo/auth/token'
      : 'https://api.preprod.jofotara.gov.jo/auth/token';

  /// API base URL
  String get apiBaseUrl => isProduction
      ? 'https://api.jofotara.gov.jo/api/v1'
      : 'https://api.preprod.jofotara.gov.jo/api/v1';
}

/// Bearer token with expiry
class JofotaraToken {
  final String accessToken;
  final DateTime expiresAt;

  JofotaraToken({required this.accessToken, required this.expiresAt});

  bool get isExpired => DateTime.now().isAfter(expiresAt);
}

/// Submission result from JOFOTARA
class JofotaraSubmissionResult {
  final bool success;
  final String? invoiceId;
  final String? invoiceHash;
  final String? qrCode;
  final String? errorMessage;
  final String? rawResponse;

  JofotaraSubmissionResult({
    required this.success,
    this.invoiceId,
    this.invoiceHash,
    this.qrCode,
    this.errorMessage,
    this.rawResponse,
  });
}

/// Invoice status from JOFOTARA
class JofotaraInvoiceStatus {
  final String status; // 'accepted', 'rejected', 'pending'
  final String? rejectionReason;

  JofotaraInvoiceStatus({required this.status, this.rejectionReason});
}

/// JOFOTARA Jordan E-Invoicing Service
///
/// Handles bearer token authentication, invoice submission,
/// QR code generation (TLV format), and offline queue support
/// for Jordan's General Sales Tax (16%).
class JofotaraService {
  final JofotaraConfig config;
  final http.Client _httpClient;
  JofotaraToken? _cachedToken;

  JofotaraService({required this.config, http.Client? httpClient})
    : _httpClient = httpClient ?? http.Client();

  // ─────────────────────────────────────────────────────────────────────────
  // AUTHENTICATION — المصادقة (Bearer Token)
  // ─────────────────────────────────────────────────────────────────────────

  /// Get a valid access token (with caching)
  Future<String> getAccessToken() async {
    if (_cachedToken != null && !_cachedToken!.isExpired) {
      return _cachedToken!.accessToken;
    }

    final response = await _httpClient.post(
      Uri.parse(config.authUrl),
      headers: {'Content-Type': 'application/json'},
      body: json.encode({
        'client_id': config.clientId,
        'client_secret': config.clientSecret,
        'grant_type': 'client_credentials',
      }),
    );

    if (response.statusCode != 200) {
      throw JofotaraAuthException(
        'فشل المصادقة مع JOFOTARA: ${response.statusCode}',
        response.body,
      );
    }

    final data = json.decode(response.body);
    final expiresIn = data['expires_in'] as int? ?? 3600;
    _cachedToken = JofotaraToken(
      accessToken: data['access_token'] as String,
      expiresAt: DateTime.now().add(Duration(seconds: expiresIn - 60)),
    );

    return _cachedToken!.accessToken;
  }

  /// Test connection to JOFOTARA servers
  Future<bool> testConnection() async {
    try {
      await getAccessToken();
      return true;
    } catch (_) {
      return false;
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // INVOICE SUBMISSION — إرسال الفواتير
  // ─────────────────────────────────────────────────────────────────────────

  /// Submit a single invoice to JOFOTARA
  /// Includes auto-retry with exponential backoff (up to 3 attempts)
  Future<JofotaraSubmissionResult> submitInvoice(
    Map<String, dynamic> invoicePayload,
  ) async {
    final jofotaraDoc = _buildJofotaraDocument(invoicePayload);

    const maxRetries = 3;
    for (int attempt = 1; attempt <= maxRetries; attempt++) {
      try {
        final token = await getAccessToken();

        final response = await _httpClient.post(
          Uri.parse('${config.apiBaseUrl}/invoices'),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $token',
          },
          body: json.encode(jofotaraDoc),
        );

        final responseData = json.decode(response.body);

        if (response.statusCode == 200 || response.statusCode == 201) {
          final invoiceId = responseData['invoiceId'] as String?;
          final invoiceHash = responseData['invoiceHash'] as String?;

          final qrContent = generateQrCode(
            sellerName: jofotaraDoc['seller']?['name'] ?? '',
            sellerTrn: config.registrationNumber,
            invoiceDate:
                invoicePayload['issueDate'] ?? DateTime.now().toIso8601String(),
            totalAmount: (invoicePayload['total'] as num?)?.toDouble() ?? 0,
            vatAmount: (invoicePayload['tax'] as num?)?.toDouble() ?? 0,
          );

          return JofotaraSubmissionResult(
            success: true,
            invoiceId: invoiceId,
            invoiceHash: invoiceHash,
            qrCode: qrContent,
            rawResponse: response.body,
          );
        }

        // Server error — retry
        if (response.statusCode >= 500 && attempt < maxRetries) {
          await Future.delayed(Duration(seconds: attempt * 2));
          continue;
        }

        // Auth error — force re-auth and retry once
        if (response.statusCode == 401 && attempt < maxRetries) {
          _cachedToken = null;
          await Future.delayed(const Duration(seconds: 1));
          continue;
        }

        return JofotaraSubmissionResult(
          success: false,
          errorMessage:
              'خطأ JOFOTARA: ${response.statusCode} — ${responseData['error'] ?? response.body}',
          rawResponse: response.body,
        );
      } catch (e) {
        if (attempt == maxRetries) {
          return JofotaraSubmissionResult(
            success: false,
            errorMessage: 'فشل الإرسال بعد $maxRetries محاولات: $e',
          );
        }
        await Future.delayed(Duration(seconds: attempt * 2));
      }
    }

    return JofotaraSubmissionResult(
      success: false,
      errorMessage: 'فشل الإرسال — استنفدت المحاولات',
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // STATUS CHECK — استعلام حالة الفاتورة
  // ─────────────────────────────────────────────────────────────────────────

  /// Check invoice status by invoice ID
  Future<JofotaraInvoiceStatus> checkInvoiceStatus(String invoiceId) async {
    final token = await getAccessToken();

    final response = await _httpClient.get(
      Uri.parse('${config.apiBaseUrl}/invoices/$invoiceId'),
      headers: {'Authorization': 'Bearer $token'},
    );

    if (response.statusCode != 200) {
      throw JofotaraApiException('فشل استعلام حالة الفاتورة', response.body);
    }

    final data = json.decode(response.body);
    return JofotaraInvoiceStatus(
      status: data['status'] as String? ?? 'unknown',
      rejectionReason: data['rejectionReason'] as String?,
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // CREDIT NOTES — إشعارات دائنة (مرتجعات)
  // ─────────────────────────────────────────────────────────────────────────

  /// Submit a credit note (reversal/return)
  Future<JofotaraSubmissionResult> submitCreditNote({
    required String originalInvoiceId,
    required Map<String, dynamic> creditNotePayload,
  }) async {
    creditNotePayload['invoiceType'] = 'credit_note';
    creditNotePayload['originalInvoiceId'] = originalInvoiceId;
    return submitInvoice(creditNotePayload);
  }

  // ─────────────────────────────────────────────────────────────────────────
  // DOCUMENT BUILDING — بناء المستند بصيغة JOFOTARA
  // ─────────────────────────────────────────────────────────────────────────

  /// Convert internal invoice payload to JOFOTARA format
  Map<String, dynamic> _buildJofotaraDocument(Map<String, dynamic> payload) {
    final items = (payload['items'] as List<Map<String, dynamic>>?) ?? [];
    final seller = payload['seller'] as Map<String, dynamic>? ?? {};
    final buyer = payload['buyer'] as Map<String, dynamic>?;

    // Build line items
    final lineItems = items.map((item) {
      final quantity = (item['quantity'] as num?)?.toDouble() ?? 1;
      final unitPrice = (item['unitPrice'] as num?)?.toDouble() ?? 0;
      final discount = (item['discount'] as num?)?.toDouble() ?? 0;
      final netAmount = (quantity * unitPrice) - discount;
      final taxRate =
          (item['taxRate'] as num?)?.toDouble() ?? 16; // Jordan default: 16%
      final taxAmount = netAmount * taxRate / 100;

      return {
        'description': item['description'] ?? '',
        'itemCode': item['itemCode'] ?? '',
        'quantity': quantity,
        'unitPrice': unitPrice,
        'discount': discount,
        'netAmount': _round(netAmount),
        'taxRate': taxRate,
        'taxAmount': _round(taxAmount),
        'totalAmount': _round(netAmount + taxAmount),
      };
    }).toList();

    // Calculate totals
    final subtotal = _round(
      lineItems.fold<double>(
        0,
        (sum, item) => sum + ((item['netAmount'] as num?)?.toDouble() ?? 0),
      ),
    );
    final totalTax = _round(
      lineItems.fold<double>(
        0,
        (sum, item) => sum + ((item['taxAmount'] as num?)?.toDouble() ?? 0),
      ),
    );
    final total = _round(subtotal + totalTax);

    // Determine invoice type
    final invoiceType = _mapInvoiceType(payload['invoiceType'] as String?);

    return {
      'invoiceType': invoiceType,
      'invoiceNumber': payload['internalId'] ?? '',
      'issueDate': payload['issueDate'] ?? DateTime.now().toIso8601String(),
      'seller': {
        'name': seller['name'] ?? '',
        'registrationNumber':
            seller['registrationNumber'] ?? config.registrationNumber,
        'branchId': seller['branchId'] ?? '1',
      },
      if (buyer != null)
        'buyer': {
          'name': buyer['name'] ?? '',
          'taxNumber': buyer['taxNumber'] ?? '',
          'address': buyer['address'] ?? '',
        },
      'lineItems': lineItems,
      'subtotal': subtotal,
      'totalTax': totalTax,
      'totalAmount': total,
      'currency': 'JOD',
      'paymentMethod': payload['paymentMethod'] ?? 'cash',
      if (payload['originalInvoiceId'] != null)
        'originalInvoiceId': payload['originalInvoiceId'],
    };
  }

  /// Map internal type to JOFOTARA invoice type
  String _mapInvoiceType(String? type) {
    switch (type?.toLowerCase()) {
      case 'credit_note':
        return 'CreditNote';
      case 'debit_note':
        return 'DebitNote';
      default:
        return 'Normal';
    }
  }

  double _round(double value) => double.parse(value.toStringAsFixed(3));

  // ─────────────────────────────────────────────────────────────────────────
  // QR CODE — رمز الاستجابة السريعة (TLV Format)
  // ─────────────────────────────────────────────────────────────────────────

  /// Generate JOFOTARA-compliant QR code content using TLV (Tag-Length-Value) format
  ///
  /// Tags:
  /// 1 = Seller Name
  /// 2 = Seller Tax Registration Number (TRN)
  /// 3 = Invoice Date/Time
  /// 4 = Invoice Total (with VAT)
  /// 5 = VAT Amount
  static String generateQrCode({
    required String sellerName,
    required String sellerTrn,
    required String invoiceDate,
    required double totalAmount,
    required double vatAmount,
  }) {
    final writer = <int>[];

    // Tag 1: Seller Name
    _writeTlv(writer, 1, utf8.encode(sellerName));
    // Tag 2: VAT Registration Number
    _writeTlv(writer, 2, utf8.encode(sellerTrn));
    // Tag 3: Invoice Date/Time
    _writeTlv(writer, 3, utf8.encode(invoiceDate));
    // Tag 4: Total Amount (with VAT)
    _writeTlv(writer, 4, utf8.encode(totalAmount.toStringAsFixed(AppConstants.decimalPlaces)));
    // Tag 5: VAT Amount
    _writeTlv(writer, 5, utf8.encode(vatAmount.toStringAsFixed(AppConstants.decimalPlaces)));

    return base64Encode(writer);
  }

  /// Write a TLV (Tag-Length-Value) entry
  static void _writeTlv(List<int> writer, int tag, List<int> value) {
    writer.add(tag);
    writer.add(value.length);
    writer.addAll(value);
  }

  /// Dispose HTTP client
  void dispose() => _httpClient.close();
}

// ═══════════════════════════════════════════════════════════════════════════
// EXCEPTIONS
// ═══════════════════════════════════════════════════════════════════════════

class JofotaraAuthException implements Exception {
  final String message;
  final String? details;
  JofotaraAuthException(this.message, [this.details]);
  @override
  String toString() =>
      'JofotaraAuthException: $message${details != null ? ' ($details)' : ''}';
}

class JofotaraApiException implements Exception {
  final String message;
  final String? details;
  JofotaraApiException(this.message, [this.details]);
  @override
  String toString() =>
      'JofotaraApiException: $message${details != null ? ' ($details)' : ''}';
}