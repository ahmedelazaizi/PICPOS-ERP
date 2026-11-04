// S-02: تعقيم clientName في مسار نسخة العميل الاحتياطية.
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:picpos_erp/services/api/backup_path_guard.dart';

void main() {
  final dir = p.join(p.current, 'build', 'test_backup_clients');
  const ts = '2026-10-30T10-00-00';
  final safe = RegExp(r'^[A-Za-z0-9_-]+$');

  final attacks = <String, String>{
    'dotdot slash': '../../evil',
    'dotdot backslash': r'..\..\evil',
    'only dotdot': '..',
    'leading dot': '.hidden',
    'absolute posix': '/etc/passwd',
    'absolute windows': r'C:\Windows\system32\x',
    'unc': r'\\server\share\x',
    'null byte': 'a\u0000b',
    'newline/control': 'a\r\nb\u001b[0m',
    'arabic': 'عميل-١',
    'emoji': 'pos😀',
    'fullwidth dots': '．．／evil',
    'colon stream': 'a:b:\$DATA',
  };

  group('sanitizeBackupClientName', () {
    attacks.forEach((label, raw) {
      test('neutralises $label', () {
        final s = sanitizeBackupClientName(raw);
        expect(s, matches(safe));
        expect(s.length, lessThanOrEqualTo(kBackupClientNameMaxLength));
      });
    });

    test('keeps legitimate names', () {
      expect(sanitizeBackupClientName('Shop-01_main'), 'Shop-01_main');
    });

    test('null/empty become unknown, long names are cut to 40', () {
      expect(sanitizeBackupClientName(null), 'unknown');
      expect(sanitizeBackupClientName(''), 'unknown');
      expect(sanitizeBackupClientName('a' * 500).length, 40);
    });
  });

  group('resolveBackupFilePath', () {
    attacks.forEach((label, raw) {
      test('$label stays inside the backup dir', () {
        final path = resolveBackupFilePath(dir, raw, ts);
        expect(path, isNotNull);
        expect(p.isWithin(dir, path!), isTrue);
        expect(p.dirname(path), p.normalize(p.absolute(dir)));
        expect(p.basename(path), endsWith('_$ts.sqlite'));
      });
    });

    test('ordinary name gives the expected file', () {
      expect(p.basename(resolveBackupFilePath(dir, 'shop1', ts)!),
          'backup_shop1_$ts.sqlite');
    });
  });
}
