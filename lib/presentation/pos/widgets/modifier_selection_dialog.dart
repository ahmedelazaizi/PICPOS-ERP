import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/permissions/permission_codes.dart';
import '../../../core/theme/app_colors.dart';
import '../../picpos_shell/picpos_surface.dart';
// `ModifierGroupWithItems` يصل عبر البرميل الذي يُصدّره `providers.dart`،
// فاستيراد `data/database/database.dart` صار زائداً وأزيل.
import '../../../data/providers/providers.dart';
import '../../widgets/permission_guard.dart';

/// Quantity level for options (قليل / وسط / كثير)
enum OptionQuantityLevel {
  none,   // No quantity level (used for additions)
  light,  // قليل
  medium, // وسط
  heavy,  // كثير
}

extension OptionQuantityLevelX on OptionQuantityLevel {
  String get label => switch (this) {
    OptionQuantityLevel.none   => '',
    OptionQuantityLevel.light  => 'قليل',
    OptionQuantityLevel.medium => 'بدون',
    OptionQuantityLevel.heavy  => 'كثير',
  };

  Color get color => switch (this) {
    OptionQuantityLevel.none   => AppColors.textMuted,
    OptionQuantityLevel.light  => const Color(0xFFF59E0B), // Amber
    OptionQuantityLevel.medium => const Color(0xFF3B82F6), // Blue
    OptionQuantityLevel.heavy  => const Color(0xFF10B981), // Emerald
  };

  IconData get icon => switch (this) {
    OptionQuantityLevel.none   => PhosphorIconsBold.circle,
    OptionQuantityLevel.light  => PhosphorIconsBold.drop,
    OptionQuantityLevel.medium => PhosphorIconsBold.dropHalf,
    OptionQuantityLevel.heavy  => PhosphorIconsBold.dropSimple,
  };

  /// Serialize to string for DB note storage
  String get code => switch (this) {
    OptionQuantityLevel.none   => '',
    OptionQuantityLevel.light  => 'L',
    OptionQuantityLevel.medium => 'M',
    OptionQuantityLevel.heavy  => 'H',
  };

  static OptionQuantityLevel fromCode(String code) => switch (code) {
    'L' => OptionQuantityLevel.light,
    'M' => OptionQuantityLevel.medium,
    'H' => OptionQuantityLevel.heavy,
    _   => OptionQuantityLevel.none,
  };
}

/// Selected modifier item in the cart
class SelectedModifier {
  final int itemId;
  final String itemName;
  final String groupName;
  final double extraPrice;
  final bool isOption; // true = option (no price), false = addition (with price)
  final OptionQuantityLevel quantityLevel; // quantity level for options

  SelectedModifier({
    required this.itemId,
    required this.itemName,
    required this.groupName,
    required this.extraPrice,
    this.isOption = false,
    this.quantityLevel = OptionQuantityLevel.none,
  });

  /// Display text combining quantity level + item name
  String get displayText {
    if (quantityLevel != OptionQuantityLevel.none) {
      return '${quantityLevel.label} $itemName';
    }
    return itemName;
  }
}

/// حصيلةُ الحوار: المعدِّلات المختارة + ملاحظةُ الكاشير اليدوية.
///
/// ⚠️ [note] **ليست** `CartItemEntity.note`. الأخيرُ نصٌّ مشتقٌّ يُبنى في
/// `composeCartItemNote` وحدَها من المعدِّلات + `itemNote`. مرِّرها إلى
/// `updateItemNote` ودعِ التركيبَ لها، وإلا محت المعدِّلات من المطبوع بينما
/// هي باقيةٌ في `item.modifiers` — والمطبخُ يحضّر الطلبَ غلط.
class ModifierSelectionResult {
  const ModifierSelectionResult({required this.modifiers, this.note});

  final List<SelectedModifier> modifiers;
  final String? note;
}

/// حقلُ ملاحظة الصنف — مستخرَجٌ كدالّةٍ مستقلّةٍ ليُقاس بلا قاعدة بيانات
/// (نفس نمط Task 6a/6b/7).
///
/// `allowManagerOverride` بلا `onGranted`: الحقلُ نصٌّ حرٌّ بلا زرٍّ واحدٍ
/// واضح — إضافةُ ملاحظةٍ كتابةٌ حقيقيةٌ على الصنف لا مجردَ عرض، فمن غير
/// الصلاحية يلزم تصريحُ مدير. والموافقةُ هنا **تفتح القفل** بدل أن تُشغّل
/// حفظاً فورياً، ثم يكتب الكاشير ويحفظ كأيّ مستخدمٍ مصرَّحٍ له. نفسُ
/// السيناريو الموثَّق في `permission_guard.dart` لحقلٍ بلا فعلٍ واحد.
@visibleForTesting
Widget buildItemNoteField({required TextEditingController controller}) {
  return PermissionGuard(
    permission: PermissionCodes.posNoteAdd,
    allowManagerOverride: true,
    actionName: 'إضافة ملاحظة على الصنف',
    child: TextField(
      controller: controller,
      style: const TextStyle(fontSize: 13),
      textInputAction: TextInputAction.done,
      decoration: const InputDecoration(
        isDense: true,
        prefixIcon: Icon(
          PhosphorIconsBold.notepad,
          size: 16,
          color: AppColors.warning,
        ),
        labelText: 'ملاحظة على الصنف',
        hintText: 'بدون بصل، سريع التحضير…',
        border: OutlineInputBorder(),
      ),
    ),
  );
}

