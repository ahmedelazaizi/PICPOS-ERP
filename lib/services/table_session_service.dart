import 'dart:math' as math;

import 'package:drift/drift.dart';

import '../core/constants/app_constants.dart';
import '../data/database/database.dart';
import '../domain/models/table_status.dart';

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

  static bool _isFullyPaid(TableOrder order) =>
      _units(order.paidAmount) >= _units(order.total);

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
  Future<int> openTable({
    required int tableId,
    required int guestCount,
    required int? userId,
    required String userName,
  }) async {
    if (guestCount < 1) {
      throw const TableTransitionException(
          'عددُ الأشخاص يجب أن يكون واحداً فأكثر');
    }
    return _db.transaction(() async {
      final table = await _table(tableId);
      if (table.status != TableStatus.available &&
          table.status != TableStatus.reserved) {
        throw TableTransitionException(
            'لا يمكن فتحُ ${table.name} — حالتُها الآن ${table.status}');
      }

      final orderId = await _db.into(_db.tableOrders).insert(
            TableOrdersCompanion.insert(
              tableId: tableId,
              userId: Value(userId),
              guestCount: Value(guestCount),
              openedAt: Value(DateTime.now()),
            ),
          );
      await _db.updateTableStatus(tableId, TableStatus.occupied);
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
      if (!_isFullyPaid(order)) {
        throw TableTransitionException(
            'لا يمكن الإغلاق قبل اكتمال الدفع — دُفع ${order.paidAmount} '
            'من ${order.total}');
      }

      await (_db.update(_db.tableOrders)
            ..where((o) => o.id.equals(order.id)))
          .write(TableOrdersCompanion(
        status: const Value('closed'),
        closedAt: Value(DateTime.now()),
      ));
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
    return _db.transaction(() async {
      final source = await _table(sourceTableId);
      final target = await _table(targetTableId);
      final sourceOrder = await _db.getActiveOrderForTable(sourceTableId);
      final targetOrder = await _db.getActiveOrderForTable(targetTableId);

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

      await _db.mergeTableOrders(sourceTableId, targetTableId);

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
