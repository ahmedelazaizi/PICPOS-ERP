// ignore_for_file: avoid_dynamic_calls
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart' hide TextDirection;
import '../../core/theme/app_colors.dart';
import '../../data/providers/repository_providers.dart';

/// Exchange Rate Management Screen — إدارة أسعار الصرف
class ExchangeRateScreen extends ConsumerStatefulWidget {
  const ExchangeRateScreen({super.key});

  @override
  ConsumerState<ExchangeRateScreen> createState() => _ExchangeRateScreenState();
}

class _ExchangeRateScreenState extends ConsumerState<ExchangeRateScreen> {
  final _dateFormat = DateFormat('yyyy/MM/dd');

  @override
  Widget build(BuildContext context) {
    final repo = ref.watch(accountingRepositoryProvider);
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: AppColors.surface,
        body: Column(
          children: [
            _buildHeader(context, repo),
            Expanded(child: _buildCurrencyList(repo)),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context, dynamic repo) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF00695C), Color(0xFF00897B)],
          begin: AlignmentDirectional.topEnd,
          end: AlignmentDirectional.bottomStart,
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(PhosphorIconsBold.currencyCircleDollar, color: Colors.white, size: 24),
          ),
          const SizedBox(width: 14),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('أسعار الصرف',
                  style: GoogleFonts.cairo(fontSize: 20, fontWeight: FontWeight.w800, color: Colors.white)),
              Text('IAS 21 — العملات الأجنبية وأسعار التحويل',
                  style: GoogleFonts.cairo(fontSize: 11, color: Colors.white.withValues(alpha: 0.7))),
            ],
          ),
          const Spacer(),
          ElevatedButton.icon(
            onPressed: () => _showAddCurrencyDialog(context, repo),
            icon: const Icon(PhosphorIconsBold.plus, size: 18),
            label: Text('عملة جديدة', style: GoogleFonts.cairo(fontWeight: FontWeight.w700)),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: const Color(0xFF00695C),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCurrencyList(dynamic repo) {
    return FutureBuilder<List<dynamic>>(
      future: repo.getActiveCurrencies(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
        final currencies = snapshot.data!;
        if (currencies.isEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(PhosphorIconsBold.currencyCircleDollar, size: 64, color: AppColors.textMuted),
                const SizedBox(height: 16),
                Text('لا توجد عملات', style: GoogleFonts.cairo(fontSize: 16, color: AppColors.textMuted)),
              ],
            ),
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: currencies.length,
          itemBuilder: (context, index) => _buildCurrencyCard(currencies[index], repo),
        );
      },
    );
  }

  Widget _buildCurrencyCard(dynamic currency, dynamic repo) {
    final isDefault = currency.isDefault;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: isDefault ? AppColors.success : AppColors.border,
          width: isDefault ? 2 : 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(currency.symbol,
                  style: GoogleFonts.cairo(fontSize: 20, fontWeight: FontWeight.w800, color: AppColors.primary)),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(currency.name, style: GoogleFonts.cairo(fontSize: 14, fontWeight: FontWeight.w700)),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppColors.textMuted.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(currency.code,
                            style: GoogleFonts.cairo(fontSize: 10, fontWeight: FontWeight.w600)),
                      ),
                      if (isDefault) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppColors.success.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text('أساسية',
                              style: GoogleFonts.cairo(fontSize: 10, color: AppColors.success, fontWeight: FontWeight.w700)),
                        ),
                      ],
                    ],
                  ),
                  Text('سعر الصرف: ${currency.exchangeRate}',
                      style: GoogleFonts.cairo(fontSize: 12, color: AppColors.textMuted)),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(PhosphorIconsBold.pencilSimple, size: 18),
              tooltip: 'تحديث سعر الصرف',
              onPressed: () => _showUpdateRateDialog(context, currency, repo),
            ),
          ],
        ),
      ),
    );
  }

  void _showAddCurrencyDialog(BuildContext context, dynamic repo) {
    final codeCtrl = TextEditingController();
    final nameCtrl = TextEditingController();
    final symbolCtrl = TextEditingController();
    final rateCtrl = TextEditingController(text: '1.0');
    bool saving = false;

    showDialog(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: StatefulBuilder(builder: (ctx, setDialogState) {
          return AlertDialog(
            title: Row(
              children: [
                const Icon(PhosphorIconsBold.currencyCircleDollar, color: AppColors.primary, size: 20),
                const SizedBox(width: 8),
                Text('عملة جديدة', style: GoogleFonts.cairo(fontWeight: FontWeight.w700)),
              ],
            ),
            content: SizedBox(
              width: 400,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(controller: codeCtrl, decoration: const InputDecoration(labelText: 'رمز العملة (مثال: USD)')),
                  const SizedBox(height: 12),
                  TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'اسم العملة')),
                  const SizedBox(height: 12),
                  TextField(controller: symbolCtrl, decoration: const InputDecoration(labelText: 'الرمز (مثال: \$)')),
                  const SizedBox(height: 12),
                  TextField(controller: rateCtrl, keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'سعر الصرف مقابل العملة الأساسية')),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
              ElevatedButton(
                onPressed: saving ? null : () async {
                  setDialogState(() => saving = true);
                  try {
                    Navigator.pop(ctx);
                    setState(() {});
                  } catch (_) {
                    setDialogState(() => saving = false);
                    rethrow;
                  }
                },
                child: const Text('إضافة'),
              ),
            ],
          );
        }),
      ),
    );
  }

  void _showUpdateRateDialog(BuildContext context, dynamic currency, dynamic repo) {
    final rateCtrl = TextEditingController(text: currency.exchangeRate.toString());
    bool saving = false;

    showDialog(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: StatefulBuilder(builder: (ctx, setDialogState) {
          return AlertDialog(
            title: Text('تحديث سعر ${currency.name}', style: GoogleFonts.cairo(fontWeight: FontWeight.w700)),
            content: TextField(
              controller: rateCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'سعر الصرف الجديد'),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
              ElevatedButton(
                onPressed: saving ? null : () async {
                  setDialogState(() => saving = true);
                  try {
                    final rate = double.tryParse(rateCtrl.text) ?? 1.0;
                    await repo.recordExchangeRate(currencyId: currency.id, rate: rate);
                    if (ctx.mounted) Navigator.pop(ctx);
                    setState(() {});
                  } catch (_) {
                    setDialogState(() => saving = false);
                    rethrow;
                  }
                },
                child: const Text('تحديث'),
              ),
            ],
          );
        }),
      ),
    );
  }
}