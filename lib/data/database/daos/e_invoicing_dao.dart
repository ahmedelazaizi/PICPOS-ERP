part of '../database.dart';

// ═══════════════════════════════════════════════════════════════════════════
// E-INVOICING DAO — الفوترة الإلكترونية (ETA مصر + JOFOTARA الأردن)
// ═══════════════════════════════════════════════════════════════════════════

extension EInvoicingDao on AppDatabase {
  // ─────────────────────────────────────────────────────────────────────────
  // CONFIGURATION — إعدادات المنظومة
  // ─────────────────────────────────────────────────────────────────────────

  /// Get e-invoice config for a platform
  Future<EInvoiceConfigData?> getEInvoiceConfig(String platform) {
    return (select(
      eInvoiceConfigs,
    )..where((c) => c.platform.equals(platform))).getSingleOrNull();
  }

  /// Get active (enabled) config for a platform
  Future<EInvoiceConfigData?> getActiveEInvoiceConfig(String platform) {
    return (select(
          eInvoiceConfigs,
        )..where((c) => c.platform.equals(platform) & c.isEnabled.equals(true)))
        .getSingleOrNull();
  }

  /// Save or update e-invoice configuration
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
    // الإعدادُ والرايةُ في معاملةٍ واحدة: إمّا يُكتبان معاً وإمّا لا شيء.
    // فلا يبقى إعدادٌ مُفعَّلٌ على الخادم ورايةٌ منزَلةٌ على الأجهزة.
    return transaction(() async {
      final existing = await getEInvoiceConfig(platform);
      final int id;
      if (existing != null) {
        await (update(
          eInvoiceConfigs,
        )..where((c) => c.id.equals(existing.id))).write(
          EInvoiceConfigsCompanion(
            clientId: Value(clientId),
            clientSecret: Value(clientSecret),
            registrationNumber: Value(registrationNumber),
            activityCode: Value(activityCode),
            branchId: Value(branchId),
            documentVersion: Value(documentVersion),
            codingSystem: Value(codingSystem),
            isProduction: Value(isProduction),
            isEnabled: Value(isEnabled),
          ),
        );
        id = existing.id;
      } else {
        id = await into(eInvoiceConfigs).insert(
          EInvoiceConfigsCompanion.insert(
            platform: platform,
            clientId: clientId,
            clientSecret: clientSecret,
            registrationNumber: registrationNumber,
            activityCode: Value(activityCode),
            branchId: Value(branchId),
            documentVersion: Value(documentVersion),
            codingSystem: Value(codingSystem),
            isProduction: Value(isProduction),
            isEnabled: Value(isEnabled),
          ),
        );
      }
      await _writeEInvoiceEnabledFlag();
      return id;
    });
  }

  /// رايةُ `Settings` بلا سرّ — الشيءُ الوحيدُ من هذا الإعداد الذي يصل
  /// الأجهزةَ بالمزامنة (الجدولُ نفسُه خارجَها لأنّه يحمل `clientSecret`).
  ///
  /// تعني «توجد منصّةٌ مُفعَّلة» لا «آخرُ ما كُتب»: تُعاد حسابُها من الجدول
  /// بعد كلّ حفظ، فكتابةُ منصّةٍ معطَّلةٍ لا تُنزل رايةَ منصّةٍ قائمة.
  Future<void> _writeEInvoiceEnabledFlag() async {
    final anyEnabled = await (select(eInvoiceConfigs)
          ..where((c) => c.isEnabled.equals(true))
          ..limit(1))
        .get();
    await setSetting(
      kEInvoiceEnabledSettingKey,
      anyEnabled.isNotEmpty ? 'true' : 'false',
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // SUBMISSIONS — إرسال الفواتير
  // ─────────────────────────────────────────────────────────────────────────

  /// Watch submissions by status (for dashboard)
  Stream<List<EInvoiceSubmissionData>> watchSubmissions({
    String? status,
    String? platform,
  }) {
    final q = select(eInvoiceSubmissions)
      ..orderBy([(s) => OrderingTerm.desc(s.createdAt)]);
    if (status != null) q.where((s) => s.status.equals(status));
    if (platform != null) q.where((s) => s.platform.equals(platform));
    return q.watch();
  }

  /// طابورُ الإرسال موصولاً بفاتورته وعميلِها.
  ///
  /// ⚠️ **لماذا استعلامٌ واحدٌ موصولٌ لا قراءةٌ لكلّ صفّ.** `EInvoiceSubmissions`
  /// تحمل `saleId` وحدَه، وشاشةُ الطابور تعرض رقمَ الفاتورة واسمَ العميل
  /// وقيمتَها لكلّ سطر. وقراءةُ الفاتورة لكلّ صفٍّ على حدة تعطي N+1 على
  /// طابورٍ قد يبلغ مئاتِ المستندات — فالوصلُ في SQL مرّةً واحدة.
  ///
  /// و`LEFT JOIN` لا `INNER`: المستندُ يبقى في الطابور وإن حُذفت فاتورتُه
  /// أو كان بلا عميلٍ مسجَّل (‏بيعٌ نقديٌّ لعابر)، فالإخفاءُ يجعل الطابورَ
  /// يكذب.
  Stream<List<Map<String, dynamic>>> watchSubmissionsWithInvoice() {
    return customSelect(
      '''SELECT e.*,
                si.invoice_number AS invoice_number,
                si.total          AS invoice_total,
                si.invoice_date   AS invoice_date,
                p.name            AS customer_name
           FROM e_invoice_submissions e
           LEFT JOIN sales_invoices si ON si.id = e.sale_id
           LEFT JOIN parties p         ON p.id = si.customer_id
          ORDER BY e.created_at DESC''',
      readsFrom: {eInvoiceSubmissions, salesInvoices, parties},
    ).watch().map((rows) => rows.map((r) => r.data).toList());
  }

  /// Get submission for a specific sale
  Future<EInvoiceSubmissionData?> getSubmissionBySaleId(int saleId) {
    return (select(
      eInvoiceSubmissions,
    )..where((s) => s.saleId.equals(saleId))).getSingleOrNull();
  }

  /// Create a submission record (before sending)
  Future<int> createSubmission({
    required int saleId,
    required String platform,
    String documentType = 'invoice',
    String? internalId,
    String? rawRequest,
  }) async {
    // Avoid duplicate submissions
    final existing = await getSubmissionBySaleId(saleId);
    if (existing != null &&
        existing.status != 'invalid' &&
        existing.status != 'rejected') {
      throw Exception('فاتورة مرسلة بالفعل — الحالة: ${existing.status}');
    }

    return into(eInvoiceSubmissions).insert(
      EInvoiceSubmissionsCompanion.insert(
        saleId: saleId,
        platform: platform,
        documentType: Value(documentType),
        internalId: Value(internalId),
        rawRequest: Value(rawRequest),
      ),
    );
  }

  /// Update submission after API response (success)
  Future<void> markSubmissionSuccess({
    required int submissionId,
    required String submissionUuid,
    String? documentUuid,
    String? longId,
    String? hashKey,
    String? qrCode,
    String? rawResponse,
  }) async {
    await (update(
      eInvoiceSubmissions,
    )..where((s) => s.id.equals(submissionId))).write(
      EInvoiceSubmissionsCompanion(
        submissionId: Value(submissionUuid),
        documentUuid: Value(documentUuid),
        longId: Value(longId),
        hashKey: Value(hashKey),
        status: const Value('submitted'),
        qrCode: Value(qrCode),
        rawResponse: Value(rawResponse),
        submittedAt: Value(DateTime.now()),
        lastCheckedAt: Value(DateTime.now()),
      ),
    );
  }

  /// Update submission status (after polling for validation)
  Future<void> updateSubmissionStatus(
    int submissionId,
    String newStatus, {
    String? errorMessage,
  }) async {
    await (update(
      eInvoiceSubmissions,
    )..where((s) => s.id.equals(submissionId))).write(
      EInvoiceSubmissionsCompanion(
        status: Value(newStatus),
        errorMessage: Value(errorMessage),
        lastCheckedAt: Value(DateTime.now()),
      ),
    );
  }

  /// Update submission after API failure
  Future<void> markSubmissionFailed(
    int submissionId,
    String error, {
    String? rawResponse,
  }) async {
    final submission = await (select(
      eInvoiceSubmissions,
    )..where((s) => s.id.equals(submissionId))).getSingleOrNull();
    await (update(
      eInvoiceSubmissions,
    )..where((s) => s.id.equals(submissionId))).write(
      EInvoiceSubmissionsCompanion(
        status: const Value('invalid'),
        errorMessage: Value(error),
        rawResponse: Value(rawResponse),
        retryCount: Value((submission?.retryCount ?? 0) + 1),
        lastCheckedAt: Value(DateTime.now()),
      ),
    );
  }

  /// Get pending submissions (queue for retry)
  Future<List<EInvoiceSubmissionData>> getPendingSubmissions({
    String? platform,
  }) {
    final q = select(eInvoiceSubmissions)
      ..where((s) => s.status.isIn(['pending', 'invalid']))
      ..where((s) => s.retryCount.isSmallerThan(const Variable(5)))
      ..orderBy([(s) => OrderingTerm.asc(s.createdAt)]);
    if (platform != null) q.where((s) => s.platform.equals(platform));
    return q.get();
  }

  /// Get submission statistics for dashboard
  Future<Map<String, int>> getSubmissionStats({String? platform}) async {
    final q = select(eInvoiceSubmissions);
    if (platform != null) q.where((s) => s.platform.equals(platform));
    final all = await q.get();

    final stats = <String, int>{
      'total': all.length,
      'pending': 0,
      'submitted': 0,
      'valid': 0,
      'invalid': 0,
      'rejected': 0,
      'cancelled': 0,
    };

    for (final s in all) {
      stats[s.status] = (stats[s.status] ?? 0) + 1;
    }
    return stats;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // TAX TYPES — أنواع الضرائب المرجعية
  // ─────────────────────────────────────────────────────────────────────────

  /// Get all tax types
  Future<List<TaxTypeData>> getAllTaxTypes() => select(taxTypes).get();

  /// Get all subtypes for a tax type
  Future<List<TaxSubtypeData>> getTaxSubtypes(String taxTypeCode) {
    return (select(
      taxSubtypes,
    )..where((s) => s.taxTypeCode.equals(taxTypeCode))).get();
  }

  /// Seed default ETA tax types (call on first setup)
  Future<void> seedTaxTypes() async {
    final existing = await getAllTaxTypes();
    if (existing.isNotEmpty) return; // Already seeded

    final types = [
      {
        'code': 'T1',
        'nameAr': 'ضريبة القيمة المضافة',
        'nameEn': 'Value Added Tax',
        'isPct': true,
      },
      {
        'code': 'T2',
        'nameAr': 'ضريبة الجدول (نسبة)',
        'nameEn': 'Table Tax (Percentage)',
        'isPct': true,
      },
      {
        'code': 'T3',
        'nameAr': 'ضريبة الجدول (مبلغ)',
        'nameEn': 'Table Tax (Fixed)',
        'isPct': false,
      },
      {
        'code': 'T4',
        'nameAr': 'ضريبة الخصم والإضافة',
        'nameEn': 'Withholding Tax',
        'isPct': true,
      },
      {
        'code': 'T5',
        'nameAr': 'ضريبة الدمغة (نسبة)',
        'nameEn': 'Stamping Tax (%)',
        'isPct': true,
      },
      {
        'code': 'T6',
        'nameAr': 'ضريبة الدمغة (مبلغ)',
        'nameEn': 'Stamping Tax (Fixed)',
        'isPct': false,
      },
      {
        'code': 'T7',
        'nameAr': 'ضريبة الملاهي',
        'nameEn': 'Entertainment Tax',
        'isPct': true,
      },
      {
        'code': 'T8',
        'nameAr': 'رسم تنمية الموارد',
        'nameEn': 'Resource Dev. Fee',
        'isPct': true,
      },
      {
        'code': 'T9',
        'nameAr': 'رسم خدمة',
        'nameEn': 'Service Charges',
        'isPct': true,
      },
      {
        'code': 'T10',
        'nameAr': 'رسم المحليات',
        'nameEn': 'Municipality Fees',
        'isPct': true,
      },
      {
        'code': 'T11',
        'nameAr': 'رسم التأمين الصحي',
        'nameEn': 'Medical Insurance',
        'isPct': true,
      },
      {
        'code': 'T12',
        'nameAr': 'رسوم أخرى',
        'nameEn': 'Other Fees',
        'isPct': true,
      },
    ];

    for (final t in types) {
      await into(taxTypes).insert(
        TaxTypesCompanion.insert(
          code: t['code'] as String,
          nameAr: t['nameAr'] as String,
          nameEn: t['nameEn'] as String,
          isPercentage: t['isPct'] as bool,
        ),
      );
    }

    // Seed VAT subtypes (T1)
    final vatSubtypes = [
      {'code': 'V001', 'nameAr': 'تصدير', 'nameEn': 'Export', 'rate': 0.0},
      {
        'code': 'V002',
        'nameAr': 'تصدير لمناطق حرة',
        'nameEn': 'Export to Free Zones',
        'rate': 0.0,
      },
      {
        'code': 'V003',
        'nameAr': 'سلعة معفاة',
        'nameEn': 'Exempt Goods',
        'rate': 0.0,
      },
      {
        'code': 'V004',
        'nameAr': 'غير خاضعة',
        'nameEn': 'Non-Taxable',
        'rate': 0.0,
      },
      {
        'code': 'V005',
        'nameAr': 'إعفاء دبلوماسي',
        'nameEn': 'Diplomatic Exemption',
        'rate': 0.0,
      },
      {
        'code': 'V006',
        'nameAr': 'إعفاء أمن قومي',
        'nameEn': 'National Security',
        'rate': 0.0,
      },
      {
        'code': 'V007',
        'nameAr': 'إعفاء اتفاقيات',
        'nameEn': 'Agreement Exemption',
        'rate': 0.0,
      },
      {
        'code': 'V008',
        'nameAr': 'إعفاءات خاصة',
        'nameEn': 'Special Exemptions',
        'rate': 0.0,
      },
      {
        'code': 'V009',
        'nameAr': 'بيع عام (14%)',
        'nameEn': 'General Sale (14%)',
        'rate': 14.0,
      },
      {
        'code': 'V010',
        'nameAr': 'نسب أخرى',
        'nameEn': 'Other Rates',
        'rate': null,
      },
    ];

    for (final s in vatSubtypes) {
      await into(taxSubtypes).insert(
        TaxSubtypesCompanion.insert(
          code: s['code'] as String,
          taxTypeCode: 'T1',
          nameAr: s['nameAr'] as String,
          nameEn: s['nameEn'] as String,
          rate: Value(s['rate'] as double?),
        ),
      );
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // PRODUCT CLASSIFICATION — تصنيف المنتجات للفوترة
  // ─────────────────────────────────────────────────────────────────────────

  /// Generate EGS code for a product (EG-{TaxReg}-{ProductCode})
  Future<String> generateEgsCode(int productId) async {
    final config = await getActiveEInvoiceConfig('eta');
    if (config == null) throw Exception('إعدادات ETA غير مفعّلة');

    final product = await getProductById(productId);
    if (product == null) throw Exception('المنتج غير موجود');

    final egsCode = 'EG-${config.registrationNumber}-${product.code}';

    // Update product with EGS code
    await (update(products)..where((p) => p.id.equals(productId))).write(
      ProductsCompanion(egsCode: Value(egsCode)),
    );

    return egsCode;
  }

  /// Bulk generate EGS codes for all products without one
  Future<int> bulkGenerateEgsCodes() async {
    final config = await getActiveEInvoiceConfig('eta');
    if (config == null) throw Exception('إعدادات ETA غير مفعّلة');

    final uncodedProducts = await (select(
      products,
    )..where((p) => p.egsCode.isNull() & p.isActive.equals(true))).get();

    int count = 0;
    for (final product in uncodedProducts) {
      final egsCode = 'EG-${config.registrationNumber}-${product.code}';
      await (update(products)..where((p) => p.id.equals(product.id))).write(
        ProductsCompanion(egsCode: Value(egsCode)),
      );
      count++;
    }
    return count;
  }

  /// Get products without e-invoicing classification (for compliance check)
  Future<List<Product>> getProductsWithoutClassification() {
    return (select(products)..where(
          (p) =>
              p.egsCode.isNull() & p.gpcCode.isNull() & p.isActive.equals(true),
        ))
        .get();
  }

  // ─────────────────────────────────────────────────────────────────────────
  // INVOICE CONVERSION — تحويل الفاتورة لصيغة المنظومة
  // ─────────────────────────────────────────────────────────────────────────

  /// Build unified invoice data from a sale for e-invoicing submission
  /// This integrates with existing SalesInvoices, SalesInvoiceItems, and Products
  Future<Map<String, dynamic>> buildInvoicePayload(
    int saleId,
    String platform,
  ) async {
    final sale = await (select(
      salesInvoices,
    )..where((s) => s.id.equals(saleId))).getSingleOrNull();
    if (sale == null) throw Exception('الفاتورة غير موجودة');

    final config = await getActiveEInvoiceConfig(platform);
    if (config == null) throw Exception('إعدادات $platform غير مفعّلة');

    // Get invoice items using existing table
    final items = await (select(
      salesInvoiceItems,
    )..where((i) => i.invoiceId.equals(saleId))).get();

    // Get customer info if exists
    Map<String, dynamic>? buyerInfo;
    if (sale.customerId != null) {
      final customer = await (select(
        parties,
      )..where((p) => p.id.equals(sale.customerId!))).getSingleOrNull();
      if (customer != null) {
        buyerInfo = {
          'name': customer.name,
          'taxNumber': customer.taxId,
          'address': customer.address,
          'phone': customer.phone,
        };
      }
    }

    // Build line items with product classification
    final lineItems = <Map<String, dynamic>>[];
    final productMap = await getProductsByIds(items.map((i) => i.productId).toList());
    for (final item in items) {
      final product = productMap[item.productId];
      if (product == null) continue;

      // Determine item code based on config coding system
      String itemCode;
      String itemCodeType;
      if (config.codingSystem == 'GPC' && product.gpcCode != null) {
        itemCode = product.gpcCode!;
        itemCodeType = 'GPC';
      } else if (product.egsCode != null) {
        itemCode = product.egsCode!;
        itemCodeType = 'EGS';
      } else {
        itemCode = 'EG-${config.registrationNumber}-${product.code}';
        itemCodeType = 'EGS';
      }

      lineItems.add({
        'description': product.name,
        'itemType': itemCodeType,
        'itemCode': itemCode,
        'unitType': 'EA', // Each (default)
        'quantity': item.quantity,
        'unitPrice': item.unitPrice,
        'discount': item.discount,
        'totalAmount': item.total,
        // التصنيفُ الضريبيُّ من المنتج (‏T1/V009 — وصفٌ لا مبلغ)، أمّا
        // **النسبةُ والمبلغُ فمن لقطة البند**.
        //
        // ⚠️ كانا يُقرآن من `product.taxRate` الحيّة ويُحسب المبلغُ
        // `item.total * product.taxRate / 100`. فتعديلُ ضريبةِ صنفٍ اليومَ —
        // أو تغييرُ نسبةِ ض.ق.م — كان يُعيد إقرارَ **كلِّ فاتورةٍ قديمة** لذلك
        // الصنف بنسبةٍ لم يدفعها العميل، فيخالف المقدَّمُ ما على إيصاله وما
        // قُيِّد في الأستاذ.
        //
        // و`sales_invoice_items` يحمل العمودَين لقطةً وقتَ البيع يكتبهما
        // `createSalesInvoice` على كلّ بند — نفسُ مبدأ `cost_price` و
        // `due_date` و`rounding_adjustment` المكتوبِ في المخطَّط.
        'taxType': product.itemTaxType,
        'taxSubtype': product.itemTaxSubtype,
        'taxRate': item.taxRate,
        'taxAmount': item.taxAmount,
      });
    }

    return {
      'platform': platform,
      'documentVersion': config.documentVersion,
      'internalId': sale.invoiceNumber,
      'issueDate': sale.invoiceDate.toIso8601String(),
      'seller': {
        'registrationNumber': config.registrationNumber,
        'activityCode': config.activityCode,
        'branchId': config.branchId ?? '0',
      },
      'buyer': buyerInfo,
      'items': lineItems,
      'subtotal': sale.subtotal,
      'discount': sale.discount,
      'tax': sale.tax,
      'total': sale.total,
      'paymentMethod': sale.paymentMethod,
    };
  }
  // ─────────────────────────────────────────────────────────────────────────
  // F-09: CREDIT NOTE SUBMISSIONS — إشعارات الائتمان
  // ─────────────────────────────────────────────────────────────────────────

  /// Create a credit note submission linked to the original invoice
  /// This is used when processing sales returns with e-invoicing enabled
  Future<int> createCreditNoteSubmission({
    required int returnSaleId,
    required int originalSaleId,
    required String platform,
    String? rawRequest,
  }) async {
    // V-03: SECURITY — Credit note cap: amount must not exceed original invoice
    final originalInvoice = await (select(salesInvoices)
          ..where((s) => s.id.equals(originalSaleId)))
        .getSingleOrNull();
    final returnInvoice = await (select(salesInvoices)
          ..where((s) => s.id.equals(returnSaleId)))
        .getSingleOrNull();
    if (originalInvoice != null && returnInvoice != null) {
      if (returnInvoice.total > originalInvoice.total) {
        throw Exception(
          'مبلغ إشعار الائتمان (${returnInvoice.total}) يتجاوز مبلغ الفاتورة الأصلية (${originalInvoice.total}) — مخالفة ضريبية',
        );
      }
    }

    // Get original submission to reference its UUID
    final originalSubmission = await getSubmissionBySaleId(originalSaleId);

    return into(eInvoiceSubmissions).insert(
      EInvoiceSubmissionsCompanion.insert(
        saleId: returnSaleId,
        platform: platform,
        documentType: const Value('credit_note'),
        internalId: Value(originalSubmission?.documentUuid),
        rawRequest: Value(rawRequest),
      ),
    );
  }

  /// Build credit note payload referencing the original invoice
  Future<Map<String, dynamic>> buildCreditNotePayload({
    required int returnSaleId,
    required int originalSaleId,
    required String platform,
  }) async {
    // Build base payload from the return sale
    final payload = await buildInvoicePayload(returnSaleId, platform);

    // Override document type and add reference to original
    payload['documentType'] = 'C'; // Credit Note type for ETA
    payload['documentTypeVersion'] = payload['documentVersion'];

    // Reference original invoice UUID
    final originalSubmission = await getSubmissionBySaleId(originalSaleId);
    if (originalSubmission?.documentUuid != null) {
      payload['references'] = [originalSubmission!.documentUuid!];
    }

    return payload;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // F-10: IMMUTABLE AUDIT TRAIL — سجل تدقيق غير قابل للتعديل
  // ─────────────────────────────────────────────────────────────────────────

  /// Log a status change to the immutable audit trail (append-only)
  Future<void> logStatusChange({
    required int submissionId,
    String? oldStatus,
    required String newStatus,
    String? changedBy,
    String? notes,
  }) async {
    await customStatement(
      'INSERT INTO e_invoice_status_log (submission_id, old_status, new_status, changed_by, notes) VALUES (?, ?, ?, ?, ?)',
      [submissionId, oldStatus, newStatus, changedBy ?? 'system', notes],
    );
  }

  /// Get full audit trail for a submission (ordered chronologically)
  Future<List<Map<String, dynamic>>> getStatusAuditTrail(int submissionId) async {
    final results = await customSelect(
      'SELECT * FROM e_invoice_status_log WHERE submission_id = ? ORDER BY changed_at ASC',
      variables: [Variable(submissionId)],
    ).get();
    return results.map((r) => r.data).toList();
  }

  /// Enhanced status update with audit trail
  Future<void> updateSubmissionStatusWithAudit(
    int submissionId,
    String newStatus, {
    String? errorMessage,
    String? changedBy,
    String? notes,
  }) async {
    // Get current status
    final submission = await (select(eInvoiceSubmissions)
          ..where((s) => s.id.equals(submissionId)))
        .getSingleOrNull();
    final oldStatus = submission?.status;

    // Update status
    await updateSubmissionStatus(submissionId, newStatus, errorMessage: errorMessage);

    // Log to audit trail
    await logStatusChange(
      submissionId: submissionId,
      oldStatus: oldStatus,
      newStatus: newStatus,
      changedBy: changedBy,
      notes: notes ?? errorMessage,
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // F-14: VAT SETTLEMENT — تسوية ضريبة القيمة المضافة
  // ─────────────────────────────────────────────────────────────────────────

  /// Calculate and post VAT settlement journal entry
  /// Nets Input VAT (1204) against Output VAT (2201) for a given period
  Future<int?> settleVat({
    required DateTime periodStart,
    required DateTime periodEnd,
  }) async {
    // V-05: SECURITY — Idempotency: prevent duplicate settlement for same period
    final existingSettlement = await customSelect(
      "SELECT id FROM journal_entries WHERE reference_type = 'vat_settlement' AND entry_date BETWEEN ? AND ? LIMIT 1",
      variables: [Variable(periodStart), Variable(periodEnd)],
    ).getSingleOrNull();
    if (existingSettlement != null) {
      throw Exception(
        'تم تنفيذ تسوية ضريبية لهذه الفترة مسبقاً — لا يمكن التكرار',
      );
    }

    // Calculate Output VAT collected (credit balance on 2201)
    final outputResult = await customSelect(
      '''SELECT COALESCE(SUM(l.credit) - SUM(l.debit), 0) as net
         FROM journal_entry_lines l
         JOIN journal_entries e ON l.entry_id = e.id
         JOIN accounts a ON l.account_id = a.id
         WHERE a.code = ? AND e.entry_date BETWEEN ? AND ?''',
      variables: [
        const Variable('2201'),
        Variable(periodStart),
        Variable(periodEnd),
      ],
      readsFrom: {journalEntryLines, journalEntries, accounts},
    ).getSingle();
    final outputVat = outputResult.data['net'] as double? ?? 0;

    // Calculate Input VAT paid (debit balance on 1204)
    final inputResult = await customSelect(
      '''SELECT COALESCE(SUM(l.debit) - SUM(l.credit), 0) as net
         FROM journal_entry_lines l
         JOIN journal_entries e ON l.entry_id = e.id
         JOIN accounts a ON l.account_id = a.id
         WHERE a.code = ? AND e.entry_date BETWEEN ? AND ?''',
      variables: [
        const Variable('1204'),
        Variable(periodStart),
        Variable(periodEnd),
      ],
      readsFrom: {journalEntryLines, journalEntries, accounts},
    ).getSingle();
    final inputVat = inputResult.data['net'] as double? ?? 0;

    if (outputVat.abs() < 0.01 && inputVat.abs() < 0.01) return null;

    final netVat = outputVat - inputVat;

    // Get accounts via purpose mapping (defaults: output_vat='2121',
    // input_vat='1141' — both seeded by syncDefaultAccounts()).
    final outputVatAccount = await accountingDao.getAccountByCode(
      await accountingDao.getMappedAccountCode('output_vat', AccountingDao.accountPurposes['output_vat']!),
    );
    final inputVatAccount = await accountingDao.getAccountByCode(
      await accountingDao.getMappedAccountCode('input_vat', AccountingDao.accountPurposes['input_vat']!),
    );
    final payableAccount = await accountingDao.getAccountByCode(
      await accountingDao.getMappedAccountCode('payables', AccountingDao.accountPurposes['payables']!),
    );
    if (outputVatAccount == null || inputVatAccount == null || payableAccount == null) return null;

    final lines = <JournalLine>[];

    // Clear Output VAT: Dr Output VAT
    if (outputVat > 0) {
      lines.add(JournalLine(
        accountId: outputVatAccount.id,
        debit: outputVat,
        description: 'تسوية ضريبة مخرجات',
      ));
    }

    // Clear Input VAT: Cr Input VAT
    if (inputVat > 0) {
      lines.add(JournalLine(
        accountId: inputVatAccount.id,
        credit: inputVat,
        description: 'تسوية ضريبة مدخلات',
      ));
    }

    // Net difference to Payables (owe tax authority) or Receivables (due from authority)
    if (netVat > 0) {
      // Owe tax: Cr Payables
      lines.add(JournalLine(
        accountId: payableAccount.id,
        credit: netVat,
        description: 'مستحق لمصلحة الضرائب',
      ));
    } else if (netVat < 0) {
      // Due from authority: Dr Receivables
      final receivableAccount = await accountingDao.getAccountByCode(
        await accountingDao.getMappedAccountCode('receivables', AccountingDao.accountPurposes['receivables']!),
      );
      if (receivableAccount != null) {
        lines.add(JournalLine(
          accountId: receivableAccount.id,
          debit: netVat.abs(),
          description: 'مستحق من مصلحة الضرائب',
        ));
      }
    }

    if (lines.isEmpty) return null;

    return accountingDao.createJournalEntry(
      description: 'تسوية ضريبة القيمة المضافة — ${periodStart.month}/${periodStart.year}',
      date: periodEnd,
      lines: lines,
      referenceType: 'vat_settlement',
      isAutoPosted: true,
    );
  }

  /// Get VAT reconciliation summary for a period
  Future<Map<String, double>> getVatReconciliation({
    required DateTime periodStart,
    required DateTime periodEnd,
  }) async {
    final outputResult = await customSelect(
      '''SELECT COALESCE(SUM(l.credit) - SUM(l.debit), 0) as net
         FROM journal_entry_lines l
         JOIN journal_entries e ON l.entry_id = e.id
         JOIN accounts a ON l.account_id = a.id
         WHERE a.code = '2201' AND e.entry_date BETWEEN ? AND ?''',
      variables: [Variable(periodStart), Variable(periodEnd)],
      readsFrom: {journalEntryLines, journalEntries, accounts},
    ).getSingle();

    final inputResult = await customSelect(
      '''SELECT COALESCE(SUM(l.debit) - SUM(l.credit), 0) as net
         FROM journal_entry_lines l
         JOIN journal_entries e ON l.entry_id = e.id
         JOIN accounts a ON l.account_id = a.id
         WHERE a.code = '1204' AND e.entry_date BETWEEN ? AND ?''',
      variables: [Variable(periodStart), Variable(periodEnd)],
      readsFrom: {journalEntryLines, journalEntries, accounts},
    ).getSingle();

    final outputVat = outputResult.data['net'] as double? ?? 0;
    final inputVat = inputResult.data['net'] as double? ?? 0;

    return {
      'outputVat': outputVat,
      'inputVat': inputVat,
      'netVat': outputVat - inputVat,
    };
  }
}
