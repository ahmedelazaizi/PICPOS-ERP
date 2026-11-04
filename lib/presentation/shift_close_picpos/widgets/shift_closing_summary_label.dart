import 'package:flutter/material.dart';
import '../../picpos_shell/picpos_surface.dart';

class ShiftClosingSummaryLabel extends StatelessWidget {
  final String label;
  final bool emphasis;

  const ShiftClosingSummaryLabel(this.label, {super.key, this.emphasis = false});

  @override
  Widget build(BuildContext context) => Text(
        label,
        style: TextStyle(
          fontSize: 12,
          color: context.picposText,
          fontWeight: emphasis ? FontWeight.bold : FontWeight.w500,
        ),
      );
}
