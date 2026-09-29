import 'package:ural_erp/core/i18n/tr.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../domain/repositories/i_products_repository.dart';
import '../../../data/providers/repository_providers.dart';
import '../../../data/providers/auth_providers.dart';
import '../../../core/logging/app_logger.dart';
import '../../../services/client_write_interceptor.dart';
import '../../../data/database/sync_interceptor.dart';

class CategoriesState {
  final bool isLoading;
  final String? error;

  const CategoriesState({this.isLoading = false, this.error});

  CategoriesState copyWith({
    bool? isLoading,
    String? error,
    bool clearError = false,
  }) {
    return CategoriesState(
      isLoading: isLoading ?? this.isLoading,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

class CategoriesNotifier extends Notifier<CategoriesState> {
  late final IProductRepository _repository;

  @override
  CategoriesState build() {
    _repository = ref.watch(productRepositoryProvider);
    return const CategoriesState();
  }

  Future<bool> createCategory({
    required String name,
    required String color,
    int? printerId,
    String? iconName,
    bool isGlobal = true,
    List<int> branchIds = const [],
  }) async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      // ── Client/Mirror mode: route to the server FIRST (awaited) ──
      // Fire-and-forget left the category existing on this device ONLY: the
      // categories pull upserts, it never re-pushes local-only rows, so a
      // failed submit produced a tree that silently disagreed with every other
      // device — and the operator had no way to tell. In client mode the
      // interceptor still returns success for "queued to outbox", so this only
      // refuses when the write genuinely could not be placed.
      if (SyncInterceptor.isClientMode) {
        final serverId = await ClientWriteInterceptor.createCategory(
          name: name,
          color: color,
          printerId: printerId,
          iconName: iconName,
          isGlobal: isGlobal,
          branchIds: branchIds,
        );
        if (serverId == null) {
          state = state.copyWith(
            isLoading: false,
            error: 'تعذّر إنشاء التصنيف على الخادم — لم يُنشأ محلياً '
                'حتى لا يظهر على هذا الجهاز وحده.',
          );
          return false;
        }
      }

      // ALWAYS write locally so the UI reflects the change immediately
      await _repository.insertCategoryWithPrinter(
        name: name,
        color: color,
        printerId: printerId,
        iconName: iconName,
        isGlobal: isGlobal,
        branchIds: branchIds,
      );

      _logActivity('category_add', tr('إضافة تصنيف جديد: {name}', {'name': name}));
      state = state.copyWith(isLoading: false);
      return true;
    } catch (e, st) {
      logger.error('Failed to create category', e, st, 'CATEGORIES');
      state = state.copyWith(isLoading: false, error: tr('فشل إضافة التصنيف: {e}', {'e': e}));
      return false;
    }
  }

  Future<bool> updateCategory({
    required int id,
    required String name,
    required String color,
    int? printerId,
    String? iconName,
    bool isGlobal = true,
    List<int> branchIds = const [],
  }) async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      // ── Client/Mirror mode: route to the server FIRST (awaited) ──
      // Same contract as deleteCategory below. Fire-and-forget was lossy for
      // the same reason: cwi_catalog.updateCategory schedules
      // `_scheduleCategoriesPull` right after the submit, and
      // CategorySyncStrategy upserts (insertOnConflictUpdate) the server row
      // over the local one. A failed submit + a local write meant the pull
      // overwrote the edit with the server's stale values — the rename or the
      // colour change reverted on its own after a success message.
      if (SyncInterceptor.isClientMode) {
        final ok = await ClientWriteInterceptor.updateCategory(
          id: id,
          name: name,
          color: color,
          printerId: printerId,
          iconName: iconName,
          isGlobal: isGlobal,
          branchIds: branchIds,
        );
        if (!ok) {
          state = state.copyWith(
            isLoading: false,
            error: 'تعذّر حفظ التعديل على الخادم — لم يُحفظ محلياً '
                'لمنع رجوع القيم القديمة مع المزامنة القادمة.',
          );
          return false;
        }
      }

      // ALWAYS write locally so the UI reflects the change immediately
      await _repository.updateCategoryWithPrinter(
        id: id,
        name: name,
        color: color,
        printerId: printerId,
        iconName: iconName,
        isGlobal: isGlobal,
        branchIds: branchIds,
      );

      _logActivity('category_edit', tr('تعديل تصنيف: {name}', {'name': name}), entityId: id);
      state = state.copyWith(isLoading: false);
      return true;
    } catch (e, st) {
      logger.error('Failed to update category', e, st, 'CATEGORIES');
      state = state.copyWith(isLoading: false, error: tr('فشل تعديل التصنيف: {e}', {'e': e}));
      return false;
    }
  }

  /// Feature 045 — count active products under [categoryId]. The
  /// delete-category dialog calls this BEFORE opening to decide whether
  /// to show the empty-confirm path or the bulk-move-then-delete path.
  Future<int> countActiveProductsInCategory(int categoryId) {
    return _repository.countActiveProductsInCategory(categoryId);
  }

  /// Field-report 2026-05-14 — count invoice items in this category on a
  /// specific branch. Surfaced in the delete dialog as an extra warning
  /// "this category is invoiced on your branch — deletion is global".
  Future<int> countCategoryInvoicedItemsOnBranch(
    int categoryId,
    int branchId,
  ) {
    return _repository.countCategoryInvoicedItemsOnBranch(categoryId, branchId);
  }

  /// Feature 045 — soft-delete a category with explicit caller-chosen
  /// destination for its active products.
  ///
  /// [moveToCategoryId] semantics:
  ///   - real id  → bulk-move all active products under [id] to that
  ///     destination inside a single DAO transaction, then soft-delete.
  ///   - null     → leave products with `categoryId = NULL` (uncategorized;
  ///     valid because `Products.categoryId` is nullable). The empty-
  ///     category path also passes null because there's nothing to move.
  ///
  /// Pre-v128 the controller fired the server delete with
  /// `.catchError((_) {})` — swallowing every failure silently. A network
  /// blip, FK mismatch, or rate-limit on the server then meant the
  /// category vanished locally but persisted on the server, and the next
  /// DeltaPull resurrected it for whoever logged in next. v128 awaits
  /// the server call and surfaces failures to the UI; the local
  /// soft-delete is the same shape the server emits, so subsequent
  /// pulls converge correctly.
  Future<bool> deleteCategory(
    int id,
    String name, {
    int? moveToCategoryId,
  }) async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      // ── Client/Mirror mode: route to server FIRST (awaited). If the
      //    server refuses we must NOT delete locally — otherwise the
      //    next DeltaPull resurrects the row.
      if (SyncInterceptor.isClientMode) {
        final ok = await ClientWriteInterceptor.deleteCategory(
          id,
          moveToCategoryId: moveToCategoryId,
        );
        if (!ok) {
          state = state.copyWith(
            isLoading: false,
            error: 'تعذّر حذف التصنيف على الخادم — لم يتم الحذف محلياً '
                'لمنع رجوع التصنيف مع المزامنة القادمة.',
          );
          return false;
        }
      }

      // Local soft-delete + bulk-move (single transaction).
      await _repository.deleteCategory(id, moveToCategoryId: moveToCategoryId);

      final moveSuffix = moveToCategoryId == null
          ? ''
          : tr(' (نُقلت الأصناف إلى تصنيف #{moveToCategoryId})', {'moveToCategoryId': moveToCategoryId});
      _logActivity('category_delete', tr('حذف تصنيف: {name}{moveSuffix}', {'name': name, 'moveSuffix': moveSuffix}));
      state = state.copyWith(isLoading: false);
      return true;
    } catch (e, st) {
      logger.error('Failed to delete category', e, st, 'CATEGORIES');
      state = state.copyWith(isLoading: false, error: tr('فشل حذف التصنيف: {e}', {'e': e}));
      return false;
    }
  }

  Future<void> toggleCategoryLock(int id, bool isLocked, String name) async {
    try {
      await _repository.setCategoryLocked(id, isLocked);
      _logActivity(
        'category_lock_toggle',
        tr('{p0} تصنيف: {name}', {'p0': isLocked ? "إقفال" : "فتح", 'name': name}),
        entityId: id,
      );
    } catch (e, st) {
      logger.error('Failed to toggle category lock', e, st, 'CATEGORIES');
    }
  }

  Future<void> toggleCategoryExclusion(
    int id,
    bool isExcluded,
    String name,
  ) async {
    try {
      if (isExcluded) {
        await _repository.excludeCategoryWithAllProducts(id);
      } else {
        await _repository.unexcludeCategoryWithAllProducts(id);
      }
      _logActivity(
        'category_exclude_toggle',
        tr('{p0} تصنيف: {name}', {'p0': isExcluded ? "استثناء" : "إلغاء استثناء", 'name': name}),
        entityId: id,
      );
    } catch (e, st) {
      logger.error('Failed to toggle category exclusion', e, st, 'CATEGORIES');
    }
  }

  Future<void> updateSortOrders(List<int> categoryIds) async {
    try {
      await _repository.updateCategorySortOrders(categoryIds);
      _logActivity('category_reorder', tr('إعادة ترتيب التصنيفات'));
    } catch (e, st) {
      logger.error('Failed to update sort orders', e, st, 'CATEGORIES');
    }
  }

  Future<void> toggleShowInPos(int id, bool showInPos, String name) async {
    try {
      await _repository.setCategoryShowInPos(id, showInPos);
      _logActivity(
        'category_pos_visibility',
        tr('{p0} تصنيف في البيع السريع: {name}', {'p0': showInPos ? "إظهار" : "إخفاء", 'name': name}),
        entityId: id,
      );
    } catch (e, st) {
      logger.error('Failed to toggle category POS visibility', e, st, 'CATEGORIES');
    }
  }

  void _logActivity(String action, String description, {int? entityId}) {
    final user = ref.read(authProvider).user;
    _repository
        .logActivity(
          userId: user?.id,
          userName: user?.displayName ?? tr('مستخدم'),
          action: action,
          entityId: entityId ?? 0,
          description: description,
        )
        .catchError((_) {});
  }
}

/// Persistent (NOT autoDispose) — the dialog-driven flows (create / edit /
/// delete) all schedule work via `Future`s that keep running after the
/// closing dialog unsubscribes. With autoDispose, that race disposed the
/// provider mid-operation and any follow-up `ref.read` (e.g. inside
/// `_logActivity`, or the controller's own state update on completion)
/// threw the classic "Cannot use the Ref of ... after it has been
/// disposed" exception. Making the provider live for the app lifetime is
/// harmless (the notifier holds only a repo reference), and eliminates
/// the class of bug outright.
final categoriesControllerProvider =
    NotifierProvider<CategoriesNotifier, CategoriesState>(
      CategoriesNotifier.new,
    );
