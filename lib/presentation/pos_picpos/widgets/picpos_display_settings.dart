// ═══════════════════════════════════════════════════════════════════════════
// PICPOS — إعدادات عرض السلة (زرار الترس أعلى السلة)
// ═══════════════════════════════════════════════════════════════════════════
//
// نسخة من `pos/widgets/cart_display_settings.dart` — الأصل `part of
// cart_view.dart` وكلاساته خاصة، فمقدرتش أستدعيه من برّه.
//
// ── المهم: نفس مفاتيح الإعدادات بالحرف ────────────────────────────────────
// الحوار منسوخ، لكن **القيم مش منسوخة**. بيكتب على نفس الخمسة مفاتيح اللي
// شاشة UralCash بتكتب عليها:
//   pos_cart_item_scale · pos_bottom_panel_scale · pos_button_height ·
//   pos_button_font_size · pos_payment_button_height
// وبنفس المدايات. يعني القيمة اللي المستخدم يضبطها من أي شاشة هي نفسها اللي
// التانية بتقراها — مصدر واحد للقيم، حتى لو الحوار اتنين.
//
// ولاحظ: `paymentButtonHeightProvider` بيقرا مفتاح اسمه
// `pos_payment_button_height`، والحوار بيكتب عليه بنفس الاسم. أي تغيير في
// أحدهما لازم يتغيّر في التاني، وإلا السلايدر يتحرك والزرار ميتغيرش.
// ═══════════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../core/theme/app_colors.dart';
import '../../../data/providers/providers.dart';
import 'picpos_pos_text.dart';

/// زرار الترس. بيتحط أعلى السلة جنب «مسح الكل».
class PicPosDisplaySettingsButton extends StatelessWidget {
  const PicPosDisplaySettingsButton({super.key});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => showDialog<void>(
        context: context,
        builder: (_) => const Directionality(
          textDirection: TextDirection.rtl,
          child: _PicPosDisplaySettingsDialog(),
        ),
      ),
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
        decoration: BoxDecoration(
          color: AppColors.primary.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: AppColors.primary.withValues(alpha: 0.25)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(PhosphorIconsBold.slidersHorizontal,
                size: 13, color: AppColors.primary),
            const SizedBox(width: 4),
            Text('العرض', style: PicPosText.v(10, color: AppColors.primary)),
          ],
        ),
      ),
    );
  }
}

class _PicPosDisplaySettingsDialog extends ConsumerStatefulWidget {
  const _PicPosDisplaySettingsDialog();

  @override
  ConsumerState<_PicPosDisplaySettingsDialog> createState() =>
      _PicPosDisplaySettingsDialogState();
}

