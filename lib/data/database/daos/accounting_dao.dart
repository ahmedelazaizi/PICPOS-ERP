part of '../database.dart';

extension AccountingDao on AppDatabase {
  static Map<String, String> get accountPurposes =>
      AccountingDaoReadsExt.accountPurposes;
}
