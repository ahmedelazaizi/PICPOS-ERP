import '../database/database.dart' as db;
import '../../domain/repositories/cheque_books_repository.dart';

/// تمريرٌ خالصٌ إلى `ChequeBooksDao` — **والقواعدُ كلُّها هناك**، داخلَ
/// المعاملة، لأنّ فحصَ التداخل في الشاشة سباقٌ بين جهازَين.
class ChequeBooksRepositoryImpl implements IChequeBooksRepository {
  ChequeBooksRepositoryImpl(this._db);

  final db.AppDatabase _db;

  @override
  Stream<List<db.ChequeBookData>> watchChequeBooks() => _db.watchChequeBooks();

  @override
  Future<List<db.ChequeBookData>> getChequeBooks() => _db.getChequeBooks();

  @override
  Future<int> createChequeBook({
    required int bankAccountId,
    required String bookNumber,
    required int fromNumber,
    required int toNumber,
    String? prefix,
    int? nextNumber,
    String? notes,
  }) =>
      _db.createChequeBook(
        bankAccountId: bankAccountId,
        bookNumber: bookNumber,
        fromNumber: fromNumber,
        toNumber: toNumber,
        prefix: prefix,
        nextNumber: nextNumber,
        notes: notes,
      );

  @override
  Future<void> updateChequeBook({
    required int id,
    required int bankAccountId,
    required String bookNumber,
    required int fromNumber,
    required int toNumber,
    required int nextNumber,
    String? prefix,
    String? notes,
  }) =>
      _db.updateChequeBook(
        id: id,
        bankAccountId: bankAccountId,
        bookNumber: bookNumber,
        fromNumber: fromNumber,
        toNumber: toNumber,
        nextNumber: nextNumber,
        prefix: prefix,
        notes: notes,
      );

  @override
  Future<void> setChequeBookCancelled(int id, bool cancelled) =>
      _db.setChequeBookCancelled(id, cancelled);

  @override
  Future<List<int>> allocateChequeNumbers({
    required int bookId,
    required int count,
  }) =>
      _db.allocateChequeNumbers(bookId: bookId, count: count);

  @override
  Future<List<db.ChequeBookUsageRow>> getChequeBookUsage(int bookId) =>
      _db.getChequeBookUsage(bookId);
}
