import 'dart:async';
import 'dart:math' as math;

import 'package:drift/drift.dart';

import '../core/constants/app_constants.dart';
import '../core/logging/diagnostic_logger.dart';
import '../data/database/database.dart';
import 'guest_order_requests.dart';
import '../domain/models/table_order_totals.dart';
import '../domain/models/table_status.dart';
import '../domain/models/tax_rate_bounds.dart';

/// انتقالٌ ممنوعٌ في آلة حالات الطاولة. رسالتُه تُعرَض للمستخدم كما هي.
class TableTransitionException implements Exception {
  const TableTransitionException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// مالكُ انتقالات الطاولة.
///
/// كلُّ انتقالٍ هنا يفعل شيئين لا واحداً: يُغيّر الحالة، ويكتب سطرَه في
/// `ActivityLogs`. السجلُّ مسلسَلٌ بالهاش (ICR-03) فيصير أثرُ الطاولة
/// غيرَ قابلٍ للتزوير بلا جدولٍ خاصٍّ به.
class TableSessionService {
  TableSessionService(this._db);

  final AppDatabase _db;

  static int get _factor =>
      math.pow(10, AppConstants.decimalPlaces).toInt();

  /// المقارنةُ بوحداتٍ صحيحةٍ لا بـ`double`: ‏٣٣٫٣٣٣×٣ لا يساوي ١٠٠ في
  /// حسابِ الفاصلة العائمة، فمقارنةُ `>=` المباشرة تُبقي طاولةً مدفوعةً
  /// بالكامل عالقةً على 🔵 إلى الأبد.
  static int _units(double value) => (value * _factor).round();

  Future<bool> _isFullyPaid(TableOrder order) async =>
      _units(order.paidAmount) >= _units((await _totalsOf(order)).total);

  Future<RestaurantTable> _table(int tableId) => (_db.select(
        _db.restaurantTables,
      )..where((t) => t.id.equals(tableId)))
          .getSingle();

  Future<void> _log({
    required int? userId,
    required String userName,
    required String action,
    required int tableId,
    required String description,
    double? amount,
    String? oldValue,
    String? newValue,
  }) =>
      _db.logActivity(
        userId: userId,
        userName: userName,
        action: action,
        entityType: 'table',
        entityId: tableId,
        description: description,
        amount: amount,
        oldValue: oldValue,
        newValue: newValue,
      );

  /// فتحُ طاولةٍ متاحةٍ أو محجوزةٍ (حضورُ الحجز) بعدد أشخاصٍ محدَّد.
  ///
  /// [userId] هو **الفاعل** (الموقَّع دخولُه) وإليه يُنسَب سطرُ السجل، أما
  /// [waiterId] فهو **النادلُ المسؤولُ عن الطلب** الذي تختاره شاشةُ الفتح.
  /// كانا شيئاً واحداً فكان اختيارُ النادل يضيع؛ وحين لا يُمرَّر نادلٌ يقع
  /// الطلبُ على الفاعل كما كان.
  /// [taxRate] نسبةُ الضريبة **كسريّةً** (0.16) تُنسَخ من إعداد
  /// `pos_default_tax_rate` وتُثبَّت على الطلب. الخدمةُ لا تملك `ref` فتقرأه
  /// بنفسها؛ المستدعي يقرأه ويمرّره. وتثبيتُه لقطةً — لا قراءةً حيّةً كما
  /// تفعل سلّةُ الكاشير — هو المقصود: الوجبةُ تمتدّ، وتغييرُ الإعداد في
  /// منتصفها يجب ألّا يُعيد تسعيرَ حسابٍ عُرض على الضيف. وافتراضُه صفرٌ كي
  /// تبقى المستدعياتُ القديمةُ (والاختباراتُ) تُصرَّف بلا تغيير.
  Future<int> openTable({
    required int tableId,
    required int guestCount,
    required int? userId,
    required String userName,
    int? waiterId,
    double taxRate = 0,
  }) async {
    _requireGuestCount(guestCount);
    return _db.transaction(() async {
      final table = await _table(tableId);
      if (table.status != TableStatus.available &&
          table.status != TableStatus.reserved) {
        throw TableTransitionException(
            'لا يمكن فتحُ ${table.name} — حالتُها الآن ${table.status}');
      }

      final orderId = await _insertOrder(
        tableId: tableId,
        guestCount: guestCount,
        waiterId: waiterId ?? userId,
        taxRate: taxRate,
      );
      await _log(
        userId: userId,
        userName: userName,
        action: 'table_open',
        tableId: tableId,
        description: 'فتح ${table.name} — $guestCount أشخاص',
      );
      return orderId;
    });
  }

