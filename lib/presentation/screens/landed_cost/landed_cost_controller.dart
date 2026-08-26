import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../data/database/database.dart' as db;
import '../../../domain/repositories/landed_cost_repository.dart';
import '../../../data/providers/repository_providers.dart';

/// ورقةُ تحميلٍ مُسطَّحةً إلى قِيَمٍ أوّليّة.
///
/// ═══ لماذا نوعٌ وسيطٌ أصلاً ═══
///
/// حارسُ `presentation_db_import_guard` يمنع كلَّ ملفِّ عرضٍ **جديد** من
/// استيراد `data/database`، وقائمتُه البيضاءُ مقفولة. وفوركُ PicPos
/// (`landed_cost_picpos_screen.dart`) ملفٌّ جديد — فلا يستطيع أن يسمّيَ
/// `db.LandedCostSheetData` ولا أن يستقبلها في توقيعِ دالّة.
///
/// وقراءتُها بـ`dynamic` هناك تعمل لكنّها تُطفئ المحلّلَ في عشرة مواضع
/// (`avoid_dynamic_calls`) وتحوّل خطأَ اسمِ حقلٍ من خطأِ ترجمةٍ إلى انهيارٍ
/// في زمن التشغيل. فالتسطيحُ يقع **هنا** — في ملفٍّ مُدرَجٍ في القائمة
/// البيضاء سلفاً ويستورد drift بحقّ — ويخرج للعرضِ نوعاً نظيفاً مؤكَّدَ
/// الحقول.
class LandedCostSheetView {
  const LandedCostSheetView({
    required this.id,
    required this.purchaseInvoiceId,
    required this.number,
    required this.totalCost,
    required this.method,
    required this.status,
  });

  final int id;
  final int purchaseInvoiceId;
  final String number;
  final double totalCost;
  final String method;
  final String status;

  factory LandedCostSheetView.from(db.LandedCostSheetData s) =>
      LandedCostSheetView(
        id: s.id,
        purchaseInvoiceId: s.purchaseInvoiceId,
        number: s.sheetNumber,
        totalCost: s.totalAdditionalCost,
        method: s.allocationMethod,
        status: s.status,
      );
}

/// بندُ تكلفةٍ مُسطَّحاً — نفسُ سببِ [LandedCostSheetView].
class LandedCostItemView {
  const LandedCostItemView({
    required this.id,
    required this.type,
    required this.description,
    required this.amount,
  });

  final int id;
  final String type;
  final String description;
  final double amount;

  factory LandedCostItemView.from(db.LandedCostItemData i) =>
      LandedCostItemView(
        id: i.id,
        type: i.costType,
        description: i.description,
        amount: i.amount,
      );
}

class LandedCostState {
  final List<db.LandedCostSheetData> sheets;
  final db.LandedCostSheetData? selectedSheet;
  final List<db.LandedCostItemData> costItems;
  final List<Map<String, dynamic>> allocations;
  final bool isLoading;

  /// S-COST (Spec 144 / R2): true while a landed-cost sheet is being applied —
  /// gates the apply button so a double-tap cannot post the entry twice.
  final bool isApplying;

  LandedCostState({
    this.sheets = const [],
    this.selectedSheet,
    this.costItems = const [],
    this.allocations = const [],
    this.isLoading = true,
    this.isApplying = false,
  });

  /// عروضٌ مُسطَّحةٌ لطبقةِ العرض — راجع [LandedCostSheetView].
  List<LandedCostSheetView> get sheetViews =>
      sheets.map(LandedCostSheetView.from).toList(growable: false);

  LandedCostSheetView? get selectedView => selectedSheet == null
      ? null
      : LandedCostSheetView.from(selectedSheet!);

  List<LandedCostItemView> get itemViews =>
      costItems.map(LandedCostItemView.from).toList(growable: false);

  LandedCostState copyWith({
    List<db.LandedCostSheetData>? sheets,
    db.LandedCostSheetData? selectedSheet,
    List<db.LandedCostItemData>? costItems,
    List<Map<String, dynamic>>? allocations,
    bool? isLoading,
    bool? isApplying,
  }) {
    return LandedCostState(
      sheets: sheets ?? this.sheets,
      selectedSheet: selectedSheet ?? this.selectedSheet,
      costItems: costItems ?? this.costItems,
      allocations: allocations ?? this.allocations,
      isLoading: isLoading ?? this.isLoading,
      isApplying: isApplying ?? this.isApplying,
    );
  }
}

class LandedCostController extends Notifier<LandedCostState> {
  @override
  LandedCostState build() {
    Future.microtask(() => _loadSheets());
    return LandedCostState();
  }

