// ═══════════════════════════════════════════════════════════════════════════
// CFD NETWORK TRANSPORT — SSE-based transport for network displays
// ═══════════════════════════════════════════════════════════════════════════

import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'cfd_transport.dart';

/// Network transport for CFD using Server-Sent Events (SSE).
///
/// This is the original/existing transport refactored into the transport pattern.
/// It broadcasts cart data to all connected SSE clients via the HTTP server.
class CfdNetworkTransport implements CfdTransport {
  // Active SSE stream controllers (one per connected client)
  final _clients = <StreamController<String>>[];
  bool _connected = false;

  @override
  CfdConnectionType get type => CfdConnectionType.network;

  @override
  bool get isConnected => _connected;

  @override
  String get statusText =>
      _connected ? 'متصل (${_clients.length} عميل)' : 'غير متصل';

  @override
  Future<bool> connect(Map<String, dynamic> config) async {
    // Network transport is always "connected" — it depends on the HTTP server
    // being active (managed by NetworkService).
    _connected = true;
    debugPrint('[CFD:Network] Transport activated');
    return true;
  }

  @override
  void sendCartUpdate(CfdCartData cartData, [CfdDisplayConfig? config]) {
    if (_clients.isEmpty) return;

    final data = json.encode(cartData.toJson(config));
    final sseEvent = 'data: $data\n\n';

    for (final controller in _clients) {
      if (!controller.isClosed) {
        controller.add(sseEvent);
      }
    }
  }

  @override
  void sendIdle([CfdDisplayConfig? config]) {
    final c = config ?? CfdDisplayConfig.defaultConfig;
    final idleData = json.encode({
      'type': 'idle',
      'welcomeMessage': c.welcomeMessage,
      'welcomeSubMessage': c.welcomeSubMessage,
    });
    final sseEvent = 'data: $idleData\n\n';
    for (final controller in _clients) {
      if (!controller.isClosed) {
        controller.add(sseEvent);
      }
    }
  }

  @override
  Future<void> disconnect() async {
    _connected = false;
    for (final controller in _clients) {
      controller.close();
    }
    _clients.clear();
    debugPrint('[CFD:Network] Transport deactivated');
  }

  // ─── SSE Client Management ────────────────────────────────────────────

  /// Connect a new SSE client and return its stream.
  Stream<String> connectClient() {
    final controller = StreamController<String>();
    _clients.add(controller);

    debugPrint('[CFD:Network] Client connected. Total: ${_clients.length}');

    controller.done.then((_) {
      _clients.remove(controller);
      debugPrint(
        '[CFD:Network] Client disconnected. Total: ${_clients.length}',
      );
    });

    return controller.stream;
  }

  /// Number of currently connected SSE clients
  int get clientCount => _clients.length;
}
