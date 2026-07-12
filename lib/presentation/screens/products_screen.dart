import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import '../../core/diagnostics/perf_trace.dart';
import '../../core/logging/diagnostic_logger.dart';
import '../../core/widgets/app_shortcuts.dart';
import '../widgets/dialogs/add_product_dialog.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/providers/auth_providers.dart';
import '../../data/providers/audit_providers.dart';
import '../../presentation/products/providers/products_controller.dart';
import 'products/widgets/product_search_header.dart';
import 'products/widgets/products_table.dart';
import 'products/widgets/products_bulk_action_bar.dart';

/// Products management screen
class ProductsScreen extends ConsumerStatefulWidget {
  const ProductsScreen({super.key});

  @override
  ConsumerState<ProductsScreen> createState() => _ProductsScreenState();
}

class _ProductsScreenState extends ConsumerState<ProductsScreen> {
  final _searchController = TextEditingController();
  final _searchFocusNode = FocusNode();
  final _scrollController = ScrollController();

  // Spec 029 / US4 — perf instrumentation. Compiled out in release
  // unless `kPerfDebug` is flipped to true. See perf-audit.md.
  final _perfFirstPaint = PerfFirstPaint('products');
  // ignore: unused_field
  TimingsCallback? _perfFrameCallback;
  // Spec 032 v3 diagnostic — screen-level build counter.
  final _screenBuilds = PerfRebuildCounter('products_screen', everyN: 10);

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);

    if (kPerfDebug) {
      _perfFrameCallback = (timings) =>
          perfReportFrameOverBudget('products', timings);
      SchedulerBinding.instance.addTimingsCallback(_perfFrameCallback!);
    }

    // Log screen access
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _perfFirstPaint.emit();
      // Spec 032 v3 diagnostic — write a clear session marker into the
      // log file so the operator can find the start of this scroll
      // session inside Documents/uralcash_login_log.txt.
      if (kPerfDebug) {
        DiagnosticLogger.startSession('products screen entered');
      }
      final user = ref.read(authProvider).user;
      if (user != null) {
        ref
            .read(activityLoggerProvider)
            .logNavigation(
              user.id,
              user.displayName,
              'قائمة المنتجات (Products)',
            );
      }
    });
  }

  @override
  void dispose() {
    if (kPerfDebug && _perfFrameCallback != null) {
      SchedulerBinding.instance.removeTimingsCallback(_perfFrameCallback!);
    }
    _searchController.dispose();
    _searchFocusNode.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  // Cluster 027 / Issue 4 (perf) — guard against the scroll listener
  // firing `loadNextPage` on every pixel of scroll while the user
  // sits near the bottom edge. The notifier already deduplicates an
  // in-flight load via its `isLoading` guard, but the call path
  // (ref.read → notifier lookup → state read → guard → return) costs
  // ~200 microseconds per fire. At 120 Hz scrolls that adds up to
  // visible jank. This local debounce skips the call entirely until
  // the previous load actually completed.
  bool _loadInFlight = false;
  // Spec 032 v3 diagnostic — log scroll deltas (throttled to 100ms) so
  // a sustained drag emits a readable trace.
  final _scrollLog = PerfScrollLogger('products', throttleMs: 100);
  void _onScroll() {
    if (kPerfDebug && _scrollController.hasClients) {
      _scrollLog.log(
        _scrollController.position.pixels,
        _scrollController.position.maxScrollExtent,
      );
    }
    if (_loadInFlight) return;
    if (_scrollController.position.pixels <
        _scrollController.position.maxScrollExtent - 200) {
      return;
    }
    _loadInFlight = true;
    Future(() async {
      try {
        await ref
            .read(productsControllerProvider.notifier)
            .loadNextPage();
      } finally {
        _loadInFlight = false;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    _screenBuilds.tick();
    return Directionality(
      textDirection: TextDirection.rtl,
      child: AppShortcuts(
        searchFocusNode: _searchFocusNode,
        searchController: _searchController,
        onNew: () async {
          final result = await AddProductDialog.show(context);
          if (result != null) {
            ref.read(productsControllerProvider.notifier).loadNextPage(isRefresh: true);
          }
        },
        child: Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        body: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ProductSearchHeader(
                searchController: _searchController,
                searchFocusNode: _searchFocusNode,
              ),
              const SizedBox(height: 12),
              Expanded(
                child: Card(
                  elevation: 2,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: ProductsTable(scrollController: _scrollController),
                ),
              ),
              const ProductsBulkActionBar(),
            ],
          ),
        ),
      ),
      ),
    );
  }
}
