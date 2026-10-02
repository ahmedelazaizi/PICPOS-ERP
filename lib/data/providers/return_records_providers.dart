// مزوّداتُ سجلَّي المرتجعات ومسوّداتهما — J2.
//
// ⚠️ **الحصرُ بالفروع يُغلَق عند الخطأ** كما في `document_record_providers`:
//    إخفاقُ `branchScopeProvider` يعيد سجلّاً فارغاً لا سجلَّ كلِّ الفروع.
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/models/return_draft.dart';
import '../repositories/return_drafts_repository.dart';
import 'branch_scope_provider.dart';
import 'providers.dart' show databaseProvider;

export '../repositories/return_drafts_repository.dart'
    show ReturnDraftsRepository, SalesReturnRecordEntry, purchaseRecordRow;

/// مدى السجلّ — من أوّل يومٍ إلى آخر لحظةٍ من الأخير.
typedef ReturnRecordWindow = ({DateTime from, DateTime to});

final returnDraftsRepositoryProvider = Provider<ReturnDraftsRepository>(
  (ref) => ReturnDraftsRepository(ref.watch(databaseProvider)),
);

/// سجلُّ مرتجعات المبيعات (مسوّدات + معتمد + ملغى).
final salesReturnRecordsProvider = FutureProvider.autoDispose
    .family<List<SalesReturnRecordEntry>, ReturnRecordWindow>((ref, w) async {
  final Set<int>? branchIds;
  try {
    branchIds = (await ref.watch(branchScopeProvider.future)).allowedBranchIds;
  } catch (_) {
    return const [];
  }
  return ref
      .watch(returnDraftsRepositoryProvider)
      .salesRecords(from: w.from, to: w.to, branchIds: branchIds);
});

/// ما يُكمّل سجلَّ مردودات المشتريات: مسوّداتٌ وملغاةٌ وأرقامُ سندات.
final purchaseReturnRecordExtrasProvider = FutureProvider.autoDispose
    .family<PurchaseReturnRecordExtras, ReturnRecordWindow>((ref, w) async {
  final Set<int>? branchIds;
  try {
    branchIds = (await ref.watch(branchScopeProvider.future)).allowedBranchIds;
  } catch (_) {
    return const PurchaseReturnRecordExtras();
  }
  return ref
      .watch(returnDraftsRepositoryProvider)
      .purchaseExtras(from: w.from, to: w.to, branchIds: branchIds);
});