class _PicPosDisplaySettingsDialogState
    extends ConsumerState<_PicPosDisplaySettingsDialog> {
  double? _itemScale;
  double? _panelScale;
  double? _btnHeight;
  double? _btnFont;
  double? _payBtnHeight;

  void _save(String key, double v) {
    ref.read(settingsRepositoryProvider).saveSetting(key, v.toStringAsFixed(2));
  }

  /// تبطيل الـ providers عشان الشاشة تعيد القراءة فوراً. من غير ده السلايدر
  /// بيتحرك والحوار بيقفل والشاشة زي ما هي لحد إعادة التشغيل.
  void _refresh() {
    ref.invalidate(posCartItemScaleProvider);
    ref.invalidate(posBottomPanelScaleProvider);
    ref.invalidate(posButtonHeightProvider);
    ref.invalidate(posButtonFontSizeProvider);
    ref.invalidate(paymentButtonHeightProvider);
  }

  @override
  Widget build(BuildContext context) {
    // القيمة المحلية بتكسب لو المستخدم حرّك السلايدر في الجلسة دي؛ وإلا
    // بنقرا المحفوظ. الـ `?? default` هو نفس افتراضي مصدر القراءة.
    _itemScale ??= ref.watch(posCartItemScaleProvider).value ?? 1.0;
    _panelScale ??= ref.watch(posBottomPanelScaleProvider).value ?? 1.0;
    _btnHeight ??= ref.watch(posButtonHeightProvider).value ?? 32.0;
    _btnFont ??= ref.watch(posButtonFontSizeProvider).value ?? 12.0;
    _payBtnHeight ??= ref.watch(paymentButtonHeightProvider).value ?? 36.0;

    return AlertDialog(
      title: const Row(
        children: [
          Icon(PhosphorIconsBold.slidersHorizontal,
              size: 20, color: AppColors.primary),
          SizedBox(width: 8),
          Text('إعدادات عرض السلة'),
        ],
      ),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _Slider(
              icon: PhosphorIconsBold.textAa,
              label: 'حجم نص الأصناف',
              value: _itemScale!,
              min: 0.7,
              max: 1.3,
              divisions: 12,
              display: '${(_itemScale! * 100).round()}%',
              onChanged: (v) {
                setState(() => _itemScale = v);
                _save('pos_cart_item_scale', v);
                _refresh();
              },
            ),
            _Slider(
              icon: PhosphorIconsBold.selectionAll,
              label: 'حجم منطقة الدفع',
              value: _panelScale!,
              min: 0.7,
              max: 1.0,
              divisions: 6,
              display: '${(_panelScale! * 100).round()}%',
              onChanged: (v) {
                setState(() => _panelScale = v);
                _save('pos_bottom_panel_scale', v);
                _refresh();
              },
            ),
            _Slider(
              icon: PhosphorIconsBold.arrowsVertical,
              label: 'ارتفاع الأزرار',
              value: _btnHeight!,
              min: 30,
              max: 50,
              divisions: 10,
              display: '${_btnHeight!.round()}px',
              onChanged: (v) {
                setState(() => _btnHeight = v);
                _save('pos_button_height', v);
                _refresh();
              },
            ),
            _Slider(
              icon: PhosphorIconsBold.textT,
              label: 'حجم خط الأزرار',
              value: _btnFont!,
              min: 10,
              max: 16,
              divisions: 6,
              display: '${_btnFont!.round()}pt',
              onChanged: (v) {
                setState(() => _btnFont = v);
                _save('pos_button_font_size', v);
                _refresh();
              },
            ),
            _Slider(
              icon: PhosphorIconsBold.creditCard,
              label: 'ارتفاع أزرار الدفع',
              value: _payBtnHeight!,
              min: 30,
              max: 80,
              divisions: 10,
              display: '${_payBtnHeight!.round()}px',
              onChanged: (v) {
                setState(() => _payBtnHeight = v);
                _save('pos_payment_button_height', v);
                _refresh();
              },
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _restoreDefaults,
          child: const Text('استعادة الافتراضي'),
        ),
        ElevatedButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('تم'),
        ),
      ],
    );
  }

  /// الافتراضيات هنا هي افتراضيات **PicPos** (٣٢/١٢/٣٦) مش افتراضيات
  /// UralCash (٤٠/١٣/٤٥): عمود الفاتورة هنا ٤٠٪ من الشاشة مش نصها، وقيم
  /// UralCash كانت بتخلّي اللوحة تاكل الجدول.
  void _restoreDefaults() {
    final repo = ref.read(settingsRepositoryProvider);
    repo.saveSetting('pos_cart_item_scale', '1.00');
    repo.saveSetting('pos_bottom_panel_scale', '1.00');
    repo.saveSetting('pos_button_height', '32.00');
    repo.saveSetting('pos_button_font_size', '12.00');
    repo.saveSetting('pos_payment_button_height', '36.00');
    setState(() {
      _itemScale = 1.0;
      _panelScale = 1.0;
      _btnHeight = 32;
      _btnFont = 12;
      _payBtnHeight = 36;
    });
    _refresh();
  }
}

class _Slider extends StatelessWidget {
  final IconData icon;
  final String label;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final String display;
  final ValueChanged<double> onChanged;

  const _Slider({
    required this.icon,
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.display,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        children: [
          Row(
            children: [
              Icon(icon, size: 15, color: AppColors.primary),
              const SizedBox(width: 6),
              Expanded(child: Text(label, style: PicPosText.v(13))),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(display,
                    style: PicPosText.v(11, color: AppColors.primary)),
              ),
            ],
          ),
          Slider(
            // `clamp` عشان قيمة محفوظة برّه المدى (من نسخة أقدم أو تعديل
            // يدوي في الإعدادات) متعملش assert في Slider وتكسر الحوار.
            value: value.clamp(min, max),
            min: min,
            max: max,
            divisions: divisions,
            onChanged: onChanged,
          ),
          const Divider(height: 1),
        ],
      ),
    );
  }
}
