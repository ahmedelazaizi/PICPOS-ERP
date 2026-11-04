import 'package:picpos_erp/core/i18n/tr.dart';

abstract final class FiscalPermissionCodes {
  static const fiscalPeriodClose = 'fiscal_period_close';
  static const fiscalYearClose = 'fiscal_year_close';
  static const closeDefaults = [fiscalPeriodClose, fiscalYearClose];
}

// A getter (not a top-level `final`): tr() must be evaluated lazily, after the
// locale is known; i18n_runtime_safety_test forbids `final` initializers that
// capture tr().
List<Map<String, String>> get fiscalClosePermissionEntries => <Map<String, String>>[
  {
    'code': FiscalPermissionCodes.fiscalPeriodClose,
    'name': tr('إقفال الفترة المحاسبية'),
    'category': 'accounting',
  },
  {
    'code': FiscalPermissionCodes.fiscalYearClose,
    'name': tr('إقفال سنة مالية'),
    'category': 'accounting',
  },
];
