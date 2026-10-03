// J4 — لبناتُ نماذج ملفّ الموظف على هويّة PicPos: قسمٌ ببطاقةٍ وشريطِ
// عنوان، وشبكةُ حقولٍ متجاوبة (٣ أعمدةٍ ≥1000 ثمّ ٢)، وحقولٌ معبّأةٌ بلا إطار
// من الثيم، وتاريخٌ ومنسدلةٌ وشارةُ حالة. ألوانٌ من `picpos*` وحدَها.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../core/i18n/tr.dart';
import '../../picpos_shell/picpos_surface.dart';
import '../hr_labels.dart';

/// بطاقةُ قسمٍ: شريطُ العلامة ثمّ العنوانُ ثمّ المحتوى.
class HrSection extends StatelessWidget {
  const HrSection({
    super.key,
    required this.title,
    required this.child,
    this.icon,
    this.actions = const [],
  });
  final String title;
  final IconData? icon;
  final Widget child;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: context.picposCard,
        border: Border.all(color: context.picposHairline),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            runSpacing: 6,
            children: [
              Row(mainAxisSize: MainAxisSize.min, children: [
                Container(
                  width: 3.5,
                  height: 15,
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primary,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: 10),
                if (icon != null) ...[
                  Icon(icon, size: 16, color: context.picposBrandInk),
                  const SizedBox(width: 6),
                ],
                Text(title,
                    style: TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w800,
                        color: context.picposText)),
              ]),
              if (actions.isNotEmpty)
                Wrap(spacing: 7, runSpacing: 6, children: actions),
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

/// شبكةُ حقولٍ تلتفّ: ٣ أعمدةٍ ≥1000 بكسل، ثمّ ٢، ثمّ عمودٌ تحت 520.
/// [wide] فهارسُ حقولٍ تأخذ عرضَ عمودين.
class HrFieldGrid extends StatelessWidget {
  const HrFieldGrid({super.key, required this.children, this.wide = const {}});
  final List<Widget> children;
  final Set<int> wide;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      final cols = c.maxWidth >= 1000 ? 3 : (c.maxWidth >= 520 ? 2 : 1);
      const gap = 12.0;
      final cell = (c.maxWidth - gap * (cols - 1)) / cols;
      return Wrap(
        spacing: gap,
        runSpacing: 12,
        children: [
          for (var i = 0; i < children.length; i++)
            SizedBox(
              width: wide.contains(i) && cols > 1 ? cell * 2 + gap : cell,
              child: children[i],
            ),
        ],
      );
    });
  }
}

/// عنوانٌ خافتٌ فوق الحقل (11/700) ونجمةٌ للمطلوب.
class HrLabeled extends StatelessWidget {
  const HrLabeled({
    super.key,
    required this.label,
    required this.child,
    this.required = false,
  });
  final String label;
  final Widget child;
  final bool required;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text.rich(
          TextSpan(text: label, children: [
            if (required)
              TextSpan(
                  text: ' *',
                  style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ]),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              color: context.picposMuted),
        ),
        const SizedBox(height: 5),
        child,
      ],
    );
  }
}

/// حقلُ نصٍّ معبّأٌ من الثيم.
class HrTextField extends StatelessWidget {
  const HrTextField({
    super.key,
    required this.label,
    required this.controller,
    this.required = false,
    this.number = false,
    this.hint,
    this.maxLines = 1,
    this.onChanged,
    this.fieldKey,
    this.textDirection,
  });
  final String label;
  final TextEditingController controller;
  final bool required;
  final bool number;
  final String? hint;
  final int maxLines;
  final ValueChanged<String>? onChanged;
  final Key? fieldKey;
  final TextDirection? textDirection;

  @override
  Widget build(BuildContext context) {
    return HrLabeled(
      label: label,
      required: required,
      child: TextField(
        key: fieldKey,
        controller: controller,
        maxLines: maxLines,
        textDirection: textDirection,
        keyboardType: number
            ? const TextInputType.numberWithOptions(decimal: true)
            : null,
        inputFormatters: number
            ? [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))]
            : null,
        style: TextStyle(
          fontSize: 13.5,
          fontWeight: FontWeight.w600,
          color: context.picposText,
          fontFeatures: number ? const [FontFeature.tabularFigures()] : null,
        ),
        decoration: InputDecoration(isDense: true, hintText: hint),
        onChanged: onChanged,
      ),
    );
  }
}

