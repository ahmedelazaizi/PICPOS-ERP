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
    'sale': 'بيع',
    'refund': 'مرتجع',
    'return': 'مرتجع',
    'cancel_return': 'إلغاء مرتجع',
    'void': 'إلغاء فاتورة',
    'delete_invoice': 'حذف فاتورة',
    'discount': 'خصم',
    'pos_discount': 'خصم POS',
    'screen_view': 'فتح شاشة',
    'add_product': 'إضافة منتج',
    'delete_product': 'حذف منتج',
    'product_delete': 'حذف منتج',
    'product_edit': 'تعديل منتج',
    'price_override': 'تعديل سعر يدوي',
    'category_add': 'إضافة تصنيف',
    'category_edit': 'تعديل تصنيف',
    'category_delete': 'حذف تصنيف',
    'add_customer': 'إضافة عميل',
    'update_customer': 'تعديل عميل',
    'delete_customer': 'حذف عميل',
    'add_supplier': 'إضافة مورد',
    'update_supplier': 'تعديل مورد',
    'delete_supplier': 'حذف مورد',
    'add_purchase': 'شراء',
    'purchase': 'شراء',
    'purchase_return': 'مرتجع مشتريات',
    'delete_purchase': 'حذف فاتورة مشتريات',
    'sales_return': 'مرتجع مبيعات',
    'update_payment': 'تعديل دفع',
    'expense': 'مصروف',
    'receipt': 'إيصال قبض',
    'delete_expense': 'حذف مصروف',
    'daily_closing': 'إقفال يومي',
    'safe_adjustment': 'تسوية خزينة',
    'login': 'تسجيل دخول',
    'logout': 'تسجيل خروج',
    'admin_elevation': 'ترقية صلاحيات',
    'settings_change': 'تغيير إعداد',
    'open_drawer': 'فتح الدرج',
    'cash_drawer_open': 'فتح الدرج',
    'cart_add': 'إضافة للسلة',
    'cart_remove': 'حذف من السلة',
    'cart_clear': 'إفراغ السلة',
    'hold_order': 'تعليق طلب',
    'order_suspend': 'تعليق طلب',
    'retrieve_held_order': 'استرجاع معلق',
    'delete_held_order': 'حذف معلق',
    'price_edit': 'تعديل سعر بيع',
    'pos_item_qty_change': 'تغيير كمية',
    'pos_apply_offer': 'تطبيق عرض',
    'request_table_bill': 'طلب حساب طاولة',
    'pos_delivery_set': 'تعيين توصيل',
    'shift_close': 'إغلاق وردية',
    'offer_add': 'إضافة عرض',
    'offer_edit': 'تعديل عرض',
    'offer_delete': 'حذف عرض',
    'offer_toggle': 'تفعيل/تعطيل عرض',
    'offer_print': 'طباعة باركود عرض',
    'stock_adjust': 'تسوية مخزون',
    'start_audit': 'بدء جرد',
    'finalize_audit': 'اعتماد جرد',
    'print_report': 'طباعة تقرير',
    'category_reorder': 'إعادة ترتيب تصنيفات',
    'category_upload_scale': 'ترحيل للميزان',
    'product_reorder': 'إعادة ترتيب منتجات',
    'print_return': 'طباعة إيصال مرتجع',
    'user_create': 'إنشاء مستخدم',
    'user_edit': 'تعديل مستخدم',
    'user_activate': 'تفعيل مستخدم',
    'user_deactivate': 'تعطيل مستخدم',
    'user_lock': 'قفل مستخدم',
    'user_unlock': 'فك قفل مستخدم',
    'user_reset_password': 'إعادة تعيين كلمة مرور',
    'perm_change': 'تغيير صلاحيات',
    'add_section': 'إضافة قسم',
    'update_section': 'تعديل قسم',
    'delete_section': 'حذف قسم',
    'add_table': 'إضافة طاولة',
    'update_table': 'تعديل طاولة',
    'delete_table': 'حذف طاولة',
    'add_reservation': 'إضافة حجز',
    'cancel_reservation': 'إلغاء حجز',
    'open_table': 'فتح طاولة',
    'close_table': 'إغلاق طاولة',
    'transfer_order': 'نقل طلب',
    // انتقالاتُ الطاولة التي يكتبها `TableSessionService` — أسماؤها
    // `table_*` بخلاف الثلاثة أعلاه التي كتبتها الشاشاتُ قبله وتبقى هنا
    // لأجل السطور القديمة.
    'table_open': 'فتح طاولة',
    'table_close': 'إغلاق طاولة',
    'table_order_cancel': 'إلغاء طلب طاولة',
    'table_status_change': 'تغيير حالة طاولة',
    'table_transfer': 'نقل طلب طاولة',
    'table_partial_transfer': 'نقل بنودٍ من طاولة',
    'table_merge': 'دمج طاولات',
    'table_discount': 'خصم طلب طاولة',
    'table_print_bill': 'طباعة فاتورة طاولة',
    'table_payment': 'دفعةُ طاولة',
    'table_payment_reconcile_needed': 'دفعةُ طاولة تحتاج تسوية',
    'add_delivery_company': 'إضافة شركة توصيل',
    'update_delivery_company': 'تعديل شركة توصيل',
    'delete_delivery_company': 'حذف شركة توصيل',
    'add_courier': 'إضافة مندوب',
    'update_courier': 'تعديل مندوب',
    'delete_courier': 'حذف مندوب',
    'add_printer': 'إضافة طابعة',
    'update_printer': 'تعديل طابعة',
    'delete_printer': 'حذف طابعة',
    'add_employee': 'إضافة موظف',
    'update_employee': 'تعديل موظف',
    'employee_advance': 'سلفة موظف',
    'employee_deduction': 'خصم موظف',
    'employee_checkin': 'تسجيل حضور',
    'employee_checkout': 'تسجيل انصراف',
    'salary_payment': 'صرف راتب',
    'update_role_permissions': 'تعديل صلاحيات دور',
    'add_role': 'إضافة دور',
    'delete_role': 'حذف دور',
    'create_invoice_template': 'إنشاء قالب فاتورة',
    'update_invoice_template': 'تعديل قالب فاتورة',
    'delete_invoice_template': 'حذف قالب فاتورة',
    'import_invoice_template': 'استيراد قالب فاتورة',
    'add_branch': 'إضافة فرع',
    'add_warehouse': 'إضافة مخزن',
    'delete_branch': 'حذف فرع',
    'delete_warehouse': 'حذف مخزن',
    'export_template': 'تصدير قالب',
    'import_data': 'استيراد بيانات',
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
      'table_payment', 'table_payment_reconcile_needed',
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
      'add_reservation', 'cancel_reservation', 'open_table', 'close_table', 'transfer_order',
      'table_open', 'table_close', 'table_order_cancel', 'table_status_change',
      'table_transfer', 'table_partial_transfer', 'table_merge',
      'table_discount', 'table_print_bill', 'table_payment',
      'table_payment_reconcile_needed',
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

  static const Map<String, Map<String, String>> _subActionLabels = {
    'items': {
      'add_product': 'إضافة منتج', 'delete_product': 'حذف منتج',
      'product_delete': 'حذف (Logger)', 'product_edit': 'تعديل منتج',
      'price_override': 'تعديل سعر يدوي', 'category_add': 'إضافة تصنيف',
      'category_edit': 'تعديل تصنيف', 'category_delete': 'حذف تصنيف',
      'category_reorder': 'ترتيب تصنيفات', 'category_upload_scale': 'ترحيل للميزان',
      'product_reorder': 'ترتيب منتجات',
    },
    'sales': {
      'sale': 'فواتير بيع', 'refund': 'مرتجعات', 'return': 'مرتجعات (Logger)',
      'sales_return': 'مرتجعات مبيعات', 'cancel_return': 'إلغاء مرتجع',
      'print_return': 'طباعة إيصال مرتجع', 'void': 'إلغاء فاتورة',
      'delete_invoice': 'حذف فاتورة', 'update_payment': 'تعديل دفع',
      'discount': 'خصم', 'pos_discount': 'خصم POS',
    },
    'purchases': {
      'add_purchase': 'فواتير شراء', 'purchase': 'فاتورة شراء',
      'purchase_return': 'مرتجع مشتريات', 'delete_purchase': 'حذف فاتورة',
    },
    'treasury': {
      'expense': 'مصروفات', 'receipt': 'إيصالات قبض',
      'delete_expense': 'حذف مصروف', 'daily_closing': 'إقفال يومي',
      'safe_adjustment': 'تسوية خزينة',
    },
    'customers': {
      'add_customer': 'إضافة', 'update_customer': 'تعديل',
      'delete_customer': 'حذف', 'export_template': 'تصدير قالب',
      'import_data': 'استيراد بيانات',
    },
    'suppliers': {
      'add_supplier': 'إضافة', 'update_supplier': 'تعديل',
      'delete_supplier': 'حذف', 'export_template': 'تصدير قالب',
      'import_data': 'استيراد بيانات',
    },
    'pos': {
      'sale': 'فواتير بيع POS', 'pos_discount': 'خصم POS',
      'cart_add': 'إضافة للسلة', 'cart_remove': 'حذف من السلة',
      'cart_clear': 'إفراغ السلة', 'hold_order': 'تعليق طلب',
      'order_suspend': 'تعليق (إيقاف)', 'retrieve_held_order': 'استرجاع معلق',
      'delete_held_order': 'حذف معلق', 'open_drawer': 'فتح الدرج',
      'cash_drawer_open': 'فتح الدرج (Logger)', 'price_edit': 'تعديل سعر',
      'pos_item_qty_change': 'تغيير كمية', 'shift_close': 'إغلاق وردية',
      'pos_apply_offer': 'تطبيق عرض', 'request_table_bill': 'طلب حساب طاولة',
      'pos_delivery_set': 'تعيين توصيل', 'pos_search': 'بحث أصناف',
      'pos_barcode_scan': 'مسح باركود', 'pos_add_product': 'إضافة صنف',
      'pos_quick_pay': 'دفع سريع', 'pos_item_plus': 'زيادة كمية',
      'pos_item_minus': 'نقص كمية',
    },
    'table_pos': {
      'open_table': 'فتح طاولة', 'close_table': 'إغلاق طاولة',
      'transfer_order': 'نقل طلب', 'request_table_bill': 'طلب حساب',
      'table_open': 'فتح طاولة', 'table_close': 'إغلاق طاولة',
      'table_transfer': 'نقل طلب', 'table_print_bill': 'طباعة فاتورة',
      'table_payment': 'دفعةُ طاولة',
      'table_payment_reconcile_needed': 'دفعةٌ تحتاج تسوية',
      'sale': 'فواتير بيع', 'cart_add': 'إضافة للسلة',
      'cart_remove': 'حذف من السلة', 'cart_clear': 'إفراغ السلة',
      'pos_item_qty_change': 'تغيير كمية', 'hold_order': 'تعليق طلب',
      'retrieve_held_order': 'استرجاع معلق', 'delete_held_order': 'حذف معلق',
    },
    'navigation': {'screen_view': 'زيارة شاشة'},
    'offers': {
      'offer_add': 'إضافة', 'offer_edit': 'تعديل', 'offer_delete': 'حذف',
      'offer_toggle': 'تفعيل/تعطيل', 'offer_print': 'طباعة باركود',
    },
    'inventory': {
      'stock_adjust': 'تسوية مخزون', 'start_audit': 'بدء جرد',
      'finalize_audit': 'اعتماد جرد', 'print_report': 'طباعة تقرير',
    },
    'settings': {'settings_change': 'تغيير إعداد'},
    'auth': {
      'login': 'تسجيل دخول', 'logout': 'تسجيل خروج',
      'admin_elevation': 'ترقية صلاحيات',
    },
    'users': {
      'user_create': 'إنشاء', 'user_edit': 'تعديل',
      'user_activate': 'تفعيل', 'user_deactivate': 'تعطيل',
      'user_lock': 'قفل', 'user_unlock': 'فك قفل',
      'user_reset_password': 'إعادة تعيين كلمة مرور', 'perm_change': 'تغيير صلاحيات',
    },
    'tables': {
      'add_section': 'إضافة قسم', 'update_section': 'تعديل قسم',
      'delete_section': 'حذف قسم', 'add_table': 'إضافة طاولة',
      'update_table': 'تعديل طاولة', 'delete_table': 'حذف طاولة',
      'add_reservation': 'حجز', 'cancel_reservation': 'إلغاء حجز',
      'open_table': 'فتح طاولة', 'close_table': 'إغلاق طاولة',
      'transfer_order': 'نقل طلب',
      'table_open': 'فتح طاولة', 'table_close': 'إغلاق طاولة',
      'table_order_cancel': 'إلغاء طلب', 'table_status_change': 'تغيير حالة',
      'table_transfer': 'نقل طلب', 'table_partial_transfer': 'نقل بنود',
      'table_merge': 'دمج طاولات', 'table_discount': 'خصم طلب',
      'table_print_bill': 'طباعة فاتورة', 'table_payment': 'دفعة',
      'table_payment_reconcile_needed': 'دفعةٌ تحتاج تسوية',
    },
    'delivery': {
      'add_delivery_company': 'إضافة شركة', 'update_delivery_company': 'تعديل شركة',
      'delete_delivery_company': 'حذف شركة', 'add_courier': 'إضافة مندوب',
      'update_courier': 'تعديل مندوب', 'delete_courier': 'حذف مندوب',
    },
    'printers': {'add_printer': 'إضافة', 'update_printer': 'تعديل', 'delete_printer': 'حذف'},
    'hr': {
      'add_employee': 'إضافة موظف', 'update_employee': 'تعديل موظف',
      'employee_advance': 'سلفة', 'employee_deduction': 'خصم',
      'employee_checkin': 'حضور', 'employee_checkout': 'انصراف',
      'salary_payment': 'صرف راتب',
    },
    'roles': {
      'update_role_permissions': 'تعديل صلاحيات', 'add_role': 'إضافة',
      'delete_role': 'حذف',
    },
    'invoice_design': {
      'create_invoice_template': 'إنشاء', 'update_invoice_template': 'تعديل',
      'delete_invoice_template': 'حذف', 'import_invoice_template': 'استيراد',
    },
    'branches': {
      'add_branch': 'إضافة فرع', 'add_warehouse': 'إضافة مخزن',
      'delete_branch': 'حذف فرع', 'delete_warehouse': 'حذف مخزن',
    },
  };

  @override
  final Map<String, String> entityLabels = {
    'invoice': 'فاتورة', 'product': 'منتج', 'customer': 'عميل',
    'supplier': 'مورد', 'payment': 'دفعة', 'setting': 'إعداد',
    'user': 'مستخدم', 'purchase': 'مشتريات', 'purchase_invoice': 'فاتورة مشتريات',
    'cart': 'سلة', 'order': 'طلب', 'drawer': 'درج',
    'treasury': 'خزينة', 'session': 'جلسة', 'return': 'مرتجع',
    'held_order': 'طلب معلق', 'category': 'تصنيف', 'offer': 'عرض',
    'stock': 'مخزون', 'shift': 'وردية', 'delivery': 'توصيل',
    'role': 'دور', 'table_section': 'قسم طاولات', 'restaurant_table': 'طاولة',
    'reservation': 'حجز', 'delivery_company': 'شركة توصيل', 'courier': 'مندوب',
    'printer': 'طابعة', 'employee': 'موظف', 'invoice_template': 'قالب فاتورة',
    'table': 'طاولة', 'branch': 'فرع', 'warehouse': 'مخزن',
    'party': 'طرف', 'settings': 'إعدادات',
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
        AppToast.show(context, 'خطأ في تحميل السجل: $e', type: ToastType.error);
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
          title: const Text('سجل العمليات'),
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
                    label: 'قائمة',
                    onTap: () =>
                        setState(() => _viewMode = ActivityViewMode.list),
                  ),
                  buildViewToggleButton(
                    icon: PhosphorIconsBold.clockCounterClockwise,
                    isSelected: _viewMode == ActivityViewMode.timeline,
                    label: 'زمني',
                    onTap: () =>
                        setState(() => _viewMode = ActivityViewMode.timeline),
                  ),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(PhosphorIconsBold.microsoftExcelLogo),
              onPressed: logs.isEmpty ? null : exportToExcel,
              tooltip: 'تصدير إلى Excel',
            ),
            IconButton(
              icon: const Icon(PhosphorIconsBold.arrowClockwise),
              onPressed: loadLogs,
              tooltip: 'تحديث',
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
                  ? const EmptyStateWidget(
                      icon: PhosphorIconsBold.clipboardText,
                      message: 'لا توجد عمليات مسجلة',
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
