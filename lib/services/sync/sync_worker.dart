import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:picpos_erp/data/providers/providers.dart';
import 'package:picpos_erp/services/server_proxy.dart';

/// State for the Sync Worker
class SyncState {
  final int pendingCount;
  final bool isSyncing;
  final String? lastError;
  final DateTime? lastSyncTime;

  SyncState({
    this.pendingCount = 0,
    this.isSyncing = false,
    this.lastError,
    this.lastSyncTime,
  });

  SyncState copyWith({
    int? pendingCount,
    bool? isSyncing,
    String? lastError,
    DateTime? lastSyncTime,
  }) {
    return SyncState(
      pendingCount: pendingCount ?? this.pendingCount,
      isSyncing: isSyncing ?? this.isSyncing,
      lastError: lastError, // Reset error if not provided
      lastSyncTime: lastSyncTime ?? this.lastSyncTime,
    );
  }
}

/// A background worker that processes the SyncOutbox and pushes data to Supabase.
class SyncWorker extends Notifier<SyncState> {
  Timer? _pollTimer;
  static const _pollInterval = Duration(seconds: 30);
  bool _isProcessing = false;

  @override
  SyncState build() {
    // Watch pending count to update UI state
    final db = ref.watch(databaseProvider);
    db.watchSyncPendingCount().listen((count) {
      state = state.copyWith(pendingCount: count);
      if (count > 0 && !_isProcessing) {
        processOutbox();
      }
    });

    // Start periodic polling as a safety net
    _pollTimer = Timer.periodic(_pollInterval, (_) => processOutbox());

    ref.onDispose(() => _pollTimer?.cancel());

    return SyncState();
  }

  /// Manually trigger a sync cycle
  Future<void> processOutbox() async {
    if (_isProcessing) return;

    final supabase = ref.read(supabaseClientProvider);
    if (supabase == null) {
      // Supabase not available (e.g. desktop without cloud configured yet)
      return;
    }

    _isProcessing = true;
    state = state.copyWith(isSyncing: true);

    try {
      final db = ref.read(databaseProvider);
      final items = await db.getPendingSyncItems(limit: 10);

      if (items.isEmpty) {
        _isProcessing = false;
        state = state.copyWith(isSyncing: false);
        return;
      }

      debugPrint('[SyncWorker] Processing ${items.length} items...');

      for (final item in items) {
        try {
          final payload = jsonDecode(item.payload);

          // Determine Supabase operation
          final response = await _performRemoteOp(
            supabase,
            item.targetTable,
            item.operation,
            item.recordId,
            payload,
          );

          if (response != null) {
            // Success!
            await db.markAsSyncSuccess(
              item.id,
              remoteId: response['id']?.toString(),
            );
          } else {
            await db.markAsSyncFailed(
              item.id,
              'Remote operation returned no data',
            );
          }
        } catch (e) {
          debugPrint('[SyncWorker] Item ${item.id} failed: $e');
          await db.markAsSyncFailed(item.id, e.toString());
        }
      }

      state = state.copyWith(isSyncing: false, lastSyncTime: DateTime.now());
    } catch (e) {
      debugPrint('[SyncWorker] Critical error: $e');
      state = state.copyWith(isSyncing: false, lastError: e.toString());
    } finally {
      _isProcessing = false;

      // If there were items, check if more are pending
      if (state.pendingCount > 0) {
        Future.delayed(const Duration(seconds: 2), () => processOutbox());
      }
    }
  }

  /// Perform the actual remote operation on Supabase
  Future<Map<String, dynamic>?> _performRemoteOp(
    SupabaseClient client,
    String table,
    String operation,
    String recordId,
    Map<String, dynamic> payload,
  ) async {
    // Custom handled tables bypass Supabase to go through the specialized Node.js API
    if (table == 'safe_transactions' && operation == 'insert') {
       await ServerProxy.instance.submitSafeTransaction(
          safeId: payload['safeId'] as int,
          transactionType: payload['transactionType'] as String,
          amount: (payload['amount'] as num).toDouble(),
          category: payload['category'] as String? ?? 'general',
          description: payload['description'] as String?,
          userId: payload['userId'] as int?,
          referenceType: payload['referenceType'] as String?,
          referenceId: payload['referenceId'] as int?,
       );
       return {'id': recordId};
    }

    if (table == 'shifts' && operation == 'close') {
       await ServerProxy.instance.closeShift(
          payload['shiftId'] as int? ?? 0,
          (payload['actualCash'] as num?)?.toDouble() ?? 0,
          notes: payload['notes'] as String?,
       );
       return {'id': recordId};
    }

    switch (operation) {
      case 'insert':
        final data = await client.from(table).insert(payload).select().maybeSingle();
        return data ?? {'id': recordId};
      case 'update':
        final data = await client
            .from(table)
            .update(payload)
            .eq('id', recordId)
            .select()
            .maybeSingle();
        return data ?? {'id': recordId};
      case 'delete':
        await client.from(table).delete().eq('id', recordId);
        return {'id': recordId}; // Return something to indicate success
      case 'upsert':
        final data = await client.from(table).upsert(payload).select().maybeSingle();
        return data ?? {'id': recordId};
      default:
        throw Exception('Unknown operation style: $operation');
    }
  }
}

/// Provider for the Sync Worker state
final syncWorkerProvider = NotifierProvider<SyncWorker, SyncState>(() {
  return SyncWorker();
});
