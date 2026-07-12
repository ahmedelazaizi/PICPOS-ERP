import 'package:flutter/material.dart';
import '../../../core/widgets/app_toast.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../../core/theme/app_colors.dart';
import '../../../data/providers/providers.dart';
import '../../../domain/repositories/accounting_repository.dart';
import '../../../services/network_service.dart';
import 'coa_shared.dart';

// ═══════════════════════════════════════════════════════════════════════════
// COA DIALOGS — Add, Edit, Delete, Ledger
// ═══════════════════════════════════════════════════════════════════════════

/// Shows the Add Account dialog (main or sub-account).
void showAddAccountDialog(
  BuildContext context,
  WidgetRef ref,
  IAccountingRepository repo,
  int? parentId,
  Account? parentAccount, {
  VoidCallback? onAccountAdded,
}) {
  final codeCtrl = TextEditingController(
    text: parentAccount != null ? parentAccount.code : '',
  );
  final nameCtrl = TextEditingController();
  String selectedType = parentAccount?.accountType ?? 'asset';

  bool saving = false;
  showDialog(
    context: context,
    builder: (ctx) => Directionality(
      textDirection: TextDirection.rtl,
      child: StatefulBuilder(builder: (ctx, setDialogState) {
        final isSubAccount = parentId != null;
        return AlertDialog(
          title: Row(
            children: [
              Icon(
                isSubAccount ? PhosphorIconsBold.treeStructure : PhosphorIconsBold.plus,
                color: AppColors.primary,
                size: 20,
              ),
              const SizedBox(width: 8),
              Text(
                isSubAccount ? 'إضافة حساب فرعي' : 'إضافة حساب رئيسي',
                style: GoogleFonts.cairo(fontWeight: FontWeight.w700),
              ),
            ],
          ),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (isSubAccount && parentAccount != null) ...[
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.info.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppColors.info.withValues(alpha: 0.2)),
                    ),
                    child: Row(
                      children: [
                        const Icon(PhosphorIconsBold.treeStructure, size: 18, color: AppColors.info),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'حساب فرعي تحت:',
                                style: GoogleFonts.cairo(fontSize: 11, color: AppColors.info),
                              ),
                              Text(
                                '${parentAccount.code} - ${parentAccount.name}',
                                style: GoogleFonts.cairo(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.textPrimary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
                TextField(
                  controller: codeCtrl,
                  decoration: InputDecoration(
                    labelText: 'رمز الحساب',
                    hintText: isSubAccount ? 'مثال: ${parentAccount?.code ?? ""}01' : 'مثال: 1104',
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(
                    labelText: 'اسم الحساب',
                    hintText: 'مثال: حساب التأمينات',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: selectedType,
                  decoration: const InputDecoration(
                    labelText: 'نوع الحساب',
                    border: OutlineInputBorder(),
                  ),
                  items: kAccountTypeConfig.entries.map((e) {
                    return DropdownMenuItem(
                      value: e.key,
                      child: Text(e.value.label),
                    );
                  }).toList(),
                  onChanged: isSubAccount
                      ? null
                      : (v) => setDialogState(() => selectedType = v!),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('إلغاء'),
            ),
            ElevatedButton.icon(
              onPressed: saving ? null : () async {
                if (codeCtrl.text.isEmpty || nameCtrl.text.isEmpty) {
                  AppToast.show(context, 'يرجى ملء جميع الحقول', type: ToastType.error);
                  return;
                }
                final trimmedName = nameCtrl.text.trim();
                final trimmedCode = codeCtrl.text.trim();
                // Feature 005 Phase 8 — guard against creating an account
                // that duplicates an existing safe-linked account. Pre-005
                // some operators typed manual codes like "11101" matching
                // the auto-generated "111-00001" by name, producing two
                // chart rows for one logical safe and breaking the COA
                // hierarchy. Hard-block the save and tell them to use the
                // safe-management dialog instead, which mints the canonical
                // code atomically.
                final db = ref.read(databaseProvider);
                final query = db.select(db.accounts)
                  ..where((a) => a.name.equals(trimmedName))
                  ..where((a) => a.isActive.equals(true))
                  ..where((a) => parentId != null
                      ? a.parentId.equals(parentId)
                      : a.parentId.isNull())
                  ..limit(1);
                final dupSafeAccount = await query.getSingleOrNull();
                if (dupSafeAccount != null) {
                  if (context.mounted) {
                    AppToast.show(
                      context,
                      'يوجد حساب باسم "$trimmedName" تحت نفس الأب '
                      '(الكود ${dupSafeAccount.code}). '
                      'لتجنّب التكرار، أنشئ الصندوق من شاشة "إدارة الصناديق" '
                      'وسيتم ربط الحساب تلقائياً.',
                      type: ToastType.error,
                    );
                  }
                  return;
                }
                setDialogState(() => saving = true);
                try {
                  await repo.createAccount(
                    code: trimmedCode,
                    name: trimmedName,
                    accountType: selectedType,
                    parentId: parentId,
                  );
                  if (ctx.mounted) Navigator.pop(ctx);
                  // Notify connected clients
                  NetworkService.instance.broadcastChange('accounts');
                  onAccountAdded?.call();
                  if (context.mounted) {
                    AppToast.show(
                      context,
                      isSubAccount ? 'تم إضافة الحساب الفرعي بنجاح' : 'تم إضافة الحساب الرئيسي بنجاح',
                    );
                  }
                } catch (e) {
                  if (ctx.mounted) setDialogState(() => saving = false);
                  if (context.mounted) {
                    AppToast.show(context, 'خطأ: ${e.toString()}', type: ToastType.error);
                  }
                }
              },
              icon: const Icon(PhosphorIconsBold.plus, size: 16),
              label: Text(isSubAccount ? 'إضافة فرعي' : 'إضافة'),
            ),
          ],
        );
      }),
    ),
  );
}

/// Shows the Edit Account dialog.
void showEditAccountDialog(
  BuildContext context,
  IAccountingRepository repo,
  Account account,
) {
  final nameCtrl = TextEditingController(text: account.name);
  final codeCtrl = TextEditingController(text: account.code);
  bool isActive = account.isActive;
  bool isHiddenFromEntries = account.isHiddenFromEntries;
  bool saving = false;

  showDialog(
    context: context,
    builder: (ctx) => Directionality(
      textDirection: TextDirection.rtl,
      child: StatefulBuilder(builder: (ctx, setDialogState) {
        return AlertDialog(
          title: Row(
            children: [
              const Icon(PhosphorIconsBold.pencilSimple, color: AppColors.primary, size: 20),
              const SizedBox(width: 8),
              Text('تعديل حساب', style: GoogleFonts.cairo(fontWeight: FontWeight.w700)),
            ],
          ),
          content: SizedBox(
            width: 400,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: codeCtrl,
                  decoration: const InputDecoration(labelText: 'رمز الحساب', border: OutlineInputBorder()),
                  enabled: !account.isSystem,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(labelText: 'اسم الحساب', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 12),
                SwitchListTile(
                  title: const Text('نشط'),
                  value: isActive,
                  onChanged: (v) => setDialogState(() => isActive = v),
                  contentPadding: EdgeInsets.zero,
                ),
                SwitchListTile(
                  title: const Text('إخفاء من سندات القيد'),
                  subtitle: Text('لن يظهر الحساب عند إنشاء قيود يدوية',
                      style: GoogleFonts.cairo(fontSize: 11, color: AppColors.textMuted)),
                  value: isHiddenFromEntries,
                  onChanged: (v) => setDialogState(() => isHiddenFromEntries = v),
                  contentPadding: EdgeInsets.zero,
                  activeThumbColor: AppColors.warning,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('إلغاء'),
            ),
            ElevatedButton(
              onPressed: saving ? null : () async {
                setDialogState(() => saving = true);
                try {
                  await repo.updateAccount(
                    account.id,
                    name: nameCtrl.text.trim(),
                    code: account.isSystem ? null : codeCtrl.text.trim(),
                    isActive: isActive,
                    isHiddenFromEntries: isHiddenFromEntries,
                  );
                  if (ctx.mounted) Navigator.pop(ctx);
                  // Notify connected clients
                  NetworkService.instance.broadcastChange('accounts');
                  if (context.mounted) {
                    AppToast.show(context, 'تم تحديث الحساب');
                  }
                } catch (e) {
                  if (ctx.mounted) setDialogState(() => saving = false);
                  if (context.mounted) {
                    AppToast.show(context, 'خطأ: ${e.toString()}', type: ToastType.error);
                  }
                }
              },
              child: const Text('حفظ'),
            ),
          ],
        );
      }),
    ),
  );
}

/// Shows the Delete confirmation dialog.
void confirmDeleteAccount(
  BuildContext context,
  IAccountingRepository repo,
  Account account,
) {
  showDialog(
    context: context,
    builder: (ctx) => Directionality(
      textDirection: TextDirection.rtl,
      child: AlertDialog(
        title: const Text('تأكيد الحذف'),
        content: Text('هل أنت متأكد من حذف حساب "${account.name}"؟\n\nسيتم حذف جميع الحسابات الفرعية التابعة.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            onPressed: () async {
              try {
                await repo.deleteAccount(account.id);
                if (ctx.mounted) Navigator.pop(ctx);
                // Notify connected clients
                NetworkService.instance.broadcastChange('accounts');
                if (context.mounted) {
                  AppToast.show(context, 'تم حذف الحساب', type: ToastType.warning);
                }
              } catch (e) {
                if (ctx.mounted) Navigator.pop(ctx);
                if (context.mounted) {
                  AppToast.show(context, 'خطأ: ${e.toString()}', type: ToastType.error);
                }
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
            child: const Text('حذف'),
          ),
        ],
      ),
    ),
  );
}

/// Shows the Account Ledger dialog.
void showAccountLedger(
  BuildContext context,
  IAccountingRepository repo,
  Account account,
) {
  final now = DateTime.now();
  var fromDate = DateTime(now.year, now.month, 1);
  var toDate = now;

  showDialog(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setDialogState) => Directionality(
        textDirection: TextDirection.rtl,
        child: Dialog(
          child: Container(
            width: 700,
            constraints: const BoxConstraints(maxHeight: 550),
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(PhosphorIconsBold.book, color: AppColors.primary, size: 22),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'دفتر أستاذ: ${account.code} - ${account.name}',
                        style: GoogleFonts.cairo(fontSize: 16, fontWeight: FontWeight.w700),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(PhosphorIconsBold.x, size: 18),
                      onPressed: () => Navigator.pop(ctx),
                    ),
                  ],
                ),
                const Divider(),
                Row(
                  children: [
                    const Icon(PhosphorIconsBold.calendarBlank, size: 18, color: AppColors.textMuted),
                    const SizedBox(width: 8),
                    InkWell(
                      onTap: () async {
                        final picked = await showDateRangePicker(
                          context: ctx,
                          firstDate: DateTime(2020),
                          lastDate: DateTime(2030),
                          initialDateRange: DateTimeRange(start: fromDate, end: toDate),
                          locale: const Locale('ar'),
                        );
                        if (picked != null) {
                          setDialogState(() {
                            fromDate = picked.start;
                            toDate = picked.end;
                          });
                        }
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          border: Border.all(color: AppColors.border),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          '${fromDate.day}/${fromDate.month}/${fromDate.year} — ${toDate.day}/${toDate.month}/${toDate.year}',
                          style: GoogleFonts.cairo(fontSize: 13, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ),
                    const Spacer(),
                  ],
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: FutureBuilder<List<Map<String, dynamic>>>(
                    key: ValueKey('ledger_${fromDate}_$toDate'),
                    future: repo.getAccountLedger(account.id, fromDate, toDate),
                    builder: (context, snapshot) {
                      if (!snapshot.hasData) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      final ledger = snapshot.data!;
                      if (ledger.length <= 1) {
                        return Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(PhosphorIconsBold.bookOpen, size: 48, color: AppColors.textMuted),
                              const SizedBox(height: 8),
                              Text('لا توجد حركات في هذه الفترة',
                                  style: GoogleFonts.cairo(color: AppColors.textMuted)),
                            ],
                          ),
                        );
                      }
                      return SingleChildScrollView(
                        child: Table(
                          columnWidths: const {
                            0: FixedColumnWidth(90),
                            1: FlexColumnWidth(),
                            2: FixedColumnWidth(80),
                            3: FixedColumnWidth(80),
                            4: FixedColumnWidth(90),
                          },
                          border: TableBorder.all(color: AppColors.border, width: 0.5),
                          children: [
                            TableRow(
                              decoration: BoxDecoration(color: AppColors.primary.withValues(alpha: 0.06)),
                              children: [
                                _ledgerCell('التاريخ', isHeader: true),
                                _ledgerCell('البيان', isHeader: true),
                                _ledgerCell('مدين', isHeader: true),
                                _ledgerCell('دائن', isHeader: true),
                                _ledgerCell('الرصيد', isHeader: true),
                              ],
                            ),
                            ...ledger.map((row) {
                              final date = row['entry_date'] as DateTime;
                              final isOpening = row['is_opening'] == true;
                              return TableRow(
                                decoration: isOpening
                                    ? BoxDecoration(color: AppColors.info.withValues(alpha: 0.05))
                                    : null,
                                children: [
                                  _ledgerCell(isOpening ? '' : '${date.day}/${date.month}'),
                                  _ledgerCell(
                                    isOpening ? 'رصيد أول المدة' : '${row['description'] ?? ''}',
                                  ),
                                  _ledgerCell(
                                    isOpening ? '' : formatAccountAmount(row['debit'] as double),
                                  ),
                                  _ledgerCell(
                                    isOpening ? '' : formatAccountAmount(row['credit'] as double),
                                  ),
                                  _ledgerCell(
                                    formatAccountAmount(row['balance'] as double),
                                    isBold: true,
                                  ),
                                ],
                              );
                            }),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

Widget _ledgerCell(String text, {bool isHeader = false, bool isBold = false}) {
  return Padding(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
    child: Text(
      text,
      style: GoogleFonts.cairo(
        fontSize: isHeader ? 11 : 12,
        fontWeight: isHeader || isBold ? FontWeight.w700 : FontWeight.normal,
        color: isHeader ? AppColors.primary : AppColors.textPrimary,
      ),
      textAlign: TextAlign.center,
    ),
  );
}
