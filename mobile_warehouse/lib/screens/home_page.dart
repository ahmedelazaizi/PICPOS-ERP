import 'package:flutter/material.dart';
import 'package:picpos_ui/picpos_ui.dart';

import '../l10n/strings.dart';
import '../session/wh_session.dart';

/// Role-aware home. What is listed comes from the permissions the desktop
/// returned for the signed-in user - never from a role name guessed here.
/// Features that are not built yet are shown as «not available yet».
class HomePage extends StatefulWidget {
  const HomePage({super.key, required this.session});
  final WhSession session;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  String? _error;

  @override
  void initState() {
    super.initState();
    if (widget.session.info == null) _refresh();
  }

  Future<void> _refresh() async {
    setState(() => _error = null);
    try {
      await widget.session.refresh();
    } on Object catch (e) {
      if (mounted) setState(() => _error = errorCode(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = S.of(context);
    final tt = Theme.of(context).textTheme;
    return ListenableBuilder(
      listenable: widget.session,
      builder: (context, _) {
        final info = widget.session.info;
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          PicPosPageHeader(
            title: t('navHome'),
            subtitle: t('homeSub'),
            icon: Icons.home_outlined,
            actions: [
              IconButton(key: const Key('home.refresh'), tooltip: t('refresh'), onPressed: _refresh, icon: const Icon(Icons.refresh)),
            ],
          ),
          Expanded(
            child: ListView(padding: const EdgeInsets.all(PicPosSpacing.lg), children: [
              if (info == null)
                Text(_error == null ? t('sessionUnknown') : S.errorText(context, _error!), key: const Key('home.unknown'))
              else ...[
                Text(t('hello', {'name': info.displayName}), style: tt.titleLarge),
                const SizedBox(height: PicPosSpacing.sm),
                Wrap(spacing: PicPosSpacing.sm, children: [
                  StatusPill(
                    label: t(info.can('stock_adjust_approve') ? 'roleSupervisor' : info.isSupervisorLevel ? 'roleKeeper' : 'roleClerk'),
                    tone: PicPosTone.brand,
                    icon: Icons.badge_outlined,
                  ),
                  StatusPill(label: t('branch', {'name': info.branchName ?? '${info.branchId}'}), tone: PicPosTone.neutral),
                ]),
                const SizedBox(height: PicPosSpacing.lg),
                PicPosBlock(
                  title: t('warehouses'),
                  child: info.warehouses.isEmpty
                      ? Text(t('noWarehouses'), key: const Key('home.noWarehouses'))
                      : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          for (final w in info.warehouses)
                            Padding(padding: const EdgeInsets.symmetric(vertical: 2), child: Text(w.name)),
                        ]),
                ),
                const SizedBox(height: PicPosSpacing.lg),
                PicPosBlock(
                  title: t('capabilities'),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    _Capability(label: t('capLookup'), available: info.can('inventory_view')),
                    _Capability(label: t('capReceive'), available: info.can('goods_receipt_mobile')),
                    _Capability(label: t('capCount'), available: info.can('stock_count_submit')),
                    if (info.isSupervisorLevel) _Capability(label: t('capTransfer'), available: info.can('inventory_transfer')),
                    if (info.can('stock_adjust_approve')) _Capability(label: t('capApprove'), available: true),
                  ]),
                ),
              ],
            ]),
          ),
        ]);
      },
    );
  }
}

class _Capability extends StatelessWidget {
  const _Capability({required this.label, required this.available});
  final String label;
  final bool available;

  @override
  Widget build(BuildContext context) {
    final t = S.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: PicPosSpacing.xs),
      child: Row(children: [
        Expanded(child: Text(label)),
        StatusPill(
          label: available ? '✓' : t('noPermission'),
          tone: available ? PicPosTone.success : PicPosTone.warning,
        ),
      ]),
    );
  }
}
