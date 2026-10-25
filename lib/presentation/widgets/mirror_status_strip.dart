// ═══════════════════════════════════════════════════════════════════════════
// Branch-manager console strip (plan 2026-10-24, M2 / MIR-008, MIR-012).
//
// Mounted at the top of the app shell. On a mirror it shows
//   * the CONNECTIVITY of the link to the main - online / reconnecting /
//     read-only - judged by the same [MirrorConnectivity] that refuses writes,
//     refreshed by a timer and by every heartbeat (success or failure), with a
//     "check now" button;
//   * the CURRENT BRANCH selector - exactly the branches the main says the
//     signed-in manager may work in; an empty scope is an explicit message, never
//     a silent "all".
// Off a mirror it collapses to nothing.
// ═══════════════════════════════════════════════════════════════════════════
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/i18n/tr.dart';
import '../../core/theme/app_colors.dart';
import '../../data/providers/mirror_branch_context_provider.dart';
import '../../data/providers/providers.dart' show databaseProvider;
import '../../services/mirror_branch_context.dart';
import '../../services/mirror_connectivity.dart';
import '../../services/mirror_heartbeat_service.dart';
import '../../services/mirror_state.dart';
import '../../services/network_service.dart';
import '../picpos_shell/picpos_dialog.dart' show picposDialogMuted;
import 'mirror_offline_banner.dart';

class MirrorStatusStrip extends ConsumerStatefulWidget {
  const MirrorStatusStrip({super.key});

  @override
  ConsumerState<MirrorStatusStrip> createState() => _MirrorStatusStripState();
}

class _MirrorStatusStripState extends ConsumerState<MirrorStatusStrip> {
  Timer? _tick;
  bool _checking = false;

  @override
  void initState() {
    super.initState();
    // Re-judge the link even when nothing else changes (a console left alone).
    _tick = Timer.periodic(
        const Duration(seconds: 15), (_) => mounted ? setState(() {}) : null);
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  Future<void> _checkNow() async {
    setState(() => _checking = true);
    await MirrorHeartbeatService.checkNow();
    if (mounted) setState(() => _checking = false);
  }

  @override
  Widget build(BuildContext context) {
    if (!NetworkService.instance.isMirror) return const SizedBox.shrink();
    // Keeps the manager's scope loaded (and refreshed on user change).
    ref.watch(mirrorConsoleContextProvider);
    ref.watch(mirrorCurrentBranchProvider);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const MirrorOfflineBanner(),
        ValueListenableBuilder<int>(
          valueListenable: MirrorState.instance.revision,
          builder: (_, _, _) => _bar(context),
        ),
      ],
    );
  }

  Widget _bar(BuildContext context) {
    final theme = Theme.of(context);
    final link = MirrorConnectivity.state;
    final (Color tone, IconData icon, String label) = switch (link) {
      MirrorLinkState.online => (
          AppColors.success,
          PhosphorIconsBold.wifiHigh,
          tr('متصل بالسيرفر الرئيسي')
        ),
      MirrorLinkState.degraded => (
          AppColors.warning,
          PhosphorIconsBold.wifiMedium,
          tr('جارٍ إعادة الاتصال…')
        ),
      MirrorLinkState.readOnly => (
          AppColors.error,
          PhosphorIconsBold.wifiSlash,
          tr('قراءة فقط')
        ),
    };
    return Material(
      color: theme.cardColor,
      child: Container(
        key: const ValueKey('mirrorStatusStrip'),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: theme.dividerColor)),
        ),
        child: Row(
          children: [
            Icon(icon, size: 16, color: tone),
            const SizedBox(width: 6),
            Text(
              label,
              key: const ValueKey('mirrorLinkLabel'),
              style: TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w700, color: tone),
            ),
            IconButton(
              key: const ValueKey('mirrorCheckNow'),
              tooltip: tr('تحقق من الاتصال الآن'),
              visualDensity: VisualDensity.compact,
              iconSize: 16,
              onPressed: _checking ? null : _checkNow,
              icon: _checking
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(PhosphorIconsBold.arrowClockwise),
            ),
            const Spacer(),
            const MirrorBranchSelector(),
          ],
        ),
      ),
    );
  }
}

/// «الفرع الحالي» - the branch the console works in.
class MirrorBranchSelector extends ConsumerWidget {
  const MirrorBranchSelector({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(mirrorCurrentBranchProvider);
    final ctx = MirrorBranchContext.instance;
    return ListenableBuilder(
      listenable: Listenable.merge([ctx.branches, ctx.loaded, ctx.current]),
      builder: (context, _) {
        final branches = ctx.branches.value;
        final muted = picposDialogMuted(context);
        if (ctx.hasNoBranches) {
          return Text(
            tr('لا فروع مسندة لحسابك'),
            key: const ValueKey('mirrorNoBranches'),
            style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: AppColors.error),
          );
        }
        final current = ctx.currentBranch;
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(tr('الفرع الحالي'),
                style: TextStyle(fontSize: 11, color: muted)),
            const SizedBox(width: 8),
            PopupMenuButton<int>(
              key: const ValueKey('mirrorBranchSelector'),
              enabled: branches.length > 1,
              tooltip: tr('تبديل الفرع'),
              onSelected: (id) async {
                await ctx.select(id, db: ref.read(databaseProvider));
              },
              itemBuilder: (_) => [
                for (final b in branches)
                  PopupMenuItem<int>(
                    value: b.id,
                    child: Text(b.name,
                        style: TextStyle(
                            fontWeight: b.id == ctx.currentBranchId
                                ? FontWeight.w800
                                : FontWeight.w500)),
                  ),
              ],
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    current?.name ?? '—',
                    key: const ValueKey('mirrorCurrentBranchName'),
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w800),
                  ),
                  if (branches.length > 1)
                    const Icon(PhosphorIconsBold.caretDown, size: 14),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}