/// Large dialog for selecting product options and additions.
///
/// Options: choices without extra price (size, cooking level, etc.)
/// Additions: extras with price (extra cheese, toppings, etc.)
class ModifierSelectionDialog extends StatefulWidget {
  final String productName;
  final List<ModifierGroupWithItems> modifierGroups;

  /// المعدِّلاتُ المختارةُ سلفاً على السطر. فارغةٌ ⇒ تُنتقى افتراضياتُ
  /// المجموعات (`isDefault`). غيرُ فارغةٍ ⇒ تُستأنف الحالةُ كما هي، وإلا
  /// بدا للكاشير أن إعادةَ الفتح مسحت اختياراته.
  final List<SelectedModifier> initialSelection;

  /// يُظهر حقلَ ملاحظةِ الصنف داخل الحوار. مطفأٌ افتراضياً كي يبقى نداءُ
  /// [show] القديم كما هو حرفياً.
  final bool noteEnabled;
  final String? initialNote;

  const ModifierSelectionDialog({
    super.key,
    required this.productName,
    required this.modifierGroups,
    this.initialSelection = const [],
    this.noteEnabled = false,
    this.initialNote,
  });

  /// Show the dialog and return selected modifiers
  static Future<List<SelectedModifier>?> show(
    BuildContext context, {
    required String productName,
    required List<ModifierGroupWithItems> modifierGroups,
  }) async {
    final result = await showDialog<ModifierSelectionResult>(
      context: context,
      barrierDismissible: false,
      builder: (c) => ModifierSelectionDialog(
        productName: productName,
        modifierGroups: modifierGroups,
      ),
    );
    return result?.modifiers;
  }

  /// يفتح الحوارَ لسطرِ سلّةٍ بعينه: يحمّل مجموعاتِ المنتج، ويستأنف
  /// الاختياراتِ والملاحظة، ويُرجع الاثنين معاً.
  ///
  /// ── لماذا التحميلُ هنا لا في `pos_picpos/` ────────────────────────────
  /// `getProductModifiers` تُرجع `ModifierGroupWithItems` وهو نوعٌ من
  /// `data/database`، و`presentation_db_import_guard` يمنع أيَّ ملفِّ عرضٍ
  /// **جديد** من استيراده. هذا الملفُّ في القائمة البيضاء سلفاً، فلا يتسرّب
  /// النوعُ لسلّة PicPos — الدالّةُ لا تُرجع إلا `SelectedModifier` ونصّاً.
  ///
  /// تُرجع null إن أُلغي الحوار، أو إن لم يكن للمنتج أيُّ مجموعةٍ وكان حقلُ
  /// الملاحظة مطفأً — فلا شيءَ يُعرض عندئذٍ.
  static Future<ModifierSelectionResult?> showForCartItem(
    BuildContext context,
    WidgetRef ref, {
    required int productId,
    required String productName,
    List<SelectedModifier> initialSelection = const [],
    String? initialNote,
    bool noteEnabled = true,
  }) async {
    List<ModifierGroupWithItems> groups;
    try {
      groups =
          await ref.read(productRepositoryProvider).getProductModifiers(productId);
    } catch (_) {
      groups = const [];
    }
    if (groups.isEmpty && !noteEnabled) return null;
    if (!context.mounted) return null;

    return showDialog<ModifierSelectionResult>(
      context: context,
      barrierDismissible: false,
      builder: (c) => ModifierSelectionDialog(
        productName: productName,
        modifierGroups: groups,
        initialSelection: initialSelection,
        noteEnabled: noteEnabled,
        initialNote: initialNote,
      ),
    );
  }

  @override
  State<ModifierSelectionDialog> createState() => _ModifierSelectionDialogState();
}

class _ModifierSelectionDialogState extends State<ModifierSelectionDialog> {
  // groupId -> list of selected item IDs
  final Map<int, Set<int>> _selections = {};

