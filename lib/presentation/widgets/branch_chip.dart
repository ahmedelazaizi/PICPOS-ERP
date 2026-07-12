// ═══════════════════════════════════════════════════════════════════════════
// BRANCH CHIP — Feature 004 (Multi-Branch Governance)
// ═══════════════════════════════════════════════════════════════════════════
//
// Shared visual chip showing which branch a row (journal entry, sales
// invoice, treasury transaction, ...) belongs to. Used across multiple
// listing screens for a unified visual language: the same branch always
// gets the same colour, so an auditor can scan a multi-branch listing
// page at a glance.
//
// Returns SizedBox.shrink() when:
//   - branchId is null (legacy data without a branch link), or
//   - the branch list hasn't loaded yet, or
//   - the branch was deleted (id no longer resolvable).
// ═══════════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../data/providers/providers.dart';

class BranchChip extends ConsumerWidget {
  const BranchChip({
    super.key,
    required this.branchId,
    this.compact = false,
  });

  /// Branch id to render. Null hides the chip entirely.
  final int? branchId;

  /// Compact mode reduces font size and padding for dense table rows.
  final bool compact;

  /// Curated palette — readable on a light background, distinguishable from
  /// status badges (info/warning/success). Same id always picks the same
  /// colour because the index is `id.abs() % length`.
  static const List<Color> _palette = [
    Color(0xFF1976D2), // blue
    Color(0xFF7B1FA2), // purple
    Color(0xFF388E3C), // green
    Color(0xFFD32F2F), // red
    Color(0xFFF57C00), // orange
    Color(0xFF00796B), // teal
    Color(0xFF5D4037), // brown
    Color(0xFF455A64), // blue-grey
  ];

  /// Resolve the deterministic colour for a given branch id without
  /// rendering a chip. Useful when other widgets (e.g. table row borders)
  /// want to mirror the branch colour.
  static Color colorFor(int branchId) =>
      _palette[branchId.abs() % _palette.length];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final id = branchId;
    if (id == null) return const SizedBox.shrink();

    final branchesAsync = ref.watch(allBranchesProvider);
    final branches = branchesAsync.value;
    if (branches == null) return const SizedBox.shrink();

    final branch = branches.where((b) => b.id == id).firstOrNull;
    if (branch == null) return const SizedBox.shrink();

    final color = colorFor(id);
    final fontSize = compact ? 9.0 : 10.0;
    final iconSize = compact ? 10.0 : 11.0;
    final hPad = compact ? 6.0 : 8.0;
    final vPad = compact ? 2.0 : 3.0;

    return Container(
      padding: EdgeInsets.symmetric(horizontal: hPad, vertical: vPad),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.35), width: 0.8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(PhosphorIconsBold.buildings, size: iconSize, color: color),
          const SizedBox(width: 4),
          Text(
            branch.name,
            style: GoogleFonts.cairo(
              fontSize: fontSize,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
