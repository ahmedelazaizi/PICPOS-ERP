/// Printing with a remembered printer and a persisted retry queue (adapted
/// from mobile/lib/printing/print_service.dart, decoupled from the rep
/// app's controller). Printing never blocks or fails a sale: a job that
/// cannot reach the printer is queued with the reason and retried later.
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../store/local_store.dart';
import 'escpos.dart';
import 'printer_transport.dart';
import 'receipt.dart';

class PrinterSettings {
  const PrinterSettings({
    this.kind = PrinterKind.bluetooth,
    this.address,
    this.name,
    this.paper = PaperWidth.mm80,
    this.printOnSave = true,
    this.kickDrawerOnCash = false,
  });
  final PrinterKind kind;
  final String? address;
  final String? name;
  final PaperWidth paper;
  final bool printOnSave;

  /// Desktop drawer policy: open the drawer after a cash payment.
  final bool kickDrawerOnCash;

  bool get hasPrinter => (address ?? '').isNotEmpty;

  PrinterSettings copyWith({
    PrinterKind? kind,
    String? address,
    String? name,
    PaperWidth? paper,
    bool? printOnSave,
    bool? kickDrawerOnCash,
  }) =>
      PrinterSettings(
        kind: kind ?? this.kind,
        address: address ?? this.address,
        name: name ?? this.name,
        paper: paper ?? this.paper,
        printOnSave: printOnSave ?? this.printOnSave,
        kickDrawerOnCash: kickDrawerOnCash ?? this.kickDrawerOnCash,
      );

  Map<String, Object?> toJson() => {
        'kind': kind.name,
        'address': address,
        'name': name,
        'paper': paper.name,
        'printOnSave': printOnSave,
        'kickDrawerOnCash': kickDrawerOnCash,
      };

  factory PrinterSettings.fromJson(Map<String, Object?> m) => PrinterSettings(
        kind: m['kind'] == 'network' ? PrinterKind.network : PrinterKind.bluetooth,
        address: m['address'] as String?,
        name: m['name'] as String?,
        paper: PaperWidth.byName(m['paper'] as String?),
        printOnSave: m['printOnSave'] != false,
        kickDrawerOnCash: m['kickDrawerOnCash'] == true,
      );
}

/// A document waiting for the printer.
class PrintJob {
  PrintJob({required this.id, required this.label, required this.queuedAt, this.attempts = 1, this.lastError});
  final String id;

  /// What the user sees (document number).
  final String label;
  final DateTime queuedAt;
  int attempts;
  String? lastError;

  Map<String, Object?> toJson() => {
        'id': id,
        'label': label,
        'queuedAt': queuedAt.millisecondsSinceEpoch,
        'attempts': attempts,
        'lastError': lastError,
      };

  factory PrintJob.fromJson(Map<String, Object?> m) => PrintJob(
        id: m['id'] as String,
        label: '${m['label'] ?? ''}',
        queuedAt: DateTime.fromMillisecondsSinceEpoch(m['queuedAt'] as int),
        attempts: (m['attempts'] as int?) ?? 1,
        lastError: m['lastError'] as String?,
      );
}

enum PrintStatus { printed, queued }

class PrintOutcome {
  const PrintOutcome(this.status, this.label, [this.error]);
  final PrintStatus status;
  final String label;

  /// [PrinterException.code] or `renderFailed` when queued.
  final String? error;
}

/// Builds the printer bytes of a job for a paper width.
typedef PrintJobBuilder = Future<Uint8List> Function(PaperWidth paper);

class PrintService extends ChangeNotifier {
  PrintService({
    required this.store,
    required List<PrinterTransport> transports,
    this.timeout = const Duration(seconds: 25),
    DateTime Function()? clock,
  })  : transports = {for (final t in transports) t.kind: t},
        _now = clock ?? DateTime.now;

  final LocalStore store;
  final Map<PrinterKind, PrinterTransport> transports;
  final Duration timeout;
  final DateTime Function() _now;

  static const _settingsKey = 'printer';
  static const _queueKey = 'printQueue';

  PrinterSettings settings = const PrinterSettings();
  List<PrintJob> queue = [];

  /// Serializes jobs: one printer connection at a time.
  Future<void> _lock = Future.value();

  Future<void> init() async {
    final s = await store.getKv(_settingsKey);
    if (s != null) settings = PrinterSettings.fromJson((jsonDecode(s) as Map).cast<String, Object?>());
    final q = await store.getKv(_queueKey);
    queue = q == null ? [] : [for (final j in jsonDecode(q) as List) PrintJob.fromJson((j as Map).cast<String, Object?>())];
    notifyListeners();
  }

  Future<void> saveSettings(PrinterSettings s) async {
    settings = s;
    await store.setKv(_settingsKey, jsonEncode(s.toJson()));
    notifyListeners();
  }

  Future<void> _saveQueue() async {
    await store.setKv(_queueKey, jsonEncode([for (final j in queue) j.toJson()]));
    notifyListeners();
  }

  PrinterTransport _transport() {
    final t = transports[settings.kind];
    if (t == null || !settings.hasPrinter) throw PrinterException('noPrinter');
    return t;
  }

  Future<T> _serial<T>(Future<T> Function() body) {
    final done = Completer<T>();
    _lock = _lock.then((_) async {
      try {
        done.complete(await body());
      } catch (e, st) {
        done.completeError(e, st);
      }
    });
    return done.future;
  }

  /// Prints job [id]; never throws. On failure the job is queued (or its
  /// attempt count raised) with the reason.
  Future<PrintOutcome> print(String id, String label, PrintJobBuilder build) => _serial(() async {
        try {
          final t = _transport();
          final bytes = await build(settings.paper);
          await t.send(settings.address!, bytes).timeout(timeout);
          queue.removeWhere((j) => j.id == id);
          await _saveQueue();
          return PrintOutcome(PrintStatus.printed, label);
        } catch (err) {
          final code = err is PrinterException ? err.code : (err is TimeoutException ? 'timeout' : 'renderFailed');
          final j = queue.where((j) => j.id == id).firstOrNull;
          if (j == null) {
            queue.add(PrintJob(id: id, label: label, queuedAt: _now(), lastError: code));
          } else {
            j
              ..attempts += 1
              ..lastError = code;
          }
          try {
            await _saveQueue();
          } catch (saveErr) {
            debugPrint('print queue not saved: $saveErr');
          }
          return PrintOutcome(PrintStatus.queued, label, code);
        }
      });

  /// Retries queued jobs in order; [rebuild] returns `null` for a job whose
  /// document no longer exists (it is dropped from the queue).
  Future<int> retryQueue(PrintJobBuilder? Function(String id) rebuild) async {
    var printed = 0;
    for (final j in List.of(queue)) {
      final b = rebuild(j.id);
      if (b == null) {
        queue.remove(j);
        await _saveQueue();
        continue;
      }
      if ((await print(j.id, j.label, b)).status == PrintStatus.printed) printed++;
    }
    return printed;
  }

  Future<void> discardJob(String id) async {
    queue.removeWhere((j) => j.id == id);
    await _saveQueue();
  }

  /// Opens the cash drawer through the receipt printer (`ESC p 0 25 250`).
  /// Throws [PrinterException] so the caller can tell the cashier why.
  Future<void> openDrawer() => _serial(() => _transport().send(settings.address!, EscPos.drawerJob()).timeout(timeout));

  /// Sends a test page; throws [PrinterException].
  Future<void> testPrint(PrintJobBuilder build) =>
      _serial(() async => _transport().send(settings.address!, await build(settings.paper)).timeout(timeout));
}
