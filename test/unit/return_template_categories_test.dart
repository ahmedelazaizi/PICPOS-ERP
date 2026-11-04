import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:picpos_erp/data/database/database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;

  setUp(() async {
    db = AppDatabase.forTesting();
    await db.seedDefaultTemplates();
  });
  tearDown(() => db.close());

  test(
    'sales return assets import their explicit sales_return category',
    () async {
      for (final (file, type) in const [
        ('thermal80_sales_return.json', 'thermal'),
        ('a4_sales_return.json', 'a4'),
      ]) {
        final json = await rootBundle.loadString(
          'assets/invoice_templates/$file',
        );
        final id = await db.importTemplateFromJson(json);
        final imported = (await db.getTemplateById(id))!;

        expect(imported.type, type, reason: file);
        expect(imported.templateCategory, 'sales_return', reason: file);
      }
    },
  );
}
