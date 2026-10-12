// اختبار «سقف حجم الملفات» (ratchet) على lib/**/*.dart:
//  (أ) أي ملف > 30KB (بنهايات LF) يجب أن يكون مسجَّلًا في file_size_baseline.txt.
//  (ب) الملف المسجَّل لا يجوز أن يزيد عن حجمه المسجَّل.
//  (ج) تصغير الملف أو حذفه أو نزوله تحت 30KB لا يفشل الاختبار؛
//      نظّف الملف الأساسي بـ: dart run tool/update_file_size_baseline.dart
// المُستثنى: *.g.dart, *.freezed.dart, *.gr.dart, *.mocks.dart والملفات ذات ترويسة GENERATED CODE.
// الحجم بعد حذف \r ليتطابق على Windows وLinux.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const int kLimit = 30 * 1024;

int _lfSize(List<int> bytes) {
  var n = 0;
  for (final b in bytes) {
    if (b != 0x0D) n++;
  }
  return n;
}

void main() {
  test('سقف حجم الملفات: لا نمو للكبيرة ولا ملفات جديدة فوق 30KB', () {
    final baselineFile = File('test/structural/file_size_baseline.txt');
    expect(baselineFile.existsSync(), isTrue,
        reason: 'الملف الأساسي file_size_baseline.txt مفقود');
    final baseline = <String, int>{};
    for (final line in baselineFile.readAsLinesSync()) {
      final t = line.trim();
      if (t.isEmpty) continue;
      final i = t.lastIndexOf(' ');
      baseline[t.substring(0, i)] = int.parse(t.substring(i + 1));
    }

    final problems = <String>[];
    for (final e in Directory('lib').listSync(recursive: true)) {
      if (e is! File || !e.path.endsWith('.dart')) continue;
      final rel = e.path.replaceAll('\\', '/');
      if (rel.endsWith('.g.dart') ||
          rel.endsWith('.freezed.dart') ||
          rel.endsWith('.gr.dart') ||
          rel.endsWith('.mocks.dart')) {
        continue;
      }
      final bytes = e.readAsBytesSync();
      final head = String.fromCharCodes(
          bytes.length > 2048 ? bytes.sublist(0, 2048) : bytes);
      if (head.contains('GENERATED CODE')) continue;
      final size = _lfSize(bytes);
      if (size <= kLimit) continue;
      final allowed = baseline[rel];
      if (allowed == null) {
        problems.add('$rel: ملف جديد/كبير تجاوز 30KB (حجمه $size بايت)؛ '
            'قسّمه حسب المسؤولية (راجع docs/ARCHITECTURE-MAP.md) '
            'ولا تضفه إلى الملف الأساسي.');
      } else if (size > allowed) {
        problems.add(
            '$rel: الحجم الحالي $size بايت يتجاوز المسموح $allowed بايت؛ '
            'لا تُكبّر الملفات الكبيرة، انقل المنطق الجديد إلى ملف مستقل.');
      }
    }
    expect(problems, isEmpty, reason: '\n${problems.join('\n')}');
  });
}
