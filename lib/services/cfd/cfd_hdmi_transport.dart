// ═══════════════════════════════════════════════════════════════════════════
// CFD HDMI TRANSPORT — Second screen transport for HDMI/DisplayPort monitors
// ═══════════════════════════════════════════════════════════════════════════

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:picpos_erp/core/constants/app_constants.dart';
import 'package:flutter/foundation.dart';
import 'cfd_transport.dart';

/// HDMI/Second Monitor transport for Customer Facing Display.
///
/// Opens a secondary Flutter window on the extended display and renders
/// a rich CFD UI showing the cart contents, totals, and branding.
///
/// Uses Win32 APIs via dart:ffi to detect monitors and position the window.
/// Communication between the main window and CFD window is done through
/// a lightweight local HTTP server on localhost.
class CfdHdmiTransport implements CfdTransport {
  bool _connected = false;
  int _monitorIndex = 1; // Default to second monitor
  StreamController<CfdCartData?>? _dataController;

  // Internal lightweight server for inter-window communication
  HttpServer? _localServer;
  CfdCartData? _lastCartData;
  bool _isIdle = true;

  static const int _localPort = 52847; // Random high port for internal use

  @override
  CfdConnectionType get type => CfdConnectionType.hdmi;

  @override
  bool get isConnected => _connected;

  @override
  String get statusText {
    if (_connected) return 'متصل (شاشة $_monitorIndex)';
    return 'غير متصل';
  }

  /// Get available monitors
  static List<Map<String, dynamic>> getAvailableMonitors() {
    // Use Flutter's display API to detect monitors
    final displays = ui.PlatformDispatcher.instance.displays.toList();
    return displays.asMap().entries.map((e) {
      final d = e.value;
      return {
        'index': e.key,
        'width': d.size.width ~/ d.devicePixelRatio,
        'height': d.size.height ~/ d.devicePixelRatio,
        'label': 'شاشة ${e.key + 1} (${d.size.width ~/ d.devicePixelRatio}x${d.size.height ~/ d.devicePixelRatio})',
      };
    }).toList();
  }

  @override
  Future<bool> connect(Map<String, dynamic> config) async {
    _monitorIndex = config['monitorIndex'] as int? ?? 1;

    try {
      await disconnect();

      // Start local data server for inter-window communication
      _localServer = await HttpServer.bind(
        InternetAddress.loopbackIPv4,
        _localPort,
        shared: true,
      );

      _localServer!.listen(_handleRequest);
      _connected = true;
      _isIdle = true;

      // Launch the CFD window in the user's default browser on the second monitor
      // This approach is simpler and more reliable than managing multi-window Flutter
      await _launchCfdWindow();

      debugPrint('[CFD:HDMI] Transport connected on monitor $_monitorIndex');
      return true;
    } catch (e) {
      debugPrint('[CFD:HDMI] Failed to connect: $e');
      _connected = false;
      return false;
    }
  }

  void _handleRequest(HttpRequest request) async {
    // Add CORS headers
    request.response.headers.add('Access-Control-Allow-Origin', '*');
    request.response.headers.add('Access-Control-Allow-Methods', 'GET');

    if (request.uri.path == '/api/cfd/data') {
      // Return current cart state as JSON
      request.response.headers.contentType = ContentType.json;
      if (_isIdle || _lastCartData == null) {
        request.response.write(json.encode({'type': 'idle'}));
      } else {
        request.response.write(json.encode(_lastCartData!.toJson()));
      }
      await request.response.close();
    } else if (request.uri.path == '/api/cfd/stream') {
      // SSE stream for real-time updates
      request.response.headers.set('Content-Type', 'text/event-stream');
      request.response.headers.set('Cache-Control', 'no-cache');
      request.response.headers.set('Connection', 'keep-alive');

      // Send current state immediately
      if (_isIdle || _lastCartData == null) {
        request.response.write('data: {"type": "idle"}\n\n');
      } else {
        request.response.write(
          'data: ${json.encode(_lastCartData!.toJson())}\n\n',
        );
      }

      // Keep connection open and send updates
      _dataController = StreamController<CfdCartData?>();
      await for (final data in _dataController!.stream) {
        if (data == null) {
          request.response.write('data: {"type": "idle"}\n\n');
        } else {
          request.response.write(
            'data: ${json.encode(data.toJson())}\n\n',
          );
        }
      }
    } else if (request.uri.path == '/health') {
      // Health check endpoint
      request.response.headers.contentType = ContentType.json;
      request.response.write(json.encode({'status': 'ok'}));
      await request.response.close();
    } else if (request.uri.path == '/' || request.uri.path == '/cfd') {
      // Serve the CFD HTML page
      request.response.headers.contentType = ContentType.html;
      request.response.write(_buildCfdHtml());
      await request.response.close();
    } else {
      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
    }
  }

  @override
  void sendCartUpdate(CfdCartData cartData) {
    _lastCartData = cartData;
    _isIdle = false;
    _dataController?.add(cartData);
  }

  @override
  void sendIdle() {
    _lastCartData = null;
    _isIdle = true;
    _dataController?.add(null);
  }

