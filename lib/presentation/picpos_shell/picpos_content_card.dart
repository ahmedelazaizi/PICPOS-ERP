import 'picpos_surface.dart';
import 'package:flutter/material.dart';

/// كارت محتوى مسطّح بحد شعري وزوايا 14 — بديل الكروت المرفوعة (`elevation:2`)
/// التي تكتبها الشاشات inline وتتجاوز بها الثيم. بلا ظلال عن قصد.
class PicPosContentCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;

  const PicPosContentCard({super.key, required this.child, this.padding});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: context.picposCard,
        border: Border.all(color: context.picposHairline),
        borderRadius: BorderRadius.circular(14),
      ),
      child: child,
    );
  }
}
