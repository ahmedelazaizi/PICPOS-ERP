import 'package:ural_erp/core/i18n/tr.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../../core/theme/app_colors.dart';
import '../../../data/database/database.dart';
import '../../../domain/repositories/accounting_repository.dart';
import 'coa_rollup.dart';
import 'coa_shared.dart';

// ═══════════════════════════════════════════════════════════════════════════
// COA TREE NODE — Recursive hierarchical account tree rendering
// ═══════════════════════════════════════════════════════════════════════════

/// A single account tree entry. Renders recursively for child accounts.
class CoaTreeNode extends StatelessWidget {
  final Account account;
  final AccountTypeInfo typeInfo;
  final List<Account> allTypeAccounts;
  final int depth;
  final IAccountingRepository repo;
  final Set<int> expandedAccounts;
  final VoidCallback onToggle;
  final void Function(Account account, String action) onAction;
  // Spec 135 BUG-E — rolled-up balances so a parent node shows the subtotal
  // of its whole subtree, not just its own (usually zero) balance.
  final CoaRollup rollup;

  const CoaTreeNode({
    super.key,
    required this.account,
    required this.typeInfo,
    required this.allTypeAccounts,
    required this.depth,
    required this.repo,
    required this.expandedAccounts,
    required this.onToggle,
    required this.onAction,
    required this.rollup,
  });

