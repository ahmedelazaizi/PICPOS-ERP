// ═══════════════════════════════════════════════════════════════════════════
// U-17: Role-Based Sidebar Visibility Filter Service
// Filters navigation items based on user's permission codes
// ═══════════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

/// Represents a navigation menu section
class NavSection {
  final String id;
  final String label;
  final IconData icon;
  final List<NavItem> items;
  final String? requiredPermission; // If set, entire section requires this permission

  const NavSection({
    required this.id,
    required this.label,
    required this.icon,
    required this.items,
    this.requiredPermission,
  });
}

/// Represents a single navigation item
class NavItem {
  final String id;
  final String label;
  final IconData icon;
  final String routeName;
  final String? requiredPermission; // Permission code needed to see this item
  final List<String>? anyOfPermissions; // Show if user has ANY of these

  const NavItem({
    required this.id,
    required this.label,
    required this.icon,
    required this.routeName,
    this.requiredPermission,
    this.anyOfPermissions,
  });
}

/// Service to filter navigation items by user's permissions
class RoleBasedSidebarService {
  /// Full navigation map grouped by role archetype
  static const _roleProfiles = {
    'cashier': [
      'pos', 'treasury', 'returns', 'customers',
    ],
    'accountant': [
      'accounting', 'reports', 'journal_entries', 'fiscal_years',
      'treasury', 'parties', 'cost_centers', 'bank_reconciliation',
    ],
    'inventory_manager': [
      'products', 'warehouses', 'stock_movements', 'cycle_count',
      'purchase_invoices', 'inventory_bonds', 'requisitions',
    ],
    'manager': [
      'dashboard', 'reports', 'parties', 'products', 'treasury',
      'accounting', 'hr', 'settings', 'branches',
    ],
    'admin': null, // null = show everything
  };

  /// Filter navigation sections based on user's permission codes
  static List<NavSection> filterSections({
    required List<NavSection> allSections,
    required Set<String> userPermissions,
    required bool isAdmin,
  }) {
    if (isAdmin) return allSections; // Admin sees everything

    return allSections
        .map((section) {
          // Check section-level permission
          if (section.requiredPermission != null &&
              !userPermissions.contains(section.requiredPermission)) {
            return null;
          }

          // Filter individual items
          final visibleItems = section.items.where((item) {
            if (item.requiredPermission != null) {
              return userPermissions.contains(item.requiredPermission);
            }
            if (item.anyOfPermissions != null) {
              return item.anyOfPermissions!.any(userPermissions.contains);
            }
            return true; // No permission required, show to all
          }).toList();

          if (visibleItems.isEmpty) return null;

          return NavSection(
            id: section.id,
            label: section.label,
            icon: section.icon,
            items: visibleItems,
            requiredPermission: section.requiredPermission,
          );
        })
        .whereType<NavSection>()
        .toList();
  }

  /// Get role profile items for quick setup
  static Set<String>? getProfileSections(String roleName) {
    final profile = _roleProfiles[roleName.toLowerCase()];
    return profile?.toSet();
  }

