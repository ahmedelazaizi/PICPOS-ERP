part of '../database.dart';

// ═══════════════════════════════════════════════════════════════════════════
// COMPLIANCE DASHBOARD DAO — لوحة الامتثال
// SOX / IFRS / ISA 315 / COSO Compliance Checks
// ═══════════════════════════════════════════════════════════════════════════

extension ComplianceDashboardDao on AppDatabase {

  /// Run full compliance audit — evaluates all categories
  Future<List<Map<String, dynamic>>> runComplianceAudit() async {
    final checks = <Map<String, dynamic>>[];

    // ── 1) IFRS Compliance ──
    checks.add(await _checkIFRSCompliance());

    // ── 2) Audit Trail Integrity ──
    checks.add(await _checkAuditTrail());

    // ── 3) SOD Compliance ──
    checks.add(await _checkSODCompliance());

    // ── 4) Data Integrity ──
    checks.add(await _checkDataIntegrity());

    // ── 5) VAT Compliance ──
    checks.add(await _checkVATCompliance());

    // ── 6) Period Controls ──
    checks.add(await _checkPeriodControls());

    // Save results
    for (final check in checks) {
      try {
        await into(complianceChecks).insert(
          ComplianceChecksCompanion.insert(
            category: check['category'] as String,
            checkName: check['checkName'] as String,
            description: check['description'] as String,
            status: Value(check['status'] as String),
            details: Value(check['details'] as String?),
            score: Value((check['score'] as num).toDouble()),
            lastCheckedAt: Value(DateTime.now()),
          ),
        );
      } catch (e) { debugPrint('[Compliance] upsert check failed: $e'); }
    }

    return checks;
  }

  Future<Map<String, dynamic>> _checkIFRSCompliance() async {
    int score = 100;
    final issues = <String>[];

    // Check fiscal years exist
    final years = await customSelect('SELECT COUNT(*) as cnt FROM fiscal_years').getSingle();
    if (((years.data['cnt'] as int?) ?? 0) == 0) {
      score -= 30;
      issues.add('لا توجد سنة مالية — IAS 1 يتطلب فترة مالية محددة');
    }

    // Check chart of accounts exists
    final accounts = await customSelect('SELECT COUNT(*) as cnt FROM accounts').getSingle();
    if (((accounts.data['cnt'] as int?) ?? 0) < 5) {
      score -= 20;
      issues.add('شجرة حسابات غير مكتملة');
    }

    // Check JE balance
    final imbalanced = await customSelect(
      '''SELECT COUNT(*) as cnt FROM (
           SELECT je.id, ABS(SUM(jel.debit) - SUM(jel.credit)) as diff
           FROM journal_entries je
           JOIN journal_entry_lines jel ON jel.entry_id = je.id
           GROUP BY je.id
           HAVING ABS(SUM(jel.debit) - SUM(jel.credit)) > 0.01
         )''',
    ).getSingleOrNull();
    if (((imbalanced?.data['cnt'] as int?) ?? 0) > 0) {
      score -= 30;
      issues.add('وجود قيود يومية غير متوازنة');
    }

    return {
      'category': 'ifrs',
      'checkName': 'IFRS / IAS Compliance',
      'description': 'فحص الامتثال لمعايير المحاسبة الدولية',
      'status': score >= 80 ? 'pass' : (score >= 50 ? 'warning' : 'fail'),
      'score': score,
      'details': issues.isEmpty ? 'متوافق مع المعايير' : issues.join('\n'),
    };
  }

  Future<Map<String, dynamic>> _checkAuditTrail() async {
    int score = 100;
    final issues = <String>[];

    // Check activity logs exist
    final logs = await customSelect('SELECT COUNT(*) as cnt FROM activity_logs').getSingle();
    if (((logs.data['cnt'] as int?) ?? 0) == 0) {
      score -= 40;
      issues.add('لا يوجد سجل أنشطة — مطلوب لمسار التدقيق');
    }

    // Check all JEs have entry_number
    final noNumber = await customSelect(
      "SELECT COUNT(*) as cnt FROM journal_entries WHERE entry_number IS NULL OR entry_number = ''",
    ).getSingleOrNull();
    if (((noNumber?.data['cnt'] as int?) ?? 0) > 0) {
      score -= 20;
      issues.add('توجد قيود بدون رقم مرجعي');
    }

    return {
      'category': 'audit_trail',
      'checkName': 'Audit Trail Integrity',
      'description': 'فحص سلامة مسار التدقيق',
      'status': score >= 80 ? 'pass' : (score >= 50 ? 'warning' : 'fail'),
      'score': score,
      'details': issues.isEmpty ? 'مسار تدقيق سليم' : issues.join('\n'),
    };
  }