  @override
  Widget build(BuildContext context) {
    final children = allTypeAccounts.where((a) => a.parentId == account.id).toList();
    final hasChildren = children.isNotEmpty;
    final isNodeExpanded = expandedAccounts.contains(account.id);

    return Column(
      children: [
        InkWell(
          onTap: hasChildren
              ? onToggle
              : () => onAction(account, 'ledger'),
          child: Container(
            padding: EdgeInsets.only(
              right: 20.0 + (depth * 28),
              left: 12,
              top: 8,
              bottom: 8,
            ),
            decoration: BoxDecoration(
              color: depth > 0
                  ? typeInfo.color.withValues(alpha: 0.02 * depth)
                  : null,
              border: Border(
                bottom: BorderSide(
                  color: AppColors.border.withValues(alpha: 0.3),
                ),
              ),
            ),
            child: Row(
              children: [
                // Expand/Collapse indicator
                SizedBox(
                  width: 24,
                  child: hasChildren
                      ? AnimatedRotation(
                          turns: isNodeExpanded ? 0.25 : 0,
                          duration: const Duration(milliseconds: 200),
                          child: Icon(
                            PhosphorIconsBold.caretLeft,
                            size: 14,
                            color: typeInfo.color.withValues(alpha: 0.7),
                          ),
                        )
                      : Icon(
                          depth > 0
                              ? PhosphorIconsBold.arrowBendDownRight
                              : PhosphorIconsBold.minus,
                          size: 12,
                          color: AppColors.textMuted.withValues(alpha: 0.4),
                        ),
                ),
                const SizedBox(width: 4),
                // Account Code Badge
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                  decoration: BoxDecoration(
                    color: typeInfo.color.withValues(alpha: hasChildren ? 0.12 : 0.06),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: typeInfo.color.withValues(alpha: hasChildren ? 0.25 : 0.12)),
                  ),
                  child: Text(
                    account.code,
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 11,
                      fontWeight: hasChildren ? FontWeight.w700 : FontWeight.w500,
                      color: typeInfo.color,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                // Account Name + badges
                Expanded(
                  child: Row(
                    children: [
                      if (hasChildren)
                        Padding(
                          padding: const EdgeInsetsDirectional.only(end: 4),
                          child: Icon(PhosphorIconsBold.folder, size: 14, color: typeInfo.color.withValues(alpha: 0.6)),
                        ),
                      Expanded(
                        child: Text(
                          account.name,
                          style: GoogleFonts.cairo(
                            fontSize: 13,
                            fontWeight: hasChildren ? FontWeight.w700 : FontWeight.w500,
                          ),
                        ),
                      ),
                      if (account.isSystem) ...[
                        const SizedBox(width: 6),
                        _badge(tr('نظام'), AppColors.info),
                      ],
                      if (!account.isActive) ...[
                        const SizedBox(width: 6),
                        _badge(tr('معطل'), AppColors.error),
                      ],
                      if (account.isHiddenFromEntries) ...[
                        const SizedBox(width: 6),
                        _badge(tr('مخفي من القيود'), AppColors.warning),
                      ],
                      if (hasChildren) ...[
                        const SizedBox(width: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                          decoration: BoxDecoration(
                            color: typeInfo.color.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            '${children.length}',
                            style: GoogleFonts.cairo(fontSize: 9, color: typeInfo.color, fontWeight: FontWeight.w700),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                // Balance — Spec 135 BUG-E: rolled-up for parents (own +
                // descendants), own for leaves.
                Builder(builder: (_) {
                  final displayBalance = rollup.balanceOf(account.id, account.balance);
                  return Text(
                    formatAccountAmount(displayBalance),
                    style: GoogleFonts.cairo(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: displayBalance.abs() < 0.01
                          ? AppColors.textMuted
                          : (displayBalance >= 0
                              ? AppColors.textPrimary
                              : AppColors.error),
                    ),
                  );
                }),
                const SizedBox(width: 4),
                // Actions
                PopupMenuButton<String>(
                  icon: const Icon(PhosphorIconsBold.dotsThreeVertical,
                      size: 14, color: AppColors.textMuted),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                  onSelected: (action) => onAction(account, action),
                  itemBuilder: (ctx) => [
                    PopupMenuItem(
                      value: 'sub',
                      child: Row(
                        children: [
                          Icon(PhosphorIconsBold.plus, size: 16, color: typeInfo.color),
                          const SizedBox(width: 8),
                           Text(tr('إضافة حساب فرعي')),
                        ],
                      ),
                    ),
                     PopupMenuItem(
                      value: 'ledger',
                      child: Row(
                        children: [
                          const Icon(PhosphorIconsBold.book, size: 16, color: AppColors.primary),
                          const SizedBox(width: 8),
                          Text(tr('دفتر الأستاذ')),
                        ],
                      ),
                    ),
                     PopupMenuItem(
                      value: 'edit',
                      child: Row(
                        children: [
                          const Icon(PhosphorIconsBold.pencilSimple, size: 16, color: AppColors.warning),
                          const SizedBox(width: 8),
                          Text(tr('تعديل')),
                        ],
                      ),
                    ),
                    if (!account.isSystem)
                       PopupMenuItem(
                        value: 'delete',
                        child: Row(
                          children: [
                            const Icon(PhosphorIconsBold.trash, size: 16, color: AppColors.error),
                            const SizedBox(width: 8),
                            Text(tr('حذف'), style: const TextStyle(color: AppColors.error)),
                          ],
                        ),
                      ),
                    PopupMenuItem(
                      value: 'toggle_hide',
                      child: Row(
                        children: [
                          Icon(
                            account.isHiddenFromEntries
                                ? PhosphorIconsBold.eye
                                : PhosphorIconsBold.eyeSlash,
                            size: 16,
                            color: AppColors.warning,
                          ),
                          const SizedBox(width: 8),
                          Text(account.isHiddenFromEntries
                              ? tr('إظهار في القيود')
                              : tr('إخفاء من القيود')),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        // Render children recursively
        if (isNodeExpanded)
          ...children.map((child) => CoaTreeNode(
                account: child,
                typeInfo: typeInfo,
                allTypeAccounts: allTypeAccounts,
                depth: depth + 1,
                repo: repo,
                expandedAccounts: expandedAccounts,
                onToggle: () => onAction(child, '_toggle'),
                onAction: onAction,
                rollup: rollup,
              )),
      ],
    );
  }

  Widget _badge(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(text,
        style: GoogleFonts.cairo(fontSize: 9, color: color, fontWeight: FontWeight.w700),
      ),
    );
  }
}
