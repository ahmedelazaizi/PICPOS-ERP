import '../../../data/database/database.dart';

/// Input for creating a commercial paper
class CreatePaperInput {
  final String paperNumber;
  final String type; // cheque, promissory_note, bill_of_exchange
  final String direction; // received, issued
  final int partyId;
  final double amount;
  final DateTime issueDate;
  final DateTime dueDate;
  final String? bankName;
  final String? bankBranch;
  final String? accountNumber;
  final int? safeId;
  final String? notes;

  CreatePaperInput({
    required this.paperNumber,
    required this.type,
    required this.direction,
    required this.partyId,
    required this.amount,
    required this.issueDate,
    required this.dueDate,
    this.bankName,
    this.bankBranch,
    this.accountNumber,
    this.safeId,
    this.notes,
  });
}

/// Result of paper operations
class PaperResult {
  final bool isSuccess;
  final int? paperId;
  final String? error;

  PaperResult.success([this.paperId]) : isSuccess = true, error = null;
  PaperResult.failure(this.error) : isSuccess = false, paperId = null;
}

/// Use case: Full commercial paper lifecycle management
class ManagePaperUseCase {
  final AppDatabase _db;

  ManagePaperUseCase(this._db);

  /// Create a new commercial paper (cheque/promissory note)
  Future<PaperResult> createPaper(CreatePaperInput input) async {
    if (input.paperNumber.trim().isEmpty) {
      return PaperResult.failure('يجب إدخال رقم الورقة');
    }
    if (input.amount <= 0) {
      return PaperResult.failure('المبلغ يجب أن يكون أكبر من صفر');
    }
    if (input.dueDate.isBefore(input.issueDate)) {
      return PaperResult.failure('تاريخ الاستحقاق يجب أن يكون بعد تاريخ الإصدار');
    }

    try {
      final id = await _db.createCommercialPaper(
        paperNumber: input.paperNumber,
        type: input.type,
        direction: input.direction,
        partyId: input.partyId,
        amount: input.amount,
        issueDate: input.issueDate,
        dueDate: input.dueDate,
        bankName: input.bankName,
        bankBranch: input.bankBranch,
        accountNumber: input.accountNumber,
        safeId: input.safeId,
        notes: input.notes,
      );
      return PaperResult.success(id);
    } catch (e) {
      return PaperResult.failure(e.toString());
    }
  }

  /// Change paper status (collect, bounce, endorse, cancel)
  Future<PaperResult> changeStatus({
    required int paperId,
    required String newStatus,
    required int changedBy,
    String? notes,
    int? endorsedToPartyId,
    int? costCenterId,
  }) async {
    try {
      await _db.changePaperStatus(
        paperId: paperId,
        newStatus: newStatus,
        changedBy: changedBy,
        notes: notes,
        endorsedToPartyId: endorsedToPartyId,
        costCenterId: costCenterId,
      );
      return PaperResult.success(paperId);
    } catch (e) {
      return PaperResult.failure(e.toString());
    }
  }

  /// Partial collection of a commercial paper
  Future<PaperResult> partialCollection({
    required int paperId,
    required double collectedAmount,
    required int changedBy,
    int? costCenterId,
    String? notes,
  }) async {
    if (collectedAmount <= 0) {
      return PaperResult.failure('المبلغ المحصل يجب أن يكون أكبر من صفر');
    }

    try {
      await _db.partialCollection(
        paperId: paperId,
        collectedAmount: collectedAmount,
        changedBy: changedBy,
        costCenterId: costCenterId,
        notes: notes,
      );
      return PaperResult.success(paperId);
    } catch (e) {
      return PaperResult.failure(e.toString());
    }
  }

  /// Deposit check for collection at bank
  Future<PaperResult> depositForCollection({
    required int paperId,
    required int bankSafeId,
    required int changedBy,
    int? costCenterId,
    String? notes,
  }) async {
    try {
      await _db.depositForCollection(
        paperId: paperId,
        bankSafeId: bankSafeId,
        changedBy: changedBy,
        costCenterId: costCenterId,
        notes: notes,
      );
      return PaperResult.success(paperId);
    } catch (e) {
      return PaperResult.failure(e.toString());
    }
  }

  /// Renew a paper (extend due date)
  Future<PaperResult> renewPaper({
    required int paperId,
    required DateTime newDueDate,
    required int changedBy,
    String? notes,
  }) async {
    try {
      await _db.renewPaper(
        paperId: paperId,
        newDueDate: newDueDate,
        changedBy: changedBy,
        notes: notes,
      );
      return PaperResult.success(paperId);
    } catch (e) {
      return PaperResult.failure(e.toString());
    }
  }
}
