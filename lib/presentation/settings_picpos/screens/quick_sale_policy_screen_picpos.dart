import 'package:ural_erp/core/i18n/tr.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/app_toast.dart';
import '../../../data/providers/providers.dart';
import '../../../data/providers/quick_sale_policy_providers.dart';
import '../../../domain/models/quick_sale_policy.dart';
import '../../../services/client_write_interceptor.dart';
import '../../../services/sync/strategies/setting_sync_strategy.dart';
import '../../picpos_shell/picpos_surface.dart';
import '../widgets/quick_sale_cashier_preview.dart';
import '../widgets/quick_sale_settings_chrome.dart';

// شاشةُ «سياسة البيع السريع» — §٤ من بلاغ المالك 2026-08-29.
//
// المصدرُ `invoice_templates/design/PicPos Quick Sale Settings.dc.html`.
//
// ═══ ما الفرقُ بينها وبين ديالوج §٣ ═══
//
// الديالوجُ يضبط **ما يُعرَض** (مقاساتٌ وأيقوناتٌ وأعمدة)، وهذه تضبط **ما
// يحدث** (‏هل يُمنع البيعُ بالسالب؟ من يصادق على الخصم؟ كيف تُقفل الوردية؟).
// ولهذا لم تُدمَجا رغم تشابه الاسم.
//
// ⚠️ **ولهذا أيضاً تعرض هذه الشاشةُ حالةَ الإنفاذ صراحةً.** إعدادٌ يضبط
// «ما يُعرَض» يُرى أثرُه فوراً، أمّا إعدادٌ يضبط «ما يحدث» ولا يقرأه المحرّكُ
// فهو كذبةٌ صامتة: المديرُ يطفئ «البيع بالسالب» فيظنّه ممنوعاً وهو يمرّ.
// فكلُّ صفٍّ لم يُوصَّل بعد يحمل وسماً ظاهراً وسببَه من النموذج.

/// أيقونةُ كلِّ صفٍّ ولونُه — عرضٌ لا نموذج، فيعيش هنا لا في
/// `domain/models`.
const Map<String, (IconData, Color)> _rowLook = {
  'focus': (PhosphorIconsBold.barcode, Color(0xFF0250D3)),
  'askqty': (PhosphorIconsBold.keyboard, Color(0xFF4A80E8)),
  'scale': (PhosphorIconsBold.scales, Color(0xFF22C55E)),
  'unknown': (PhosphorIconsBold.question, Color(0xFFF59E0B)),
  'negstock': (PhosphorIconsBold.warning, Color(0xFFF59E0B)),
  'merge': (PhosphorIconsBold.stack, Color(0xFF0250D3)),
  'maxqty': (PhosphorIconsBold.hash, Color(0xFF6B7280)),
  'disccap': (PhosphorIconsBold.percent, Color(0xFFF59E0B)),
  'discappr': (PhosphorIconsBold.shieldCheck, Color(0xFF22C55E)),
  'priceedit': (PhosphorIconsBold.tag, Color(0xFF0250D3)),
  'hold': (PhosphorIconsBold.pause, Color(0xFF0250D3)),
  'holdmax': (PhosphorIconsBold.listNumbers, Color(0xFF4A80E8)),
  'delauth': (PhosphorIconsBold.trash, Color(0xFFEF4444)),
  'reqcust': (PhosphorIconsBold.user, Color(0xFF8B5CF6)),
  'skipdlg': (PhosphorIconsBold.lightning, Color(0xFFF59E0B)),
  'defmethod': (PhosphorIconsBold.star, Color(0xFF0250D3)),
  'round': (PhosphorIconsBold.coins, Color(0xFF22C55E)),
  'mgrlimit': (PhosphorIconsBold.shieldWarning, Color(0xFFF59E0B)),
  'quickamt': (PhosphorIconsBold.gridFour, Color(0xFF4A80E8)),
  'autoprint': (PhosphorIconsBold.printer, Color(0xFF0250D3)),
  'copies': (PhosphorIconsBold.copy, Color(0xFF4A80E8)),
  'tpl': (PhosphorIconsBold.cards, Color(0xFF8B5CF6)),
  'drawer': (PhosphorIconsBold.wallet, Color(0xFF22C55E)),
  'after': (PhosphorIconsBold.arrowUUpLeft, Color(0xFF8B5CF6)),
  'digital': (PhosphorIconsBold.paperPlaneTilt, Color(0xFF22C55E)),
  'quickclose': (PhosphorIconsBold.lockKeyOpen, Color(0xFFEF4444)),
  'blind': (PhosphorIconsBold.eyeSlash, Color(0xFF0250D3)),
  'diffmax': (PhosphorIconsBold.scales, Color(0xFFF59E0B)),
  'xrep': (PhosphorIconsBold.receipt, Color(0xFF22C55E)),
};

