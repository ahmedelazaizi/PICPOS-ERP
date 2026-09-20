import 'package:drift/drift.dart';
import '../database/database.dart' as db;
import '../../domain/repositories/commercial_papers_repository.dart';

class CommercialPapersRepositoryImpl implements ICommercialPapersRepository {
  final db.AppDatabase _db;

  CommercialPapersRepositoryImpl(this._db);

  @override
  Stream<List<db.CommercialPaperData>> watchCommercialPapers({
    String? direction,
    String? status,
  }) {
    return _db.watchCommercialPapers(status: status, direction: direction);
  }

  @override
  Future<List<db.CommercialPaperData>> getCommercialPapers({
    String? direction,
    String? status,
  }) {
    final query = _db.select(_db.commercialPapers);
    if (direction != null) query.where((t) => t.direction.equals(direction));
    if (status != null) query.where((t) => t.status.equals(status));
    return query.get();
  }

  @override
  Future<db.CommercialPaperData?> getPaperById(int id) {
    return _db.getCommercialPaper(id);
  }

  @override
  Future<int> createCommercialPaper(db.CommercialPapersCompanion paper) {
    return _db.into(_db.commercialPapers).insert(paper);
  }

  @override
  Future<int> createPaper({
    required String paperNumber,
    required String type,
    required String direction,
    required int partyId,
    required double amount,
    required DateTime issueDate,
    required DateTime dueDate,
    String? bankName,
    int? safeId,
    String? accountNumber,
    String? notes,
    String? globalId,

    /// سندُ القبض/الصرف الذي وُلدت منه الورقة — راجع الـDAO.
    int? sourceVoucherId,

    /// دفترُ الشيكات الذي سُحب منه الرقم — راجع الـDAO.
    int? chequeBookId,
  }) {
    return _db.createCommercialPaper(
      sourceVoucherId: sourceVoucherId,
      chequeBookId: chequeBookId,
      paperNumber: paperNumber,
      type: type,
      direction: direction,
      partyId: partyId,
      amount: amount,
      issueDate: issueDate,
      dueDate: dueDate,
      bankName: bankName,
      safeId: safeId,
      accountNumber: accountNumber,
      notes: notes,
      globalId: globalId,
    );
  }

  @override
  Future<bool> updatePaperStatus(
    int id,
    String status, {
    int? changedBy,
    String? notes,
    int? counterAccountId,
  }) async {
    await _db.changePaperStatus(
      paperId: id,
      newStatus: status,
      changedBy: changedBy ?? 0,
      notes: notes,
      counterAccountId: counterAccountId,
    );
    return true;
  }

  @override
  Stream<List<db.PaperStatusHistoryData>> watchPaperHistory(int paperId) {
    // The DAO doesn't have a watchPaperHistory, only getPaperHistory.
    // We can implement watch directly or add to DAO.
    return (_db.select(_db.paperStatusHistory)
          ..where((t) => t.paperId.equals(paperId))
          ..orderBy([(t) => OrderingTerm.desc(t.changedAt)]))
        .watch();
  }

  @override
  Future<void> collectPaper(int id, {double? amount, int? changedBy, String? notes}) async {
    await updatePaperStatus(id, 'cashed', changedBy: changedBy, notes: notes);
  }

  @override
  Future<void> partialCollection(int id, double amount, {int? changedBy, String? notes}) async {
    await _db.partialCollection(
      paperId: id,
      collectedAmount: amount,
      changedBy: changedBy ?? 0,
      notes: notes,
    );
  }

  @override
  Future<void> depositForCollection(int id, int bankSafeId, {int? changedBy, String? notes}) async {
    await _db.depositForCollection(
      paperId: id,
      bankSafeId: bankSafeId,
      changedBy: changedBy ?? 0,
      notes: notes,
    );
  }

  @override
  Future<void> reissuePaper(int id, int newPartyId, {int? changedBy, String? notes}) async {
    await _db.reissueToParty(
      paperId: id,
      newPartyId: newPartyId,
      changedBy: changedBy ?? 0,
      notes: notes,
    );
  }

  @override
  Future<void> endorsePaper(int id, int toPartyId, {int? changedBy, String? notes}) async {
    // The DAO uses endorsedToPartyId in changePaperStatus
    await _db.changePaperStatus(
      paperId: id,
      newStatus: 'endorsed',
      changedBy: changedBy ?? 0,
      notes: notes,
      endorsedToPartyId: toPartyId,
    );
  }

  @override
  Future<void> renewPaper(int id, DateTime newDueDate, {int? changedBy, String? notes}) async {
    await _db.renewPaper(
      paperId: id,
      newDueDate: newDueDate,
      changedBy: changedBy ?? 0,
      notes: notes,
    );
  }

  @override
  Future<List<db.PaperStatusHistoryData>> getPaperHistory(int paperId) {
    return _db.getPaperHistory(paperId);
  }

  @override
  Stream<List<db.CommercialPaperData>> watchPortfolio() {
    return (_db.select(_db.commercialPapers)
          ..where((t) => t.status.isIn(['in_portfolio', 'pending', 'bounced'])))
        .watch();
  }

  @override
  Future<Map<String, double>> getPapersSummary({String? direction}) async {
    final summary = await _db.getCommercialPapersSummary();
    final rec = summary['received'] as Map<String, double>;
    final iss = summary['issued'] as Map<String, double>;
    
    if (direction == 'received') {
      double total = 0;
      for (var v in rec.values) {
        total += v;
      }
      return {
        'total': total,
        'pending': (rec['pending'] ?? 0) + (rec['in_portfolio'] ?? 0),
        'cashed': rec['cashed'] ?? 0,
      };
    } else if (direction == 'issued') {
      double total = 0;
      for (var v in iss.values) {
        total += v;
      }
      return {
        'total': total,
        'pending': iss['pending'] ?? 0,
        'cashed': iss['cashed'] ?? 0,
      };
    } else {
      // General summary
      return {
        'total': 0, // Not perfectly defined for mixed
      };
    }
  }
}
