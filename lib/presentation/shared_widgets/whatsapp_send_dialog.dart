import 'package:ural_erp/core/i18n/tr.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/permissions/permission_codes.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/app_toast.dart';
import '../../data/providers/providers.dart';
import '../../data/providers/feature_settings_providers.dart';
import '../../domain/models/whatsapp_message.dart';
import '../widgets/permission_guard.dart';

/// حوارُ إرسالِ رسالةٍ للعميل على واتساب.
///
/// ═══ ما يفعله هذا الحوارُ ولا يفعله ═══
///
/// يفتح واتساب على جهاز المستخدم بالنصّ مملوءاً؛ **والمستخدمُ يضغط «إرسال»
/// بنفسه**. فلا إرسالَ آليّ، ولا مرفقَ PDF، ولا إيصالَ تسليم — وهو ما يترتّب
/// على منفَذ `wa.me` الذي اختاره المالك 2026-09-12، لا نقصٌ في التنفيذ.
///
/// ⚠️ **ولذلك لا تُسجَّل حالةُ «أُرسِل».** لا شيءَ يعود من واتساب، وعمودٌ
/// يقول «أُرسِلت» يكذب على من يقرؤه بعد شهر. المسجَّلُ «فُتح واتساب».
///
/// ⚠️ **والنصُّ قابلٌ للتعديل قبل الفتح** عن قصد: الموظّفُ يعرف زبونَه، وقد
/// يضيف سطراً أو يحذفه. ومنعُه لا يحمي شيئاً — هو من سيضغط «إرسال» أصلاً.
class WhatsAppSendDialog extends ConsumerStatefulWidget {
  const WhatsAppSendDialog({
    super.key,
    required this.title,
    required this.rawPhone,
    required this.message,
    this.actionLogLabel,
  });

  /// عنوانُ الحوار — «إرسال الفاتورة» · «إرسال كشف الحساب» · «مطالبة».
  final String title;

  /// رقمُ العميل كما هو في القاعدة — يُسوَّى هنا.
  final String? rawPhone;

  /// النصُّ المقترَح.
  final String message;

  /// وصفُ الفعل في سجلّ النشاط.
  final String? actionLogLabel;

  /// يفتح الحوارَ **بعد** فحص الصلاحية.
  ///
  /// ⚠️ **والفحصُ هنا لا في مدخلِ قائمةٍ منبثقة**: مدخلُ القائمة يبقى قابلاً
  /// للاختيار مهما لُفّ نصُّه، فالحراسةُ بلفّه زينةٌ لا ضابط — وهو درسٌ
  /// مكتوبٌ في هذا المستودع بنصّه.
  static Future<void> show(
    BuildContext context,
    WidgetRef ref, {
    required String title,
    required String? rawPhone,
    required String message,
    String? actionLogLabel,
  }) async {
    final granted = await ensurePermission(
      ref,
      context,
      PermissionCodes.customerMessageSend,
      actionName: title,
    );
    if (!granted || !context.mounted) return;

    await showDialog<void>(
      context: context,
      builder: (_) => WhatsAppSendDialog(
        title: title,
        rawPhone: rawPhone,
        message: message,
        actionLogLabel: actionLogLabel,
      ),
    );
  }

  @override
  ConsumerState<WhatsAppSendDialog> createState() =>
      _WhatsAppSendDialogState();
}

class _WhatsAppSendDialogState extends ConsumerState<WhatsAppSendDialog> {
  late final TextEditingController _text =
      TextEditingController(text: widget.message);
  late final TextEditingController _phone =
      TextEditingController(text: widget.rawPhone ?? '');