  // Separate groups into options (no-price items) and additions (with price)
  List<ModifierGroupWithItems> get _optionGroups => widget.modifierGroups
      .where((mg) => mg.items.every((item) => item.extraPrice <= 0) || mg.group.type == 'option')
      .toList();

  List<ModifierGroupWithItems> get _additionGroups => widget.modifierGroups
      .where((mg) => mg.items.any((item) => item.extraPrice > 0) && mg.group.type != 'option')
      .toList();

  late final TextEditingController _noteController;

  @override
  void initState() {
    super.initState();
    _noteController = TextEditingController(text: widget.initialNote ?? '');

    // استئنافُ اختياراتِ السطر إن وُجدت، وإلا فافتراضياتُ المجموعات.
    final resumed = widget.initialSelection.map((m) => m.itemId).toSet();
    for (final mg in widget.modifierGroups) {
      _selections[mg.group.id] = {};
      for (final item in mg.items) {
        final on = resumed.isEmpty ? item.isDefault : resumed.contains(item.id);
        if (on) {
          _selections[mg.group.id]!.add(item.id);
        }
      }
    }
  }

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  /// يغلّف المعدِّلات بالملاحظة. لما الحقلُ مطفأً تُمرَّر [initialNote] كما
  /// هي — فالحوارُ لم يعرضها ولا يجوز أن يمحوها.
  ModifierSelectionResult _result(List<SelectedModifier> modifiers) {
    if (!widget.noteEnabled) {
      return ModifierSelectionResult(
        modifiers: modifiers,
        note: widget.initialNote,
      );
    }
    final note = _noteController.text.trim();
    return ModifierSelectionResult(
      modifiers: modifiers,
      note: note.isEmpty ? null : note,
    );
  }

  double get _totalExtra {
    double total = 0;
    for (final mg in widget.modifierGroups) {
      final selected = _selections[mg.group.id] ?? {};
      for (final item in mg.items) {
        if (selected.contains(item.id)) {
          total += item.extraPrice;
        }
      }
    }
    return total;
  }

  bool get _isValid {
    for (final mg in widget.modifierGroups) {
      final selected = _selections[mg.group.id] ?? {};
      if (mg.group.isRequired && selected.isEmpty) return false;
      if (selected.length < mg.group.minSelect) return false;
      if (mg.group.maxSelect > 0 && selected.length > mg.group.maxSelect) return false;
    }
    return true;
  }

