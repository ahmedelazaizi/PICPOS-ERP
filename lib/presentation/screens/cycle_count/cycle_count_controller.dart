import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../data/database/database.dart' as db;
import '../../../domain/repositories/cycle_count_repository.dart';
import '../../../data/providers/repository_providers.dart';

class CycleCountState {
  final List<db.CycleCountPlanData> plans;
  final List<db.CycleCountTaskData> tasks;
  final db.CycleCountTaskData? selectedTask;
  final List<db.CycleCountItemData> taskItems;
  final bool isLoading;

  CycleCountState({
    this.plans = const [],
    this.tasks = const [],
    this.selectedTask,
    this.taskItems = const [],
    this.isLoading = true,
  });

  CycleCountState copyWith({
    List<db.CycleCountPlanData>? plans,
    List<db.CycleCountTaskData>? tasks,
    db.CycleCountTaskData? selectedTask,
    List<db.CycleCountItemData>? taskItems,
    bool? isLoading,
  }) {
    return CycleCountState(
      plans: plans ?? this.plans,
      tasks: tasks ?? this.tasks,
      selectedTask: selectedTask ?? this.selectedTask,
      taskItems: taskItems ?? this.taskItems,
      isLoading: isLoading ?? this.isLoading,
    );
  }
}

class CycleCountController extends Notifier<CycleCountState> {
  @override
  CycleCountState build() {
    Future.microtask(() => _loadData());
    return CycleCountState();
  }

  ICycleCountRepository get _repo => ref.read(cycleCountRepositoryProvider);

  Future<void> _loadData() async {
    try {
      final plans = await _repo.getCycleCountPlans();
      final tasks = await _repo.getCycleCountTasks();

      List<db.CycleCountItemData>? items;
      if (state.selectedTask != null) {
        items = await _repo.getCycleCountItems(state.selectedTask!.id);
      }

      state = state.copyWith(
        plans: plans,
        tasks: tasks,
        taskItems: items ?? state.taskItems,
        isLoading: false,
      );
    } catch (e) {
      debugPrint('[CycleCount] Load error: $e');
      state = state.copyWith(isLoading: false);
    }
  }

  Future<void> refresh() => _loadData();

  Future<void> selectTask(db.CycleCountTaskData task) async {
    state = state.copyWith(isLoading: true);
    try {
      final items = await _repo.getCycleCountItems(task.id);
      state = state.copyWith(selectedTask: task, taskItems: items, isLoading: false);
    } catch (e) {
      debugPrint('[CycleCount] Select task error: $e');
      state = state.copyWith(isLoading: false);
    }
  }
}

final cycleCountControllerProvider = NotifierProvider<CycleCountController, CycleCountState>(
  () => CycleCountController(),
);
