import '../../core/enums/requisition_status.dart';

/// Stock Requisition entity for domain layer
///
/// Pure domain entity - no Drift or UI dependencies
class StockRequisitionEntity {
  final int id;
  final String requisitionNumber;
  final DateTime requisitionDate;
  final int fromBranchId;
  final int toBranchId;
  final RequisitionStatus status;
  final String? notes;
  final int createdByUserId;
  final int? updatedByUserId;
  final DateTime createdAt;
  final DateTime? updatedAt;
  final String? fromBranchName;
  final String? toBranchName;
  final String? createdByUserName;

  const StockRequisitionEntity({
    required this.id,
    required this.requisitionNumber,
    required this.requisitionDate,
    required this.fromBranchId,
    required this.toBranchId,
    required this.status,
    this.notes,
    required this.createdByUserId,
    this.updatedByUserId,
    required this.createdAt,
    this.updatedAt,
    this.fromBranchName,
    this.toBranchName,
    this.createdByUserName,
  });

  StockRequisitionEntity copyWith({
    int? id,
    String? requisitionNumber,
    DateTime? requisitionDate,
    int? fromBranchId,
    int? toBranchId,
    RequisitionStatus? status,
    String? notes,
    int? createdByUserId,
    int? updatedByUserId,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? fromBranchName,
    String? toBranchName,
    String? createdByUserName,
  }) {
    return StockRequisitionEntity(
      id: id ?? this.id,
      requisitionNumber: requisitionNumber ?? this.requisitionNumber,
      requisitionDate: requisitionDate ?? this.requisitionDate,
      fromBranchId: fromBranchId ?? this.fromBranchId,
      toBranchId: toBranchId ?? this.toBranchId,
      status: status ?? this.status,
      notes: notes ?? this.notes,
      createdByUserId: createdByUserId ?? this.createdByUserId,
      updatedByUserId: updatedByUserId ?? this.updatedByUserId,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      fromBranchName: fromBranchName ?? this.fromBranchName,
      toBranchName: toBranchName ?? this.toBranchName,
      createdByUserName: createdByUserName ?? this.createdByUserName,
    );
  }
}