  /// إضافةُ طلبٍ إلى طاولةٍ 🟠 — الطلبُ المسدَّدُ يُغلَق أوّلاً ثم يُفتح
  /// طلبٌ جديدٌ عليها.
  ///
  /// هذا ما تعنيه المواصفةُ بـ«بعد 🟠 لا تُضاف أصناف: الإضافةُ تفتح طلباً
  /// جديداً». وكانت الشاشةُ تنادي `createTableOrder` مباشرةً — فيبقى الطلبُ
  /// المسدَّدُ `open` ويُضاف إليه ثانٍ، فيصير على الطاولة صفّان يطابقان
  /// `getActiveOrderForTable`، و`getSingleOrNull()` ترمي `StateError` على
  /// **كلّ** قراءةٍ لاحقة: لا إغلاقٌ ولا إلغاءٌ ولا حتى عرضُ البطاقة. الإغلاقُ
  /// والفتحُ هنا في معاملةٍ واحدة، فلا لحظةَ تكون فيها الطاولةُ بطلبين.
  /// [taxRate] كسريّةٌ تُنسَخ من الإعداد — اقرأ [openTable].
  Future<int> openNewOrderOnPaidTable({
    required int tableId,
    required int guestCount,
    required int? userId,
    required String userName,
    int? waiterId,
    double taxRate = 0,
  }) async {
    _requireGuestCount(guestCount);
    return _db.transaction(() async {
      final table = await _table(tableId);
      if (table.status != TableStatus.paid) {
        throw TableTransitionException(
            'لا طلبَ مسدَّداً على ${table.name} — حالتُها الآن ${table.status}');
      }
      final settled = await _db.getActiveOrderForTable(tableId);
      if (settled == null) {
        throw TableTransitionException('لا يوجد طلبٌ على ${table.name}');
      }
      if (!await _isFullyPaid(settled)) {
        throw TableTransitionException(
            'الطلبُ #${settled.id} لم يُسدَّد كاملاً — دُفع ${settled.paidAmount} '
            'من ${(await _totalsOf(settled)).total}');
      }

      await (_db.update(_db.tableOrders)
            ..where((o) => o.id.equals(settled.id)))
          .write(TableOrdersCompanion(
        status: const Value('closed'),
        closedAt: Value(DateTime.now()),
      ));
      // ⚠️ وطلباتُ الضيوف المعلَّقةُ على هذا الطلب تسقط معه. ولولا ذلك بقيت
      // في شاشة النادل تنادي لطاولةٍ أُغلقت ودُفعت — وهو نداءٌ لا يُلبّى
      // (‏الاعتمادُ يرفضه ويُسقطه) لكنّه يبقى معروضاً حتى يلمسه أحد.
      GuestOrderRequests.instance.dropForOrder(settled.id);
      await _log(
        userId: userId,
        userName: userName,
        action: 'table_close',
        tableId: tableId,
        description: 'إغلاقُ الطلب #${settled.id} على ${table.name} — فُتح '
            'عليها طلبٌ جديد',
        amount: settled.total,
      );

      final orderId = await _insertOrder(
        tableId: tableId,
        guestCount: guestCount,
        waiterId: waiterId ?? userId,
        taxRate: taxRate,
      );
      await _log(
        userId: userId,
        userName: userName,
        action: 'table_open',
        tableId: tableId,
        description: 'فتحُ طلبٍ جديدٍ على ${table.name} — $guestCount أشخاص',
      );
      return orderId;
    });
  }

  /// حجزٌ سريعٌ للطاولة — يكتب الصفَّ **ويترك أثراً** في سجلّ العمليات (مَن
  /// حجز ومتى). وهذا حجزُ طاولةٍ لا موعدُ خدمة (العربونُ والخدمات لمنظومة
  /// الحجوزات). [partyId] = العميلُ المرجعيّ (معدومٌ = ضيف)، والاسمُ/الهاتفُ
  /// لقطةٌ. يُنادى `_db.createReservation` مباشرةً.
  Future<void> reserveTable({
    required int tableId,
    required String customerName,
    String? customerPhone,
    int? partyId,
    required DateTime reservationTime,
    required int partySize,
    String? notes,
    required int? userId,
    required String userName,
  }) async {
    await _db.createReservation(
      tableId: tableId,
      customerName: customerName,
      customerPhone: customerPhone,
      partyId: partyId,
      reservationTime: reservationTime,
      partySize: partySize,
      notes: notes,
    );
    final table = await _table(tableId);
    await _log(
      userId: userId,
      userName: userName,
      action: 'table_reserve',
      tableId: tableId,
      description: 'حجزُ ${table.name} باسم $customerName — '
          '${reservationTime.toIso8601String()} · $partySize أشخاص',
    );
  }

  static void _requireGuestCount(int guestCount) {
    if (guestCount < 1) {
      throw const TableTransitionException(
          'عددُ الأشخاص يجب أن يكون واحداً فأكثر');
    }
  }

  Future<int> _insertOrder({
    required int tableId,
    required int guestCount,
    required int? waiterId,
    double taxRate = 0,
  }) async {
    final orderId = await _db.into(_db.tableOrders).insert(
          TableOrdersCompanion.insert(
            tableId: tableId,
            userId: Value(waiterId),
            guestCount: Value(guestCount),
            // `taxEnabled` يبقى على افتراضه `false` — النسبةُ تُلقَط عند
            // الفتح لكنّ تفعيلَها قرارُ الكاشير من الزرّ، تماماً كسلّة
            // نقطة البيع.
            taxRate: Value(taxRate),
            openedAt: Value(DateTime.now()),
          ),
        );
    await _db.updateTableStatus(tableId, TableStatus.occupied);
    return orderId;
  }

  /// إغلاقُ طاولةٍ سُدِّد حسابُها كاملاً — روتينٌ بلا خطر.
  Future<void> closeTable({
    required int tableId,
    required int? userId,
    required String userName,
  }) async {
    await _db.transaction(() async {
      final table = await _table(tableId);
      final order = await _db.getActiveOrderForTable(tableId);
      if (order == null) {
        throw TableTransitionException('لا يوجد طلبٌ على ${table.name}');
      }
      if (!await _isFullyPaid(order)) {
        throw TableTransitionException(
            'لا يمكن الإغلاق قبل اكتمال الدفع — دُفع ${order.paidAmount} '
            'من ${(await _totalsOf(order)).total}');
      }

      await (_db.update(_db.tableOrders)
            ..where((o) => o.id.equals(order.id)))
          .write(TableOrdersCompanion(
        status: const Value('closed'),
        closedAt: Value(DateTime.now()),
      ));
      // ⚠️ وطلباتُ الضيوف المعلَّقةُ على هذا الطلب تسقط معه. ولولا ذلك بقيت
      // في شاشة النادل تنادي لطاولةٍ أُغلقت ودُفعت — وهو نداءٌ لا يُلبّى
      // (‏الاعتمادُ يرفضه ويُسقطه) لكنّه يبقى معروضاً حتى يلمسه أحد.
      GuestOrderRequests.instance.dropForOrder(order.id);
      await _db.updateTableStatus(tableId, TableStatus.available);
      await _log(
        userId: userId,
        userName: userName,
        action: 'table_close',
        tableId: tableId,
        description: 'إغلاق ${table.name}',
        amount: order.total,
      );
    });
  }