  /// Build the default navigation map for the system
  static List<NavSection> buildDefaultNavigation() {
    return [
      const NavSection(
        id: 'main',
        label: 'الرئيسية',
        icon: PhosphorIconsBold.house,
        items: [
          NavItem(id: 'dashboard', label: 'لوحة التحكم', icon: PhosphorIconsBold.chartBar, routeName: '/dashboard'),
          NavItem(id: 'pos', label: 'نقطة البيع', icon: PhosphorIconsBold.storefront, routeName: '/pos', requiredPermission: 'pos_access'),
        ],
      ),
      const NavSection(
        id: 'sales',
        label: 'المبيعات',
        icon: PhosphorIconsBold.shoppingCart,
        items: [
          NavItem(id: 'sales_invoices', label: 'فواتير المبيعات', icon: PhosphorIconsBold.receipt, routeName: '/sales', requiredPermission: 'sales_view'),
          NavItem(id: 'sales_quotes', label: 'عروض الأسعار', icon: PhosphorIconsBold.fileText, routeName: '/quotes', requiredPermission: 'quotes_view'),
          NavItem(id: 'returns', label: 'المرتجعات', icon: PhosphorIconsBold.arrowUUpLeft, routeName: '/returns', requiredPermission: 'returns_view'),
        ],
      ),
      const NavSection(
        id: 'purchases',
        label: 'المشتريات',
        icon: PhosphorIconsBold.package,
        requiredPermission: 'purchases_view',
        items: [
          NavItem(id: 'purchase_invoices', label: 'فواتير المشتريات', icon: PhosphorIconsBold.fileArrowDown, routeName: '/purchases'),
        ],
      ),
      const NavSection(
        id: 'inventory',
        label: 'المخزون',
        icon: PhosphorIconsBold.warehouse,
        items: [
          NavItem(id: 'products', label: 'الأصناف', icon: PhosphorIconsBold.barcode, routeName: '/products', requiredPermission: 'products_view'),
          NavItem(id: 'warehouses', label: 'المستودعات', icon: PhosphorIconsBold.buildings, routeName: '/warehouses', requiredPermission: 'warehouses_view'),
          NavItem(id: 'stock_movements', label: 'حركة المخزون', icon: PhosphorIconsBold.arrowsLeftRight, routeName: '/stock-movements', requiredPermission: 'stock_view'),
          NavItem(id: 'cycle_count', label: 'الجرد الدوري', icon: PhosphorIconsBold.listChecks, routeName: '/cycle-count', requiredPermission: 'stock_audit'),
        ],
      ),
      const NavSection(
        id: 'accounting',
        label: 'المحاسبة',
        icon: PhosphorIconsBold.calculator,
        requiredPermission: 'accounting_view',
        items: [
          NavItem(id: 'journal_entries', label: 'القيود اليومية', icon: PhosphorIconsBold.notebook, routeName: '/journal-entries'),
          NavItem(id: 'financial_statements', label: 'القوائم المالية', icon: PhosphorIconsBold.chartLineUp, routeName: '/financial-statements'),
          NavItem(id: 'cost_centers', label: 'مراكز التكلفة', icon: PhosphorIconsBold.target, routeName: '/cost-centers'),
          NavItem(id: 'bank_reconciliation', label: 'مطابقة البنوك', icon: PhosphorIconsBold.bank, routeName: '/bank-reconciliation'),
        ],
      ),
      const NavSection(
        id: 'parties',
        label: 'الأطراف',
        icon: PhosphorIconsBold.users,
        items: [
          NavItem(id: 'customers', label: 'العملاء', icon: PhosphorIconsBold.userCircle, routeName: '/customers', requiredPermission: 'parties_view'),
          NavItem(id: 'suppliers', label: 'الموردين', icon: PhosphorIconsBold.truck, routeName: '/suppliers', requiredPermission: 'parties_view'),
        ],
      ),
      const NavSection(
        id: 'treasury',
        label: 'الخزينة',
        icon: PhosphorIconsBold.vault,
        requiredPermission: 'treasury_view',
        items: [
          NavItem(id: 'receipt_vouchers', label: 'سندات القبض', icon: PhosphorIconsBold.arrowFatLineDown, routeName: '/receipts'),
          NavItem(id: 'payment_vouchers', label: 'سندات الصرف', icon: PhosphorIconsBold.arrowFatLineUp, routeName: '/payments'),
        ],
      ),
      const NavSection(
        id: 'reports',
        label: 'التقارير',
        icon: PhosphorIconsBold.chartPieSlice,
        requiredPermission: 'reports_view',
        items: [
          NavItem(id: 'sales_report', label: 'تقرير المبيعات', icon: PhosphorIconsBold.chartLineUp, routeName: '/reports/sales'),
          NavItem(id: 'inventory_report', label: 'تقرير المخزون', icon: PhosphorIconsBold.package, routeName: '/reports/inventory'),
          NavItem(id: 'treasury_report', label: 'تقرير الخزينة', icon: PhosphorIconsBold.vault, routeName: '/reports/treasury'),
        ],
      ),
      const NavSection(
        id: 'admin',
        label: 'الإدارة',
        icon: PhosphorIconsBold.gearSix,
        requiredPermission: 'settings_access',
        items: [
          NavItem(id: 'settings', label: 'الإعدادات', icon: PhosphorIconsBold.wrench, routeName: '/settings'),
          NavItem(id: 'users', label: 'المستخدمين', icon: PhosphorIconsBold.usersThree, routeName: '/users', requiredPermission: 'users_manage'),
          NavItem(id: 'activity_log', label: 'سجل النشاط', icon: PhosphorIconsBold.clockCounterClockwise, routeName: '/activity-log', requiredPermission: 'audit_view'),
          NavItem(id: 'branches', label: 'الفروع', icon: PhosphorIconsBold.buildings, routeName: '/branches', requiredPermission: 'branches_manage'),
        ],
      ),
    ];
  }
}
