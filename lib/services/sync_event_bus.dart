import 'dart:async';
import 'package:flutter/foundation.dart';

// ═══════════════════════════════════════════════════════════════════════════
// P4.3 — Sync Event Bus
// ═══════════════════════════════════════════════════════════════════════════
// Broadcasts sync lifecycle events so UI widgets can react without polling.
//
// Usage:
//   SyncEventBus.instance.stream.listen((e) { ... });
//   SyncEventBus.instance.tableStream('products').listen((e) { ... });

sealed class SyncEvent {
  const SyncEvent();
}

class SyncPullStarted extends SyncEvent {
  const SyncPullStarted();
}

class SyncTablePulled extends SyncEvent {
  final String table;
  final int rowCount;
  const SyncTablePulled(this.table, this.rowCount);
}

class SyncPullCompleted extends SyncEvent {
  final int totalRows;
  const SyncPullCompleted(this.totalRows);
}

/// Emitted when the client's local row is newer than the server row.
class SyncConflictDetected extends SyncEvent {
  final String table;
  final dynamic recordId;
  final String resolution; // 'client_wins' | 'server_wins'
  const SyncConflictDetected(this.table, this.recordId, this.resolution);
}

class SyncEventBus {
  SyncEventBus._();
  static final SyncEventBus instance = SyncEventBus._();

  final StreamController<SyncEvent> _controller =
      StreamController<SyncEvent>.broadcast();

  /// All sync events.
  Stream<SyncEvent> get stream => _controller.stream;

  /// Whether a delta pull is currently in progress.
  final ValueNotifier<bool> isPulling = ValueNotifier<bool>(false);

  /// Events filtered to a single table (only [SyncTablePulled]).
  Stream<SyncTablePulled> tableStream(String table) => stream
      .where((e) => e is SyncTablePulled)
      .cast<SyncTablePulled>()
      .where((e) => e.table == table);

  void emit(SyncEvent event) {
    if (!_controller.isClosed) _controller.add(event);
  }

  void dispose() {
    _controller.close();
    isPulling.dispose();
  }
}