  /// إلغاءُ طلبٍ حيٍّ — هدمٌ. تُشترط له صلاحيةُ `tables_cancel` عند
  /// الاستدعاء، ويُشترط هنا ألّا يكون دُفع منه شيء.
  Future<void> cancelOrder({
    required int tableId,
    required int? userId,
    required String userName,
  }) async {
    await _db.transaction(() async {
      final table = await _table(tableId);
      final order = await _db.getActiveOrderForTable(tableId);
      if (order == null) {
        throw TableTransitionException('لا يوجد طلبٌ على ${table.name}');
      }
      if (_units(order.paidAmount) > 0) {
        throw const TableTransitionException(
            'لا يمكن إلغاءُ طلبٍ دُفع منه شيء — فاتورةٌ صدرت ورُحِّلت');
      }

      await (_db.update(_db.tableOrders)
            ..where((o) => o.id.equals(order.id)))
          .write(TableOrdersCompanion(
        status: const Value('cancelled'),
        closedAt: Value(DateTime.now()),
      ));
      await _db.updateTableStatus(tableId, TableStatus.available);
      await _log(
        userId: userId,
        userName: userName,
        action: 'table_order_cancel',
        tableId: tableId,
        description: 'إلغاءُ طلبِ ${table.name}',
        amount: order.total,
      );
    });
  }

  /// إخراجُ الطاولة من الخدمة أو إعادتُها — بين 🟢 و⚪ فقط.
  ///
  /// والقيدُ على الطرفين لا على الهدف وحدَه. طاولةٌ 🟣 محجوزةٌ لا طلبَ عليها
  /// كانت تمرّ من هنا: تُخرَج من الخدمة ثم تُعاد، فتحطّ على 🟢 «متاحة» وقد
  /// ضاعت علامةُ الحجز بينما صفُّ الحجز باقٍ في `TableReservations` — طاولةٌ
  /// تبدو حرّةً وهي محجوزةٌ فتُجلَس عليها مجموعةٌ أخرى. إلغاءُ الحجز له بابُه.
  Future<void> setTableStatus({
    required int tableId,
    required String status,
    required int? userId,
    required String userName,
  }) async {
    if (status != TableStatus.available &&
        status != TableStatus.outOfService) {
      throw TableTransitionException(
          'تغييرُ الحالة اليدويُّ بين المتاحة وغير المتاحة فقط، لا إلى $status');
    }
    await _db.transaction(() async {
      final table = await _table(tableId);
      if (table.status != TableStatus.available &&
          table.status != TableStatus.outOfService) {
        throw TableTransitionException(
            'تغييرُ الحالة اليدويُّ من المتاحة أو غير المتاحة فقط — '
            '${table.name} حالتُها ${table.status}');
      }
      final order = await _db.getActiveOrderForTable(tableId);
      if (order != null) {
        throw TableTransitionException(
            'على ${table.name} طلبٌ مفتوح — أغلقه أوّلاً');
      }

      await _db.updateTableStatus(tableId, status);
      await _log(
        userId: userId,
        userName: userName,
        action: 'table_status_change',
        tableId: tableId,
        description: 'تغييرُ حالة ${table.name}',
        oldValue: table.status,
        newValue: status,
      );
    });
  }

  /// نتيجةُ دمجٍ — تُبلِّغ الواجهةَ بما سقط ليُعرَض في التأكيد.
  Future<MergeOutcome> mergeOrders({
    required int sourceTableId,
    required int targetTableId,
    required int? userId,
    required String userName,
  }) async {
    // دمجُ الطاولة في نفسها: كلُّ حارسٍ لاحقٍ يمرّ لأن المصدرَ والهدفَ نفسُ
    // الطلب، فيُعاد وسمُ كلِّ بندٍ على نفسه ويُغلَق الطلبُ الحيُّ الوحيد
    // بصمت. هذا الحارسُ يمنعه قبل فتح المعاملة.
    if (sourceTableId == targetTableId) {
      throw const TableTransitionException(
          'لا تُدمج الطاولةُ في نفسها');
    }
    unawaited(DiagnosticLogger.log(
        'TABLE-MERGE', '14/ الخدمة: قبل فتح المعاملة'));
    return _db.transaction(() async {
      unawaited(
          DiagnosticLogger.log('TABLE-MERGE', '15/ الخدمة: المعاملةُ فُتحت'));
      final source = await _table(sourceTableId);
      final target = await _table(targetTableId);
      final sourceOrder = await _db.getActiveOrderForTable(sourceTableId);
      final targetOrder = await _db.getActiveOrderForTable(targetTableId);
      unawaited(DiagnosticLogger.log('TABLE-MERGE',
          '16/ الخدمة: الطلبان src=${sourceOrder?.id} tgt=${targetOrder?.id}'));

      if (sourceOrder == null) {
        throw TableTransitionException('لا يوجد طلبٌ على ${source.name}');
      }
      if (targetOrder == null) {
        throw TableTransitionException('لا يوجد طلبٌ على ${target.name}');
      }
      if (_units(sourceOrder.paidAmount) > 0 ||
          _units(targetOrder.paidAmount) > 0) {
        throw const TableTransitionException(
            'لا يمكن دمجُ طلبٍ دُفع منه شيء — فاتورةٌ صدرت ورُحِّلت');
      }

      final droppedDiscount = _units(sourceOrder.discountValue) > 0;

      unawaited(DiagnosticLogger.log(
          'TABLE-MERGE', '17/ الخدمة: الحرّاسُ مرّوا — نداءُ الـDAO'));
      await _db.mergeTableOrders(sourceTableId, targetTableId);
      unawaited(
          DiagnosticLogger.log('TABLE-MERGE', '18/ الخدمة: الـDAO انتهى'));

      // الضيوفُ يُجمعون: صاروا على طاولةٍ واحدة.
      await (_db.update(_db.tableOrders)
            ..where((o) => o.id.equals(targetOrder.id)))
          .write(TableOrdersCompanion(
        guestCount:
            Value(targetOrder.guestCount + sourceOrder.guestCount),
      ));

      await _log(
        userId: userId,
        userName: userName,
        action: 'table_merge',
        tableId: targetTableId,
        description: 'دمجُ ${source.name} في ${target.name}'
            '${droppedDiscount ? ' — أُسقط خصمُ ${source.name}' : ''}',
        amount: sourceOrder.total,
      );

      return MergeOutcome(
        droppedDiscount: droppedDiscount,
        droppedDiscountLabel: droppedDiscount
            ? '${sourceOrder.discountValue}'
                '${sourceOrder.discountType == 'percent' ? '٪' : ''}'
            : null,
      );
    });
  }

