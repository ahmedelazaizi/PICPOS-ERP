import '../../core/permissions/permission_codes.dart';
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

/// كودُ الصلاحيّة الذي يحرس كلَّ فعل — أو `null` لفعلٍ لا يحتاج صلاحيّةً خاصّة.
///
/// دالّةٌ خالصةٌ بجوار [actionsForStatus] وللسبب نفسِه: كانت الحراسةُ متناثرةً
/// في الودجت، فبقيت ثلاثةُ أفعالٍ (دمجٌ وتقسيمٌ وحجز) **بلا صلاحيّةٍ إطلاقاً**
/// ولم يلاحظ أحد. وموضعان منها كانا يعيشان في `table_order_panel.dart` — وهي
/// لوحةٌ تختفي في شاشة PicPos، فكان الكساءُ يُسقط الإنفاذَ صامتاً.
///
/// و`log` وحدَه `null`: قراءةُ سجلٍّ لا تغيّر شيئاً، ودخولُ الشاشة نفسِه محروسٌ
/// بـ`tables_view`.
String? permissionForAction(TableAction action) {
  switch (action) {
    case TableAction.open:
    case TableAction.changeStatus:
    case TableAction.closeTable:
      return PermissionCodes.tablesManage;
    case TableAction.addItems:
      return PermissionCodes.tablesAddItems;
    case TableAction.pay:
      return PermissionCodes.tablesCheckout;
    case TableAction.transfer:
      return PermissionCodes.tablesTransfer;
    case TableAction.merge:
      return PermissionCodes.tablesMerge;
    case TableAction.splitBill:
      return PermissionCodes.tablesSplitBill;
    case TableAction.printBill:
      return PermissionCodes.tablesPrintBill;
    case TableAction.reserve:
      return PermissionCodes.tablesReserve;
    case TableAction.cancelOrder:
      return PermissionCodes.tablesCancel;
    case TableAction.log:
      return null;
  }
}
