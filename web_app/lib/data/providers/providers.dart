import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../database/supabase_database.dart';
import '../database/models.dart';

// ═══════════════════════════════════════════════════════════════════════════
// SUPABASE PROVIDERS
// ═══════════════════════════════════════════════════════════════════════════

/// Supabase client provider
final supabaseClientProvider = Provider<SupabaseClient>((ref) {
  return Supabase.instance.client;
});

/// Supabase database provider
final databaseProvider = Provider<SupabaseDatabase>((ref) {
  final client = ref.watch(supabaseClientProvider);
  return SupabaseDatabase(client);
});

// ═══════════════════════════════════════════════════════════════════════════
// PRODUCT PROVIDERS
// ═══════════════════════════════════════════════════════════════════════════

final allProductsProvider = StreamProvider<List<Product>>((ref) {
  final db = ref.watch(databaseProvider);
  return db.watchAllProducts();
});

final allCategoriesProvider = StreamProvider<List<Category>>((ref) {
  final db = ref.watch(databaseProvider);
  return db.watchCategories();
});

// ═══════════════════════════════════════════════════════════════════════════
// PARTY PROVIDERS
// ═══════════════════════════════════════════════════════════════════════════

final allCustomersProvider = StreamProvider<List<Party>>((ref) {
  final db = ref.watch(databaseProvider);
  return db.watchCustomers();
});

final allSuppliersProvider = StreamProvider<List<Party>>((ref) {
  final db = ref.watch(databaseProvider);
  return db.watchSuppliers();
});

// ═══════════════════════════════════════════════════════════════════════════
// SALES PROVIDERS
// ═══════════════════════════════════════════════════════════════════════════

final todaySalesProvider = StreamProvider<List<SalesInvoiceData>>((ref) {
  final db = ref.watch(databaseProvider);
  return db.watchSalesInvoices();
});

// ═══════════════════════════════════════════════════════════════════════════
// PURCHASE PROVIDERS
// ═══════════════════════════════════════════════════════════════════════════

final allPurchasesProvider = StreamProvider<List<PurchaseInvoiceData>>((ref) {
  final db = ref.watch(databaseProvider);
  return db.watchPurchaseInvoices();
});

// ═══════════════════════════════════════════════════════════════════════════
// TREASURY PROVIDERS
// ═══════════════════════════════════════════════════════════════════════════

final allSafesProvider = StreamProvider<List<Safe>>((ref) {
  final db = ref.watch(databaseProvider);
  return db.watchSafes();
});

final totalCashBalanceProvider = StreamProvider<double>((ref) {
  final safes = ref.watch(allSafesProvider);
  return safes.when(
    data: (list) => Stream.value(list.fold(0.0, (sum, safe) => sum + safe.balance)),
    loading: () => Stream.value(0.0),
    error: (_, _) => Stream.value(0.0),
  );
});

// ═══════════════════════════════════════════════════════════════════════════
// STOCK MOVEMENTS PROVIDERS
// ═══════════════════════════════════════════════════════════════════════════

final stockMovementsProvider = StreamProvider<List<StockMovement>>((ref) {
  final db = ref.watch(databaseProvider);
  return db.watchStockMovements();
});

// ═══════════════════════════════════════════════════════════════════════════
// AUTH STATE
// ═══════════════════════════════════════════════════════════════════════════

class AuthState {
  final AppUser? user;
  final bool isAuthenticated;
  final DateTime? loginTime;
  final DateTime? lastActivity;
  
  static const Duration sessionTimeout = Duration(hours: 8);
  static const Duration inactivityTimeout = Duration(minutes: 30);

  const AuthState({
    this.user, 
    this.isAuthenticated = false,
    this.loginTime,
    this.lastActivity,
  });

  bool get isAdmin => user?.role == 'admin';
  bool get isManager => user?.role == 'manager' || isAdmin;
  bool get isCashier => user?.role == 'cashier';
  
  bool get isSessionExpired {
    if (loginTime == null || !isAuthenticated) return true;
    return DateTime.now().difference(loginTime!) > sessionTimeout;
  }
  
  bool get isInactive {
    if (lastActivity == null || !isAuthenticated) return true;
    return DateTime.now().difference(lastActivity!) > inactivityTimeout;
  }
  
  Duration get remainingSessionTime {
    if (loginTime == null) return Duration.zero;
    final elapsed = DateTime.now().difference(loginTime!);
    final remaining = sessionTimeout - elapsed;
    return remaining.isNegative ? Duration.zero : remaining;
  }
  
  String get sessionInfo {
    if (!isAuthenticated || user == null) return '';
    final remaining = remainingSessionTime;
    final hours = remaining.inHours;
    final minutes = remaining.inMinutes % 60;
    return '$hours:${minutes.toString().padLeft(2, '0')}';
  }

  AuthState copyWith({
    AppUser? user, 
    bool? isAuthenticated,
    DateTime? loginTime,
    DateTime? lastActivity,
  }) {
    return AuthState(
      user: user ?? this.user,
      isAuthenticated: isAuthenticated ?? this.isAuthenticated,
      loginTime: loginTime ?? this.loginTime,
      lastActivity: lastActivity ?? this.lastActivity,
    );
  }
}

class AuthNotifier extends Notifier<AuthState> {
  @override
  AuthState build() => const AuthState();

  void login(AppUser user) {
    final now = DateTime.now();
    state = AuthState(
      user: user, 
      isAuthenticated: true,
      loginTime: now,
      lastActivity: now,
    );
  }

  void updateActivity() {
    if (state.isAuthenticated) {
      state = state.copyWith(lastActivity: DateTime.now());
    }
  }
  
  bool checkSession() {
    if (!state.isAuthenticated) return false;
    
    if (state.isSessionExpired) {
      logout();
      return false;
    }
    
    updateActivity();
    return true;
  }
  
  bool hasPermission(String permission) {
    if (!state.isAuthenticated || state.user == null) return false;
    
    switch (permission) {
      case 'admin':
        return state.isAdmin;
      case 'manager':
        return state.isManager;
      case 'settings':
        return state.isAdmin;
      case 'reports':
        return state.isManager;
      case 'users':
        return state.isAdmin;
      case 'products':
        return state.isManager;
      case 'sales':
        return true;
      case 'purchases':
        return state.isManager;
      case 'treasury':
        return state.isManager;
      default:
        return false;
    }
  }

  void logout() {
    state = const AuthState();
  }
}

final authProvider = NotifierProvider<AuthNotifier, AuthState>(() {
  return AuthNotifier();
});

// ═══════════════════════════════════════════════════════════════════════════
// THEME PROVIDER
// ═══════════════════════════════════════════════════════════════════════════

class ThemeModeNotifier extends Notifier<bool> {
  @override
  bool build() => false; // false = light, true = dark

  void toggle() {
    state = !state;
  }

  void setDarkMode(bool value) {
    state = value;
  }
}

final themeModeProvider = NotifierProvider<ThemeModeNotifier, bool>(() {
  return ThemeModeNotifier();
});