  /// نقلُ الطلبِ كاملاً إلى طاولةٍ متاحة.
  ///
  /// كلُّ ما تُعدّده المواصفة — رقمُ الطلب والأصناف والكميّات والملاحظات
  /// والخصومات والضرائب والموظف والإجمالي والحالة — حقولٌ في صفِّ الطلب
  /// الواحد. فالنقلُ تحديثُ `tableId` لا غير، وينتقل كلُّ ذلك بلا احتمالِ
  /// ضياع.
  Future<void> transferOrder({
    required int fromTableId,
    required int toTableId,
    required int? userId,
    required String userName,
  }) async {
    await _db.transaction(() async {
      final from = await _table(fromTableId);
      final to = await _table(toTableId);
      final order = await _db.getActiveOrderForTable(fromTableId);

      if (order == null) {
        throw TableTransitionException('لا يوجد طلبٌ على ${from.name}');
      }
      if (_units(order.paidAmount) > 0) {
        throw const TableTransitionException(
            'لا يمكن نقلُ طلبٍ دُفع منه شيء — فاتورةٌ صدرت ورُحِّلت');
      }
      if (to.status != TableStatus.available) {
        throw TableTransitionException('${to.name} غيرُ متاحة');
      }

      await _db.transferTableOrder(fromTableId, toTableId);
      await _log(
        userId: userId,
        userName: userName,
        action: 'table_transfer',
        tableId: toTableId,
        description:
            'نقلُ الطلب #${order.id} من ${from.name} إلى ${to.name}',
        amount: order.total,
        oldValue: from.name,
        newValue: to.name,
      );
    });
  }

  /// نقلُ بنودٍ مختارةٍ (بكمّياتها) من طلبٍ إلى آخر — لا الطلبَ كاملاً.
  ///
  /// نفسُ حارس `transferOrder`: لا نقلَ من طلبٍ دُفع منه شيء — فاتورةٌ صدرت
  /// وتُرحَّل على أصنافٍ وإجماليٍّ صار الآن يتزحزح خلفها بلا أثر. الحركةُ
  /// الفعليّةُ (تقسيمُ البند أو نقلُه، وتحديثُ إجماليَي الطلبين، وإغلاقُ
  /// المصدر إن فرغ) تبقى في `partialTransferTableOrder` — لا إعادةَ تنفيذٍ
  /// هنا، فقط الحارسُ والسجلُّ.
  Future<void> partialTransferOrder({
    required int fromTableId,
    required int toTableId,
    required Map<int, double> itemQuantities,
    required int? userId,
    required String userName,
  }) async {
    if (fromTableId == toTableId) {
      throw const TableTransitionException(
          'لا يُنقل جزءٌ من الطاولة إلى نفسها');
    }
    await _db.transaction(() async {
      final from = await _table(fromTableId);
      final to = await _table(toTableId);
      final order = await _db.getActiveOrderForTable(fromTableId);

      if (order == null) {
        throw TableTransitionException('لا يوجد طلبٌ على ${from.name}');
      }
      if (_units(order.paidAmount) > 0) {
        throw const TableTransitionException(
            'لا يمكن نقلُ بنودٍ من طلبٍ دُفع منه شيء — فاتورةٌ صدرت ورُحِّلت');
      }

      await _db.partialTransferTableOrder(
        sourceTableId: fromTableId,
        targetTableId: toTableId,
        itemQuantities: itemQuantities,
      );
      await _log(
        userId: userId,
        userName: userName,
        action: 'table_partial_transfer',
        tableId: toTableId,
        description:
            'نقلُ ${itemQuantities.length} صنفٍ من ${from.name} إلى ${to.name}',
        oldValue: from.name,
        newValue: to.name,
      );
    });
  }

  /// إجمالياتُ الطلب كاملةً — المجموعُ والخصمُ والضريبةُ والمستحقّ.
  ///
  /// هذه هي **نقطةُ الحساب الوحيدة** لخدمة الطاولات. الشاشةُ والبطاقةُ
  /// وشاشةُ التقسيم والطباعةُ كلُّها تمرّ من هنا، فلا تُنسَخ قاعدةُ الخصم
  /// ولا قاعدةُ الضريبة في أيٍّ منها. وكانت منسوخةً في أربعة مواضع.
  Future<TableOrderTotals> totalsFor(int orderId) async =>
      _totalsOf(await _order(orderId));

  Future<TableOrder> _order(int orderId) => (_db.select(_db.tableOrders)
        ..where((o) => o.id.equals(orderId)))
      .getSingle();

