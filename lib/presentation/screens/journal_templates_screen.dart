import 'package:picpos_erp/core/i18n/tr.dart';
import 'package:picpos_erp/core/constants/app_constants.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/theme/app_colors.dart';
import '../widgets/permission_guard.dart';
import '../../core/permissions/permission_codes.dart';
import '../../domain/repositories/accounting_repository.dart';
import '../../data/providers/providers.dart';
import 'create_journal_template_dialog.dart';
import '../../core/widgets/app_toast.dart';

/// Screen to list, create, and manage journal entry templates
class JournalTemplatesScreen extends ConsumerStatefulWidget {
  const JournalTemplatesScreen({super.key});

  @override
  ConsumerState<JournalTemplatesScreen> createState() => _JournalTemplatesScreenState();
}

class _JournalTemplatesScreenState extends ConsumerState<JournalTemplatesScreen> {
  @override
  Widget build(BuildContext context) {
    final accountingRepo = ref.watch(accountingRepositoryProvider);

    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        title: Text(
          tr('قوالب القيود'),
          style: GoogleFonts.cairo(fontWeight: FontWeight.w700),
        ),
        centerTitle: true,
        elevation: 0,
        actions: [
          PermissionGuard(
            permission: PermissionCodes.accountingManage,
            fallback: const SizedBox.shrink(),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: ElevatedButton.icon(
                onPressed: () => _showCreateTemplateDialog(context, accountingRepo),
                icon: const Icon(PhosphorIconsBold.plus, size: 18),
                label:  Text(tr('قالب جديد')),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
              ),
            ),
          ),
        ],
      ),
      body: StreamBuilder<List<JournalEntryTemplateData>>(
        stream: accountingRepo.watchAllTemplates(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text(tr('خطأ: {p0}', {'p0': snapshot.error}), style: GoogleFonts.cairo()));
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final templates = snapshot.data!;
          if (templates.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(PhosphorIconsLight.notebook, size: 80, color: AppColors.textMuted.withValues(alpha: 0.3)),
                  const SizedBox(height: 16),
                  Text(
                    tr('لا توجد قوالب قيود'),
                    style: GoogleFonts.cairo(fontSize: 18, fontWeight: FontWeight.w600, color: AppColors.textMuted),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    tr('استخدم القوالب لتسريع إنشاء القيود المتكررة كرواتب الموظفين أو الإيجارات.'),
                    style: GoogleFonts.cairo(fontSize: 14, color: AppColors.textMuted),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.all(24),
            itemCount: templates.length,
            separatorBuilder: (context, index) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final template = templates[index];
              return _buildTemplateCard(context, accountingRepo, template);
            },
          );
        },
      ),
    );
  }

  Widget _buildTemplateCard(BuildContext context, IAccountingRepository accountingRepo, JournalEntryTemplateData template) {
    return Card(
      elevation: 0,
      color: Theme.of(context).cardColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: AppColors.border.withValues(alpha: 0.5)),
      ),
      child: ExpansionTile(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        collapsedShape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: template.isActive 
                    ? AppColors.primary.withValues(alpha: 0.1) 
                    : AppColors.textMuted.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                PhosphorIconsBold.notebook,
                size: 20,
                color: template.isActive ? AppColors.primary : AppColors.textMuted,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    template.name,
                    style: GoogleFonts.cairo(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: template.isActive ? AppColors.textPrimary : AppColors.textMuted,
                    ),
                  ),
                  if (template.description?.isNotEmpty == true)
                    Text(
                      template.description!,
                      style: GoogleFonts.cairo(
                        fontSize: 12,
                        color: AppColors.textMuted,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),
            if (!template.isActive)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.textMuted.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(tr('غير نشط'), style: GoogleFonts.cairo(fontSize: 11, color: AppColors.textMuted)),
              ),
          ],
        ),
        children: [
          const Divider(height: 1),
          // View Template Lines
          FutureBuilder<List<Map<String, dynamic>>>(
            future: accountingRepo.getTemplateLinesWithAccounts(template.id),
            builder: (context, snapshot) {
              if (!snapshot.hasData) {
                return const Padding(
                  padding: EdgeInsets.all(32),
                  child: Center(child: CircularProgressIndicator()),
                );
              }
              
              final lines = snapshot.data!;
              double totalDebit = 0;
              double totalCredit = 0;
              for (final line in lines) {
                totalDebit += line['debit'] as double;
                totalCredit += line['credit'] as double;
              }

              return Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      decoration: BoxDecoration(
                        border: Border.all(color: AppColors.border),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Table(
                          columnWidths: const {
                            0: FixedColumnWidth(100),
                            1: FlexColumnWidth(),
                            2: FlexColumnWidth(),
                            3: FixedColumnWidth(100),
                            4: FixedColumnWidth(100),
                          },
                          border: TableBorder.symmetric(
                            inside: BorderSide(color: AppColors.border.withValues(alpha: 0.5)),
                          ),
                          children: [
                            TableRow(
                              decoration: const BoxDecoration(color: AppColors.surface),
                              children: [
                                _tableHeaderCell(tr('رمز الحساب')),
                                _tableHeaderCell(tr('اسم الحساب')),
                                _tableHeaderCell(tr('البيان')),
                                _tableHeaderCell(tr('مدين')),
                                _tableHeaderCell(tr('دائن')),
                              ],
                            ),
                            ...lines.map((line) => TableRow(
                              children: [
                                _tableCell(line['account_code']?.toString() ?? ''),
                                _tableCell(line['account_name']?.toString() ?? ''),
                                _tableCell(line['description']?.toString() ?? ''),
                                _tableCell((line['debit'] as double) > 0 ? (line['debit'] as double).toStringAsFixed(AppConstants.decimalPlaces) : ''),
                                _tableCell((line['credit'] as double) > 0 ? (line['credit'] as double).toStringAsFixed(AppConstants.decimalPlaces) : ''),
                              ],
                            )),
                            // Totals
                            TableRow(
                              decoration: BoxDecoration(color: AppColors.success.withValues(alpha: 0.05)),
                              children: [
                                _tableHeaderCell(''),
                                _tableHeaderCell(tr('الإجمالي'), color: AppColors.success),
                                _tableHeaderCell(''),
                                _tableHeaderCell(totalDebit.toStringAsFixed(AppConstants.decimalPlaces), color: AppColors.success),
                                _tableHeaderCell(totalCredit.toStringAsFixed(AppConstants.decimalPlaces), color: AppColors.success),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton.icon(
                          onPressed: () => _deleteTemplate(context, accountingRepo, template),
                          icon: const Icon(PhosphorIconsBold.trash, size: 16, color: AppColors.error),
                          label: Text(tr('حذف'), style: GoogleFonts.cairo(color: AppColors.error, fontWeight: FontWeight.w600)),
                          style: TextButton.styleFrom(
                            foregroundColor: AppColors.error,
                            backgroundColor: AppColors.error.withValues(alpha: 0.1),
                          ),
                        ),
                        const SizedBox(width: 12),
                        ElevatedButton.icon(
                          onPressed: () => _showCreateTemplateDialog(context, accountingRepo, templateToEdit: template, lines: lines),
                          icon: const Icon(PhosphorIconsBold.pencilSimple, size: 16),
                          label: Text(tr('تعديل القالب'), style: GoogleFonts.cairo(fontWeight: FontWeight.w600)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            foregroundColor: Colors.white,
                            elevation: 0,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _tableHeaderCell(String text, {Color? color}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      child: Text(
        text,
        style: GoogleFonts.cairo(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: color ?? AppColors.textPrimary,
        ),
        textAlign: TextAlign.center,
      ),
    );
  }

  Widget _tableCell(String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      child: Text(
        text,
        style: GoogleFonts.cairo(
          fontSize: 12,
          fontWeight: FontWeight.w500,
          color: AppColors.textPrimary,
        ),
        textAlign: TextAlign.center,
      ),
    );
  }

  Future<void> _deleteTemplate(BuildContext context, IAccountingRepository accountingRepo, JournalEntryTemplateData template) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: Text(tr('تأكيد الحذف'), style: GoogleFonts.cairo(fontWeight: FontWeight.w700, color: AppColors.error)),
          content: Text(tr('هل أنت متأكد من حذف القالب "{p0}"؟', {'p0': template.name}), style: GoogleFonts.cairo()),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child:  Text(tr('إلغاء')),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.error, foregroundColor: Colors.white),
              onPressed: () => Navigator.pop(ctx, true),
              child:  Text(tr('حذف')),
            ),
          ],
        ),
      ),
    );

    if (confirm == true) {
      await accountingRepo.deleteJournalTemplate(template.id);
      if (!context.mounted) return;
      AppToast.show(context, tr('تم حذف القالب بنجاح'), type: ToastType.warning);
      }
    }

  void _showCreateTemplateDialog(BuildContext context, IAccountingRepository accountingRepo, {JournalEntryTemplateData? templateToEdit, List<Map<String, dynamic>>? lines}) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => CreateJournalTemplateDialog(
        templateToEdit: templateToEdit,
        initialLines: lines,
      ),
    );
  }
}
