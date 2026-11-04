@Tags(['pg'])
library;

import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/data/database/database.dart';
import '../../integration_pg/_support/pg_fixture.dart';

void main() {
  test('income statement and balance sheet work after the PG overlap repair',
      skip: Platform.environment['PG_TEST_DSN'] == null ? 'PG_TEST_DSN not set' : false,
      timeout: const Timeout(Duration(minutes: 2)), () async {
    final db = openExtraPgConnection();
    addTearDown(db.close);
    await db.customSelect('SELECT 1').get();

    final years = await db.getFiscalYears();
    expect(years.any((year) => year.id == 2), isFalse);
    final income = await db.getIncomeStatement(
      DateTime(2026), DateTime(2026, 12, 31, 23, 59, 59, 999),
    );
    final balanceSheet = await db.getBalanceSheet(DateTime(2026, 12, 31));
    expect(income, isNotEmpty);
    expect(balanceSheet, isNotEmpty);
  });
}
