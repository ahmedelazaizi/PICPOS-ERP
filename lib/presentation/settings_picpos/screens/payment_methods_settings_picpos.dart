// طرقُ الدفع المؤشَّرة — إعدادٌ خاصٌّ بـPicPos، لا نسخةَ عن UralCash.
//
// ── لماذا هنا لا في `PosSettingsWidget` المشترك ───────────────────────────
// الودجتُ المشتركُ يخدم البراندَين، و`allowedMethods` **لا يُمرَّر** في مسار
// بيع UralCash إطلاقاً (‏`null` = الكلّ؛ مقيسٌ في جدول التكافؤ برأس
// `picpos_pos_operations.dart`). فوضعُ الإعداد هناك كان سيعرض على مستخدم
// UralCash مربّعاتِ تأشيرٍ لا أثرَ لها — إعدادٌ يكذب.
//
// ── وطلبُ المالك (2026-08-14) ───────────────────────────────────────────────
// «إتمامُ الدفع له صلاحيةٌ في الإعدادات: عند التأشير للنقديّ فقط لا تظهر
// الطرقُ الأخرى؛ وعند النقديّ مع البطاقة يظهر إتمامُ الدفع بالطرق المؤشَّرة
// بطريقةٍ أسهل وأسرع.»
//
// والقرارُ نفسُه خالصٌ في `domain/models/pos_payment_methods.dart`: المُظهَرُ
// تقاطعُ الإعداد والصلاحية، والمؤشَّرُ الواحدُ يتخطّى حوارَ الدفع.
part of 'settings_picpos_screen.dart';

/// أسماءُ الطرق كما يقرؤها صاحبُ المحلّ — لا كما تُخزَّن.
const Map<String, String> _paymentMethodLabels = <String, String>{
  'cash': 'نقدي',
  'card': 'بطاقة',
  'click': 'تحويل / كليك',
  'credit': 'آجل',
  'multiple': 'دفع متعدّد',
};

/// إظهارُ «إغلاق سريع» أو إخفاؤه — طلبُ المالك 2026-08-14.
///
/// هو الطريقُ الوحيدُ **بلا أيّ مصادقة** ويُصفّر الفرقَ (`actual = system`)،
/// فإخفاؤه يجعل كلَّ إغلاقٍ يمرّ ببطاقةٍ أو كلمةِ مرورٍ لمن يملك
/// `pos_shift_close`.
class _QuickCloseSettingTile extends ConsumerWidget {
  const _QuickCloseSettingTile();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final enabled = ref.watch(posQuickCloseEnabledProvider).value ?? true;
    return SwitchListTile(
      value: enabled,
      title: const Text('إظهار «إغلاق سريع»'),
      subtitle: const Text(
        'إغلاق بلا مصادقة يجعل الفرق صفراً — أطفئه ليمرّ كل إغلاق '
        'ببطاقة أو كلمة مرور.',
        style: TextStyle(fontSize: 12),
      ),
      secondary: const Icon(PhosphorIconsBold.lightning,
          color: AppColors.warning),
      onChanged: (v) async {
        await ref
            .read(settingsRepositoryProvider)
            .saveSetting('pos_quick_close_enabled', v.toString());
        ref.invalidate(posQuickCloseEnabledProvider);
      },
    );
  }
}

class _PaymentMethodsSettingsCard extends ConsumerStatefulWidget {
  const _PaymentMethodsSettingsCard();

  @override
  ConsumerState<_PaymentMethodsSettingsCard> createState() =>
      _PaymentMethodsSettingsCardState();
}

class _PaymentMethodsSettingsCardState
    extends ConsumerState<_PaymentMethodsSettingsCard> {
  bool _loading = true;

  /// المؤشَّرُ حالياً. يبدأ بالخمسة حين لا إعدادَ مخزَّناً — أي «بلا تضييق»،
  /// وهو نفسُ ما تقرؤه [parseEnabledPaymentMethods] من قيمةٍ غائبة.
  Set<String> _checked = paymentMethodPermissionCodes.keys.toSet();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final repo = ref.read(settingsRepositoryProvider);
    final raw = await repo.getSetting(enabledPaymentMethodsSettingKey);
    if (!mounted) return;
    setState(() {
      _checked = parseEnabledPaymentMethods(raw) ??
          paymentMethodPermissionCodes.keys.toSet();
      _loading = false;
    });
  }

  Future<void> _toggle(String method, bool value) async {
    // ⚠️ آخرُ طريقةٍ لا تُرفَع: تنصيبةٌ بصفرِ طرقٍ = تِلٌّ لا يبيع، ولا رسالةَ
    // خطأٍ تشرح للكاشير لماذا. المنعُ هنا لا في مسار الحفظ لأن الرفضَ
    // الصامتَ في الحفظ يبدو عطباً.
    final next = Set<String>.from(_checked);
    if (value) {
      next.add(method);
    } else {
      next.remove(method);
    }
    if (next.isEmpty) {
      AppToast.show(
        context,
        'لا بدّ من طريقة دفعٍ واحدةٍ على الأقلّ',
        type: ToastType.warning,
      );
      return;
    }

    setState(() => _checked = next);
    final repo = ref.read(settingsRepositoryProvider);
    await repo.saveSetting(
      enabledPaymentMethodsSettingKey,
      // الترتيبُ ثابتٌ بترتيب التعريف كي لا يتغيّر النصُّ المخزَّن بلا سبب —
      // فيقرأ المشخِّصُ فرقاً في القاعدة حيث لا فرقَ في المعنى.
      paymentMethodPermissionCodes.keys.where(next.contains).join(','),
    );
    // بلا هذا يبقى مسارُ البيع على القيمة القديمة حتّى إعادة التشغيل.
    ref.invalidate(posEnabledPaymentMethodsProvider);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    final fastPath = singlePaymentMethodFastPath(_checked);

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'الطرقُ المؤشَّرة وحدَها تظهر للكاشير عند إتمام الدفع — '
            'والصلاحياتُ تضيّق عليها ولا توسّعها.',
            style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 12),
          ..._paymentMethodLabels.entries.map(
            (e) => CheckboxListTile(
              value: _checked.contains(e.key),
              onChanged: (v) => _toggle(e.key, v ?? false),
              title: Text(e.value),
              dense: true,
              controlAffinity: ListTileControlAffinity.leading,
            ),
          ),
          if (fastPath != null) ...[
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.success.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: AppColors.success.withValues(alpha: 0.3),
                ),
              ),
              child: Row(
                children: [
                  const Icon(PhosphorIconsBold.lightning,
                      color: AppColors.success, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'طريقةٌ واحدةٌ مؤشَّرة (${_paymentMethodLabels[fastPath]}) '
                      '⇒ «إتمام الدفع» يحفظ مباشرةً بلا حوار.',
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