  @override
  void dispose() {
    _text.dispose();
    _phone.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cc = ref.watch(whatsAppCountryCodeProvider).asData?.value ?? '';
    final normalized = normalizeWhatsAppPhone(
      _phone.text,
      defaultCountryCode: cc,
    );

    return Directionality(
      textDirection: TextDirection.rtl,
      child: AlertDialog(
        title: Row(
          children: [
            const Icon(PhosphorIconsBold.whatsappLogo,
                color: AppColors.success),
            const SizedBox(width: 8),
            Text(widget.title),
          ],
        ),
        content: SizedBox(
          width: 480,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ⚠️ **ويُضبَط من هنا لا من شاشةٍ أخرى.** هذا هو الموضعُ الذي
              // يُكتشَف فيه غيابُه — والإحالةُ إلى الإعدادات تعني أن يترك
              // الموظّفُ زبونَه ويبحث، ثمّ يعود فينسى ما كان يفعل.
              if (cc.isEmpty) _CountryCodeField(onSaved: _refreshCode),
              TextField(
                controller: _phone,
                onChanged: (_) => setState(() {}),
                decoration:  InputDecoration(
                  isDense: true,
                  labelText: tr('رقم العميل'),
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 6),
              // ⚠️ الرقمُ المسوّى يُعرَض قبل الفتح: رقمٌ يبدو سليماً على
              // الشاشة قد يُنتج رابطاً ميّتاً، و`wa.me` لا يقول لماذا —
              // يعرض «الرقمُ غيرُ صالح» فيظنّ الموظّفُ أنّ العميلَ ليس عليه.
              Text(
                normalized == null
                    ? tr('لا يمكن تسويةُ الرقم — راجِعه')
                    : tr('سيُفتَح على: {normalized}', {'normalized': normalized}),
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.bold,
                  color: normalized == null
                      ? AppColors.error
                      : AppColors.textMuted,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _text,
                maxLines: 8,
                minLines: 5,
                decoration:  InputDecoration(
                  labelText: tr('نصّ الرسالة'),
                  alignLabelWithHint: true,
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              _note(
                color: AppColors.info,
                icon: PhosphorIconsBold.info,
                text: tr('يفتح واتساب بالنصّ جاهزاً — وأنت من يضغط «إرسال». ولا يصل النظامَ إشعارُ تسليم.'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child:  Text(tr('إلغاء')),
          ),
          ElevatedButton.icon(
            onPressed: normalized == null ? null : () => _open(normalized),
            icon: const Icon(PhosphorIconsBold.whatsappLogo, size: 16),
            label:  Text(tr('فتح واتساب')),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.success,
            ),
          ),
        ],
      ),
    );
  }

  void _refreshCode() => ref.invalidate(whatsAppCountryCodeProvider);

  Widget _note({
    required Color color,
    required IconData icon,
    required String text,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(9),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 15, color: color),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 11.5))),
        ],
      ),
    );
  }

  Future<void> _open(String phone) async {
    final url = Uri.parse(
      buildWhatsAppUrl(phone: phone, message: _text.text),
    );
    // `externalApplication` لا `platformDefault`: المطلوبُ تطبيقُ واتساب أو
    // المتصفّح خارجَ التطبيق، لا نافذةٌ مضمَّنةٌ لا يملك المستخدمُ فيها حسابَه.
    final opened = await launchUrl(url, mode: LaunchMode.externalApplication);
    if (!mounted) return;

    if (!opened) {
      AppToast.show(context, tr('تعذّر فتح واتساب على هذا الجهاز'));
      return;
    }
    try {
      final user = ref.read(authProvider).user;
      if (user != null) {
        // ⚠️ «فُتح واتساب» لا «أُرسِلت الرسالة» — لا إيصالَ يعود، وسجلٌّ
        // يقول غيرَ ذلك يكذب على من يقرؤه في نزاعٍ بعد شهر.
        ref.read(activityLoggerProvider).logNavigation(
              user.id,
              user.displayName,
              tr('فُتح واتساب — {p0} ({phone})', {'p0': widget.actionLogLabel ?? widget.title, 'phone': phone}),
            );
      }
    } catch (_) {
      // السجلُّ أثرٌ لا شرطٌ — إخفاقُه لا يُبطل ما وقع فعلاً.
    }
    if (mounted) Navigator.pop(context);
  }
}

/// ضبطُ رمز الدولة عند أوّل استعمال.
///
/// ⚠️ **ولا قيمةَ مقترحةٌ مسبقاً.** رمزٌ معروضٌ سلفاً يُحفَظ بضغطةٍ واحدةٍ بلا
/// قراءة، فتُشوَّه أرقامُ سوقٍ كامل. والحقلُ يبقى فارغاً حتى يكتبه من يعرف.
class _CountryCodeField extends ConsumerStatefulWidget {
  const _CountryCodeField({required this.onSaved});

  final VoidCallback onSaved;

  @override
  ConsumerState<_CountryCodeField> createState() => _CountryCodeFieldState();
}

class _CountryCodeFieldState extends ConsumerState<_CountryCodeField> {
  final _ctrl = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final raw = _ctrl.text.trim().replaceAll('+', '');
    // نفسُ حدّ `normalizeWhatsAppPhone` — رمزٌ خارجَه يُنتج أرقاماً مشوَّهة.
    if (raw.isEmpty ||
        raw.length > 4 ||
        !RegExp(r'^\d+$').hasMatch(raw)) {
      setState(() => _error = tr('أرقامٌ فقط — مثال: 20 أو 966'));
      return;
    }
    setState(() => _error = null);
    await writeFeatureSetting(ref, kWhatsAppCountryCodeKey, raw);
    widget.onSaved();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.error.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.error.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
           Text(
            tr('رمزُ الدولة غيرُ مضبوط'),
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 12.5,
              color: AppColors.error,
            ),
          ),
          const SizedBox(height: 2),
           Text(
            tr('يلزم لتحويل أرقام العملاء المحلّيّة إلى الصيغة الدوليّة.'),
            style: const TextStyle(fontSize: 11),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _ctrl,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: tr('مثال: 20'),
                    errorText: _error,
                    border: const OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton(onPressed: _save, child:  Text(tr('حفظ'))),
            ],
          ),
        ],
      ),
    );
  }
}
