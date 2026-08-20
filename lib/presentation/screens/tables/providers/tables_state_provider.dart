import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../domain/models/table_designer_mode.dart';

class TablesUIState {
  final String statusFilter;
  final bool isVisualView;
  final bool isDesignerMode;
  final double tableCardSize;
  final int? selectedTableId;

  const TablesUIState({
    this.statusFilter = 'all',
    this.isVisualView = true,
    this.isDesignerMode = false,
    this.tableCardSize = 200.0,
    this.selectedTableId,
  });

  TablesUIState copyWith({
    String? statusFilter,
    bool? isVisualView,
    bool? isDesignerMode,
    double? tableCardSize,
    int? Function()? selectedTableId,
  }) {
    return TablesUIState(
      statusFilter: statusFilter ?? this.statusFilter,
      isVisualView: isVisualView ?? this.isVisualView,
      isDesignerMode: isDesignerMode ?? this.isDesignerMode,
      tableCardSize: tableCardSize ?? this.tableCardSize,
      selectedTableId: selectedTableId != null ? selectedTableId() : this.selectedTableId,
    );
  }
}

class TablesUIController extends Notifier<TablesUIState> {
  @override
  TablesUIState build() => const TablesUIState();

  void setStatusFilter(String filter) => state = state.copyWith(statusFilter: filter);

  // مغادرةُ الخريطة تُطفئ وضعَ التصميم — `designerModeAfterViewToggle` دالّةٌ
  // خالصةٌ مُختبَرةٌ لوحدها (البند ٥ في task-6b-brief.md).
  void toggleView() {
    final nextVisual = !state.isVisualView;
    state = state.copyWith(
      isVisualView: nextVisual,
      isDesignerMode: designerModeAfterViewToggle(
        wasVisualView: state.isVisualView,
        wasDesignerMode: state.isDesignerMode,
      ),
    );
  }

  void toggleDesignerMode() => state = state.copyWith(isDesignerMode: !state.isDesignerMode);
  void setCardSize(double size) => state = state.copyWith(tableCardSize: size.clamp(120, 320));
  void selectTable(int? id) => state = state.copyWith(selectedTableId: () => id);
}

final tablesUIProvider = NotifierProvider<TablesUIController, TablesUIState>(() {
  return TablesUIController();
});
