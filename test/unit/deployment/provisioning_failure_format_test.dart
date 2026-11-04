// تشخيصُ الإقلاع: سطرُ `ADOPT-FAIL` و`RECONCILE-FAIL` يحمل نوعَ الاستثناء
// ونصَّه الكامل وموضعَ خطأ PostgreSQL، دون أن يكشف قيماً طويلةً (tokens /
// كلمات مرور)، وبحجمٍ مقطوعٍ عند 2000 حرف، ودون أن يرمي أبداً.
import 'package:flutter_test/flutter_test.dart';
import 'package:postgres/messages.dart';
// الباني الداخليّ لـ`ServerException` غيرُ مُصدَّر من `postgres.dart`، والاختبارُ
// وحدَه يحتاجه لبناء استثناءٍ حقيقيٍّ بحقول الخادم (ليس تقليداً).
// ignore: implementation_imports
import 'package:postgres/src/exceptions.dart' show buildExceptionFromErrorFields;

import 'package:picpos_erp/services/deployment/provisioning_applier.dart';

/// toString يرمي — الدالةُ لا يجوز أن ترمي بدورها داخل `catch`.
class _ThrowingToString implements Exception {
  @override
  String toString() => throw StateError('boom');
}

void main() {
  group('describeFailureForLog', () {
    test('plain exception: type, full message, one line, stack capped at 12',
        () {
      final out = describeFailureForLog(
        Exception('plain failure'),
        StackTrace.current,
      );
      expect(out, startsWith('type=_Exception; msg=Exception: plain failure'));
      expect(out, isNot(contains('\n')));
      final frames = RegExp(r'#\d+\s').allMatches(out).length;
      expect(frames, inInclusiveRange(1, 12));
      expect(out, contains('Documents/server_errors.log'));
    });

    test('message longer than 2000 chars is clipped, not dropped', () {
      final out = describeFailureForLog(
        Exception('x' * 5000),
        StackTrace.current,
      );
      expect(out.length, lessThan(2000 + 40));
      expect(out, startsWith('type=_Exception; msg=Exception: xxxx'));
      expect(out, contains('...(+'));
    });

    test('ServerException: full toString and the error position are kept', () {
      final e = buildExceptionFromErrorFields([
        ErrorField(ErrorFieldId.severity, 'ERROR'),
        ErrorField(ErrorFieldId.code, '42601'),
        ErrorField(ErrorFieldId.message, 'syntax error at or near ","'),
        ErrorField(ErrorFieldId.position, '57'),
        ErrorField(ErrorFieldId.routine, 'scanner_yyerror'),
      ]);
      final out = describeFailureForLog(e, StackTrace.current);
      expect(out, contains('Severity.error 42601: syntax error at or near ","'));
      expect(out, contains('position=57'));
      expect(out, contains('routine=scanner_yyerror'));
      expect(out, isNot(contains('\n')));
    });

    test('ServerException: long SQL literals (secrets) are masked, short '
        'punctuation literals are kept', () {
      const secret = 'tok-ABCDEFGH12';
      final e = buildExceptionFromErrorFields([
        ErrorField(ErrorFieldId.severity, 'ERROR'),
        ErrorField(ErrorFieldId.code, '42601'),
        ErrorField(ErrorFieldId.message, 'syntax error at or near ","'),
        ErrorField(ErrorFieldId.internalQuery, "SELECT '$secret' , ','"),
      ]);
      final out = describeFailureForLog(e, StackTrace.current);
      expect(out, isNot(contains(secret)));
      expect(out, contains("'<${secret.length} chars>'"));
      expect(out, contains("','"));
    });

    test('never throws: a failing toString still yields a one-line entry', () {
      final out =
          describeFailureForLog(_ThrowingToString(), StackTrace.current);
      expect(out, contains('failure description unavailable'));
      expect(out, isNot(contains('\n')));
    });
  });
}
