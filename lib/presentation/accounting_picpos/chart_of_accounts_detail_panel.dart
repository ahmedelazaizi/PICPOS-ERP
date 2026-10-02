import 'package:ural_erp/core/i18n/tr.dart';
// لوحُ تفاصيل الحساب — **يحلّ محلَّ الحوارات تماماً** (قرارُ المالك 2026-09-18).
//
// ═══ لماذا لوحٌ لا حوار ═══
//
// الحوارُ يحجب الشجرةَ التي تُحرَّر منها. ودليلُ الحسابات يُحرَّر **بالمقارنة**:
// رمزُ الابن يتبع رمزَ أبيه، والنوعُ يتبع الفرعَ. فإخفاءُ الشجرة يجعل
// المستخدمَ يحفظ ما يقارن به.
//
// ═══ 🔴 وثلاثةُ حقولٍ في التصميم لا تُكتَب كما تبدو ═══
//
// ‏١ — **«طبيعة الحساب» (مدين/دائن) مشتقّةٌ لا مختارة**: هجرةُ v110 تملأ
//     `normal_balance` من `account_type` بقاعدةٍ صريحة، فاختيارُها بيدٍ يسمح
//     بحساب إيراداتٍ «مدين» — وهو ما كان يقع فعلاً، لأنّ الكاتبَ كان يتركها
//     على افتراض العمود. فتُعرَض ولا تُحرَّر.
//
// ‏٢ — **و«الحساب الأب» يُختار عند الإنشاء ويُقرأ عند التعديل**:
//     `updateAccount` لا تقبل `parentId`، وإعادةُ النسب تُعيد حسابَ مستوى
//     الحساب **وكلِّ ذرّيّته** وتفتح بابَ حلقةٍ في الشجرة. فحقلٌ يَعِد بها
//     ولا يفعلها أسوأُ من غيابه.
//
// ‏٣ — **و«تفاصيل إضافية: ملاحظات ومرفقات» تُسقَط**: لا عمودَ `notes` على
//     `accounts` إطلاقاً. وصفٌّ لا يحمل شيئاً أبداً ضجيجٌ — نفسُ قرار
//     «ملاحظات» في اليومية العامة.
//
//     ⚠️ **والمرفقاتُ ليست مؤجَّلةً بعد اليوم — هي خارجُ النطاق.** نُفِّذت
//     §٨ في v176، و`accounts` **ليس من الأنواع التسعة** التي قرّر المالكُ
//     أنّها تقبل مرفقاً (§٨٫٤ قرار ٢): تلك مستنداتٌ لها تاريخٌ ومبلغٌ
//     وطرفٌ، والحسابُ تعريفٌ في شجرة. وإضافتُه سطرٌ واحدٌ في
//     `kAttachmentEntities` يومَ يُطلَب — بقرارٍ لا بسهو.

import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/theme/app_colors.dart';
import '../../core/widgets/app_toast.dart';
import '../../domain/models/account_facts.dart';
import '../picpos_shell/picpos_surface.dart';
import '../screens/coa/coa_shared.dart';

/// حسابٌ كما يراه اللوح — **قيمٌ خالصةٌ لا صفُّ drift**.
///
/// ⚠️ وهذا ليس تجميلاً: حارسُ `presentation_db_import_guard` يمنع أيَّ ملفِّ
/// عرضٍ **جديد** من استيراد `data/database`، وقائمتُه مقفولة. فاللوحُ يأخذ
/// ما يعرضه ويعيد ما يُكتَب، والشاشةُ وحدَها تلمس الصفوف.
class AccountPanelValue {
  const AccountPanelValue({
    required this.id,
    required this.code,
    required this.name,
    required this.accountType,
    required this.accountNature,
    required this.isActive,
    required this.isSystem,
    required this.isHiddenFromEntries,
    required this.parentId,
  });

  final int id;
  final String code;
  final String name;
  final String accountType;
  final String accountNature;
  final bool isActive;
  final bool isSystem;
  final bool isHiddenFromEntries;
  final int? parentId;
}

/// خيارُ أبٍ في القائمة المنسدلة.
typedef AccountParentOption = ({int id, String code, String name, String accountType});

/// قيمُ اللوح بعد التحقّق — والشاشةُ تملك الكتابة.
typedef AccountPanelSave = Future<void> Function({
  required String code,
  required String name,
  required String accountType,
  required String accountNature,
  required bool isActive,
  required bool isHiddenFromEntries,
  int? parentId,
});

class AccountDetailPanel extends StatefulWidget {
  const AccountDetailPanel({
    super.key,
    required this.account,
    required this.parent,
    required this.allAccounts,
    required this.onSave,
    required this.onClose,
    this.onOpenLedger,
  });

  /// الحسابُ المعروض — أو `null` حين يكون اللوحُ في وضع الإنشاء.
  final AccountPanelValue? account;

  /// الأبُ المقترَح عند الإنشاء (أو أبُ الحساب المعروض عند التعديل).
  final AccountParentOption? parent;

  final List<AccountParentOption> allAccounts;
  final AccountPanelSave onSave;
  final VoidCallback onClose;

