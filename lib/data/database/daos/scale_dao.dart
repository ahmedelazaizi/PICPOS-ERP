part of '../database.dart';

extension ScaleDao on AppDatabase {
  Future<List<LabelScale>> getAllLabelScales() => select(labelScales).get();
  
  Stream<List<LabelScale>> watchAllLabelScales() => select(labelScales).watch();
  
  Future<LabelScale?> getLabelScaleById(int id) =>
      (select(labelScales)..where((s) => s.id.equals(id))).getSingleOrNull();
      
  Future<int> insertLabelScale(LabelScalesCompanion scale) =>
      into(labelScales).insert(scale);
      
  Future<bool> updateLabelScale(LabelScale scale) =>
      update(labelScales).replace(scale);
      
  Future<void> deleteLabelScale(int id) =>
      (delete(labelScales)..where((s) => s.id.equals(id))).go();
      
  Future<void> updateLabelScaleStatus(int id, bool isActive) =>
      (update(labelScales)..where((s) => s.id.equals(id)))
          .write(LabelScalesCompanion(isActive: Value(isActive)));
}
