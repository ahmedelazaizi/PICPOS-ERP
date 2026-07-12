import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'core/theme/app_theme.dart';
import 'core/config/supabase_config.dart';
import 'data/providers/providers.dart';
import 'presentation/shell/app_shell.dart';
import 'presentation/screens/login_screen.dart';
import 'presentation/screens/dashboard_screen.dart';
import 'presentation/pos/screens/pos_screen.dart';
import 'presentation/screens/products_screen.dart';
import 'presentation/screens/categories_screen.dart';
import 'presentation/screens/customers_screen.dart';
import 'presentation/screens/suppliers_screen.dart';
import 'presentation/screens/inventory_screen.dart';
import 'presentation/screens/purchases_screen.dart';
import 'presentation/screens/treasury_screen.dart';
import 'presentation/screens/reports_screen.dart';
import 'presentation/screens/settings_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Initialize Supabase
  await Supabase.initialize(
    url: SupabaseConfig.supabaseUrl,
    anonKey: SupabaseConfig.supabaseAnonKey,
  );
  
  runApp(
    const ProviderScope(
      child: CashierMarketWebApp(),
    ),
  );
}

class CashierMarketWebApp extends ConsumerWidget {
  const CashierMarketWebApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authProvider);
    final isDarkMode = ref.watch(themeModeProvider);

    return MaterialApp(
      title: 'UralCash Web - نظام الكاشير',
      debugShowCheckedModeBanner: false,
      locale: const Locale('ar', 'EG'),
      supportedLocales: const [
        Locale('ar', 'EG'),
        Locale('en', 'US'),
      ],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: isDarkMode ? ThemeMode.dark : ThemeMode.light,
      home: authState.isAuthenticated 
          ? const AppShell() 
          : const LoginScreen(),
      routes: {
        '/login': (context) => const LoginScreen(),
        '/dashboard': (context) => const DashboardScreen(),
        '/pos': (context) => const POSScreen(),
        '/products': (context) => const ProductsScreen(),
        '/categories': (context) => const CategoriesScreen(),
        '/customers': (context) => const CustomersScreen(),
        '/suppliers': (context) => const SuppliersScreen(),
        '/inventory': (context) => const InventoryScreen(),
        '/purchases': (context) => const PurchasesScreen(),
        '/treasury': (context) => const TreasuryScreen(),
        '/reports': (context) => const ReportsScreen(),
        '/settings': (context) => const SettingsScreen(),
      },
    );
  }
}
