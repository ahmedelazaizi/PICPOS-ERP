import 'package:drift/drift.dart';

import '../data/database/database.dart';
import 'guest_order_requests.dart';

/// ما آل إليه اعتمادُ طلبِ ضيف.
enum GuestApprovalOutcome {
  /// دخل الحسابَ.
  approved,

  /// لم يعد معلَّقاً — اعتُمد أو رُفض قبل لحظات.
  notPending,

  /// الطاولةُ أُغلقت بين وصول الطلب واعتماده.
  orderClosed,

  /// إخفاقٌ غيرُ متوقّع.
  failed,
}

/// اعتمادُ طلبِ ضيفٍ — **محرّكٌ واحدٌ** يناديه الخادمُ والشاشةُ معاً.
///
/// ⚠️ **ولماذا خدمةٌ لا جسمُ معالجٍ في `ApiHandler`.** الطابورُ يعيش في ذاكرة
/// الخادم، فجهازُ الخادم نفسُه يعتمد **مباشرةً** بلا مرورٍ بـHTTP، وجهازُ
/// العميل يعتمد عبر المسار. ولو بقي المنطقُ في المعالج لكان أمامَ الشاشة
/// المحلّيّة نسخةٌ ثانيةٌ منه — ومحرّكا حسابٍ يتباعدان هما علّةُ هذا المستودع
/// المعروفة، وهنا التباعدُ يعني بنداً يدخل حساباً بسعرٍ أو ضريبةٍ مختلفة.
class GuestOrderApproval {
  GuestOrderApproval(this._db, {GuestOrderRequests? queue})
      : _queue = queue ?? GuestOrderRequests.instance;

  final AppDatabase _db;
  final GuestOrderRequests _queue;

  /// يعتمد [requestId] فيكتب بنودَه في الطلب المفتوح.
  ///
  /// ⚠️ **والسعرُ يُقرأ الآن من المنتج، ولقطةُ الضريبة معه.** المرورُ بـ
  /// `addOrUpdateTableOrderItem` هو ما يجعل صنفَ الضيف مطابقاً لما يُدخِله
  /// النادلُ بيده: نفسُ الدمجِ مع بندٍ قائم، ونفسُ قاعدةِ «لا تُطمَس نسبةٌ
  /// محفوظة»، ونفسُ تحديثِ إجماليّ الطلب.
  Future<GuestApprovalOutcome> approve(int requestId) async {
    final pending = _queue.take(requestId);
    if (pending == null) return GuestApprovalOutcome.notPending;

    try {
      // ⚠️ **الطلبُ يُعاد فحصُه قبل الكتابة.** بين وصولِه واعتمادِه قد تكون
      // الطاولةُ أُغلقت ودُفعت وجلس عليها ضيفٌ آخر — فاعتمادُه حينَها يُضيف
      // أصنافاً إلى حسابِ من لم يطلبها.
      final order = await (_db.select(_db.tableOrders)
            ..where((o) => o.id.equals(pending.orderId))
            ..where((o) => o.status.isIn(['open', 'bill_requested'])))
          .getSingleOrNull();
      if (order == null) {
        _queue.dropForOrder(pending.orderId);
        return GuestApprovalOutcome.orderClosed;
      }

      for (final line in pending.lines) {
        final product = await (_db.select(_db.products)
              ..where((p) => p.id.equals(line.productId)))
            .getSingleOrNull();
        if (product == null) continue;
        await _db.addOrUpdateTableOrderItem(
          orderId: order.id,
          productId: product.id,
          quantity: line.quantity,
          unitPrice: product.salePrice,
          taxRate: product.taxRate,
        );
      }
      return GuestApprovalOutcome.approved;
    } catch (_) {
      return GuestApprovalOutcome.failed;
    }
  }

  /// يرفض الطلبَ — إسقاطٌ بلا كتابة.
  bool reject(int requestId) => _queue.reject(requestId);
}