  /// الجسرُ بين صفوف القاعدة والنموذج الخالص.
  ///
  /// وهنا **الموضعُ الوحيدُ** الذي تُحوَّل فيه نسبةُ الطلب من كسريّةٍ
  /// (`TableOrders.taxRate` = 0.16، لقطةُ `pos_default_tax_rate`) إلى مئويّةٍ
  /// (16) التي يفهمها النموذج. نِسَبُ البنود مئويّةٌ أصلاً (منسوخةٌ عن
  /// `Products.taxRate`) فتُمرَّر كما هي.
  Future<TableOrderTotals> _totalsOf(TableOrder order) async {
    final items = await (_db.select(_db.tableOrderItems)
          ..where((i) => i.tableOrderId.equals(order.id)))
        .get();
    return _totalsOfItems(order, items, await _exemptIdsOf(items));
  }

  /// B3 — «معفى» products among the order lines (raw `products.tax_exempt`).
  Future<Set<int>> _exemptIdsOf(List<TableOrderItem> items) =>
      _db.getTaxExemptProductIds(items.map((i) => i.productId));

  static TableOrderTotals _totalsOfItems(
    TableOrder order,
    List<TableOrderItem> items,
    Set<int> exemptProductIds,
  ) {
    return TableOrderTotals.compute(
      lines: items
          .map((i) => TableOrderLine(
                quantity: i.quantity,
                unitPrice: i.unitPrice,
                taxRate: i.taxRate,
                taxExempt: exemptProductIds.contains(i.productId),
              ))
          .toList(),
      discountType: order.discountType,
      discountValue: order.discountValue,
      taxEnabled: order.taxEnabled,
      taxPercent: TableOrderTotals.taxPercentFromRate(order.taxRate),
    );
  }

  /// الإجماليُّ بعد الخصم وفوقه الضريبة — وهو ما يُقسَّم ويُدفع ويُطبع.
  Future<double> effectiveTotal(int orderId) async =>
      (await totalsFor(orderId)).total;

  /// `itemId → حصّتُه من المستحقّ` — نصيبُه من الخصم وضريبتُه فوقه.
  ///
  /// التقسيمُ بالأصناف يحتاجها: كان يجمع `TableOrderItems.total` الخامَ
  /// (كميّة × سعر)، فمجموعُ الحصص لا يبلغ المستحقَّ متى كان على الطلب خصمٌ
  /// أو ضريبة — فتُسوَّى الحصصُ كلُّها وتبقى الطاولةُ «غيرَ مدفوعة» بلا
  /// رسالةِ خطأٍ واحدة.
  ///
  /// والقراءةُ هنا مرّةٌ واحدةٌ بقصد: الحصصُ تُزاوَج بالبنود بالفهرس، فلا
  /// يجوز أن يُعاد الاستعلامُ بينهما وقد تغيّر الترتيب.
  Future<Map<int, double>> effectiveLineTotals(int orderId) async {
    final order = await _order(orderId);
    final items = await (_db.select(_db.tableOrderItems)
          ..where((i) => i.tableOrderId.equals(order.id)))
        .get();
    final totals = _totalsOfItems(order, items, await _exemptIdsOf(items));
    return {
      for (var i = 0; i < items.length; i++)
        items[i].id: totals.lineTotals[i],
    };
  }

  /// المتبقّي على الطلب: الإجماليُّ بعد الخصم ناقصاً ما دُفع منه.
  ///
  /// هذا هو الرقمُ الذي تقيس عليه شاشةُ التحصيل سلّتَها **قبل** ترحيل
  /// الفاتورة. حسابُه هنا لا في الشاشة لأنه نفسُ الحساب الذي يحكم به
  /// [recordPayment] على الدفعة؛ ونسخُه في الشاشة يعني محرّكاً ثالثاً.
  Future<double> amountDue(int orderId) async {
    final order = await _order(orderId);
    final totals = await _totalsOf(order);
    final due = _units(totals.total) - _units(order.paidAmount);
    return (due < 0 ? 0 : due) / _factor;
  }

  /// تثبيتُ خصمٍ على الطلب قبل الدفع.
  ///
  /// تُشترط صلاحيةُ `tables_discount` عند الاستدعاء. وتثبيتُه على الطلب —
  /// لا في السلة لحظةَ الدفع — هو ما يجعله ينتقل مع الطلب ويظهر في فاتورة
  /// ما قبل الدفع.
  Future<void> setOrderDiscount({
    required int orderId,
    required String? type,
    required double value,
    required int? userId,
    required String userName,
  }) async {
    await _db.transaction(() async {
      final order = await (_db.select(_db.tableOrders)
            ..where((o) => o.id.equals(orderId)))
          .getSingle();

      if (_units(order.paidAmount) > 0) {
        throw const TableTransitionException(
            'لا يمكن تعديلُ خصمِ طلبٍ دُفع منه شيء');
      }
      if (type != null && type != 'percent' && type != 'amount') {
        throw TableTransitionException('نوعُ خصمٍ غيرُ معروف: $type');
      }
      if (value < 0) {
        throw const TableTransitionException('الخصمُ لا يكون سالباً');
      }
      if (type == 'percent' && value > 100) {
        throw const TableTransitionException('النسبةُ لا تتجاوز ١٠٠٪');
      }
      if (type == 'amount' && _units(value) > _units(order.total)) {
        throw TableTransitionException(
            'الخصمُ $value يتجاوز إجماليَّ الطلب ${order.total}');
      }

      await (_db.update(_db.tableOrders)..where((o) => o.id.equals(orderId)))
          .write(TableOrdersCompanion(
        discountType: Value(type),
        discountValue: Value(type == null ? 0 : value),
      ));

      await _log(
        userId: userId,
        userName: userName,
        action: 'table_discount',
        tableId: order.tableId,
        description: 'تعديلُ خصمِ الطلب #$orderId',
        oldValue: '${order.discountType}:${order.discountValue}',
        newValue: type == null ? 'none' : '$type:$value',
      );
    });
  }

