import '../../data/database/database.dart' as db;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/providers/providers.dart';
import '../../data/repositories/commercial_papers_repository_impl.dart';

abstract class ICommercialPapersRepository {
  Stream<List<db.CommercialPaperData>> watchCommercialPapers({
    String? direction,
    String? status,
  });

  Future<List<db.CommercialPaperData>> getCommercialPapers({
    String? direction,
    String? status,
  });

  Future<db.CommercialPaperData?> getPaperById(int id);

  Future<int> createCommercialPaper(db.CommercialPapersCompanion paper);
  
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
    // Cluster 030 / Bug D — let the caller pass a deterministic globalId
    // so mirror + server share identity for downstream status updates.
    String? globalId,

    /// سندُ القبض/الصرف الذي وُلدت منه الورقة (v174) — بديلُ النصّ الحرّ
    /// الذي كان في [notes]. تقرؤه «إدارة الشيكات» في زرّ «عرض السند».
    int? sourceVoucherId,

    /// دفترُ الشيكات الذي سُحب منه الرقم (v174) — للصادر وحدَه.
    int? chequeBookId,
  });

  /// Feature 048 (v130) — `counterAccountId` lets the caller override the
  /// auto-posted JE's contra leg. The status-change dialog already lets
  /// the user pick "الحساب المقابل" but pre-v130 that selection only
  /// got appended to the notes string — the actual JE used hardcoded
  /// purposes (`cash` / `bank` from accountPurposes map). Result: when
  /// a cashier deposited a cheque into "1115 - البنك التجاري - ودائع"
  /// the JE landed on the default bank account instead, and the chosen
  /// account did NOT appear in دفتر الأستاذ. Null preserves legacy
  /// purposes-map behaviour.
  Future<bool> updatePaperStatus(
    int id,
    String status, {
    int? changedBy,
    String? notes,
    int? counterAccountId,
  });

  Stream<List<db.PaperStatusHistoryData>> watchPaperHistory(int paperId);
  
  Future<void> collectPaper(int id, {double? amount, int? changedBy, String? notes});
  Future<void> partialCollection(int id, double amount, {int? changedBy, String? notes});
  Future<void> depositForCollection(int id, int bankSafeId, {int? changedBy, String? notes});
  Future<void> reissuePaper(int id, int newPartyId, {int? changedBy, String? notes});
  Future<void> endorsePaper(int id, int toPartyId, {int? changedBy, String? notes});
  Future<void> renewPaper(int id, DateTime newDueDate, {int? changedBy, String? notes});

  Future<List<db.PaperStatusHistoryData>> getPaperHistory(int paperId);
  Future<Map<String, dynamic>> getPapersSummary({String? direction});
  Stream<List<db.CommercialPaperData>> watchPortfolio();

  /// E-fix ٢ (v186) — ساحبُ الشيك الوارد / مستفيدُ الصادر من دليل الحسابات،
  /// مع لقطة اسمه. `name` فارغٌ ⇒ اسمُ الحساب.
  Future<void> setPaperDrawer(int paperId, {int? accountId, String? name});

  /// ساحبُ كلِّ ورقةٍ له ساحب — بمعرّف الورقة.
  Future<Map<int, ({int? accountId, String? name})>> getPaperDrawers();
}

final commercialPapersRepositoryProvider = Provider<ICommercialPapersRepository>((ref) {
  return CommercialPapersRepositoryImpl(ref.watch(databaseProvider));
});
