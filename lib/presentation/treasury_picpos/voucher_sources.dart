// مصادرُ استمارة السند — المرحلة هـ / E2 + E3.
//
// • خياراتُ الحسابات: كلُّ حسابٍ تفصيليٍّ نشطٍ مع طرفه (إن كان حسابَ طرف)
//   وخزنتِه (إن كان حسابَ خزنةٍ من خزائن نطاق المستخدم).
// • دفاترُ السندات السارية لنوعٍ واحد، والدفترُ الافتراضيُّ للمستخدم.
// • حارسُ الورقة قبل الكتابة وختمُها بعدها.

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/i18n/tr.dart';
import '../../data/providers/providers.dart';
import '../../domain/models/voucher_book.dart';
import '../../services/server_proxy.dart';
import 'screens/voucher_form_picpos.dart';

/// جهازٌ عميل: الكتابةُ الماليّةُ تقع على الخادم عبر `ClientWriteInterceptor`
/// — ومساراتُ E2 المحلّيّة (التحويلُ والمستفيدُ من الدليل في الصرف) لا
/// نقطةَ لها هناك بعد، فتُرفَض بوضوحٍ لا تُكتَب محلّيّاً بصمت.
bool get voucherRunsOnClient => ServerProxy.isClientMode;

/// كلُّ حسابٍ تفصيليٍّ نشط — مرتّبٌ بالرمز.
final voucherAccountOptionsProvider =
    FutureProvider.autoDispose<List<VoucherAccountOption>>((ref) async {
  final db = ref.watch(databaseProvider);
  final scoped = await ref.watch(scopedSafesProvider.future);
  return db.voucherAccountOptions(safeIds: {for (final s in scoped) s.id});
});

/// تسميةُ الدفتر في المنتقي — دالّةٌ لا ثابتٌ ليتبع لغةَ الواجهة وقتَ البناء.
String _bookLabel(VoucherBook b) =>
    tr('{p0} · متبقٍّ {p1}', {'p0': b.displayName, 'p1': b.remaining});

/// دفاترُ نوعٍ ([type] = `receipt`|`payment`) السارية، والافتراضيُّ للمستخدم.
final voucherBookOptionsProvider = FutureProvider.autoDispose.family<
    ({List<VoucherBookOption> books, int? defaultId}), String>((ref, type) async {
  final db = ref.watch(databaseProvider);
  final userId = ref.watch(authProvider).user?.id;
  final books = await db.listVoucherBooks(type: type, activeOnly: true);
  final options = <VoucherBookOption>[];
  for (final b in books) {
    options.add((
      id: b.id,
      label: _bookLabel(b),
      prefix: b.prefix,
      rangeFrom: b.rangeFrom,
      rangeTo: b.rangeTo,
      suggested: await db.suggestNextVoucherBookNumber(b.id),
    ));
  }
  final def = await db.defaultVoucherBookFor(type: type, userId: userId);
  return (books: options, defaultId: def?.id);
});

/// يرفض ورقةً لا تجوز **قبل** أيّ كتابة — خارج المدى أو مكرّرةً أو ملغاة.
Future<void> preValidateVoucherBookLeaf(
    AppDatabase db, VoucherSubmission v) async {
  if (v.bookId == null) return;
  if (v.bookNumber == null) {
    throw VoucherBookException('اكتب رقم ورقة الدفتر.');
  }
  await db.validateVoucherBookLeaf(v.bookId!, v.bookNumber!);
}

/// يختم صفَّ السند [txnId] بورقة الدفتر ويقدّم الدفتر.
Future<void> stampVoucherBookLeaf(
    AppDatabase db, VoucherSubmission v, int txnId) async {
  if (v.bookId == null || v.bookNumber == null || txnId <= 0) return;
  await db.assignVoucherBookLeaf(
      txnId: txnId, bookId: v.bookId!, number: v.bookNumber!);
}
