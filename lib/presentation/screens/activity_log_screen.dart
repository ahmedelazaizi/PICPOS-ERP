import 'package:ural_erp/core/i18n/tr.dart';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:ural_erp/core/widgets/app_toast.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:excel/excel.dart' as xls;
import '../../core/constants/app_constants.dart';
import '../../core/theme/app_colors.dart';

import '../../data/providers/providers.dart';
import '../widgets/activity_timeline.dart';
import '../widgets/enhanced_components.dart';
import '../widgets/field_audit_history_widget.dart';

// ── Part files (mixin-based extraction) ─────────────────────────────────
part 'activity_log/activity_log_filters.dart';
part 'activity_log/activity_log_items.dart';

/// View mode for activity log display
enum ActivityViewMode { list, timeline }

/// Activity Log Screen - سجل العمليات (#14)
///
/// Displays all user activities with filtering options
/// Supports both list view and timeline view
class ActivityLogScreen extends ConsumerStatefulWidget {
  const ActivityLogScreen({super.key});

  @override
  ConsumerState<ActivityLogScreen> createState() => _ActivityLogScreenState();
}

class _ActivityLogScreenState extends ConsumerState<ActivityLogScreen>
    with _ActivityLogFiltersMixin, _ActivityLogItemsMixin {
  @override
  DateTime? fromDate;
  @override
  DateTime? toDate;
  @override
  int? selectedUserId;
  @override
  String? selectedAction;
  String? _selectedEntityType;
  @override
  List<ActivityLog> logs = [];
  bool _isLoading = true;
  ActivityViewMode _viewMode = ActivityViewMode.timeline;
  @override
  String? selectedCategory;
  @override
  String? selectedSubAction;
  @override
  int? selectedBranchId;
  /// Maps branch ID -> set of user IDs that belong to that branch
  @override
  Map<int, Set<int>> branchUserMapping = {};

  // Complete action labels — must match all logged action keys
  @override
  final Map<String, String> actionLabels = {
    'sale': tr('بيع'),
    'refund': tr('مرتجع'),
    'return': tr('مرتجع'),
    'cancel_return': tr('إلغاء مرتجع'),
    'void': tr('إلغاء فاتورة'),
    'delete_invoice': tr('حذف فاتورة'),
    'discount': tr('خصم'),
    'pos_discount': tr('خصم POS'),
    'screen_view': tr('فتح شاشة'),
    'add_product': tr('إضافة منتج'),
    'delete_product': tr('حذف منتج'),
    'product_delete': tr('حذف منتج'),
    'product_edit': tr('تعديل منتج'),
    'price_override': tr('تعديل سعر يدوي'),
    'category_add': tr('إضافة تصنيف'),
    'category_edit': tr('تعديل تصنيف'),
    'category_delete': tr('حذف تصنيف'),
    'add_customer': tr('إضافة عميل'),
    'update_customer': tr('تعديل عميل'),
    'delete_customer': tr('حذف عميل'),
    'add_supplier': tr('إضافة مورد'),
    'update_supplier': tr('تعديل مورد'),
    'delete_supplier': tr('حذف مورد'),
    'add_purchase': tr('شراء'),
    'purchase': tr('شراء'),
    'purchase_return': tr('مرتجع مشتريات'),
    'delete_purchase': tr('حذف فاتورة مشتريات'),
    'sales_return': tr('مرتجع مبيعات'),
    'update_payment': tr('تعديل دفع'),
    'expense': tr('مصروف'),
    'receipt': tr('إيصال قبض'),
    'delete_expense': tr('حذف مصروف'),
    'daily_closing': tr('إقفال يومي'),
    'safe_adjustment': tr('تسوية خزينة'),
    'login': tr('تسجيل دخول'),
    'logout': tr('تسجيل خروج'),
    'admin_elevation': tr('ترقية صلاحيات'),
    'settings_change': tr('تغيير إعداد'),
    'open_drawer': tr('فتح الدرج'),
    'cash_drawer_open': tr('فتح الدرج'),
    'cart_add': tr('إضافة للسلة'),
    'cart_remove': tr('حذف من السلة'),
    'cart_clear': tr('إفراغ السلة'),
    'hold_order': tr('تعليق طلب'),
    'order_suspend': tr('تعليق طلب'),
    'retrieve_held_order': tr('استرجاع معلق'),
    'delete_held_order': tr('حذف معلق'),
    'price_edit': tr('تعديل سعر بيع'),
    'pos_item_qty_change': tr('تغيير كمية'),
    'pos_apply_offer': tr('تطبيق عرض'),
    'request_table_bill': tr('طلب حساب طاولة'),
    'pos_delivery_set': tr('تعيين توصيل'),
    'shift_close': tr('إغلاق وردية'),
    'offer_add': tr('إضافة عرض'),
    'offer_edit': tr('تعديل عرض'),
    'offer_delete': tr('حذف عرض'),
    'offer_toggle': tr('تفعيل/تعطيل عرض'),
    'offer_print': tr('طباعة باركود عرض'),
    'stock_adjust': tr('تسوية مخزون'),
    'start_audit': tr('بدء جرد'),
    'finalize_audit': tr('اعتماد جرد'),
    'print_report': tr('طباعة تقرير'),
    'category_reorder': tr('إعادة ترتيب تصنيفات'),
    'category_upload_scale': tr('ترحيل للميزان'),
    'product_reorder': tr('إعادة ترتيب منتجات'),
    'print_return': tr('طباعة إيصال مرتجع'),
    'user_create': tr('إنشاء مستخدم'),
    'user_edit': tr('تعديل مستخدم'),
    'user_activate': tr('تفعيل مستخدم'),
    'user_deactivate': tr('تعطيل مستخدم'),
    'user_lock': tr('قفل مستخدم'),
    'user_unlock': tr('فك قفل مستخدم'),
    'user_reset_password': tr('إعادة تعيين كلمة مرور'),
    'perm_change': tr('تغيير صلاحيات'),
    'add_section': tr('إضافة قسم'),
    'update_section': tr('تعديل قسم'),
    'delete_section': tr('حذف قسم'),
    'add_table': tr('إضافة طاولة'),
    'update_table': tr('تعديل طاولة'),
    'delete_table': tr('حذف طاولة'),
    'add_reservation': tr('إضافة حجز'),
    'cancel_reservation': tr('إلغاء حجز'),
    'open_table': tr('فتح طاولة'),
    'close_table': tr('إغلاق طاولة'),
    'transfer_order': tr('نقل طلب'),
    // انتقالاتُ الطاولة التي يكتبها `TableSessionService` — أسماؤها
    // `table_*` بخلاف الثلاثة أعلاه التي كتبتها الشاشاتُ قبله وتبقى هنا
    // لأجل السطور القديمة.
    'table_open': tr('فتح طاولة'),
    'table_close': tr('إغلاق طاولة'),
    'table_order_cancel': tr('إلغاء طلب طاولة'),
    'table_status_change': tr('تغيير حالة طاولة'),
    'table_transfer': tr('نقل طلب طاولة'),
    'table_partial_transfer': tr('نقل بنودٍ من طاولة'),
    'table_merge': tr('دمج طاولات'),
    'table_discount': tr('خصم طلب طاولة'),
    'table_tax': tr('ضريبة طلب طاولة'),
    'table_print_bill': tr('طباعة فاتورة طاولة'),
    'table_payment': tr('دفعةُ طاولة'),
    'table_payment_reconcile_needed': tr('دفعةُ طاولة تحتاج تسوية'),
    'add_delivery_company': tr('إضافة شركة توصيل'),
    'update_delivery_company': tr('تعديل شركة توصيل'),
    'delete_delivery_company': tr('حذف شركة توصيل'),
    'add_courier': tr('إضافة مندوب'),
    'update_courier': tr('تعديل مندوب'),
    'delete_courier': tr('حذف مندوب'),
    'add_printer': tr('إضافة طابعة'),
    'update_printer': tr('تعديل طابعة'),
    'delete_printer': tr('حذف طابعة'),
    'add_employee': tr('إضافة موظف'),
    'update_employee': tr('تعديل موظف'),
    'employee_advance': tr('سلفة موظف'),
    'employee_deduction': tr('خصم موظف'),
    'employee_checkin': tr('تسجيل حضور'),
    'employee_checkout': tr('تسجيل انصراف'),
    'salary_payment': tr('صرف راتب'),
    'update_role_permissions': tr('تعديل صلاحيات دور'),
    'add_role': tr('إضافة دور'),
    'delete_role': tr('حذف دور'),
    'create_invoice_template': tr('إنشاء قالب فاتورة'),
    'update_invoice_template': tr('تعديل قالب فاتورة'),
    'delete_invoice_template': tr('حذف قالب فاتورة'),
    'import_invoice_template': tr('استيراد قالب فاتورة'),
    'add_branch': tr('إضافة فرع'),
    'add_warehouse': tr('إضافة مخزن'),
    'delete_branch': tr('حذف فرع'),
    'delete_warehouse': tr('حذف مخزن'),
    'export_template': tr('تصدير قالب'),
    'import_data': tr('استيراد بيانات'),
  };

  // Category-to-actions mapping for quick filters
  @override
  Map<String, List<String>> get categoryActionsMap => _categoryActions;

  static const Map<String, List<String>> _categoryActions = {
    'items': [
      'add_product', 'delete_product', 'product_delete', 'product_edit',
      'price_override', 'category_add', 'category_edit', 'category_delete',
      'category_reorder', 'category_upload_scale', 'product_reorder',
    ],
    'sales': [
      'sale', 'refund', 'return', 'cancel_return', 'void', 'delete_invoice',
      'discount', 'pos_discount', 'sales_return', 'update_payment', 'print_return',
    ],
    'purchases': ['add_purchase', 'purchase', 'purchase_return', 'delete_purchase'],
    'treasury': ['expense', 'receipt', 'delete_expense', 'daily_closing', 'safe_adjustment'],
    'customers': ['add_customer', 'update_customer', 'delete_customer', 'export_template', 'import_data'],
    'suppliers': ['add_supplier', 'update_supplier', 'delete_supplier', 'export_template', 'import_data'],
    'navigation': ['screen_view'],
    'pos': [
      'sale', 'pos_discount', 'cart_add', 'cart_remove', 'cart_clear',
      'pos_item_qty_change', 'hold_order', 'order_suspend', 'retrieve_held_order',
      'delete_held_order', 'open_drawer', 'cash_drawer_open', 'price_edit',
      'shift_close', 'pos_apply_offer', 'pos_delivery_set',
      'pos_search', 'pos_barcode_scan', 'pos_add_product', 'pos_quick_pay',
      'pos_item_plus', 'pos_item_minus',
    ],
    'table_pos': [
      'open_table', 'close_table', 'transfer_order', 'request_table_bill',
      'table_open', 'table_close', 'table_transfer', 'table_print_bill',
      'table_tax', 'table_payment', 'table_payment_reconcile_needed',
      'sale', 'cart_add', 'cart_remove', 'cart_clear', 'pos_item_qty_change',
      'hold_order', 'retrieve_held_order', 'delete_held_order',
    ],
    'offers': ['offer_add', 'offer_edit', 'offer_delete', 'offer_toggle', 'offer_print'],
    'inventory': ['stock_adjust', 'start_audit', 'finalize_audit', 'print_report'],
    'settings': ['settings_change'],
    'auth': ['login', 'logout', 'admin_elevation'],
    'users': [
      'user_create', 'user_edit', 'user_activate', 'user_deactivate',
      'user_lock', 'user_unlock', 'user_reset_password', 'perm_change',
    ],
    'tables': [
      'add_section', 'update_section', 'delete_section',
      'add_table', 'update_table', 'delete_table',
      // `add_reservation` هو الاسمُ القديمُ لحجزِ الطاولة — صفوفٌ حقيقيّةٌ في
      // قاعدة المالك مسجَّلةٌ به، فيبقى في القائمة ولا يُحذَف (حذفُه يُخفي
      // تاريخاً حقيقيّاً). `table_reserve` هو الاسمُ الذي تكتبه
      // `TableSessionService.reserveTable` منذ سدِّ ثغرة السجلّ (2026-08-20)
      // — بلا هذا السطر تختفي كلُّ حجوزات الطاولة الجديدة من تصفية
      // «الطاولات» هنا رغم ظهورها في سجلّ الطاولة الواحدة.
      'add_reservation', 'table_reserve', 'cancel_reservation', 'open_table',
      'close_table', 'transfer_order',
      'table_open', 'table_close', 'table_order_cancel', 'table_status_change',
      'table_transfer', 'table_partial_transfer', 'table_merge',
      'table_discount', 'table_tax', 'table_print_bill', 'table_payment',
      'table_payment_reconcile_needed',
    ],
    // الحجوزات — مواعيدُ الخدمة. أفعالُها منفصلةٌ عن أفعال الطاولات لأنّ
    // الجدولين منفصلان: ذاك يحجز مكاناً وهذا يحجز وقتَ إنسان.
    'bookings': [
      'booking_create', 'booking_reassign', 'booking_reschedule',
      'booking_cancel', 'booking_status',
    ],
    'delivery': [
      'add_delivery_company', 'update_delivery_company', 'delete_delivery_company',
      'add_courier', 'update_courier', 'delete_courier',
    ],
    'printers': ['add_printer', 'update_printer', 'delete_printer'],
    'hr': [
      'add_employee', 'update_employee', 'employee_advance', 'employee_deduction',
      'employee_checkin', 'employee_checkout', 'salary_payment',
    ],
    'roles': ['update_role_permissions', 'add_role', 'delete_role'],
    'invoice_design': [
      'create_invoice_template', 'update_invoice_template',
      'delete_invoice_template', 'import_invoice_template',
    ],
    'branches': ['add_branch', 'add_warehouse', 'delete_branch', 'delete_warehouse'],
  };

  // Sub-action labels (Arabic) for each category
  @override
  Map<String, Map<String, String>> get subActionLabelsMap => _subActionLabels;

  static Map<String, Map<String, String>> get _subActionLabels => {
    'items': {
      'add_product': tr('إضافة منتج'), 'delete_product': tr('حذف منتج'),
      'product_delete': tr('حذف (Logger)'), 'product_edit': tr('تعديل منتج'),
      'price_override': tr('تعديل سعر يدوي'), 'category_add': tr('إضافة تصنيف'),
      'category_edit': tr('تعديل تصنيف'), 'category_delete': tr('حذف تصنيف'),
      'category_reorder': tr('ترتيب تصنيفات'), 'category_upload_scale': tr('ترحيل للميزان'),
      'product_reorder': tr('ترتيب منتجات'),
    },
    'sales': {
      'sale': tr('فواتير بيع'), 'refund': tr('مرتجعات'), 'return': tr('مرتجعات (Logger)'),
      'sales_return': tr('مرتجعات مبيعات'), 'cancel_return': tr('إلغاء مرتجع'),
      'print_return': tr('طباعة إيصال مرتجع'), 'void': tr('إلغاء فاتورة'),
      'delete_invoice': tr('حذف فاتورة'), 'update_payment': tr('تعديل دفع'),
      'discount': tr('خصم'), 'pos_discount': tr('خصم POS'),
    },
    'purchases': {
      'add_purchase': tr('فواتير شراء'), 'purchase': tr('فاتورة شراء'),
      'purchase_return': tr('مرتجع مشتريات'), 'delete_purchase': tr('حذف فاتورة'),
    },
    'treasury': {
      'expense': tr('مصروفات'), 'receipt': tr('إيصالات قبض'),
      'delete_expense': tr('حذف مصروف'), 'daily_closing': tr('إقفال يومي'),
      'safe_adjustment': tr('تسوية خزينة'),
    },
    'customers': {
      'add_customer': tr('إضافة'), 'update_customer': tr('تعديل'),
      'delete_customer': tr('حذف'), 'export_template': tr('تصدير قالب'),
      'import_data': tr('استيراد بيانات'),
    },
    'suppliers': {
      'add_supplier': tr('إضافة'), 'update_supplier': tr('تعديل'),
      'delete_supplier': tr('حذف'), 'export_template': tr('تصدير قالب'),
      'import_data': tr('استيراد بيانات'),
    },
    'pos': {
      'sale': tr('فواتير بيع POS'), 'pos_discount': tr('خصم POS'),
      'cart_add': tr('إضافة للسلة'), 'cart_remove': tr('حذف من السلة'),
      'cart_clear': tr('إفراغ السلة'), 'hold_order': tr('تعليق طلب'),
      'order_suspend': tr('تعليق (إيقاف)'), 'retrieve_held_order': tr('استرجاع معلق'),
      'delete_held_order': tr('حذف معلق'), 'open_drawer': tr('فتح الدرج'),
      'cash_drawer_open': tr('فتح الدرج (Logger)'), 'price_edit': tr('تعديل سعر'),
      'pos_item_qty_change': tr('تغيير كمية'), 'shift_close': tr('إغلاق وردية'),
      'pos_apply_offer': tr('تطبيق عرض'), 'request_table_bill': tr('طلب حساب طاولة'),
      'pos_delivery_set': tr('تعيين توصيل'), 'pos_search': tr('بحث أصناف'),
      'pos_barcode_scan': tr('مسح باركود'), 'pos_add_product': tr('إضافة صنف'),
      'pos_quick_pay': tr('دفع سريع'), 'pos_item_plus': tr('زيادة كمية'),
      'pos_item_minus': tr('نقص كمية'),
    },
    'table_pos': {
      'open_table': tr('فتح طاولة'), 'close_table': tr('إغلاق طاولة'),
      'transfer_order': tr('نقل طلب'), 'request_table_bill': tr('طلب حساب'),
      'table_open': tr('فتح طاولة'), 'table_close': tr('إغلاق طاولة'),
      'table_transfer': tr('نقل طلب'), 'table_print_bill': tr('طباعة فاتورة'),
      'table_tax': tr('ضريبة طلب'), 'table_payment': tr('دفعةُ طاولة'),
      'table_payment_reconcile_needed': tr('دفعةٌ تحتاج تسوية'),
      'sale': tr('فواتير بيع'), 'cart_add': tr('إضافة للسلة'),
      'cart_remove': tr('حذف من السلة'), 'cart_clear': tr('إفراغ السلة'),
      'pos_item_qty_change': tr('تغيير كمية'), 'hold_order': tr('تعليق طلب'),
      'retrieve_held_order': tr('استرجاع معلق'), 'delete_held_order': tr('حذف معلق'),
    },
    'navigation': {'screen_view': tr('زيارة شاشة')},
    'offers': {
      'offer_add': tr('إضافة'), 'offer_edit': tr('تعديل'), 'offer_delete': tr('حذف'),
      'offer_toggle': tr('تفعيل/تعطيل'), 'offer_print': tr('طباعة باركود'),
    },
    'inventory': {
      'stock_adjust': tr('تسوية مخزون'), 'start_audit': tr('بدء جرد'),
      'finalize_audit': tr('اعتماد جرد'), 'print_report': tr('طباعة تقرير'),
    },
    'settings': {'settings_change': tr('تغيير إعداد')},
    'auth': {
      'login': tr('تسجيل دخول'), 'logout': tr('تسجيل خروج'),
      'admin_elevation': tr('ترقية صلاحيات'),
    },
    'users': {
      'user_create': tr('إنشاء'), 'user_edit': tr('تعديل'),
      'user_activate': tr('تفعيل'), 'user_deactivate': tr('تعطيل'),
      'user_lock': tr('قفل'), 'user_unlock': tr('فك قفل'),
      'user_reset_password': tr('إعادة تعيين كلمة مرور'), 'perm_change': tr('تغيير صلاحيات'),
    },
    'tables': {
      'add_section': tr('إضافة قسم'), 'update_section': tr('تعديل قسم'),
      'delete_section': tr('حذف قسم'), 'add_table': tr('إضافة طاولة'),
      'update_table': tr('تعديل طاولة'), 'delete_table': tr('حذف طاولة'),
      'add_reservation': tr('حجز'), 'cancel_reservation': tr('إلغاء حجز'),
      'open_table': tr('فتح طاولة'), 'close_table': tr('إغلاق طاولة'),
      'transfer_order': tr('نقل طلب'),
      'table_open': tr('فتح طاولة'), 'table_close': tr('إغلاق طاولة'),
      'table_order_cancel': tr('إلغاء طلب'), 'table_status_change': tr('تغيير حالة'),
      'table_transfer': tr('نقل طلب'), 'table_partial_transfer': tr('نقل بنود'),
      'table_merge': tr('دمج طاولات'), 'table_discount': tr('خصم طلب'),
      'table_tax': tr('ضريبة طلب'),
      'table_print_bill': tr('طباعة فاتورة'), 'table_payment': tr('دفعة'),
      'table_payment_reconcile_needed': tr('دفعةٌ تحتاج تسوية'),
    },
    'delivery': {
      'add_delivery_company': tr('إضافة شركة'), 'update_delivery_company': tr('تعديل شركة'),
      'delete_delivery_company': tr('حذف شركة'), 'add_courier': tr('إضافة مندوب'),
      'update_courier': tr('تعديل مندوب'), 'delete_courier': tr('حذف مندوب'),
    },
    'printers': {'add_printer': tr('إضافة'), 'update_printer': tr('تعديل'), 'delete_printer': tr('حذف')},
    'hr': {
      'add_employee': tr('إضافة موظف'), 'update_employee': tr('تعديل موظف'),
      'employee_advance': tr('سلفة'), 'employee_deduction': tr('خصم'),
      'employee_checkin': tr('حضور'), 'employee_checkout': tr('انصراف'),
      'salary_payment': tr('صرف راتب'),
    },
    'roles': {
      'update_role_permissions': tr('تعديل صلاحيات'), 'add_role': tr('إضافة'),
      'delete_role': tr('حذف'),
    },
    'invoice_design': {
      'create_invoice_template': tr('إنشاء'), 'update_invoice_template': tr('تعديل'),
      'delete_invoice_template': tr('حذف'), 'import_invoice_template': tr('استيراد'),
    },
    'branches': {
      'add_branch': tr('إضافة فرع'), 'add_warehouse': tr('إضافة مخزن'),
      'delete_branch': tr('حذف فرع'), 'delete_warehouse': tr('حذف مخزن'),
    },
  };

  @override
  final Map<String, String> entityLabels = {
    'invoice': tr('فاتورة'), 'product': tr('منتج'), 'customer': tr('عميل'),
    'supplier': tr('مورد'), 'payment': tr('دفعة'), 'setting': tr('إعداد'),
    'user': tr('مستخدم'), 'purchase': tr('مشتريات'), 'purchase_invoice': tr('فاتورة مشتريات'),
    'cart': tr('سلة'), 'order': tr('طلب'), 'drawer': tr('درج'),
    'treasury': tr('خزينة'), 'session': tr('جلسة'), 'return': tr('مرتجع'),
    'held_order': tr('طلب معلق'), 'category': tr('تصنيف'), 'offer': tr('عرض'),
    'stock': tr('مخزون'), 'shift': tr('وردية'), 'delivery': tr('توصيل'),
    'role': tr('دور'), 'table_section': tr('قسم طاولات'), 'restaurant_table': tr('طاولة'),
    'reservation': tr('حجز'), 'delivery_company': tr('شركة توصيل'), 'courier': tr('مندوب'),
    'printer': tr('طابعة'), 'employee': tr('موظف'), 'invoice_template': tr('قالب فاتورة'),
    'table': tr('طاولة'), 'branch': tr('فرع'), 'warehouse': tr('مخزن'),
    'party': tr('طرف'), 'settings': tr('إعدادات'),
  };

  @override
  void initState() {
    super.initState();
    toDate = DateTime.now();
    fromDate = toDate!.subtract(const Duration(days: 7));
    _bootstrap();
  }

  /// Issue 18: load the branch→users mapping BEFORE the first loadLogs so
  /// the branch filter can apply on the very first render. The previous
  /// code called both in parallel, so any user changing the branch
  /// dropdown before the mapping completed would see the filter silently
  /// skipped (`branchUserMapping.containsKey(...) == false` → no rows
  /// removed) and conclude the filter was broken.
  Future<void> _bootstrap() async {
    await _loadBranchUserMapping();
    if (mounted) await loadLogs();
  }

  /// Load branch -> user mapping for client-side branch filtering.
  ///
  /// activity_logs doesn't carry a branch_id column (TODO: bundle into
  /// the next schema migration so we can filter at SQL level). Until
  /// then we approximate the filter as "users assigned to this branch
  /// via user_branch_access". An admin / financial-manager / user with
  /// `getUserAccessibleBranchIds == []` (full access) is intentionally
  /// EXCLUDED from per-branch sets — including them stuck their logs
  /// in every filter and made branch selection look like it did nothing
  /// for any setup with an active admin user.
  Future<void> _loadBranchUserMapping() async {
    try {
      // ISS-06: Route through branchRepositoryProvider instead of direct DB access
      final branchRepo = ref.read(branchRepositoryProvider);
      final branches = await branchRepo.getBranches();
      final mapping = <int, Set<int>>{};
      final users = ref.read(allUsersProvider).value ?? [];
      for (final branch in branches) {
        final userIds = <int>{};
        for (final uw in users) {
          final accessIds = await branchRepo.getUserAccessibleBranchIds(uw.user.id);
          // Issue 18: skip full-access users so branch filter actually narrows.
          // They show up under "all branches" via the unfiltered view.
          if (accessIds.contains(branch.id)) {
            userIds.add(uw.user.id);
          }
        }
        mapping[branch.id] = userIds;
      }
      if (mounted) {
        setState(() => branchUserMapping = mapping);
      }
    } catch (e) {
      debugPrint('[ActivityLog] Error loading branch mapping: $e');
    }
  }

  DateTime _endOfDay(DateTime date) {
    return DateTime(date.year, date.month, date.day, 23, 59, 59, 999);
  }

  DateTime _startOfDay(DateTime date) {
    return DateTime(date.year, date.month, date.day);
  }

  @override
  Future<void> loadLogs() async {
    setState(() => _isLoading = true);

    try {
      final db = ref.read(activityLogRepositoryProvider);
      final effectiveFrom = fromDate != null ? _startOfDay(fromDate!) : null;
      final effectiveTo = toDate != null ? _endOfDay(toDate!) : null;

      // v138 (Issue 18 cleanup): branch filter now hits the activity_logs
      // table directly via the new branch_id column. The old client-side
      // approximation via user_branch_access is gone — it misclassified
      // users moved between branches and showed empty results when the
      // mapping hadn't loaded yet.
      List<ActivityLog> result;
      if (selectedCategory != null &&
          _categoryActions.containsKey(selectedCategory)) {
        if (selectedSubAction != null) {
          result = (await db.getActivityLogs(
            fromDate: effectiveFrom, toDate: effectiveTo,
            userId: selectedUserId, action: selectedSubAction,
            entityType: _selectedEntityType, branchId: selectedBranchId,
            limit: 500,
          )).cast<ActivityLog>();
        } else {
          final actions = _categoryActions[selectedCategory]!;
          result = [];
          for (final action in actions) {
            final actionLogs = (await db.getActivityLogs(
              fromDate: effectiveFrom, toDate: effectiveTo,
              userId: selectedUserId, action: action,
              entityType: _selectedEntityType, branchId: selectedBranchId,
              limit: 500,
            )).cast<ActivityLog>();
            result.addAll(actionLogs);
          }
          result.sort((a, b) => b.createdAt.compareTo(a.createdAt));
        }
      } else {
        result = (await db.getActivityLogs(
          fromDate: effectiveFrom, toDate: effectiveTo,
          userId: selectedUserId, action: selectedAction,
          entityType: _selectedEntityType, branchId: selectedBranchId,
          limit: 500,
        )).cast<ActivityLog>();
      }

      if (mounted) {
        setState(() { logs = result; _isLoading = false; });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        AppToast.show(context, tr('خطأ في تحميل السجل: {e}', {'e': e}), type: ToastType.error);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          title:  Text(tr('سجل العمليات')),
          actions: [
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 8),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  buildViewToggleButton(
                    icon: PhosphorIconsBold.list,
                    isSelected: _viewMode == ActivityViewMode.list,
                    label: tr('قائمة'),
                    onTap: () =>
                        setState(() => _viewMode = ActivityViewMode.list),
                  ),
                  buildViewToggleButton(
                    icon: PhosphorIconsBold.clockCounterClockwise,
                    isSelected: _viewMode == ActivityViewMode.timeline,
                    label: tr('زمني'),
                    onTap: () =>
                        setState(() => _viewMode = ActivityViewMode.timeline),
                  ),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(PhosphorIconsBold.microsoftExcelLogo),
              onPressed: logs.isEmpty ? null : exportToExcel,
              tooltip: tr('تصدير إلى Excel'),
            ),
            IconButton(
              icon: const Icon(PhosphorIconsBold.arrowClockwise),
              onPressed: loadLogs,
              tooltip: tr('تحديث'),
            ),
          ],
        ),
        body: Column(
          children: [
            buildFiltersBar(),
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _viewMode == ActivityViewMode.timeline
                  ? ActivityTimeline(
                      logs: logs,
                      onTap: showLogDetails,
                      actionLabels: actionLabels,
                      entityLabels: entityLabels,
                    )
                  : logs.isEmpty
                  ?  EmptyStateWidget(
                      icon: PhosphorIconsBold.clipboardText,
                      message: tr('لا توجد عمليات مسجلة'),
                    )
                  : ListView.builder(
                      itemCount: logs.length,
                      itemBuilder: (context, index) =>
                          buildLogItem(logs[index]),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