  /// تفعيلُ ضريبة المبيعات على الطلب أو إطفاؤها.
  ///
  /// تُكتب **على الطلب** لا في السلّة: هي التي تجعل ما يُشحَن على الفاتورة
  /// وما يُسجَّل على الطلب رقماً واحداً، فيسكت حارسُ `checkTableCharge`.
  /// وتنتقل مع الطلب عند النقل، وتُطبع في فاتورة ما قبل الدفع.
  ///
  /// والرفضُ بعد أوّل دفعةٍ ليس تشدّداً: تغييرُ الضريبة على طلبٍ سُوِّيت منه
  /// حصّةٌ يُعيد تسعير حصصٍ حُصِّلت بالفعل وصدرت فواتيرُها — فيصير المجموعُ
  /// المسجَّلُ لا يطابق مجموعَ الفواتير الصادرة. نفسُ حارس [setOrderDiscount]
  /// وللسبب نفسِه.
  Future<void> setOrderTax({
    required int orderId,
    required bool enabled,
    required int? userId,
    required String userName,
  }) async {
    await _db.transaction(() async {
      final order = await _order(orderId);

      if (_units(order.paidAmount) > 0) {
        throw const TableTransitionException(
            'لا يمكن تعديلُ ضريبةِ طلبٍ دُفع منه شيء');
      }
      // ضريبةٌ «مفعَّلةٌ» بنسبةٍ صفرٍ حالةٌ تكذب: الزرُّ يقول «مفعلة (0%)»،
      // ولا ضريبةَ تُحصَّل، **ولا حارسَ يُطلق** لأن المحرّكين يتّفقان على
      // الصفر — فتخرج الفاتورةُ بلا سطر ضريبةٍ ويُنقَص التحصيلُ في الدفاتر
      // بلا كلمةٍ عند الصندوق. ورفضٌ عالٍ عند المفتاح خيرٌ من نقصٍ صامتٍ في
      // الفاتورة، ولذلك تُمنَع الحالةُ حيث تُكتَب لا حيث تُكتشَف.
      //
      // والعتبةُ [TaxRateBounds.minRate] لا الصفرَ: `tax_rate > 0` تقبل
      // `0.0000001` — فالزرُّ «مفعَّل» والقيدُ راضٍ والمحصَّلُ صفرٌ بعد
      // التقريب. الكذبةُ نفسُها بصورةٍ أدقَّ تمرّ من تحت قيد v156، ولا يمسكها
      // إلّا حدٌّ يقول ما النسبةُ التي تستحقّ أن تُدَّعى.
      if (enabled && order.taxRate < TaxRateBounds.minRate) {
        throw const TableTransitionException(
            'نسبةُ الضريبة على هذا الطلب دون الحدّ الأدنى (١٪) — اضبط '
            '«نسبة الضريبة الافتراضية» في الإعدادات ثم افتح الطاولةَ من جديد');
      }
      if (order.taxEnabled == enabled) return;

      await (_db.update(_db.tableOrders)..where((o) => o.id.equals(orderId)))
          .write(TableOrdersCompanion(taxEnabled: Value(enabled)));

      await _log(
        userId: userId,
        userName: userName,
        action: 'table_tax',
        tableId: order.tableId,
        description: enabled
            ? 'تفعيلُ ضريبةِ الطلب #$orderId'
            : 'إطفاءُ ضريبةِ الطلب #$orderId',
        oldValue: order.taxEnabled ? 'on' : 'off',
        newValue: enabled ? 'on' : 'off',
      );
    });
  }

  /// طلبُ فاتورةِ ما قبل الدفع.
  ///
  /// تُشترط صلاحيةُ `tables_print_bill` عند الاستدعاء. الطلبُ يصير
  /// `bill_requested` — وهي صفةٌ **للطلب** لا للطاولة، فالطاولةُ تبقى 🔵
  /// (حالةُ `billing` مشطوبةٌ من مفردات الطاولة في v154). وعلى طلبٍ سُدِّد
  /// كاملاً هي إعادةُ طباعةٍ فحسب، فلا تُغيَّر حالتُه — يبقى قابلاً
  /// للإغلاق كما هو.
  Future<void> requestBill({
    required int orderId,
    required int? userId,
    required String userName,
  }) async {
    await _db.transaction(() async {
      final order = await (_db.select(_db.tableOrders)
            ..where((o) => o.id.equals(orderId)))
          .getSingle();
      if (order.status != 'open' && order.status != 'bill_requested') {
        throw TableTransitionException(
            'لا تُطلب فاتورةُ طلبٍ حالتُه ${order.status}');
      }

      final settled = await _isFullyPaid(order);
      if (!settled) {
        await _db.requestTableBill(orderId);
      }
      await _log(
        userId: userId,
        userName: userName,
        action: 'table_print_bill',
        tableId: order.tableId,
        description: settled
            ? 'إعادةُ طباعة فاتورة الطلب #$orderId'
            : 'طلبُ فاتورة الطلب #$orderId',
        amount: (await _totalsOf(order)).total,
      );
    });
  }

  /// ملاحظةُ بندٍ («بلا بصل») — تصل المطبخ وتُطبع.
  Future<void> setItemNotes({
    required int orderItemId,
    required String? notes,
  }) async {
    await (_db.update(_db.tableOrderItems)
          ..where((i) => i.id.equals(orderItemId)))
        .write(TableOrderItemsCompanion(notes: Value(notes)));
  }

