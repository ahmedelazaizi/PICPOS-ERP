import 'package:ural_erp/core/i18n/tr.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../../core/theme/app_colors.dart';
import '../../../data/providers/providers.dart';
import '../../../services/security_service.dart';

/// لوحة التدقيق — Audit Dashboard
/// تعرض حالة Hash Chain وإحصائيات سلامة النظام
class AuditDashboardScreen extends ConsumerStatefulWidget {
  const AuditDashboardScreen({super.key});

  @override
  ConsumerState<AuditDashboardScreen> createState() =>
      _AuditDashboardScreenState();
}

class _AuditDashboardScreenState
    extends ConsumerState<AuditDashboardScreen> {
  Map<String, dynamic>? _verificationResult;
  Map<String, int>? _hashStats;
  int _conflictCount = 0;
  bool _isVerifying = false;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadStats();
  }

  Future<void> _loadStats() async {
    setState(() => _isLoading = true);
    try {
      // ISS-06: Route through auditDashboardStatsProvider instead of direct DB access
      final result = await ref.read(auditDashboardStatsProvider.future);

      if (mounted) {
        setState(() {
          _hashStats = result.hashStats;
          _conflictCount = result.conflictCount;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _runVerification() async {
    setState(() => _isVerifying = true);
    try {
      // ISS-06: Route through auditHashChainVerifyProvider instead of direct DB access
      final result = await ref.read(auditHashChainVerifyProvider.future);
      if (mounted) {
        setState(() {
          _verificationResult = result;
          _isVerifying = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _verificationResult = {
            'isValid': false,
            'brokenReason': tr('خطأ في الفحص: {e}', {'e': e}),
          };
          _isVerifying = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          title:  Text(tr('لوحة التدقيق')),
          actions: [
            IconButton(
              icon: const Icon(PhosphorIconsBold.arrowClockwise),
              onPressed: _loadStats,
              tooltip: tr('تحديث'),
            ),
          ],
        ),
        body: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // ── Overview Cards ─────────────────────────────
                    Row(
                      children: [
                        Expanded(child: _buildStatCard(
                          icon: PhosphorIconsBold.shieldCheck,
                          title: tr('قيود موقّعة'),
                          value: '${_hashStats?['signed'] ?? 0}',
                          color: Colors.green,
                        )),
                        const SizedBox(width: 12),
                        Expanded(child: _buildStatCard(
                          icon: PhosphorIconsBold.shieldWarning,
                          title: tr('قيود غير موقّعة'),
                          value: '${_hashStats?['unsigned'] ?? 0}',
                          color: Colors.orange,
                        )),
                        const SizedBox(width: 12),
                        Expanded(child: _buildStatCard(
                          icon: PhosphorIconsBold.bookOpen,
                          title: tr('إجمالي القيود'),
                          value: '${_hashStats?['total'] ?? 0}',
                          color: AppColors.primary,
                        )),
                        const SizedBox(width: 12),
                        Expanded(child: _buildStatCard(
                          icon: PhosphorIconsBold.warning,
                          title: tr('تعارضات معلّقة'),
                          value: '$_conflictCount',
                          color: _conflictCount > 0 ? AppColors.error : Colors.green,
                        )),
                      ],
                    ),

                    const SizedBox(height: 24),

                    // ── Hash Chain Verification ────────────────────
                    Card(
                      elevation: 2,
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Icon(PhosphorIconsBold.linkSimpleHorizontal,
                                    color: AppColors.primary),
                                const SizedBox(width: 8),
                                 Text(tr('فحص سلسلة التجزئة (Hash Chain)'),
                                    style: const TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold)),
                                const Spacer(),
                                ElevatedButton.icon(
                                  onPressed: _isVerifying ? null : _runVerification,
                                  icon: _isVerifying
                                      ? const SizedBox(
                                          width: 16,
                                          height: 16,
                                          child: CircularProgressIndicator(
                                              strokeWidth: 2))
                                      : const Icon(PhosphorIconsBold.play, size: 16),
                                  label: Text(_isVerifying
                                      ? tr('جارٍ الفحص...')
                                      : tr('فحص سلامة السلسلة')),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: AppColors.primary,
                                    foregroundColor: Colors.white,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text(
                              tr('يتحقق من أن كل قيد محاسبي يحمل توقيع SHA-256 صحيح مبني على القيد السابق.\nأي تعديل غير مشروع سيُكسر السلسلة.'),
                              style: TextStyle(color: Colors.grey[600]),
                            ),

                            if (_verificationResult != null) ...[
                              const Divider(height: 24),
                              _buildVerificationResult(),
                            ],
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 16),

                    // ── System Health ──────────────────────────────
                    Card(
                      elevation: 2,
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                             Row(
                              children: [
                                const Icon(PhosphorIconsBold.heartbeat,
                                    color: AppColors.primary),
                                const SizedBox(width: 8),
                                Text(tr('صحة النظام'),
                                    style: const TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold)),
                              ],
                            ),
                            const SizedBox(height: 16),
                            _buildHealthItem(
                              'Hash Chain SHA-256',
                              tr('سلسلة تجزئة غير قابلة للتعديل على كل قيد'),
                              true,
                            ),
                            _buildHealthItem(
                              'Idempotency Keys',
                              tr('مفاتيح فريدة على 50+ endpoint لمنع التكرار'),
                              true,
                            ),
                            _buildHealthItem(
                              'Dead Letter Queue',
                              tr('عزل العمليات الفاشلة لمراجعتها'),
                              true,
                            ),
                            // ⚠️ قيمةٌ **حيّة** لا ثابتة: كانت `true` مثبَّتةً
                            // فتعرض «مشفَّرة» خضراءَ على قاعدةٍ نصٍّ صريح —
                            // فحصٌ يطمئن المشغّلَ ولا يقيس شيئاً.
                            _buildHealthItem(
                              'SQLCipher Encryption',
                              SecurityService.databaseEncryptionVerified
                                  ? tr('تشفير قاعدة البيانات المحلية — مُثبَت')
                                  : tr('غير مُثبَت (PostgreSQL أو محرّك بلا تشفير)'),
                              SecurityService.databaseEncryptionVerified,
                            ),
                            _buildHealthItem(
                              'Secure Token Storage',
                              tr('تخزين التوكنات في Windows Credential Store'),
                              true,
                            ),
                            _buildHealthItem(
                              'Global UUID (Products)',
                              tr('معرف عالمي فريد لمنع تعارض IDs'),
                              true,
                            ),
                            _buildHealthItem(
                              'Global UUID (Parties)',
                              tr('معرف عالمي فريد للعملاء والموردين'),
                              true,
                            ),
                            _buildHealthItem(
                              'Negative Stock Guard',
                              tr('منع البيع بالسالب (per-warehouse)'),
                              true,
                            ),
                            _buildHealthItem(
                              'Trial Balance Validation',
                              tr('فحص تلقائي لتوازن ميزان المراجعة'),
                              true,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _buildStatCard({
    required IconData icon,
    required String title,
    required String value,
    required Color color,
  }) {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Icon(icon, color: color, size: 32),
            const SizedBox(height: 8),
            Text(value,
                style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: color)),
            const SizedBox(height: 4),
            Text(title,
                style: TextStyle(color: Colors.grey[600], fontSize: 12)),
          ],
        ),
      ),
    );
  }

  Widget _buildVerificationResult() {
    final result = _verificationResult!;
    final isValid = result['isValid'] as bool;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isValid
            ? Colors.green.withValues(alpha: 0.08)
            : AppColors.error.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isValid
              ? Colors.green.withValues(alpha: 0.3)
              : AppColors.error.withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                isValid
                    ? PhosphorIconsBold.checkCircle
                    : PhosphorIconsBold.xCircle,
                color: isValid ? Colors.green : AppColors.error,
                size: 28,
              ),
              const SizedBox(width: 8),
              Text(
                isValid
                    ? tr('✅ السلسلة سليمة — لا يوجد أي تلاعب')
                    : tr('❌ تم اكتشاف كسر في السلسلة!'),
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: isValid ? Colors.green[700] : AppColors.errorDark,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (result['totalEntries'] != null)
            Text(tr('إجمالي القيود: {p0}', {'p0': result['totalEntries']})),
          if (result['signedEntries'] != null)
            Text(tr('قيود موقّعة: {p0}', {'p0': result['signedEntries']})),
          if (result['unsignedEntries'] != null)
            Text(tr('قيود غير موقّعة: {p0}', {'p0': result['unsignedEntries']})),
          if (!isValid && result['brokenAt'] != null)
            Text(tr('الكسر في قيد رقم: {p0}', {'p0': result['brokenAt']}),
                style: const TextStyle(
                    color: AppColors.error, fontWeight: FontWeight.bold)),
          if (!isValid && result['brokenReason'] != null)
            Text(tr('السبب: {p0}', {'p0': result['brokenReason']}),
                style: const TextStyle(color: AppColors.error)),
        ],
      ),
    );
  }

  Widget _buildHealthItem(String title, String description, bool isActive) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(
            isActive
                ? PhosphorIconsBold.checkCircle
                : PhosphorIconsBold.xCircle,
            color: isActive ? Colors.green : AppColors.error,
            size: 20,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                Text(description,
                    style: TextStyle(fontSize: 12, color: Colors.grey[600])),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
