import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../core/theme/app_colors.dart';
import '../../data/providers/providers.dart';
import '../screens/dashboard_screen.dart';
import '../pos/screens/pos_screen.dart';
import '../screens/products_screen.dart';
import '../screens/categories_screen.dart';
import '../screens/customers_screen.dart';
import '../screens/suppliers_screen.dart';
import '../screens/inventory_screen.dart';
import '../screens/purchases_screen.dart';
import '../screens/treasury_screen.dart';
import '../screens/reports_screen.dart';
import '../screens/settings_screen.dart';

class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key});

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  int _selectedIndex = 0;
  bool _isExpanded = true;

  final List<_NavItem> _navItems = [
    _NavItem('لوحة التحكم', PhosphorIconsBold.squaresFour, const DashboardScreen()),
    _NavItem('نقطة البيع', PhosphorIconsBold.shoppingCart, const POSScreen()),
    _NavItem('المنتجات', PhosphorIconsBold.package, const ProductsScreen()),
    _NavItem('التصنيفات', PhosphorIconsBold.folders, const CategoriesScreen()),
    _NavItem('العملاء', PhosphorIconsBold.users, const CustomersScreen()),
    _NavItem('الموردين', PhosphorIconsBold.truck, const SuppliersScreen()),
    _NavItem('المخزون', PhosphorIconsBold.warehouse, const InventoryScreen()),
    _NavItem('المشتريات', PhosphorIconsBold.shoppingBag, const PurchasesScreen()),
    _NavItem('الخزينة', PhosphorIconsBold.bank, const TreasuryScreen()),
    _NavItem('التقارير', PhosphorIconsBold.chartBar, const ReportsScreen()),
    _NavItem('الإعدادات', PhosphorIconsBold.gear, const SettingsScreen()),
  ];

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      body: Row(
        children: [
          // Sidebar
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: _isExpanded ? 250 : 70,
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1a1a2e) : AppColors.primary,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.1),
                  blurRadius: 10,
                  offset: const Offset(2, 0),
                ),
              ],
            ),
            child: Column(
              children: [
                // Header
                Container(
                  height: 80,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(
                          PhosphorIconsBold.storefront,
                          color: Colors.white,
                          size: 24,
                        ),
                      ),
                      if (_isExpanded) ...[
                        const SizedBox(width: 12),
                        const Expanded(
                          child: Text(
                            'UralCash Web',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                
                const Divider(color: Colors.white24, height: 1),

                // Navigation items
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemCount: _navItems.length,
                    itemBuilder: (context, index) {
                      final item = _navItems[index];
                      final isSelected = _selectedIndex == index;

                      return Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            onTap: () => setState(() => _selectedIndex = index),
                            borderRadius: BorderRadius.circular(12),
                            child: Container(
                              height: 48,
                              padding: const EdgeInsets.symmetric(horizontal: 12),
                              decoration: BoxDecoration(
                                color: isSelected 
                                    ? Colors.white.withValues(alpha: 0.2) 
                                    : Colors.transparent,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    item.icon,
                                    color: Colors.white,
                                    size: 22,
                                  ),
                                  if (_isExpanded) ...[
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Text(
                                        item.title,
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontWeight: isSelected 
                                              ? FontWeight.bold 
                                              : FontWeight.normal,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),

                // User info & logout
                Container(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      if (_isExpanded && authState.user != null)
                        Container(
                          padding: const EdgeInsets.all(12),
                          margin: const EdgeInsets.only(bottom: 8),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            children: [
                              const CircleAvatar(
                                radius: 16,
                                backgroundColor: Colors.white24,
                                child: Icon(PhosphorIconsBold.user, color: Colors.white, size: 16),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      authState.user!.fullName ?? authState.user!.username,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 12,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    Text(
                                      authState.user!.role,
                                      style: TextStyle(
                                        color: Colors.white.withValues(alpha: 0.7),
                                        fontSize: 10,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      
                      // Expand/Collapse button
                      IconButton(
                        onPressed: () => setState(() => _isExpanded = !_isExpanded),
                        icon: Icon(
                          _isExpanded 
                              ? PhosphorIconsBold.caretLeft 
                              : PhosphorIconsBold.caretRight,
                          color: Colors.white,
                        ),
                      ),
                      
                      // Logout button
                      SizedBox(
                        width: double.infinity,
                        child: TextButton.icon(
                          onPressed: () {
                            ref.read(authProvider.notifier).logout();
                          },
                          icon: const Icon(PhosphorIconsBold.signOut, color: Colors.white70),
                          label: _isExpanded 
                              ? const Text('تسجيل الخروج', style: TextStyle(color: Colors.white70))
                              : const SizedBox.shrink(),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Main content
          Expanded(
            child: _navItems[_selectedIndex].screen,
          ),
        ],
      ),
    );
  }
}

class _NavItem {
  final String title;
  final IconData icon;
  final Widget screen;

  _NavItem(this.title, this.icon, this.screen);
}
