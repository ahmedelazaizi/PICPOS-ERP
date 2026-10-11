// مزامنةُ جدولَي v165 — الاستراتيجيّة والتسجيلُ ومسارُ الخادم.
//
// ═══ لماذا حارسٌ على التوصيل ═══
//
// جدولٌ محلّيٌّ بلا استراتيجيّةٍ **لا يُعلن عن نفسه**: يعمل تماماً على الجهاز
// الذي كُتب عليه، ولا يظهر أبداً على غيره. والعطبُ لا يُكتشَف إلّا حين يسأل
// فرعٌ عن متابعةٍ سجّلها فرعٌ آخر — وذلك بعد أسابيع.
//
// والتوصيلُ أربعةُ مواضع: صنفُ الاستراتيجيّة، وتسجيلُها في `sync_service`،
// ومسارُ الخادم في `api_handler`، وتطابقُ `apiEndpoint` مع المسار المسجَّل.
// وثلاثةٌ منها صحيحةٌ = مزامنةٌ صامتةٌ لا تعمل.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import '../helpers/api_handler_source.dart';
import 'package:ural_erp/data/database/database.dart';
import 'package:ural_erp/services/sync/strategies/party_follow_up_sync_strategy.dart';
import 'package:ural_erp/services/sync/strategies/supplier_claim_sync_strategy.dart';
import 'package:ural_erp/services/sync/sync_strategy.dart';

int _countOf(String haystack, String needle) {
  var n = 0;
  var i = haystack.indexOf(needle);
  while (i != -1) {
    n++;
    i = haystack.indexOf(needle, i + needle.length);
  }
  return n;
}