  /// تسجيلُ دفعةٍ على الطلب بعد صدور فاتورتها.
  ///
  /// الحالةُ مشتقّةٌ لا مخزَّنةٌ مرّتين: تبقى الطاولة 🔵 حتى يبلغ
  /// `paidAmount` الإجماليَّ بعد الخصم، فتصير 🟠. ويترتّب على ذلك أثرٌ
  /// مقصود — إن أُضيف صنفٌ بعد دفعةٍ جزئيّة، ارتفع الإجماليُّ فوق المدفوع
  /// فعادت الطاولة 🔵 من تلقائها بلا قاعدةٍ خاصّة.
  ///
  /// [userId]/[userName] اختياريّان — لا مستدعيَ اليوم يملك سياقَ مستخدمٍ
  /// حقيقيّاً (المنسّقُ `TableCheckoutCoordinator` لا يمرّره)، فتُترك
  /// `null`/"مجهول" بدل إجبار كلِّ مستدعٍ على تمرير قيمةٍ لا يملكها. الوثيقةُ
  /// نفسُها التي كتبت كلَّ انتقالٍ آخر في هذا الملف — لا يُترك الدفعُ
  /// وحدَه بلا سطرٍ في `ActivityLogs`.
  Future<void> recordPayment({
    required int orderId,
    required int invoiceId,
    required double amount,
    String? splitLabel,
    int? userId,
    String? userName,
  }) async {
    // مُعادُ البناءِ فوق `reservePayment` + `confirmPayment` في معاملةٍ واحدة.
    // سلوكُه لمن يملك فاتورةً بالفعل لم يتغيّر، وحسابُ المال بقي في مسارٍ
    // واحدٍ لا نسختين تفترقان.
    await _db.transaction(() async {
      final reservationId = await _reserve(
        orderId: orderId,
        amount: amount,
        splitLabel: splitLabel,
        userId: userId,
        userName: userName,
        action: 'table_payment',
        description: splitLabel != null
            ? 'دفعةُ $splitLabel — فاتورة #$invoiceId'
            : 'دفعةٌ — فاتورة #$invoiceId',
      );
      await _confirm(reservationId: reservationId, invoiceId: invoiceId);
    });
  }

  /// يحجز المبلغَ على الطلب **قبل** أن تُرحَّل فاتورتُه.
  ///
  /// هنا تعمل كلُّ الحراس التي كانت تعمل بعد الترحيل: المبلغُ موجب، والطلبُ
  /// في حالةٍ تقبل الدفع، والمجموعُ لا يتجاوز المستحقّ — **ولا شيءَ رُحِّل
  /// بعد**. فإن رمى حارسٌ، لا فاتورةَ يتيمةَ تحتاج تسويةً يدويّة.
  ///
  /// ويرفع `paidAmount` فوراً ولا يُضاف عمودُ «محجوز»: حقلُ مالٍ واحدٌ ومصدرُ
  /// حقٍّ واحد. و`paidAmount` حقلٌ تشغيليٌّ لخدمة الطاولات لا حسابٌ في
  /// الأستاذ — الدفاترُ لا تتحرّك إلّا بترحيل الفاتورة، فأجزاءُ الثانية التي
  /// يكون فيها «مدفوعٌ بلا فاتورة» لا تمسّ قيداً واحداً.
  ///
  /// يعيد رقمَ الحجز — يُمرَّر إلى [confirmPayment] أو [releaseReservation].
  Future<int> reservePayment({
    required int orderId,
    required double amount,
    String? splitLabel,
    int? userId,
    String? userName,
  }) =>
      _db.transaction(() => _reserve(
            orderId: orderId,
            amount: amount,
            splitLabel: splitLabel,
            userId: userId,
            userName: userName,
            action: 'table_payment_reserved',
            description: splitLabel != null
                ? 'حجزُ دفعةِ $splitLabel — بانتظار الفاتورة'
                : 'حجزُ دفعةٍ — بانتظار الفاتورة',
          ));

  Future<int> _reserve({
    required int orderId,
    required double amount,
    required String? splitLabel,
    required int? userId,
    required String? userName,
    required String action,
    required String description,
  }) async {
    if (amount <= 0) {
      throw const TableTransitionException('الدفعةُ يجب أن تكون موجبة');
    }

    final order = await _order(orderId);

    if (order.status != 'open' && order.status != 'bill_requested') {
      throw TableTransitionException(
          'لا تُسجَّل دفعةٌ على طلبٍ حالتُه ${order.status}');
    }

    // حجزٌ معلّقٌ آخرُ يعني ترحيلاً جارياً أو انهياراً تركه — وحجزٌ ثانٍ فوقه
    // يُراكم مالاً لا سندَ له. يُحرَّر الأوّلُ أو يُثبَّت قبل أن يُفتَح ثانٍ.
    final pending = await (_db.select(_db.tableOrderPayments)
          ..where((p) =>
              p.tableOrderId.equals(orderId) & p.status.equals('pending'))
          ..limit(1))
        .getSingleOrNull();
    if (pending != null) {
      throw TableTransitionException(
          'على هذا الطلب حجزٌ معلّقٌ (#${pending.id} بمبلغ ${pending.amount}) — '
          'ثبّته أو حرّره قبل حجزٍ جديد');
    }

    final due = _units((await _totalsOf(order)).total);
    final already = _units(order.paidAmount);
    if (already + _units(amount) > due) {
      throw TableTransitionException(
          'الدفعةُ $amount تتجاوز المتبقّي ${(due - already) / _factor}');
    }

    final reservationId = await _db.into(_db.tableOrderPayments).insert(
          TableOrderPaymentsCompanion.insert(
            tableOrderId: orderId,
            amount: amount,
            splitLabel: Value(splitLabel),
            paidAt: Value(DateTime.now()),
            status: const Value('pending'),
          ),
        );

    final newPaid = (already + _units(amount)) / _factor;
    await (_db.update(_db.tableOrders)..where((o) => o.id.equals(orderId)))
        .write(TableOrdersCompanion(paidAmount: Value(newPaid)));

    if (already + _units(amount) >= due) {
      await _db.updateTableStatus(order.tableId, TableStatus.paid);
    }

    await _log(
      userId: userId,
      userName: userName ?? 'مجهول',
      action: action,
      tableId: order.tableId,
      description: description,
      amount: amount,
    );

    return reservationId;
  }

