import 'package:picpos_erp/core/i18n/tr.dart';
// محرِّرا الخدمة والمورد — وهما ما كان ينقص ليمكن **الربطُ** أصلاً.
//
// بلاغُ المالك 2026-08-23: «ازاى هربط الخدمة بمورد او جهاز». والقياسُ كشف أنّ
// المستودعَ لم يكن يملك موضعاً واحداً يكتب خدمةً أو مورداً — فلا ربطَ ولا
// تعريف.
//
// ⚠️ **وتوضيحُ العلاقة جزءٌ من الحلّ**: لا يوجد ربطٌ «خدمة ⇐ مورد» في
// النموذج، والحجزُ يختار الاثنين **مستقلَّين**. الربطُ الوحيدُ الموجود —
// وهو المطلوبُ للتفويتر — هو «خدمة ⇐ صنفٌ من نوع خدمة». فيُقال ذلك في
// الشاشة بدل أن يبحث المستخدمُ عن خيارٍ لا وجودَ له.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../core/config/app_config.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/number_utils.dart';
import '../../../data/providers/providers.dart';
import '../../picpos_shell/picpos_dialog.dart';

const _palette = [
  '#0250D3',
  '#8B5CF6',
  '#14B8A6',
  '#F59E0B',
  '#EF4444',
  '#22C55E',
];

/// موظَّفو الموارد البشريّة — لربطِ موردِ الحجز بملفّه.
///
/// ⚠️ الربطُ **اختياريٌّ وفي اتّجاهٍ واحد**: لا كلُّ موظَّفٍ يُحجَز وقتُه
/// (المحاسبُ وأمينُ المخزن)، ولا كلُّ موردٍ موظَّفٌ (الأجهزةُ والغرف). ولذلك
/// يُختار من هنا ولا تُبنى القائمةُ من `employees` تلقائيّاً.
final bookingLinkableEmployeesProvider =
    StreamProvider.autoDispose<List<Employee>>(
  (ref) => ref.watch(databaseProvider).watchAllEmployees(),
);

Future<bool?> showServiceEditor(BuildContext context, {BookingService? existing}) =>
    showDialog<bool>(
      context: context,
      builder: (_) => _ServiceEditor(existing: existing),
    );

Future<bool?> showResourceEditor(BuildContext context,
        {BookingResource? existing}) =>
    showDialog<bool>(
      context: context,
      builder: (_) => _ResourceEditor(existing: existing),
    );

// ═════════════════════════ الخدمة ═════════════════════════

class _ServiceEditor extends ConsumerStatefulWidget {
  const _ServiceEditor({this.existing});
  final BookingService? existing;

  @override
  ConsumerState<_ServiceEditor> createState() => _ServiceEditorState();
}

class _ServiceEditorState extends ConsumerState<_ServiceEditor> {
  late final _name = TextEditingController(text: widget.existing?.name ?? '');
  late final _duration = TextEditingController(
      text: '${widget.existing?.durationMinutes ?? 30}');
  late final _buffer =
      TextEditingController(text: '${widget.existing?.bufferMinutes ?? 0}');
  late final _price =
      TextEditingController(text: '${widget.existing?.price ?? 0}');

