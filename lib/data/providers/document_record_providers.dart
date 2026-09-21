// مزوِّدا **سجلّ المستندات** — ما تقرؤه شاشاتُ السجلّ في خ‑٩.
//
// ═══ لماذا ملفٌّ مستقلّ ═══
//
// الشاشاتُ الثلاثُ جديدةٌ، و`presentation_db_import_guard` يمنعها من
// استيراد `data/database`. فهي تقرأ هذَين المزوِّدَين وتعرف **أنواعَ
// `domain/models/document_record.dart` وحدَها** — لا صفَّ drift.
//
// ⚠️ **والحصرُ بالفروع يُغلَق عند الخطأ لا يُفتَح.** `branchScopeProvider`
// قد يخفق (‏قاعدةٌ لم تُفتَح بعد · مستخدمٌ بلا جلسة)، ولكلّ سلوكٍ سابقةٌ في
// `treasury_providers.dart`:
//
//   • `scopedSafesProvider` يُرجع فارغاً — «نُفضّل الفراغَ على التسريب»؛
//   • `scopedRecentTransactionsProvider` يرتدّ إلى **قراءةٍ بلا ترشيح**
//     «حتى لا تبدو الشاشةُ معطوبة».
//
// والثاني يعني أنّ إخفاقاً عابراً في حلّ النطاق يعرض سنداتِ كلِّ الفروع
// لمستخدمٍ محصور. وهذان المزوِّدان **سجلَّا مستنداتٍ ماليّة**، فيتبعان
// الأوّلَ: عزلُ الفروع ثابتةٌ لا تُرخَّص عند الخطأ (‏Spec 151 Track‑3).

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/models/document_record.dart';
import 'branch_scope_provider.dart';
import 'repository_providers.dart';

/// مرشِّحاتُ شاشة السجلّ — ما يضبطه المستخدمُ في شريط المرشِّحات.
typedef DocumentRecordFilter = ({
  DateTime? from,
  DateTime? to,
  String? search,
});

/// سجلُّ السندات لاتّجاهٍ واحدٍ بمرشِّحاته.
final voucherRecordsProvider = StreamProvider.autoDispose
    .family<List<VoucherRecord>, (VoucherDirection, DocumentRecordFilter)>(
        (ref, key) {
  final (direction, filter) = key;
  final scope = ref.watch(branchScopeProvider);
  final repo = ref.watch(treasuryRepositoryProvider);
  return scope.when(
    data: (s) => repo.watchVoucherRecords(
      direction: direction,
      from: filter.from,
      to: filter.to,
      branchIds: s.allowedBranchIds,
      search: filter.search,
    ),
    loading: () => const Stream<List<VoucherRecord>>.empty(),
    // راجع رأسَ الملفّ: الفراغُ لا التسريب.
    error: (_, _) => const Stream<List<VoucherRecord>>.empty(),
  );
});

/// سجلُّ مردودات المشتريات بمرشِّحاته.
final purchaseReturnRecordsProvider = StreamProvider.autoDispose
    .family<List<PurchaseReturnRecord>, DocumentRecordFilter>((ref, filter) {
  final scope = ref.watch(branchScopeProvider);
  final repo = ref.watch(returnsRepositoryProvider);
  return scope.when(
    data: (s) => repo.watchPurchaseReturnRecords(
      from: filter.from,
      to: filter.to,
      branchIds: s.allowedBranchIds,
      search: filter.search,
    ),
    loading: () => const Stream<List<PurchaseReturnRecord>>.empty(),
    error: (_, _) => const Stream<List<PurchaseReturnRecord>>.empty(),
  );
});