/// حقلُ تاريخٍ يفتح منتقيَ الثيم، ويُفرَّغ بزرّ المسح.
class HrDateField extends StatelessWidget {
  const HrDateField({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.required = false,
    this.fieldKey,
    this.warning,
  });
  final String label;
  final DateTime? value;
  final ValueChanged<DateTime?> onChanged;
  final bool required;
  final Key? fieldKey;

  /// تلوينٌ تحذيريٌّ (مستندٌ منتهٍ مثلاً).
  final Color? warning;

  @override
  Widget build(BuildContext context) {
    return HrLabeled(
      label: label,
      required: required,
      child: InkWell(
        key: fieldKey,
        borderRadius: BorderRadius.circular(10),
        onTap: () async {
          final now = DateTime.now();
          final picked = await showDatePicker(
            context: context,
            initialDate: value ?? now,
            firstDate: DateTime(1940),
            lastDate: DateTime(now.year + 30),
          );
          if (picked != null) onChanged(picked);
        },
        child: InputDecorator(
          isEmpty: value == null,
          decoration: InputDecoration(
            isDense: true,
            hintText: tr('اختر تاريخاً'),
            suffixIcon: value == null
                ? Icon(PhosphorIconsBold.calendarBlank,
                    size: 16, color: context.picposMuted)
                : IconButton(
                    tooltip: tr('مسح'),
                    iconSize: 16,
                    onPressed: () => onChanged(null),
                    icon: const Icon(PhosphorIconsBold.x),
                  ),
          ),
          child: Text(
            value == null ? '' : hrDate(value),
            style: TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w700,
              color: warning ?? context.picposText,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ),
      ),
    );
  }
}

/// منسدلةٌ معبّأةٌ بقيمةٍ فارغةٍ اختياريّة ([emptyLabel]).
class HrDropdown<T> extends StatelessWidget {
  const HrDropdown({
    super.key,
    required this.label,
    required this.value,
    required this.items,
    required this.onChanged,
    this.emptyLabel,
    this.required = false,
    this.fieldKey,
  });
  final String label;
  final T? value;
  final Map<T, String> items;
  final ValueChanged<T?>? onChanged;
  final String? emptyLabel;
  final bool required;
  final Key? fieldKey;

  @override
  Widget build(BuildContext context) {
    final current = items.containsKey(value) ? value : null;
    return HrLabeled(
      key: fieldKey,
      label: label,
      required: required,
      // ⚠️ المفتاحُ بالقيمة: `initialValue` لا يتبع تغييراً من خارج الحقل
      // (‏قسمٌ يُفرِّغ المسمّى)، فالحقلُ يُبنى من جديد حين تتغيّر.
      child: DropdownButtonFormField<T?>(
        key: ValueKey<Object?>(current),
        initialValue: current,
        isExpanded: true,
        isDense: true,
        decoration: const InputDecoration(isDense: true),
        style: TextStyle(
            fontSize: 13.5,
            fontWeight: FontWeight.w600,
            color: context.picposText),
        items: [
          if (emptyLabel != null)
            DropdownMenuItem<T?>(value: null, child: Text(emptyLabel!)),
          for (final e in items.entries)
            DropdownMenuItem<T?>(
              value: e.key,
              child: Text(e.value, overflow: TextOverflow.ellipsis),
            ),
        ],
        onChanged: onChanged,
      ),
    );
  }
}

/// شارةُ حالةٍ (‏tone α 0.12، حدٌّ α 0.35، نقطةٌ 6).
class HrPill extends StatelessWidget {
  const HrPill({super.key, required this.label, required this.color, this.icon});
  final String label;
  final Color color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .12),
        border: Border.all(color: color.withValues(alpha: .35)),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (icon != null)
          Icon(icon, size: 12, color: color)
        else
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
        const SizedBox(width: 5),
        Text(label,
            style: TextStyle(
                fontSize: 11, fontWeight: FontWeight.w800, color: color)),
      ]),
    );
  }
}

/// سطرٌ للقراءة: عنوانٌ خافتٌ وقيمة.
class HrInfoLine extends StatelessWidget {
  const HrInfoLine({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
  });
  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(children: [
        Icon(icon, size: 15, color: context.picposMuted),
        const SizedBox(width: 6),
        Text('$label: ',
            style: TextStyle(fontSize: 12, color: context.picposMuted)),
        Expanded(
          child: Text(value,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: context.picposText)),
        ),
      ]),
    );
  }
}