const Map<String, IconData> _stepIcon = {
  'scan': PhosphorIconsBold.barcode,
  'cart': PhosphorIconsBold.shoppingCart,
  'pay': PhosphorIconsBold.money,
  'print': PhosphorIconsBold.printer,
  'shift': PhosphorIconsBold.clockCountdown,
};

Color _toneColor(QuickSaleImpactTone tone) => switch (tone) {
      QuickSaleImpactTone.good => AppColors.success,
      QuickSaleImpactTone.neutral => AppColors.primary,
      QuickSaleImpactTone.warn => AppColors.warning,
      QuickSaleImpactTone.danger => AppColors.error,
    };

class QuickSalePolicyScreenPicpos extends ConsumerStatefulWidget {
  const QuickSalePolicyScreenPicpos({super.key});

  @override
  ConsumerState<QuickSalePolicyScreenPicpos> createState() =>
      _QuickSalePolicyScreenState();
}

class _QuickSalePolicyScreenState
    extends ConsumerState<QuickSalePolicyScreenPicpos> {
  int _step = 0;

  /// مسوّدةٌ محلّيّةٌ فوق المحفوظ — لا يُكتب شيءٌ قبل «حفظ».
  final Map<String, String> _draft = {};
  bool _saving = false;

  QuickSalePolicyValues _merged(QuickSalePolicyValues stored) =>
      QuickSalePolicyValues({...stored.raw, ..._draft});

  void _put(Map<String, String> entries) =>
      setState(() => _draft.addAll(entries));

  Future<void> _save() async {
    if (_draft.isEmpty) {
      AppToast.show(context, tr('لا تغييرات لحفظها'));
      return;
    }
    setState(() => _saving = true);
    try {
      await ref.read(databaseProvider).saveSettings(_draft);
      ref.invalidate(quickSalePolicyProvider);

      // ⚠️ **الحفظُ المحلّيُّ وحدَه كان يُبتلَع.** على عميلٍ أو مرآةٍ لا
      // يصل التغييرُ الخادمَ، ثمّ تعيده أوّلُ `fullSync` دوريّةٍ إلى قيمة
      // الخادم — فيظنّ المديرُ أنّه حفظ وقد رُدَّ عليه بصمت.
      // (‏بلاغُ تدقيق المزامنة 2026-08-30)
      //
      // ومفاتيحُ الجهاز تُستثنى من الدفع: رفعُها يجعل خيارَ طرفيّةٍ واحدةٍ
      // قيمةَ الخادمِ ثمّ تُبَثّ إلى الجميع — أي عكسَ الغرض من عزلها.
      final shared = Map<String, String>.from(_draft)
        ..removeWhere((k, _) => kDeviceLocalSettingKeys.contains(k));
      if (shared.isNotEmpty) {
        // الإخفاقُ لا يُسقط الحفظَ المحلّيّ: الطابورُ يعيد المحاولةَ،
        // والمرآةُ بلا طابورٍ ترمي — وكلاهما لا يُبطل ما كُتب محلّيّاً.
        try {
          await ClientWriteInterceptor.saveSettings(shared);
        } catch (_) {}
      }
      if (!mounted) return;
      setState(() {
        _draft.clear();
        _saving = false;
      });
      AppToast.show(context, tr('حُفظت سياسة البيع السريع'),
          type: ToastType.success);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      AppToast.show(context, tr('تعذّر الحفظ: {e}', {'e': e}), type: ToastType.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(quickSalePolicyProvider);

    return Scaffold(
      appBar: AppBar(
        title:  Text(tr('إعدادات البيع السريع')),
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: FilledButton.icon(
              onPressed: _saving ? null : _save,
              icon: const Icon(PhosphorIconsBold.floppyDisk, size: 18),
              label: Text(_draft.isEmpty ? tr('حفظ') : tr('حفظ ({p0})', {'p0': _draft.length})),
            ),
          ),
        ],
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text(tr('تعذّر تحميل الإعدادات: {e}', {'e': e}))),
        data: (stored) => _buildBody(_merged(stored)),
      ),
    );
  }

  Widget _buildBody(QuickSalePolicyValues values) {
    final step = kQuickSaleSteps[_step];

    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(width: 250, child: _buildRail()),
        Expanded(child: _buildStepPane(step, values)),
        SizedBox(width: 340, child: _buildImpactPane(step, values)),
      ],
    );
  }

  // ── الشريطُ الجانبيّ ────────────────────────────────────────────────────
  Widget _buildRail() {
    return Container(
      decoration: BoxDecoration(
        color: context.picposField,
        border: Border(left: BorderSide(color: context.picposHairline)),
      ),
      child: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        children: [
          Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(8, 6, 8, 8),
            child: Text(tr('خطوات البيع'),
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.4,
                  color: context.picposMuted,
                )),
          ),
          for (var i = 0; i < kQuickSaleSteps.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: QuickSaleNavTile(
                icon: _stepIcon[kQuickSaleSteps[i].id]!,
                tint: AppColors.primary,
                title: kQuickSaleSteps[i].label,
                settingCount: kQuickSaleSteps[i].rows.length,
                selected: i == _step,
                dirty: kQuickSaleSteps[i]
                    .rows
                    .any((r) => _draft.containsKey(r.settingKey)),
                onTap: () => setState(() => _step = i),
              ),
            ),
        ],
      ),
    );
  }

  // ── لوحةُ الخطوة ────────────────────────────────────────────────────────
  Widget _buildStepPane(QuickSaleStep step, QuickSalePolicyValues values) {
    return ListView(
      padding: const EdgeInsetsDirectional.fromSTEB(22, 18, 22, 24),
      children: [
        QuickSaleSectionHeader(
          icon: _stepIcon[step.id]!,
          tint: AppColors.primary,
          title: step.label,
          hint: step.sub,
        ),
        const SizedBox(height: 10),
        _buildLede(step.lede),
        const SizedBox(height: 14),
        for (final group in step.groups) ...[
          QuickSaleGroupCard(
            label: group.title,
            tint: AppColors.primary,
            rows: [
              for (var i = 0; i < group.rows.length; i++)
                _buildRow(group.rows[i], values,
                    isLast: i == group.rows.length - 1),
            ],
          ),
          if (group.note != null) _buildNote(group.note!),
          const SizedBox(height: 14),
        ],
        if (step.pick != null) _buildPick(step.pick!, values),
      ],
    );
  }

  Widget _buildLede(String text) {
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(text,
          style: TextStyle(
              fontSize: 12, height: 1.7, color: context.picposMuted)),
    );
  }

  Widget _buildNote(String note) {
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(4, 8, 4, 0),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Icon(PhosphorIconsBold.info, size: 14, color: AppColors.warning),
        const SizedBox(width: 8),
        Expanded(
          child: Text(note,
              style: TextStyle(
                  fontSize: 11, height: 1.6, color: context.picposMuted)),
        ),
      ]),
    );
  }

  // ── صفُّ إعدادٍ واحد ────────────────────────────────────────────────────
  Widget _buildRow(QuickSaleRow row, QuickSalePolicyValues values,
      {required bool isLast}) {
    final look = _rowLook[row.id] ?? (PhosphorIconsBold.gear, AppColors.primary);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        QuickSaleSettingRow(
          icon: look.$1,
          tint: look.$2,
          title: row.title,
          settingKey: row.settingKey,
          sub: row.sub,
          isLast: true,
          control: _buildControl(row, values),
        ),
        if (!row.enforced) _buildNotEnforcedBadge(row),
        if (row.caveat != null) _buildCaveat(row.caveat!),
        if (!isLast)
          Divider(height: 1, color: context.picposHairline),
      ],
    );
  }

  /// وسمُ «لم يُوصَّل بعد» — الفرقُ بين إعدادٍ يعمل وإعدادٍ يُحفَظ فقط.
  ///
  /// ⚠️ **يُعرَض للمستخدم لا يُكتب في تعليقٍ فقط.** المديرُ الذي يطفئ مِزلاجاً
  /// يظنّ السلوكَ تغيّر؛ وإخفاءُ الحقيقة عنه أسوأُ من غياب المِزلاج أصلاً.
  Widget _buildNotEnforcedBadge(QuickSaleRow row) {
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(0, 0, 44, 10),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
          decoration: BoxDecoration(
            color: AppColors.warning.withValues(alpha: 0.13),
            borderRadius: BorderRadius.circular(6),
          ),
          child:  Text(tr('يُحفَظ ولا يُنفَّذ بعد'),
              style: const TextStyle(
                  fontSize: 9.5,
                  fontWeight: FontWeight.w800,
                  color: AppColors.warning)),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(row.notEnforcedReason ?? '',
              style: TextStyle(
                  fontSize: 10.5, height: 1.55, color: context.picposMuted)),
        ),
      ]),
    );
  }

  Widget _buildCaveat(String caveat) {
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(0, 0, 44, 10),
      child: Text('⚠︎ $caveat',
          style: TextStyle(
              fontSize: 10.5, height: 1.55, color: context.picposMuted)),
    );
  }

  // ── الضوابطُ الأربعة ───────────────────────────────────────────────────
  Widget _buildControl(QuickSaleRow row, QuickSalePolicyValues values) {
    switch (row.kind) {
      case QuickSaleControl.toggle:
        return Switch(
          value: values.isOn(row),
          onChanged: (v) =>
              _put(QuickSalePolicyValues.write(row, v ? 1 : 0)),
        );

      case QuickSaleControl.number:
        final value = values.numberOf(row);
        return SizedBox(
          width: 210,
          child: Row(children: [
            Expanded(
              child: Slider(
                value: value,
                min: row.min ?? 0,
                max: row.max ?? 100,
                divisions: ((row.max ?? 100) - (row.min ?? 0)).round(),
                label: '${value.round()}${row.unit ?? ''}',
                onChanged: (v) =>
                    _put(QuickSalePolicyValues.writeNumber(row, v)),
              ),
            ),
            SizedBox(
              width: 46,
              child: Text('${value.round()}${row.unit ?? ''}',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 12.5,
                      color: context.picposText)),
            ),
          ]),
        );

      case QuickSaleControl.pill:
        return _buildPills(row, values);

      case QuickSaleControl.segmented:
        return _buildSegmented(row, values);
    }
  }

  Widget _buildPills(QuickSaleRow row, QuickSalePolicyValues values) {
    final selected = values.indexOf(row);
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 260),
      child: Wrap(
        alignment: WrapAlignment.end,
        spacing: 6,
        runSpacing: 6,
        children: [
          for (var i = 0; i < row.options.length; i++)
            ChoiceChip(
              label: Text(row.options[i],
                  style: const TextStyle(fontSize: 11.5)),
              selected: i == selected,
              onSelected: (_) => _put(QuickSalePolicyValues.write(row, i)),
            ),
        ],
      ),
    );
  }

  /// `seg` — ثلاثةُ خياراتٍ لكلٍّ شرحٌ تحته. تُرسَم **تحت** الصفّ لا بجانبه:
  /// الشرحُ سطرٌ كاملٌ ولا يسع عمودَ الضابط.
  Widget _buildSegmented(QuickSaleRow row, QuickSalePolicyValues values) {
    final selected = values.indexOf(row);
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 300),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (var i = 0; i < row.options.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 5),
              child: InkWell(
                onTap: () => _put(QuickSalePolicyValues.write(row, i)),
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 11, vertical: 7),
                  decoration: BoxDecoration(
                    color: i == selected
                        ? AppColors.primary.withValues(alpha: 0.10)
                        : Colors.transparent,
                    border: Border.all(
                      color: i == selected
                          ? AppColors.primary
                          : context.picposHairline,
                    ),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(row.options[i],
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            color: i == selected
                                ? AppColors.primary
                                : context.picposText,
                          )),
                      if (i < row.optionSubs.length)
                        Text(row.optionSubs[i],
                            textAlign: TextAlign.end,
                            style: TextStyle(
                                fontSize: 10,
                                height: 1.45,
                                color: context.picposMuted)),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ── مجموعةُ الاختيار المتعدّد ──────────────────────────────────────────
  Widget _buildPick(QuickSalePick pick, QuickSalePolicyValues values) {
    final selected = values.pickOf(pick);

    return QuickSaleGroupCard(
      label: pick.title,
      tint: AppColors.success,
      note: pick.sub,
      rows: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final item in pick.items)
                FilterChip(
                  label: Text(item.label),
                  tooltip: item.sub,
                  selected: selected.contains(item.id),
                  onSelected: (on) {
                    final next = [...selected];
                    if (on) {
                      next.add(item.id);
                    } else {
                      next.remove(item.id);
                    }
                    _put(QuickSalePolicyValues.writePick(pick, next));
                  },
                ),
            ],
          ),
        ),
        if (pick.note != null) _buildNote(pick.note!),
      ],
    );
  }

  // ── لوحةُ الأثر ─────────────────────────────────────────────────────────
  Widget _buildImpactPane(QuickSaleStep step, QuickSalePolicyValues values) {
    final lines = quickSaleImpact(step.id, values);

    return Container(
      decoration: BoxDecoration(
        color: context.picposField,
        border: Border(right: BorderSide(color: context.picposHairline)),
      ),
      child: ListView(
        padding: const EdgeInsetsDirectional.fromSTEB(16, 18, 16, 24),
        children: [
          Row(children: [
            const Icon(PhosphorIconsBold.eye, size: 18, color: AppColors.primary),
            const SizedBox(width: 8),
            Expanded(
              child: Text(tr('أثر الإعدادات الحالية'),
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: context.picposText)),
            ),
          ]),
          const SizedBox(height: 6),
          Text(tr('ما الذي يتغيّر فعلاً على شاشة الكاشير بهذه الإعدادات'),
              style:
                  TextStyle(fontSize: 11, color: context.picposMuted)),
          const SizedBox(height: 12),
          QuickSaleCashierPreview(stepId: step.id, values: values),
          const SizedBox(height: 14),
          for (final line in lines)
            Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: context.picposCard,
                border: Border.all(color: context.picposHairline),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Container(
                  width: 3.5,
                  height: 30,
                  decoration: BoxDecoration(
                    color: _toneColor(line.tone),
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(line.text,
                      style: TextStyle(
                          fontSize: 12,
                          height: 1.7,
                          color: context.picposText)),
                ),
              ]),
            ),
        ],
      ),
    );
  }
}
