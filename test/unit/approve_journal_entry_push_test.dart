// test/unit/approve_journal_entry_push_test.dart
//
// اعتمادُ مسودّةٍ على جهاز **عميل** يدفع القيدَ إلى المضيف عبر
// `SyncInterceptor.submitJournalEntry`. المضيف يقرأ `referenceType` و
// `referenceId` و`isAutoPosted` (api_data_accounting.dart) بافتراض
// `isAutoPosted ?? true`، فإن لم تُرسَل الحقول خُزّن القيد اليدوي بلا مرجع
// وبوسم «آلي». هذا الاختبار يلتقط ما يُسلَّم للمعترض ويقارنه بصفّ القيد.
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/data/database/database.dart';
import 'package:picpos_erp/data/database/sync_interceptor.dart';
import 'package:picpos_erp/data/repositories/drift_accounting_repository.dart';
import 'package:picpos_erp/domain/repositories/accounting_repository.dart';

/// معترض يلتقط وسائط `submitJournalEntry` ويزعم وضع العميل/المضيف.
class _CapturingInterceptor implements SyncInterceptor {
  _CapturingInterceptor({required this.clientMode});
  final bool clientMode;
  final List<Map<String, dynamic>> pushes = [];

  @override
  bool get isClientModeImpl => clientMode;

  @override
  Future<void> submitJournalEntry({
    required String description,
    required DateTime date,
    required List<dynamic> lines,
    String? referenceType,
    int? referenceId,
    bool isAutoPosted = false,
    int? costCenterId,
    int? branchId,
    String? globalId,
  }) async {
    pushes.add({
      'description': description,
      'date': date,
      'lines': lines,
      'referenceType': referenceType,
      'referenceId': referenceId,
      'isAutoPosted': isAutoPosted,
      'costCenterId': costCenterId,
      'branchId': branchId,
      'globalId': globalId,
    });
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late AppDatabase db;
  late DriftAccountingRepository repo;

  setUp(() async {
    SyncInterceptor.instance = null;
    db = AppDatabase.forTesting();
    repo = DriftAccountingRepository(db);
  });

  tearDown(() async {
    SyncInterceptor.instance = null;
    await db.close();
  });

  /// مسودّة تُنشأ **قبل** تركيب المعترض، كي لا يُحسب أيّ دفعٍ عند الإنشاء.
  Future<int> makeDraft({String? referenceType, int? referenceId}) async {
    final all = await repo.getAllAccounts();
    final cash =
        all.firstWhere((a) => a.code == '1111' && a.accountNature == 'detail');
    final sales = all.firstWhere(
        (a) => a.code.startsWith('41') && a.accountNature == 'detail');
    return repo.createJournalEntry(
      description: 'قيد يدوي — مسودة',
      date: DateTime(2026, 8, 27),
      lines: [
        JournalLine(accountId: cash.id, debit: 500, credit: 0),
        JournalLine(accountId: sales.id, debit: 0, credit: 500),
      ],
      referenceType: referenceType,
      referenceId: referenceId,
      asDraft: true,
    );
  }

  Future<int> approver() async => (await db.select(db.users).get()).first.id;

  Future<JournalEntryData> rowOf(int id) => (db.select(db.journalEntries)
        ..where((e) => e.id.equals(id)))
      .getSingle();

  test('عميل: الدفع يحمل referenceType/referenceId/isAutoPosted=false من الصفّ',
      () async {
    final id = await makeDraft(referenceType: 'adjustment', referenceId: 4242);
    final before = await rowOf(id);
    expect(before.referenceType, 'adjustment');
    expect(before.referenceId, 4242);
    expect(before.isAutoPosted, isFalse);

    final icpt = _CapturingInterceptor(clientMode: true);
    SyncInterceptor.instance = icpt;
    await db.approveJournalEntry(id, await approver());

    expect(icpt.pushes, hasLength(1));
    final p = icpt.pushes.single;
    expect(p['referenceType'], 'adjustment');
    expect(p['referenceId'], 4242);
    expect(p['isAutoPosted'], isFalse,
        reason: 'قيد يدوي — المضيف يفترض true عند الغياب');
    expect(p['globalId'], before.globalId);
    expect(p['description'], before.description);
    expect(p['lines'], hasLength(2));
    expect((await rowOf(id)).isPosted, isTrue);
  });

  test('عميل: referenceType=null يُرسَل null صريحاً دون انهيار', () async {
    final id = await makeDraft();
    final before = await rowOf(id);
    expect(before.referenceType, isNull);
    expect(before.referenceId, isNull);

    final icpt = _CapturingInterceptor(clientMode: true);
    SyncInterceptor.instance = icpt;
    await db.approveJournalEntry(id, await approver());

    expect(icpt.pushes, hasLength(1));
    final p = icpt.pushes.single;
    expect(p.containsKey('referenceType'), isTrue);
    expect(p['referenceType'], isNull);
    expect(p['referenceId'], isNull);
    expect(p['isAutoPosted'], before.isAutoPosted);
    expect(p['isAutoPosted'], isFalse);
    expect((await rowOf(id)).isPosted, isTrue);
  });

  test('مضيف: لا دفع ويُرحَّل القيد محلياً', () async {
    final id = await makeDraft(referenceType: 'daily', referenceId: 7);
    final icpt = _CapturingInterceptor(clientMode: false);
    SyncInterceptor.instance = icpt;
    expect(SyncInterceptor.isClientMode, isFalse);

    await db.approveJournalEntry(id, await approver());

    expect(icpt.pushes, isEmpty);
    final row = await rowOf(id);
    expect(row.isPosted, isTrue);
    expect(row.referenceType, 'daily');
  });
}