  ILandedCostRepository get _repo => ref.read(landedCostRepositoryProvider);

  Future<void> _loadSheets() async {
    try {
      final sheets = await _repo.getLandedCostSheets();

      List<db.LandedCostItemData>? items;
      List<Map<String, dynamic>>? allocs;
      if (state.selectedSheet != null) {
        items = await _repo.getLandedCostItems(state.selectedSheet!.id);
        allocs = await _repo.getAllocationsWithDetails(state.selectedSheet!.id);
      }

      state = state.copyWith(
        sheets: sheets,
        costItems: items ?? state.costItems,
        allocations: allocs ?? state.allocations,
        isLoading: false,
      );
    } catch (e) {
      debugPrint('[LandedCost] Load error: $e');
      state = state.copyWith(isLoading: false);
    }
  }

  Future<void> refresh() => _loadSheets();

  /// R2 double-submission guard for the apply flow.
  void setApplying(bool value) =>
      state = state.copyWith(isApplying: value);

  /// إلغاءُ الاختيار — العودةُ إلى قائمة الأوراق.
  ///
  /// ⚠️ لا تُبنى بـ`copyWith`: تمريرُ `null` فيها يعني «أبقِ القديم» لا
  /// «امسح»، فالورقةُ كانت تبقى مختارةً والزرُّ يبدو معطَّلاً. فالحالةُ
  /// تُبنى صريحةً هنا.
  void clearSelection() => state = LandedCostState(
        sheets: state.sheets,
        isLoading: false,
      );

  /// اختيارُ ورقةٍ برقمها الداخليّ — يُستعمل حيث لا تُمرَّر الصفُّ نفسُه.
  Future<void> selectSheetById(int sheetId) async {
    final match = state.sheets.where((s) => s.id == sheetId).firstOrNull;
    if (match == null) return;
    await selectSheet(match);
  }

  /// تغييرُ طريقة التوزيع ثمّ إعادةُ تحميل الصفوف المحسوبة.
  Future<void> changeAllocationMethod(int sheetId, String method) async {
    await _repo.updateAllocationMethod(sheetId, method);
    await _reloadSelected(sheetId);
  }

  /// إضافةُ بند تكلفةٍ — الـDAO يعيد حسابَ إجمالي الورقة بعدها.
  ///
  /// ⚠️ وإعادةُ حساب التوزيع تُطلَب صراحةً: `addLandedCostItem` تحدّث
  /// المجموعَ وحدَه، فبدونها يبقى جدولُ التوزيع على المبلغ القديم.
  Future<void> addCostItem({
    required int sheetId,
    required String costType,
    required String description,
    required double amount,
    int? supplierPartyId,
  }) async {
    await _repo.addLandedCostItem(
      sheetId: sheetId,
      costType: costType,
      description: description,
      amount: amount,
      supplierPartyId: supplierPartyId,
    );
    await _repo.calculateAllocations(sheetId);
    await _reloadSelected(sheetId);
  }

  /// تطبيقُ الورقة — محروسٌ بـ[LandedCostState.isApplying] فلا يُقيَّد مرّتين.
  Future<void> applySheet(int sheetId) async {
    if (state.isApplying) return;
    state = state.copyWith(isApplying: true);
    try {
      await _repo.applyLandedCost(sheetId);
      await _reloadSelected(sheetId);
    } finally {
      state = state.copyWith(isApplying: false);
    }
  }

  /// إعادةُ قراءةِ قائمةِ الأوراق ثمّ الورقةِ المختارة بعد فعلٍ غيّرها.
  Future<void> _reloadSelected(int sheetId) async {
    final sheets = await _repo.getLandedCostSheets();
    final fresh = sheets.where((s) => s.id == sheetId).firstOrNull;
    final items = await _repo.getLandedCostItems(sheetId);
    final allocs = await _repo.getAllocationsWithDetails(sheetId);
    state = state.copyWith(
      sheets: sheets,
      selectedSheet: fresh,
      costItems: items,
      allocations: allocs,
      isLoading: false,
    );
  }

  Future<void> selectSheet(db.LandedCostSheetData sheet) async {
    state = state.copyWith(isLoading: true);
    try {
      final items = await _repo.getLandedCostItems(sheet.id);
      final allocs = await _repo.getAllocationsWithDetails(sheet.id);
      state = state.copyWith(
        selectedSheet: sheet,
        costItems: items,
        allocations: allocs,
        isLoading: false,
      );
    } catch (e) {
      debugPrint('[LandedCost] Select sheet error: $e');
      state = state.copyWith(isLoading: false);
    }
  }
}

final landedCostControllerProvider = NotifierProvider<LandedCostController, LandedCostState>(() {
  return LandedCostController();
});
