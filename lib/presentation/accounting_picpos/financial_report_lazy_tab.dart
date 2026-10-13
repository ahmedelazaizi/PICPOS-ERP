import 'package:flutter/material.dart';

/// يبني جسمَ التبويب عند أوّل تفعيلٍ فقط (تحميلٌ كسول) بدل بناء التبويبات كلّها.
///
/// ⚠️ منقولٌ حرفياً من inancial_statements_picpos_screen.dart (كان فوق ody:):
/// TabBarView يطلب ارتفاعاً محدَّداً، وجسمُ الغلاف يُمرَّر داخل$nl/// Expanded فيعطيه إيّاه. ولو لُفَّ في تمريرةٍ لطلب ارتفاعاً لا
/// نهائيّاً وانهار — وهو عطبُ الخزينة البيضاء نفسُه.
class FinancialReportLazyTab extends StatefulWidget {
  const FinancialReportLazyTab({
    super.key,
    required this.active,
    required this.builder,
  });

  final bool active;
  final WidgetBuilder builder;

  @override
  State<FinancialReportLazyTab> createState() => _FinancialReportLazyTabState();
}

class _FinancialReportLazyTabState extends State<FinancialReportLazyTab> {
  Widget? _content;

  @override
  void didUpdateWidget(covariant FinancialReportLazyTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active && !oldWidget.active) _content = widget.builder(context);
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.active) return const SizedBox.shrink();
    return _content ??= widget.builder(context);
  }
}