  late String _color = widget.existing?.colorHex ?? _palette.first;
  late int? _productId = widget.existing?.productId;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _duration.dispose();
    _buffer.dispose();
    _price.dispose();
    super.dispose();
  }

  void _rebuild() => setState(() {});

  int get _dur => int.tryParse(_duration.text.trim()) ?? 0;
  int get _buf => int.tryParse(_buffer.text.trim()) ?? 0;
  double get _priceVal => NumberUtils.tryParseLocale(_price.text) ?? 0;

  String? get _blocked {
    if (_name.text.trim().isEmpty) return tr('اكتب اسم الخدمة');
    if (_dur <= 0) return tr('المدّة يجب أن تكون أكبر من صفر');
    if (_buf < 0) return tr('الفاصل لا يكون سالباً');
    if (_priceVal < 0) return tr('السعر لا يكون سالباً');
    return null;
  }

  @override
  Widget build(BuildContext context) {
    // ⚠️ **الأصنافُ الخدميّةُ وحدَها**: ربطُ خدمةٍ بصنفٍ مخزونيٍّ يجعل
    // التفويترَ يخصم من المخزون شيئاً لا يُخزَّن — والمحرّكُ يرفضه. فلا
    // يُعرَض في المنتقي أصلاً بدل أن يُختار ثمّ يُرفَض.
    final serviceProducts = (ref.watch(allProductsProvider).value ?? const [])
        .where((p) => p.productType == 'service')
        .toList();

    return PicPosDialog(
      icon: PhosphorIconsBold.scissors,
      title: widget.existing == null ? tr('خدمة جديدة') : tr('تعديل الخدمة'),
      subtitle: tr('المدّة والسعر يُستعملان في كلّ حجزٍ على هذه الخدمة'),
      width: 640,
      primaryAction: PicPosDialogAction(
        label: tr('حفظ'),
        icon: PhosphorIconsBold.check,
        busy: _busy,
        onPressed: _blocked != null || _busy ? null : _save,
      ),
      body: [
        _text(tr('اسم الخدمة'), _name, onChanged: _rebuild),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
                child: _text(tr('المدة (دقيقة)'), _duration, keyboard: TextInputType.number, onChanged: _rebuild)),
            const SizedBox(width: 10),
            Expanded(
                child: _text(tr('فاصل بعدها (دقيقة)'), _buffer, keyboard: TextInputType.number, onChanged: _rebuild)),
            const SizedBox(width: 10),
            Expanded(
              child: _text(
                tr('السعر ({p0})', {'p0': AppConstants.currencySymbol}),
                _price,
                keyboard:
                    const TextInputType.numberWithOptions(decimal: true),
                onChanged: _rebuild,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _labelled(tr('اللون'), _colorRow()),
        const SizedBox(height: 12),
        _labelled(
          tr('الصنف المرتبط (لتفويتر الحجوزات)'),
          DropdownButtonFormField<int?>(
            initialValue: _productId,
            isExpanded: true,
            decoration: _dec(),
            items: [
               DropdownMenuItem(value: null, child: Text(tr('بلا ربط'))),
              for (final p in serviceProducts)
                DropdownMenuItem(value: p.id, child: Text('${p.name} · ${p.code}')),
            ],
            onChanged: (v) => setState(() => _productId = v),
          ),
        ),
        const SizedBox(height: 8),
        _note(
          PhosphorIconsBold.info,
          serviceProducts.isEmpty
              ? tr('لا توجد أصنافٌ من نوع «خدمة» بعد. أنشئ صنفاً ونوعُه «خدمة» من شاشة الأصناف، ثمّ اربطه هنا — بدونه لا تُفوتَر حجوزُ هذه الخدمة.')
              : tr('بلا ربطٍ بصنف، لا يمكن تحويلُ حجوزِ هذه الخدمة إلى فاتورة. وتُعرَض الأصنافُ الخدميّةُ وحدَها هنا عن قصد.'),
          serviceProducts.isEmpty ? AppColors.warning : AppColors.info,
        ),
        // ⚠️ يُقال صراحةً أنّ «الربطَ بمورد» لا وجودَ له — وإلّا بحث عنه
        // المستخدمُ في كلّ شاشة.
        const SizedBox(height: 8),
        _note(
          PhosphorIconsBold.users,
          tr('الخدمةُ لا تُربَط بموظَّفٍ أو جهاز: الإسنادُ يقع **عند كلّ حجز** على حدة، فيمكن لأيّ موظَّفٍ أداءُ أيّ خدمة.'),
          AppColors.textMuted,
        ),
        if (_blocked != null) ...[
          const SizedBox(height: 10),
          _note(PhosphorIconsBold.warningCircle, _blocked!, AppColors.warning),
        ],
        if (_error != null) ...[
          const SizedBox(height: 10),
          _note(PhosphorIconsBold.xCircle, _error!, AppColors.error),
        ],
      ],
    );
  }

  Widget _colorRow() => Row(
        children: [
          for (final c in _palette) ...[
            InkWell(
              onTap: () => setState(() => _color = c),
              borderRadius: BorderRadius.circular(999),
              child: Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: _hex(c),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: _color == c ? AppColors.textPrimary : Colors.transparent,
                    width: 2.5,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
          ],
        ],
      );

  Future<void> _save() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(databaseProvider).upsertBookingService(
            id: widget.existing?.id,
            name: _name.text,
            durationMinutes: _dur,
            bufferMinutes: _buf,
            price: _priceVal,
            colorHex: _color,
            productId: _productId,
          );
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) setState(() => _error = _clean(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}

// ═════════════════════════ المورد ═════════════════════════

class _ResourceEditor extends ConsumerStatefulWidget {
  const _ResourceEditor({this.existing});
  final BookingResource? existing;

  @override
  ConsumerState<_ResourceEditor> createState() => _ResourceEditorState();
}

class _ResourceEditorState extends ConsumerState<_ResourceEditor> {
  late final _name = TextEditingController(text: widget.existing?.name ?? '');
  late final _role = TextEditingController(text: widget.existing?.role ?? '');
  late final _phone = TextEditingController(text: widget.existing?.phone ?? '');

  late String _kind = widget.existing?.kind ?? 'staff';
  late int? _employeeId = widget.existing?.employeeId;
  late String _color = widget.existing?.colorHex ?? _palette.first;
  late TimeOfDay? _start = _toTime(widget.existing?.shiftStartMinutes);
  late TimeOfDay? _end = _toTime(widget.existing?.shiftEndMinutes);
  bool _busy = false;
  String? _error;

  static TimeOfDay? _toTime(int? m) =>
      m == null ? null : TimeOfDay(hour: (m ~/ 60) % 24, minute: m % 60);
  static int? _toMinutes(TimeOfDay? t) =>
      t == null ? null : t.hour * 60 + t.minute;

  @override
  void dispose() {
    _name.dispose();
    _role.dispose();
    _phone.dispose();
    super.dispose();
  }

  void _rebuild() => setState(() {});

  String? get _blocked =>
      _name.text.trim().isEmpty ? tr('اكتب اسم الموظَّف أو الجهاز') : null;

  /// مُنتقي الموظَّف — و«بلا ربط» خيارٌ صريحٌ لا غيابُ اختيار.
  ///
  /// ⚠️ واختيارُ موظَّفٍ يملأ الاسمَ **إن كان فارغاً فقط**: الكتابةُ فوقَ اسمٍ
  /// كتبه المستخدمُ بيده مصادرةٌ لقراره — قد يسمّي الموردَ «كرسي محمد».
  Widget _employeePicker() {
    final employees =
        ref.watch(bookingLinkableEmployeesProvider).value ?? const <Employee>[];

    // موظَّفٌ مربوطٌ ثمّ حُذف: قيمةٌ لا تقابل عنصراً تُسقط `DropdownButton`.
    final known = employees.any((e) => e.id == _employeeId);
    final value = known ? _employeeId : null;

    return DropdownButtonFormField<int?>(
      initialValue: value,
      isExpanded: true,
      decoration: _dec(),
      hint: Text(employees.isEmpty ? tr('لا موظَّفين مسجَّلين') : tr('بلا ربط')),
      items: [
         DropdownMenuItem<int?>(value: null, child: Text(tr('بلا ربط'))),
        for (final e in employees)
          DropdownMenuItem<int?>(value: e.id, child: Text(e.name)),
      ],
      onChanged: (v) => setState(() {
        _employeeId = v;
        if (v != null && _name.text.trim().isEmpty) {
          _name.text = employees.firstWhere((e) => e.id == v).name;
        }
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PicPosDialog(
      icon: PhosphorIconsBold.users,
      title: widget.existing == null ? tr('مورد جديد') : tr('تعديل المورد'),
      subtitle: tr('موظَّفٌ أو جهازٌ تُسنَد إليه الحجوزات'),
      width: 640,
      primaryAction: PicPosDialogAction(
        label: tr('حفظ'),
        icon: PhosphorIconsBold.check,
        busy: _busy,
        onPressed: _blocked != null || _busy ? null : _save,
      ),
      body: [
        Row(
          children: [
            Expanded(child: _text(tr('الاسم'), _name, onChanged: _rebuild)),
            const SizedBox(width: 10),
            Expanded(child: _text(tr('الدور (اختياري)'), _role, onChanged: _rebuild)),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _labelled(
                tr('النوع'),
                SegmentedButton<String>(
                  segments:  [
                    ButtonSegment(value: 'staff', label: Text(tr('موظَّف'))),
                    ButtonSegment(value: 'device', label: Text(tr('جهاز'))),
                  ],
                  selected: {_kind},
                  onSelectionChanged: (s) => setState(() => _kind = s.first),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
                child: _text(tr('الهاتف (اختياري)'), _phone, keyboard: TextInputType.phone, onChanged: _rebuild)),
          ],
        ),
        // ⚠️ يظهر فقط حين تكون الموارد البشريّة مفعَّلةً وحين يكون النوعُ
        //    «موظَّف»: ملفّا `restaurant` و`cafe` يفتحان الحجوزاتِ
        //    و`hrEnabled` مطفأةٌ عندهما، وحقلٌ يشير إلى وحدةٍ محجوبةٍ تشويشٌ.
        //    والجهازُ لا ملفَّ له في الرواتب.
        if (AppConfig.showHR && _kind == 'staff') ...[
          const SizedBox(height: 12),
          _labelled(tr('الموظَّف في الموارد البشريّة (اختياري)'), _employeePicker()),
          const SizedBox(height: 8),
          _note(
            PhosphorIconsBold.info,
            tr('الربطُ للتعريف فقط: الموظَّفُ يبقى كيانَ الرواتب والحضور، والموردُ تقويمَه القابلَ للحجز. وإنشاءُ موردٍ لا يُنشئ موظَّفاً ولا يدخل مسيّرَ الرواتب.'),
            AppColors.textMuted,
          ),
        ],
        // ⚠️ قرارُ المالك 2026-08-23: لا ربطَ بين موردِ الجهاز والأصول
        //    الثابتة. الجهازُ هنا موعدٌ يُحجَز، وفي الأصول قيمةٌ تُهلَك —
        //    دورتان مختلفتان. وكثيرٌ ممّا يُحجَز ليس أصلاً أصلاً (غرفةٌ
        //    مستأجَرة). ويُقال صراحةً وإلّا بحث المستخدمُ عن الربط.
        if (_kind == 'device') ...[
          const SizedBox(height: 12),
          _note(
            PhosphorIconsBold.info,
            tr('الجهازُ هنا موردٌ يُحجَز وقتُه فقط — لا يدخل الأصولَ الثابتة ولا دورةَ الإهلاك. سجِّله في «الأصول الثابتة» على حدة إن كان أصلاً يُهلَك.'),
            AppColors.textMuted,
          ),
        ],
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(child: _labelled(tr('بداية الوردية'), _timeBox(true))),
            const SizedBox(width: 10),
            Expanded(child: _labelled(tr('نهاية الوردية'), _timeBox(false))),
          ],
        ),
        const SizedBox(height: 12),
        _labelled(tr('اللون'), _colorRow()),
        const SizedBox(height: 8),
        _note(
          PhosphorIconsBold.info,
          tr('الورديّةُ تُستعمل لحساب نسبةِ الإشغال. وتركُها فارغةً يعني «بلا ورديّة محدّدة» — والنسبةُ تُعرَض صفراً حينئذٍ لا رقماً مخترَعاً.'),
          AppColors.info,
        ),
        if (_blocked != null) ...[
          const SizedBox(height: 10),
          _note(PhosphorIconsBold.warningCircle, _blocked!, AppColors.warning),
        ],
        if (_error != null) ...[
          const SizedBox(height: 10),
          _note(PhosphorIconsBold.xCircle, _error!, AppColors.error),
        ],
      ],
    );
  }

  Widget _timeBox(bool isStart) {
    final t = isStart ? _start : _end;
    return InkWell(
      onTap: () async {
        final picked = await showTimePicker(
          context: context,
          initialTime: t ?? const TimeOfDay(hour: 10, minute: 0),
        );
        if (picked != null) {
          setState(() => isStart ? _start = picked : _end = picked);
        }
      },
      child: Container(
        height: 44,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          border: Border.all(color: Theme.of(context).dividerColor),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Row(
          children: [
            const Icon(PhosphorIconsBold.clock,
                size: 15, color: AppColors.textMuted),
            const SizedBox(width: 8),
            Text(
              t == null
                  ? tr('بلا تحديد')
                  : '${t.hour.toString().padLeft(2, '0')}:'
                      '${t.minute.toString().padLeft(2, '0')}',
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
            ),
          ],
        ),
      ),
    );
  }

  Widget _colorRow() => Row(
        children: [
          for (final c in _palette) ...[
            InkWell(
              onTap: () => setState(() => _color = c),
              borderRadius: BorderRadius.circular(999),
              child: Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: _hex(c),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color:
                        _color == c ? AppColors.textPrimary : Colors.transparent,
                    width: 2.5,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
          ],
        ],
      );

  Future<void> _save() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(databaseProvider).upsertBookingResource(
            id: widget.existing?.id,
            name: _name.text,
            role: _role.text,
            kind: _kind,
            // الجهازُ لا ملفَّ له في الرواتب — فتبديلُ النوع إلى «جهاز» يفكّ
            // الربطَ بدل أن يتركه معلَّقاً على صفٍّ لا يُرى حقلُه.
            employeeId: _kind == 'staff' ? _employeeId : null,
            colorHex: _color,
            shiftStartMinutes: _toMinutes(_start),
            shiftEndMinutes: _toMinutes(_end),
            phone: _phone.text,
          );
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) setState(() => _error = _clean(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}

// ═════════════════════════ مشترَك ═════════════════════════

/// ‏`ArgumentError` يطبع «Invalid argument(s): …» — والمستخدمُ لا يقرأ ذلك.
String _clean(Object e) {
  final s = '$e';
  const prefixes = ['Invalid argument(s): ', 'Bad state: ', 'Exception: '];
  for (final p in prefixes) {
    if (s.startsWith(p)) return s.substring(p.length);
  }
  return s;
}

Color _hex(String hex) {
  final v = int.tryParse(hex.replaceAll('#', ''), radix: 16);
  return v == null ? AppColors.primary : Color(0xFF000000 | v);
}

InputDecoration _dec() => const InputDecoration(
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

/// ⚠️ [onChanged] يأتي من **الأب** لا من `StatefulBuilder` محلّيّ: التحقّقُ
/// (‏`_blocked`) يعيش في حالة الأب، وإعادةُ بناءِ الحقلِ وحدَه كانت تترك زرَّ
/// الحفظ معطَّلاً مهما كتب المستخدم.
Widget _text(
  String label,
  TextEditingController c, {
  TextInputType? keyboard,
  required VoidCallback onChanged,
}) =>
    _labelled(
      label,
      TextField(
        controller: c,
        keyboardType: keyboard,
        onChanged: (_) => onChanged(),
        decoration: _dec(),
        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
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
        crossAxisAlignment: CrossAxisAlignment.start,
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
