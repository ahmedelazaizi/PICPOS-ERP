/// Receipt printing for the van: remembered default printer and paper width,
/// print-on-save, reprint, and a persistent retry queue. Printing never
/// blocks or fails a sale — the document is already saved in the outbox;
/// a print that cannot reach the printer is queued with the reason and can
/// be retried (ARCHITECTURE-I §10).
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../data/local_store.dart';
import '../state/app_controller.dart';
import 'printer_transport.dart';
import 'receipt_composer.dart';
import 'receipt_model.dart';
import 'receipt_renderer.dart';

class PrinterSettings {
  const PrinterSettings({this.address, this.name, this.paper = PaperWidth.mm80, this.printOnSave = true});
  final String? address;
  final String? name;
  final PaperWidth paper;
  final bool printOnSave;

  bool get hasPrinter => (address ?? '').isNotEmpty;

  PrinterSettings copyWith({String? address, String? name, PaperWidth? paper, bool? printOnSave}) => PrinterSettings(
        address: address ?? this.address,
        name: name ?? this.name,
        paper: paper ?? this.paper,
        printOnSave: printOnSave ?? this.printOnSave,
      );

  Map<String, Object?> toJson() => {'address': address, 'name': name, 'paper': paper.name, 'printOnSave': printOnSave};
  factory PrinterSettings.fromJson(Map<String, Object?> m) => PrinterSettings(
        address: m['address'] as String?,
        name: m['name'] as String?,
        paper: PaperWidth.byName(m['paper'] as String?),
        printOnSave: m['printOnSave'] != false,
      );
}

/// A receipt waiting for the printer.
class PrintJob {
  PrintJob({required this.globalId, required this.kind, required this.number, required this.queuedAt, this.attempts = 1, this.lastError});
  final String globalId;
  final String kind;
  final String number;
  final DateTime queuedAt;
  int attempts;
  String? lastError;

  Map<String, Object?> toJson() => {
        'globalId': globalId,
        'kind': kind,
        'number': number,
        'queuedAt': queuedAt.millisecondsSinceEpoch,
        'attempts': attempts,
        'lastError': lastError,
      };
  factory PrintJob.fromJson(Map<String, Object?> m) => PrintJob(
        globalId: m['globalId'] as String,
        kind: m['kind'] as String,
        number: '${m['number'] ?? ''}',
        queuedAt: DateTime.fromMillisecondsSinceEpoch(m['queuedAt'] as int),
        attempts: (m['attempts'] as int?) ?? 1,
        lastError: m['lastError'] as String?,
      );
}

enum PrintStatus { printed, queued }

class PrintOutcome {
  const PrintOutcome(this.status, this.number, [this.error]);
  final PrintStatus status;
  final String number;

  /// [PrinterException.code] or `renderFailed` when queued.
  final String? error;
}

class PrintService extends ChangeNotifier {
  PrintService({
    required this.controller,
    required this.transport,
    ReceiptRasterizer? rasterizer,
    this.timeout = const Duration(seconds: 25),
  }) : rasterize = rasterizer ?? rasterizeReceipt;

  final AppController controller;
  final PrinterTransport transport;
  final ReceiptRasterizer rasterize;
  final Duration timeout;

  static const _settingsKey = 'printer';
  static const _queueKey = 'printQueue';

  PrinterSettings settings = const PrinterSettings();
  List<PrintJob> queue = [];

  /// Receipt language (follows the app language).
  String locale = 'ar';

  /// UI hook for a snackbar after each attempt.
  void Function(PrintOutcome outcome)? onOutcome;

  /// Serializes jobs: one Bluetooth socket at a time.
  Future<void> _lock = Future.value();

  Future<void> init() async {
    final s = await controller.store.getKv(_settingsKey);
    if (s != null) settings = PrinterSettings.fromJson((jsonDecode(s) as Map).cast<String, Object?>());
    final q = await controller.store.getKv(_queueKey);
    queue = q == null
        ? []
        : [for (final j in jsonDecode(q) as List) PrintJob.fromJson((j as Map).cast<String, Object?>())];
    notifyListeners();
  }

