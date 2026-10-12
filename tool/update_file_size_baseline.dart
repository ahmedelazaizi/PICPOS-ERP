// يعيد توليد test/structural/file_size_baseline.txt من الحالة الحالية دون رفع أي حد:
//  - الملفات المسجَّلة: يُكتب الأدنى بين الحجم الحالي والمسجَّل.
//  - الملفات التي صارت <= 30KB أو حُذفت: تُسقَط.
//  - ملف جديد > 30KB غير مسجَّل: يفشل السكربت (exit 1) ما لم يُمرَّر --init (للبذر مرة واحدة).
// الحجم يُحسب بنهايات LF (بعد حذف \r) ليتطابق على Windows وLinux.
// التشغيل: dart run tool/update_file_size_baseline.dart [--init]
import 'dart:io';

const int kLimit = 30 * 1024;
const String kBaseline = 'test/structural/file_size_baseline.txt';

bool _isGeneratedName(String p) =>
    p.endsWith('.g.dart') ||
    p.endsWith('.freezed.dart') ||
    p.endsWith('.gr.dart') ||
    p.endsWith('.mocks.dart');

int _lfSize(List<int> bytes) {
  var n = 0;
  for (final b in bytes) {
    if (b != 0x0D) n++;
  }
  return n;
}

bool _hasGeneratedHeader(List<int> bytes) {
  final head = String.fromCharCodes(
      bytes.length > 2048 ? bytes.sublist(0, 2048) : bytes);
  return head.contains('GENERATED CODE');
}

void main(List<String> args) {
  final init = args.contains('--init');
  final root = Directory('lib');
  if (!root.existsSync()) {
    stderr.writeln('شغّل السكربت من جذر المشروع (lib/ غير موجود).');
    exit(2);
  }
  final old = <String, int>{};
  final f = File(kBaseline);
  if (f.existsSync()) {
    for (final line in f.readAsLinesSync()) {
      final t = line.trim();
      if (t.isEmpty) continue;
      final i = t.lastIndexOf(' ');
      old[t.substring(0, i)] = int.parse(t.substring(i + 1));
    }
  }
  final out = <String, int>{};
  final unregistered = <String>[];
  for (final e in root.listSync(recursive: true, followLinks: false)) {
    if (e is! File || !e.path.endsWith('.dart')) continue;
    final rel = e.path.replaceAll('\\', '/');
    if (_isGeneratedName(rel)) continue;
    final bytes = e.readAsBytesSync();
    if (_hasGeneratedHeader(bytes)) continue;
    final size = _lfSize(bytes);
    if (size <= kLimit) continue;
    final prev = old[rel];
    if (prev != null) {
      out[rel] = size < prev ? size : prev;
    } else if (init) {
      out[rel] = size;
    } else {
      unregistered.add('$rel ($size)');
    }
  }
  if (unregistered.isNotEmpty) {
    stderr.writeln('ملفات جديدة تتجاوز 30KB وغير مسجَّلة — قسّمها حسب المسؤولية '
        '(docs/ARCHITECTURE-MAP.md) ولا تضفها إلى الملف الأساسي:');
    for (final u in unregistered) {
      stderr.writeln('  $u');
    }
    exit(1);
  }
  final keys = out.keys.toList()..sort();
  final sb = StringBuffer();
  for (final k in keys) {
    sb.write('$k ${out[k]}\n');
  }
  f.writeAsStringSync(sb.toString());
  final total = out.values.fold<int>(0, (a, b) => a + b);
  stdout.writeln('الملف الأساسي: ${keys.length} ملفًا، الإجمالي $total بايت.');
}
