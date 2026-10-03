import 'package:flutter/material.dart';
import 'package:picpos_ui/picpos_ui.dart';

import '../l10n/strings.dart';

/// Sale screen layout: items on the start side and the cart on the end side
/// at ≥ 840 dp (mirrors in LTR); cart-first stack on narrower screens.
/// M-0 shows the structure only.
class SalePage extends StatelessWidget {
  const SalePage({super.key});

  @override
  Widget build(BuildContext context) {
    final t = S.of(context);
    final items = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(
        padding: const EdgeInsets.all(PicPosSpacing.lg),
        child: TextField(
          enabled: false,
          decoration: InputDecoration(prefixIcon: const Icon(Icons.qr_code_scanner), hintText: t('scanOrSearch')),
        ),
      ),
      Expanded(child: EmptyState(icon: Icons.grid_view_outlined, title: t('items'), message: t('itemsMsg'))),
    ]);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      PicPosPageHeader(
        title: t('navSale'),
        subtitle: t('saleSub'),
        icon: Icons.shopping_cart_outlined,
        actions: const [ConnectionChip(connection: PicPosConnection.offline)],
      ),
      Expanded(
        child: LayoutBuilder(builder: (context, c) {
          if (c.maxWidth < PicPosBreakpoints.expanded) {
            return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Expanded(child: items),
              const Padding(padding: EdgeInsets.fromLTRB(16, 0, 16, 16), child: _CartPanel(compact: true)),
            ]);
          }
          return Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Expanded(child: items),
            const SizedBox(
              width: 380,
              child: Padding(
                padding: EdgeInsets.all(PicPosSpacing.lg),
                child: Align(alignment: Alignment.topCenter, child: _CartPanel()),
              ),
            ),
          ]);
        }),
      ),
    ]);
  }
}

class _CartPanel extends StatelessWidget {
  const _CartPanel({this.compact = false});
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final t = S.of(context);
    final tt = Theme.of(context).textTheme;
    Widget row(String label, String value, {bool strong = false}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(children: [
            Expanded(child: Text(label, style: strong ? tt.titleMedium : tt.bodyMedium)),
            AmountText(value, style: strong ? tt.titleLarge : tt.bodyMedium),
          ]),
        );
    return PicPosBlock(
      title: t('cart'),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
        if (!compact) ...[
          Text(t('cartEmpty'), style: tt.bodyMedium?.copyWith(color: context.picposMuted), textAlign: TextAlign.center),
          const SizedBox(height: PicPosSpacing.xl),
          row(t('subtotal'), '0.000'),
          row(t('tax'), '0.000'),
          const Divider(height: PicPosSpacing.lg),
        ],
        row(t('total'), '0.000', strong: true),
        const SizedBox(height: PicPosSpacing.md),
        FilledButton(onPressed: null, child: Text(t('pay'))),
      ]),
    );
  }
}
