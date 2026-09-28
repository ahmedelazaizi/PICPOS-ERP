import 'package:flutter/material.dart';
import 'picpos_page_header.dart';

/// إطار شاشة PicPos: RTL + Scaffold بخلفية canvas + هيدر أعلى + محتوى.
/// slots اختيارية: subHeader (بطاقات ملخص/تبويبات)، toolbar (صف أزرار).
class PicPosScreenScaffold extends StatelessWidget {
  final String title;
  final String? subtitle;
  final IconData? icon;
  final Widget? headerSearch;
  final List<Widget> headerActions;
  final Widget? subHeader;
  final Widget? toolbar;
  final Widget body;
  final EdgeInsetsGeometry bodyPadding;

  const PicPosScreenScaffold({
    super.key,
    required this.title,
    this.subtitle,
    this.icon,
    this.headerSearch,
    this.headerActions = const [],
    this.subHeader,
    this.toolbar,
    required this.body,
    this.bodyPadding = const EdgeInsetsDirectional.fromSTEB(16, 12, 16, 12),
  });

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            PicPosPageHeader(
              title: title,
              subtitle: subtitle,
              icon: icon,
              search: headerSearch,
              actions: headerActions,
            ),
            ?subHeader,
            ?toolbar,
            Expanded(child: Padding(padding: bodyPadding, child: body)),
          ],
        ),
      ),
    );
  }
}
