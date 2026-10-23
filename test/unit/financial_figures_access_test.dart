import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/domain/models/branch_assignment_scope.dart';
import 'package:ural_erp/core/navigation/screen_id.dart';
import 'package:ural_erp/core/permissions/financial_figures_access.dart';
import 'package:ural_erp/core/permissions/screen_access_resolver.dart';

void main() {
  test('action-only access does not expose figures without a figure code', () {
    expect(
      canSeeScreenFigures(['sales_create'], ScreenId.salesInvoices),
      isFalse,
    );
    expect(
      canSeeScreenFigures(['sales_view'], ScreenId.salesInvoices),
      isTrue,
    );
    expect(
      canSeeScreenFigures(['purchases_create'], ScreenId.purchases),
      isFalse,
    );
    expect(
      canSeeScreenFigures(['purchases_view'], ScreenId.purchases),
      isTrue,
    );
    expect(
      canSeeScreenFigures(['sales_create'], ScreenId.salesInvoices, bypass: true),
      isTrue,
    );
  });

  test('branch-restricted action user sees only own-branch rows', () {
    final rows = [
      (id: 1, branchId: 7),
      (id: 2, branchId: 9),
    ];
    expect(
      canOpenScreen(['sales_create'], ScreenId.salesInvoices,
          primaryCode: 'sales_view', bypass: false),
      isTrue,
    );
    final visible = restrictForAssignment(
      rows,
      {7},
      branchIdOf: (row) => row.branchId,
      onEmpty: EmptyScopePolicy.refuse,
    );
    expect(visible.map((row) => row.id), [1]);
  });

  test('figure registry covers every action-enabled screen', () {
    expect(
      screenFigurePermissionCodes.keys,
      containsAll(screenActionCodes.keys),
    );
  });
}
