part of '../database.dart';

@DataClassName('DocumentSequence')
class DocumentSequences extends Table {
  TextColumn get prefix => text().withLength(min: 1, max: 20)();
  IntColumn get nextValue => integer().withDefault(const Constant(1))();

  @override
  Set<Column> get primaryKey => {prefix};
}
