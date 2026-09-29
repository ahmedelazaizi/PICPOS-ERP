import 'package:ural_erp/core/i18n/tr.dart';
// lib/presentation/settings_picpos/screens/guest_services_settings_picpos.dart
//
// إعداداتُ خدمات الضيف والعميل — بلاغُ المالك 2026-09-12:
// «معرفتنيش ازاى هظبط الاعداد بتاعهم وهم اصلا مش ظاهرين».
//
// ⚠️ **والبلاغُ كشف أخطرَ ممّا وصف.** رايةُ `table_bill_guest_order_enabled`
// شُحنت في ‎253 و‎254 ولها قارئٌ في `api_handler` وطابورٌ ومحرّكُ اعتمادٍ
// وبانرٌ للنادل ونقطتا API وثلاثةَ عشرَ اختبارَ تكامل — و**صفرُ كُتّابٍ في
// `lib/` كلِّها**. فالنصفُ الذي طلبه المالكُ صراحةً كان مطفأً إلى الأبد، ولا
// اختبارٌ لاحظ ذلك لأنّ اختبارات التكامل تزرع الرايةَ في قاعدتها بنفسها.
//
// ⚠️ **ولماذا هنا لا في حوار الطباعة وحدَه.** الإعدادُ الذي يعيش داخلَ حوارٍ
// يُفتَح لغرضٍ آخرَ (‏طباعةُ الأكواد) لا يجده من يبحث عنه — وهو عينُ ما
// وقع. والحوارُ يبقى للطباعة، والضبطُ يصير له موضعٌ يُقصَد.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/app_toast.dart';
import '../../../data/providers/feature_settings_providers.dart';
import '../../../services/api/table_bill_token.dart';
import '../widgets/settings_blocks.dart';

/// ضبطُ رمز حساب الطاولة — التشغيل، وطلبُ الضيف، والنشرُ على دومين.
class TableBillSettingsCard extends ConsumerWidget {
  const TableBillSettingsCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final enabled = ref.watch(tableBillQrEnabledProvider);
    final guestOrder = ref.watch(tableBillGuestOrderEnabledProvider);
    final publicBase = ref.watch(tableBillPublicBaseUrlProvider);

    final isOn = enabled.asData?.value ?? false;

    return SettingsRowsBody(
      children: [
        SettingsSwitchRow(
          first: true,
          icon: PhosphorIconsBold.qrCode,
          title: tr('رمز حساب الطاولة'),
          sub: tr('يقرأ الضيفُ حسابَ طاولته من هاتفه بلا تسجيل دخول'),
          value: isOn,
          onChanged: enabled.isLoading
              ? null
              : (v) => writeFeatureSetting(
                    ref,
                    kTableBillQrEnabledKey,
                    '$v',
                  ),
        ),
        // ⚠️ **ولا يظهر طلبُ الضيف إلّا والعرضُ مُشعَل**: الطلبُ يمرّ برمز
        // الجلسة الذي لا يُنال إلّا من القراءة، فإشعالُه وحدَه يُنتج رايةً
        // مُشعَلةً لا أثرَ لها — وهو أسوأُ من إخفائها.
        if (isOn)
          SettingsSwitchRow(
            icon: PhosphorIconsBold.forkKnife,
            title: tr('السماح للضيف بطلب أصناف'),
            sub: tr('الطلبُ لا يدخل الحسابَ إلّا باعتماد النادل'),
            value: guestOrder.asData?.value ?? false,
            onChanged: guestOrder.isLoading
                ? null
                : (v) => writeFeatureSetting(
                      ref,
                      kTableBillGuestOrderEnabledKey,
                      '$v',
                    ),
          ),
        if (isOn) _PublicBaseUrlRow(current: publicBase.asData?.value),
      ],
    );
  }
}

/// عنوانُ الخادم العامّ — فارغٌ يعني «على شبكة المحلّ وحدَها».
class _PublicBaseUrlRow extends ConsumerStatefulWidget {
  const _PublicBaseUrlRow({required this.current});

  final String? current;

  @override
  ConsumerState<_PublicBaseUrlRow> createState() => _PublicBaseUrlRowState();
}

class _PublicBaseUrlRowState extends ConsumerState<_PublicBaseUrlRow> {
  late final TextEditingController _ctrl =
      TextEditingController(text: widget.current ?? '');
  String? _error;

  @override
  void didUpdateWidget(covariant _PublicBaseUrlRow old) {
    super.didUpdateWidget(old);
    // ⚠️ ولا يُكتَب فوقَ ما يكتبه المستخدم: التحديثُ يقع حين تتبدّل القيمةُ
    // المحفوظةُ من سطحٍ آخر (‏حوارُ الطباعة) لا مع كلّ إعادة بناء.
    if (old.current != widget.current && !_focused) {
      _ctrl.text = widget.current ?? '';
    }
  }

