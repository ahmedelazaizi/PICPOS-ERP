import 'package:flutter/material.dart';
import 'package:ural_erp/core/widgets/app_toast.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../../core/theme/app_colors.dart';
import '../../picpos_shell/picpos_surface.dart';

import '../../../data/providers/providers.dart';
import '../../../services/client_write_interceptor.dart';
import '../../../services/invoice_generator.dart';
import '../../../../../../core/constants/app_constants.dart';

class TreasuryClosingScreen extends ConsumerStatefulWidget {
  const TreasuryClosingScreen({super.key});

  @override
  ConsumerState<TreasuryClosingScreen> createState() =>
      _TreasuryClosingScreenState();
}

class _TreasuryClosingScreenState extends ConsumerState<TreasuryClosingScreen> {
  final Map<int, TextEditingController> _controllers = {};
  final Map<int, double> _actualBalances = {};
  bool _isProcessing = false;

  @override
  void dispose() {
    for (var controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final safesAsync = ref.watch(scopedSafesProvider);

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text(
            'محضر جرد الخزينة (إقفال اليوم)',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          ),
          backgroundColor: AppColors.primary,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(PhosphorIconsBold.arrowRight, color: Colors.white),
            onPressed: () => Navigator.pop(context),
          ),
        ),
        body: safesAsync.when(
          data: (safes) {
            final activeSafes = safes.where((s) => s.balance.abs() > 0.001).toList();

            if (activeSafes.isEmpty) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(PhosphorIconsBold.checkCircle, color: AppColors.success.withValues(alpha: 0.8), size: 64),
                      const SizedBox(height: 16),
                      const Text(
                        'جميع الخزائن تمت تسويتها',
                        style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'لا توجد خزائن حالية تتطلب إقفال مباشر. الأرصدة مصفرة (تم إقفالها مسبقاً عبر ورديات الكاشير).',
                        style: TextStyle(color: AppColors.textMuted, fontSize: 14),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              );
            }

            return Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildHeaderInfo(),
                  const SizedBox(height: 24),
                  Expanded(
                    child: ListView.builder(
                      itemCount: activeSafes.length,
                      itemBuilder: (context, index) {
                        final safe = activeSafes[index];
                        return _buildSafeAuditCard(safe);
                      },
                    ),
                  ),
                  const SizedBox(height: 24),
                  _buildFooterActions(activeSafes),
                ],
              ),
            );
          },
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (err, stack) => Center(child: Text('خطأ: $err')),
        ),
      ),
    );
  }

  Widget _buildHeaderInfo() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.info.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.info.withValues(alpha: 0.3)),
      ),
      child: const Row(
        children: [
          Icon(PhosphorIconsBold.info, color: AppColors.info),
          SizedBox(width: 12),
          Expanded(
            child: Text(
              'يرجى إدخال المبلغ الفعلي الموجود في كل خزينة لمطابقته مع رصيد النظام.',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSafeAuditCard(SafeData safe) {
    if (!_controllers.containsKey(safe.id)) {
      _controllers[safe.id] = TextEditingController();
    }

    final systemBalance = safe.balance;
    final actualBalance = _actualBalances[safe.id] ?? 0.0;
    final variance = actualBalance - systemBalance;
    final hasVariance = variance.abs() > 0.001;

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: context.picposHairline),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: safe.safeType == 'bank'
                    ? AppColors.info.withValues(alpha: 0.1)
                    : AppColors.warning.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                safe.safeType == 'bank'
                    ? PhosphorIconsBold.bank
                    : PhosphorIconsBold.money,
                color: safe.safeType == 'bank'
                    ? AppColors.info
                    : AppColors.warning,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              flex: 2,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    safe.name,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  Text(
                    safe.safeType == 'bank' ? 'حساب بنكي' : 'خزينة نقدية',
                    style: const TextStyle(
                      color: AppColors.textMuted,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              flex: 2,
              child: Column(
                children: [
                  const Text(
                    'رصيد النظام',
                    style: TextStyle(fontSize: 12, color: AppColors.textMuted),
                  ),
                  Text(
                    '${systemBalance.toStringAsFixed(AppConstants.decimalPlaces)} ${AppConstants.currencySymbolEn}',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              flex: 2,
              child: TextField(
                controller: _controllers[safe.id],
                keyboardType: TextInputType.number,
                textAlign: TextAlign.center,
                decoration: const InputDecoration(
                  labelText: 'المبلغ الفعلي',
                  hintText: '0.00',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                onChanged: (value) {
                  setState(() {
                    _actualBalances[safe.id] = double.tryParse(value) ?? 0.0;
                  });
                },
              ),
            ),
            const SizedBox(width: 24),
            Expanded(
              flex: 1,
              child: Column(
                children: [
                  const Text(
                    'الفارق',
                    style: TextStyle(fontSize: 12, color: AppColors.textMuted),
                  ),
                  Text(
                    '${variance > 0 ? '+' : ''}${variance.toStringAsFixed(AppConstants.decimalPlaces)}',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: !hasVariance
                          ? AppColors.success
                          : (variance < 0
                                ? AppColors.error
                                : AppColors.warning),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFooterActions(List<SafeData> safes) {
    double totalSystem = safes.fold(0, (sum, safe) => sum + safe.balance);
    double totalActual = _actualBalances.values.fold(
      0,
      (sum, val) => sum + val,
    );
    double totalVariance = totalActual - totalSystem;

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, -5),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'إجمالي الفوارق',
                  style: TextStyle(color: AppColors.textMuted, fontSize: 14),
                ),
                Text(
                  '${totalVariance.toStringAsFixed(AppConstants.decimalPlaces)} ${AppConstants.currencySymbolEn}',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: totalVariance == 0
                        ? AppColors.success
                        : (totalVariance < 0
                              ? AppColors.error
                              : AppColors.warning),
                  ),
                ),
              ],
            ),
          ),
          ElevatedButton(
            onPressed: _isProcessing ? null : () => _confirmAndClose(safes),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 20),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: _isProcessing
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 2,
                    ),
                  )
                : const Text(
                    'اعتماد الإقفال وترحيل الفوارق',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
          ),
          const SizedBox(width: 16),
          // Print Button
          OutlinedButton.icon(
            onPressed: _isProcessing ? null : () => _printReport(safes),
            icon: const Icon(PhosphorIconsBold.printer),
            label: const Text('طباعة التقرير'),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _printReport(List<SafeData> safes) async {
    final settingsRepo = ref.read(settingsRepositoryProvider);
    final companyName = await settingsRepo.getSetting('company_name');

    // Prepare data
    double totalSystem = 0;
    double totalActual = 0;
    final List<Map<String, dynamic>> safeData = [];

    for (final safe in safes) {
      final actual = _actualBalances[safe.id] ?? 0.0;
      final system = safe.balance;
      final variance = actual - system;

      totalSystem += system;
      totalActual += actual;

      safeData.add({
        'name': safe.name,
        'system': system,
        'actual': actual,
        'variance': variance,
      });
    }

    final totalVariance = totalActual - totalSystem;

    // Print
    await InvoiceGenerator.printTreasuryClosingReport(
      safeData: safeData,
      totalSystem: totalSystem,
      totalActual: totalActual,
      totalVariance: totalVariance,
      companyName: companyName,
      employeeName: 'مدير النظام',
    );
  }

  Future<void> _confirmAndClose(List<SafeData> safes) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('تأكيد إقفال المحاسبة'),
        content: const Text(
          'هل أنت متأكد من اعتماد الأرصدة المدخلة وإقفال اليوم المالي؟ سيتم تصفير أرصدة الخزائن المرحلة.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
            child: const Text('تأكيد'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      setState(() => _isProcessing = true);
      try {
        final treasuryRepo = ref.read(treasuryRepositoryProvider);

        for (final safe in safes) {
          final actual = _actualBalances[safe.id] ?? 0.0;
          final system = safe.balance;
          final variance = actual - system;

          // If there's a variance, record it as an expense or income
          if (variance.abs() > 0.001) {
            if (variance < 0) {
              // Deficiency - record as payment/expense
              // ── Client mode: route to server ──
              final intercepted = await ClientWriteInterceptor.createExpense(
                amount: variance.abs(),
                category: 'عجز خزينة',
                description: 'عجز عند إقفال اليوم لـ ${safe.name}',
              );
              if (intercepted == null) {
                await treasuryRepo.createPaymentVoucher(
                  amount: variance.abs(),
                  category: 'عجز خزينة',
                  description: 'عجز عند إقفال اليوم لـ ${safe.name}',
                  safeId: safe.id,
                );
              }
            } else {
              // Surplus - record as receipt/income
              // ── Client mode: route to server ──
              final intercepted = await ClientWriteInterceptor.createReceipt(
                amount: variance,
                category: 'زيادة خزينة',
                description: 'زيادة عند إقفال اليوم لـ ${safe.name}',
              );
              if (intercepted == null) {
                await treasuryRepo.createReceiptVoucher(
                  amount: variance,
                  category: 'زيادة خزينة',
                  description: 'زيادة عند إقفال اليوم لـ ${safe.name}',
                  safeId: safe.id,
                );
              }
            }
          }

          // Close the safe (zero out for next session)
          await treasuryRepo.closeSafe(safe.id);
        }

        if (mounted) {
          AppToast.show(
            context,
            'تم إقفال اليوم المالي واعتماد الجرد بنجاح',
            type: ToastType.success,
          );
          Navigator.pop(context);
        }
      } catch (e) {
        if (mounted) {
          AppToast.show(
            context,
            'خطأ أثناء الإقفال: $e',
            type: ToastType.error,
          );
        }
      } finally {
        if (mounted) setState(() => _isProcessing = false);
      }
    }
  }
}
