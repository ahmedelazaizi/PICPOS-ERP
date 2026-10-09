// قناة JSON لبروتوكول drift remote فوق WebSocket (نصوص).
//
// بروتوكول drift remote يمرّر قوائم متداخلة فيها `Uint8List`/`BigInt`/أعداد
// كبيرة، وكلّها لا تعبر JSON كما هي. فيُرمَّز كلٌّ منها بكائنٍ أحاديّ المفتاح
// يبدأ مفتاحه بـ`$` (وسم خاص)، ويُفكَّ عند الطرف الآخر:
//
//   Uint8List -> {"$u8": "<base64>"}
//   BigInt    -> {"$big": "<decimal>"}
//   DateTime  -> {"$dt": [microsSinceEpoch, isUtc]}
//   int > 2^53 -> {"$i": "<decimal>"}   (يحفظ الدقّة عند طرف JS)
//   NaN/±Inf  -> {"$d": "nan" | "inf" | "-inf"}
//   خريطة فيها مفتاح يبدأ بـ`$` -> {"$m": {...}}   (تهريب كي لا تُقرأ وسماً)
//
// الطرفان يجب أن يستخدما **نفس إصدار drift** (البروتوكول تجريبي).

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:async/async.dart' show StreamSinkTransformer;
import 'package:stream_channel/stream_channel.dart';

/// 2^53 - 1: أكبر عدد صحيح يُمثَّل بدقّة في JavaScript.
const int _maxSafeInt = 9007199254740991;

/// يحوّل [socket] (قناة نصوص، مثل `WebSocketChannel`) إلى قناة كائنات
/// لبروتوكول drift remote: كلّ رسالة تُرمَّز نصّ JSON واحداً.
///
/// مرّر الناتج إلى `DriftServer.serve(channel)` أو
/// `connectToRemoteAndInitialize(channel)` (بالقيمة الافتراضية `serialize: true`
/// على الطرفين).
StreamChannel<Object?> driftJsonChannel(StreamChannel<dynamic> socket) {
  return socket.cast<String>().transform(
    StreamChannelTransformer<Object?, String>(
      StreamTransformer<String, Object?>.fromHandlers(
        handleData: (text, sink) => sink.add(decodeDriftMessage(text)),
      ),
      StreamSinkTransformer<Object?, String>.fromHandlers(
        handleData: (message, sink) => sink.add(encodeDriftMessage(message)),
      ),
    ),
  );
}

/// ترميز رسالة drift إلى نصّ JSON آمن.
String encodeDriftMessage(Object? message) => jsonEncode(_encode(message));

/// فكّ نصّ JSON إلى رسالة drift (عكس [encodeDriftMessage]).
Object? decodeDriftMessage(String text) => _decode(jsonDecode(text));

Object? _encode(Object? v) {
  if (v == null || v is bool || v is String) return v;
  if (v is int) {
    return v.abs() > _maxSafeInt ? {r'$i': v.toString()} : v;
  }
  if (v is double) {
    if (v.isNaN) return {r'$d': 'nan'};
    if (v.isInfinite) return {r'$d': v.isNegative ? '-inf' : 'inf'};
    return v;
  }
  if (v is BigInt) return {r'$big': v.toString()};
  if (v is DateTime) {
    return {
      r'$dt': [v.microsecondsSinceEpoch, v.isUtc],
    };
  }
  // Uint8List قبل List: هو نفسه List<int>.
  if (v is Uint8List) return {r'$u8': base64Encode(v)};
  if (v is List) return [for (final e in v) _encode(e)];
  if (v is Map) {
    final out = <String, Object?>{};
    var escape = false;
    for (final entry in v.entries) {
      final k = entry.key;
      if (k is! String) {
        throw ArgumentError('مفتاح خريطة غير نصّي: ${k.runtimeType}');
      }
      if (k.startsWith(r'$')) escape = true;
      out[k] = _encode(entry.value);
    }
    return escape ? {r'$m': out} : out;
  }
  throw ArgumentError('نوع غير مدعوم في قناة drift JSON: ${v.runtimeType}');
}

Object? _decode(Object? v) {
  if (v is List) return [for (final e in v) _decode(e)];
  if (v is Map) {
    if (v.length == 1) {
      final key = v.keys.single as String;
      final value = v.values.single;
      switch (key) {
        case r'$u8':
          return base64Decode(value as String);
        case r'$big':
          return BigInt.parse(value as String);
        case r'$i':
          return int.parse(value as String);
        case r'$d':
          return switch (value) {
            'nan' => double.nan,
            'inf' => double.infinity,
            '-inf' => double.negativeInfinity,
            _ => throw FormatException('قيمة \$d غير معروفة: $value'),
          };
        case r'$dt':
          final parts = value as List;
          return DateTime.fromMicrosecondsSinceEpoch(
            (parts[0] as num).toInt(),
            isUtc: parts[1] as bool,
          );
        case r'$m':
          return {
            for (final e in (value as Map).entries)
              e.key as String: _decode(e.value),
          };
      }
      if (key.startsWith(r'$')) {
        throw FormatException('وسم غير معروف في قناة drift JSON: $key');
      }
    }
    return {for (final e in v.entries) e.key as String: _decode(e.value)};
  }
  return v;
}