  /// 🔴 **دفترُ الأستاذ لم يسقط** — نُقل إلى هنا: نقرةُ الصفّ صارت تختار
  /// (كما يرسم التصميم)، وكانت تفتح الدفتر. وصفُّ الشجرة ودجتٌ **مشتركةٌ**
  /// مع فرع UralCash فلا يُفرَّق فيه بين النقرة والقائمة.
  ///
  /// و`null` عند الإنشاء: لا حسابَ بعدُ ليُفتَح دفترُه.
  final VoidCallback? onOpenLedger;

  @override
  State<AccountDetailPanel> createState() => _AccountDetailPanelState();
}

class _AccountDetailPanelState extends State<AccountDetailPanel> {
  late final TextEditingController _code;
  late final TextEditingController _name;
  late String _type;
  late String _nature;
  late bool _active;
  late bool _hidden;
  int? _parentId;
  bool _saving = false;

  bool get _isNew => widget.account == null;
  bool get _isSystem => widget.account?.isSystem ?? false;

  @override
  void initState() {
    super.initState();
    final a = widget.account;
    _code = TextEditingController(
      // عند الإنشاء تحت أبٍ: رمزُ الأب بادئةً — كما كان الحوارُ يفعل.
      text: a?.code ?? widget.parent?.code ?? '',
    );
    _name = TextEditingController(text: a?.name ?? '');
    _type = a?.accountType ?? widget.parent?.accountType ?? 'asset';
    _nature = a?.accountNature ?? kAccountNatureDetail;
    _active = a?.isActive ?? true;
    _hidden = a?.isHiddenFromEntries ?? false;
    _parentId = a?.parentId ?? widget.parent?.id;
  }

