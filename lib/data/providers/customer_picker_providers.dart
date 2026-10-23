import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/models/party_reservation_entry.dart';
import '../database/daos/customer_picker_dao.dart';
import 'providers.dart';

// مزوّداتُ CustomerPickerField وتبويبِ «حجوزات العميل» (P3).
//
// نطاقُ الفرع يُحقَن من `branchScopeProvider`: مستخدمٌ مقيَّدٌ بفرعٍ لا يرى
// عملاءَ فروعٍ أخرى. وأثناء حلّ النطاق (أوّلَ إطار) تُعاد قائمةٌ فارغةٌ لا
// قائمةُ المدير — كما في `parties_providers.dart`.

/// بحثُ المنتقي. المفتاحُ نصُّ البحث (الـdebounce في الودجت).
final customerPickerSearchProvider = FutureProvider.autoDispose
    .family<List<Party>, String>((ref, query) async {
  final scope = await ref.watch(branchScopeProvider.future);
  return ref.read(databaseProvider).searchCustomersForPicker(
        query,
        allowedBranchIds: scope.allowedBranchIds,
      );
});

/// عملاءُ بهذا الهاتف داخل النطاق — منعُ التكرار عند الإضافة السريعة.
final customersByPhoneProvider = FutureProvider.autoDispose
    .family<List<Party>, String>((ref, phone) async {
  final scope = await ref.watch(branchScopeProvider.future);
  return ref.read(databaseProvider).findCustomersByPhone(
        phone,
        allowedBranchIds: scope.allowedBranchIds,
      );
});

/// الطرفُ المختار بمعرّفه (حتى لو محذوفاً ⇒ بطاقة «عميل محذوف»).
final customerPickerPartyProvider =
    FutureProvider.autoDispose.family<Party?, int>((ref, id) =>
        ref.read(databaseProvider).partyByIdAny(id));

/// عددُ حجوزات العميل (بطاقة المنتقي).
final customerReservationCountProvider =
    FutureProvider.autoDispose.family<int, int>((ref, id) =>
        ref.read(databaseProvider).partyReservationCount(id));

/// حجوزاتُ العميل (خدماتٌ + طاولات) — تبويبُ «الحجوزات».
final partyReservationsProvider = FutureProvider.autoDispose
    .family<List<PartyReservationEntry>, int>((ref, id) =>
        ref.read(databaseProvider).partyReservations(id));
