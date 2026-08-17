import 'table_status.dart';

enum TableAction {
  open,
  addItems,
  transfer,
  merge,
  splitBill,
  printBill,
  reserve,
  pay,
  changeStatus,
  cancelOrder,
  closeTable,
  log,
}

/// الكبساتُ المسموحةُ لحالةٍ ما.
///
/// دالّةٌ خالصةٌ مُختبَرة لا شروطٌ متناثرةٌ في `build`: عرضُ «دفع» لطاولةٍ
/// فارغةٍ أو «نقل» لطاولةٍ بلا طلبٍ كان أحدَ العيوب التي نُصلحها، وشرطٌ
/// منسيٌّ في ودجتٍ واحدةٍ يُعيده.
List<TableAction> actionsForStatus(String status) {
  switch (status) {
    case TableStatus.available:
      return const [
        TableAction.open,
        TableAction.reserve,
        TableAction.changeStatus,
        TableAction.log,
      ];
    case TableStatus.occupied:
      return const [
        TableAction.addItems,
        TableAction.transfer,
        TableAction.merge,
        TableAction.splitBill,
        TableAction.printBill,
        TableAction.pay,
        TableAction.cancelOrder,
        TableAction.log,
      ];
    case TableStatus.paid:
      // الإضافةُ هنا تفتح طلباً جديداً وتُعيد الطاولة 🔵 — لا تُعدّل فاتورةً
      // رُحِّلت. والإغلاقُ روتينٌ، بخلاف الإلغاء الذي لا معنى له بعد الدفع.
      return const [
        TableAction.addItems,
        TableAction.printBill,
        TableAction.closeTable,
        TableAction.log,
      ];
    case TableStatus.reserved:
      return const [
        TableAction.open,
        TableAction.changeStatus,
        TableAction.log,
      ];
    case TableStatus.outOfService:
      return const [TableAction.changeStatus, TableAction.log];
    default:
      return const [TableAction.log];
  }
}