  @override
  void dispose() {
    _code.dispose();
    _name.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_code.text.trim().isEmpty || _name.text.trim().isEmpty) {
      AppToast.show(context, tr('الرمزُ والاسمُ مطلوبان'), type: ToastType.error);
      return;
    }
    setState(() => _saving = true);
    try {
      await widget.onSave(
        code: _code.text.trim(),
        name: _name.text.trim(),
        accountType: _type,
        accountNature: _nature,
        isActive: _active,
        isHiddenFromEntries: _hidden,
        parentId: _parentId,
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final parentName = widget.allAccounts
        .where((a) => a.id == _parentId)
        .map((a) => '${a.code} — ${trData(a.name)}')
        .firstOrNull;

    return Container(
      decoration: BoxDecoration(
        color: context.picposCard,
        border: Border.all(color: context.picposHairline),
        borderRadius: BorderRadius.circular(14),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            color: AppColors.primary.withValues(alpha: 0.05),
            child: Row(
              children: [
                Icon(
                  _isNew
                      ? PhosphorIconsBold.plusCircle
                      : PhosphorIconsBold.identificationCard,
                  size: 16,
                  color: context.picposBrandInk,
                ),
                const SizedBox(width: 8),
                Text(
                  _isNew ? tr('حساب جديد') : tr('تفاصيل الحساب'),
                  style: text.labelLarge?.copyWith(fontWeight: FontWeight.w800),
                ),
              ],
            ),
          ),
          // 🔴 **السببُ ظاهرٌ لا مخفيّ** — قرارُ المالك. والحوارُ القديمُ كان
          //    يُعطّل حقلَ الرمز بـ`enabled: !isSystem` **بلا كلمة**، فيرى
          //    المستخدمُ حقلاً رماديّاً ويظنّ البرنامجَ معطوباً.
          if (_isSystem)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              color: AppColors.warning.withValues(alpha: 0.08),
              child: Row(
                children: [
                  const Icon(PhosphorIconsBold.lock,
                      size: 14, color: AppColors.warning),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      tr('حسابُ نظام — رمزُه ثابتٌ ولا يُحذَف. يقرؤه المحرّكُ بالرمز في الترحيل الآليّ، وتغييرُه يقطع الترحيل.'),
                      style: text.labelSmall
                          ?.copyWith(color: context.picposText),
                    ),
                  ),
                ],
              ),
            ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _field(
                    tr('رمز الحساب'),
                    TextField(
                      controller: _code,
                      enabled: !_isSystem,
                      decoration: const InputDecoration(
                          isDense: true, border: OutlineInputBorder()),
                    ),
                  ),
                  _field(
                    tr('اسم الحساب'),
                    TextField(
                      controller: _name,
                      decoration: const InputDecoration(
                          isDense: true, border: OutlineInputBorder()),
                    ),
                  ),
                  _field(
                    tr('الحساب الأب'),
                    _isNew
                        ? DropdownButtonFormField<int?>(
                            initialValue: _parentId,
                            isExpanded: true,
                            decoration: const InputDecoration(
                                isDense: true, border: OutlineInputBorder()),
                            items: [
                               DropdownMenuItem(
                                  value: null, child: Text(tr('— حسابٌ رئيسيّ —'))),
                              for (final a in widget.allAccounts)
                                DropdownMenuItem(
                                  value: a.id,
                                  child: Text('${a.code} — ${trData(a.name)}',
                                      overflow: TextOverflow.ellipsis),
                                ),
                            ],
                            onChanged: (v) => setState(() {
                              _parentId = v;
                              final p = widget.allAccounts
                                  .where((a) => a.id == v)
                                  .firstOrNull;
                              // النوعُ يتبع الأبَ — حسابٌ فرعيٌّ من نوعٍ آخر
                              // يكسر كلَّ تجميعٍ هرميّ.
                              if (p != null) _type = p.accountType;
                            }),
                          )
                        : _readOnly(
                            parentName ?? tr('— حسابٌ رئيسيّ —'),
                            hint: tr('النسبُ يُختار عند الإنشاء: تغييرُه يُعيد حسابَ المستوى للحساب وكلِّ ذرّيّته.'),
                          ),
                  ),
                  if (_isNew)
                    _field(
                      tr('نوع الحساب'),
                      DropdownButtonFormField<String>(
                        initialValue: _type,
                        isExpanded: true,
                        decoration: const InputDecoration(
                            isDense: true, border: OutlineInputBorder()),
                        items: [
                          for (final e in kAccountTypeConfig.entries)
                            DropdownMenuItem(
                                value: e.key, child: Text(e.value.label)),
                        ],
                        // ⚠️ مقفولٌ تحت أب — نفسُ قاعدة حوار الإنشاء
                        //    (`onChanged: isSubAccount ? null : …`): الفرعيُّ
                        //    من نوعٍ غيرِ نوع أبيه يكسر كلَّ تجميعٍ هرميّ.
                        onChanged: _parentId != null
                            ? null
                            : (v) => setState(() => _type = v ?? _type),
                      ),
                    ),
                  // مشتقٌّ لا مختار — راجع ترويسةَ الملفّ.
                  _field(
                    tr('طبيعة الحساب'),
                    _readOnly(
                      normalBalanceFor(_type) == 'credit' ? tr('دائن') : tr('مدين'),
                      hint: tr('تُشتقُّ من نوع الحساب — ولا تُحرَّر بيد.'),
                    ),
                  ),
                  _field(
                    tr('مستوى الحساب'),
                    DropdownButtonFormField<String>(
                      initialValue: _nature,
                      isExpanded: true,
                      decoration: const InputDecoration(
                          isDense: true, border: OutlineInputBorder()),
                      items:  [
                        DropdownMenuItem(
                            value: kAccountNatureDetail,
                            child: Text(tr('تفصيلي — يُرحَّل عليه'))),
                        DropdownMenuItem(
                            value: kAccountNatureView,
                            child: Text(tr('رئيسي — لا يُرحَّل عليه'))),
                      ],
                      onChanged: (v) => setState(() => _nature = v ?? _nature),
                    ),
                  ),
                  _field(
                    tr('حالة الحساب'),
                    DropdownButtonFormField<bool>(
                      initialValue: _active,
                      isExpanded: true,
                      decoration: const InputDecoration(
                          isDense: true, border: OutlineInputBorder()),
                      items:  [
                        DropdownMenuItem(value: true, child: Text(tr('نشط'))),
                        DropdownMenuItem(value: false, child: Text(tr('موقوف'))),
                      ],
                      onChanged: (v) => setState(() => _active = v ?? _active),
                    ),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    title: Text(tr('إخفاء من سندات القيد'),
                        style: text.labelMedium
                            ?.copyWith(fontWeight: FontWeight.w700)),
                    subtitle: Text(tr('لن يظهر عند إنشاء قيدٍ يدويّ'),
                        style: text.labelSmall
                            ?.copyWith(color: context.picposMuted)),
                    value: _hidden,
                    onChanged: (v) => setState(() => _hidden = v),
                  ),
                ],
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: context.picposHairline)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _saving ? null : _submit,
                    icon: const Icon(PhosphorIconsBold.floppyDisk, size: 15),
                    label: Text(_isNew ? tr('حفظ الحساب') : tr('تعديل الحساب')),
                  ),
                ),
                if (!_isNew && widget.onOpenLedger != null) ...[
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    onPressed: widget.onOpenLedger,
                    icon: const Icon(PhosphorIconsBold.book, size: 14),
                    label:  Text(tr('دفتر الأستاذ')),
                  ),
                ],
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: widget.onClose,
                  icon: const Icon(PhosphorIconsBold.caretLeft, size: 14),
                  label:  Text(tr('رجوع')),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _field(String label, Widget child) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(label,
                style: Theme.of(context)
                    .textTheme
                    .labelSmall
                    ?.copyWith(color: context.picposMuted)),
            const SizedBox(height: 5),
            child,
          ],
        ),
      );

  /// حقلٌ يُعرَض ولا يُحرَّر — **وسببُه مكتوبٌ تحته**.
  Widget _readOnly(String value, {required String hint}) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
            decoration: BoxDecoration(
              color: context.picposMuted.withValues(alpha: 0.06),
              border: Border.all(color: context.picposHairline),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall),
          ),
          const SizedBox(height: 4),
          Text(hint,
              style: Theme.of(context)
                  .textTheme
                  .labelSmall
                  ?.copyWith(color: context.picposMuted)),
        ],
      );
}
