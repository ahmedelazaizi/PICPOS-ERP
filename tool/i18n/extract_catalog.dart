import 'dart:convert';
import 'dart:io';

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';

class CatalogOccurrence {
  const CatalogOccurrence({required this.key, required this.firstUse});
  final String key;
  final String firstUse;
}

class _CatalogVisitor extends RecursiveAstVisitor<void> {
  _CatalogVisitor(this.source, this.path);
  final String source;
  final String path;
  final occurrences = <String, CatalogOccurrence>{};

  @override
  void visitMethodInvocation(MethodInvocation node) {
    if (node.methodName.name != 'tr' || node.argumentList.arguments.isEmpty) {
      super.visitMethodInvocation(node);
      return;
    }
    final argument = node.argumentList.arguments.first;
    if (argument is SimpleStringLiteral && argument.stringValue != null) {
      final line = '\n'.allMatches(source.substring(0, node.offset)).length + 1;
      occurrences.putIfAbsent(
        argument.stringValue!,
        () => CatalogOccurrence(key: argument.stringValue!, firstUse: '$path:$line'),
      );
    }
    super.visitMethodInvocation(node);
  }
}

Map<String, CatalogOccurrence> extractCatalogFromSources(
  Map<String, String> sources,
) {
  final result = <String, CatalogOccurrence>{};
  for (final entry in sources.entries) {
    try {
      final parse = parseString(content: entry.value, path: entry.key);
      final visitor = _CatalogVisitor(entry.value, entry.key);
      parse.unit.accept(visitor);
      for (final item in visitor.occurrences.entries) {
        result.putIfAbsent(item.key, () => item.value);
      }
    } catch (error) {
      throw StateError('Could not parse ${entry.key}: $error');
    }
  }
  return result;
}

Map<String, String> catalogKeySetFromSources(Map<String, String> sources) => {
      for (final key in extractCatalogFromSources(sources).keys) key: key,
    };

Future<void> main() async {
  final root = Directory.current;
  final sources = <String, String>{};
  await for (final entity in Directory('${root.path}${Platform.pathSeparator}lib')
      .list(recursive: true, followLinks: false)
      .where((entity) => entity is File && entity.path.endsWith('.dart'))) {
    final file = entity as File;
    sources[_relative(root.path, file.path)] = await file.readAsString();
  }
  final occurrences = extractCatalogFromSources(sources);
  final catalogPath = File('${root.path}/assets/i18n/catalog_ar.json');
  final englishPath = File('${root.path}/assets/i18n/en.json');
  final english = _readObject(englishPath);
  for (final key in occurrences.keys) {
    english.putIfAbsent(key, () => '');
  }
  await catalogPath.writeAsString(
    const JsonEncoder.withIndent('  ').convert({}),
  );
  final firstUse = <String, String>{
    for (final key in occurrences.keys.toList()..sort())
      key: occurrences[key]!.firstUse,
  };
  await catalogPath.writeAsString(
    '${const JsonEncoder.withIndent('  ').convert(firstUse)}\n',
  );
  await englishPath.writeAsString(
    '${const JsonEncoder.withIndent('  ').convert(_sorted(english))}\n',
  );
  await _writeReview(root, occurrences, english);
  stdout.writeln('catalog_keys=${occurrences.length}');
  stdout.writeln('english_entries=${english.length}');
}

Map<String, String> _readObject(File file) {
  if (!file.existsSync()) return <String, String>{};
  final decoded = jsonDecode(file.readAsStringSync());
  if (decoded is! Map<String, dynamic>) {
    throw const FormatException('en.json must contain an object');
  }
  return {
    for (final entry in decoded.entries) entry.key: entry.value?.toString() ?? '',
  };
}

Map<String, String> _sorted(Map<String, String> values) {
  final keys = values.keys.toList()..sort();
  return {for (final key in keys) key: values[key]!};
}

Future<void> _writeReview(
  Directory root,
  Map<String, CatalogOccurrence> occurrences,
  Map<String, String> english,
) async {
  final file = File('${root.path}/docs/i18n/translation_review.csv');
  final rows = <String>['arabic,english,first_use,status'];
  for (final key in occurrences.keys.toList()..sort()) {
    final value = english[key] ?? '';
    rows.add([
      _csv(key),
      _csv(value),
      _csv(occurrences[key]!.firstUse),
      value.isEmpty ? 'pending' : 'translated',
    ].join(','));
  }
  await file.writeAsString('${rows.join('\n')}\n');
}

String _csv(String value) => '"${value.replaceAll('"', '""')}"';

String _relative(String root, String path) =>
    path.substring(root.length + 1).replaceAll('\\', '/');
