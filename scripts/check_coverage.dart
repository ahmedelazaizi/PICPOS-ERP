#!/usr/bin/env dart
// ISS-QA-01: Coverage gate script.
// Usage: dart run scripts/check_coverage.dart [--threshold=50]
// Parses coverage/lcov.info and fails if domain layer coverage < threshold.

import 'dart:io';

void main(List<String> args) {
  final thresholdArg = args
      .where((a) => a.startsWith('--threshold='))
      .map((a) => double.tryParse(a.split('=').last))
      .whereType<double>()
      .firstOrNull;
  final threshold = thresholdArg ?? 50.0;

  final lcovFile = File('coverage/lcov.info');
  if (!lcovFile.existsSync()) {
    stderr.writeln('[coverage] ERROR: coverage/lcov.info not found.');
    stderr.writeln('[coverage] Run: flutter test --coverage');
    exit(1);
  }

  int totalLf = 0;
  int totalLh = 0;
  String currentFile = '';
  int fileLf = 0;
  int fileLh = 0;

  for (final line in lcovFile.readAsLinesSync()) {
    if (line.startsWith('SF:')) {
      currentFile = line.substring(3);
      fileLf = 0;
      fileLh = 0;
    } else if (line.startsWith('LF:')) {
      fileLf = int.tryParse(line.substring(3)) ?? 0;
    } else if (line.startsWith('LH:')) {
      fileLh = int.tryParse(line.substring(3)) ?? 0;
    } else if (line == 'end_of_record') {
      // Only count domain entities and usecases (pure business logic)
      final isDomainLayer = currentFile.contains('domain${Platform.pathSeparator}entities') ||
          currentFile.contains('domain${Platform.pathSeparator}usecases') ||
          currentFile.contains('domain/entities') ||
          currentFile.contains('domain/usecases');
      if (isDomainLayer) {
        totalLf += fileLf;
        totalLh += fileLh;
      }
    }
  }

  if (totalLf == 0) {
    stderr.writeln('[coverage] ERROR: no domain layer lines found in lcov.info.');
    exit(1);
  }

  final coverage = (100.0 * totalLh / totalLf);
  final pass = coverage >= threshold;

  stdout.writeln('[coverage] Domain layer (entities + usecases):');
  stdout.writeln('[coverage]   Lines found : $totalLf');
  stdout.writeln('[coverage]   Lines hit   : $totalLh');
  stdout.writeln('[coverage]   Coverage    : ${coverage.toStringAsFixed(1)}%');
  stdout.writeln('[coverage]   Threshold   : ${threshold.toStringAsFixed(0)}%');
  stdout.writeln('[coverage]   Result      : ${pass ? "PASS ✓" : "FAIL ✗"}');

  if (!pass) {
    stderr.writeln(
      '[coverage] FAIL: domain coverage ${coverage.toStringAsFixed(1)}% < ${threshold.toStringAsFixed(0)}% threshold.',
    );
    exit(1);
  }
}