  /// Hooks print-on-save into the controller (called once at start-up).
  void attach() => controller.onDocumentSaved = onDocumentSaved;

  Future<void> saveSettings(PrinterSettings s) async {
    settings = s;
    await controller.store.setKv(_settingsKey, jsonEncode(s.toJson()));
    notifyListeners();
  }

  Future<void> _saveQueue() async {
    await controller.store.setKv(_queueKey, jsonEncode([for (final j in queue) j.toJson()]));
    notifyListeners();
  }

  Future<List<PrinterDevice>> discover() => transport.pairedDevices();

  /// Print-on-save: returns immediately; the print runs in the background.
  void onDocumentSaved(OutboxEntry e) {
    if (!settings.printOnSave || !kPrintableKinds.contains(e.kind)) return;
    unawaited(printEntry(e));
  }

  static String numberOf(OutboxEntry e) =>
      '${e.payload['number'] ?? '${e.payload['_bookPrefix'] ?? ''}${e.payload['bookNumber'] ?? ''}'}';

  /// Prints [e]; never throws. On failure the job is queued (or its attempt
  /// count raised) with the reason.
  Future<PrintOutcome> printEntry(OutboxEntry e, {bool reprint = false}) {
    final done = Completer<PrintOutcome>();
    _lock = _lock.then((_) async {
      PrintOutcome out;
      try {
        await _send(() async => ReceiptComposer(controller).compose(e, locale: locale, reprint: reprint));
        queue.removeWhere((j) => j.globalId == e.globalId);
        await _saveQueue();
        out = PrintOutcome(PrintStatus.printed, numberOf(e));
      } catch (err) {
        final code = err is PrinterException ? err.code : (err is TimeoutException ? 'timeout' : 'renderFailed');
        if (err is! PrinterException && err is! TimeoutException) debugPrint('print failed: $err');
        final j = queue.where((j) => j.globalId == e.globalId).firstOrNull;
        if (j == null) {
          queue.add(PrintJob(
              globalId: e.globalId, kind: e.kind, number: numberOf(e), queuedAt: DateTime.now(), lastError: code));
        } else {
          j
            ..attempts += 1
            ..lastError = code;
        }
        out = PrintOutcome(PrintStatus.queued, numberOf(e), code);
        try {
          await _saveQueue();
        } catch (saveErr) {
          debugPrint('print queue not saved: $saveErr');
        }
      }
      done.complete(out);
      try {
        onOutcome?.call(out);
      } catch (_) {
        // A failing UI hook never affects printing.
      }
    });
    return done.future;
  }

  Future<void> _send(Future<Receipt> Function() build) async {
    final s = settings;
    if (!s.hasPrinter) throw PrinterException('noPrinter');
    final receipt = await build();
    final bytes = await rasterize(receipt, s.paper);
    await transport.send(s.address!, bytes).timeout(timeout);
  }

  /// Retries every queued job in order; returns how many printed.
  Future<int> retryQueue() async {
    var printed = 0;
    final all = {for (final e in await controller.store.outbox()) e.globalId: e};
    for (final j in List.of(queue)) {
      final e = all[j.globalId];
      if (e == null) {
        queue.remove(j);
        await _saveQueue();
        continue;
      }
      if ((await printEntry(e)).status == PrintStatus.printed) printed++;
    }
    return printed;
  }

  Future<void> discardJob(String globalId) async {
    queue.removeWhere((j) => j.globalId == globalId);
    await _saveQueue();
  }

  /// Test page; throws [PrinterException] so the settings screen can show why.
  Future<void> testPrint() async {
    final b = ReceiptBuilder(ReceiptComposer(controller).company, locale: locale);
    await _send(() async => b.test(settings.paper));
  }

  /// Documents that have a receipt, newest first (reprint from history).
  Future<List<OutboxEntry>> history() async =>
      (await controller.store.outbox()).where((e) => kPrintableKinds.contains(e.kind)).toList().reversed.toList();
}