  @override
  Future<void> disconnect() async {
    _connected = false;
    _dataController?.close();
    _dataController = null;
    await _localServer?.close(force: true);
    _localServer = null;
    debugPrint('[CFD:HDMI] Transport disconnected');
  }

  Future<void> _launchCfdWindow() async {
    const url = 'http://localhost:$_localPort/cfd';
    try {
      if (Platform.isWindows) {
        // Try Chrome app mode (no toolbar, clean kiosk)
        var result = await Process.run('cmd', ['/c', 'start', 'chrome', '--app=$url', '--start-fullscreen']);
        if (result.exitCode != 0) {
          // Try Microsoft Edge
          result = await Process.run('cmd', ['/c', 'start', 'msedge', '--app=$url', '--start-fullscreen']);
        }
        if (result.exitCode != 0) {
          // Fallback: default browser
          await Process.run('cmd', ['/c', 'start', '', url]);
        }
      }
      debugPrint('[CFD:HDMI] Browser launched: $url');
    } catch (e) {
      debugPrint('[CFD:HDMI] Failed to launch browser: $e');
    }
  }

  /// Build the CFD HTML page — same beautiful design as the network version
  /// but connects to localhost for data
  String _buildCfdHtml() {
    return '''
<!DOCTYPE html>
<html lang="ar" dir="rtl">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>شاشة العميل</title>
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body {
            font-family: 'Segoe UI', Tahoma, sans-serif;
            background: linear-gradient(135deg, #0a0a1a, #1a1a2e, #16213e);
            color: #fff;
            height: 100vh;
            overflow: hidden;
            display: flex;
            flex-direction: column;
        }
        .header {
            padding: 15px 25px;
            background: rgba(0,0,0,0.4);
            border-bottom: 2px solid rgba(99,102,241,0.3);
            display: flex;
            justify-content: space-between;
            align-items: center;
        }
        .header h1 { font-size: 1.4em; color: #a5b4fc; }
        .company-name { font-size: 0.9em; color: rgba(255,255,255,0.6); }
        .status {
            font-size: 0.8em; padding: 4px 12px;
            border-radius: 20px;
            background: rgba(34,197,94,0.2); color: #4ade80;
        }
        .status.disconnected { background: rgba(239,68,68,0.2); color: #f87171; }
        .table-header {
            display: flex; justify-content: space-between;
            padding: 10px 25px;
            background: rgba(99,102,241,0.1);
            border-bottom: 1px solid rgba(99,102,241,0.2);
            font-size: 0.85em; font-weight: 600;
            color: rgba(255,255,255,0.5);
        }
        .table-header .th-name { flex: 1; }
        .table-header .th-qty { min-width: 60px; text-align: center; }
        .table-header .th-price { min-width: 100px; text-align: center; }
        .table-header .th-total { min-width: 100px; text-align: left; }
        .items-container {
            flex: 1; overflow-y: auto; padding: 0 25px;
            scroll-behavior: smooth;
        }
        .item-row {
            display: flex; justify-content: space-between; align-items: center;
            padding: 12px 0; border-bottom: 1px solid rgba(255,255,255,0.05);
            animation: fadeIn 0.3s ease;
            transition: background 0.3s ease;
        }
        .item-row.last-item {
            animation: fadeIn 0.3s ease, glowPulse 1.5s ease-in-out 2;
            background: rgba(99,102,241,0.1);
            border-radius: 6px;
            padding: 12px 8px;
        }
        @keyframes fadeIn {
            from { opacity: 0; transform: translateX(-10px); }
            to { opacity: 1; transform: translateX(0); }
        }
        @keyframes glowPulse {
            0%, 100% { box-shadow: none; background: rgba(99,102,241,0.1); }
            50% { box-shadow: 0 0 15px rgba(99,102,241,0.3); background: rgba(99,102,241,0.2); }
        }
        .item-name { flex: 1; font-size: 1.1em; }
        .item-qty { min-width: 60px; text-align: center; color: rgba(255,255,255,0.6); }
        .item-price { min-width: 100px; text-align: center; color: rgba(255,255,255,0.7); }
        .item-total { min-width: 100px; text-align: left; color: #4ade80; font-weight: 600; }
        .totals {
            padding: 15px 25px;
            background: rgba(0,0,0,0.5);
            border-top: 2px solid rgba(99,102,241,0.3);
        }
        .total-row {
            display: flex; justify-content: space-between;
            padding: 5px 0; font-size: 1em;
            color: rgba(255,255,255,0.7);
        }
        .total-row.grand {
            font-size: 1.5em; font-weight: 700; color: #fff;
            padding-top: 10px; border-top: 1px solid rgba(255,255,255,0.1);
            margin-top: 5px;
        }
        .total-row.grand .amount { color: #4ade80; }
        .payment-section {
            margin-top: 8px; padding-top: 8px;
            border-top: 1px dashed rgba(255,255,255,0.15);
        }
        .payment-section .total-row { color: rgba(255,255,255,0.8); }
        .payment-section .change-row { color: #fbbf24; font-weight: 600; }
        .thank-you {
            text-align: center; padding: 8px 0 4px;
            font-size: 1.1em; color: #a5b4fc;
            animation: fadeIn 0.5s ease;
        }
        .idle-screen {
            display: none; flex: 1; justify-content: center;
            align-items: center; flex-direction: column;
            text-align: center; padding: 40px;
        }
        .idle-screen.active { display: flex; }
        .idle-screen h2 {
            font-size: 2.5em;
            background: linear-gradient(90deg, #667eea, #764ba2);
            -webkit-background-clip: text; -webkit-text-fill-color: transparent;
            margin-bottom: 15px;
        }
        .idle-screen p { color: rgba(255,255,255,0.5); font-size: 1.2em; }
        .cart-view { display: none; flex-direction: column; flex: 1; }
        .cart-view.active { display: flex; }
    </style>
</head>
<body>
    <div class="header">
        <div>
            <h1>شاشة العميل</h1>
            <span class="company-name" id="companyName"></span>
        </div>
        <span class="status" id="status">متصل</span>
    </div>
    <div class="idle-screen active" id="idle">
        <h2>مرحباً بكم</h2>
        <p>في انتظار الطلبات</p>
    </div>
    <div class="cart-view" id="cart">
        <div class="table-header">
            <span class="th-name">الصنف</span>
            <span class="th-qty">الكمية</span>
            <span class="th-price">السعر</span>
            <span class="th-total">الإجمالي</span>
        </div>
        <div class="items-container" id="items"></div>
        <div class="totals" id="totals"></div>
    </div>
    <script>
        const itemsEl = document.getElementById('items');
        const totalsEl = document.getElementById('totals');
        const idleEl = document.getElementById('idle');
        const cartEl = document.getElementById('cart');
        const statusEl = document.getElementById('status');

        function connect() {
            const es = new EventSource('/api/cfd/stream');
            es.onopen = () => {
                statusEl.textContent = 'متصل';
                statusEl.classList.remove('disconnected');
            };
            es.onmessage = (e) => {
                try {
                    const data = JSON.parse(e.data);
                    if (data.type === 'idle' || !data.items || data.items.length === 0) {
                        showIdle();
                    } else {
                        showCart(data);
                    }
                } catch (err) { console.error('Parse error:', err); }
            };
            es.onerror = () => {
                statusEl.textContent = 'غير متصل';
                statusEl.classList.add('disconnected');
                es.close();
                setTimeout(connect, 3000);
            };
        }

        function showIdle() {
            idleEl.classList.add('active');
            cartEl.classList.remove('active');
        }

        function showCart(data) {
            idleEl.classList.remove('active');
            cartEl.classList.add('active');

            const lastIndex = data.items.length - 1;
            itemsEl.innerHTML = data.items.map((i, idx) =>
                '<div class="item-row' + (idx === lastIndex ? ' last-item' : '') + '">' +
                '<span class="item-name">' + i.name + '</span>' +
                '<span class="item-qty">\u00d7' + i.qty + '</span>' +
                '<span class="item-price">' + Number(i.price || 0).toFixed(3) + '</span>' +
                '<span class="item-total">' + Number(i.total).toFixed(3) + '</span>' +
                '</div>'
            ).join('');

            // Auto-scroll to the latest item
            itemsEl.scrollTop = itemsEl.scrollHeight;

            let totalsHtml = '';
            if (data.customer) {
                totalsHtml += '<div class="total-row"><span>العميل</span><span>' + data.customer + '</span></div>';
            }
            if (data.subtotal !== undefined) {
                totalsHtml += '<div class="total-row"><span>المجموع</span><span>' + Number(data.subtotal).toFixed(3) + '</span></div>';
            }
            if (data.discount && data.discount > 0) {
                totalsHtml += '<div class="total-row"><span>الخصم</span><span>-' + Number(data.discount).toFixed(2) + '%</span></div>';
            }
            if (data.tax && data.tax > 0) {
                totalsHtml += '<div class="total-row"><span>الضريبة</span><span>' + Number(data.tax).toFixed(3) + '</span></div>';
            }
            totalsHtml += '<div class="total-row grand"><span>الإجمالي</span><span class="amount">' + Number(data.total).toFixed(3) + ' ${AppConstants.currencySymbol}</span></div>';

            // Payment section
            if (data.paid && data.paid > 0) {
                totalsHtml += '<div class="payment-section">';
                totalsHtml += '<div class="total-row"><span>المدفوع</span><span>' + Number(data.paid).toFixed(3) + '</span></div>';
                const change = data.paid - data.total;
                if (change >= 0) {
                    totalsHtml += '<div class="total-row change-row"><span>الباقي</span><span>' + Number(change).toFixed(3) + '</span></div>';
                }
                totalsHtml += '</div>';
                totalsHtml += '<div class="thank-you">شكراً لتسوقكم</div>';
            }

            totalsEl.innerHTML = totalsHtml;
        }

        connect();
    </script>
</body>
</html>
''';
  }
}
