part of '../database.dart';

// ═══════════════════════════════════════════════════════════════════════════
// دفترُ الشيكات — أوّلُ كاتبٍ لـ`ChequeBooks` (v174 شحنت الجدولَ بلا كاتب)
// ═══════════════════════════════════════════════════════════════════════════
//
// ═══ 🔴 والقواعدُ تُفحَص **داخل المعاملة** لا في الشاشة ═══
//
// `cheque_book_plan.dart` خالصةٌ ويستعملها النموذجُ ليُري المستخدمَ الخطأَ
// وهو يكتب. لكنّ الفحصَ هناك **سباقٌ**: جهازان يفتحان دفترَين متداخلَين في
// نفس اللحظة، وكلاهما قرأ القائمةَ قبل كتابة الآخر. فالحكمُ النافذُ هنا،
// على قراءةٍ داخلَ المعاملة نفسِها.
//
// ═══ 🔴 والسحبُ عند الحفظ لا عند العرض ═══
//
// [allocateChequeNumbers] تقرأ `next_number` وتكتبه في معاملةٍ واحدة. ولو
// سُحبت الأرقامُ حين يفتح المستخدمُ النموذجَ لـ«عرضها» ثمّ فشل الحفظُ
// لاحترقت أرقامٌ لم تُكتَب على ورقة — والدفترُ الورقيُّ لا يُعاد ترقيمُه.
// فالنموذجُ **يُعاين** والمعاملةُ **تسحب**، كما يولَّد رقمُ المستند في
// مواصفة ٠٦٦.

/// جدولُ الشيكات المسحوبةِ من دفترٍ بعينه — لعرضِ «ماذا صُرف منه».
typedef ChequeBookUsageRow = ({
  int paperId,
  String paperNumber,
  double amount,
  DateTime dueDate,
  String status,
});

extension ChequeBooksDao on AppDatabase {
  /// الدفاترُ الحيّةُ كلُّها — الملغى منها يبقى معروضاً بحالته.
  Stream<List<ChequeBookData>> watchChequeBooks() {
    return (select(chequeBooks)
          ..where((b) => b.deletedAt.isNull())
          ..orderBy([
            (b) => OrderingTerm(expression: b.bankAccountId),
            (b) => OrderingTerm(expression: b.fromNumber),
          ]))
        .watch();
  }

  Future<List<ChequeBookData>> getChequeBooks() {
    return (select(chequeBooks)..where((b) => b.deletedAt.isNull())).get();
  }

  Future<ChequeBookData?> getChequeBook(int id) {
    return (select(chequeBooks)..where((b) => b.id.equals(id)))
        .getSingleOrNull();
  }

  /// صفُّ الخطّة من صفِّ القاعدة — الموضعُ الوحيدُ الذي يترجم بينهما.
  ChequeBookRow _planRow(ChequeBookData b) => (
        id: b.id,
        bankAccountId: b.bankAccountId,
        fromNumber: b.fromNumber,
        toNumber: b.toNumber,
        nextNumber: b.nextNumber,
        status: b.status,
      );

  /// يفتح دفتراً جديداً. يُرجع معرّفَه.
  ///
  /// 🔴 يرفض **التداخلَ على نفس الحساب البنكيّ** — وهو الموضعُ الوحيدُ الذي
  ///    يمنع رقماً مكرَّراً من الوصول إلى البنك بدل أن يكتشفه بعد وقوعه.
  Future<int> createChequeBook({
    required int bankAccountId,
    required String bookNumber,
    required int fromNumber,
    required int toNumber,
    String? prefix,
    int? nextNumber,
    String? notes,
    String? globalId,
  }) async {
    return transaction(() async {
      final next = nextNumber ?? fromNumber;
      await _assertChequeBookSane(
        bankAccountId: bankAccountId,
        bookNumber: bookNumber,
        fromNumber: fromNumber,
        toNumber: toNumber,
        nextNumber: next,
      );
      return into(chequeBooks).insert(
        ChequeBooksCompanion.insert(
          bankAccountId: bankAccountId,
          bookNumber: bookNumber.trim(),
          fromNumber: fromNumber,
          toNumber: toNumber,
          nextNumber: next,
          prefix: Value(
              (prefix ?? '').trim().isEmpty ? null : prefix!.trim()),
          status: Value(resolveChequeBookStatus(
              current: 'active', nextNumber: next, toNumber: toNumber)),
          notes: Value((notes ?? '').trim().isEmpty ? null : notes!.trim()),
          globalId: Value(globalId ?? UuidV7.generate()),
        ),
      );
    });
  }

  /// يعدّل دفتراً قائماً.
  ///
  /// ⚠️ **و`nextNumber` قابلٌ للتعديل عمداً**: دفترٌ وصل والنظامُ لم يُفتَح
  ///    إلّا بعد أن صُرفت منه أوراقٌ ورقيّاً — فبدايتُه الفعليّةُ ليست
  ///    `fromNumber`. وهو الطريقُ الوحيدُ لتصحيح ذلك بلا حذفٍ وإعادةِ فتح.
  Future<void> updateChequeBook({
    required int id,
    required int bankAccountId,
    required String bookNumber,
    required int fromNumber,
    required int toNumber,
    required int nextNumber,
    String? prefix,
    String? notes,
  }) async {
    await transaction(() async {
      final current = await getChequeBook(id);
      if (current == null) {
        throw Exception('الدفتر غير موجود');
      }
      await _assertChequeBookSane(
        bankAccountId: bankAccountId,
        bookNumber: bookNumber,
        fromNumber: fromNumber,
        toNumber: toNumber,
        nextNumber: nextNumber,
        editingId: id,
      );
      await (update(chequeBooks)..where((b) => b.id.equals(id))).write(
        ChequeBooksCompanion(
          bankAccountId: Value(bankAccountId),
          bookNumber: Value(bookNumber.trim()),
          fromNumber: Value(fromNumber),
          toNumber: Value(toNumber),
          nextNumber: Value(nextNumber),
          prefix:
              Value((prefix ?? '').trim().isEmpty ? null : prefix!.trim()),
          notes: Value((notes ?? '').trim().isEmpty ? null : notes!.trim()),
          // الحالةُ مشتقّةٌ — توسيعُ النهاية يُعيد المنتهيَ نشطاً، والإلغاءُ
          // يغلب فلا يُنقَض بتعديلِ مدًى.
          status: Value(resolveChequeBookStatus(
            current: current.status,
            nextNumber: nextNumber,
            toNumber: toNumber,
          )),
          lastModifiedAt: Value(DateTime.now()),
        ),
      );
    });
  }

