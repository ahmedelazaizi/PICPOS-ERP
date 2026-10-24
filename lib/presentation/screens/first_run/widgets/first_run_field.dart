// حقلُ نصٍّ مرتبطٌ بقيمةٍ في المسودّة: يحتفظ بمتحكّمه ويتزامن عند تغيّر القيمة
// من الخارج (‏استئناف المسودّة) دون أن يقفز المؤشّر أثناء الكتابة.
import 'package:flutter/material.dart';

import '../../../picpos_shell/picpos_surface.dart';

class FirstRunField extends StatefulWidget {
  const FirstRunField({
    super.key,
    required this.label,
    required this.value,
    this.onChanged,
    this.hint,
    this.readOnly = false,
    this.obscure = false,
    this.ltr = false,
    this.keyboardType,
    this.suffix,
    this.maxLength,
    this.textInputAction,
  });

  final String label;
  final String value;
  final ValueChanged<String>? onChanged;
  final String? hint;
  final bool readOnly;
  final bool obscure;

  /// حقولُ الأسماء التقنيّة (‏اسم الدخول · العنوان) تُكتَب LTR دائماً.
  final bool ltr;
  final TextInputType? keyboardType;
  final Widget? suffix;
  final int? maxLength;
  final TextInputAction? textInputAction;

  @override
  State<FirstRunField> createState() => _FirstRunFieldState();
}

class _FirstRunFieldState extends State<FirstRunField> {
  late final TextEditingController _c =
      TextEditingController(text: widget.value);

  @override
  void didUpdateWidget(FirstRunField old) {
    super.didUpdateWidget(old);
    if (widget.value != _c.text) {
      _c.value = TextEditingValue(
        text: widget.value,
        selection: TextSelection.collapsed(offset: widget.value.length),
      );
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.label,
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w700,
            color: context.picposSecondary,
          ),
        ),
        const SizedBox(height: 5),
        TextField(
          controller: _c,
          readOnly: widget.readOnly,
          obscureText: widget.obscure,
          maxLength: widget.maxLength,
          keyboardType: widget.keyboardType,
          textInputAction: widget.textInputAction,
          textDirection: widget.ltr ? TextDirection.ltr : null,
          onChanged: widget.onChanged,
          style: TextStyle(color: context.picposText, fontSize: 14),
          decoration: InputDecoration(
            isDense: true,
            counterText: '',
            hintText: widget.hint,
            suffixIcon: widget.suffix,
            filled: true,
            fillColor: context.picposField,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(9),
              borderSide: BorderSide(color: context.picposHairline),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(9),
              borderSide: BorderSide(color: context.picposHairline),
            ),
          ),
        ),
      ],
    );
  }
}
