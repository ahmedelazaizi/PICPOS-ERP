// قائمةُ «عنوان / قيمة» للمراجعة (‏dl) ورأسُ قسمٍ بزرّ «تعديل».
import 'package:flutter/material.dart';

import '../../../../core/i18n/tr.dart';
import '../../../picpos_shell/picpos_surface.dart';

class FirstRunSummarySection extends StatelessWidget {
  const FirstRunSummarySection({
    super.key,
    required this.title,
    required this.rows,
    this.onEdit,
    this.editKey,
  });

  final String title;
  final List<(String, String)> rows;
  final VoidCallback? onEdit;
  final Key? editKey;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: context.picposCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: context.picposHairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: context.picposText,
                  ),
                ),
              ),
              if (onEdit != null)
                TextButton(
                  key: editKey,
                  onPressed: onEdit,
                  child: Text(tr('تعديل')),
                ),
            ],
          ),
          const SizedBox(height: 6),
          for (final (label, value) in rows)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 170,
                    child: Text(
                      label,
                      style: TextStyle(fontSize: 13, color: context.picposMuted),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      value,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: context.picposText,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
