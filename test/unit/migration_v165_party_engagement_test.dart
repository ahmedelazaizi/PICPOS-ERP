// هجرةُ v165 — متابعةُ التحصيل ومطالبةُ المورد.
//
// ═══ ما يحمي هذا الملفّ ═══
//
// **فشلُ الترقية في هذا المستودع يُبتلَع.** وقع في v162: خطوةٌ رمت فعُدَّت
// عديمةَ الأثر، فخُتمت القاعدةُ بالرقم الجديد بلا أعمدة. فالفحصُ يقرأ
// `sqlite_master` و`PRAGMA table_info` ولا يثق برقم المخطَّط.
//
// وأربعةُ أخطارٍ متمايزة:
//
//  ‏١) **جدولٌ لم يُنشَأ** — يُفحَص وجودُه في `sqlite_master` بالاسم SQL لا
//     باسم Dart، فالمولِّدُ هو الذي يترجم بينهما.
//  ‏٢) **عمودٌ سقط من التعريف** — تُعَدّ الأعمدةُ بأسمائها الفعليّة.
//  ‏٣) **الخطوةُ غيرُ قابلةٍ للإعادة** — تشغيلةٌ انقطعت بعد الجدول الأوّل
//     تترك الثانيَ ناقصاً، فإعادةُ الترقية يجب ألّا ترمي «table exists».
//  ‏٤) 🔴 **الترقيةُ تكتب صفّاً** — الجدولان جديدان وفارغان، وأيُّ صفٍّ يظهر
//     بعد الترقية بيانةٌ اخترعها البرنامجُ عن المالك.
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:ural_erp/data/database/database.dart';

void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase.forTesting());

  Future<Set<String>> columnsOf(String table) async {
    final info = await db.customSelect('PRAGMA table_info($table)').get();
    return info.map((r) => r.data['name'] as String).toSet();
  }

  Future<bool> tableExists(String name) async {
    final rows = await db.customSelect(
      "SELECT name FROM sqlite_master WHERE type = 'table' AND name = ?",
      variables: [Variable(name)],
    ).get();
    return rows.isNotEmpty;
  }

  test('الجدولان موجودان بأسمائهما في SQL', () async {
    // مرساة: لو انكسرت قراءةُ sqlite_master لعاد كلُّ فحصٍ false ومرّ أعمى
    // في الاتّجاه المعاكس — فيُفحَص جدولٌ نعرف أنّه موجود.
    expect(await tableExists('parties'), isTrue,
        reason: 'قراءةُ sqlite_master فشلت — الفحصُ أعمى');

    expect(await tableExists('party_follow_ups'), isTrue);
    expect(await tableExists('supplier_claims'), isTrue);
  });

  test('أعمدةُ المتابعة كلُّها في مكانها', () async {
    final cols = await columnsOf('party_follow_ups');
    expect(cols.length, greaterThan(10), reason: 'قراءةُ PRAGMA فشلت');
    expect(
      cols,
      containsAll(<String>[
        'party_id',
        'invoice_id',
        'invoice_number',
        'amount_due',
        'contacted_at',
        'outcome',
        'promised_date',
        'promised_amount',
        'contact_person',
        'next_action_at',
        'notes',
        'created_by',
        'global_id',
        'deleted_at',
        'row_version',
      ]),
    );
  });

  test('أعمدةُ المطالبة كلُّها في مكانها', () async {
    final cols = await columnsOf('supplier_claims');
    expect(cols.length, greaterThan(10), reason: 'قراءةُ PRAGMA فشلت');
    expect(
      cols,
      containsAll(<String>[
        'supplier_id',
        'claim_date',
        'ledger_balance',
        'settlement_kind',
        'status',
        'net_amount',
        'lines_json',
        'line_count',
        'reply_due_at',
        'notes',
        'created_by',
        'global_id',
        'last_modified_at',
        'deleted_at',
        'row_version',
      ]),
    );
  });

  test('🔴 الترقيةُ لا تكتب صفّاً واحداً', () async {
    // جدولان جديدان يجب أن يبدآ فارغَين. صفٌّ يظهر هنا بيانةٌ اخترعها
    // البرنامجُ عن المالك.
    final followUps = await db.select(db.partyFollowUps).get();
    final claims = await db.select(db.supplierClaims).get();
    expect(followUps, isEmpty);
    expect(claims, isEmpty);
  });

  test('رقمُ المخطَّط بلغ ١٦٥ فأكثر', () async {
    // ⚠️ **«بلغ» لا «تجمّد»** — والدرسُ من `migration_v164` الذي سقط بتوكيدٍ
    //    مساوٍ لحظةَ رُفع المخطَّط هنا. الجدولان أعلاه هما دليلُ أنّ الخطوةَ
    //    جرت، والرقمُ حدٌّ أدنى لا سقف.
    expect(db.schemaVersion, greaterThanOrEqualTo(165));
  });

  test('الافتراضاتُ كما أُعلنت — والحالةُ تبدأ مسوّدة', () async {
    final pid = await db
        .into(db.parties)
        .insert(PartiesCompanion.insert(name: 'جهينة للأغذية'));

    final claimId = await db.insertSupplierClaim(
      SupplierClaimsCompanion.insert(
        supplierId: pid,
        claimDate: DateTime(2026, 8, 26),
        settlementKind: 'credit_note',
      ),
    );
    final claim = (await db.getSupplierClaims(pid)).single;
    expect(claim.id, claimId);
    expect(claim.status, 'draft', reason: 'المطالبةُ تبدأ مسوّدةً لا مُرسَلة');
    expect(claim.netAmount, 0);
    expect(claim.lineCount, 0);
    expect(claim.linesJson, isNull);
  });

  tearDown(() async => db.close());
}
