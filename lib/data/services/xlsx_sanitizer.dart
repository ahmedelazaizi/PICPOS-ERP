import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

/// Excel (the real app) sometimes re-declares a BUILT-IN number format id
/// (e.g. 43, the accounting format) inside `xl/styles.xml` as a custom
/// `<numFmt numFmtId="43" .../>`. `package:excel` rejects that with
/// "custom numFmtId starts at 164 but found a value of 43".
///
/// This strips every `<numFmt>` whose id is < 164 (the built-in range). Cell
/// styles that reference those ids keep working because ids < 164 resolve to
/// built-ins. Only `xl/styles.xml` is touched; every other zip entry is copied
/// as is. Never throws: on any problem (not a zip, no styles.xml, nothing to
/// change, malformed content) the ORIGINAL bytes are returned.
Uint8List? sanitizeXlsxBytes(Uint8List? bytes) {
  if (bytes == null) return null;
  try {
    final archive = ZipDecoder().decodeBytes(bytes);
    final styles = archive.findFile('xl/styles.xml');
    if (styles == null) return bytes;
    final xml = utf8.decode(styles.content as List<int>);
    final fixed = stripBuiltInNumFmts(xml);
    if (fixed == xml) return bytes;

    final out = Archive();
    for (final f in archive.files) {
      if (identical(f, styles)) {
        final data = utf8.encode(fixed);
        out.addFile(ArchiveFile(f.name, data.length, data));
      } else if (f.isFile) {
        out.addFile(ArchiveFile(f.name, f.size, f.content));
      } else {
        out.addFile(ArchiveFile(f.name, 0, <int>[])..isFile = false);
      }
    }
    final encoded = ZipEncoder().encode(out);
    if (encoded == null) return bytes;
    return Uint8List.fromList(encoded);
  } catch (_) {
    return bytes;
  }
}

final _numFmtTag = RegExp(r'<numFmt\b[^>]*?/>|<numFmt\b[^>]*?>\s*</numFmt>');
final _numFmtId = RegExp(r'''numFmtId\s*=\s*["'](\d+)["']''');
final _numFmtsBlock = RegExp(r'<numFmts\b([^>]*?)(/>|>([\s\S]*?)</numFmts>)');
final _countAttr = RegExp(r'''\s*count\s*=\s*["']\d+["']''');

/// Pure string step of [sanitizeXlsxBytes] (exposed for tests).
String stripBuiltInNumFmts(String xml) {
  return xml.replaceAllMapped(_numFmtsBlock, (m) {
    final attrs = m.group(1) ?? '';
    final inner = m.group(3) ?? '';
    var removed = 0;
    var kept = 0;
    final newInner = inner.replaceAllMapped(_numFmtTag, (t) {
      final id = int.tryParse(_numFmtId.firstMatch(t.group(0)!)?.group(1) ?? '');
      if (id != null && id < 164) {
        removed++;
        return '';
      }
      kept++;
      return t.group(0)!;
    });
    if (removed == 0) return m.group(0)!;
    if (kept == 0) return '';
    final newAttrs = attrs.replaceFirst(_countAttr, ' count="$kept"');
    return '<numFmts$newAttrs>$newInner</numFmts>';
  });
}