  List<SelectedModifier> _buildResult() {
    final result = <SelectedModifier>[];
    for (final mg in widget.modifierGroups) {
      final selected = _selections[mg.group.id] ?? {};
      final isOptionGroup = _optionGroups.contains(mg);
      for (final item in mg.items) {
        if (selected.contains(item.id)) {
          result.add(SelectedModifier(
            itemId: item.id,
            itemName: item.name,
            groupName: mg.group.name,
            extraPrice: item.extraPrice,
            isOption: isOptionGroup,
          ));
        }
      }
    }
    return result;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final screenSize = MediaQuery.of(context).size;
    final options = _optionGroups;
    final additions = _additionGroups;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Dialog(
        insetPadding: EdgeInsets.symmetric(
          horizontal: screenSize.width * 0.08,
          vertical: screenSize.height * 0.06,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Container(
          constraints: BoxConstraints(
            maxWidth: 700,
            maxHeight: screenSize.height * 0.85,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // ─── Header ───
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      AppColors.primary,
                      AppColors.primary.withValues(alpha: 0.85),
                    ],
                  ),
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(PhosphorIconsBold.forkKnife, color: Colors.white, size: 24),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.productName,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.w900,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'اختر الخيارات والإضافات المطلوبة',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.8),
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(PhosphorIconsBold.x, color: Colors.white),
                    ),
                  ],
                ),
              ),

              // ─── Body: Scrollable Options & Additions ───
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Options section (no price)
                      if (options.isNotEmpty) ...[
                        _buildSectionHeader(
                          icon: PhosphorIconsBold.listChecks,
                          label: 'الخيارات',
                          color: theme.colorScheme.tertiary,
                          subtitle: 'اختيارات بدون سعر إضافي',
                        ),
                        const SizedBox(height: 12),
                        ...options.map((mg) => _buildGroupCard(mg, theme, isOption: true)),
                        const SizedBox(height: 24),
                      ],

                      // Additions section (with price)
                      if (additions.isNotEmpty) ...[
                        _buildSectionHeader(
                          icon: PhosphorIconsBold.plusCircle,
                          label: 'الإضافات',
                          color: AppColors.primary,
                          subtitle: 'إضافات بسعر إضافي',
                        ),
                        const SizedBox(height: 12),
                        ...additions.map((mg) => _buildGroupCard(mg, theme, isOption: false)),
                      ],
                    ],
                  ),
                ),
              ),

              // ─── Footer: Total + Actions ───
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                decoration: BoxDecoration(
                  color: theme.cardColor,
                  border: Border(top: BorderSide(color: context.picposHairline)),
                  borderRadius: const BorderRadius.vertical(bottom: Radius.circular(20)),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (widget.noteEnabled) ...[
                      buildItemNoteField(controller: _noteController),
                      const SizedBox(height: 12),
                    ],
                    Row(
                  children: [
                    // Total extra price badge
                    if (_totalExtra > 0)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
                        ),
                        child: Row(
                          children: [
                            const Icon(PhosphorIconsBold.currencyCircleDollar,
                                size: 18, color: AppColors.primary),
                            const SizedBox(width: 6),
                            Text(
                              'إضافات: +${_totalExtra.toStringAsFixed(AppConstants.decimalPlaces)} ${AppConstants.currencySymbolEn}',
                              style: const TextStyle(
                                color: AppColors.primary,
                                fontWeight: FontWeight.w900,
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                      ),
                    const Spacer(),
                    // Cancel
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('إلغاء'),
                    ),
                    const SizedBox(width: 8),
                    // Without additions
                    OutlinedButton.icon(
                      onPressed: () => Navigator.pop(context, _result(const [])),
                      icon: const Icon(PhosphorIconsBold.minus, size: 16),
                      label: const Text('بدون إضافات'),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      ),
                    ),
                    const SizedBox(width: 8),
                    // Confirm
                    FilledButton.icon(
                      onPressed: _isValid
                          ? () => Navigator.pop(context, _result(_buildResult()))
                          : null,
                      icon: const Icon(PhosphorIconsBold.check, size: 16),
                      label: const Text('تأكيد الاختيارات'),
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                        backgroundColor: AppColors.success,
                      ),
                    ),
                  ],
                ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionHeader({
    required IconData icon,
    required String label,
    required Color color,
    String? subtitle,
  }) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: 20, color: color),
        ),
        const SizedBox(width: 10),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w900,
                color: color,
              ),
            ),
            if (subtitle != null)
              Text(
                subtitle,
                style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
              ),
          ],
        ),
      ],
    );
  }

  Widget _buildGroupCard(ModifierGroupWithItems mg, ThemeData theme, {required bool isOption}) {
    final g = mg.group;
    final selected = _selections[g.id] ?? {};
    final isSingle = g.maxSelect == 1;
    final cardColor = isOption
        ? theme.colorScheme.tertiary.withValues(alpha: 0.04)
        : AppColors.primary.withValues(alpha: 0.04);
    final borderColor = isOption
        ? theme.colorScheme.tertiary.withValues(alpha: 0.15)
        : AppColors.primary.withValues(alpha: 0.15);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Group header
          Row(
            children: [
              Text(
                g.name,
                style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
              ),
              if (g.isRequired) ...[
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppColors.error.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text(
                    'مطلوب *',
                    style: TextStyle(fontSize: 10, color: AppColors.error, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
              const Spacer(),
              Text(
                isSingle
                    ? 'اختر واحد'
                    : 'اختر ${g.minSelect}-${g.maxSelect > 0 ? g.maxSelect : '∞'}',
                style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // Items as chips
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: mg.items.map((item) {
              final isSelected = selected.contains(item.id);
              final chipColor = isOption
                  ? theme.colorScheme.tertiary
                  : AppColors.primary;

              return Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () {
                    setState(() {
                      if (isSingle) {
                        _selections[g.id] = isSelected ? {} : {item.id};
                      } else {
                        if (isSelected) {
                          _selections[g.id]!.remove(item.id);
                        } else {
                          if (g.maxSelect == 0 || selected.length < g.maxSelect) {
                            _selections[g.id]!.add(item.id);
                          }
                        }
                      }
                    });
                  },
                  borderRadius: BorderRadius.circular(10),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? chipColor.withValues(alpha: 0.15)
                          : theme.colorScheme.surface,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: isSelected
                            ? chipColor.withValues(alpha: 0.6)
                            : context.picposHairline,
                        width: isSelected ? 2 : 1,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          isSelected
                              ? PhosphorIconsBold.checkCircle
                              : PhosphorIconsBold.circle,
                          size: 18,
                          color: isSelected ? chipColor : AppColors.textMuted,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          item.name,
                          style: TextStyle(
                            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                            color: isSelected ? chipColor : null,
                          ),
                        ),
                        if (item.extraPrice > 0) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppColors.success.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              '+${item.extraPrice.toStringAsFixed(0)} ${AppConstants.currencySymbolEn}',
                              style: const TextStyle(
                                fontSize: 11,
                                color: AppColors.success,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}
