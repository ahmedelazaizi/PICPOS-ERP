import 'package:flutter/material.dart';

/// صف أدوات PicPos: يلفّ الأزرار/الشرايح الممرَّرة مع تباعد موحّد، ويلتفّ
/// (wrap) على الشاشات الضيّقة بدل ما يفيض أفقياً.
class PicPosToolbar extends StatelessWidget {
  final List<Widget> children;
  final double spacing;

  const PicPosToolbar({super.key, required this.children, this.spacing = 8});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Wrap(
        spacing: spacing,
        runSpacing: spacing,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: children,
      ),
    );
  }
}