  bool _focused = false;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final raw = _ctrl.text.trim();
    if (raw.isNotEmpty && normalizeTableBillBaseUrl(raw) == null) {
      setState(() => _error = tr('عنوانٌ غيرُ صالح — مثال: https://shop.com'));
      return;
    }
    setState(() => _error = null);
    await writeFeatureSetting(ref, kTableBillPublicBaseUrlKey, raw);
    if (mounted) {
      AppToast.show(context, raw.isEmpty ? tr('أُلغي النشر') : tr('حُفظ العنوان'));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(PhosphorIconsBold.globe,
                  size: 16, color: AppColors.warning),
              const SizedBox(width: 8),
              Expanded(
                child: Focus(
                  onFocusChange: (f) => _focused = f,
                  child: TextField(
                    controller: _ctrl,
                    textDirection: TextDirection.ltr,
                    style: const TextStyle(fontSize: 12.5),
                    decoration: InputDecoration(
                      isDense: true,
                      labelText: tr('نشرُ الخادم على دومين (اختياريّ)'),
                      hintText: 'https://shop.example.com',
                      errorText: _error,
                      helperMaxLines: 3,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton.tonal(
                onPressed: _save,
                child:  Text(tr('حفظ')),
              ),
            ],
          ),
          const SizedBox(height: 6),
          // ⚠️ **والتحذيرُ جزءٌ من الإعداد لا زينة.** النشرُ يُسقط الحاجزَ
          // الأوّلَ كلَّه (‏شبكةَ المحلّ)، فمن صوّر الرمزَ المطبوعَ مرّةً
          // يقرأ من أيّ مكانٍ في الدنيا. ولذلك يُشترَط رقمُ الجلسة تلقائيّاً.
          Text(
            widget.current == null
                ? tr('اتركه فارغاً ليعمل الرمزُ على شبكة المحلّ وحدَها.')
                : tr('منشورٌ على دومين — ويُطلَب من الضيف رقمُ الطاولة (٤ خانات) قبل طلب الحساب أو إضافة الأصناف، يقوله له النادل.'),
            style: TextStyle(
              fontSize: 11,
              color: widget.current == null
                  ? AppColors.textMuted
                  : AppColors.warning,
            ),
          ),
        ],
      ),
    );
  }
}

/// ضبطُ رسائل العملاء على واتساب — رمزُ الدولة.
class WhatsAppSettingsCard extends ConsumerStatefulWidget {
  const WhatsAppSettingsCard({super.key});

  @override
  ConsumerState<WhatsAppSettingsCard> createState() =>
      _WhatsAppSettingsCardState();
}

class _WhatsAppSettingsCardState extends ConsumerState<WhatsAppSettingsCard> {
  final _ctrl = TextEditingController();
  bool _loaded = false;
  String? _error;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final raw = _ctrl.text.replaceAll(RegExp(r'[^0-9]'), '');
    if (raw.isEmpty || raw.length > 4) {
      setState(() => _error = tr('رمزٌ غيرُ صالح — مثال: 20 أو 966'));
      return;
    }
    setState(() => _error = null);
    await writeFeatureSetting(ref, kWhatsAppCountryCodeKey, raw);
    if (mounted) AppToast.show(context, tr('حُفظ رمزُ الدولة'));
  }

  @override
  Widget build(BuildContext context) {
    final code = ref.watch(whatsAppCountryCodeProvider);
    // أوّلُ وصولٍ للقيمة يملأ الحقل؛ وما بعده بيدِ المستخدم.
    if (!_loaded && code.asData != null) {
      _loaded = true;
      _ctrl.text = code.asData!.value;
    }

    return SettingsRowsBody(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(PhosphorIconsBold.whatsappLogo,
                      size: 16, color: AppColors.success),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 120,
                    child: TextField(
                      controller: _ctrl,
                      textDirection: TextDirection.ltr,
                      keyboardType: TextInputType.number,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        LengthLimitingTextInputFormatter(4),
                      ],
                      style: const TextStyle(fontSize: 12.5),
                      decoration: InputDecoration(
                        isDense: true,
                        labelText: tr('رمز الدولة'),
                        hintText: '20',
                        prefixText: '+',
                        errorText: _error,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.tonal(
                    onPressed: _save,
                    child:  Text(tr('حفظ')),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              // ⚠️ ولا يُفترَض رمزٌ في الشيفرة: المنتجُ يُشحَن في أكثرَ من
              // سوق، وافتراضُ دولةٍ يُشوِّه أرقامَ السوق الآخر كلَّها بصمت.
               Text(
                tr('يُضاف إلى الأرقام المحلّيّة قبل فتح واتساب. بدونه لا يُبنى رابطٌ أصلاً — لأنّ رابطاً برقمٍ ناقصٍ يفتح «الرقم غير صالح» فيُظنّ أنّ العميل ليس على واتساب.'),
                style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
