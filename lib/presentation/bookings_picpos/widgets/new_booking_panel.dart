import 'package:ural_erp/core/i18n/tr.dart';
// لوحُ «حجز جديد».
//
// ⚠️ **والمدّةُ تُعرَض ولا تُكتب**: التصميمُ يرسمها حقلَ إدخال، لكنّ
// `createBooking` يشتقّ `endsAt` من `service.durationMinutes` — والمدّةُ
// **تُخزَّن ولا تُحسَب** عمداً كي لا يغيّر تعديلُ الخدمةِ الشهرَ القادم طولَ
// حجوزٍ ماضية. فحقلٌ يقبل تحريراً ثمّ يُتجاهَل أسوأُ من حقلٍ مقفول: يُعرَض
// رقمُ الخدمة ويُقال إنه منها.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/number_utils.dart';
import '../../../data/providers/providers.dart';
import '../../picpos_shell/picpos_dialog.dart';

/// يفتح لوحَ الحجز الجديد. يعيد `true` حين يُحفَظ حجزٌ فعلاً.
Future<bool?> showNewBookingPanel(BuildContext context, {DateTime? onDay}) {
  return showDialog<bool>(
    context: context,
    builder: (_) => NewBookingPanel(onDay: onDay),
  );
}

class NewBookingPanel extends ConsumerStatefulWidget {
  const NewBookingPanel({super.key, this.onDay});

  final DateTime? onDay;

  @override
  ConsumerState<NewBookingPanel> createState() => _NewBookingPanelState();
}

class _NewBookingPanelState extends ConsumerState<NewBookingPanel> {
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _deposit = TextEditingController(text: '0');
  final _notes = TextEditingController();

