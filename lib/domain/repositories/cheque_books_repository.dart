import '../../data/database/database.dart' as db;

/// دفاترُ الشيكات الصادرةُ من حساباتنا البنكيّة.
///
/// ⚠️ **ولماذا مستودعٌ لا `databaseProvider` مباشرةً**: الشاشةُ **تراقب**
/// الدفاترَ بـ`StreamProvider`، وأيُّ مزوّدٍ يلمس `databaseProvider` يفتح
/// قاعدةً حقيقيّةً في اختبار الودجت فيتعلّق `pumpAndSettle` إلى الأبد —
/// عينُ ما هو مكتوبٌ في رأس `bank_reconciliation_picpos_screen.dart`.
abstract class IChequeBooksRepository {
  Stream<List<db.ChequeBookData>> watchChequeBooks();

  Future<List<db.ChequeBookData>> getChequeBooks();

  Future<int> createChequeBook({
    required int bankAccountId,
    required String bookNumber,
    required int fromNumber,
    required int toNumber,
    String? prefix,
    int? nextNumber,
    String? notes,
  });

  Future<void> updateChequeBook({
    required int id,
    required int bankAccountId,
    required String bookNumber,
    required int fromNumber,
    required int toNumber,
    required int nextNumber,
    String? prefix,
    String? notes,
  });

  /// إلغاءُ دفترٍ (ضاع أو سُحب من البنك) أو إعادتُه — **ولا حذف**:
  /// `commercial_papers.cheque_book_id` تشير إليه.
  Future<void> setChequeBookCancelled(int id, bool cancelled);

  /// 🔴 يسحب [count] رقماً ويقدّم `next_number` **في معاملةٍ واحدة**.
  ///
  /// يُنادى **عند الحفظ** لا عند العرض: أرقامٌ تُسحَب لمعاينةٍ ثمّ يفشل
  /// الحفظُ تحترق، والدفترُ الورقيُّ لا يُعاد ترقيمُه.
  Future<List<int>> allocateChequeNumbers({
    required int bookId,
    required int count,
  });

  /// الشيكاتُ التي صُرفت من الدفتر.
  Future<List<db.ChequeBookUsageRow>> getChequeBookUsage(int bookId);
}