  /// يكتب رقمَ الفاتورة على حجزٍ قائمٍ فيصير مثبَّتاً.
  ///
  /// **لا حسابَ مالٍ فيها**: المبلغُ سُجِّل عند الحجز و`paidAmount` رُفع
  /// هناك. فلا قاعدةَ عملٍ تردّ هذه الخطوة — وهذا هو بيتُ القصيد: ما يقع
  /// بعد الترحيل لا يمكن أن يُرفض، فلا تتباعد الدفاترُ عن الطاولة.
  Future<void> confirmPayment({
    required int reservationId,
    required int invoiceId,
  }) =>
      _db.transaction(
          () => _confirm(reservationId: reservationId, invoiceId: invoiceId));

  Future<void> _confirm({
    required int reservationId,
    required int invoiceId,
  }) async {
    final updated = await (_db.update(_db.tableOrderPayments)
          ..where((p) => p.id.equals(reservationId) & p.status.equals('pending')))
        .write(TableOrderPaymentsCompanion(
      invoiceId: Value(invoiceId),
      status: const Value('settled'),
    ));

    if (updated == 0) {
      throw TableTransitionException(
          'لا حجزَ معلّقٌ بالرقم #$reservationId ليُثبَّت');
    }
  }

  /// يُلغي حجزاً لم تصدر فاتورتُه ويردّ ما ترتّب عليه.
  ///
  /// يُنادى حين يفشل الترحيلُ أو يتراجع الكاشير. ولا يُنادى آلياً على حجزٍ
  /// عالقٍ من انهيار: قد تكون فاتورتُه رُحّلت فعلاً وفشل تثبيتُها وحدَه،
  /// فتحريرُه حينئذٍ يمحو دفعةً حقيقيّة. يبقى ظاهراً ليحسمه إنسان.
  Future<void> releaseReservation({
    required int reservationId,
    required String reason,
    int? userId,
    String? userName,
  }) async {
    await _db.transaction(() async {
      final row = await (_db.select(_db.tableOrderPayments)
            ..where((p) =>
                p.id.equals(reservationId) & p.status.equals('pending')))
          .getSingleOrNull();
      if (row == null) {
        throw TableTransitionException(
            'لا حجزَ معلّقٌ بالرقم #$reservationId ليُحرَّر');
      }

      final order = await _order(row.tableOrderId);

      await (_db.delete(_db.tableOrderPayments)
            ..where((p) => p.id.equals(reservationId)))
          .go();

      final restored = _units(order.paidAmount) - _units(row.amount);
      await (_db.update(_db.tableOrders)
            ..where((o) => o.id.equals(row.tableOrderId)))
          .write(TableOrdersCompanion(
              paidAmount: Value(restored < 0 ? 0 : restored / _factor)));

      // الحالةُ تُشتقّ من جديدٍ لا تُفترَض: الطاولةُ قد تكون قُلبت «مدفوعة»
      // عند الحجز، وردُّ المبلغِ يُعيدها مشغولةً ما لم تبلغها دفعاتٌ أخرى.
      final due = _units((await _totalsOf(order)).total);
      if (restored < due) {
        await _db.updateTableStatus(order.tableId, TableStatus.occupied);
      }

      await _log(
        userId: userId,
        userName: userName ?? 'مجهول',
        action: 'table_payment_released',
        tableId: order.tableId,
        description: 'تحريرُ حجزٍ #$reservationId — $reason',
        amount: row.amount,
      );
    });
  }

  /// الحجوزُ المعلّقةُ على طلب — تُعرَض في سجلِّ الطاولة ليحسمها إنسان.
  Future<List<TableOrderPayment>> pendingReservations(int orderId) =>
      (_db.select(_db.tableOrderPayments)
            ..where((p) =>
                p.tableOrderId.equals(orderId) & p.status.equals('pending'))
            ..orderBy([(p) => OrderingTerm.asc(p.id)]))
          .get();

  /// دفعاتُ الطلب مرتّبةً بترتيب حدوثها.
  /// دفعاتُ الطلب **المثبَّتةُ** وحدَها، مرتّبةً بترتيب حدوثها.
  ///
  /// الترشيحُ بـ`settled` شرطُ صحّةٍ محاسبيٌّ لا تحسين: الصفُّ المحجوزُ لا
  /// فاتورةَ له بعد، فاحتسابُه هنا يربط مالاً بسندٍ لم يصدر. والحجوزُ
  /// المعلّقةُ تُقرأ من [pendingReservations] حيث يُقصَد أن تُرى.
  Future<List<TableOrderPayment>> paymentsFor(int orderId) =>
      (_db.select(_db.tableOrderPayments)
            ..where((p) =>
                p.tableOrderId.equals(orderId) & p.status.equals('settled'))
            ..orderBy([(p) => OrderingTerm.asc(p.id)]))
          .get();
}

/// ما سقط في الدمج — تعرضه الواجهةُ في نافذة التأكيد.
class MergeOutcome {
  const MergeOutcome({
    required this.droppedDiscount,
    this.droppedDiscountLabel,
  });

  /// هل كان على الطاولة المدموجة خصمٌ أُسقط؟
  ///
  /// خصمُ الرئيسية يبقى وحدَه. جمعُ الخصمين يعني أن خصماً مُنح لأربعةٍ صار
  /// يُطبَّق على ثمانية — تسريبُ مالٍ صامت.
  final bool droppedDiscount;
  final String? droppedDiscountLabel;
}
