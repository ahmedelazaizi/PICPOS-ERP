import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../../core/theme/app_colors.dart';
import '../../../data/providers/providers.dart';

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
            'brokenReason': 'خطأ في الفحص: $e',
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
          title: const Text('لوحة التدقيق'),
          actions: [
            IconButton(
              icon: const Icon(PhosphorIconsBold.arrowClockwise),
              onPressed: _loadStats,
              tooltip: 'تحديث',
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
                          title: 'قيود موقّعة',
                          value: '${_hashStats?['signed'] ?? 0}',
                          color: Colors.green,
                        )),
                        const SizedBox(width: 12),
                        Expanded(child: _buildStatCard(
                          icon: PhosphorIconsBold.shieldWarning,
                          title: 'قيود غير موقّعة',
                          value: '${_hashStats?['unsigned'] ?? 0}',
                          color: Colors.orange,
                        )),
                        const SizedBox(width: 12),
                        Expanded(child: _buildStatCard(
                          icon: PhosphorIconsBold.bookOpen,
                          title: 'إجمالي القيود',
                          value: '${_hashStats?['total'] ?? 0}',
                          color: AppColors.primary,
                        )),
                        const SizedBox(width: 12),
                        Expanded(child: _buildStatCard(
                          icon: PhosphorIconsBold.warning,
                          title: 'تعارضات معلّقة',
                          value: '$_conflictCount',
                          color: _conflictCount > 0 ? Colors.red : Colors.green,
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
                                const Text('فحص سلسلة التجزئة (Hash Chain)',
                                    style: TextStyle(
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
                                      ? 'جارٍ الفحص...'
                                      : 'فحص سلامة السلسلة'),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: AppColors.primary,
                                    foregroundColor: Colors.white,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'يتحقق من أن كل قيد محاسبي يحمل توقيع SHA-256 '
                              'صحيح مبني على القيد السابق.\n'
                              'أي تعديل غير مشروع سيُكسر السلسلة.',
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
                            const Row(
                              children: [
                                Icon(PhosphorIconsBold.heartbeat,
                                    color: AppColors.primary),
                                SizedBox(width: 8),
                                Text('صحة النظام',
                                    style: TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold)),
                              ],
                            ),
                            const SizedBox(height: 16),
                            _buildHealthItem(
                              'Hash Chain SHA-256',
                              'سلسلة تجزئة غير قابلة للتعديل على كل قيد',
                              true,
                            ),
                            _buildHealthItem(
                              'Idempotency Keys',
                              'مفاتيح فريدة على 50+ endpoint لمنع التكرار',
                              true,
                            ),
                            _buildHealthItem(
                              'Dead Letter Queue',
                              'عزل العمليات الفاشلة لمراجعتها',
                              true,
                            ),
                            _buildHealthItem(
                              'SQLCipher Encryption',
                              'تشفير قاعدة البيانات المحلية',
                              true,
                            ),
                            _buildHealthItem(
                              'Secure Token Storage',
                              'تخزين التوكنات في Windows Credential Store',
                              true,
                            ),
                            _buildHealthItem(
                              'Global UUID (Products)',
                              'معرف عالمي فريد لمنع تعارض IDs',
                              true,
                            ),
                            _buildHealthItem(
                              'Global UUID (Parties)',
                              'معرف عالمي فريد للعملاء والموردين',
                              true,
                            ),
                            _buildHealthItem(
                              'Negative Stock Guard',
                              'منع البيع بالسالب (per-warehouse)',
                              true,
                            ),
                            _buildHealthItem(
                              'Trial Balance Validation',
                              'فحص تلقائي لتوازن ميزان المراجعة',
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
            : Colors.red.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isValid
              ? Colors.green.withValues(alpha: 0.3)
              : Colors.red.withValues(alpha: 0.3),
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
                color: isValid ? Colors.green : Colors.red,
                size: 28,
              ),
              const SizedBox(width: 8),
              Text(
                isValid
                    ? '✅ السلسلة سليمة — لا يوجد أي تلاعب'
                    : '❌ تم اكتشاف كسر في السلسلة!',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: isValid ? Colors.green[700] : Colors.red[700],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (result['totalEntries'] != null)
            Text('إجمالي القيود: ${result['totalEntries']}'),
          if (result['signedEntries'] != null)
            Text('قيود موقّعة: ${result['signedEntries']}'),
          if (result['unsignedEntries'] != null)
            Text('قيود غير موقّعة: ${result['unsignedEntries']}'),
          if (!isValid && result['brokenAt'] != null)
            Text('الكسر في قيد رقم: ${result['brokenAt']}',
                style: const TextStyle(
                    color: Colors.red, fontWeight: FontWeight.bold)),
          if (!isValid && result['brokenReason'] != null)
            Text('السبب: ${result['brokenReason']}',
                style: const TextStyle(color: Colors.red)),
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
            color: isActive ? Colors.green : Colors.red,
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
