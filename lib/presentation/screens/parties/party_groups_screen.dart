// ═══════════════════════════════════════════════════════════════════════════
// PARTY GROUPS SCREEN — Phase 2
// ═══════════════════════════════════════════════════════════════════════════
//
// Standalone screen wrapper for [PartyGroupsTab]. Mounted as a pushed
// route from the `UnifiedPartiesScreen` header via the "المجموعات"
// button. Kept thin so the tab widget can be reused inside other
// composite screens later (e.g. a tabbed master-data area).
// ═══════════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../core/theme/app_colors.dart';
import 'party_groups_tab.dart';

class PartyGroupsScreen extends StatelessWidget {
  const PartyGroupsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          title: const Row(
            children: [
              Icon(PhosphorIconsBold.usersThree),
              SizedBox(width: 8),
              Text('مجموعات العملاء والموردين'),
            ],
          ),
        ),
        // Reuses the existing tab widget so all CRUD + drill-down logic
        // lives in a single place.
        body: const PartyGroupsTab(),
      ),
    );
  }
}
