/// Canonical JSON for signed snapshots and query results (ARCHITECTURE-M
/// ADR-M2 "Integrity of figures"): UTF-8, object keys sorted by UTF-16 code
/// units (as RFC 8785), no insignificant whitespace, amounts as decimal
/// strings and timestamps as ISO-8601 UTC strings. The desktop signs these
/// exact bytes; the phone re-encodes the received payload and verifies.
library;

import 'dart:convert';

/// Thrown for values that have no single canonical form.
class CanonicalJsonException implements Exception {
  CanonicalJsonException(this.message);
  final String message;
  @override
  String toString() => 'CanonicalJsonException: $message';
}

/// Encodes [value] canonically. Allowed: `null`, `bool`, `int`, `String`,
/// `DateTime` (written as ISO-8601 UTC), `List`, `Map` with `String` keys.
/// Doubles are rejected: amounts must travel as decimal strings so the
/// signer and the verifier never disagree on a float's text form.
String canonicalJson(Object? value) {
  final out = StringBuffer();
  _write(out, value, r'$');
  return out.toString();
}

/// UTF-8 bytes of [canonicalJson] — the exact bytes that are signed.
List<int> canonicalJsonBytes(Object? value) => utf8.encode(canonicalJson(value));

void _write(StringBuffer out, Object? v, String path) {
  switch (v) {
    case null:
      out.write('null');
    case bool b:
      out.write(b ? 'true' : 'false');
    case int i:
      out.write(i.toString());
    case double _:
      throw CanonicalJsonException('double at $path: send amounts as decimal strings');
    case String s:
      out.write(jsonEncode(s));
    case DateTime d:
      out.write(jsonEncode(d.toUtc().toIso8601String()));
    case List<Object?> l:
      out.write('[');
      for (var i = 0; i < l.length; i++) {
        if (i > 0) out.write(',');
        _write(out, l[i], '$path[$i]');
      }
      out.write(']');
    case Map<Object?, Object?> m:
      final keys = <String>[];
      for (final k in m.keys) {
        if (k is! String) throw CanonicalJsonException('non-string key at $path');
        keys.add(k);
      }
      keys.sort();
      out.write('{');
      for (var i = 0; i < keys.length; i++) {
        if (i > 0) out.write(',');
        out
          ..write(jsonEncode(keys[i]))
          ..write(':');
        _write(out, m[keys[i]], '$path.${keys[i]}');
      }
      out.write('}');
    default:
      throw CanonicalJsonException('unsupported ${v.runtimeType} at $path');
  }
}