  /// يُلغي دفتراً (ضاع أو سُحب من البنك) أو يُعيده.
  ///
  /// ⚠️ **ولا حذفَ**: `commercial_papers.cheque_book_id` تشير إليه، وحذفُه
  ///    يُيتّم كلَّ شيكٍ صُرف منه.
  Future<void> setChequeBookCancelled(int id, bool cancelled) async {
    await transaction(() async {
      final b = await getChequeBook(id);
      if (b == null) return;
      await (update(chequeBooks)..where((r) => r.id.equals(id))).write(
        ChequeBooksCompanion(
          status: Value(resolveChequeBookStatus(
            current: cancelled ? 'cancelled' : 'active',
            nextNumber: b.nextNumber,
            toNumber: b.toNumber,
          )),
          lastModifiedAt: Value(DateTime.now()),
        ),
      );
    });
  }

  /// 🔴 يسحب [count] رقماً من الدفتر ويقدّم `next_number` — **في معاملةٍ
  /// واحدةٍ تقرأ وتكتب**.
  ///
  /// يُرجع الأرقامَ المسحوبةَ بترتيبها. ويرمي إن لم تكفِ.
  ///
  /// ⚠️ والقراءةُ هنا هي الحكم: ما عاينه النموذجُ قد يكون بطُل لأنّ جهازاً
  ///    آخرَ سحب قبله.
  Future<List<int>> allocateChequeNumbers({
    required int bookId,
    required int count,
  }) async {
    return transaction(() async {
      final book = await getChequeBook(bookId);
      if (book == null) {
        throw Exception('الدفتر غير موجود');
      }
      final plan = planChequeNumbers(book: _planRow(book), count: count);
      if (plan.error != null) {
        throw Exception(plan.error);
      }
      final advanced = plan.numbers.last + 1;
      await (update(chequeBooks)..where((b) => b.id.equals(bookId))).write(
        ChequeBooksCompanion(
          nextNumber: Value(advanced),
          status: Value(resolveChequeBookStatus(
            current: book.status,
            nextNumber: advanced,
            toNumber: book.toNumber,
          )),
          lastModifiedAt: Value(DateTime.now()),
        ),
      );
      return plan.numbers;
    });
  }

  /// الشيكاتُ التي صُرفت من هذا الدفتر.
  Future<List<ChequeBookUsageRow>> getChequeBookUsage(int bookId) async {
    final rows = await (select(commercialPapers)
          ..where((p) => p.chequeBookId.equals(bookId))
          ..orderBy([(p) => OrderingTerm(expression: p.paperNumber)]))
        .get();
    return [
      for (final p in rows)
        (
          paperId: p.id,
          paperNumber: p.paperNumber,
          amount: p.amount,
          dueDate: p.dueDate,
          status: p.status,
        ),
    ];
  }

  /// الفحوصُ المشتركةُ بين الفتح والتعديل — **داخل المعاملة**.
  Future<void> _assertChequeBookSane({
    required int bankAccountId,
    required String bookNumber,
    required int fromNumber,
    required int toNumber,
    required int nextNumber,
    int? editingId,
  }) async {
    if (bookNumber.trim().isEmpty) {
      throw Exception('رقم الدفتر مطلوب');
    }
    final rangeError = validateChequeBookRange(
      fromNumber: fromNumber,
      toNumber: toNumber,
      nextNumber: nextNumber,
    );
    if (rangeError != null) throw Exception(rangeError);

    final live = await (select(chequeBooks)
          ..where((b) => b.deletedAt.isNull()))
        .get();

    // رقمُ دفترٍ مكرَّرٌ على نفس الحساب — ورقةُ غلافٍ واحدةٌ باسمين.
    final sameNumber = live.where((b) =>
        b.id != editingId &&
        b.bankAccountId == bankAccountId &&
        b.bookNumber.trim() == bookNumber.trim());
    if (sameNumber.isNotEmpty) {
      throw Exception('دفتر بالرقم ${bookNumber.trim()} مفتوحٌ على هذا الحساب');
    }

    final clash = findChequeRangeOverlap(
      existing: [for (final b in live) _planRow(b)],
      bankAccountId: bankAccountId,
      fromNumber: fromNumber,
      toNumber: toNumber,
      editingId: editingId,
    );
    if (clash != null) {
      throw Exception(
          'المدى يتداخل مع دفترٍ قائمٍ على نفس الحساب '
          '(${clash.fromNumber} – ${clash.toNumber}) — '
          'ورقمٌ مكرَّرٌ في شيكٍ صادرٍ يصل البنك');
    }
  }
}
