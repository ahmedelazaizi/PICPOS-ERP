import '../../../data/database/database.dart';

/// Input for creating a Bill of Materials
class CreateBOMInput {
  final int finishedProductId;
  final String bomCode;
  final double expectedQuantity;
  final String? notes;
  final List<BOMComponentInput> components;

  CreateBOMInput({
    required this.finishedProductId,
    required this.bomCode,
    this.expectedQuantity = 1,
    this.notes,
    required this.components,
  });
}

class BOMComponentInput {
  final int rawMaterialId;
  final double quantity;
  final double unitCost;
  final int? selectedUnitId;
  final String unitName;
  final double quantityInBase;

  BOMComponentInput({
    required this.rawMaterialId,
    required this.quantity,
    required this.unitCost,
    this.selectedUnitId,
    this.unitName = 'قطعة',
    this.quantityInBase = 1,
  });

  Map<String, dynamic> toMap() => {
    'rawMaterialId': rawMaterialId,
    'quantity': quantity,
    'unitCost': unitCost,
    'unit': unitName,
    'quantityInBase': quantityInBase,
  };
}

/// Result of BOM creation
class CreateBOMResult {
  final bool isSuccess;
  final int? bomId;
  final String? error;
  
  CreateBOMResult.success(this.bomId) : isSuccess = true, error = null;
  CreateBOMResult.failure(this.error) : isSuccess = false, bomId = null;
}

/// Use case: Create a Bill of Materials with components
class CreateBOMUseCase {
  final AppDatabase _db;

  CreateBOMUseCase(this._db);

  Future<CreateBOMResult> execute(CreateBOMInput input) async {
    // Validate
    if (input.components.isEmpty) {
      return CreateBOMResult.failure('يجب إضافة مكون واحد على الأقل');
    }
    if (input.bomCode.trim().isEmpty) {
      return CreateBOMResult.failure('يجب إدخال كود BOM');
    }
    if (input.expectedQuantity <= 0) {
      return CreateBOMResult.failure('الكمية المتوقعة يجب أن تكون أكبر من صفر');
    }

    try {
      final bomId = await _db.createBOM(
        finishedProductId: input.finishedProductId,
        bomCode: input.bomCode,
        expectedQuantity: input.expectedQuantity,
        notes: input.notes,
        components: input.components.map((c) => c.toMap()).toList(),
      );
      return CreateBOMResult.success(bomId);
    } catch (e) {
      return CreateBOMResult.failure(e.toString());
    }
  }
}