void main() {
  late AppDatabase db;
  setUp(() => db = AppDatabase.forTesting());
  tearDown(() async => db.close());

  group('عقدُ الاستراتيجيّتين', () {
    test('اسمُ الجدول والمسارُ كما في القاعدة والخادم', () {
      final f = PartyFollowUpSyncStrategy(db);
      expect(f.tableName, 'party_follow_ups');
      expect(f.apiEndpoint, '/api/party-follow-ups');

      final c = SupplierClaimSyncStrategy(db);
      expect(c.tableName, 'supplier_claims');
      expect(c.apiEndpoint, '/api/supplier-claims');
    });

    // ⚠️ السياستان **مختلفتان عن قصد**، وتبديلُهما عطبٌ صامت: `appendOnly`
    //    على المطالبة يُجمّد حالتَها على أوّلِ كاتب، و`lastWriteWins` على
    //    المتابعة يجعل الخادمَ يُعيد كتابةَ مكالمةٍ لم يشهدها.
    test('سياسةُ التعارض تفرّق بين حدثٍ وقع وحالةٍ تتقدّم', () {
      expect(PartyFollowUpSyncStrategy(db).conflictPolicy,
          ConflictPolicy.appendOnly,
          reason: 'المتابعةُ حدثٌ وقع — لا يُعاد كتابتُه من الخادم');
      expect(SupplierClaimSyncStrategy(db).conflictPolicy,
          ConflictPolicy.lastWriteWins,
          reason: 'المطالبةُ حالةٌ تتقدّم — الفرعُ والإدارةُ كلاهما يكتب');
    });

    test('`syncFromJson` يُدخل الصفوفَ فعلاً', () async {
      await PartyFollowUpSyncStrategy(db).syncFromJson({
        'party_follow_ups': [
          {
            'id': 7,
            'partyId': 1,
            'amountDue': 9140.0,
            'contactedAt': '2026-08-26T10:00:00.000',
            'outcome': 'promise',
            'promisedDate': '2026-09-02T00:00:00.000',
            'promisedAmount': 9140.0,
            'rowVersion': 1,
          }
        ]
      });
      final rows = await db.select(db.partyFollowUps).get();
      expect(rows, hasLength(1));
      expect(rows.single.id, 7);
      expect(rows.single.outcome, 'promise');
      expect(rows.single.promisedAmount, 9140.0);

      await SupplierClaimSyncStrategy(db).syncFromJson({
        'supplier_claims': [
          {
            'id': 3,
            'supplierId': 2,
            'claimDate': '2026-08-26T00:00:00.000',
            'settlementKind': 'credit_note',
            'status': 'sent',
            'netAmount': 3220.0,
            'lineCount': 2,
            'rowVersion': 1,
          }
        ]
      });
      final claims = await db.select(db.supplierClaims).get();
      expect(claims, hasLength(1));
      expect(claims.single.status, 'sent');
      expect(claims.single.netAmount, 3220.0);
    });

    test('حمولةٌ فارغةٌ لا تُدخل شيئاً ولا ترمي', () async {
      await PartyFollowUpSyncStrategy(db).syncFromJson(const {});
      await SupplierClaimSyncStrategy(db).syncFromJson(const {});
      expect(await db.select(db.partyFollowUps).get(), isEmpty);
      expect(await db.select(db.supplierClaims).get(), isEmpty);
    });
  });

  group('التسجيلُ في المصدر', () {
    final syncSrc = File('lib/services/sync_service.dart').readAsStringSync();
    final apiSrc = readApiHandlerSource();

    test('المرساة — النمطُ يطابق استراتيجيّةً قائمة', () {
      // إن سقطت هذه فالنمطُ انكسر، والفحوصُ التاليةُ تمرّ خضراءَ بلا معنى.
      expect(_countOf(syncSrc, 'PaymentAllocationSyncStrategy(localDb)'), 1);
      expect(_countOf(apiSrc, "router.get('/api/payment-allocations'"), 1);
    });

    test('الاستراتيجيّتان مسجَّلتان مرّةً واحدةً كلٌّ', () {
      expect(_countOf(syncSrc, 'PartyFollowUpSyncStrategy(localDb)'), 1,
          reason: 'استراتيجيّةُ المتابعة غيرُ مسجَّلة — الجدولُ محلّيٌّ صامت');
      expect(_countOf(syncSrc, 'SupplierClaimSyncStrategy(localDb)'), 1,
          reason: 'استراتيجيّةُ المطالبة غيرُ مسجَّلة');
    });

    test('مسارا الخادم مسجَّلان ولهما معالجان', () {
      expect(_countOf(apiSrc, "router.get('/api/party-follow-ups'"), 1);
      expect(_countOf(apiSrc, "router.get('/api/supplier-claims'"), 1);
      expect(_countOf(apiSrc, 'Future<Response> _getPartyFollowUps('), 1,
          reason: 'المسارُ مسجَّلٌ بلا معالج');
      expect(_countOf(apiSrc, 'Future<Response> _getSupplierClaims('), 1);
    });

    // ⚠️ **مفتاحُ الحمولة هو اسمُ الجدول** — والخادمُ يُصدره والاستراتيجيّةُ
    //    تقرؤه. اختلافُهما يعني نداءً ناجحاً بصفرِ صفوفٍ إلى الأبد.
    test('مفتاحُ حمولة الخادم يطابق ما تقرؤه الاستراتيجيّة', () {
      expect(_countOf(apiSrc, "{'party_follow_ups': jsonList"), 1);
      expect(_countOf(apiSrc, "{'supplier_claims': jsonList"), 1);
    });

    // ⚠️ **قرارٌ يُحرَس، ومرساتُه أصلُهما.** الجدولان يتبعان `parties`،
    //    فيُرسَل معهما `branch_id` كما يُرسَل معه. ولو خرج مسارُ الأطراف من
    //    المجموعة يوماً سقطت المرساةُ أوّلاً وأُعيد النظرُ في التابعَين معه.
    test('في `_scopedEndpoints` كأصلهما `parties`', () {
      final start = syncSrc.indexOf('static const _scopedEndpoints');
      final end = syncSrc.indexOf('};', start);
      expect(start, isNonNegative, reason: 'المجموعةُ لم تُوجَد — الفحصُ أعمى');
      final scoped = syncSrc.substring(start, end);

      expect(scoped.contains("'/api/parties'"), isTrue,
          reason: 'المرساة: مسارُ الأطراف خرج من المجموعة — أعد النظر في '
              'إلحاق التابعَين بها');
      expect(scoped.contains("'/api/party-follow-ups'"), isTrue);
      expect(scoped.contains("'/api/supplier-claims'"), isTrue);
    });

    // ⚠️ **ولا في مجموعة الفشل المقفول**: تلك مساراتُ معاملاتٍ يُصفّرها
    //    الخادمُ بلا جلسة، وإدراجُ مسارٍ مرجعيٍّ فيها يمنع سحبَه قبل الدخول
    //    ويُسمّم علامتَه. والمرساةُ أنّ `/api/parties` غائبٌ عنها أيضاً.
    test('ليسا في `_branchScopedFullSyncEndpoints`', () {
      final start =
          syncSrc.indexOf('static const _branchScopedFullSyncEndpoints');
      final end = syncSrc.indexOf('};', start);
      expect(start, isNonNegative, reason: 'المجموعةُ لم تُوجَد — الفحصُ أعمى');
      final set = syncSrc.substring(start, end);

      expect(set.contains("'/api/parties'"), isFalse,
          reason: 'المرساة: مسارُ الأطراف دخل مجموعةَ الفشل المقفول');
      expect(set.contains("'/api/party-follow-ups'"), isFalse);
      expect(set.contains("'/api/supplier-claims'"), isFalse);
    });
  });
}
