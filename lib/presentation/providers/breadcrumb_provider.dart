import 'package:flutter_riverpod/flutter_riverpod.dart';

class BreadcrumbItem {
  final String label;
  final String? route;
  final Function()? onTap;

  const BreadcrumbItem({
    required this.label,
    this.route,
    this.onTap,
  });
}

class BreadcrumbNotifier extends Notifier<List<BreadcrumbItem>> {
  @override
  List<BreadcrumbItem> build() => [];

  void setBreadcrumbs(List<BreadcrumbItem> items) {
    state = items;
  }

  void addBreadcrumb(BreadcrumbItem item) {
    // Avoid duplicates if same label is added consecutively
    if (state.isNotEmpty && state.last.label == item.label) return;
    state = [...state, item];
  }

  void popToLabel(String label) {
    final index = state.indexWhere((item) => item.label == label);
    if (index != -1) {
      state = state.sublist(0, index + 1);
    }
  }

  void clear() {
    state = [];
  }

  /// Sets breadcrumbs from a list of strings (simple labels)
  void setFromLabels(List<String> labels, {Function(int)? onTap}) {
    state = labels.asMap().entries.map((entry) {
      final index = entry.key;
      final label = entry.value;
      return BreadcrumbItem(
        label: label,
        onTap: onTap != null ? () => onTap(index) : null,
      );
    }).toList();
  }
}

final breadcrumbProvider = NotifierProvider<BreadcrumbNotifier, List<BreadcrumbItem>>(() {
  return BreadcrumbNotifier();
});
