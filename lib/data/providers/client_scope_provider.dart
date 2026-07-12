import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../domain/models/client_scope.dart';
import '../../services/network_service.dart';
import 'providers.dart';

/// Provider for the current client's operational scope.
///
/// - In **server/standalone** mode: returns [ClientScope.unrestricted]
/// - In **client** mode: resolves the assigned branch and its
///   warehouses, safes, and cost centers from the local database.
///
/// Usage: `ref.watch(clientScopeProvider)` returns an `AsyncValue<ClientScope>`.
final clientScopeProvider = FutureProvider<ClientScope>((ref) async {
  if (!NetworkService.instance.isClient) {
    return ClientScope.unrestricted;
  }

  final prefs = await SharedPreferences.getInstance();
  final branchId = prefs.getInt('client_branch_id');

  if (branchId == null) {
    debugPrint('[ClientScope] No client_branch_id configured — unrestricted');
    return ClientScope.unrestricted;
  }

  final db = ref.read(databaseProvider);

  // Resolve branch name
  final branch = await (db.select(db.branches)
        ..where((b) => b.id.equals(branchId)))
      .getSingleOrNull();
  final branchName = branch?.name ?? 'فرع $branchId';

  // Resolve warehouses belonging to this branch
  final warehouses = await (db.select(db.warehouses)
        ..where((w) => w.branchId.equals(branchId)))
      .get();
  final warehouseIds = warehouses.map((w) => w.id).toList();

  // Resolve safes belonging to this branch
  final safes = await (db.select(db.safes)
        ..where((s) => s.branchId.equals(branchId)))
      .get();
  final safeIds = safes.map((s) => s.id).toList();

  // Resolve cost centers: branch's own + warehouses' + safes'
  final costCenterIds = <int>{};
  if (branch?.costCenterId != null) costCenterIds.add(branch!.costCenterId!);
  for (final w in warehouses) {
    if (w.costCenterId != null) costCenterIds.add(w.costCenterId!);
  }
  for (final s in safes) {
    if (s.costCenterId != null) costCenterIds.add(s.costCenterId!);
  }

  final scope = ClientScope(
    branchId: branchId,
    branchName: branchName,
    allowedWarehouseIds: warehouseIds,
    allowedSafeIds: safeIds,
    allowedCostCenterIds: costCenterIds.toList(),
  );

  debugPrint('[ClientScope] Resolved: $scope');
  return scope;
});