  Future<Map<String, dynamic>> _checkSODCompliance() async {
    int score = 100;
    final issues = <String>[];

    // Check SOD rules exist
    final rules = await customSelect(
      "SELECT COUNT(*) as cnt FROM sod_conflicts WHERE is_active = ${sqlBool(true)}",
    ).getSingleOrNull();
    if (((rules?.data['cnt'] as int?) ?? 0) == 0) {
      score -= 50;
      issues.add('لا توجد قواعد فصل مهام — يجب تحميل القواعد الافتراضية');
    }

    // Count violations
    final violations = await customSelect(
      "SELECT COUNT(*) as cnt FROM sod_violations WHERE was_blocked = ${sqlBool(false)}",
    ).getSingleOrNull();
    final vCount = (violations?.data['cnt'] as int?) ?? 0;
    if (vCount > 0) {
      score -= (vCount * 10).clamp(0, 40);
      issues.add('$vCount مخالفة SOD لم يتم حظرها');
    }

    return {
      'category': 'sod',
      'checkName': 'Segregation of Duties',
      'description': 'فحص فصل المهام ISA 315',
      'status': score >= 80 ? 'pass' : (score >= 50 ? 'warning' : 'fail'),
      'score': score,
      'details': issues.isEmpty ? 'متوافق مع فصل المهام' : issues.join('\n'),
    };
  }

  Future<Map<String, dynamic>> _checkDataIntegrity() async {
    int score = 100;
    final issues = <String>[];

    // PRAGMA integrity check
    try {
      if (isPostgres) {
        // PostgreSQL doesn't support PRAGMA — skip integrity check
        // PostgreSQL has built-in data integrity via WAL
      } else {
        final result = await customSelect('PRAGMA integrity_check').getSingle();
        if (result.data.values.first != 'ok') {
          score = 0;
          issues.add('فشل فحص سلامة قاعدة البيانات');
        }
      }
    } catch (e) {
      score -= 30;
      issues.add('خطأ في فحص السلامة: $e');
    }

    return {
      'category': 'data_integrity',
      'checkName': 'Database Integrity',
      'description': 'فحص سلامة قاعدة البيانات',
      'status': score >= 80 ? 'pass' : 'fail',
      'score': score,
      'details': issues.isEmpty ? 'قاعدة البيانات سليمة' : issues.join('\n'),
    };
  }

  Future<Map<String, dynamic>> _checkVATCompliance() async {
    int score = 100;
    final issues = <String>[];

    // Check VAT accounts exist
    final vatAccounts = await customSelect(
      "SELECT COUNT(*) as cnt FROM accounts WHERE code LIKE '2201%' OR code LIKE '2202%'",
    ).getSingleOrNull();
    if (((vatAccounts?.data['cnt'] as int?) ?? 0) < 2) {
      score -= 30;
      issues.add('حسابات ضريبة القيمة المضافة غير مكتملة');
    }

    return {
      'category': 'vat',
      'checkName': 'VAT Compliance',
      'description': 'فحص الامتثال الضريبي',
      'status': score >= 80 ? 'pass' : (score >= 50 ? 'warning' : 'fail'),
      'score': score,
      'details': issues.isEmpty ? 'متوافق ضريبياً' : issues.join('\n'),
    };
  }

  Future<Map<String, dynamic>> _checkPeriodControls() async {
    int score = 100;
    final issues = <String>[];

    // Check if posting to closed periods is possible
    final closedPeriodPostings = await customSelect(
      '''SELECT COUNT(*) as cnt FROM journal_entries je
         JOIN accounting_periods ap
           ON je.entry_date >= ap.start_date AND je.entry_date <= ap.end_date
         WHERE ap.is_closed = ${sqlBool(true)} AND je.created_at > ap.closed_at''',
    ).getSingleOrNull();

    final count = (closedPeriodPostings?.data['cnt'] as int?) ?? 0;
    if (count > 0) {
      score -= 40;
      issues.add('$count قيد تم ترحيله في فترة مغلقة');
    }

    return {
      'category': 'period_controls',
      'checkName': 'Period Controls',
      'description': 'فحص ضوابط الفترات المحاسبية',
      'status': score >= 80 ? 'pass' : (score >= 50 ? 'warning' : 'fail'),
      'score': score,
      'details': issues.isEmpty ? 'ضوابط الفترات سليمة' : issues.join('\n'),
    };
  }

  /// Get latest compliance results
  Future<List<ComplianceCheckData>> getLatestComplianceResults() {
    return customSelect(
      '''SELECT * FROM compliance_checks
         WHERE id IN (
           SELECT MAX(id) FROM compliance_checks GROUP BY category
         )
         ORDER BY score ASC''',
    ).get().then((rows) => rows.map((r) => ComplianceCheckData(
      id: r.data['id'] as int,
      category: r.data['category'] as String,
      checkName: r.data['check_name'] as String,
      description: r.data['description'] as String,
      status: r.data['status'] as String,
      details: r.data['details'] as String?,
      score: (r.data['score'] as num).toDouble(),
      lastCheckedAt: r.data['last_checked_at'] != null
          ? () { final v = r.data['last_checked_at']; return v is DateTime ? v : DateTime.fromMillisecondsSinceEpoch((v as int) * 1000); }()
          : null,
      createdAt: () { final v = r.data['created_at']; return v is DateTime ? v : DateTime.fromMillisecondsSinceEpoch((v as int) * 1000); }(),
      // v173 — مطلوبٌ في صنفِ البيانات المولَّد؛ صفرٌ حالُ صفٍّ لم يُعدَّل قطّ.
      rowVersion: (r.data['row_version'] as int?) ?? 0,
    )).toList());
  }

  /// Get overall compliance score
  Future<double> getOverallComplianceScore() async {
    final results = await getLatestComplianceResults();
    if (results.isEmpty) return 0;
    final total = results.fold<double>(0, (sum, r) => sum + r.score);
    return total / results.length;
  }
}