  int? _serviceId;
  int? _resourceId;
  late DateTime _date;
  TimeOfDay _time = const TimeOfDay(hour: 10, minute: 0);
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final d = widget.onDay ?? DateTime.now();
    _date = DateTime(d.year, d.month, d.day);
    _deposit.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _deposit.dispose();
    _notes.dispose();
    super.dispose();
  }

  DateTime get _startsAt => DateTime(
      _date.year, _date.month, _date.day, _time.hour, _time.minute);

  double get _depositValue =>
      NumberUtils.tryParseLocale(_deposit.text) ?? 0;

  /// رسالةُ المنع أو `null`. الترتيبُ مقصود: الخدمةُ أوّلاً لأنّ كلَّ ما
  /// بعدها (المدّةُ والسعرُ) يُشتقّ منها.
  String? _blockingReason(List<BookingService> services) {
    // ⚠️ «اختر الخدمة» فوق قائمةٍ فارغةٍ تتّهم المستخدمَ بأنه لم يختر، وهو
    //    قد أنشأ ما يظنّه الخدمة. والحجوزاتُ لها جدولُها المستقلُّ
    //    (`booking_services`): صنفُ المخزون من نوع «خدمة» ارتباطٌ اختياريٌّ
    //    للتفويتر لا مصدرٌ لهذه القائمة. فالرسالةُ تسمّي الحقيقةَ وتدلّ على
    //    الزرّ الذي يُنشئها (‏بلاغُ المالك 2026-08-23).
    if (services.isEmpty) {
      return tr('لا خدمات معرَّفة — أضِفها من زرّ «الخدمات» أعلى الشاشة');
    }
    if (_serviceId == null) return tr('اختر الخدمة');
    if (_name.text.trim().isEmpty) return tr('اكتب اسم العميل');
    if (_startsAt.isBefore(DateTime.now())) {
      return tr('لا يمكن الحجز في الماضي — اختر وقتاً قادماً');
    }
    final svc = services.where((s) => s.id == _serviceId).firstOrNull;
    if (svc != null && _depositValue > svc.price) {
      return tr('العربون أكبر من سعر الخدمة');
    }
    if (_depositValue < 0) return tr('العربون لا يكون سالباً');
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final services = ref.watch(bookingServicesProvider).value ?? const [];
    final resources = ref.watch(bookingResourcesProvider).value ?? const [];
    final svc = services.where((s) => s.id == _serviceId).firstOrNull;
    final blocked = _blockingReason(services);

    return PicPosDialog(
      icon: PhosphorIconsBold.calendarPlus,
      title: tr('حجز جديد'),
      subtitle: tr('المدّة والسعر يأتيان من الخدمة المختارة'),
      width: 720,
      primaryAction: PicPosDialogAction(
        label: tr('حفظ الحجز'),
        icon: PhosphorIconsBold.check,
        busy: _saving,
        onPressed: blocked != null || _saving ? null : _save,
      ),
      body: [
        Row(
          children: [
            Expanded(child: _field(tr('اسم العميل'), _name)),
            const SizedBox(width: 10),
            Expanded(
              child: _field(tr('رقم الهاتف'), _phone,
                  keyboard: TextInputType.phone, ltr: true),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _labelled(
                tr('الخدمة'),
                DropdownButtonFormField<int>(
                  initialValue: _serviceId,
                  isExpanded: true,
                  decoration: _decoration(),
                  // ⚠️ والتلميحُ يتبع الحقيقةَ كالمنع: «اختر» فوق قائمةٍ
                  //    فارغةٍ دعوةٌ إلى فعلٍ غيرِ ممكن.
                  hint: Text(services.isEmpty
                      ? tr('لا خدمات معرَّفة')
                      : tr('اختر الخدمة')),
                  items: [
                    for (final s in services)
                      DropdownMenuItem(value: s.id, child: Text(s.name)),
                  ],
                  onChanged: (v) => setState(() => _serviceId = v),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _labelled(
                tr('الموظف / المورد'),
                DropdownButtonFormField<int?>(
                  initialValue: _resourceId,
                  isExpanded: true,
                  decoration: _decoration(),
                  // ‏«بلا إسناد» خيارٌ حقيقيٌّ لا نقص: حجزٌ بلا موردٍ مسموحٌ
                  // في المحرّك (لا أحدَ يتعارض عليه) وهو نموذجُ الانتظار.
                  items: [
                     DropdownMenuItem(value: null, child: Text(tr('بلا إسناد'))),
                    for (final r in resources)
                      DropdownMenuItem(value: r.id, child: Text(r.name)),
                  ],
                  onChanged: (v) => setState(() => _resourceId = v),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _labelled(
                tr('التاريخ'),
                _tappable(
                  '${_date.year}/${_two(_date.month)}/${_two(_date.day)}',
                  PhosphorIconsBold.calendarBlank,
                  _pickDate,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _labelled(
                tr('وقت البداية'),
                _tappable(
                  '${_two(_time.hour)}:${_two(_time.minute)}',
                  PhosphorIconsBold.clock,
                  _pickTime,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _labelled(
                tr('المدة'),
                _readOnly(
                  svc == null
                      ? '—'
                      : tr('{p0} دقيقة{p1}', {'p0': svc.durationMinutes, 'p1': svc.bufferMinutes > 0 ? ' (+${svc.bufferMinutes} فاصل)' : ''}),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _field(
                tr('العربون ({p0})', {'p0': AppConstants.currencySymbol}),
                _deposit,
                keyboard: const TextInputType.numberWithOptions(decimal: true),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _labelled(
                tr('إجمالي الخدمة'),
                _readOnly(svc == null
                    ? '—'
                    : '${svc.price.toStringAsFixed(AppConstants.decimalPlaces)} '
                        '${AppConstants.currencySymbol}'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _field(tr('ملاحظات'), _notes),
        if (_depositValue > 0) ...[
          const SizedBox(height: 12),
          // ⚠️ يُقال صراحةً: العربونُ **مالٌ يُقبَض الآن** لا رقمٌ يُكتب.
          // يُنشئ سندَ قبضٍ مقابلَه حسابُ التزامٍ، ويُخصَم عند التفويتر.
          _note(
            PhosphorIconsBold.wallet,
            tr('سيُسجَّل سندُ قبضٍ بالعربون فور الحفظ، ويُخصَم من الفاتورة عند التفويتر.'),
            AppColors.info,
          ),
        ],
        if (blocked != null) ...[
          const SizedBox(height: 10),
          _note(PhosphorIconsBold.warningCircle, blocked, AppColors.warning),
        ],
        if (_error != null) ...[
          const SizedBox(height: 10),
          _note(PhosphorIconsBold.xCircle, _error!, AppColors.error),
        ],
      ],
    );
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final auth = ref.read(authProvider);
      await ref.read(bookingActionsServiceProvider).create(
            customerName: _name.text.trim(),
            customerPhone:
                _phone.text.trim().isEmpty ? null : _phone.text.trim(),
            serviceId: _serviceId!,
            resourceId: _resourceId,
            startsAt: _startsAt,
            depositAmount: _depositValue,
            notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
            userId: auth.user?.id,
            userName: auth.user?.displayName ?? '',
          );
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      // ⚠️ الفشلُ يُقال ولا يُبتلَع: تعارضُ موعدٍ أو حجزٌ في الماضي أو تعذّرُ
      // ترحيلِ العربون كلُّها ترمي برسائلَ مفهومة، وابتلاعُها يترك اللوحَ
      // مفتوحاً بلا سبب.
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime.now().subtract(const Duration(days: 1)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(context: context, initialTime: _time);
    if (picked != null) setState(() => _time = picked);
  }

  static String _two(int v) => v.toString().padLeft(2, '0');

  InputDecoration _decoration() => const InputDecoration(
        isDense: true,
        border: OutlineInputBorder(),
        contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 12),
      );

  Widget _labelled(String label, Widget child) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: AppColors.textMuted,
              )),
          const SizedBox(height: 4),
          child,
        ],
      );

  Widget _field(
    String label,
    TextEditingController controller, {
    TextInputType? keyboard,
    bool ltr = false,
  }) =>
      _labelled(
        label,
        TextField(
          controller: controller,
          keyboardType: keyboard,
          textDirection: ltr ? TextDirection.ltr : null,
          onChanged: (_) => setState(() {}),
          decoration: _decoration(),
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
        ),
      );

  Widget _readOnly(String value) => Container(
        height: 44,
        alignment: AlignmentDirectional.centerStart,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          border: Border.all(color: Theme.of(context).dividerColor),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w800,
            color: AppColors.textMuted,
          ),
        ),
      );

  Widget _tappable(String value, IconData icon, VoidCallback onTap) =>
      InkWell(
        onTap: onTap,
        child: Container(
          height: 44,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            border: Border.all(color: Theme.of(context).dividerColor),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Row(
            children: [
              Icon(icon, size: 15, color: AppColors.textMuted),
              const SizedBox(width: 8),
              Text(value,
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w700)),
            ],
          ),
        ),
      );

  Widget _note(IconData icon, String text, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: .10),
          border: Border.all(color: color.withValues(alpha: .30)),
          borderRadius: BorderRadius.circular(9),
        ),
        child: Row(
          children: [
            Icon(icon, size: 15, color: color),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                text,
                style: TextStyle(
                    fontSize: 11.5, fontWeight: FontWeight.w700, color: color),
              ),
            ),
          ],
        ),
      );
}
