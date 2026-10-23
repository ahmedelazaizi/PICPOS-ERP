import 'package:picpos_erp/core/i18n/tr.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/logging/diagnostic_logger.dart';
import '../../../core/permissions/permission_codes.dart';
import '../../../core/utils/uuid_v7.dart';
import '../../../data/providers/providers.dart';
import '../../../services/client_write_interceptor.dart';
import '../../../services/generators/thermal_voucher_generator.dart';
import '../providers/pos_notification_provider.dart';
import 'pos_previous_expenses_dialog.dart';

/// حقل وصف سند المصروف — مستخرج كودجت top-level عشان يتعمله اختبار wiring
/// مباشر (هل العلم فعلاً بيتحكّم في ظهور الحقل ولّا لأ) من غير ما نركّب
/// `PosExpenseDialog` كله أو نعمل fake لـ `IAuthRepository`. الجلب
/// غير المتزامن للصلاحية (`_checkPermissions`) نفس شكل `_canSelectType`
/// المجاور — مالوش اختبار مخصص هنا برضه لنفس السبب.
///
/// الحقل مختفي تماماً من غير الصلاحية بدل ما يتعطّل، عشان الكاشير ما
/// يحسّش إنه في حاجة ناقصة كان المفروض يملاها (نفس معاملة _canSelectType).
@visibleForTesting
Widget buildPosExpenseDescriptionField({
  required bool canEnter,
  required TextEditingController controller,
}) {
  if (!canEnter) return const SizedBox.shrink();
  return Column(
    children: [
      const SizedBox(height: 16),
      TextField(
        controller: controller,
        decoration: InputDecoration(
          labelText: tr('الوصف (اختياري)'),
          prefixIcon: const Icon(PhosphorIconsBold.note),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
    ],
  );
}

/// Dialog for creating quick expense vouchers from the POS
class PosExpenseDialog extends ConsumerStatefulWidget {
  const PosExpenseDialog({super.key});

  /// Static helper to show the dialog
  static Future<void> show(BuildContext context) async {
    return showDialog<void>(
      context: context,
      builder: (context) => const PosExpenseDialog(),
    );
  }

  @override
  ConsumerState<PosExpenseDialog> createState() => _PosExpenseDialogState();
}

class _PosExpenseDialogState extends ConsumerState<PosExpenseDialog> {
  final _amountController = TextEditingController();
  final _descriptionController = TextEditingController();
  String _selectedCategory = 'other_expense';
  bool _canSelectType = false;
  // إضافة وصف حر على سند المصروف — كانت دايماً ظاهرة من غير أي فحص، رغم إن
  // حقل النوع جنبها (_canSelectType) مربوط بصلاحيته من زمان. نفس المعاملة.
  bool _canEnterDescription = false;
  bool _isLoading = true;

  // #4: Employee/salary fields
  int? _selectedEmployeeId;
  String? _selectedEmployeeName;
  String _salarySubType = 'salary'; // salary, advance, deduction

  final List<Map<String, String>> _salarySubTypes = [
    {'value': 'salary', 'label': tr('راتب')},
    {'value': 'advance', 'label': tr('سلفة')},
    {'value': 'deduction', 'label': tr('خصم')},
  ];

  final List<Map<String, String>> _categories = [
    {'value': 'salary', 'label': tr('رواتب')},
    {'value': 'rent', 'label': tr('إيجار')},
    {'value': 'utilities', 'label': tr('فواتير (كهرباء/ماء)')},
    {'value': 'supplies', 'label': tr('مستلزمات')},
    {'value': 'other_expense', 'label': tr('مصروفات أخرى')},
  ];

  @override
  void initState() {
    super.initState();
    _checkPermissions();
  }

  Future<void> _checkPermissions() async {
    // Guarded against exceptions. The original implementation let
    // `userHasPermission` propagate errors — on a broken PG install
    // (where the permissions query could throw with a 42601 syntax
    // error) the exception escaped initState, `_isLoading` stayed `true`
    // forever, and the dialog showed only a spinner with no way to
    // dismiss or add an expense. The user reported this as
    // "المصروف السريع مش بيظهر — بيحصل فيه مشكلة".
    try {
      final authRepo = ref.read(authRepositoryProvider);
      final authState = ref.read(authProvider);
      final userId = authState.user?.id;
      if (userId != null) {
        _canSelectType = await authRepo.userHasPermission(
          userId,
          'pos_expense_type_select',
        );
        _canEnterDescription = await authRepo.userHasPermission(
          userId,
          PermissionCodes.posExpenseDescription,
        );
      }
    } catch (e) {
      debugPrint('[PosExpenseDialog] permission check failed: $e');
      // Fall through with both flags false so the dialog still opens —
      // user can add an expense with the default category and no note.
      _canSelectType = false;
      _canEnterDescription = false;
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _amountController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      // Keep the dialog frame so the user can still dismiss it if the
      // async permission check is taking too long or hangs — the previous
      // bare `Center(CircularProgressIndicator)` had no close affordance
      // and no modal barrier dismiss, trapping the user on click-through.
      return Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          content:  SizedBox(
            width: 200,
            height: 100,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const CircularProgressIndicator(),
                const SizedBox(height: 12),
                Text(tr('جاري التحميل...'), style: const TextStyle(fontSize: 13)),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child:  Text(tr('إلغاء')),
            ),
          ],
        ),
      );
    }

    return Directionality(
      textDirection: TextDirection.rtl,
      child: AlertDialog(
        title: Row(
          children: [
            const Icon(PhosphorIconsBold.money, color: AppColors.error),
            const SizedBox(width: 8),
             Text(tr('إضافة مصروف')),
            const Spacer(),
            TextButton.icon(
              onPressed: () {
                Navigator.pop(context);
                PosPreviousExpensesDialog.show(context);
              },
              icon: const Icon(
                PhosphorIconsBold.clockCounterClockwise,
                size: 18,
              ),
              label:  Text(
                tr('المصروفات السابقة'),
                style: const TextStyle(fontSize: 12),
              ),
              style: TextButton.styleFrom(foregroundColor: AppColors.info),
            ),
          ],
        ),
        content: SizedBox(
          width: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Category dropdown - only if user has permission
              if (_canSelectType)
                DropdownButtonFormField<String>(
                  initialValue: _selectedCategory,
                  decoration: InputDecoration(
                    labelText: tr('نوع المصروف'),
                    prefixIcon: const Icon(PhosphorIconsBold.tag),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  items: _categories
                      .map(
                        (cat) => DropdownMenuItem<String>(
                          value: cat['value']!,
                          child: Text(cat['label']!),
                        ),
                      )
                      .toList(),
                  onChanged: (value) {
                    setState(
                      () => _selectedCategory = value ?? 'other_expense',
                    );
                  },
                ),
              if (_canSelectType) const SizedBox(height: 16),

              // Amount field - always shown
              TextField(
                controller: _amountController,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                autofocus: true,
                decoration: InputDecoration(
                  labelText: tr('المبلغ'),
                  prefixIcon: const Icon(
                    PhosphorIconsBold.currencyCircleDollar,
                  ),
                  suffixText: AppConstants.currencySymbolAr,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),

              buildPosExpenseDescriptionField(
                canEnter: _canEnterDescription,
                controller: _descriptionController,
              ),

              // #4: Employee selector when salary is chosen
              if (_selectedCategory == 'salary') ...[
                const SizedBox(height: 16),

                // Salary sub-type
                DropdownButtonFormField<String>(
                  initialValue: _salarySubType,
                  decoration: InputDecoration(
                    labelText: tr('نوع الصرف'),
                    prefixIcon: const Icon(PhosphorIconsBold.wallet),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  items: _salarySubTypes
                      .map((t) => DropdownMenuItem<String>(
                            value: t['value']!,
                            child: Text(t['label']!),
                          ))
                      .toList(),
                  onChanged: (v) => setState(() => _salarySubType = v ?? 'salary'),
                ),

                const SizedBox(height: 16),

                // Employee search dropdown
                _buildEmployeeSelector(),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child:  Text(tr('إلغاء')),
          ),
          ElevatedButton.icon(
            onPressed: _saveExpense,
            icon: const Icon(PhosphorIconsBold.check),
            label:  Text(tr('حفظ المصروف')),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
          ),
        ],
      ),
    );
  }

  Future<void> _saveExpense() async {
    final amount = double.tryParse(_amountController.text);
    if (amount == null || amount <= 0) {
      showPosToast(
        context,
        ref,
        tr('أدخل مبلغ صحيح'),
        type: PosNotificationType.warning,
      );
      return;
    }

    // #4: Validate employee selection for salary expenses
    if (_selectedCategory == 'salary' && _selectedEmployeeId == null) {
      showPosToast(
        context,
        ref,
        tr('اختر الموظف أولاً'),
        type: PosNotificationType.warning,
      );
      return;
    }

    // #4: Build description with employee info for salary
    String? description = _descriptionController.text.isEmpty
        ? null
        : _descriptionController.text;
    if (_selectedCategory == 'salary' && _selectedEmployeeName != null) {
      final subLabel = _salarySubTypes.firstWhere(
        (t) => t['value'] == _salarySubType,
        orElse: () => {'label': tr('راتب')},
      )['label']!;
      description = '$subLabel - $_selectedEmployeeName${description != null ? ' - $description' : ''}';
    }

    final treasuryRepo = ref.read(treasuryRepositoryProvider);
    final authState = ref.read(authProvider);

    await DiagnosticLogger.log('EXPENSE',
        'start category=$_selectedCategory amount=$amount');

    try {
      final defaultSafe = await treasuryRepo.getDefaultSafeByType('cash');
      await DiagnosticLogger.log('EXPENSE',
          'step1 defaultCashSafe=${defaultSafe?.id ?? "NULL"}');
      if (defaultSafe == null) {
        if (mounted) {
          showPosToast(
            context,
            ref,
            tr('لا يوجد خزنة افتراضية! يرجى إعداد خزنة من الإعدادات'),
            type: PosNotificationType.error,
          );
        }
        return;
      }

      // Resolve cost center AND branchId from active branch (same pattern as checkout).
      // P5 FIX: branchId was missing — server uses it to scope the expense to
      // the correct branch and to validate the safe + cost-center FKs. Without
      // it the server falls back to the default branch which may not exist on
      // a fresh server install, producing a confusing 404.
      int? costCenterId;
      int? branchId;
      try {
        final branchRepo = ref.read(branchRepositoryProvider);
        final activeBranch = await branchRepo.getActiveBranch();
        costCenterId = activeBranch?.costCenterId;
        branchId = activeBranch?.id;
      } catch (_) {}
      await DiagnosticLogger.log('EXPENSE',
          'step2 costCenterId=$costCenterId branchId=$branchId');

      // ── Client mode: route to server (fire-and-forget for outbox) ──
      // Previously this branch REPLACED the local insert in client
      // mode — so a successful server-call made the client write NOTHING
      // locally. The cashier's own shift reconciliation + "previous
      // expenses" dialog both read ONLY from local `safe_transactions`,
      // so the expense was invisible to the cashier immediately after
      // save (it only appeared once the server-push came back through
      // the pull-sync, which could be minutes). User symptom: "المصروفات
      // مش بتظهر فى ديالوج المصروفات بالنسبة للكاشير".
      //
      // New behaviour: ALWAYS write locally so the cashier sees their
      // expense immediately, and QUEUE the server call via the
      // interceptor (fire-and-forget). Both paths share the SAME
      // globalId so the server dedupes on insert AND the pull-sync
      // reconciler merges the two rows — previously each side minted
      // its own UUID, producing a duplicate voucher after sync.
      final sharedGlobalId = UuidV7.generate();
      try {
        ClientWriteInterceptor.createExpense(
          amount: amount,
          category: _selectedCategory,
          description: description,
          userId: authState.user?.id,
          costCenterId: costCenterId,
          branchId: branchId,
          globalId: sharedGlobalId,
        ).catchError((e) {
          debugPrint('[PosExpenseDialog] background server queue failed: $e');
          return null;
        });
        await DiagnosticLogger.log('EXPENSE',
            'step3 server queue scheduled (fire-and-forget) gid=$sharedGlobalId');
      } catch (e, st) {
        await DiagnosticLogger.log('EXPENSE',
            'step3 server queue FAILED (continuing local): $e\n$st');
      }

      int savedTransactionId = 0;
      try {
        savedTransactionId = await treasuryRepo.createPaymentVoucher(
          amount: amount,
          category: _selectedCategory,
          description: description,
          safeId: defaultSafe.id,
          userId: authState.user?.id,
          costCenterId: costCenterId,
          globalId: sharedGlobalId,
        );
        await DiagnosticLogger.log('EXPENSE',
            'step4 local createPaymentVoucher OK txId=$savedTransactionId');
      } catch (e, st) {
        await DiagnosticLogger.log('EXPENSE',
            'step4 local createPaymentVoucher FAILED: $e\nSTACK:\n$st');
        rethrow;
      }

      // Issue 12 (Feature 019): auto-print the expense voucher when the
      // operator's `auto_print_receipt` setting is on. Mirrors the pattern
      // already established for receipt + payment vouchers in
      // payment_voucher_dialog.dart. Best-effort: any printing failure is
      // logged but never blocks the dialog close — operator already saw the
      // success toast and can reprint from the previous-expenses screen.
      try {
        final settingsRepo = ref.read(settingsRepositoryProvider);
        final autoPrintRaw = await settingsRepo.getSetting('auto_print_receipt');
        if (autoPrintRaw?.toLowerCase() == 'true' && savedTransactionId > 0) {
          final transaction = await treasuryRepo.getTransactionById(savedTransactionId);
          final companyName = await settingsRepo.getSetting('company_name');
          final companyPhone = await settingsRepo.getSetting('company_phone');
          final companyAddress = await settingsRepo.getSetting('company_address');
          await ThermalVoucherGenerator.printVoucher(
            voucherNumber: transaction?.voucherNumber ?? 'EXP-$savedTransactionId',
            voucherType: 'payment',
            date: DateTime.now(),
            amount: amount,
            companyName: companyName,
            companyPhone: companyPhone,
            companyAddress: companyAddress,
            description: description,
            safeName: defaultSafe.name,
            employeeName: authState.user?.displayName,
          );
          await DiagnosticLogger.log('EXPENSE',
              'step5 auto-print OK voucher=${transaction?.voucherNumber}');
        }
      } catch (e, st) {
        await DiagnosticLogger.log('EXPENSE',
            'step5 auto-print FAILED (continuing): $e\n$st');
      }

      if (mounted) {
        Navigator.pop(context);
        showPosToast(
          context,
          ref,
          tr('تم إنشاء سند مصروف {p0} د.أ', {'p0': amount.toStringAsFixed(AppConstants.decimalPlaces)}),
          type: PosNotificationType.success,
        );
      }
    } catch (e, st) {
      await DiagnosticLogger.log('EXPENSE',
          'OUTER CATCH: $e\nSTACK:\n$st');
      if (mounted) {
        showPosToast(
          context,
          ref,
          tr('خطأ في حفظ المصروف: {e}', {'e': e}),
          type: PosNotificationType.error,
        );
      }
    }
  }
  /// #4: Build employee search/select dropdown
  Widget _buildEmployeeSelector() {
    final usersAsync = ref.watch(allUsersProvider);
    return usersAsync.when(
      loading: () => const LinearProgressIndicator(),
      error: (e, _) => Text(tr('خطأ: {e}', {'e': e})),
      data: (users) {
        return Autocomplete<UserWithRole>(
          optionsBuilder: (textEditingValue) {
            if (textEditingValue.text.isEmpty) return users;
            final q = textEditingValue.text.toLowerCase();
            return users.where((u) =>
                u.user.displayName.toLowerCase().contains(q) ||
                u.user.username.toLowerCase().contains(q));
          },
          displayStringForOption: (u) => u.user.displayName,
          onSelected: (u) => setState(() {
            _selectedEmployeeId = u.user.id;
            _selectedEmployeeName = u.user.displayName;
          }),
          fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
            return TextField(
              controller: controller,
              focusNode: focusNode,
              decoration: InputDecoration(
                labelText: tr('اختر الموظف *'),
                prefixIcon: const Icon(PhosphorIconsBold.user),
                hintText: tr('ابحث عن موظف...'),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                suffixIcon: _selectedEmployeeName != null
                    ? IconButton(
                        icon: const Icon(PhosphorIconsBold.x, size: 18),
                        onPressed: () {
                          controller.clear();
                          setState(() {
                            _selectedEmployeeId = null;
                            _selectedEmployeeName = null;
                          });
                        },
                      )
                    : null,
              ),
            );
          },
        );
      },
    );
  }
}
